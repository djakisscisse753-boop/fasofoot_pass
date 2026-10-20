alter table public.clubs
  add column if not exists marketing_phone text,
  add column if not exists headquarters_address text;

alter table public.clubs
  add constraint clubs_marketing_phone_length_check
    check (marketing_phone is null or char_length(marketing_phone) between 8 and 24),
  add constraint clubs_headquarters_address_length_check
    check (headquarters_address is null or char_length(headquarters_address) <= 250);

alter table public.clubs enable row level security;
revoke all on public.clubs from public, anon, authenticated;
grant select on public.clubs to anon, authenticated;
grant update (marketing_phone, headquarters_address) on public.clubs to authenticated;
drop policy if exists "Club admins update their handoff details" on public.clubs;
create policy "Club admins update their handoff details"
  on public.clubs for update to authenticated
  using (exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and (p.role::text = 'super_admin'
        or (p.role::text = 'admin_club' and p.managed_club_id = clubs.id))
  ))
  with check (exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and (p.role::text = 'super_admin'
        or (p.role::text = 'admin_club' and p.managed_club_id = clubs.id))
  ));

alter table public.marketplace_order_items
  add column if not exists club_id_snapshot uuid,
  add column if not exists club_name text not null default 'Club partenaire',
  add column if not exists club_city text,
  add column if not exists marketing_phone text,
  add column if not exists headquarters_address text,
  add column if not exists fulfillment_status text not null default 'awaiting_contact';
alter table public.marketplace_order_items
  add constraint marketplace_order_items_fulfillment_status_check
    check (fulfillment_status in ('awaiting_contact', 'contacted', 'pickup_agreed', 'completed', 'cancelled')),
  add constraint marketplace_order_items_club_phone_length_check
    check (marketing_phone is null or char_length(marketing_phone) between 8 and 24),
  add constraint marketplace_order_items_club_address_length_check
    check (headquarters_address is null or char_length(headquarters_address) <= 250);

update public.marketplace_order_items i
set club_id_snapshot = p.club_id,
    club_name = coalesce(c.name, i.club_name),
    club_city = c.city,
    marketing_phone = c.marketing_phone,
    headquarters_address = c.headquarters_address
from public.products p
left join public.clubs c on c.id = p.club_id
where i.product_id = p.id;

create policy "Club admins read their marketplace order lines"
  on public.marketplace_order_items for select to authenticated
  using (exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and (p.role::text = 'super_admin'
        or (p.role::text = 'admin_club' and p.managed_club_id = marketplace_order_items.club_id_snapshot))
  ));
create policy "Club admins update their order fulfillment"
  on public.marketplace_order_items for update to authenticated
  using (exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and (p.role::text = 'super_admin'
        or (p.role::text = 'admin_club' and p.managed_club_id = marketplace_order_items.club_id_snapshot))
  ))
  with check (exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and (p.role::text = 'super_admin'
        or (p.role::text = 'admin_club' and p.managed_club_id = marketplace_order_items.club_id_snapshot))
  ));
grant update (fulfillment_status) on public.marketplace_order_items to authenticated;

create or replace function public.is_marketplace_club_order_admin(p_order_id uuid)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from public.profiles p
    join public.marketplace_order_items i on i.order_id = p_order_id
    where p.id = (select auth.uid())
      and (p.role::text = 'super_admin'
        or (p.role::text = 'admin_club' and p.managed_club_id = i.club_id_snapshot))
  );
$$;
revoke all on function public.is_marketplace_club_order_admin(uuid) from public, anon;
grant execute on function public.is_marketplace_club_order_admin(uuid) to authenticated;
create policy "Club admins read their marketplace orders"
  on public.marketplace_orders for select to authenticated
  using (public.is_marketplace_club_order_admin(id));

create or replace function public.reserve_marketplace_order(
  p_user_id uuid,
  p_phone text,
  p_items jsonb
) returns table(order_id uuid, total_amount bigint)
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_order_id uuid := gen_random_uuid();
  v_total bigint;
  v_line record;
begin
  if p_user_id is null or p_phone !~ '^(\+?226)?[0-9]{8}$' then
    raise exception 'invalid buyer details';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) < 1 or jsonb_array_length(p_items) > 20 then
    raise exception 'invalid cart';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_items) i
    where coalesce(i->>'product_id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      or coalesce(i->>'quantity', '') !~ '^[0-9]+$'
      or (i->>'quantity')::integer not between 1 and 10
  ) then raise exception 'invalid cart line'; end if;

  for v_line in
    select o.id from public.marketplace_orders o
    where o.status = 'pending' and o.expires_at <= now() for update
  loop
    update public.products p set stock = coalesce(p.stock, 0) + i.quantity, updated_at = now()
    from public.marketplace_order_items i
    where i.order_id = v_line.id and i.product_id = p.id;
    update public.marketplace_orders set status = 'expired', updated_at = now() where id = v_line.id;
  end loop;

  perform p.id from public.products p
  join (select (i->>'product_id')::uuid id from jsonb_array_elements(p_items) i group by 1) requested on requested.id = p.id
  order by p.id for update of p;

  if exists (
    select 1 from (
      select (i->>'product_id')::uuid id, sum((i->>'quantity')::integer)::integer quantity
      from jsonb_array_elements(p_items) i group by 1
    ) requested
    left join public.products p on p.id = requested.id
    left join public.clubs c on c.id = p.club_id
    where p.id is null or not p.is_active or coalesce(p.stock, 0) < requested.quantity
      or p.price <= 0 or p.price <> trunc(p.price)
      or (nullif(btrim(c.marketing_phone), '') is null
        and nullif(btrim(c.headquarters_address), '') is null)
  ) then raise exception 'product unavailable or insufficient stock'; end if;

  select sum(p.price::bigint * requested.quantity)::bigint into v_total
  from (select (i->>'product_id')::uuid id, sum((i->>'quantity')::integer)::integer quantity
        from jsonb_array_elements(p_items) i group by 1) requested
  join public.products p on p.id = requested.id;
  if v_total is null or v_total <= 0 then raise exception 'invalid order amount'; end if;

  insert into public.marketplace_orders(id, user_id, total_amount, payment_phone)
  values (v_order_id, p_user_id, v_total, p_phone);
  insert into public.marketplace_order_items(
    order_id, product_id, product_title, unit_price, quantity,
    club_id_snapshot, club_name, club_city, marketing_phone, headquarters_address
  )
  select v_order_id, p.id, p.title, p.price::bigint, requested.quantity,
         p.club_id, coalesce(c.name, 'Club partenaire'), c.city, c.marketing_phone, c.headquarters_address
  from (select (i->>'product_id')::uuid id, sum((i->>'quantity')::integer)::integer quantity
        from jsonb_array_elements(p_items) i group by 1) requested
  join public.products p on p.id = requested.id
  left join public.clubs c on c.id = p.club_id;
  update public.products p set stock = coalesce(p.stock, 0) - requested.quantity, updated_at = now()
  from (select (i->>'product_id')::uuid id, sum((i->>'quantity')::integer)::integer quantity
        from jsonb_array_elements(p_items) i group by 1) requested
  where p.id = requested.id;
  return query select v_order_id, v_total;
end;
$$;

revoke all on function public.reserve_marketplace_order(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function public.reserve_marketplace_order(uuid, text, jsonb) to service_role;
