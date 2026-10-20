alter type public.user_role add value if not exists 'admin_competition';

create table if not exists public.competitions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null unique,
  competition_type text not null check (competition_type in ('league', 'cup', 'international')),
  country_code char(2) not null default 'BF',
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.seasons (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.competitions(id) on delete cascade,
  name text not null,
  starts_on date,
  ends_on date,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (competition_id, name),
  check (ends_on is null or starts_on is null or ends_on >= starts_on)
);

insert into public.competitions (code, name, competition_type) values
  ('L1-BF', 'Ligue 1 LONAB', 'league'),
  ('L2-BF', 'Ligue 2', 'league'),
  ('CDF-BF', 'Coupe du Faso', 'cup'),
  ('ETALONS', 'Étalons', 'international')
on conflict (code) do update set name = excluded.name, competition_type = excluded.competition_type;

alter table public.matches
  add column if not exists competition_id uuid references public.competitions(id),
  add column if not exists season_id uuid references public.seasons(id),
  add column if not exists status text not null default 'scheduled';
alter table public.match_results
  add column if not exists match_id uuid references public.matches(id) on delete set null,
  add column if not exists competition_id uuid references public.competitions(id),
  add column if not exists validated_at timestamptz,
  add column if not exists validated_by uuid references public.profiles(id) on delete set null;
alter table public.matches
  add constraint matches_status_check
  check (status in ('scheduled', 'live', 'finished', 'postponed', 'cancelled'));
create index if not exists matches_competition_date_idx
  on public.matches (competition_id, date_time);
create index if not exists match_results_competition_date_idx
  on public.match_results (competition_id, match_date desc);

update public.match_results as result
set competition_id = competition.id
from public.competitions as competition
where result.competition_id is null and result.category = competition.name;

alter table public.profiles
  add column if not exists managed_club_id uuid references public.clubs(id) on delete set null;

alter table public.competitions enable row level security;
alter table public.seasons enable row level security;
alter table public.matches enable row level security;
alter table public.match_results enable row level security;
alter table public.products enable row level security;
alter table public.profiles enable row level security;

revoke all on public.competitions, public.seasons from public, anon, authenticated;
grant select on public.competitions, public.seasons to anon, authenticated;
grant insert, update, delete on public.competitions, public.seasons to authenticated;
revoke all on public.profiles from public, anon, authenticated;
grant select on public.profiles to authenticated;
grant update (full_name, favorite_club_id) on public.profiles to authenticated;

do $$ begin
  create policy "Active competitions are public"
    on public.competitions for select to anon, authenticated using (is_active);
exception when duplicate_object then null;
end $$;
do $$ begin
  create policy "Active seasons are public"
    on public.seasons for select to anon, authenticated using (is_active);
exception when duplicate_object then null;
end $$;

grant insert, update, delete on public.matches, public.match_results to authenticated;
grant select on public.matches, public.match_results to anon, authenticated;
do $$ begin
  create policy "Competition admins manage matches"
    on public.matches for all to authenticated
    using (exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role::text in ('admin_competition', 'super_admin')))
    with check (exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role::text in ('admin_competition', 'super_admin')));
exception when duplicate_object then null;
end $$;
do $$ begin
  create policy "Competition admins manage results"
    on public.match_results for all to authenticated
    using (exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role::text in ('admin_competition', 'super_admin')))
    with check (exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role::text in ('admin_competition', 'super_admin')));
exception when duplicate_object then null;
end $$;
do $$ begin
  create policy "Competition admins manage competitions"
    on public.competitions for all to authenticated
    using (exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role::text = 'super_admin'))
    with check (exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role::text = 'super_admin'));
exception when duplicate_object then null;
end $$;
do $$ begin
  create policy "Competition admins manage seasons"
    on public.seasons for all to authenticated
    using (exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role::text in ('admin_competition', 'super_admin')))
    with check (exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role::text in ('admin_competition', 'super_admin')));
exception when duplicate_object then null;
end $$;

revoke all on public.products from public, anon, authenticated;
grant select on public.products to anon, authenticated;
grant insert, update, delete on public.products to authenticated;
drop policy if exists "Produits visibles par tous" on public.products;
do $$ begin
  create policy "Active products are public"
    on public.products for select to anon, authenticated using (is_active);
exception when duplicate_object then null;
end $$;
do $$ begin
  create policy "Club admins manage their products"
    on public.products for all to authenticated
    using (exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid())
        and (p.role::text = 'super_admin' or (p.role::text = 'admin_club' and p.managed_club_id = products.club_id))
    ))
    with check (exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid())
        and (p.role::text = 'super_admin' or (p.role::text = 'admin_club' and p.managed_club_id = products.club_id))
    ));
exception when duplicate_object then null;
end $$;
