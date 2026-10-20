-- Restrict stadium validation to staff assigned to ticket control.
drop policy if exists "Authorized agents can read tickets" on public.tickets;
create policy "Ticket control staff can read tickets"
  on public.tickets for select to authenticated
  using (exists (
    select 1
    from public.profiles
    where profiles.id = (select auth.uid())
      and profiles.role::text in ('agent_stade', 'super_admin')
  ));

create or replace function public.validate_ticket(p_qr_secret text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  caller_role text;
  ticket_row public.tickets%rowtype;
  match_status text;
  match_date timestamptz;
begin
  select role::text into caller_role
  from public.profiles
  where id = auth.uid();

  if coalesce(caller_role, '') not in ('agent_stade', 'super_admin') then
    raise exception 'Accès réservé aux agents de contrôle' using errcode = '42501';
  end if;

  if p_qr_secret is null or length(p_qr_secret) <> 64 then
    return jsonb_build_object('success', false, 'reason', 'invalid', 'message', 'Billet invalide ou inexistant.');
  end if;

  select * into ticket_row
  from public.tickets
  where qr_token_secret = p_qr_secret
  for update;

  if not found then
    return jsonb_build_object('success', false, 'reason', 'invalid', 'message', 'Billet invalide ou inexistant.');
  end if;

  if ticket_row.status = 'used' then
    return jsonb_build_object('success', false, 'reason', 'used', 'message', 'Ce billet a déjà été utilisé.', 'ticket', to_jsonb(ticket_row));
  end if;

  if ticket_row.status <> 'paid' then
    return jsonb_build_object('success', false, 'reason', 'unpaid', 'message', 'Ce billet n’est pas payé ou a été annulé.', 'ticket', to_jsonb(ticket_row));
  end if;

  select status, date_time into match_status, match_date
  from public.matches
  where id = ticket_row.match_id;

  if not found then
    return jsonb_build_object('success', false, 'reason', 'match_missing', 'message', 'Le match associé à ce billet est introuvable.', 'ticket', to_jsonb(ticket_row));
  end if;

  if match_status = 'cancelled' then
    return jsonb_build_object('success', false, 'reason', 'cancelled', 'message', 'Ce match a été annulé. Contactez l’organisateur.', 'ticket', to_jsonb(ticket_row));
  end if;

  if match_status = 'postponed' then
    return jsonb_build_object('success', false, 'reason', 'postponed', 'message', 'Ce match a été reporté. Vérifiez la nouvelle date auprès de l’organisateur.', 'ticket', to_jsonb(ticket_row));
  end if;

  if match_status = 'finished' or now() > match_date + interval '6 hours' then
    return jsonb_build_object('success', false, 'reason', 'expired', 'message', 'Ce billet a expiré.', 'ticket', to_jsonb(ticket_row));
  end if;

  update public.tickets
  set status = 'used', scanned_at = now(), scanned_by = auth.uid()
  where id = ticket_row.id and status = 'paid'
  returning * into ticket_row;

  if not found then
    return jsonb_build_object('success', false, 'reason', 'used', 'message', 'Ce billet a déjà été utilisé.');
  end if;

  return jsonb_build_object('success', true, 'reason', 'valid', 'message', 'Billet validé.', 'ticket', to_jsonb(ticket_row));
end;
$$;

revoke all on function public.validate_ticket(text) from public, anon;
grant execute on function public.validate_ticket(text) to authenticated;
