alter table public.seasons
  add column if not exists group_count integer not null default 0,
  add column if not exists qualifiers_per_group integer not null default 2;

do $$ begin
  alter table public.seasons
    add constraint seasons_group_count_check
    check (group_count >= 0);
exception when duplicate_object then null;
end $$;

do $$ begin
  alter table public.seasons
    add constraint seasons_qualifiers_per_group_check
    check (qualifiers_per_group > 0);
exception when duplicate_object then null;
end $$;

create table if not exists public.competition_teams (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references public.seasons(id) on delete cascade,
  club_id uuid references public.clubs(id) on delete set null,
  team_name text not null,
  group_name text,
  is_eliminated boolean not null default false,
  is_qualified boolean not null default false,
  created_at timestamptz not null default now(),
  unique (season_id, team_name),
  check (length(trim(team_name)) between 1 and 120),
  check (group_name is null or length(trim(group_name)) between 1 and 20)
);

alter table public.competition_teams
  add column if not exists is_qualified boolean not null default false;

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
  v_season_id uuid;
  v_team_count integer;
  v_group_count integer;
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

  select id into v_competition_id
  from public.competitions
  where code = upper(trim(p_code)) or name = trim(p_name)
  for update;

  if v_competition_id is null then
    insert into public.competitions (code, name, competition_type)
    values (upper(trim(p_code)), trim(p_name), p_competition_type)
    returning id into v_competition_id;
  elsif not exists (
    select 1
    from public.competitions
    where id = v_competition_id
      and code = upper(trim(p_code))
      and name = trim(p_name)
      and competition_type = p_competition_type
  ) then
    raise exception 'competition_code_name_or_type_conflict';
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

create index if not exists competition_teams_season_group_idx
  on public.competition_teams (season_id, group_name, team_name);
create unique index if not exists competition_teams_season_team_name_ci_idx
  on public.competition_teams (season_id, lower(team_name));
create unique index if not exists competition_teams_season_club_idx
  on public.competition_teams (season_id, club_id)
  where club_id is not null;

alter table public.matches
  add column if not exists phase text not null default 'league',
  add column if not exists matchday integer,
  add column if not exists stage_name text,
  add column if not exists group_name text,
  add column if not exists home_competition_team_id uuid
    references public.competition_teams(id) on delete set null,
  add column if not exists away_competition_team_id uuid
    references public.competition_teams(id) on delete set null;

do $$ begin
  alter table public.matches
    add constraint matches_competition_phase_check
    check (phase in ('league', 'group', 'knockout'));
exception when duplicate_object then null;
end $$;

do $$ begin
  alter table public.matches
    add constraint matches_nonnegative_matchday_check
    check (matchday is null or matchday > 0);
exception when duplicate_object then null;
end $$;

do $$ begin
  alter table public.matches
    add constraint matches_distinct_competition_teams_check
    check (
      home_competition_team_id is null
      or away_competition_team_id is null
      or home_competition_team_id <> away_competition_team_id
    );
exception when duplicate_object then null;
end $$;

alter table public.match_results
  add column if not exists phase text,
  add column if not exists matchday integer,
  add column if not exists stage_name text,
  add column if not exists group_name text,
  add column if not exists home_penalties integer,
  add column if not exists away_penalties integer,
  add column if not exists winner_competition_team_id uuid
    references public.competition_teams(id) on delete set null;

do $$ begin
  alter table public.match_results
    add constraint match_results_nonnegative_penalties_check
    check (
      (home_penalties is null or home_penalties >= 0)
      and (away_penalties is null or away_penalties >= 0)
    );
exception when duplicate_object then null;
end $$;

create or replace function public.sync_match_result_competition_details()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match public.matches%rowtype;
  v_competition_type text;
