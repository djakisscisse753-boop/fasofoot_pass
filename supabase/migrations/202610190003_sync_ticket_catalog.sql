create or replace function public.sync_ticket_catalog_from_category()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  category_match_id uuid;
  category_zone_id uuid;
  category_price numeric;
  sold integer;
  offered integer;
  zone_label text;
begin
  if tg_op = 'DELETE' or (tg_op = 'UPDATE' and
      (old.match_id is distinct from new.match_id or old.zone_id is distinct from new.zone_id)) then
    select zone_name into zone_label from public.stadium_zones where id = old.zone_id;
    update public.ticket_catalog
      set is_active = false
      where match_id = old.match_id and category_name = zone_label;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  category_match_id := new.match_id;
  category_zone_id := new.zone_id;
  category_price := new.price;
  sold := coalesce(new.tickets_sold, 0);
  offered := coalesce(new.total_tickets_offered, 0);

  select zone_name into zone_label from public.stadium_zones where id = category_zone_id;
  if zone_label is null or category_price <= 0 then
    return new;
  end if;

  insert into public.ticket_catalog (match_id, category_name, price, is_active)
  values (category_match_id, zone_label, category_price::integer, sold < offered)
  on conflict (match_id, category_name) do update
    set price = excluded.price, is_active = excluded.is_active;
  return new;
end;
$$;

drop trigger if exists sync_ticket_catalog on public.match_ticket_categories;
create trigger sync_ticket_catalog
  after insert or update or delete on public.match_ticket_categories
  for each row execute function public.sync_ticket_catalog_from_category();
