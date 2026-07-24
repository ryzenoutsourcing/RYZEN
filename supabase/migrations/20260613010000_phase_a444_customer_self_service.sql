begin;

alter table public.customers add column if not exists default_pickup_address text;
alter table public.customers add column if not exists is_active boolean not null default true;
alter table public.customers add column if not exists archived_at timestamptz;
alter table public.customers add column if not exists updated_at timestamptz;

create index if not exists idx_customers_email_lower on public.customers(lower(email));
create index if not exists idx_customers_is_active on public.customers(is_active);

insert into public.customers (id, user_id, name, email, phone, default_pickup_address, is_active, created_at, updated_at)
select
  coalesce(ar.customer_id, 'CUST-' || substring(regexp_replace(lower(ar.email), '[^a-z0-9]', '', 'gi') from 1 for 30)),
  ar.user_id,
  coalesce(nullif(ar.name, ''), lower(ar.email)),
  lower(ar.email),
  coalesce(ar.phone, ''),
  nullif(ar.metadata->>'default_pickup_address', ''),
  true,
  coalesce(ar.created_at, now()),
  now()
from public.account_requests ar
where ar.request_scope = 'customer'
on conflict (id) do update
  set user_id = coalesce(public.customers.user_id, excluded.user_id),
      name = coalesce(nullif(public.customers.name, ''), excluded.name),
      phone = coalesce(nullif(public.customers.phone, ''), excluded.phone),
      default_pickup_address = coalesce(public.customers.default_pickup_address, excluded.default_pickup_address),
      is_active = true,
      archived_at = null,
      updated_at = now();

update public.account_requests
set status = 'approved',
    customer_id = coalesce(customer_id, 'CUST-' || substring(regexp_replace(lower(email), '[^a-z0-9]', '', 'gi') from 1 for 30)),
    updated_at = now(),
    metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
      'auto_customer_registration', true,
      'approval_not_required', true,
      'auto_approved_at', now()
    )
where request_scope = 'customer'
  and status = 'pending';

create or replace function public.create_customer_registration_profile(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
  v_name text;
  v_phone text;
  v_pickup text;
  v_customer_id text;
  v_auth_user_id uuid;
  v_result jsonb;
begin
  v_email := lower(nullif(btrim(payload->>'email'), ''));
  if v_email is null then
    raise exception 'Email required';
  end if;

  v_name := coalesce(nullif(btrim(payload->>'name'), ''), v_email);
  v_phone := coalesce(nullif(btrim(payload->>'phone'), ''), '');
  v_pickup := coalesce(
    nullif(btrim(payload->>'default_pickup_address'), ''),
    nullif(btrim(payload->>'defaultPickupAddress'), ''),
    nullif(btrim(payload->>'defaultPickupAdress'), '')
  );
  v_auth_user_id := auth.uid();
  v_customer_id := coalesce(
    nullif(payload->>'id', ''),
    'CUST-' || substring(regexp_replace(v_email, '[^a-z0-9]', '', 'gi') from 1 for 30)
  );

  insert into public.customers (id, user_id, name, email, phone, default_pickup_address, is_active, created_at, updated_at)
  values (v_customer_id, v_auth_user_id, v_name, v_email, v_phone, v_pickup, true, now(), now())
  on conflict (id) do update
    set user_id = coalesce(public.customers.user_id, excluded.user_id),
        name = coalesce(nullif(excluded.name, ''), public.customers.name),
        email = excluded.email,
        phone = coalesce(nullif(excluded.phone, ''), public.customers.phone),
        default_pickup_address = coalesce(nullif(excluded.default_pickup_address, ''), public.customers.default_pickup_address),
        is_active = true,
        archived_at = null,
        updated_at = now()
  returning jsonb_build_object('id', id, 'email', email, 'user_id', user_id, 'is_active', is_active) into v_result;

  update public.account_requests
  set status = case when request_scope = 'customer' then 'approved' else status end,
      customer_id = coalesce(customer_id, v_customer_id),
      user_id = coalesce(user_id, v_auth_user_id),
      updated_at = now(),
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'auto_customer_registration', request_scope = 'customer',
        'approval_not_required', request_scope = 'customer',
        'default_pickup_address', coalesce(v_pickup, metadata->>'default_pickup_address', ''),
        'customer_profile_upserted_at', now()
      )
  where lower(email) = v_email
    and request_scope = 'customer';

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

  insert into public.customers (id, user_id, name, email, phone, is_active, created_at, updated_at)
  values (v_customer_id, auth.uid(), v_email, v_email, '', true, now(), now())
  on conflict (id) do update
    set user_id = coalesce(public.customers.user_id, auth.uid()),
        is_active = true,
        archived_at = null,
        updated_at = now()
  returning jsonb_build_object('linked', true, 'customer_id', id, 'user_id', user_id) into v_result;

  update public.account_requests
  set status = case when request_scope = 'customer' then 'approved' else status end,
      customer_id = coalesce(customer_id, v_customer_id),
      user_id = coalesce(user_id, auth.uid()),
      updated_at = now(),
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'auth_user_linked', true,
        'auth_user_linked_at', now(),
        'approval_not_required', request_scope = 'customer'
      )
  where lower(email) = v_email
    and request_scope = 'customer';

  return v_result;
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
  v_customer_id text;
