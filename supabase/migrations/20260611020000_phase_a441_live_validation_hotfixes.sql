begin;

create or replace function public.attach_booking_to_customer(p_booking_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
  v_customer_id text;
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Login required';
  end if;

  v_email := lower(nullif(auth.jwt()->>'email', ''));
  if v_email is null then
    raise exception 'Customer email unavailable';
  end if;

  if p_booking_id is null or length(trim(p_booking_id)) < 6 then
    raise exception 'Valid booking number is required';
  end if;

  v_customer_id := 'CUST-' || substring(regexp_replace(v_email, '[^a-z0-9]', '', 'gi') from 1 for 30);

  update public.bookings
  set customer_id = v_customer_id,
      user_id = auth.uid(),
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'customer_attached_at', now(),
        'customer_attached_by', auth.uid()
      )
  where id = trim(p_booking_id)
    and lower(email) = v_email
  returning jsonb_build_object(
    'id', id,
    'datetime', datetime,
    'time', time,
    'pickup', pickup,
    'destination', destination,
    'amount', amount,
    'status', status
  ) into v_result;

  if v_result is null then
    raise exception 'Booking not found for this customer email';
  end if;

  return v_result;
end;
$$;

revoke all on function public.attach_booking_to_customer(text) from public;
revoke all on function public.attach_booking_to_customer(text) from anon;
grant execute on function public.attach_booking_to_customer(text) to authenticated;

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
  v_raw_amount numeric;
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
  v_raw_amount := nullif(payload->>'amount','')::numeric;
  v_amount := greatest(v_raw_amount, 15);

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

  if v_raw_amount is null or v_raw_amount <= 0 then
    raise exception 'Positive calculated booking amount is required';
  end if;

  v_id := coalesce(nullif(payload->>'id',''), 'FC-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS'));
  v_form_data := coalesce(payload->'form_data', '{}'::jsonb) || jsonb_build_object(
    'pickup_place_id', v_pickup_place_id,
    'dropoff_place_id', v_dropoff_place_id,
    'route_distance_km', v_distance,
    'route_duration_min', v_duration,
    'raw_calculated_amount', v_raw_amount,
    'minimum_fare_applied', v_amount > v_raw_amount,
    'route_pricing_required', true
  );
  v_metadata := coalesce(payload->'metadata', '{}'::jsonb) || jsonb_build_object(
    'pickup_place_id', v_pickup_place_id,
    'dropoff_place_id', v_dropoff_place_id,
    'route_distance_km', v_distance,
    'route_duration_min', v_duration,
    'raw_calculated_amount', v_raw_amount,
    'minimum_fare_applied', v_amount > v_raw_amount,
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
    'amount', amount,
    'minimum_fare_applied', amount > v_raw_amount
  ) into v_result;

  return v_result;
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
  v_pickup_at timestamptz;
  v_event_type text;
  v_previous_driver jsonb;
  v_snapshot jsonb;
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

  v_previous_driver := v_booking.assigned_driver;

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
    v_previous_driver,
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
      status = 'reassignment_needed',
      assigned_driver_id = null,
      assigned_driver = null,
      assignment_token = null,
      assignment_accepted_at = null,
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'requires_reassignment', true,
        'declined_driver', v_previous_driver,
        'last_reassignment_event', v_event_type,
        'last_reassignment_at', now()
      )
  where id = v_booking.id
  returning jsonb_build_object(
    'id', id,
    'reference', id,
    'datetime', datetime,
    'time', time,
    'pickup', pickup,
    'destination', destination,
    'vehicle', vehicle,
    'amount', amount,
    'status', status,
    'customer', jsonb_build_object('name', name, 'email', email, 'phone', phone),
    'driver', coalesce(v_previous_driver, '{}'::jsonb),
    'metadata', metadata,
    'preferred_language', 'nl'
  ) into v_snapshot;

  return jsonb_build_object('id', v_booking.id, 'status', 'reassignment_needed', 'requires_reassignment', true, 'event_type', v_event_type, 'snapshot', v_snapshot);
end;
$$;

revoke all on function public.create_public_booking(jsonb) from public;
revoke all on function public.driver_decline_assignment(text) from public;
grant execute on function public.create_public_booking(jsonb) to anon, authenticated;
grant execute on function public.driver_decline_assignment(text) to anon, authenticated;

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

  update public.bookings
  set assignment_accepted_at = now(),
      status = 'assigned',
      metadata = coalesce(metadata, '{}'::jsonb)
        || jsonb_build_object(
          'requires_reassignment', false,
          'reassignment_pending_driver_acceptance', false,
          'reassignment_cleared_at', now()
        )
  where id = v_booking.id;

  return jsonb_build_object('id', v_booking.id, 'status', 'assigned', 'requires_reassignment', false);
end;
$$;

revoke all on function public.driver_accept_assignment(text) from public;
grant execute on function public.driver_accept_assignment(text) to anon, authenticated;

select pg_notify('pgrst', 'reload schema');

commit;
