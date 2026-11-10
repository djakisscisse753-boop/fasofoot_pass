-- Migration pour la gestion de la capacité des stades et la tarification par catégorie

-- 1. Ajout de colonnes de capacité et de suivi des ventes dans ticket_catalog
alter table public.ticket_catalog
  add column if not exists total_capacity integer not null default 100 check (total_capacity >= 0),
  add column if not exists tickets_sold integer not null default 0 check (tickets_sold >= 0);

-- 2. Table des zones de stade standard si elle n'existe pas encore
create table if not exists public.stadium_zones (
  id uuid primary key default gen_random_uuid(),
  stadium_id uuid not null references public.stadiums(id) on delete cascade,
  zone_name text not null,
  capacity integer not null check (capacity >= 0),
  created_at timestamptz not null default now(),
  unique (stadium_id, zone_name)
);

create unique index if not exists stadium_zones_stadium_zone_key
  on public.stadium_zones (stadium_id, zone_name);

-- Les zones dépendent du stade et son schéma varie selon l'installation.
-- Les catégories vendables sont configurées dans ticket_catalog ci-dessous.

-- 3. Table des catégories de tickets par match si elle n'existe pas encore
create table if not exists public.match_ticket_categories (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  zone_id uuid not null references public.stadium_zones(id) on delete cascade,
  price numeric not null check (price > 0),
  total_tickets_offered integer not null check (total_tickets_offered >= 0),
  tickets_sold integer not null default 0 check (tickets_sold >= 0),
  created_at timestamptz not null default now()
);

do $$ begin
  alter table public.match_ticket_categories add constraint match_ticket_categories_match_zone_key unique (match_id, zone_id);
exception when others then null;
end $$;

-- 4. Droits RLS pour que les administrateurs puissent gérer le catalogue et les catégories
grant select, insert, update, delete on public.ticket_catalog to authenticated;
grant select, insert, update, delete on public.match_ticket_categories to authenticated;
grant select, insert, update on public.stadium_zones to authenticated;

do $$ begin
  create policy "Admins manage ticket catalog"
    on public.ticket_catalog for all to authenticated
    using (exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid())
        and p.role::text in ('admin_competition', 'super_admin')
    ))
    with check (exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid())
        and p.role::text in ('admin_competition', 'super_admin')
    ));
exception when duplicate_object then null;
end $$;

do $$ begin
  create policy "Admins manage match ticket categories"
    on public.match_ticket_categories for all to authenticated
    using (exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid())
        and p.role::text in ('admin_competition', 'super_admin')
    ))
    with check (exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid())
        and p.role::text in ('admin_competition', 'super_admin')
    ));
exception when duplicate_object then null;
end $$;

-- 5. Mise à jour de la fonction reserve_ticket pour supporter à la fois match_ticket_categories et ticket_catalog direct
create or replace function public.reserve_ticket(
  p_match_id uuid,
  p_category_name text,
  p_customer_name text,
  p_customer_phone text,
  p_user_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_price integer;
  v_capacity integer;
  v_category_sold integer;
  v_paid_count bigint;
  v_reserved_count bigint;
  v_sold integer;
  v_match_status text;
  v_match_date timestamptz;
  v_ticket public.tickets%rowtype;
begin
  select status, date_time into v_match_status, v_match_date
  from public.matches where id = p_match_id;
  if not found then
    return jsonb_build_object('success', false, 'reason', 'match_missing', 'message', 'Match introuvable.');
  end if;
  if v_match_status in ('cancelled', 'postponed', 'finished') or v_match_date <= now() then
    return jsonb_build_object('success', false, 'reason', 'sales_closed', 'message', 'La vente des billets pour ce match est fermée.');
  end if;

  -- 1. Chercher d'abord dans match_ticket_categories
  select category.price::integer, category.total_tickets_offered, coalesce(category.tickets_sold, 0)
  into v_price, v_capacity, v_category_sold
  from public.match_ticket_categories category
  join public.stadium_zones zone on zone.id = category.zone_id
  where category.match_id = p_match_id and zone.zone_name = p_category_name
  for update of category;

  -- 2. Si pas trouvé, chercher directement dans ticket_catalog
  if not found or v_price is null or v_capacity is null then
    select tc.price, tc.total_capacity, coalesce(tc.tickets_sold, 0)
    into v_price, v_capacity, v_category_sold
    from public.ticket_catalog tc
    where tc.match_id = p_match_id and tc.category_name = p_category_name and tc.is_active = true
    for update of tc;
  end if;

  if not found or v_price is null or v_price <= 0 or v_capacity is null or v_capacity <= 0 then
    return jsonb_build_object('success', false, 'reason', 'category_unavailable', 'message', 'Cette catégorie de billets n’est pas disponible.');
  end if;

  -- Compter les billets confirmés et les réservations actives
  select count(*) into v_paid_count
  from public.tickets
  where match_id = p_match_id and category_name = p_category_name
    and status in ('paid', 'used');

  select count(*) into v_reserved_count
  from public.tickets
  where match_id = p_match_id and category_name = p_category_name
    and status = 'pending' and payment_expires_at > now();

  v_sold := greatest(v_category_sold, v_paid_count::integer);
  if v_sold + v_reserved_count >= v_capacity then
    -- Marquer la catégorie comme inactive si épuisée
    update public.ticket_catalog
    set is_active = false
    where match_id = p_match_id and category_name = p_category_name;

    return jsonb_build_object('success', false, 'reason', 'sold_out', 'message', 'Cette catégorie vient d’être épuisée.');
  end if;

  insert into public.tickets (
    match_id, user_id, category_name, customer_name, customer_phone,
    price, status, payment_expires_at
  ) values (
    p_match_id, p_user_id, p_category_name, p_customer_name, p_customer_phone,
    v_price, 'pending', now() + interval '15 minutes'
  ) returning * into v_ticket;

  return jsonb_build_object('success', true, 'ticket_id', v_ticket.id, 'price', v_ticket.price);
end;
$$;

revoke all on function public.reserve_ticket(uuid, text, text, text, uuid) from public, anon, authenticated;
grant execute on function public.reserve_ticket(uuid, text, text, text, uuid) to service_role;
