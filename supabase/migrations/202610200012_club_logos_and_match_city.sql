alter table public.matches
  add column if not exists city text;

alter table public.matches
  add constraint matches_city_length_check
  check (city is null or char_length(city) between 2 and 100);

grant update (logo_url) on public.clubs to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('club-logos', 'club-logos', true, 3145728, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Public club logos are readable" on storage.objects;
create policy "Public club logos are readable"
  on storage.objects for select to anon, authenticated
  using (bucket_id = 'club-logos');

drop policy if exists "Club admins upload their club logos" on storage.objects;
create policy "Club admins upload their club logos"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'club-logos'
    and exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid())
        and (p.role::text = 'super_admin'
          or (p.role::text = 'admin_club' and p.managed_club_id::text = (storage.foldername(name))[1]))
    )
  );

drop policy if exists "Club admins replace their club logos" on storage.objects;
create policy "Club admins replace their club logos"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'club-logos'
    and exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid())
        and (p.role::text = 'super_admin'
          or (p.role::text = 'admin_club' and p.managed_club_id::text = (storage.foldername(name))[1]))
    )
  )
  with check (
    bucket_id = 'club-logos'
    and exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid())
        and (p.role::text = 'super_admin'
          or (p.role::text = 'admin_club' and p.managed_club_id::text = (storage.foldername(name))[1]))
    )
  );
