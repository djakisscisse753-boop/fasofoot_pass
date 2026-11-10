create table if not exists public.app_settings (
  id smallint primary key default 1 check (id = 1),
  maintenance_enabled boolean not null default false,
  maintenance_message text not null default 'FasoFoot Pass est temporairement en maintenance. Merci de revenir bientôt.',
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete set null,
  constraint app_settings_maintenance_message_length_check
    check (char_length(maintenance_message) between 10 and 500)
);

insert into public.app_settings (id)
values (1)
on conflict (id) do nothing;

alter table public.app_settings enable row level security;
revoke all on public.app_settings from public, anon, authenticated;
grant select on public.app_settings to anon, authenticated;

drop policy if exists "Maintenance status is publicly readable" on public.app_settings;
create policy "Maintenance status is publicly readable"
  on public.app_settings for select to anon, authenticated
  using (id = 1);

create or replace function public.set_app_maintenance(
  p_enabled boolean,
  p_message text default null
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text;
  v_message text;
begin
  select role::text into v_role
  from public.profiles
  where id = (select auth.uid());

  if v_role is distinct from 'super_admin' then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_enabled is null then
    raise exception 'enabled state is required' using errcode = '22023';
  end if;

  select coalesce(nullif(btrim(p_message), ''), maintenance_message)
  into v_message
  from public.app_settings
  where id = 1;

  if char_length(v_message) not between 10 and 500 then
    raise exception 'maintenance message must contain between 10 and 500 characters'
      using errcode = '22023';
  end if;

  update public.app_settings
  set maintenance_enabled = p_enabled,
      maintenance_message = v_message,
      updated_at = now(),
      updated_by = (select auth.uid())
  where id = 1;
end;
$$;

revoke all on function public.set_app_maintenance(boolean, text) from public, anon;
grant execute on function public.set_app_maintenance(boolean, text) to authenticated;
