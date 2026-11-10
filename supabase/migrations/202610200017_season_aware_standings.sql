alter table public.match_results
  add column if not exists season_id uuid references public.seasons(id) on delete set null;

create index if not exists match_results_season_date_idx
  on public.match_results (season_id, match_date desc);

update public.match_results as result
set competition_id = competition.id
from public.competitions as competition
where result.competition_id is null
  and result.category = competition.name;

update public.match_results as result
set competition_id = match.competition_id,
    season_id = match.season_id
from public.matches as match
where result.match_id = match.id
  and (result.competition_id is distinct from match.competition_id
    or result.season_id is distinct from match.season_id);

create or replace function public.sync_match_result_season()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.match_id is not null then
    select match.competition_id, match.season_id
      into new.competition_id, new.season_id
    from public.matches as match
    where match.id = new.match_id;
  end if;
  return new;
end;
$$;

drop trigger if exists match_results_sync_season on public.match_results;
create trigger match_results_sync_season
before insert or update of match_id, competition_id, season_id
on public.match_results
for each row execute function public.sync_match_result_season();

create or replace function public.sync_match_season_to_results()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.match_results
  set competition_id = new.competition_id,
      season_id = new.season_id
  where match_id = new.id;
  return new;
end;
$$;

drop trigger if exists matches_sync_result_season on public.matches;
create trigger matches_sync_result_season
after update of competition_id, season_id
on public.matches
for each row execute function public.sync_match_season_to_results();
