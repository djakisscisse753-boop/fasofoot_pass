alter table public.marketplace_orders
  drop constraint if exists marketplace_orders_status_check;
alter table public.marketplace_orders
  add constraint marketplace_orders_status_check
  check (status in ('pending', 'paid', 'failed', 'cancelled', 'expired', 'refund_required'));

create or replace function public.confirm_marketplace_order(
  p_order_id uuid, p_transaction_id text, p_amount bigint
) returns text language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_order public.marketplace_orders%rowtype;
  v_unavailable boolean;
begin
  select * into v_order from public.marketplace_orders where id = p_order_id for update;
  if not found then return 'not_found'; end if;
  if v_order.status in ('paid', 'refund_required') and v_order.provider_transaction_id = p_transaction_id then
    return case when v_order.status = 'paid' then 'duplicate' else 'refund_required' end;
  end if;
  if v_order.total_amount <> p_amount then return 'amount_mismatch'; end if;
  if v_order.status = 'pending' then
    update public.marketplace_orders set status = 'paid', provider_transaction_id = p_transaction_id,
      updated_at = now() where id = p_order_id;
    return 'paid';
  end if;
  if v_order.status <> 'expired' then return 'not_pending'; end if;

  -- If the checkout was completed after its stock reservation expired, reacquire stock atomically.
  if exists (select 1 from public.marketplace_order_items where order_id = p_order_id and product_id is null) then
    v_unavailable := true;
  else
    perform p.id from public.products p
    join (select product_id from public.marketplace_order_items where order_id = p_order_id group by product_id) i
      on i.product_id = p.id
    order by p.id for update of p;
    select exists (
      select 1 from public.marketplace_order_items i
      left join public.products p on p.id = i.product_id
      where i.order_id = p_order_id and (p.id is null or not p.is_active or coalesce(p.stock, 0) < i.quantity)
    ) into v_unavailable;
  end if;

  if v_unavailable then
    update public.marketplace_orders set status = 'refund_required', provider_transaction_id = p_transaction_id,
      updated_at = now() where id = p_order_id;
    return 'refund_required';
  end if;
  update public.products p set stock = coalesce(p.stock, 0) - i.quantity, updated_at = now()
  from public.marketplace_order_items i where i.order_id = p_order_id and i.product_id = p.id;
  update public.marketplace_orders set status = 'paid', provider_transaction_id = p_transaction_id,
    updated_at = now() where id = p_order_id;
  return 'paid';
end;
$$;

revoke all on function public.confirm_marketplace_order(uuid, text, bigint) from public, anon, authenticated;
grant execute on function public.confirm_marketplace_order(uuid, text, bigint) to service_role;
