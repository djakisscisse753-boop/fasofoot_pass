-- Applied to Supabase as migration 20261110130501.
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
      and coalesce(v_caller_role, '') <> 'super_admin'
      and not (
        coalesce(v_caller_role, '') = 'admin_club'
        and public.is_marketplace_club_order_admin(p_order_id)
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
