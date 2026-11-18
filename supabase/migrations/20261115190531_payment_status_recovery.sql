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
  v_capacity integer;
  v_category_sold integer;
  v_paid_count bigint;
  v_reserved_count bigint;
  v_sold integer;
  v_match_status text;
  v_has_reservation boolean;
  v_transaction_id text := nullif(btrim(p_transaction_id), '');
begin
  if v_transaction_id is null or length(v_transaction_id) > 200
     or p_amount is null or p_amount <= 0 then
    return 'invalid_payment';
  end if;

  select * into v_ticket
  from public.tickets
  where id = p_ticket_id
  for update;

  if not found then
    return 'not_found';
  end if;

  if v_ticket.status in ('paid', 'used') then
    return case
      when v_ticket.transaction_id = v_transaction_id then 'duplicate'
      else 'not_pending'
    end;
  end if;
  if v_ticket.status = 'refund_required'
     and v_ticket.transaction_id = v_transaction_id then
    return 'refund_required';
  end if;
  if v_ticket.transaction_id is not null
     and v_ticket.transaction_id <> v_transaction_id then
    return 'not_pending';
  end if;
  if p_amount * 100 < v_ticket.price * 90 then
    return 'amount_mismatch';
  end if;
  if v_ticket.status not in ('pending', 'failed') then
    return 'not_pending';
  end if;

  select status into v_match_status
  from public.matches
  where id = v_ticket.match_id;

  if not found or v_match_status in ('cancelled', 'postponed', 'finished') then
    update public.tickets
    set status = 'refund_required',
        transaction_id = v_transaction_id,
        payment_expires_at = null
    where id = v_ticket.id;
    return 'refund_required';
  end if;

  select total_capacity, coalesce(tickets_sold, 0)
    into v_capacity, v_category_sold
  from public.ticket_catalog
  where match_id = v_ticket.match_id
    and category_name = v_ticket.category_name
  for update;

  if not found or v_capacity is null or v_capacity <= 0 then
    update public.tickets
    set status = 'refund_required',
        transaction_id = v_transaction_id,
        payment_expires_at = null
    where id = v_ticket.id;
    return 'refund_required';
  end if;

  select count(*) into v_paid_count
  from public.tickets
  where match_id = v_ticket.match_id
    and category_name = v_ticket.category_name
    and status in ('paid', 'used');

  select count(*) into v_reserved_count
  from public.tickets
  where match_id = v_ticket.match_id
    and category_name = v_ticket.category_name
    and status = 'pending'
    and payment_expires_at > now()
    and id <> v_ticket.id;

  v_sold := greatest(v_category_sold, v_paid_count::integer);
  v_has_reservation := v_ticket.status = 'pending'
    and v_ticket.payment_expires_at is not null
    and v_ticket.payment_expires_at > now();

  if v_has_reservation or v_sold + v_reserved_count < v_capacity then
    update public.tickets
    set status = 'paid',
        transaction_id = v_transaction_id,
        payment_expires_at = null,
        qr_token_secret = coalesce(
          qr_token_secret,
          encode(gen_random_bytes(24), 'hex')
        )
    where id = v_ticket.id;

    update public.ticket_catalog
    set tickets_sold = v_sold + 1,
        is_active = is_active and v_sold + 1 < v_capacity
    where match_id = v_ticket.match_id
      and category_name = v_ticket.category_name;

    return 'paid';
  end if;

  update public.tickets
  set status = 'refund_required',
      transaction_id = v_transaction_id,
      payment_expires_at = null
  where id = v_ticket.id;

  return 'refund_required';
end;
$$;

revoke all on function public.confirm_ticket_payment(uuid, text, bigint)
  from public, anon, authenticated;
grant execute on function public.confirm_ticket_payment(uuid, text, bigint)
  to service_role;

create or replace function public.verify_or_confirm_ticket(p_ticket_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_ticket public.tickets%rowtype;
  v_caller_role text;
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    return jsonb_build_object(
      'success', false,
      'message', 'Connexion requise.'
    );
  end if;

  select role::text into v_caller_role
  from public.profiles
  where id = v_uid;

  select * into v_ticket
  from public.tickets
  where id = p_ticket_id;

  if not found then
    return jsonb_build_object(
      'success', false,
      'message', 'Billet introuvable.'
    );
  end if;

  if v_ticket.user_id is distinct from v_uid
     and coalesce(v_caller_role, '') not in ('super_admin', 'admin_competition') then
    return jsonb_build_object(
      'success', false,
      'message', 'Accès non autorisé.'
    );
  end if;

  return jsonb_build_object(
    'success', v_ticket.status in ('paid', 'used'),
    'status', v_ticket.status,
    'qr_token_secret', case
      when v_ticket.status in ('paid', 'used') then v_ticket.qr_token_secret
      else null
    end,
    'message', case
      when v_ticket.status = 'paid' then 'Billet payé et valide.'
      when v_ticket.status = 'used' then 'Ce billet a déjà été utilisé.'
      when v_ticket.status = 'pending' then 'Le paiement attend la confirmation de YengaPay.'
      else 'Ce billet n’est pas valide.'
    end
  );
end;
$$;

revoke all on function public.verify_or_confirm_ticket(uuid)
  from public, anon, authenticated;
grant execute on function public.verify_or_confirm_ticket(uuid)
  to authenticated;

do $$
declare
  v_table text;
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) then
    foreach v_table in array array['matches', 'match_results', 'competition_teams']
    loop
      if not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = v_table
      ) then
        execute format(
          'alter publication supabase_realtime add table public.%I',
          v_table
        );
      end if;
    end loop;
  end if;
end;
$$;

notify pgrst, 'reload schema';
