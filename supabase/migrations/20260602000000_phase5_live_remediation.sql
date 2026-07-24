-- Phase 5: Live Supabase Remediation
-- Non-destructive schema/RLS/RPC repair based on live Phase 4.6 validation.

begin;

alter table public.customers add column if not exists user_id uuid references auth.users(id);
create index if not exists idx_customers_user_id on public.customers(user_id);

alter table public.bookings add column if not exists user_id uuid references auth.users(id);
alter table public.bookings add column if not exists metadata jsonb default '{}'::jsonb;
alter table public.bookings add column if not exists stripe_session_id text;
alter table public.bookings add column if not exists stripe_payment_intent_id text;
alter table public.bookings add column if not exists invoice_id text;
alter table public.bookings add column if not exists invoice_pdf_url text;
alter table public.bookings add column if not exists payment_method_type text;
create index if not exists idx_bookings_user_id on public.bookings(user_id);

create table if not exists public.payments (
    id uuid primary key default gen_random_uuid(),
    booking_id text references public.bookings(id),
    customer_id text,
    stripe_session_id text unique,
    stripe_payment_intent_id text unique,
    amount decimal(10, 2) not null,
    currency text default 'EUR',
    status text not null,
    payment_method text,
    created_at timestamptz default now(),
    updated_at timestamptz default now()
);

create table if not exists public.refunds (
    id uuid primary key default gen_random_uuid(),
    payment_id uuid references public.payments(id),
    booking_id text references public.bookings(id),
    stripe_refund_id text unique,
    amount decimal(10, 2) not null,
    status text not null,
    reason text,
    created_at timestamptz default now(),
    updated_at timestamptz default now()
);

create table if not exists public.invoices (
    id uuid primary key default gen_random_uuid(),
    booking_id text references public.bookings(id),
    stripe_invoice_id text unique,
    invoice_number text,
    invoice_pdf_url text,
    hosted_invoice_url text,
    status text,
    amount_due decimal(10, 2),
    amount_paid decimal(10, 2),
    created_at timestamptz default now()
);

create table if not exists public.settlements (
    id uuid primary key default gen_random_uuid(),
    stripe_payout_id text unique,
    amount decimal(10, 2) not null,
    currency text default 'EUR',
    status text,
    arrival_date timestamptz,
    created_at timestamptz default now()
);

create table if not exists public.transaction_ledger (
    id uuid primary key default gen_random_uuid(),
    booking_id text references public.bookings(id),
    entity_type text,
    entity_id uuid,
    amount decimal(10, 2) not null,
    entry_type text,
    description text,
    created_at timestamptz default now()
);

create index if not exists idx_payments_booking_id on public.payments(booking_id);
create index if not exists idx_refunds_booking_id on public.refunds(booking_id);
create index if not exists idx_invoices_booking_id on public.invoices(booking_id);
create index if not exists idx_ledger_booking_id on public.transaction_ledger(booking_id);

alter table public.bookings enable row level security;
alter table public.customers enable row level security;
alter table public.drivers enable row level security;
alter table public.partners enable row level security;
alter table public.payments enable row level security;
alter table public.refunds enable row level security;
alter table public.invoices enable row level security;
alter table public.settlements enable row level security;
alter table public.transaction_ledger enable row level security;

drop policy if exists "Allow all bookings" on public.bookings;
drop policy if exists "Allow all customers" on public.customers;
drop policy if exists "Allow authenticated delete drivers" on public.drivers;
drop policy if exists "Allow authenticated insert drivers" on public.drivers;
drop policy if exists "Allow authenticated select drivers" on public.drivers;
drop policy if exists "Allow authenticated update drivers" on public.drivers;
drop policy if exists "Allow authenticated delete partners" on public.partners;
drop policy if exists "Allow authenticated insert partners" on public.partners;
drop policy if exists "Allow authenticated select partners" on public.partners;
drop policy if exists "Allow authenticated update partners" on public.partners;
drop policy if exists "Allow public delete partners" on public.partners;
drop policy if exists "Allow public insert partners" on public.partners;
drop policy if exists "Allow public select partners" on public.partners;
drop policy if exists "Allow public update partners" on public.partners;

