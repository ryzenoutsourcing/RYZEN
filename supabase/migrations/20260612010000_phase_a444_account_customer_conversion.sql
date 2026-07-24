begin;

alter table public.account_requests add column if not exists customer_id text references public.customers(id);
alter table public.account_requests add column if not exists user_id uuid references auth.users(id);

create index if not exists idx_account_requests_customer_id on public.account_requests(customer_id);
create index if not exists idx_account_requests_user_id on public.account_requests(user_id);
create index if not exists idx_account_requests_email_lower on public.account_requests(lower(email));

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

  v_customer_id := 'CUST-' || substring(regexp_replace(lower(v_request.email), '[^a-z0-9]', '', 'gi') from 1 for 30);

  select id into v_auth_user_id
  from auth.users
  where lower(email) = lower(v_request.email)
  order by created_at desc
  limit 1;

  insert into public.customers (id, user_id, name, email, phone, created_at)
  values (v_customer_id, v_auth_user_id, v_request.name, lower(v_request.email), v_request.phone, now())
  on conflict (id) do update
    set user_id = coalesce(public.customers.user_id, excluded.user_id),
        name = excluded.name,
        email = excluded.email,
        phone = excluded.phone;

  update public.account_requests
  set status = 'approved',
      customer_id = v_customer_id,
      user_id = v_auth_user_id,
      approved_by = auth.uid(),
      approved_at = now(),
      updated_at = now(),
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'approval_note', case
          when v_auth_user_id is null then 'Approved and customer profile created. User must complete Supabase Auth registration/verification before login.'
          else 'Approved, customer profile created, and existing Supabase Auth user linked.'
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
    'customer_id', v_customer_id,
    'user_id', v_auth_user_id,
    'auth_user_linked', v_auth_user_id is not null
  );
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
    and status = 'approved'
    and (user_id is null or user_id = auth.uid())
  returning jsonb_build_object(
    'request_id', id,
    'status', status,
    'customer_id', customer_id,
    'user_id', user_id
  ) into v_result;

  if v_result is null then
    return jsonb_build_object('linked', false, 'customer_id', v_customer_id);
  end if;

  return v_result || jsonb_build_object('linked', true);
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
  order by created_at desc
  limit 1;

  if not found then
    return jsonb_build_object('found', false);
  end if;

  return jsonb_build_object(
    'found', true,
    'status', v_request.status,
    'customer_id', v_request.customer_id,
    'user_linked', v_request.user_id is not null
  );
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

  return v_result;
end;
$$;

revoke all on function public.approve_account_request(uuid) from public;
revoke all on function public.approve_account_request(uuid) from anon;
grant execute on function public.approve_account_request(uuid) to authenticated;

revoke all on function public.link_customer_after_registration() from public;
revoke all on function public.link_customer_after_registration() from anon;
grant execute on function public.link_customer_after_registration() to authenticated;

revoke all on function public.get_account_request_status(text) from public;
grant execute on function public.get_account_request_status(text) to anon, authenticated;

revoke all on function public.create_customer_registration_profile(jsonb) from public;
grant execute on function public.create_customer_registration_profile(jsonb) to anon, authenticated;

select pg_notify('pgrst', 'reload schema');

commit;
