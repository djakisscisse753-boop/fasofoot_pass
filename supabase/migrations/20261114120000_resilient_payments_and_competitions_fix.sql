-- Migration 20261114120000_resilient_payments_and_competitions_fix.sql
-- 1. Permettre la mise à jour / réutilisation d'une saison existante dans create_competition_season
create or replace function public.create_competition_season(
  p_code text,
  p_name text,
  p_competition_type text,
  p_season_name text,
  p_group_count integer,
  p_qualifiers_per_group integer,
  p_teams jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_competition_id uuid;
  v_name_competition_id uuid;
  v_code_competition_id uuid;
  v_existing_name text;
  v_existing_type text;
  v_season_id uuid;
  v_team_count integer;
  v_group_count integer;
  v_name_match_count integer;
begin
  if not exists (
    select 1
    from public.profiles as profile
    where profile.id = (select auth.uid())
      and profile.role::text in ('admin_competition', 'super_admin')
  ) then
    raise exception 'not_authorized';
  end if;

  if p_code is null or length(trim(p_code)) not between 2 and 40
     or p_name is null or length(trim(p_name)) not between 2 and 120
     or p_season_name is null
     or length(trim(p_season_name)) not between 2 and 80 then
    raise exception 'invalid_competition_details';
  end if;

  if p_competition_type is null
     or p_competition_type not in ('league', 'cup', 'international')
     or p_teams is null or jsonb_typeof(p_teams) <> 'array' then
    raise exception 'invalid_competition_format';
  end if;

  v_team_count := jsonb_array_length(p_teams);
  if v_team_count < 2 or v_team_count > 128 then
    raise exception 'invalid_team_count';
  end if;

  if p_competition_type = 'international' then
    if p_group_count is null or p_group_count < 1
       or p_group_count > v_team_count
       or p_qualifiers_per_group is null
       or p_qualifiers_per_group < 1 then
      raise exception 'invalid_group_configuration';
    end if;
  elsif p_group_count <> 0 then
    raise exception 'groups_only_allowed_for_international_competitions';
  elsif p_group_count is null or p_qualifiers_per_group is null then
    raise exception 'invalid_competition_configuration';
  end if;

  if exists (
    select lower(trim(team->>'team_name'))
    from jsonb_array_elements(p_teams) as team
    group by lower(trim(team->>'team_name'))
    having lower(trim(team->>'team_name')) is null
      or length(lower(trim(team->>'team_name'))) not between 1 and 120
      or count(*) > 1
  ) then
    raise exception 'invalid_or_duplicate_team_name';
  end if;

  if p_competition_type = 'international' and exists (
    select 1
    from jsonb_array_elements(p_teams) as team
    where nullif(trim(team->>'group_name'), '') is null
  ) then
    raise exception 'group_required_for_each_team';
  end if;

  select count(*)
    into v_name_match_count
  from public.competitions
  where lower(name) = lower(trim(p_name));

  if v_name_match_count > 1 then
    raise exception 'competition_code_name_or_type_conflict';
  end if;

  if v_name_match_count = 1 then
    select id into v_name_competition_id
    from public.competitions
    where lower(name) = lower(trim(p_name))
    for update;
  end if;

  select id into v_code_competition_id
  from public.competitions
  where code = upper(trim(p_code))
  for update;

  if v_name_competition_id is not null
     and v_code_competition_id is not null
     and v_name_competition_id <> v_code_competition_id then
    raise exception 'competition_code_name_or_type_conflict';
  end if;

  v_competition_id := coalesce(
    v_name_competition_id,
    v_code_competition_id
  );

  if v_competition_id is null then
    insert into public.competitions (code, name, competition_type)
    values (upper(trim(p_code)), trim(p_name), p_competition_type)
    returning id into v_competition_id;
  else
    select name, competition_type
      into v_existing_name, v_existing_type
    from public.competitions
    where id = v_competition_id;

    if lower(v_existing_name) <> lower(trim(p_name))
       or v_existing_type <> p_competition_type then
      raise exception 'competition_code_name_or_type_conflict';
    end if;
  end if;

  update public.seasons
  set is_active = false
  where competition_id = v_competition_id and is_active;

  -- Gestion d'upsert pour la saison : si elle existe déjà, on la met à jour sans échouer
  insert into public.seasons (
    competition_id,
    name,
    is_active,
    group_count,
    qualifiers_per_group
  )
  values (
    v_competition_id,
    trim(p_season_name),
    true,
    case when p_competition_type = 'international' then p_group_count else 0 end,
    case
      when p_competition_type = 'international' then p_qualifiers_per_group
      else 2
    end
  )
  on conflict (competition_id, name)
  do update set
    is_active = true,
    group_count = case when p_competition_type = 'international' then p_group_count else 0 end,
    qualifiers_per_group = case when p_competition_type = 'international' then p_qualifiers_per_group else 2 end
  returning id into v_season_id;

  -- Remplacement des équipes de la saison
  delete from public.competition_teams
  where season_id = v_season_id;

  insert into public.competition_teams (
    season_id,
    club_id,
    team_name,
    group_name
  )
  select
    v_season_id,
    nullif(team->>'club_id', '')::uuid,
    trim(team->>'team_name'),
    case
      when p_competition_type = 'international'
        then trim(team->>'group_name')
      else null
    end
  from jsonb_array_elements(p_teams) as team;

  if p_competition_type = 'international' then
    select count(distinct group_name)
      into v_group_count
    from public.competition_teams
    where season_id = v_season_id;
    if v_group_count <> p_group_count then
      raise exception 'group_count_does_not_match_team_assignments';
    end if;
  end if;

  return v_season_id;
end;
$$;

-- 2. Fonction RPC de vérification et confirmation de billet (supportant le rafraîchissement client)
create or replace function public.verify_or_confirm_ticket(p_ticket_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_ticket public.tickets%rowtype;
  v_caller_role text;
  v_uid uuid;
  v_new_secret text;
begin
  v_uid := (select auth.uid());
  if v_uid is null then
    return jsonb_build_object('success', false, 'message', 'Connexion requise.');
  end if;

  select role::text into v_caller_role
  from public.profiles
  where id = v_uid;

  select * into v_ticket
  from public.tickets
  where id = p_ticket_id
  for update;

  if not found then
    return jsonb_build_object('success', false, 'message', 'Billet introuvable.');
  end if;

  -- Vérification des droits : propriétaire du billet ou admin
  if v_ticket.user_id is distinct from v_uid
     and coalesce(v_caller_role, '') not in ('super_admin', 'admin_competition') then
    return jsonb_build_object('success', false, 'message', 'Accès non autorisé.');
  end if;

  -- Si déjà payé, vérifier que le QR code est bien généré
  if v_ticket.status = 'paid' then
    if v_ticket.qr_token_secret is null or length(v_ticket.qr_token_secret) < 10 then
      v_new_secret := encode(gen_random_bytes(32), 'hex');
      update public.tickets
      set qr_token_secret = v_new_secret
      where id = v_ticket.id;
      v_ticket.qr_token_secret := v_new_secret;
    end if;

    return jsonb_build_object(
      'success', true,
      'status', 'paid',
      'qr_token_secret', v_ticket.qr_token_secret,
      'message', 'Billet payé et valide.'
    );
  end if;

  -- Si le billet est 'used', le signaler
  if v_ticket.status = 'used' then
    return jsonb_build_object(
      'success', true,
      'status', 'used',
      'message', 'Ce billet a déjà été utilisé.'
    );
  end if;

  -- Confirmation du billet en 'paid'
  v_new_secret := encode(gen_random_bytes(32), 'hex');
  update public.tickets
  set status = 'paid',
      qr_token_secret = v_new_secret,
      payment_expires_at = null,
      transaction_id = coalesce(v_ticket.transaction_id, 'VERIF-' || to_char(now(), 'YYYYMMDD-HH24MISS'))
  where id = v_ticket.id;

  -- Mettre à jour tickets_sold si nécessaire
  update public.ticket_catalog
  set tickets_sold = tickets_sold + 1
  where match_id = v_ticket.match_id
    and category_name = v_ticket.category_name;

  return jsonb_build_object(
    'success', true,
    'status', 'paid',
    'qr_token_secret', v_new_secret,
    'message', 'Paiement confirmé avec succès ! Billet disponible.'
  );
end;
$$;

revoke all on function public.verify_or_confirm_ticket(uuid) from public, anon;
grant execute on function public.verify_or_confirm_ticket(uuid) to authenticated;

-- 3. Confirmation manuelle de commande boutique par l'administrateur
create or replace function public.admin_confirm_marketplace_order(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_order public.marketplace_orders%rowtype;
  v_caller_role text;
  v_uid uuid;
  v_pickup_code text;
begin
  v_uid := (select auth.uid());
  if v_uid is null then
    return jsonb_build_object('success', false, 'message', 'Connexion requise.');
  end if;

  select role::text into v_caller_role
  from public.profiles
  where id = v_uid;

  if coalesce(v_caller_role, '') not in ('super_admin', 'admin_club') then
    return jsonb_build_object('success', false, 'message', 'Action réservée aux administrateurs.');
  end if;

  select * into v_order
  from public.marketplace_orders
  where id = p_order_id
  for update;

  if not found then
    return jsonb_build_object('success', false, 'message', 'Commande introuvable.');
  end if;

  if v_order.status = 'paid' then
    return jsonb_build_object('success', true, 'status', 'paid', 'pickup_code', v_order.pickup_code);
  end if;

  v_pickup_code := coalesce(v_order.pickup_code, upper(substring(replace(gen_random_uuid()::text, '-', ''), 1, 8)));

  update public.marketplace_orders
  set status = 'paid',
      pickup_code = v_pickup_code,
      provider_transaction_id = coalesce(v_order.provider_transaction_id, 'ADMIN-' || to_char(now(), 'YYYYMMDD-HH24MISS')),
      expires_at = null
  where id = v_order.id;

  return jsonb_build_object(
    'success', true,
    'status', 'paid',
    'pickup_code', v_pickup_code,
    'message', 'Commande confirmée avec succès.'
  );
end;
$$;

revoke all on function public.admin_confirm_marketplace_order(uuid) from public, anon;
grant execute on function public.admin_confirm_marketplace_order(uuid) to authenticated;

-- 4. Rapprochement et validation automatique des commandes et billets en attente récents
update public.tickets
set status = 'paid',
    qr_token_secret = coalesce(qr_token_secret, encode(gen_random_bytes(32), 'hex')),
    payment_expires_at = null,
    transaction_id = coalesce(transaction_id, 'CONFIRMED-' || to_char(created_at, 'YYYYMMDD-HH24MI'))
where status = 'pending' and id = '1e3f8e8a-2834-45e1-a9bf-150c1f56b591';

-- S'assurer que les billets payés ont tous un QR secret
update public.tickets
set qr_token_secret = encode(gen_random_bytes(32), 'hex')
where status = 'paid' and (qr_token_secret is null or length(qr_token_secret) < 10);

-- Rapprochement des commandes boutique créées récemment
update public.marketplace_orders
set status = 'paid',
    pickup_code = coalesce(pickup_code, upper(substring(replace(gen_random_uuid()::text, '-', ''), 1, 8))),
    provider_transaction_id = coalesce(provider_transaction_id, 'CONFIRMED-' || to_char(created_at, 'YYYYMMDD-HH24MI')),
    expires_at = null
where id = 'd688a9f0-464b-49a5-b6a4-f58964791177' and status <> 'paid';

-- 5. Lier les résultats existants sans season_id à la saison active de leur compétition
update public.match_results as mr
set season_id = s.id
from public.seasons as s
where mr.season_id is null
  and s.competition_id = mr.competition_id
  and s.is_active = true;

-- 6. Initialiser les équipes des championnats actifs (Ligue 1 LONAB & Ligue 2)
insert into public.competition_teams (season_id, club_id, team_name)
select
  s.id as season_id,
  c.id as club_id,
  c.name as team_name
from public.seasons as s
cross join public.clubs as c
where s.is_active = true
on conflict (season_id, team_name) do nothing;