begin
  if new.match_id is null then
    return new;
  end if;

  select * into v_match
  from public.matches
  where id = new.match_id;

  if not found then
    raise exception 'match_not_found';
  end if;

  new.competition_id := v_match.competition_id;
  new.season_id := v_match.season_id;
  new.phase := v_match.phase;
  new.matchday := v_match.matchday;
  new.stage_name := v_match.stage_name;
  new.group_name := v_match.group_name;

  if v_match.home_competition_team_id is not null then
    select team_name into new.home_team_name
    from public.competition_teams
    where id = v_match.home_competition_team_id;
    select team_name into new.away_team_name
    from public.competition_teams
    where id = v_match.away_competition_team_id;
  end if;

  if (v_match.home_competition_team_id is null)
     <> (v_match.away_competition_team_id is null) then
    raise exception 'both_competition_teams_must_be_selected';
  end if;

  if v_match.home_competition_team_id is not null and not exists (
    select 1
    from public.competition_teams as home_team
    join public.competition_teams as away_team
      on away_team.id = v_match.away_competition_team_id
    where home_team.id = v_match.home_competition_team_id
      and home_team.season_id = v_match.season_id
      and away_team.season_id = v_match.season_id
  ) then
    raise exception 'match_teams_must_belong_to_its_season';
  end if;

  if v_match.phase = 'group'
     and v_match.home_competition_team_id is not null
     and not exists (
       select 1
       from public.competition_teams as home_team
       join public.competition_teams as away_team
         on away_team.id = v_match.away_competition_team_id
       where home_team.id = v_match.home_competition_team_id
         and home_team.season_id = v_match.season_id
         and home_team.group_name is not null
         and home_team.group_name = away_team.group_name
         and home_team.group_name = v_match.group_name
     ) then
    raise exception 'group_match_teams_must_share_group';
  end if;

  if v_match.phase = 'knockout' then
    select competition_type into v_competition_type
    from public.competitions
    where id = v_match.competition_id;

    if v_competition_type = 'international'
       and v_match.home_competition_team_id is not null
       and exists (
         select 1
         from public.competition_teams
         where id in (
           v_match.home_competition_team_id,
           v_match.away_competition_team_id
         )
           and not is_qualified
       ) then
      raise exception 'knockout_teams_must_be_qualified';
    end if;

    if new.home_score = new.away_score then
      if new.home_penalties is null
         or new.away_penalties is null
         or new.home_penalties = new.away_penalties then
        raise exception 'knockout_tie_requires_penalty_winner';
      end if;

      new.winner_competition_team_id :=
        case
          when v_match.home_competition_team_id is null then null
          when new.home_penalties > new.away_penalties
            then v_match.home_competition_team_id
          else v_match.away_competition_team_id
        end;
    else
      if new.home_penalties is not null or new.away_penalties is not null then
        raise exception 'penalties_only_allowed_for_drawn_score';
      end if;

      new.winner_competition_team_id :=
        case
          when v_match.home_competition_team_id is null then null
          when new.home_score > new.away_score
            then v_match.home_competition_team_id
          else v_match.away_competition_team_id
        end;
    end if;
  else
    new.winner_competition_team_id := null;
    new.home_penalties := null;
    new.away_penalties := null;
  end if;

  return new;
end;
$$;

drop trigger if exists match_results_sync_competition_details
  on public.match_results;
create trigger match_results_sync_competition_details
before insert or update of match_id, home_score, away_score, home_penalties,
  away_penalties
on public.match_results
for each row execute function public.sync_match_result_competition_details();

create or replace function public.refresh_competition_team_eliminations(
  p_season_id uuid
)
returns void
language sql
security definer
set search_path = public
as $$
  update public.competition_teams as team
  set is_eliminated = exists (
    select 1
    from public.match_results as result
    join public.matches as match on match.id = result.match_id
    where match.season_id = team.season_id
      and match.phase = 'knockout'
      and lower(result.status) in ('finished', 'completed', 'termine', 'terminé')
      and match.home_competition_team_id is not null
      and match.away_competition_team_id is not null
      and result.winner_competition_team_id is not null
      and team.id = case
        when result.winner_competition_team_id = match.home_competition_team_id
          then match.away_competition_team_id
        else match.home_competition_team_id
      end
  )
  where team.season_id = p_season_id;
$$;

