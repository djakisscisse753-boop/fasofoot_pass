-- Ajout des champs buteurs et passeurs à la table match_results
alter table public.match_results
  add column if not exists scorers text,
  add column if not exists assists text;

-- Ajout d'une table dédiée pour le détail fin des événements de match si nécessaire
create table if not exists public.match_events (
  id uuid primary key default gen_random_uuid(),
  match_result_id uuid not null references public.match_results(id) on delete cascade,
  event_type text not null check (event_type in ('goal', 'own_goal', 'penalty', 'assist', 'yellow_card', 'red_card')),
  team_side text not null check (team_side in ('home', 'away')),
  player_name text not null check (char_length(btrim(player_name)) between 2 and 80),
  minute integer check (minute between 1 and 130),
  created_at timestamptz not null default now()
);

create index if not exists match_events_result_idx on public.match_events (match_result_id);

alter table public.match_events enable row level security;

revoke all on public.match_events from public, anon, authenticated;
grant select on public.match_events to anon, authenticated;
grant insert, update, delete on public.match_events to authenticated;

do $$ begin
  create policy "Match events are publicly readable"
    on public.match_events for select to anon, authenticated
    using (true);
exception when duplicate_object then null;
end $$;

do $$ begin
  create policy "Competition admins manage match events"
    on public.match_events for all to authenticated
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
