-- =============================================================================
-- Cycle 3 B-5: Add RLS policies to onderaannemers table
-- =============================================================================
--
-- Purpose: onderaannemers has RLS enabled but no policies (audit finding F-003).
-- This is a dormant risk: any non-service-role query to onderaannemers returns
-- zero rows. Add a SELECT policy for authenticated (matching the partners
-- table pattern) and an ALL policy for service_role.
--
-- Scope: ADDITIVE only. No existing policies modified. No data changed.
--
-- =============================================================================

begin;

drop policy if exists "Operators can view onderaannemers" on public.onderaannemers;
create policy "Operators can view onderaannemers"
  on public.onderaannemers for select
  to authenticated
  using (true);

drop policy if exists "Service role full access onderaannemers" on public.onderaannemers;
create policy "Service role full access onderaannemers"
  on public.onderaannemers for all
  to service_role
  using (true) with check (true);

commit;