drop policy if exists "Service role full access bookings" on public.bookings;
create policy "Service role full access bookings" on public.bookings for all to service_role using (true) with check (true);
drop policy if exists "Service role full access customers" on public.customers;
create policy "Service role full access customers" on public.customers for all to service_role using (true) with check (true);
drop policy if exists "Service role full access drivers" on public.drivers;
create policy "Service role full access drivers" on public.drivers for all to service_role using (true) with check (true);
drop policy if exists "Service role full access partners" on public.partners;
create policy "Service role full access partners" on public.partners for all to service_role using (true) with check (true);

drop policy if exists "Authenticated customers view own profile" on public.customers;
create policy "Authenticated customers view own profile" on public.customers for select to authenticated
using (user_id = auth.uid() or email = auth.jwt()->>'email');

drop policy if exists "Authenticated customers update own profile" on public.customers;
create policy "Authenticated customers update own profile" on public.customers for update to authenticated
using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "Authenticated customers view own bookings" on public.bookings;
create policy "Authenticated customers view own bookings" on public.bookings for select to authenticated
using (user_id = auth.uid() or email = auth.jwt()->>'email');

drop policy if exists "Authenticated customers insert own bookings" on public.bookings;
create policy "Authenticated customers insert own bookings" on public.bookings for insert to authenticated
with check (user_id = auth.uid());

drop policy if exists "Authenticated customers update own bookings" on public.bookings;
create policy "Authenticated customers update own bookings" on public.bookings for update to authenticated
using (user_id = auth.uid()) with check (user_id = auth.uid());

create or replace function public.is_operator()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.partners p
    where p.user_id = auth.uid()
      and coalesce(p.is_hoofd, false) = true
  );
$$;

revoke all on function public.is_operator() from public;
grant execute on function public.is_operator() to authenticated;

drop policy if exists "Operators can view bookings" on public.bookings;
create policy "Operators can view bookings" on public.bookings for select to authenticated
using (public.is_operator());

drop policy if exists "Operators can update bookings" on public.bookings;
create policy "Operators can update bookings" on public.bookings for update to authenticated
using (public.is_operator()) with check (public.is_operator());

drop policy if exists "Operators can view drivers" on public.drivers;
create policy "Operators can view drivers" on public.drivers for select to authenticated
using (public.is_operator());

drop policy if exists "Operators can manage drivers" on public.drivers;
create policy "Operators can manage drivers" on public.drivers for all to authenticated
using (public.is_operator()) with check (public.is_operator());

drop policy if exists "Operators can view partners" on public.partners;
create policy "Operators can view partners" on public.partners for select to authenticated
using (public.is_operator() or user_id = auth.uid());

drop policy if exists "Operators can manage partners" on public.partners;
create policy "Operators can manage partners" on public.partners for all to authenticated
using (public.is_operator()) with check (public.is_operator());

drop policy if exists "Authenticated partner users view own partner" on public.partners;
create policy "Authenticated partner users view own partner" on public.partners for select to authenticated
using (user_id = auth.uid());

drop policy if exists "Service role full access payments" on public.payments;
create policy "Service role full access payments" on public.payments for all to service_role using (true) with check (true);
drop policy if exists "Service role full access refunds" on public.refunds;
create policy "Service role full access refunds" on public.refunds for all to service_role using (true) with check (true);
drop policy if exists "Service role full access invoices" on public.invoices;
create policy "Service role full access invoices" on public.invoices for all to service_role using (true) with check (true);
drop policy if exists "Service role full access settlements" on public.settlements;
create policy "Service role full access settlements" on public.settlements for all to service_role using (true) with check (true);
drop policy if exists "Service role full access ledger" on public.transaction_ledger;
create policy "Service role full access ledger" on public.transaction_ledger for all to service_role using (true) with check (true);

drop policy if exists "Users can view own payments" on public.payments;
create policy "Users can view own payments" on public.payments for select to authenticated
using (customer_id = (select id from public.customers where user_id = auth.uid() or email = auth.jwt()->>'email' limit 1));

drop policy if exists "Users can view own refunds" on public.refunds;
create policy "Users can view own refunds" on public.refunds for select to authenticated
using (booking_id in (select id from public.bookings where user_id = auth.uid() or email = auth.jwt()->>'email'));

drop policy if exists "Users can view own invoices" on public.invoices;
create policy "Users can view own invoices" on public.invoices for select to authenticated
using (booking_id in (select id from public.bookings where user_id = auth.uid() or email = auth.jwt()->>'email'));

