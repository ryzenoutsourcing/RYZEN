begin;

create or replace function public.partner_pwa_public_partner_options()
returns jsonb
language sql
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', p.id,
      'name', p.name,
      'is_hoofd', coalesce(p.is_hoofd, false)
    )
    order by coalesce(p.is_hoofd, false) desc, p.name
  ), '[]'::jsonb)
  from public.partners p
  where p.archived_at is null;
$$;

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
  v_preferred_language text;
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
    and archived_at is null
  order by updated_at desc nulls last
  limit 1;

  if found and v_driver.partner_id is not null then
    select *
    into v_partner
    from public.partners
    where id = v_driver.partner_id
      and archived_at is null
    limit 1;
  end if;

  if v_partner.id is null then
    select *
    into v_partner
    from public.partners
    where archived_at is null
      and (user_id = auth.uid() or lower(coalesce(email, '')) = v_email)
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

  select nullif(metadata->>'preferred_language', '')
  into v_preferred_language
  from public.account_requests
  where lower(email) = v_email
  order by updated_at desc nulls last, created_at desc nulls last
  limit 1;

  return jsonb_build_object(
    'role', v_role,
    'email', v_email,
    'preferred_language', v_preferred_language,
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

create or replace function public.partner_pwa_partner_drivers()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_context jsonb;
  v_partner_id integer;
begin
  v_context := public.partner_pwa_context();
  v_partner_id := nullif(v_context #>> '{partner,id}', '')::integer;

  if v_partner_id is null then
    raise exception 'Partner profile required';
  end if;

  return jsonb_build_object(
    'context', v_context,
    'drivers', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', d.id,
        'driver_code', d.driver_code,
        'name', d.name,
        'email', d.email,
        'phone', d.phone,
        'vehicle', d.vehicle,
        'license_plate', d.license_plate,
        'is_active', coalesce(d.is_active, true),
        'archived_at', d.archived_at,
        'updated_at', d.updated_at
      ) order by coalesce(d.is_active, true) desc, d.name), '[]'::jsonb)
      from public.drivers d
      where d.partner_id = v_partner_id
    )
  );
end;
$$;

