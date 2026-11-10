alter table public.matches
  add column if not exists home_club_id uuid references public.clubs(id) on delete set null,
  add column if not exists away_club_id uuid references public.clubs(id) on delete set null;

do $$ begin
  alter table public.matches
    add constraint matches_distinct_clubs_check
    check (home_club_id is null or away_club_id is null or home_club_id <> away_club_id);
exception when duplicate_object then null;
end $$;

create index if not exists matches_home_club_date_idx
  on public.matches (home_club_id, date_time);
create index if not exists matches_away_club_date_idx
  on public.matches (away_club_id, date_time);

grant insert (name, short_name, city, logo_url, marketing_phone, headquarters_address)
  on public.clubs to authenticated;
grant update (name, short_name, city, logo_url, marketing_phone, headquarters_address)
  on public.clubs to authenticated;
grant select on public.clubs to anon, authenticated;

drop policy if exists "Club profiles are public" on public.clubs;
create policy "Club profiles are public"
  on public.clubs for select to anon, authenticated
  using (true);

drop policy if exists "Super admins create clubs" on public.clubs;
create policy "Super admins create clubs"
  on public.clubs for insert to authenticated
  with check (exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid()) and p.role::text = 'super_admin'
  ));
