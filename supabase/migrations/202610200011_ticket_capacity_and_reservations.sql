alter table public.tickets
  add column if not exists payment_expires_at timestamptz;

alter table public.tickets
  drop constraint if exists tickets_status_check;
alter table public.tickets
  add constraint tickets_status_check
  check (status in ('pending', 'paid', 'failed', 'used', 'cancelled', 'refund_required'));

create or replace function public.reserve_ticket(
  p_match_id uuid,
  p_category_name text,
  p_customer_name text,
  p_customer_phone text,
  p_user_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_category_id uuid;
  v_price numeric;
  v_capacity integer;
  v_category_sold integer;
  v_paid_count bigint;
  v_reserved_count bigint;
  v_sold integer;
  v_match_status text;
  v_match_date timestamptz;
  v_ticket public.tickets%rowtype;
begin
  select status, date_time into v_match_status, v_match_date
  from public.matches where id = p_match_id;
  if not found then
    return jsonb_build_object('success', false, 'reason', 'match_missing', 'message', 'Match introuvable.');
  end if;
  if v_match_status in ('cancelled', 'postponed', 'finished') or v_match_date <= now() then
    return jsonb_build_object('success', false, 'reason', 'sales_closed', 'message', 'La vente des billets pour ce match est fermée.');
  end if;

  select category.id, category.price, category.total_tickets_offered,
         coalesce(category.tickets_sold, 0)
  into v_category_id, v_price, v_capacity, v_category_sold
  from public.match_ticket_categories category
  join public.stadium_zones zone on zone.id = category.zone_id
  where category.match_id = p_match_id and zone.zone_name = p_category_name
  for update of category;

  if not found or v_price <= 0 or v_capacity <= 0 then
    return jsonb_build_object('success', false, 'reason', 'category_unavailable', 'message', 'Cette catégorie de billets n’est pas disponible.');
  end if;

  select count(*) into v_paid_count
  from public.tickets
  where match_id = p_match_id and category_name = p_category_name
    and status in ('paid', 'used');
  select count(*) into v_reserved_count
  from public.tickets
  where match_id = p_match_id and category_name = p_category_name
    and status = 'pending' and payment_expires_at > now();

  v_sold := greatest(v_category_sold, v_paid_count::integer);
  if v_sold + v_reserved_count >= v_capacity then
    return jsonb_build_object('success', false, 'reason', 'sold_out', 'message', 'Cette catégorie vient d’être épuisée.');
  end if;

  insert into public.tickets (
    match_id, user_id, category_name, customer_name, customer_phone,
    price, status, payment_expires_at
  ) values (
    p_match_id, p_user_id, p_category_name, p_customer_name, p_customer_phone,
    v_price::integer, 'pending', now() + interval '15 minutes'
  ) returning * into v_ticket;

  return jsonb_build_object('success', true, 'ticket_id', v_ticket.id, 'price', v_ticket.price);
end;
$$;

create or replace function public.confirm_ticket_payment(
  p_ticket_id uuid,
  p_transaction_id text,
  p_amount bigint
) returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_ticket public.tickets%rowtype;
  v_category_id uuid;
  v_capacity integer;
  v_category_sold integer;
  v_paid_count bigint;
  v_reserved_count bigint;
  v_sold integer;
  v_match_status text;
  v_match_date timestamptz;
  v_has_reservation boolean;
begin
  select * into v_ticket
  from public.tickets where id = p_ticket_id
  for update;
  if not found then return 'not_found'; end if;

  if v_ticket.status in ('paid', 'used') and v_ticket.transaction_id = p_transaction_id then
    return 'duplicate';
  end if;
  if v_ticket.status = 'refund_required' and v_ticket.transaction_id = p_transaction_id then
    return 'refund_required';
  end if;
  if v_ticket.transaction_id is not null and v_ticket.transaction_id <> p_transaction_id then
    return 'not_pending';
  end if;
  if v_ticket.price <> p_amount then return 'amount_mismatch'; end if;
  if v_ticket.status not in ('pending', 'failed') then return 'not_pending'; end if;

  select status, date_time into v_match_status, v_match_date
  from public.matches where id = v_ticket.match_id;
  if not found or v_match_status in ('cancelled', 'postponed', 'finished') then
    update public.tickets set status = 'refund_required', transaction_id = p_transaction_id,
      payment_expires_at = null where id = v_ticket.id;
    return 'refund_required';
  end if;

  select category.id, category.total_tickets_offered, coalesce(category.tickets_sold, 0)
  into v_category_id, v_capacity, v_category_sold
  from public.match_ticket_categories category
  join public.stadium_zones zone on zone.id = category.zone_id
  where category.match_id = v_ticket.match_id and zone.zone_name = v_ticket.category_name
  for update of category;
  if not found then
    update public.tickets set status = 'refund_required', transaction_id = p_transaction_id,
      payment_expires_at = null where id = v_ticket.id;
    return 'refund_required';
  end if;

  select count(*) into v_paid_count
  from public.tickets
  where match_id = v_ticket.match_id and category_name = v_ticket.category_name
    and status in ('paid', 'used');
  select count(*) into v_reserved_count
  from public.tickets
  where match_id = v_ticket.match_id and category_name = v_ticket.category_name
    and status = 'pending' and payment_expires_at > now() and id <> v_ticket.id;

  v_sold := greatest(v_category_sold, v_paid_count::integer);
  v_has_reservation := v_ticket.status = 'pending'
    and v_ticket.payment_expires_at is not null and v_ticket.payment_expires_at > now();

  if v_has_reservation or v_sold + v_reserved_count < v_capacity then
    update public.tickets set status = 'paid', transaction_id = p_transaction_id,
      payment_expires_at = null where id = v_ticket.id;
    update public.match_ticket_categories
    set tickets_sold = v_sold + 1
    where id = v_category_id;
    return 'paid';
  end if;

  update public.tickets set status = 'refund_required', transaction_id = p_transaction_id,
    payment_expires_at = null where id = v_ticket.id;
  return 'refund_required';
end;
$$;

revoke all on function public.reserve_ticket(uuid, text, text, text, uuid) from public, anon, authenticated;
grant execute on function public.reserve_ticket(uuid, text, text, text, uuid) to service_role;
revoke all on function public.confirm_ticket_payment(uuid, text, bigint) from public, anon, authenticated;
grant execute on function public.confirm_ticket_payment(uuid, text, bigint) to service_role;
