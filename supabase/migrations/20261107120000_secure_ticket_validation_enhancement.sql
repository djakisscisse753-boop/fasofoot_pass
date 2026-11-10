-- Amélioration et fiabilisation de la validation sécurisée des billets

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
  -- 1. Vérification des droits du contrôleur / scanneur
  select role::text into caller_role
  from public.profiles
  where id = auth.uid();

  if coalesce(caller_role, '') not in ('agent_stade', 'super_admin', 'admin_competition', 'admin_club') then
    raise exception 'Accès réservé aux agents de contrôle et administrateurs' using errcode = '42501';
  end if;

  -- 2. Vérification du format du secret QR
  if p_qr_secret is null or length(trim(p_qr_secret)) < 8 then
    return jsonb_build_object('success', false, 'reason', 'invalid', 'message', 'QR Code invalide ou non reconnu.');
  end if;

  -- 3. Recherche du billet avec verrouillage exclusif
  select * into ticket_row
  from public.tickets
  where qr_token_secret = trim(p_qr_secret)
  for update;

  if not found then
    return jsonb_build_object('success', false, 'reason', 'invalid', 'message', 'Aucun billet correspondant trouvé.');
  end if;

  -- Récupération des infos du match associé
  select * into match_row
  from public.matches
  where id = ticket_row.match_id;

  -- Construction du json enrichi du billet
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

  -- 4. Vérification si déjà scanné / utilisé
  if ticket_row.status = 'used' then
    return jsonb_build_object(
      'success', false,
      'reason', 'used',
      'message', 'Ce billet a déjà été utilisé et scanné le ' || to_char(coalesce(ticket_row.scanned_at, now()), 'DD/MM/YYYY à HH24:MI'),
      'ticket', ticket_json
    );
  end if;

  -- 5. Vérification si payé
  if ticket_row.status <> 'paid' then
    return jsonb_build_object(
      'success', false,
      'reason', 'unpaid',
      'message', 'Ce billet n’a pas été payé ou a été annulé.',
      'ticket', ticket_json
    );
  end if;

  -- 6. Vérification du statut du match
  if match_row.id is not null then
    if match_row.status = 'cancelled' then
      return jsonb_build_object('success', false, 'reason', 'cancelled', 'message', 'Ce match a été annulé.', 'ticket', ticket_json);
    end if;

    if match_row.status = 'postponed' then
      return jsonb_build_object('success', false, 'reason', 'postponed', 'message', 'Ce match a été reporté à une date ultérieure.', 'ticket', ticket_json);
    end if;
  end if;

  -- 7. Validation unique : passage immédiat à 'used' avec horodatage et ID de l'agent
  update public.tickets
  set status = 'used',
      scanned_at = now(),
      scanned_by = auth.uid()
  where id = ticket_row.id and status = 'paid'
  returning * into ticket_row;

  if not found then
    return jsonb_build_object('success', false, 'reason', 'used', 'message', 'Ce billet a déjà été validé par un autre agent.');
  end if;

  -- Mise à jour du JSON avec le nouveau statut 'used' et 'scanned_at'
  ticket_json := ticket_json || jsonb_build_object(
    'status', 'used',
    'scanned_at', now(),
    'scanned_by', auth.uid()
  );

  return jsonb_build_object(
    'success', true,
    'reason', 'valid',
    'message', 'Billet validé avec succès ! Entrée autorisée.',
    'ticket', ticket_json
  );
end;
$$;

revoke all on function public.validate_ticket(text) from public, anon;
grant execute on function public.validate_ticket(text) to authenticated;
