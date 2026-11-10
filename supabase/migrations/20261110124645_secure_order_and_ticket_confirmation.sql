-- Applied to Supabase as migration 20261110124645.
create or replace function public.confirm_marketplace_order(
  p_order_id uuid,
  p_transaction_id text default null,
  p_amount bigint default null
) returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_order public.marketplace_orders%rowtype;
  v_unavailable boolean;
begin
  if p_transaction_id is null or nullif(btrim(p_transaction_id), '') is null
    or p_amount is null or p_amount <= 0 then
    return 'invalid_payment';
  end if;

  select * into v_order
  from public.marketplace_orders
  where id = p_order_id
  for update;

  if not found then
    return 'not_found';
  end if;

  if v_order.status in ('paid', 'refund_required') then
    if v_order.provider_transaction_id = p_transaction_id then
      return case
        when v_order.status = 'paid' then 'duplicate'
        else 'refund_required'
      end;
    end if;
    return 'not_pending';
  end if;

  if p_amount < v_order.total_amount * 0.95 then
    return 'amount_mismatch';
  end if;

  if v_order.status not in ('pending', 'expired') then
    return 'not_pending';
  end if;

  if not exists (
    select 1
    from public.marketplace_order_items
    where order_id = p_order_id
  ) then
    update public.marketplace_orders
    set status = 'refund_required',
        provider_transaction_id = p_transaction_id,
        updated_at = now()
    where id = p_order_id;
    return 'refund_required';
  end if;

  if v_order.status = 'pending' then
    update public.marketplace_orders
    set status = 'paid',
        provider_transaction_id = p_transaction_id,
        updated_at = now()
    where id = p_order_id;
    return 'paid';
  end if;

  if exists (
    select 1
    from public.marketplace_order_items
    where order_id = p_order_id and product_id is null
  ) then
    v_unavailable := true;
  else
    perform p.id
    from public.products p
    join (
      select product_id
      from public.marketplace_order_items
      where order_id = p_order_id
      group by product_id
    ) items on items.product_id = p.id
    order by p.id
    for update of p;

    select exists (
      select 1
      from public.marketplace_order_items i
      left join public.products p on p.id = i.product_id
      where i.order_id = p_order_id
        and (p.id is null or not p.is_active or coalesce(p.stock, 0) < i.quantity)
    ) into v_unavailable;
  end if;

  if v_unavailable then
    update public.marketplace_orders
    set status = 'refund_required',
        provider_transaction_id = p_transaction_id,
        updated_at = now()
    where id = p_order_id;
    return 'refund_required';
  end if;

  update public.products p
  set stock = coalesce(p.stock, 0) - i.quantity,
      updated_at = now()
  from public.marketplace_order_items i
  where i.order_id = p_order_id
    and i.product_id = p.id;

  update public.marketplace_orders
  set status = 'paid',
      provider_transaction_id = p_transaction_id,
      updated_at = now()
  where id = p_order_id;

  return 'paid';
end;
$$;

revoke all on function public.confirm_marketplace_order(uuid, text, bigint)
  from public, anon, authenticated;
grant execute on function public.confirm_marketplace_order(uuid, text, bigint)
  to service_role;

