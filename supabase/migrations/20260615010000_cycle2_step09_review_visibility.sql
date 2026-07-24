-- =============================================================================
-- Cycle 2 Step 9: Review Visibility Fix
-- =============================================================================
--
-- Purpose: Implements Founder Finding 1 — "A completed ride review must be
-- visible in (a) operator dashboard history under the specific ride, (b) under
-- the specific customer account in the dashboard, (c) inside the customer portal
-- under the customer's ride history."
--
-- Background: ride_reviews table exists; submit_ride_review RPC exists;
-- review.html page exists; get_public_ride_reviews RPC exists (for testimonials
-- on the public landing page). But:
-- 1. The RLS policy on ride_reviews only allows operators to read.
--    Customers CANNOT read their own reviews directly.
-- 2. There is no batch-fetch RPC to retrieve reviews for a list of booking IDs.
-- 3. There is no RPC to retrieve a single review by booking ID.
-- 4. There is no per-customer reviews RPC (to show all reviews for one customer).
--
-- This migration adds 3 new RPCs (security definer, bypassing RLS) that allow
-- the operator dashboard and customer portal to fetch reviews without changing
-- the RLS policy (which would require a broader security review).
--
-- Scope: ADDITIVE only. No existing functions modified. No tables modified.
-- No RLS policy changes. No data migrations.
--
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 1. get_reviews_for_bookings: batch fetch reviews for a list of booking IDs
--    Used by: operator dashboard historyOrders, customer portal completedTable
-- -----------------------------------------------------------------------------
create or replace function public.get_reviews_for_bookings(p_booking_ids text[])
returns table (
    booking_id text,
    rating integer,
    comment text,
    created_at timestamptz,
    customer_name text
)
language sql
security definer
set search_path = public
as $$
    select
        r.booking_id,
        r.rating,
        r.comment,
        r.created_at,
        coalesce(nullif(b.name, ''), 'FleetConnect customer') as customer_name
    from public.ride_reviews r
    join public.bookings b on b.id = r.booking_id
    where r.booking_id = any(p_booking_ids)
    order by r.created_at desc;
$$;

revoke all on function public.get_reviews_for_bookings(text[]) from public;
grant execute on function public.get_reviews_for_bookings(text[]) to anon, authenticated;

-- -----------------------------------------------------------------------------
-- 2. get_review_for_booking: single booking lookup
--    Used by: operator dashboard booking-fiche modal, customer portal ride detail
-- -----------------------------------------------------------------------------
create or replace function public.get_review_for_booking(p_booking_id text)
returns table (
    booking_id text,
    rating integer,
    comment text,
    created_at timestamptz,
    customer_name text
)
language sql
security definer
set search_path = public
as $$
    select
        r.booking_id,
        r.rating,
        r.comment,
        r.created_at,
        coalesce(nullif(b.name, ''), 'FleetConnect customer') as customer_name
    from public.ride_reviews r
    join public.bookings b on b.id = r.booking_id
    where r.booking_id = p_booking_id
    limit 1;
$$;

revoke all on function public.get_review_for_booking(text) from public;
grant execute on function public.get_review_for_booking(text) to anon, authenticated;

-- -----------------------------------------------------------------------------
-- 3. get_reviews_for_customer: fetch all reviews for a customer's bookings
--    Used by: operator dashboard customer-account view
-- -----------------------------------------------------------------------------
create or replace function public.get_reviews_for_customer(p_customer_id text)
returns table (
    booking_id text,
    rating integer,
    comment text,
    created_at timestamptz,
    customer_name text
)
language sql
security definer
set search_path = public
as $$
    select
        r.booking_id,
        r.rating,
        r.comment,
        r.created_at,
        coalesce(nullif(b.name, ''), 'FleetConnect customer') as customer_name
    from public.ride_reviews r
    join public.bookings b on b.id = r.booking_id
    where b.customer_id = p_customer_id
    order by r.created_at desc;
$$;

revoke all on function public.get_reviews_for_customer(text) from public;
grant execute on function public.get_reviews_for_customer(text) to anon, authenticated;

notify pgrst, 'reload schema';

commit;
