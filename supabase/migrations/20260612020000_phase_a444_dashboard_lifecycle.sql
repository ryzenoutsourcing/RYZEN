begin;

create or replace function public.operator_cancel_booking(p_booking_id text, p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  if not public.is_operator() then
    raise exception 'Operator access required';
  end if;

  update public.bookings
  set status = 'cancelled',
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'operator_cancelled_at', now(),
        'operator_cancelled_by', auth.uid(),
        'cancellation_reason', nullif(trim(p_reason), '')
      )
  where id = trim(p_booking_id)
    and status in ('accepted', 'assignment_sent', 'assigned', 'reassignment_needed')
  returning jsonb_build_object('id', id, 'status', status, 'reason', nullif(trim(p_reason), '')) into v_result;

  if v_result is null then
    raise exception 'Active booking not found';
  end if;

  return v_result;
end;
$$;

revoke all on function public.operator_cancel_booking(text, text) from public;
revoke all on function public.operator_cancel_booking(text, text) from anon;
grant execute on function public.operator_cancel_booking(text, text) to authenticated;

create or replace function public.create_operator_booking(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking_id text;
  v_partner_id bigint;
  v_amount numeric;
  v_booking public.bookings%rowtype;
begin
  if not public.is_operator() then
    raise exception 'Operator access required';
  end if;

  v_amount := coalesce(nullif(payload->>'amount', '')::numeric, 0);
  if v_amount < 15 then
    raise exception 'Minimum amount is EUR 15';
  end if;

  if coalesce(payload->>'name','') = ''
    or coalesce(payload->>'email','') = ''
    or coalesce(payload->>'pickup','') = ''
    or coalesce(payload->>'destination','') = ''
    or coalesce(payload->>'datetime','') = ''
    or coalesce(payload->>'time','') = '' then
    raise exception 'Missing required booking fields';
  end if;

  select p.id
  into v_partner_id
  from public.partners p
  where p.is_hoofd is true
    and p.user_id = auth.uid()
  order by p.id
  limit 1;

  if v_partner_id is null then
    select p.id
    into v_partner_id
    from public.partners p
    where p.is_hoofd is true
    order by p.id
    limit 1;
  end if;

  v_booking_id := 'FC-' || to_char(now(), 'YYYYMMDD') || '-' || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));

  insert into public.bookings (
    id,
    name,
    email,
    phone,
    pickup,
    destination,
    datetime,
    time,
    vehicle,
    amount,
    payment,
    status,
    partner_id,
    form_data,
    metadata
  )
  values (
    v_booking_id,
    payload->>'name',
    lower(payload->>'email'),
    payload->>'phone',
    payload->>'pickup',
    payload->>'destination',
    payload->>'datetime',
    payload->>'time',
    coalesce(payload->>'vehicle', 'Premium Sedan'),
    v_amount,
    coalesce(payload->>'payment', 'operator'),
    'pending',
    v_partner_id,
    payload,
    jsonb_build_object('source', coalesce(payload->>'source', 'operator-dashboard'), 'created_by_operator', auth.uid())
  )
  returning * into v_booking;

  return to_jsonb(v_booking);
end;
$$;

create or replace function public.operator_complete_booking(p_booking_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.bookings%rowtype;
begin
  if not public.is_operator() then
    raise exception 'Operator access required';
  end if;

  select *
  into v_booking
  from public.bookings
  where id = p_booking_id
  for update;

  if not found then
    raise exception 'Booking not found';
  end if;

  if v_booking.status <> 'assigned' then
    raise exception 'Only assigned rides can be completed';
  end if;

  update public.bookings
  set status = 'completed',
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'completed_at', now(),
        'completed_by_operator', auth.uid()
      )
  where id = p_booking_id
  returning * into v_booking;

  return to_jsonb(v_booking);
end;
$$;

revoke all on function public.create_operator_booking(jsonb) from public;
revoke all on function public.create_operator_booking(jsonb) from anon;
grant execute on function public.create_operator_booking(jsonb) to authenticated;

revoke all on function public.operator_complete_booking(text) from public;
revoke all on function public.operator_complete_booking(text) from anon;
grant execute on function public.operator_complete_booking(text) to authenticated;

select pg_notify('pgrst', 'reload schema');

commit;