create or replace function public.verify_or_confirm_order(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_order public.marketplace_orders%rowtype;
  v_caller_role text;
begin
  select role::text into v_caller_role
  from public.profiles
  where id = (select auth.uid());

  select * into v_order
  from public.marketplace_orders
  where id = p_order_id;

  if not found then
    return jsonb_build_object(
      'success', false,
      'message', 'Commande introuvable.'
    );
  end if;

  if (select auth.uid()) is null
    or (
      v_order.user_id is distinct from (select auth.uid())
      and coalesce(v_caller_role, '') not in (
        'super_admin', 'admin_club', 'admin_competition'
      )
    ) then
    return jsonb_build_object(
      'success', false,
      'message', 'Accès non autorisé.'
    );
  end if;

  if v_order.status = 'paid'
    and v_order.provider_transaction_id is not null
    and v_order.provider_transaction_id not like 'MANUAL-%' then
    return jsonb_build_object(
      'success', true,
      'status', v_order.status,
      'pickup_code', v_order.pickup_code
    );
  end if;

  if v_order.status = 'paid' then
    return jsonb_build_object(
      'success', false,
      'status', 'review_required',
      'message', 'Cette commande doit être rapprochée avec YengaPay avant sa remise.'
    );
  end if;

  return jsonb_build_object(
    'success', false,
    'status', v_order.status,
    'message', 'Le paiement n’a pas encore été confirmé par YengaPay.'
  );
end;
$$;

revoke all on function public.verify_or_confirm_order(uuid)
  from public, anon;
grant execute on function public.verify_or_confirm_order(uuid)
  to authenticated;

create or replace function public.validate_ticket(p_qr_secret text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  caller_role text;
  ticket_row public.tickets%rowtype;
  match_row public.matches%rowtype;
  ticket_json jsonb;
begin
  select role::text into caller_role
  from public.profiles
  where id = (select auth.uid());

  if coalesce(caller_role, '') not in ('agent_stade', 'super_admin') then
    raise exception 'Accès réservé aux agents de stade et administrateurs plateforme'
      using errcode = '42501';
  end if;

  if p_qr_secret is null or length(trim(p_qr_secret)) < 8 then
    return jsonb_build_object(
      'success', false,
      'reason', 'invalid',
      'message', 'QR Code invalide ou non reconnu.'
    );
  end if;

  select * into ticket_row
  from public.tickets
  where qr_token_secret = trim(p_qr_secret)
  for update;

  if not found then
    return jsonb_build_object(
      'success', false,
      'reason', 'invalid',
      'message', 'Aucun billet correspondant trouvé.'
    );
  end if;

  select * into match_row
  from public.matches
  where id = ticket_row.match_id;

  ticket_json := to_jsonb(ticket_row);
  if match_row.id is not null then
    ticket_json := ticket_json || jsonb_build_object(
      'match', jsonb_build_object(
        'teams', match_row.teams,
        'date_time', match_row.date_time,
        'stadium', match_row.stadium,
        'city', match_row.city
      )
    );
  end if;

  if ticket_row.status = 'used' then
    return jsonb_build_object(
      'success', false,
      'reason', 'used',
      'message', 'Ce billet a déjà été utilisé et scanné le '
        || to_char(coalesce(ticket_row.scanned_at, now()), 'DD/MM/YYYY à HH24:MI'),
      'ticket', ticket_json
    );
  end if;

  if ticket_row.status <> 'paid' then
    return jsonb_build_object(
      'success', false,
      'reason', 'unpaid',
      'message', 'Ce billet n’a pas été payé ou a été annulé.',
      'ticket', ticket_json
    );
  end if;

  if match_row.id is not null then
    if match_row.status = 'cancelled' then
      return jsonb_build_object(
        'success', false,
        'reason', 'cancelled',
        'message', 'Ce match a été annulé.',
        'ticket', ticket_json
      );
    end if;

    if match_row.status = 'postponed' then
      return jsonb_build_object(
        'success', false,
        'reason', 'postponed',
        'message', 'Ce match a été reporté à une date ultérieure.',
        'ticket', ticket_json
      );
    end if;
  end if;

  update public.tickets
  set status = 'used',
      scanned_at = now(),
      scanned_by = (select auth.uid())
  where id = ticket_row.id
    and status = 'paid'
  returning * into ticket_row;

  if not found then
    return jsonb_build_object(
      'success', false,
      'reason', 'used',
      'message', 'Ce billet a déjà été validé par un autre agent.'
    );
  end if;

  ticket_json := ticket_json || jsonb_build_object(
    'status', 'used',
    'scanned_at', now(),
    'scanned_by', (select auth.uid())
  );

  return jsonb_build_object(
    'success', true,
    'reason', 'valid',
    'message', 'Billet validé avec succès ! Entrée autorisée.',
    'ticket', ticket_json
  );
end;
$$;

revoke all on function public.validate_ticket(text)
  from public, anon;
grant execute on function public.validate_ticket(text)
  to authenticated;