create or replace function public.partner_pwa_request_driver(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_context jsonb;
  v_partner_id integer;
  v_partner_name text;
  v_payload jsonb;
  v_result jsonb;
  v_request_id uuid;
begin
  v_context := public.partner_pwa_context();
  v_partner_id := nullif(v_context #>> '{partner,id}', '')::integer;
  v_partner_name := nullif(v_context #>> '{partner,name}', '');

  if v_partner_id is null then
    raise exception 'Partner profile required';
  end if;

  v_payload := coalesce(payload, '{}'::jsonb)
  || jsonb_build_object(
    'account_type', 'Driver',
    'request_scope', 'operator',
    'company', coalesce(nullif(payload->>'partner_company_name', ''), v_partner_name, ''),
    'source', 'partner-pwa-driver-request',
    'requested_portal', 'partner-app',
    'linked_partner_id', v_partner_id::text
  );

  v_result := public.submit_account_request(v_payload);
  v_request_id := nullif(v_result->>'id', '')::uuid;

  if v_request_id is not null then
    update public.account_requests
       set metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
         'license_plate', coalesce(v_payload->>'license_plate', metadata->>'license_plate', ''),
         'vehicle_type', coalesce(v_payload->>'vehicle_type', metadata->>'vehicle_type', ''),
         'linked_partner_id', v_partner_id::text,
         'preferred_language', coalesce(v_payload->>'preferred_language', metadata->>'preferred_language', ''),
         'requested_portal', 'partner-app'
       ),
           updated_at = now()
     where id = v_request_id;
  end if;

  return v_result;
end;
$$;

create or replace function public.partner_pwa_submit_account_request(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
  v_request_id uuid;
begin
  v_result := public.submit_account_request(payload);
  v_request_id := nullif(v_result->>'id', '')::uuid;

  if v_request_id is not null then
    update public.account_requests
       set metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
         'license_plate', coalesce(payload->>'license_plate', metadata->>'license_plate', ''),
         'partner_id', coalesce(payload->>'partner_id', metadata->>'partner_id', ''),
         'partner_company_name', coalesce(payload->>'partner_company_name', metadata->>'partner_company_name', ''),
         'linked_partner_id', coalesce(payload->>'linked_partner_id', metadata->>'linked_partner_id', ''),
         'preferred_language', coalesce(payload->>'preferred_language', metadata->>'preferred_language', ''),
         'requested_portal', coalesce(payload->>'requested_portal', metadata->>'requested_portal', 'partner-app')
       ),
           updated_at = now()
     where id = v_request_id;
  end if;

  return v_result;
end;
$$;

create or replace function public.partner_pwa_update_driver(p_driver_id uuid, payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_context jsonb;
  v_partner_id integer;
  v_result jsonb;
begin
  v_context := public.partner_pwa_context();
  v_partner_id := nullif(v_context #>> '{partner,id}', '')::integer;

  if v_partner_id is null then
    raise exception 'Partner profile required';
  end if;

  update public.drivers
     set name = coalesce(nullif(trim(payload->>'name'), ''), name),
         phone = coalesce(nullif(trim(payload->>'phone'), ''), phone),
         vehicle = coalesce(nullif(trim(payload->>'vehicle'), ''), vehicle),
         license_plate = coalesce(nullif(trim(payload->>'license_plate'), ''), license_plate),
         updated_at = now()
   where id = p_driver_id
     and partner_id = v_partner_id
   returning jsonb_build_object(
     'id', id,
     'driver_code', driver_code,
     'name', name,
     'email', email,
     'phone', phone,
     'vehicle', vehicle,
     'license_plate', license_plate,
     'is_active', coalesce(is_active, true),
     'archived_at', archived_at
   ) into v_result;

  if v_result is null then
    raise exception 'Driver not found for this partner';
  end if;

  return v_result;
end;
$$;

create or replace function public.partner_pwa_archive_driver(p_driver_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_context jsonb;
  v_partner_id integer;
  v_result jsonb;
begin
  v_context := public.partner_pwa_context();
  v_partner_id := nullif(v_context #>> '{partner,id}', '')::integer;

  if v_partner_id is null then
    raise exception 'Partner profile required';
  end if;

  if exists (
    select 1
    from public.bookings b
    where b.assigned_driver_id = p_driver_id
      and b.status in ('assignment_sent','assigned','accepted')
  ) then
    raise exception 'Driver has active assigned rides and cannot be archived';
  end if;

  update public.drivers
     set is_active = false,
         archived_at = coalesce(archived_at, now()),
         updated_at = now()
   where id = p_driver_id
     and partner_id = v_partner_id
   returning jsonb_build_object(
     'id', id,
     'name', name,
     'email', email,
     'is_active', coalesce(is_active, true),
     'archived_at', archived_at
   ) into v_result;

  if v_result is null then
    raise exception 'Driver not found for this partner';
  end if;

  return v_result;
end;
$$;

revoke all on function public.partner_pwa_public_partner_options() from public;
grant execute on function public.partner_pwa_public_partner_options() to anon, authenticated;

revoke all on function public.partner_pwa_partner_drivers() from public;
revoke all on function public.partner_pwa_partner_drivers() from anon;
grant execute on function public.partner_pwa_partner_drivers() to authenticated;

revoke all on function public.partner_pwa_request_driver(jsonb) from public;
revoke all on function public.partner_pwa_request_driver(jsonb) from anon;
grant execute on function public.partner_pwa_request_driver(jsonb) to authenticated;

revoke all on function public.partner_pwa_submit_account_request(jsonb) from public;
grant execute on function public.partner_pwa_submit_account_request(jsonb) to anon, authenticated;

revoke all on function public.partner_pwa_update_driver(uuid, jsonb) from public;
revoke all on function public.partner_pwa_update_driver(uuid, jsonb) from anon;
grant execute on function public.partner_pwa_update_driver(uuid, jsonb) to authenticated;

revoke all on function public.partner_pwa_archive_driver(uuid) from public;
revoke all on function public.partner_pwa_archive_driver(uuid) from anon;
grant execute on function public.partner_pwa_archive_driver(uuid) to authenticated;

select pg_notify('pgrst', 'reload schema');

commit;
