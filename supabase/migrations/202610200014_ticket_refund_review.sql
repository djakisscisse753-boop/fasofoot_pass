alter table public.tickets
  add column if not exists refund_resolution text not null default 'open',
  add column if not exists refund_reference text,
  add column if not exists refund_note text,
  add column if not exists refund_resolved_at timestamptz,
  add column if not exists refund_resolved_by uuid references public.profiles(id) on delete set null;

do $$ begin
  alter table public.tickets
    add constraint tickets_refund_resolution_check
    check (refund_resolution in ('open', 'refunded', 'payment_reversed'));
exception when duplicate_object then null;
end $$;

do $$ begin
  alter table public.tickets
    add constraint tickets_refund_resolution_audit_check
    check (
      (refund_resolution = 'open'
        and refund_resolved_at is null
        and refund_resolved_by is null)
      or (refund_resolution <> 'open'
        and refund_resolved_at is not null
        and refund_resolved_by is not null
        and nullif(btrim(refund_reference), '') is not null)
    );
exception when duplicate_object then null;
end $$;

create index if not exists tickets_refund_review_idx
  on public.tickets (refund_resolution, created_at desc)
  where status = 'refund_required';

create or replace function public.resolve_ticket_refund(
  p_ticket_id uuid,
  p_resolution text,
  p_reference text,
  p_note text default null
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text;
begin
  select role::text into v_role
  from public.profiles
  where id = (select auth.uid());

  if v_role is distinct from 'super_admin' then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_resolution not in ('refunded', 'payment_reversed') then
    raise exception 'invalid resolution' using errcode = '22023';
  end if;
  if p_reference is null or char_length(btrim(p_reference)) not between 3 and 120 then
    raise exception 'valid external reference is required' using errcode = '22023';
  end if;
  if p_note is not null and char_length(p_note) > 500 then
    raise exception 'note is too long' using errcode = '22023';
  end if;

  update public.tickets
  set refund_resolution = p_resolution,
      refund_reference = btrim(p_reference),
      refund_note = nullif(btrim(p_note), ''),
      refund_resolved_at = now(),
      refund_resolved_by = (select auth.uid())
  where id = p_ticket_id
    and status = 'refund_required'
    and refund_resolution = 'open';

  if not found then
    raise exception 'ticket is not awaiting refund review' using errcode = 'P0002';
  end if;
end;
$$;

revoke all on function public.resolve_ticket_refund(uuid, text, text, text)
  from public, anon;
grant execute on function public.resolve_ticket_refund(uuid, text, text, text)
  to authenticated;
