create table if not exists public.marketplace_orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete restrict,
  status text not null default 'pending' check (status in ('pending', 'paid', 'failed', 'cancelled', 'expired')),
  total_amount bigint not null check (total_amount > 0),
  payment_phone text not null,
  provider_transaction_id text unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '20 minutes')
);

create table if not exists public.marketplace_order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.marketplace_orders(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  product_title text not null,
  unit_price bigint not null check (unit_price > 0),
  quantity integer not null check (quantity between 1 and 10),
  created_at timestamptz not null default now()
);

create index if not exists marketplace_orders_user_created_idx
  on public.marketplace_orders (user_id, created_at desc);
create index if not exists marketplace_order_items_order_idx
  on public.marketplace_order_items (order_id);

alter table public.marketplace_orders enable row level security;
alter table public.marketplace_order_items enable row level security;
revoke all on public.marketplace_orders, public.marketplace_order_items from public, anon, authenticated;
grant select on public.marketplace_orders, public.marketplace_order_items to authenticated;

create policy "Supporters read their marketplace orders"
  on public.marketplace_orders for select to authenticated
  using (user_id = (select auth.uid()));
create policy "Supporters read their marketplace order items"
  on public.marketplace_order_items for select to authenticated
  using (exists (
    select 1 from public.marketplace_orders o
    where o.id = marketplace_order_items.order_id and o.user_id = (select auth.uid())
  ));

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

  -- Release expired reservations before checking stock for this cart.
  for v_line in
    select o.id from public.marketplace_orders o
    where o.status = 'pending' and o.expires_at <= now() for update
  loop
    update public.products p set stock = coalesce(p.stock, 0) + i.quantity, updated_at = now()
    from public.marketplace_order_items i
    where i.order_id = v_line.id and i.product_id = p.id;
    update public.marketplace_orders set status = 'expired', updated_at = now() where id = v_line.id;
  end loop;

  -- Lock products in a stable order, then reject the whole order if any line cannot be reserved.
  perform p.id from public.products p
  join (select (i->>'product_id')::uuid id from jsonb_array_elements(p_items) i group by 1) requested on requested.id = p.id
  order by p.id for update of p;

  if exists (
    select 1 from (
      select (i->>'product_id')::uuid id, sum((i->>'quantity')::integer)::integer quantity
      from jsonb_array_elements(p_items) i group by 1
    ) requested
    left join public.products p on p.id = requested.id
    where p.id is null or not p.is_active or coalesce(p.stock, 0) < requested.quantity
      or p.price <= 0 or p.price <> trunc(p.price)
  ) then raise exception 'product unavailable or insufficient stock'; end if;

  select sum(p.price::bigint * requested.quantity)::bigint into v_total
  from (select (i->>'product_id')::uuid id, sum((i->>'quantity')::integer)::integer quantity
        from jsonb_array_elements(p_items) i group by 1) requested
  join public.products p on p.id = requested.id;
  if v_total is null or v_total <= 0 then raise exception 'invalid order amount'; end if;

  insert into public.marketplace_orders(id, user_id, total_amount, payment_phone)
  values (v_order_id, p_user_id, v_total, p_phone);
  insert into public.marketplace_order_items(order_id, product_id, product_title, unit_price, quantity)
  select v_order_id, p.id, p.title, p.price::bigint, requested.quantity
  from (select (i->>'product_id')::uuid id, sum((i->>'quantity')::integer)::integer quantity
        from jsonb_array_elements(p_items) i group by 1) requested
  join public.products p on p.id = requested.id;
  update public.products p set stock = coalesce(p.stock, 0) - requested.quantity, updated_at = now()
  from (select (i->>'product_id')::uuid id, sum((i->>'quantity')::integer)::integer quantity
        from jsonb_array_elements(p_items) i group by 1) requested
  where p.id = requested.id;
  return query select v_order_id, v_total;
end;
$$;

create or replace function public.fail_marketplace_order(p_order_id uuid)
returns boolean language plpgsql security definer set search_path = public, pg_temp as $$
declare v_status text;
begin
  select status into v_status from public.marketplace_orders where id = p_order_id for update;
  if not found or v_status <> 'pending' then return false; end if;
  update public.products p set stock = coalesce(p.stock, 0) + i.quantity, updated_at = now()
  from public.marketplace_order_items i where i.order_id = p_order_id and i.product_id = p.id;
  update public.marketplace_orders set status = 'failed', updated_at = now()
  where id = p_order_id and status = 'pending';
  return true;
end;
$$;

create or replace function public.confirm_marketplace_order(
  p_order_id uuid, p_transaction_id text, p_amount bigint
) returns text language plpgsql security definer set search_path = public, pg_temp as $$
declare v_order public.marketplace_orders%rowtype;
begin
  select * into v_order from public.marketplace_orders where id = p_order_id for update;
  if not found then return 'not_found'; end if;
  if v_order.status = 'paid' and v_order.provider_transaction_id = p_transaction_id then return 'duplicate'; end if;
  if v_order.status <> 'pending' then return 'not_pending'; end if;
  if v_order.total_amount <> p_amount then return 'amount_mismatch'; end if;
  update public.marketplace_orders set status = 'paid', provider_transaction_id = p_transaction_id,
    updated_at = now() where id = p_order_id and status = 'pending';
  return 'paid';
end;
$$;

revoke all on function public.reserve_marketplace_order(uuid, text, jsonb) from public, anon, authenticated;
revoke all on function public.fail_marketplace_order(uuid) from public, anon, authenticated;
revoke all on function public.confirm_marketplace_order(uuid, text, bigint) from public, anon, authenticated;
grant execute on function public.reserve_marketplace_order(uuid, text, jsonb) to service_role;
grant execute on function public.fail_marketplace_order(uuid) to service_role;
grant execute on function public.confirm_marketplace_order(uuid, text, bigint) to service_role;
