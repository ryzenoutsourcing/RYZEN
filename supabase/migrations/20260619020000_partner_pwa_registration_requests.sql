begin;

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
  v_scope text;
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
  v_scope := lower(coalesce(nullif(trim(payload->>'request_scope'), ''), case when v_account_type in ('Client') then 'customer' else 'operator' end));

  if v_name is null then
    raise exception 'Name is required';
  end if;

  if v_email is null or position('@' in v_email) = 0 then
    raise exception 'Valid email is required';
  end if;

  if v_account_type not in ('Operations', 'Partner', 'Driver', 'Client', 'Other') then
    raise exception 'Invalid account type';
  end if;

  if v_scope not in ('customer', 'operator') then
    v_scope := 'operator';
  end if;

  if v_account_type = 'Partner' and v_company is null then
    raise exception 'Company is required for partner account requests';
  end if;

  update public.account_requests
  set name = v_name,
      phone = coalesce(v_phone, phone),
      company = coalesce(v_company, company),
      account_type = v_account_type,
      notes = coalesce(v_notes, notes),
      request_scope = v_scope,
      updated_at = now(),
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'source', coalesce(payload->>'source', metadata->>'source', 'operator-login'),
        'user_agent', coalesce(payload->>'user_agent', metadata->>'user_agent', ''),
        'default_pickup_address', coalesce(payload->>'default_pickup_address', metadata->>'default_pickup_address', ''),
        'google_places_available', coalesce(payload->>'google_places_available', metadata->>'google_places_available', ''),
        'vehicle_type', coalesce(payload->>'vehicle_type', metadata->>'vehicle_type', ''),
        'operating_area', coalesce(payload->>'operating_area', metadata->>'operating_area', ''),
        'preferred_language', coalesce(payload->>'preferred_language', metadata->>'preferred_language', ''),
        'requested_portal', coalesce(payload->>'requested_portal', metadata->>'requested_portal', ''),
        'resubmitted_at', now()
      )
  where lower(email) = v_email
    and request_scope = v_scope
    and status in ('pending', 'approved')
  returning jsonb_build_object('id', id, 'status', status, 'created_at', created_at, 'request_scope', request_scope) into v_result;

  if v_result is not null then
    return v_result;
  end if;

  insert into public.account_requests (
    name, email, phone, company, account_type, notes, request_scope, metadata
  )
  values (
    v_name,
    v_email,
    v_phone,
    v_company,
    v_account_type,
    v_notes,
    v_scope,
    jsonb_build_object(
      'source', coalesce(payload->>'source', 'operator-login'),
      'user_agent', coalesce(payload->>'user_agent', ''),
      'default_pickup_address', coalesce(payload->>'default_pickup_address', ''),
      'google_places_available', coalesce(payload->>'google_places_available', ''),
      'vehicle_type', coalesce(payload->>'vehicle_type', ''),
      'operating_area', coalesce(payload->>'operating_area', ''),
      'preferred_language', coalesce(payload->>'preferred_language', ''),
      'requested_portal', coalesce(payload->>'requested_portal', ''),
      'submitted_at', now()
    )
  )
  returning jsonb_build_object(
    'id', id,
    'status', status,
    'created_at', created_at,
    'request_scope', request_scope
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.submit_account_request(jsonb) from public;
grant execute on function public.submit_account_request(jsonb) to anon, authenticated;

notify pgrst, 'reload schema';

commit;
