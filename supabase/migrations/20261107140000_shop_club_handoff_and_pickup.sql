-- Ajout des informations de contact, itinéraire et retrait boutique pour les clubs et commandes

-- 1. Champs supplémentaires sur les clubs : nom du responsable et lien maps / itinéraire
alter table public.clubs
  add column if not exists manager_name text,
  add column if not exists maps_url text;

grant update (marketing_phone, headquarters_address, manager_name, maps_url) on public.clubs to authenticated;

-- 2. Champs supplémentaires sur les commandes boutique
alter table public.marketplace_orders
  add column if not exists customer_name text,
  add column if not exists pickup_code text;

-- 3. Champs supplémentaires sur les lignes de commande
alter table public.marketplace_order_items
  add column if not exists manager_name text,
  add column if not exists maps_url text;

-- 4. Fonction de réservation mise à jour pour inclure le nom du client et générer le code de retrait
drop function if exists public.reserve_marketplace_order(uuid, text, jsonb);
drop function if exists public.reserve_marketplace_order(uuid, text, jsonb, text);

create or replace function public.reserve_marketplace_order(
  p_user_id uuid,
  p_phone text,
  p_items jsonb,
  p_customer_name text default null
) returns table(order_id uuid, total_amount bigint, pickup_code text)
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_order_id uuid := gen_random_uuid();
  v_pickup_code text := 'RET-' || upper(substr(md5(random()::text), 1, 6));
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

  -- Libération des réservations expirées
  for v_line in
    select o.id from public.marketplace_orders o
    where o.status = 'pending' and o.expires_at <= now() for update
  loop
    update public.products p set stock = coalesce(p.stock, 0) + i.quantity, updated_at = now()
    from public.marketplace_order_items i
    where i.order_id = v_line.id and i.product_id = p.id;
    update public.marketplace_orders set status = 'expired', updated_at = now() where id = v_line.id;
  end loop;

  -- Verrouillage des produits commandés
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

  insert into public.marketplace_orders(id, user_id, total_amount, payment_phone, customer_name, pickup_code)
  values (v_order_id, p_user_id, v_total, p_phone, nullif(trim(p_customer_name), ''), v_pickup_code);

  insert into public.marketplace_order_items(
    order_id, product_id, product_title, unit_price, quantity,
    club_id_snapshot, club_name, club_city, marketing_phone, headquarters_address, manager_name, maps_url
  )
  select v_order_id, p.id, p.title, p.price::bigint, requested.quantity,
         p.club_id, coalesce(c.name, 'Club partenaire'), c.city, c.marketing_phone, c.headquarters_address,
         c.manager_name, c.maps_url
  from (select (i->>'product_id')::uuid id, sum((i->>'quantity')::integer)::integer quantity
        from jsonb_array_elements(p_items) i group by 1) requested
  join public.products p on p.id = requested.id
  left join public.clubs c on c.id = p.club_id;

  update public.products p set stock = coalesce(p.stock, 0) - requested.quantity, updated_at = now()
  from (select (i->>'product_id')::uuid id, sum((i->>'quantity')::integer)::integer quantity
        from jsonb_array_elements(p_items) i group by 1) requested
  where p.id = requested.id;

  return query select v_order_id, v_total, v_pickup_code;
end;
$$;

-- Compatibilité avec la signature à 3 arguments
create or replace function public.reserve_marketplace_order(
  p_user_id uuid,
  p_phone text,
  p_items jsonb
) returns table(order_id uuid, total_amount bigint, pickup_code text)
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  return query select * from public.reserve_marketplace_order(p_user_id, p_phone, p_items, null);
end;
$$;

revoke all on function public.reserve_marketplace_order(uuid, text, jsonb, text) from public, anon, authenticated;
grant execute on function public.reserve_marketplace_order(uuid, text, jsonb, text) to service_role;

revoke all on function public.reserve_marketplace_order(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function public.reserve_marketplace_order(uuid, text, jsonb) to service_role;

-- 5. Bucket de stockage pour les photos de produits si non existant
insert into storage.buckets (id, name, public)
values ('products', 'products', true)
on conflict (id) do update set public = true;

-- Droits de lecture publique pour les photos
do $$ begin
  create policy "Public product images read"
    on storage.objects for select to public
    using (bucket_id = 'products');
exception when others then null;
end $$;

-- Droits d'upload pour les admins
do $$ begin
  create policy "Authenticated users upload product images"
    on storage.objects for insert to authenticated
    with check (bucket_id = 'products');
exception when others then null;
end $$;
