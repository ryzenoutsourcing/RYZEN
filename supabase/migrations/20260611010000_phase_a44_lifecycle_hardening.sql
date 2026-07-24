begin;

create table if not exists public.account_requests (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  email text not null,
  phone text,
  company text,
  account_type text not null check (account_type in ('Operations', 'Partner', 'Driver', 'Client', 'Other')),
  notes text,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.account_requests enable row level security;

drop policy if exists "Service role full access account requests" on public.account_requests;
create policy "Service role full access account requests"
on public.account_requests
for all
to service_role
using (true)
with check (true);

drop policy if exists "Operators can view account requests" on public.account_requests;
create policy "Operators can view account requests"
on public.account_requests
for select
to authenticated
using (public.is_operator());

create or replace function public.submit_account_request(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
  v_email text;
  v_phone text;
  v_company text;
  v_account_type text;
  v_notes text;
  v_result jsonb;
begin
  if payload is null then
    raise exception 'Missing account request payload';
  end if;

  v_name := nullif(trim(payload->>'name'), '');
  v_email := lower(nullif(trim(payload->>'email'), ''));
  v_phone := nullif(trim(payload->>'phone'), '');
  v_company := nullif(trim(payload->>'company'), '');
  v_account_type := coalesce(nullif(trim(payload->>'account_type'), ''), 'Other');
  v_notes := nullif(trim(payload->>'notes'), '');

  if v_name is null then
    raise exception 'Name is required';
  end if;

  if v_email is null or position('@' in v_email) = 0 then
    raise exception 'Valid email is required';
  end if;

  if v_account_type not in ('Operations', 'Partner', 'Driver', 'Client', 'Other') then
    raise exception 'Invalid account type';
  end if;

  insert into public.account_requests (
    name, email, phone, company, account_type, notes, metadata
  )
  values (
    v_name,
    v_email,
    v_phone,
    v_company,
    v_account_type,
    v_notes,
    jsonb_build_object(
      'source', coalesce(payload->>'source', 'operator-login'),
      'user_agent', coalesce(payload->>'user_agent', ''),
      'submitted_at', now()
    )
  )
  returning jsonb_build_object(
    'id', id,
    'status', status,
    'created_at', created_at
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.submit_account_request(jsonb) from public;
grant execute on function public.submit_account_request(jsonb) to anon, authenticated;

alter table public.bookings add column if not exists pickup_place_id text;
alter table public.bookings add column if not exists dropoff_place_id text;
alter table public.bookings add column if not exists route_distance_km numeric;
alter table public.bookings add column if not exists route_duration_min integer;

create index if not exists idx_bookings_pickup_place_id on public.bookings (pickup_place_id);
create index if not exists idx_bookings_dropoff_place_id on public.bookings (dropoff_place_id);

alter table public.drivers add column if not exists phone text;
alter table public.drivers add column if not exists is_active boolean not null default true;
alter table public.drivers add column if not exists archived_at timestamptz;
alter table public.drivers add column if not exists updated_at timestamptz;

create or replace function public.update_operator_driver(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_driver_id uuid;
  v_partner_id integer;
  v_result jsonb;
begin
  if not public.is_operator() then
    raise exception 'Not authorized';
  end if;

  v_driver_id := nullif(payload->>'id','')::uuid;
  if v_driver_id is null then
    raise exception 'Driver id is required';
  end if;

  v_partner_id := nullif(payload->>'partner_id','')::integer;
  if v_partner_id is not null and not exists (select 1 from public.partners where id = v_partner_id) then
    raise exception 'Invalid partner';
  end if;

  update public.drivers
  set name = coalesce(nullif(payload->>'name',''), name),
      email = coalesce(nullif(payload->>'email',''), email),
      phone = coalesce(nullif(payload->>'phone',''), phone),
      vehicle = coalesce(nullif(payload->>'vehicle',''), vehicle),
      color = coalesce(nullif(payload->>'color',''), color),
      license_plate = coalesce(nullif(payload->>'license_plate',''), license_plate),
      partner_id = coalesce(v_partner_id, partner_id),
      updated_at = now()
  where id = v_driver_id
  returning jsonb_build_object('id', id, 'name', name, 'email', email, 'phone', phone, 'vehicle', vehicle, 'license_plate', license_plate, 'is_active', is_active) into v_result;

  if v_result is null then
    raise exception 'Driver not found';
  end if;

  return v_result;
end;
$$;

create or replace function public.archive_operator_driver(p_driver_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  if not public.is_operator() then
    raise exception 'Not authorized';
  end if;

  update public.drivers
  set is_active = false,
      archived_at = now(),
      updated_at = now()
  where id = p_driver_id
  returning jsonb_build_object('id', id, 'is_active', is_active, 'archived_at', archived_at) into v_result;

  if v_result is null then
    raise exception 'Driver not found';
  end if;

  return v_result;
end;
$$;

revoke all on function public.update_operator_driver(jsonb) from public;
revoke all on function public.archive_operator_driver(uuid) from public;
revoke all on function public.update_operator_driver(jsonb) from anon;
revoke all on function public.archive_operator_driver(uuid) from anon;
grant execute on function public.update_operator_driver(jsonb) to authenticated;
grant execute on function public.archive_operator_driver(uuid) to authenticated;

create or replace function public.create_public_booking(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id text;
  v_status text;
  v_pickup text;
  v_destination text;
  v_pickup_place_id text;
  v_dropoff_place_id text;
  v_distance numeric;
  v_duration integer;
  v_amount numeric;
  v_form_data jsonb;
  v_metadata jsonb;
  v_result jsonb;
begin
  if payload is null then
    raise exception 'Missing booking payload';
  end if;

  v_status := coalesce(nullif(payload->>'status',''), 'pending');
  if v_status not in ('pending','pending_payment') then
    raise exception 'Invalid booking status';
  end if;

  v_pickup := nullif(trim(payload->>'pickup'), '');
  v_destination := nullif(trim(payload->>'destination'), '');
  v_pickup_place_id := nullif(trim(coalesce(payload->>'pickup_place_id', payload #>> '{form_data,pickup_place_id}', payload #>> '{metadata,pickup_place_id}')), '');
  v_dropoff_place_id := nullif(trim(coalesce(payload->>'dropoff_place_id', payload #>> '{form_data,dropoff_place_id}', payload #>> '{metadata,dropoff_place_id}')), '');
  v_distance := nullif(coalesce(payload->>'route_distance_km', payload #>> '{form_data,route_distance_km}', payload #>> '{metadata,route_distance_km}', payload->>'distance_km', payload #>> '{form_data,distance_km}', payload #>> '{metadata,distance_km}'), '')::numeric;
  v_duration := nullif(coalesce(payload->>'route_duration_min', payload #>> '{form_data,route_duration_min}', payload #>> '{metadata,route_duration_min}', payload->>'duration_min', payload #>> '{form_data,duration_min}', payload #>> '{metadata,duration_min}'), '')::integer;
  v_amount := nullif(payload->>'amount','')::numeric;

  if v_pickup is null or length(v_pickup) < 3 then
    raise exception 'Valid pickup address is required';
  end if;

  if v_destination is null or length(v_destination) < 3 then
    raise exception 'Valid destination address is required';
  end if;

  if v_pickup_place_id is null or v_dropoff_place_id is null then
    raise exception 'Google-selected pickup and destination addresses are required';
  end if;

  if v_distance is null or v_distance <= 0 then
    raise exception 'Calculated route distance is required';
  end if;

  if v_duration is null or v_duration <= 0 then
    raise exception 'Calculated route duration is required';
  end if;

  if v_amount is null or v_amount <= 0 then
    raise exception 'Positive calculated booking amount is required';
  end if;

  v_id := coalesce(nullif(payload->>'id',''), 'FC-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS'));
  v_form_data := coalesce(payload->'form_data', '{}'::jsonb) || jsonb_build_object(
    'pickup_place_id', v_pickup_place_id,
    'dropoff_place_id', v_dropoff_place_id,
    'route_distance_km', v_distance,
    'route_duration_min', v_duration,
    'route_pricing_required', true
  );
  v_metadata := coalesce(payload->'metadata', '{}'::jsonb) || jsonb_build_object(
    'pickup_place_id', v_pickup_place_id,
    'dropoff_place_id', v_dropoff_place_id,
    'route_distance_km', v_distance,
    'route_duration_min', v_duration,
    'route_pricing_required', true
  );

  insert into public.bookings (
    id, datetime, time, name, email, phone, pickup, destination, flight_number,
    vehicle, extras, amount, payment, status, customer_id, form_data, metadata,
    partner_id, payment_status, user_id, pickup_place_id, dropoff_place_id,
    route_distance_km, route_duration_min
  ) values (
    v_id,
    nullif(payload->>'datetime',''),
    nullif(payload->>'time',''),
    nullif(payload->>'name',''),
    nullif(payload->>'email',''),
    nullif(payload->>'phone',''),
    v_pickup,
    v_destination,
    nullif(payload->>'flight_number',''),
    nullif(payload->>'vehicle',''),
    nullif(payload->>'extras',''),
    v_amount,
    nullif(payload->>'payment',''),
    v_status,
    nullif(payload->>'customer_id',''),
    v_form_data,
    v_metadata,
    nullif(payload->>'partner_id','')::integer,
    coalesce(nullif(payload->>'payment_status',''), 'unpaid'),
    auth.uid(),
    v_pickup_place_id,
    v_dropoff_place_id,
    v_distance,
    v_duration
  )
  returning jsonb_build_object(
    'id', id,
    'status', status,
    'payment_status', payment_status,
    'route_distance_km', route_distance_km,
    'route_duration_min', route_duration_min,
    'amount', amount
  ) into v_result;

  return v_result;
end;
$$;

create table if not exists public.booking_reassignment_events (
  id uuid primary key default gen_random_uuid(),
  booking_id text not null,
  previous_driver_id text,
  previous_driver jsonb,
  event_type text not null check (event_type in ('driver_declined_before_acceptance', 'driver_emergency_declined_after_acceptance')),
  reason text,
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

alter table public.booking_reassignment_events enable row level security;

drop policy if exists "Service role full access reassignment events" on public.booking_reassignment_events;
create policy "Service role full access reassignment events"
on public.booking_reassignment_events
for all
to service_role
using (true)
with check (true);

drop policy if exists "Operators can view reassignment events" on public.booking_reassignment_events;
create policy "Operators can view reassignment events"
on public.booking_reassignment_events
for select
to authenticated
using (public.is_operator());

create or replace function public.driver_decline_assignment(p_assignment_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.bookings%rowtype;
  v_pickup_at timestamptz;
  v_event_type text;
begin
  if p_assignment_token is null or length(trim(p_assignment_token)) < 10 then
    raise exception 'Invalid assignment token';
  end if;

  select * into v_booking from public.bookings where assignment_token = p_assignment_token limit 1;
  if not found then raise exception 'Assignment not found'; end if;
  if v_booking.assignment_declined_at is not null then raise exception 'Assignment already declined'; end if;
  if v_booking.status in ('completed', 'cancelled') then raise exception 'Booking is closed'; end if;
  if v_booking.assignment_sent_at is null or v_booking.assignment_sent_at < now() - interval '30 minutes' then
    raise exception 'Assignment expired';
  end if;

  if v_booking.assignment_accepted_at is not null then
    begin
      v_pickup_at := ((v_booking.datetime || ' ' || coalesce(v_booking.time, '00:00'))::timestamp at time zone 'Europe/Brussels');
    exception when others then
      raise exception 'Pickup time unavailable for emergency decline';
    end;

    if v_pickup_at <= now() + interval '40 minutes' then
      raise exception 'Emergency decline window closed';
    end if;
    v_event_type := 'driver_emergency_declined_after_acceptance';
  else
    v_event_type := 'driver_declined_before_acceptance';
  end if;

  insert into public.booking_reassignment_events (
    booking_id, previous_driver_id, previous_driver, event_type, reason, metadata
  ) values (
    v_booking.id,
    v_booking.assigned_driver_id::text,
    v_booking.assigned_driver,
    v_event_type,
    'Driver declined assignment from email action',
    jsonb_build_object(
      'assignment_token_present', true,
      'assignment_sent_at', v_booking.assignment_sent_at,
      'assignment_accepted_at', v_booking.assignment_accepted_at
    )
  );

  update public.bookings
  set assignment_declined_at = now(),
      status = 'accepted',
      assigned_driver_id = null,
      assigned_driver = null,
      assignment_token = null,
      assignment_accepted_at = null,
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'requires_reassignment', true,
        'last_reassignment_event', v_event_type,
        'last_reassignment_at', now()
      )
  where id = v_booking.id;

  return jsonb_build_object('id', v_booking.id, 'status', 'accepted', 'requires_reassignment', true, 'event_type', v_event_type);
end;
$$;

revoke all on function public.create_public_booking(jsonb) from public;
revoke all on function public.driver_decline_assignment(text) from public;
grant execute on function public.create_public_booking(jsonb) to anon, authenticated;
grant execute on function public.driver_decline_assignment(text) to anon, authenticated;

select pg_notify('pgrst', 'reload schema');

commit;