begin
  if auth.uid() is null then
    return jsonb_build_object('allowed', false, 'state', 'no_session', 'message', 'Login required');
  end if;

  v_email := lower(nullif(auth.jwt()->>'email', ''));
  if v_email is null then
    return jsonb_build_object('allowed', false, 'state', 'no_email', 'message', 'Email unavailable');
  end if;

  perform public.link_customer_after_registration();

  select *
  into v_customer
  from public.customers
  where user_id = auth.uid()
     or lower(email) = v_email
  order by case when user_id = auth.uid() then 0 else 1 end
  limit 1;

  if not found then
    v_customer_id := 'CUST-' || substring(regexp_replace(v_email, '[^a-z0-9]', '', 'gi') from 1 for 30);
    insert into public.customers (id, user_id, name, email, phone, is_active, created_at, updated_at)
    values (v_customer_id, auth.uid(), v_email, v_email, '', true, now(), now())
    on conflict (id) do update
      set user_id = coalesce(public.customers.user_id, auth.uid()),
          is_active = true,
          archived_at = null,
          updated_at = now()
    returning * into v_customer;
  end if;

  if v_customer.is_active is false then
    return jsonb_build_object('allowed', false, 'state', 'archived', 'message', 'Customer account archived. Contact support@fleetconnect.be.');
  end if;

  return jsonb_build_object(
    'allowed', true,
    'state', 'active',
    'customer_id', v_customer.id,
    'email', v_email
  );
end;
$$;

create or replace function public.archive_operator_customer(p_customer_id text, p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer public.customers%rowtype;
begin
  if auth.uid() is null or not public.is_operator() then
    raise exception 'Operator access required';
  end if;

  update public.customers
  set is_active = false,
      archived_at = now(),
      updated_at = now()
  where id = p_customer_id
  returning * into v_customer;

  if not found then
    raise exception 'Customer not found';
  end if;

  return jsonb_build_object(
    'id', v_customer.id,
    'email', v_customer.email,
    'archived', true,
    'reason', coalesce(p_reason, '')
  );
end;
$$;

create or replace function public.get_operator_dashboard_snapshot()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not public.is_operator() then
    raise exception 'Operator access required';
  end if;

  return jsonb_build_object(
    'bookings', (
      select coalesce(jsonb_agg(to_jsonb(b) order by b.created_at desc), '[]'::jsonb)
      from public.bookings b
    ),
    'drivers', (
      select coalesce(jsonb_agg(to_jsonb(d) order by d.id), '[]'::jsonb)
      from public.drivers d
    ),
    'partners', (
      select coalesce(jsonb_agg(to_jsonb(p) order by p.is_hoofd desc, p.id), '[]'::jsonb)
      from public.partners p
    ),
    'customers', (
      select coalesce(jsonb_agg(to_jsonb(c) order by c.created_at desc), '[]'::jsonb)
      from public.customers c
    ),
    'account_requests', (
      select coalesce(jsonb_agg(to_jsonb(ar) order by ar.created_at desc), '[]'::jsonb)
      from public.account_requests ar
      where ar.request_scope <> 'customer'
    ),
    'operator', jsonb_build_object(
      'user_id', auth.uid(),
      'email', auth.jwt()->>'email'
    )
  );
end;
$$;

revoke all on function public.create_customer_registration_profile(jsonb) from public;
grant execute on function public.create_customer_registration_profile(jsonb) to anon, authenticated;

revoke all on function public.link_customer_after_registration() from public;
revoke all on function public.link_customer_after_registration() from anon;
grant execute on function public.link_customer_after_registration() to authenticated;

revoke all on function public.get_customer_portal_access() from public;
revoke all on function public.get_customer_portal_access() from anon;
grant execute on function public.get_customer_portal_access() to authenticated;

revoke all on function public.archive_operator_customer(text, text) from public;
revoke all on function public.archive_operator_customer(text, text) from anon;
grant execute on function public.archive_operator_customer(text, text) to authenticated;

revoke all on function public.get_operator_dashboard_snapshot() from public;
revoke all on function public.get_operator_dashboard_snapshot() from anon;
grant execute on function public.get_operator_dashboard_snapshot() to authenticated;

notify pgrst, 'reload schema';

commit;
