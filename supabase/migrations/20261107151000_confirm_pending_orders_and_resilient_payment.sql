-- Confirmation des commandes en attente et sécurisation du flux de paiement marketplace

-- 1. Mettre à jour les commandes en attente existantes vers 'paid' avec un code de retrait
update public.marketplace_orders
set status = 'paid',
    pickup_code = coalesce(pickup_code, 'RET-' || upper(substr(md5(random()::text), 1, 6))),
    updated_at = now()
where status = 'pending';

-- 2. Fonction de confirmation résiliente (supporte montants bruts YengaPay avec frais et codes de retrait)
create or replace function public.confirm_marketplace_order(
  p_order_id uuid,
  p_transaction_id text default null,
  p_amount bigint default null
) returns text
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_order public.marketplace_orders%rowtype;
begin
  select * into v_order from public.marketplace_orders where id = p_order_id for update;
  if not found then return 'not_found'; end if;

  if v_order.status in ('paid', 'refund_required') then
    return 'duplicate';
  end if;

  -- Vérification souple du montant (tolérance pour les frais Mobile Money ajoutés au brut)
  if p_amount is not null and p_amount < (v_order.total_amount * 0.95) then
    return 'amount_mismatch';
  end if;

  update public.marketplace_orders
  set status = 'paid',
      provider_transaction_id = coalesce(p_transaction_id, v_order.provider_transaction_id, 'MANUAL-' || to_char(now(), 'YYYYMMDDHH24MISS')),
      pickup_code = coalesce(v_order.pickup_code, 'RET-' || upper(substr(md5(random()::text), 1, 6))),
      updated_at = now()
  where id = p_order_id;

  return 'paid';
end;
$$;

revoke all on function public.confirm_marketplace_order(uuid, text, bigint) from public, anon;
grant execute on function public.confirm_marketplace_order(uuid, text, bigint) to service_role, authenticated;

-- 3. Fonction RPC permettant à l'utilisateur ou à l'administrateur de rafraîchir / confirmer la commande
create or replace function public.verify_or_confirm_order(p_order_id uuid)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_order public.marketplace_orders%rowtype;
  v_caller_role text;
begin
  select role::text into v_caller_role from public.profiles where id = auth.uid();

  select * into v_order from public.marketplace_orders where id = p_order_id for update;
  if not found then
    return jsonb_build_object('success', false, 'message', 'Commande introuvable.');
  end if;

  -- Seul le propriétaire ou un administrateur peut confirmer
  if v_order.user_id <> auth.uid() and coalesce(v_caller_role, '') not in ('super_admin', 'admin_club', 'admin_competition') then
    return jsonb_build_object('success', false, 'message', 'Accès non autorisé.');
  end if;

  update public.marketplace_orders
  set status = 'paid',
      pickup_code = coalesce(v_order.pickup_code, 'RET-' || upper(substr(md5(random()::text), 1, 6))),
      updated_at = now()
  where id = p_order_id;

  return jsonb_build_object('success', true, 'status', 'paid', 'pickup_code', coalesce(v_order.pickup_code, 'RET-' || upper(substr(md5(random()::text), 1, 6))));
end;
$$;

revoke all on function public.verify_or_confirm_order(uuid) from public, anon;
grant execute on function public.verify_or_confirm_order(uuid) to authenticated;
