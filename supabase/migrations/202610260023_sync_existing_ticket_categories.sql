insert into public.ticket_catalog (
  match_id,
  category_name,
  price,
  total_capacity,
  tickets_sold,
  is_active
)
select
  category.match_id,
  zone.zone_name,
  category.price::integer,
  category.total_tickets_offered,
  coalesce(category.tickets_sold, 0),
  coalesce(category.tickets_sold, 0) < category.total_tickets_offered
from public.match_ticket_categories as category
join public.stadium_zones as zone on zone.id = category.zone_id
where category.price > 0
on conflict (match_id, category_name) do nothing;
