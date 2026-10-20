insert into public.clubs (name, short_name, city)
select 'Étalons du Burkina Faso', 'ETALONS', 'Ouagadougou'
where not exists (
  select 1 from public.clubs where short_name = 'ETALONS'
);

update public.products p
set club_id = c.id
from public.clubs c
where c.short_name = 'ETALONS'
  and p.club_id is null
  and (p.title ilike '%Étalons%' or p.title ilike '%Burkina Faso%');

-- Do not advertise catalog items whose club cannot yet coordinate their handoff.
update public.products p
set is_active = false, updated_at = now()
where p.is_active
  and not exists (
    select 1 from public.clubs c
    where c.id = p.club_id
      and (nullif(btrim(c.marketing_phone), '') is not null
        or nullif(btrim(c.headquarters_address), '') is not null)
  );

create or replace function public.require_product_handoff_details()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  if new.is_active and not exists (
    select 1 from public.clubs c
    where c.id = new.club_id
      and (nullif(btrim(c.marketing_phone), '') is not null
        or nullif(btrim(c.headquarters_address), '') is not null)
  ) then
    raise exception 'club handoff details are required before publishing this product';
  end if;
  return new;
end;
$$;
drop trigger if exists products_require_handoff_details on public.products;
create trigger products_require_handoff_details
before insert or update of is_active, club_id on public.products
for each row execute function public.require_product_handoff_details();
