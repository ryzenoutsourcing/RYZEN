begin;

create or replace function public.create_operator_partner(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
  v_prefix text;
  v_result jsonb;
begin
  if auth.uid() is null or not public.is_operator() then
    raise exception 'Operator access required' using errcode = '42501';
  end if;

  if payload is null then
    raise exception 'Missing partner payload';
  end if;

  v_name := nullif(trim(payload->>'name'), '');
  if v_name is null then
    raise exception 'Partner name is required';
  end if;

  v_prefix := upper(nullif(regexp_replace(coalesce(payload->>'prefix', ''), '[^a-zA-Z0-9]', '', 'g'), ''));
  if v_prefix is null then
    v_prefix := upper(substr(regexp_replace(v_name, '[^a-zA-Z0-9]', '', 'g'), 1, 3));
  end if;
  if v_prefix is null or length(v_prefix) = 0 then
    v_prefix := 'PRT';
  end if;

  insert into public.partners (name, is_hoofd, prefix, contact, email, phone)
  values (
    v_name,
    coalesce((payload->>'is_hoofd')::boolean, false),
    v_prefix,
    nullif(trim(payload->>'contact'), ''),
    nullif(trim(payload->>'email'), ''),
    nullif(trim(payload->>'phone'), '')
  )
  returning jsonb_build_object(
    'id', id,
    'name', name,
    'is_hoofd', is_hoofd,
    'prefix', prefix,
    'contact', contact,
    'email', email,
    'phone', phone
  ) into v_result;

  return v_result;
end;
$$;

create or replace function public.create_operator_driver(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_partner_id integer;
  v_name text;
  v_driver_code text;
  v_result jsonb;
begin
  if auth.uid() is null or not public.is_operator() then
    raise exception 'Operator access required' using errcode = '42501';
  end if;

  if payload is null then
    raise exception 'Missing driver payload';
  end if;

  v_partner_id := nullif(payload->>'partner_id', '')::integer;
  if v_partner_id is null or not exists (select 1 from public.partners where id = v_partner_id) then
    raise exception 'Valid partner_id is required';
  end if;

  v_name := nullif(trim(payload->>'name'), '');
  if v_name is null then
    raise exception 'Driver name is required';
  end if;

  v_driver_code := nullif(trim(payload->>'driver_code'), '');
  if v_driver_code is null then
    select coalesce((select prefix from public.partners where id = v_partner_id), 'DRV') || '-' ||
           lpad(((select count(*) from public.drivers where partner_id = v_partner_id) + 1)::text, 2, '0')
    into v_driver_code;
  end if;

  insert into public.drivers (
    partner_id, driver_code, name, email, phone, vehicle, color, license_plate
  )
  values (
    v_partner_id,
    v_driver_code,
    v_name,
    nullif(trim(payload->>'email'), ''),
    nullif(trim(payload->>'phone'), ''),
    coalesce(nullif(trim(payload->>'vehicle'), ''), 'Standaard'),
    coalesce(nullif(trim(payload->>'color'), ''), 'Zwart'),
    coalesce(nullif(trim(payload->>'license_plate'), ''), 'Onbekend')
  )
  returning jsonb_build_object(
    'id', id,
    'partner_id', partner_id,
    'driver_code', driver_code,
    'name', name,
    'email', email,
    'phone', phone,
    'vehicle', vehicle,
    'color', color,
    'license_plate', license_plate
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.create_operator_partner(jsonb) from public;
revoke all on function public.create_operator_driver(jsonb) from public;
revoke all on function public.create_operator_partner(jsonb) from anon;
revoke all on function public.create_operator_driver(jsonb) from anon;
grant execute on function public.create_operator_partner(jsonb) to authenticated;
grant execute on function public.create_operator_driver(jsonb) to authenticated;

commit;
