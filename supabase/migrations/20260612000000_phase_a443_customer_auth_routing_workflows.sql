begin;

alter table public.account_requests add column if not exists approved_by uuid;
alter table public.account_requests add column if not exists approved_at timestamptz;
alter table public.account_requests add column if not exists rejected_by uuid;
alter table public.account_requests add column if not exists rejected_at timestamptz;
alter table public.account_requests add column if not exists rejection_reason text;

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
    and (user_id is null or user_id = auth.uid())
    and (customer_id is null or customer_id = v_customer_id)
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
    raise exception 'Booking not found for this customer email, or it is already linked to another account';
  end if;

  return v_result;
end;
$$;

create or replace function public.approve_account_request(p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.account_requests%rowtype;
  v_customer_id text;
begin
  if not public.is_operator() then
    raise exception 'Operator access required';
  end if;

  select * into v_request
  from public.account_requests
  where id = p_request_id
  for update;

  if not found then
    raise exception 'Account request not found';
  end if;

  if v_request.status <> 'pending' then
    raise exception 'Account request is not pending';
  end if;

  update public.account_requests
  set status = 'approved',
      approved_by = auth.uid(),
      approved_at = now(),
      updated_at = now(),
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'approval_note', 'Approved by FleetConnect operator. Supabase Auth invite must be issued by service-role/admin flow when required.',
        'approved_at', now()
      )
  where id = p_request_id;

  if v_request.account_type = 'Client' then
    v_customer_id := 'CUST-' || substring(regexp_replace(lower(v_request.email), '[^a-z0-9]', '', 'gi') from 1 for 30);
    insert into public.customers (id, name, email, phone, created_at)
    values (v_customer_id, v_request.name, lower(v_request.email), v_request.phone, now())
    on conflict (id) do update
      set name = excluded.name,
          email = excluded.email,
          phone = excluded.phone;
  end if;

  return jsonb_build_object('id', p_request_id, 'status', 'approved', 'email', lower(v_request.email), 'account_type', v_request.account_type);
end;
$$;

create or replace function public.reject_account_request(p_request_id uuid, p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.account_requests%rowtype;
begin
  if not public.is_operator() then
    raise exception 'Operator access required';
  end if;

  select * into v_request
  from public.account_requests
  where id = p_request_id
  for update;

  if not found then
    raise exception 'Account request not found';
  end if;

  if v_request.status <> 'pending' then
    raise exception 'Account request is not pending';
  end if;

  update public.account_requests
  set status = 'rejected',
      rejected_by = auth.uid(),
      rejected_at = now(),
      rejection_reason = nullif(trim(p_reason), ''),
      updated_at = now()
  where id = p_request_id;

  return jsonb_build_object('id', p_request_id, 'status', 'rejected', 'email', lower(v_request.email), 'reason', nullif(trim(p_reason), ''));
end;
$$;

create or replace function public.operator_reject_booking(p_booking_id text, p_reason text default null)
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
  set status = 'declined',
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'operator_rejected_at', now(),
        'operator_rejected_by', auth.uid(),
        'rejection_reason', nullif(trim(p_reason), '')
      )
  where id = trim(p_booking_id)
    and status = 'pending'
  returning jsonb_build_object('id', id, 'status', status, 'reason', nullif(trim(p_reason), '')) into v_result;

  if v_result is null then
    raise exception 'Pending booking not found';
  end if;

  return v_result;
end;
$$;

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
    and status in ('accepted', 'assigned', 'reassignment_needed')
  returning jsonb_build_object('id', id, 'status', status, 'reason', nullif(trim(p_reason), '')) into v_result;

  if v_result is null then
    raise exception 'Active booking not found';
  end if;

  return v_result;
end;
$$;

create or replace function public.reactivate_operator_driver(p_driver_id uuid)
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

  update public.drivers
  set is_active = true,
      archived_at = null,
      updated_at = now()
  where id = p_driver_id
  returning jsonb_build_object('id', id, 'is_active', is_active) into v_result;

  if v_result is null then
    raise exception 'Driver not found';
  end if;

  return v_result;
end;
$$;

revoke all on function public.attach_booking_to_customer(text) from public;
revoke all on function public.attach_booking_to_customer(text) from anon;
grant execute on function public.attach_booking_to_customer(text) to authenticated;

revoke all on function public.approve_account_request(uuid) from public;
revoke all on function public.reject_account_request(uuid, text) from public;
revoke all on function public.operator_reject_booking(text, text) from public;
revoke all on function public.operator_cancel_booking(text, text) from public;
revoke all on function public.reactivate_operator_driver(uuid) from public;
grant execute on function public.approve_account_request(uuid) to authenticated;
grant execute on function public.reject_account_request(uuid, text) to authenticated;
grant execute on function public.operator_reject_booking(text, text) to authenticated;
grant execute on function public.operator_cancel_booking(text, text) to authenticated;
grant execute on function public.reactivate_operator_driver(uuid) to authenticated;

select pg_notify('pgrst', 'reload schema');

commit;
