-- Ticket writes go through trusted Edge Functions or SECURITY DEFINER RPCs.
revoke all on public.tickets from public, anon, authenticated;
grant select on public.tickets to authenticated;

revoke all on public.ticket_catalog from public, anon;
grant select on public.ticket_catalog to authenticated;