create or replace function public.create_public_booking(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id text;
  v_status text;
  v_result jsonb;
begin
  if payload is null then
    raise exception 'Missing booking payload';
  end if;

  v_status := coalesce(nullif(payload->>'status',''), 'pending');
  if v_status not in ('pending','pending_payment') then
    raise exception 'Invalid booking status';
  end if;

  v_id := coalesce(nullif(payload->>'id',''), 'FC-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS'));

  insert into public.bookings (
    id, datetime, time, name, email, phone, pickup, destination, flight_number,
    vehicle, extras, amount, payment, status, customer_id, form_data, metadata,
    partner_id, payment_status, user_id
  ) values (
    v_id,
    nullif(payload->>'datetime',''),
    nullif(payload->>'time',''),
    nullif(payload->>'name',''),
    nullif(payload->>'email',''),
    nullif(payload->>'phone',''),
    nullif(payload->>'pickup',''),
    nullif(payload->>'destination',''),
    nullif(payload->>'flight_number',''),
    nullif(payload->>'vehicle',''),
    nullif(payload->>'extras',''),
    nullif(payload->>'amount','')::numeric,
    nullif(payload->>'payment',''),
    v_status,
    nullif(payload->>'customer_id',''),
    coalesce(payload->'form_data', '{}'::jsonb),
    coalesce(payload->'metadata', '{}'::jsonb),
    nullif(payload->>'partner_id','')::integer,
    coalesce(nullif(payload->>'payment_status',''), 'unpaid'),
    auth.uid()
  )
  returning jsonb_build_object('id', id, 'status', status, 'payment_status', payment_status) into v_result;

  return v_result;
end;
$$;

create or replace function public.driver_accept_assignment(p_assignment_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.bookings%rowtype;
begin
  if p_assignment_token is null or length(trim(p_assignment_token)) < 10 then
    raise exception 'Invalid assignment token';
  end if;

  select * into v_booking from public.bookings where assignment_token = p_assignment_token limit 1;
  if not found then raise exception 'Assignment not found'; end if;
  if v_booking.assignment_accepted_at is not null then raise exception 'Assignment already accepted'; end if;
  if v_booking.assignment_declined_at is not null then raise exception 'Assignment already declined'; end if;
  if v_booking.assignment_sent_at is null or v_booking.assignment_sent_at < now() - interval '30 minutes' then
    raise exception 'Assignment expired';
  end if;

  update public.bookings set assignment_accepted_at = now(), status = 'assigned' where id = v_booking.id;
  return jsonb_build_object('id', v_booking.id, 'status', 'assigned');
end;
$$;

create or replace function public.driver_decline_assignment(p_assignment_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.bookings%rowtype;
begin
  if p_assignment_token is null or length(trim(p_assignment_token)) < 10 then
    raise exception 'Invalid assignment token';
  end if;

  select * into v_booking from public.bookings where assignment_token = p_assignment_token limit 1;
  if not found then raise exception 'Assignment not found'; end if;
  if v_booking.assignment_accepted_at is not null then raise exception 'Assignment already accepted'; end if;
  if v_booking.assignment_declined_at is not null then raise exception 'Assignment already declined'; end if;
  if v_booking.assignment_sent_at is null or v_booking.assignment_sent_at < now() - interval '30 minutes' then
    raise exception 'Assignment expired';
  end if;

  update public.bookings
  set assignment_declined_at = now(),
      status = 'accepted',
      assigned_driver_id = null,
      assigned_driver = null,
      assignment_token = null
  where id = v_booking.id;

  return jsonb_build_object('id', v_booking.id, 'status', 'accepted');
end;
$$;

create or replace function public.sync_booking_user_id()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.user_id is null and auth.uid() is not null then
    new.user_id := auth.uid();
  end if;
  return new;
end;
$$;

drop trigger if exists tr_sync_booking_user_id on public.bookings;
create trigger tr_sync_booking_user_id
before insert on public.bookings
for each row execute function public.sync_booking_user_id();

revoke all on function public.create_public_booking(jsonb) from public;
revoke all on function public.driver_accept_assignment(text) from public;
revoke all on function public.driver_decline_assignment(text) from public;
grant execute on function public.create_public_booking(jsonb) to anon, authenticated;
grant execute on function public.driver_accept_assignment(text) to anon, authenticated;
grant execute on function public.driver_decline_assignment(text) to anon, authenticated;

commit;
