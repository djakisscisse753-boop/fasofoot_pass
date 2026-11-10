create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  profile_name text;
begin
  profile_name := coalesce(
    nullif(btrim(new.raw_user_meta_data ->> 'full_name'), ''),
    nullif(btrim(new.raw_user_meta_data ->> 'name'), ''),
    nullif(btrim(new.raw_user_meta_data ->> 'display_name'), '')
  );

  insert into public.profiles (id, phone_number, full_name)
  values (new.id, new.phone, profile_name)
  on conflict (id) do update
    set phone_number = coalesce(excluded.phone_number, profiles.phone_number),
        full_name = coalesce(profiles.full_name, excluded.full_name);

  return new;
end;
$$;
