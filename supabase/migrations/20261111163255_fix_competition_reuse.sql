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

  -- Existing competitions can have a canonical code different from the generated one.
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
  returning id into v_season_id;

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

revoke all on function public.create_competition_season(
  text, text, text, text, integer, integer, jsonb
) from public, anon, authenticated;
grant execute on function public.create_competition_season(
  text, text, text, text, integer, integer, jsonb
) to authenticated;
