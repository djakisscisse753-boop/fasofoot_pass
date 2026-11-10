-- Allow competition admins to update match status (live, postponed, cancelled, scheduled)
-- The status column already exists with its check constraint.
-- We only need to confirm that the RLS policy on matches allows UPDATE for admins.
-- This migration adds an explicit policy for status changes.

do $$ begin
  create policy "Competition admins update match status"
    on public.matches for update to authenticated
    using (exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid())
        and p.role::text in ('admin_competition', 'super_admin')
    ))
    with check (exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid())
        and p.role::text in ('admin_competition', 'super_admin')
    ));
exception when duplicate_object then null;
end $$;
