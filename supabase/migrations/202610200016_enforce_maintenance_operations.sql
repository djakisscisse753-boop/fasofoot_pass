create or replace function public.enforce_app_maintenance()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_maintenance boolean;
  v_role text;
begin
  select maintenance_enabled into v_maintenance
  from public.app_settings
  where id = 1;
  if not coalesce(v_maintenance, false) then
    return new;
  end if;

  if tg_table_name = 'tickets' then
    if tg_op = 'INSERT' and coalesce(new.status, 'pending') = 'pending' then
      raise exception 'FasoFoot Pass is in maintenance' using errcode = '55000';
    end if;
    if tg_op = 'UPDATE' and old.status = 'paid' and new.status = 'used' then
      select role::text into v_role
      from public.profiles
      where id = (select auth.uid());
      if v_role is distinct from 'super_admin' then
        raise exception 'FasoFoot Pass is in maintenance' using errcode = '55000';
      end if;
    end if;
  elsif tg_table_name = 'marketplace_orders'
      and tg_op = 'INSERT'
      and coalesce(new.status, 'pending') = 'pending' then
    raise exception 'FasoFoot Pass is in maintenance' using errcode = '55000';
  end if;

  return new;
end;
$$;

revoke all on function public.enforce_app_maintenance() from public, anon, authenticated;

drop trigger if exists enforce_app_maintenance_on_tickets on public.tickets;
create trigger enforce_app_maintenance_on_tickets
  before insert or update of status on public.tickets
  for each row execute function public.enforce_app_maintenance();

drop trigger if exists enforce_app_maintenance_on_marketplace_orders
  on public.marketplace_orders;
create trigger enforce_app_maintenance_on_marketplace_orders
  before insert or update of status on public.marketplace_orders
  for each row execute function public.enforce_app_maintenance();
