begin;

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
        'reassignment_pending_driver_acceptance', false,
        'declined_driver', v_previous_driver,
        'last_reassignment_event', v_event_type,
        'last_reassignment_at', now()
      )
  where id = v_booking.id;

  v_snapshot := jsonb_build_object(
    'id', v_booking.id,
    'reference', v_booking.id,
    'datetime', v_booking.datetime,
    'time', v_booking.time,
    'pickup', v_booking.pickup,
    'destination', v_booking.destination,
    'vehicle', v_booking.vehicle,
    'amount', v_booking.amount,
    'status', 'reassignment_needed',
    'customer', jsonb_build_object('name', v_booking.name, 'email', v_booking.email, 'phone', v_booking.phone),
    'driver', v_previous_driver,
    'metadata', coalesce(v_booking.metadata, '{}'::jsonb) || jsonb_build_object(
      'requires_reassignment', true,
      'declined_driver', v_previous_driver,
      'last_reassignment_event', v_event_type,
      'last_reassignment_at', now()
    ),
    'preferred_language', 'nl'
  );

  return jsonb_build_object(
    'id', v_booking.id,
    'status', 'reassignment_needed',
    'requires_reassignment', true,
    'event_type', v_event_type,
    'snapshot', v_snapshot
  );
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
  v_is_reassignment boolean;
  v_notification_trigger text;
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

  v_is_reassignment := coalesce((v_booking.metadata->>'requires_reassignment')::boolean, false)
    or nullif(v_booking.metadata->>'last_reassignment_event', '') is not null;
  v_notification_trigger := case when v_is_reassignment then 'DRIVER_REASSIGNED' else 'DRIVER_ASSIGNED' end;

  update public.bookings
  set assignment_accepted_at = now(),
      status = 'assigned',
      metadata = coalesce(metadata, '{}'::jsonb)
        || jsonb_build_object(
          'requires_reassignment', false,
          'reassignment_pending_driver_acceptance', false,
          'reassignment_cleared_at', now(),
          'customer_notification_intent', v_notification_trigger,
          'last_driver_acceptance_at', now()
        )
  where id = v_booking.id;

  return jsonb_build_object(
    'id', v_booking.id,
    'status', 'assigned',
    'notification_trigger', v_notification_trigger,
    'is_reassignment', v_is_reassignment,
    'assignment_token', p_assignment_token
  );
end;
$$;

create or replace function public.record_customer_lifecycle_email(
  p_booking_id text,
  p_assignment_token text,
  p_trigger text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_allowed text[] := array['DRIVER_ASSIGNED', 'DRIVER_REASSIGNED', 'RIDE_COMPLETED_REVIEW_REQUEST'];
  v_booking public.bookings%rowtype;
  v_history jsonb;
begin
  if p_trigger <> all(v_allowed) then
    raise exception 'Unsupported customer lifecycle trigger';
  end if;

  if p_trigger in ('DRIVER_ASSIGNED', 'DRIVER_REASSIGNED') and (p_assignment_token is null or length(trim(p_assignment_token)) < 10) then
    raise exception 'Assignment token required for driver customer notification audit';
  end if;

  select * into v_booking
  from public.bookings
  where id = p_booking_id
    and (p_assignment_token is null or assignment_token = p_assignment_token)
  limit 1;

  if not found then
    raise exception 'Booking not found for lifecycle email audit';
  end if;

  if p_trigger in ('DRIVER_ASSIGNED', 'DRIVER_REASSIGNED') and v_booking.assignment_accepted_at is null then
    raise exception 'Driver acceptance required before customer confirmation audit';
  end if;

  if p_trigger = 'RIDE_COMPLETED_REVIEW_REQUEST' and v_booking.status <> 'completed' then
    raise exception 'Completed status required before review request audit';
  end if;

  v_history := coalesce(v_booking.metadata->'customer_notification_history', '[]'::jsonb)
    || jsonb_build_array(jsonb_build_object('trigger', p_trigger, 'sent_at', now()));

  update public.bookings
  set metadata = coalesce(metadata, '{}'::jsonb)
    || jsonb_build_object(
      'customer_notification_history', v_history,
      'last_customer_notification_trigger', p_trigger,
      'last_customer_notification_sent_at', now()
    )
    || case
      when p_trigger = 'DRIVER_ASSIGNED' then jsonb_build_object('customer_ride_confirmed_email_sent_at', now())
      when p_trigger = 'DRIVER_REASSIGNED' then jsonb_build_object('customer_driver_update_email_sent_at', now())
      when p_trigger = 'RIDE_COMPLETED_REVIEW_REQUEST' then jsonb_build_object('customer_review_request_email_sent_at', now())
      else '{}'::jsonb
    end
  where id = p_booking_id;

  return jsonb_build_object('id', p_booking_id, 'trigger', p_trigger, 'recorded', true);
end;
$$;

revoke all on function public.driver_accept_assignment(text) from public;
revoke all on function public.driver_decline_assignment(text) from public;
revoke all on function public.record_customer_lifecycle_email(text, text, text) from public;
grant execute on function public.driver_accept_assignment(text) to anon, authenticated;
grant execute on function public.driver_decline_assignment(text) to anon, authenticated;
grant execute on function public.record_customer_lifecycle_email(text, text, text) to anon, authenticated;

select pg_notify('pgrst', 'reload schema');

commit;