create or replace function public.refresh_competition_team_qualifications(
  p_season_id uuid
)
returns void
language sql
security definer
set search_path = public
as $$
  with season_rules as (
    select qualifiers_per_group
    from public.seasons
    where id = p_season_id
  ),
  fixture_completion as (
    select
      match.group_name,
      count(distinct match.id) as fixture_count,
      count(distinct match.id) filter (
        where lower(result.status) in (
          'finished', 'completed', 'termine', 'terminé'
        )
      ) as finished_count
    from public.matches as match
    left join public.match_results as result on result.match_id = match.id
    where match.season_id = p_season_id
      and match.phase = 'group'
      and match.group_name is not null
      and match.status <> 'cancelled'
    group by match.group_name
  ),
  team_table as (
    select
      team.id,
      team.group_name,
      team.team_name,
      coalesce(sum(
        case
          when result.id is null then 0
          when result.home_score = result.away_score then 1
          when (result.home_score > result.away_score
                and match.home_competition_team_id = team.id)
            or (result.away_score > result.home_score
                and match.away_competition_team_id = team.id) then 3
          else 0
        end
      ), 0) as points,
      coalesce(sum(
        case
          when result.id is null then 0
          when match.home_competition_team_id = team.id
            then result.home_score - result.away_score
          else result.away_score - result.home_score
        end
      ), 0) as goal_difference,
      coalesce(sum(
        case
          when result.id is null then 0
          when match.home_competition_team_id = team.id
            then result.home_score
          else result.away_score
        end
      ), 0) as goals_scored
    from public.competition_teams as team
    left join public.matches as match
      on match.season_id = team.season_id
      and match.phase = 'group'
      and match.group_name = team.group_name
      and match.status <> 'cancelled'
      and (
        match.home_competition_team_id = team.id
        or match.away_competition_team_id = team.id
      )
    left join public.match_results as result
      on result.match_id = match.id
      and lower(result.status) in (
        'finished', 'completed', 'termine', 'terminé'
      )
    where team.season_id = p_season_id
      and team.group_name is not null
    group by team.id, team.group_name, team.team_name
  ),
  ranked_teams as (
    select
      team_table.id,
      row_number() over (
        partition by team_table.group_name
        order by
          team_table.points desc,
          team_table.goal_difference desc,
          team_table.goals_scored desc,
          team_table.team_name
      ) as group_rank,
      fixture_completion.fixture_count,
      fixture_completion.finished_count,
      season_rules.qualifiers_per_group
    from team_table
    cross join season_rules
    left join fixture_completion
      on fixture_completion.group_name = team_table.group_name
  )
  update public.competition_teams as team
  set is_qualified = coalesce(
    ranked_teams.fixture_count > 0
      and ranked_teams.fixture_count = ranked_teams.finished_count
      and ranked_teams.group_rank <= ranked_teams.qualifiers_per_group,
    false
  )
  from ranked_teams
  where team.id = ranked_teams.id;
$$;

create or replace function public.refresh_competition_eliminations_from_result()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old_season_id uuid;
  v_new_season_id uuid;
begin
  if tg_op <> 'INSERT' and old.match_id is not null then
    select season_id into v_old_season_id
    from public.matches
    where id = old.match_id;
    if v_old_season_id is not null then
      perform public.refresh_competition_team_eliminations(v_old_season_id);
      perform public.refresh_competition_team_qualifications(v_old_season_id);
    end if;
  end if;

  if tg_op <> 'DELETE' and new.match_id is not null then
    select season_id into v_new_season_id
    from public.matches
    where id = new.match_id;
    if v_new_season_id is not null
       and v_new_season_id is distinct from v_old_season_id then
      perform public.refresh_competition_team_eliminations(v_new_season_id);
      perform public.refresh_competition_team_qualifications(v_new_season_id);
    elsif v_new_season_id is not null and tg_op = 'INSERT' then
      perform public.refresh_competition_team_eliminations(v_new_season_id);
      perform public.refresh_competition_team_qualifications(v_new_season_id);
    elsif v_new_season_id is not null and tg_op = 'UPDATE' then
      perform public.refresh_competition_team_eliminations(v_new_season_id);
      perform public.refresh_competition_team_qualifications(v_new_season_id);
    end if;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists match_results_refresh_competition_eliminations
  on public.match_results;
