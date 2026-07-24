begin;

alter table public.account_requests add column if not exists request_scope text not null default 'operator';
create index if not exists idx_account_requests_scope_status on public.account_requests(request_scope, status);

update public.account_requests
set request_scope = 'customer'
where request_scope <> 'customer'
  and (
    lower(coalesce(account_type, '')) in ('client', 'customer')
    or lower(coalesce(metadata->>'source', '')) in ('customer-registration', 'customer-portal')
  );

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

create or replace function public.create_customer_registration_profile(payload jsonb)
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
  v_email := lower(nullif(btrim(payload->>'email'), ''));
  if v_email is null then
    raise exception 'Email required';
  end if;

  v_customer_id := coalesce(
    nullif(payload->>'id', ''),
    'CUST-' || substring(regexp_replace(v_email, '[^a-z0-9]', '', 'gi') from 1 for 30)
  );

  insert into public.customers (id, user_id, name, email, phone, default_pickup_address, created_at)
  values (
    v_customer_id,
    auth.uid(),
    nullif(payload->>'name', ''),
    v_email,
    nullif(payload->>'phone', ''),
    nullif(payload->>'default_pickup_address', ''),
    now()
  )
  on conflict (id) do update
    set user_id = coalesce(public.customers.user_id, auth.uid()),
        name = coalesce(nullif(excluded.name, ''), public.customers.name),
        phone = coalesce(nullif(excluded.phone, ''), public.customers.phone),
        default_pickup_address = coalesce(nullif(excluded.default_pickup_address, ''), public.customers.default_pickup_address)
  returning jsonb_build_object('id', id, 'email', email, 'user_id', user_id) into v_result;

  perform public.submit_account_request(jsonb_build_object(
    'name', coalesce(nullif(payload->>'name', ''), v_email),
    'email', v_email,
    'phone', coalesce(payload->>'phone', ''),
    'company', 'FleetConnect customer',
    'account_type', 'Client',
    'request_scope', 'customer',
    'notes', coalesce(payload->>'notes', 'Customer portal registration'),
    'source', 'customer-registration',
    'default_pickup_address', coalesce(payload->>'default_pickup_address', ''),
    'google_places_available', coalesce(payload->>'google_places_available', '')
  ));

  update public.account_requests
  set customer_id = coalesce(customer_id, v_customer_id),
      user_id = coalesce(user_id, auth.uid()),
      updated_at = now()
  where lower(email) = v_email
    and request_scope = 'customer'
    and status in ('pending', 'approved');

  return v_result;
end;
$$;

create or replace function public.link_customer_after_registration()
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

  v_customer_id := 'CUST-' || substring(regexp_replace(v_email, '[^a-z0-9]', '', 'gi') from 1 for 30);

  update public.customers
  set user_id = auth.uid()
  where id = v_customer_id
    and lower(email) = v_email
    and (user_id is null or user_id = auth.uid());

  update public.account_requests
  set customer_id = coalesce(customer_id, v_customer_id),
      user_id = auth.uid(),
      updated_at = now(),
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'auth_user_linked', true,
        'auth_user_linked_at', now()
      )
  where lower(email) = v_email
    and request_scope = 'customer'
    and status in ('pending', 'approved')
    and (user_id is null or user_id = auth.uid())
  returning jsonb_build_object(
    'request_id', id,
    'status', status,
    'customer_id', customer_id,
    'user_id', user_id
  ) into v_result;

  return coalesce(v_result, jsonb_build_object('linked', false, 'customer_id', v_customer_id));
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
  v_auth_user_id uuid;
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

  v_customer_id := coalesce(
    v_request.customer_id,
    'CUST-' || substring(regexp_replace(lower(v_request.email), '[^a-z0-9]', '', 'gi') from 1 for 30)
  );

  select id into v_auth_user_id
  from auth.users
  where lower(email) = lower(v_request.email)
  order by created_at desc
  limit 1;

  if v_request.request_scope = 'customer' or lower(v_request.account_type) in ('client', 'customer') then
    insert into public.customers (id, user_id, name, email, phone, default_pickup_address, created_at)
    values (
      v_customer_id,
      v_auth_user_id,
      v_request.name,
      lower(v_request.email),
      v_request.phone,
      nullif(v_request.metadata->>'default_pickup_address', ''),
      now()
    )
    on conflict (id) do update
      set user_id = coalesce(public.customers.user_id, excluded.user_id),
          name = excluded.name,
          email = excluded.email,
          phone = excluded.phone,
          default_pickup_address = coalesce(excluded.default_pickup_address, public.customers.default_pickup_address);
  end if;

  update public.account_requests
  set status = 'approved',
      customer_id = case when v_request.request_scope = 'customer' or lower(v_request.account_type) in ('client', 'customer') then v_customer_id else customer_id end,
      user_id = coalesce(v_auth_user_id, user_id),
      approved_by = auth.uid(),
      approved_at = now(),
      updated_at = now(),
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'approval_note', case
          when v_auth_user_id is null then 'Approved. Supabase Auth verification is still required before login.'
          else 'Approved and existing Supabase Auth user linked.'
        end,
        'approved_at', now(),
        'auth_user_linked', v_auth_user_id is not null
      )
  where id = p_request_id;

  return jsonb_build_object(
    'id', p_request_id,
    'status', 'approved',
    'email', lower(v_request.email),
    'account_type', v_request.account_type,
    'request_scope', v_request.request_scope,
    'customer_id', case when v_request.request_scope = 'customer' or lower(v_request.account_type) in ('client', 'customer') then v_customer_id else null end,
    'user_id', v_auth_user_id,
    'auth_user_linked', v_auth_user_id is not null
  );
