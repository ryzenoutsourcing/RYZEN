begin;

create or replace function public.partner_pwa_context()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
  v_driver public.drivers%rowtype;
  v_partner public.partners%rowtype;
  v_role text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  v_email := lower(nullif(auth.jwt()->>'email', ''));
  if v_email is null then
    raise exception 'Authenticated email unavailable';
  end if;

  select *
  into v_driver
  from public.drivers
  where lower(email) = v_email
    and is_active is not false
  order by updated_at desc nulls last
  limit 1;

  if found and v_driver.partner_id is not null then
    select *
    into v_partner
    from public.partners
    where id = v_driver.partner_id
    limit 1;
  end if;

  if v_partner.id is null then
    select *
    into v_partner
    from public.partners
    where user_id = auth.uid()
       or lower(coalesce(email, '')) = v_email
    order by is_hoofd desc nulls last, id
    limit 1;
  end if;

  if v_driver.id is not null and v_partner.id is not null then
    v_role := 'driver_partner';
  elsif v_driver.id is not null then
    v_role := 'driver';
  elsif v_partner.id is not null then
    v_role := 'partner';
  else
    raise exception 'No active driver or partner profile linked to this account';
  end if;

  return jsonb_build_object(
    'role', v_role,
    'email', v_email,
    'driver', case when v_driver.id is null then null else jsonb_build_object(
      'id', v_driver.id,
      'driver_code', v_driver.driver_code,
      'name', v_driver.name,
      'email', v_driver.email,
      'phone', v_driver.phone,
      'vehicle', v_driver.vehicle,
      'license_plate', v_driver.license_plate,
      'partner_id', v_driver.partner_id
    ) end,
    'partner', case when v_partner.id is null then null else jsonb_build_object(
      'id', v_partner.id,
      'name', v_partner.name,
      'email', v_partner.email,
      'phone', v_partner.phone,
      'is_hoofd', v_partner.is_hoofd
    ) end
  );
end;
$$;

create or replace function public.partner_pwa_rides()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_context jsonb;
  v_driver_id uuid;
  v_partner_id integer;