create trigger match_results_refresh_competition_eliminations
after insert or update or delete on public.match_results
for each row execute function public.refresh_competition_eliminations_from_result();

create or replace function public.sync_match_details_to_results()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.match_results
  set match_id = new.id
  where match_id = new.id;
  return new;
end;
$$;

drop trigger if exists matches_sync_details_to_results on public.matches;
create trigger matches_sync_details_to_results
after update of competition_id, season_id, phase, matchday, stage_name,
  group_name, home_competition_team_id, away_competition_team_id
on public.matches
for each row execute function public.sync_match_details_to_results();

create or replace function public.refresh_competition_state_from_match()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old_season_id uuid;
  v_new_season_id uuid;
begin
  if tg_op <> 'INSERT' then
    v_old_season_id := old.season_id;
    if v_old_season_id is not null then
      perform public.refresh_competition_team_eliminations(v_old_season_id);
      perform public.refresh_competition_team_qualifications(v_old_season_id);
    end if;
  end if;

  if tg_op <> 'DELETE' then
    v_new_season_id := new.season_id;
    if v_new_season_id is not null
       and v_new_season_id is distinct from v_old_season_id then
      perform public.refresh_competition_team_eliminations(v_new_season_id);
      perform public.refresh_competition_team_qualifications(v_new_season_id);
    elsif v_new_season_id is not null and tg_op = 'INSERT' then
      perform public.refresh_competition_team_eliminations(v_new_season_id);
      perform public.refresh_competition_team_qualifications(v_new_season_id);
    end if;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists matches_refresh_competition_state on public.matches;
create trigger matches_refresh_competition_state
after insert or update or delete
on public.matches
for each row execute function public.refresh_competition_state_from_match();

alter table public.competition_teams enable row level security;
revoke all on public.competition_teams from public, anon, authenticated;
grant select on public.competition_teams to anon, authenticated;
grant insert, update, delete on public.competition_teams to authenticated;

drop policy if exists "Competition teams are public"
  on public.competition_teams;
create policy "Competition teams are public"
  on public.competition_teams for select to anon, authenticated
  using (true);

drop policy if exists "Active seasons are public" on public.seasons;
drop policy if exists "Competition seasons are public" on public.seasons;
create policy "Competition seasons are public"
  on public.seasons for select to anon, authenticated
  using (true);

drop policy if exists "Competition admins manage competition teams"
  on public.competition_teams;
create policy "Competition admins manage competition teams"
  on public.competition_teams for all to authenticated
  using (exists (
    select 1 from public.profiles as profile
    where profile.id = (select auth.uid())
      and profile.role::text in ('admin_competition', 'super_admin')
  ))
  with check (exists (
    select 1 from public.profiles as profile
    where profile.id = (select auth.uid())
      and profile.role::text in ('admin_competition', 'super_admin')
  ));

drop policy if exists "Competition admins manage competitions"
  on public.competitions;
create policy "Competition admins manage competitions"
  on public.competitions for all to authenticated
  using (exists (
    select 1 from public.profiles as profile
    where profile.id = (select auth.uid())
      and profile.role::text in ('admin_competition', 'super_admin')
  ))
  with check (exists (
    select 1 from public.profiles as profile
    where profile.id = (select auth.uid())
      and profile.role::text in ('admin_competition', 'super_admin')
  ));

revoke all on function public.refresh_competition_team_eliminations(uuid)
  from public, anon, authenticated;
revoke all on function public.refresh_competition_team_qualifications(uuid)
  from public, anon, authenticated;
revoke all on function public.sync_match_result_competition_details()
  from public, anon, authenticated;
revoke all on function public.refresh_competition_eliminations_from_result()
  from public, anon, authenticated;
revoke all on function public.sync_match_details_to_results()
  from public, anon, authenticated;
revoke all on function public.refresh_competition_state_from_match()
  from public, anon, authenticated;
revoke all on function public.create_competition_season(
  text, text, text, text, integer, integer, jsonb
) from public, anon, authenticated;
grant execute on function public.create_competition_season(
  text, text, text, text, integer, integer, jsonb
) to authenticated;