end;
$$;

create or replace function public.get_account_request_status(p_email text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.account_requests%rowtype;
begin
  if p_email is null or position('@' in p_email) = 0 then
    return jsonb_build_object('found', false);
  end if;

  select * into v_request
  from public.account_requests
  where lower(email) = lower(trim(p_email))
  order by case when request_scope = 'customer' then 0 else 1 end, created_at desc
  limit 1;

  if not found then
    return jsonb_build_object('found', false);
  end if;

  return jsonb_build_object(
    'found', true,
    'status', v_request.status,
    'request_scope', v_request.request_scope,
    'customer_id', v_request.customer_id,
    'user_linked', v_request.user_id is not null
  );
end;
$$;

create or replace function public.get_customer_portal_access()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
  v_customer public.customers%rowtype;
  v_request public.account_requests%rowtype;
  v_customer_id text;
begin
  if auth.uid() is null then
    return jsonb_build_object('allowed', false, 'state', 'no_session', 'message', 'Login required');
  end if;

  v_email := lower(nullif(auth.jwt()->>'email', ''));
  if v_email is null then
    return jsonb_build_object('allowed', false, 'state', 'no_email', 'message', 'Email unavailable');
  end if;

  v_customer_id := 'CUST-' || substring(regexp_replace(v_email, '[^a-z0-9]', '', 'gi') from 1 for 30);

  perform public.link_customer_after_registration();

  select *
  into v_request
  from public.account_requests
  where lower(email) = v_email
    and (request_scope = 'customer' or lower(account_type) in ('client', 'customer'))
  order by created_at desc
  limit 1;

  if found and v_request.status = 'pending' then
    return jsonb_build_object('allowed', false, 'state', 'pending', 'message', 'Your account is awaiting approval.');
  end if;

  if found and v_request.status = 'rejected' then
    return jsonb_build_object('allowed', false, 'state', 'rejected', 'message', coalesce(v_request.rejection_reason, 'Account request rejected.'));
  end if;

  select *
  into v_customer
  from public.customers
  where user_id = auth.uid()
     or lower(email) = v_email
  order by case when user_id = auth.uid() then 0 else 1 end
  limit 1;

  if not found and v_request.status = 'approved' then
    insert into public.customers (id, user_id, name, email, phone, default_pickup_address, created_at)
    values (
      coalesce(v_request.customer_id, v_customer_id),
      auth.uid(),
      v_request.name,
      v_email,
      v_request.phone,
      nullif(v_request.metadata->>'default_pickup_address', ''),
      now()
    )
    on conflict (id) do update
      set user_id = coalesce(public.customers.user_id, excluded.user_id),
          name = coalesce(excluded.name, public.customers.name),
          phone = coalesce(excluded.phone, public.customers.phone),
          default_pickup_address = coalesce(excluded.default_pickup_address, public.customers.default_pickup_address)
    returning * into v_customer;
  end if;

  if not found then
    return jsonb_build_object('allowed', false, 'state', 'profile_missing', 'message', 'No linked customer profile found. Please register or wait for approval.');
  end if;

  if v_customer.user_id is null then
    update public.customers
    set user_id = auth.uid()
    where id = v_customer.id
      and lower(email) = v_email
      and user_id is null
    returning * into v_customer;
  end if;

  update public.account_requests
  set customer_id = coalesce(customer_id, v_customer.id),
      user_id = coalesce(user_id, auth.uid()),
      updated_at = now()
  where lower(email) = v_email
    and request_scope = 'customer'
    and status = 'approved';

  return jsonb_build_object(
    'allowed', true,
    'state', 'approved',
    'customer_id', v_customer.id,
    'email', v_email
  );
end;
$$;

revoke all on function public.submit_account_request(jsonb) from public;
grant execute on function public.submit_account_request(jsonb) to anon, authenticated;

revoke all on function public.create_customer_registration_profile(jsonb) from public;
grant execute on function public.create_customer_registration_profile(jsonb) to anon, authenticated;

revoke all on function public.link_customer_after_registration() from public;
revoke all on function public.link_customer_after_registration() from anon;
grant execute on function public.link_customer_after_registration() to authenticated;

revoke all on function public.approve_account_request(uuid) from public;
revoke all on function public.approve_account_request(uuid) from anon;
grant execute on function public.approve_account_request(uuid) to authenticated;

revoke all on function public.get_account_request_status(text) from public;
grant execute on function public.get_account_request_status(text) to anon, authenticated;

revoke all on function public.get_customer_portal_access() from public;
revoke all on function public.get_customer_portal_access() from anon;
grant execute on function public.get_customer_portal_access() to authenticated;

notify pgrst, 'reload schema';

commit;
