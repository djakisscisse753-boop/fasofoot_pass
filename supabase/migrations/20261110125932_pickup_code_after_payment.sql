-- Applied to Supabase as migration 20261110125932.
create or replace function public.set_marketplace_pickup_code()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.status <> 'paid'
    or new.provider_transaction_id is null
    or new.provider_transaction_id like 'MANUAL-%' then
    new.pickup_code := null;
  elsif new.pickup_code is null then
    new.pickup_code := 'RET-' || upper(substr(md5(random()::text), 1, 6));
  end if;

  return new;
end;
$$;

revoke all on function public.set_marketplace_pickup_code()
  from public, anon, authenticated;

drop trigger if exists set_marketplace_pickup_code
  on public.marketplace_orders;
create trigger set_marketplace_pickup_code
  before insert or update of status, provider_transaction_id, pickup_code
  on public.marketplace_orders
  for each row
  execute function public.set_marketplace_pickup_code();
