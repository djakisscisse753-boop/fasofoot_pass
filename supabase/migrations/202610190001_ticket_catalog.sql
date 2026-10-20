create table if not exists public.ticket_catalog (
  match_id uuid not null,
  category_name text not null,
  price integer not null check (price > 0),
  is_active boolean not null default true,
  primary key (match_id, category_name)
);

alter table public.ticket_catalog enable row level security;
grant select on public.ticket_catalog to authenticated;
do $$ begin
  create policy "Authenticated users can read ticket catalog"
    on public.ticket_catalog for select to authenticated using (is_active);
exception when duplicate_object then null;
end $$;

do $$ begin
  create policy "Users can read their own profile"
    on public.profiles for select to authenticated
    using (id = (select auth.uid()));
exception when duplicate_object then null;
end $$;

create table if not exists public.tickets (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null,
  user_id uuid references auth.users(id) on delete set null,
  category_name text not null,
  customer_name text not null,
  customer_phone text not null,
  price integer not null check (price > 0),
  status text not null default 'pending'
    check (status in ('pending', 'paid', 'failed', 'used', 'cancelled')),
  qr_token_secret text unique,
  transaction_id text unique,
  scanned_at timestamptz,
  scanned_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

alter table public.tickets add column if not exists user_id uuid references auth.users(id) on delete set null;
alter table public.tickets add column if not exists category_name text;
alter table public.tickets add column if not exists customer_name text;
alter table public.tickets add column if not exists customer_phone text;
alter table public.tickets add column if not exists price integer;
alter table public.tickets add column if not exists status text not null default 'pending';
alter table public.tickets add column if not exists qr_token_secret text;
alter table public.tickets add column if not exists transaction_id text;
alter table public.tickets add column if not exists scanned_at timestamptz;
alter table public.tickets add column if not exists scanned_by uuid references public.profiles(id);
alter table public.tickets add column if not exists created_at timestamptz not null default now();
alter table public.tickets alter column qr_token_secret drop not null;

create unique index if not exists tickets_qr_token_secret_key
  on public.tickets (qr_token_secret) where qr_token_secret is not null;
create unique index if not exists tickets_transaction_id_key
  on public.tickets (transaction_id) where transaction_id is not null;

alter table public.tickets enable row level security;
revoke all on public.tickets from anon;
grant select on public.tickets to authenticated;
create index if not exists tickets_user_created_idx
  on public.tickets (user_id, created_at desc);

do $$ begin
  create policy "Users can read their own tickets"
    on public.tickets for select to authenticated
    using (user_id = (select auth.uid()));
exception when duplicate_object then null;
end $$;

drop policy if exists "Permettre la création de tickets" on public.tickets;
drop policy if exists "Permettre la lecture des tickets" on public.tickets;
drop policy if exists "Agent lit tous les tickets pour scan" on public.tickets;
drop policy if exists "Agent valide/scanne le ticket" on public.tickets;
do $$ begin
  create policy "Authorized agents can read tickets"
    on public.tickets for select to authenticated
    using (exists (
      select 1 from public.profiles
      where profiles.id = (select auth.uid())
        and profiles.role in ('agent_stade', 'admin_club', 'super_admin')
    ));
exception when duplicate_object then null;
end $$;

create or replace function public.validate_ticket(p_qr_secret text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_role text;
  ticket_row public.tickets%rowtype;
begin
  select role into caller_role from public.profiles where id = auth.uid();
  if coalesce(caller_role, '') not in ('agent_stade', 'admin_club', 'super_admin') then
    raise exception 'Accès réservé aux agents habilités' using errcode = '42501';
  end if;

  update public.tickets
    set status = 'used', scanned_at = now(), scanned_by = auth.uid()
    where qr_token_secret = p_qr_secret and status = 'paid'
    returning * into ticket_row;

  if found then
    return jsonb_build_object('success', true, 'message', 'Billet validé.', 'ticket', to_jsonb(ticket_row));
  end if;

  select * into ticket_row from public.tickets where qr_token_secret = p_qr_secret;
  if not found then
    return jsonb_build_object('success', false, 'message', 'Billet invalide ou inexistant.');
  end if;
  if ticket_row.status = 'used' then
    return jsonb_build_object('success', false, 'message', 'Ce billet a déjà été utilisé.', 'ticket', to_jsonb(ticket_row));
  end if;
  return jsonb_build_object('success', false, 'message', 'Ce billet n’est pas payable ou a été annulé.', 'ticket', to_jsonb(ticket_row));
end;
$$;

revoke all on function public.validate_ticket(text) from public, anon;
grant execute on function public.validate_ticket(text) to authenticated;

insert into public.ticket_catalog (match_id, category_name, price, is_active)
select match.id, zone.zone_name, category.price::integer,
       category.tickets_sold < category.total_tickets_offered
from public.match_ticket_categories as category
join public.matches as match on match.id = category.match_id
join public.stadium_zones as zone on zone.id = category.zone_id
where category.price > 0
on conflict (match_id, category_name) do update
set price = excluded.price, is_active = excluded.is_active;