begin
  v_context := public.partner_pwa_context();
  v_driver_id := nullif(v_context #>> '{driver,id}', '')::uuid;
  v_partner_id := nullif(v_context #>> '{partner,id}', '')::integer;

  return jsonb_build_object(
    'context', v_context,
    'rides', (
      select coalesce(jsonb_agg(
        to_jsonb(b)
        || jsonb_build_object(
          'passenger', jsonb_build_object(
            'name', b.name,
            'email', b.email,
            'phone', b.phone
          ),
          'driver', case when d.id is null then b.assigned_driver else jsonb_build_object(
            'id', d.id,
            'name', d.name,
            'email', d.email,
            'phone', d.phone,
            'vehicle', d.vehicle,
            'license_plate', d.license_plate
          ) end,
          'partner_name', p.name,
          'pwa_driver_can_act', v_driver_id is not null and b.assigned_driver_id = v_driver_id
        )
        order by b.created_at desc
      ), '[]'::jsonb)
      from public.bookings b
      left join public.drivers d on d.id = b.assigned_driver_id
      left join public.partners p on p.id = b.partner_id
      where (
        (v_driver_id is not null and b.assigned_driver_id = v_driver_id)
        or (
          v_partner_id is not null
          and (
            b.partner_id = v_partner_id
            or b.assigned_driver_id in (
              select d2.id from public.drivers d2 where d2.partner_id = v_partner_id
            )
          )
        )
      )
      and b.status in ('assignment_sent','assigned','accepted','reassignment_needed','completed','cancelled')
    )
  );
end;
$$;

create or replace function public.partner_pwa_accept_ride(p_booking_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_context jsonb;
  v_driver_id uuid;
  v_booking public.bookings%rowtype;
  v_result jsonb;
begin
  v_context := public.partner_pwa_context();
  v_driver_id := nullif(v_context #>> '{driver,id}', '')::uuid;
  if v_driver_id is null then
    raise exception 'Driver profile required';
  end if;

  select *
  into v_booking
  from public.bookings
  where id = p_booking_id
  for update;

  if not found then raise exception 'Ride not found'; end if;
  if v_booking.assigned_driver_id is distinct from v_driver_id then raise exception 'Ride is not assigned to this driver'; end if;
  if v_booking.assignment_token is null then raise exception 'Assignment token unavailable'; end if;

  v_result := public.driver_accept_assignment(v_booking.assignment_token);
  return v_result || jsonb_build_object('ride', (select to_jsonb(b) from public.bookings b where b.id = p_booking_id));
end;
$$;

create or replace function public.partner_pwa_decline_ride(p_booking_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_context jsonb;
  v_driver_id uuid;
  v_booking public.bookings%rowtype;
  v_result jsonb;
begin
  v_context := public.partner_pwa_context();
  v_driver_id := nullif(v_context #>> '{driver,id}', '')::uuid;
  if v_driver_id is null then
    raise exception 'Driver profile required';
  end if;

  select *
  into v_booking
  from public.bookings
  where id = p_booking_id
  for update;

  if not found then raise exception 'Ride not found'; end if;
  if v_booking.assigned_driver_id is distinct from v_driver_id then raise exception 'Ride is not assigned to this driver'; end if;
  if v_booking.assignment_token is null then raise exception 'Assignment token unavailable'; end if;

  v_result := public.driver_decline_assignment(v_booking.assignment_token);
  return v_result || jsonb_build_object('ride', (select to_jsonb(b) from public.bookings b where b.id = p_booking_id));
end;
$$;

create or replace function public.partner_pwa_update_ride_progress(p_booking_id text, p_action text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_context jsonb;
  v_driver_id uuid;
  v_booking public.bookings%rowtype;
  v_action text;
begin
  v_context := public.partner_pwa_context();
  v_driver_id := nullif(v_context #>> '{driver,id}', '')::uuid;
  v_action := lower(nullif(trim(p_action), ''));

  if v_driver_id is null then
    raise exception 'Driver profile required';
  end if;
  if v_action not in ('on_the_way','arrived','completed') then
    raise exception 'Invalid ride progress action';
  end if;

  select *
  into v_booking
  from public.bookings
  where id = p_booking_id
  for update;

  if not found then raise exception 'Ride not found'; end if;
  if v_booking.assigned_driver_id is distinct from v_driver_id then raise exception 'Ride is not assigned to this driver'; end if;
  if v_booking.status <> 'assigned' then raise exception 'Ride must be assigned before progress updates'; end if;

  if v_action = 'completed' then
    update public.bookings
    set status = 'completed',
        metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
          'driver_progress_state', 'completed',
          'completed_at', now(),
          'completed_by_driver', v_driver_id,
          'driver_completed_at', now(),
          'driver_progress_updated_by', auth.uid()
        )
    where id = p_booking_id
    returning * into v_booking;
  else
    update public.bookings
    set metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
          'driver_progress_state', v_action,
          'driver_progress_updated_at', now(),
          'driver_progress_updated_by', auth.uid()
        )
    where id = p_booking_id
    returning * into v_booking;
  end if;

  return jsonb_build_object(
    'id', v_booking.id,
    'status', v_booking.status,
    'driver_progress_state', v_booking.metadata->>'driver_progress_state',
    'ride', to_jsonb(v_booking)
  );
end;
$$;

revoke all on function public.partner_pwa_context() from public;
revoke all on function public.partner_pwa_context() from anon;
grant execute on function public.partner_pwa_context() to authenticated;

revoke all on function public.partner_pwa_rides() from public;
revoke all on function public.partner_pwa_rides() from anon;
grant execute on function public.partner_pwa_rides() to authenticated;

revoke all on function public.partner_pwa_accept_ride(text) from public;
revoke all on function public.partner_pwa_accept_ride(text) from anon;
grant execute on function public.partner_pwa_accept_ride(text) to authenticated;

revoke all on function public.partner_pwa_decline_ride(text) from public;
revoke all on function public.partner_pwa_decline_ride(text) from anon;
grant execute on function public.partner_pwa_decline_ride(text) to authenticated;

revoke all on function public.partner_pwa_update_ride_progress(text, text) from public;
revoke all on function public.partner_pwa_update_ride_progress(text, text) from anon;
grant execute on function public.partner_pwa_update_ride_progress(text, text) to authenticated;

select pg_notify('pgrst', 'reload schema');

commit;
