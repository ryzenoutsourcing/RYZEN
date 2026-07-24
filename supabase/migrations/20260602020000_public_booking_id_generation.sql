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

  -- Never trust public clients for the primary key. Browser-local counters can collide.
  v_id := 'FC-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS') || '-' ||
          substr(md5(random()::text || clock_timestamp()::text), 1, 8);

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

revoke all on function public.create_public_booking(jsonb) from public;
grant execute on function public.create_public_booking(jsonb) to anon, authenticated;
