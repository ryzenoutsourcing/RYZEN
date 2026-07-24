-- =============================================================================
-- Cycle 3 B-3: Make link_customer_after_registration and get_customer_portal_access idempotent
-- =============================================================================
--
-- Purpose: Fix the 409 duplicate key error that occurs when these two functions
-- are called on a customer that already has a row (the defense-in-depth pattern
-- in PV/klantenportaalpv.html).
--
-- Root cause: The original functions use `ON CONFLICT (id) DO UPDATE`, but
-- the conflict happens on the `email` unique constraint (not on `id`).
-- When `get_customer_portal_access` calls itself recursively or after
-- `link_customer_after_registration`, the second INSERT attempts to create
-- a new row with the same email but potentially a different computed id,
-- hitting the email unique constraint.
--
-- Fix: Add explicit handling for the email conflict case. Use the email
-- as the conflict target where applicable.
--
-- Scope: ADDITIVE only. No existing functions deleted. No tables modified.
-- No RLS policy changes. No data migrations.
--
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 1. link_customer_after_registration: now idempotent on email too
--    (the original is on id, which fails for the email-uniqueness case)
-- -----------------------------------------------------------------------------
create or replace function public.link_customer_after_registration()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_email text;
  v_customer_id text;
  v_existing_id text;
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

  -- Check if a customer with this email already exists with a different id
  select id into v_existing_id
  from public.customers
  where lower(email) = v_email
  limit 1;

  -- If exists, update that row; otherwise insert a new one
  if v_existing_id is not null then
    update public.customers
    set user_id = coalesce(public.customers.user_id, auth.uid()),
        is_active = true,
        archived_at = null,
        updated_at = now()
    where id = v_existing_id
    returning jsonb_build_object('linked', true, 'customer_id', id, 'user_id', user_id) into v_result;
  else
    insert into public.customers (id, user_id, name, email, phone, is_active, created_at, updated_at)
    values (v_customer_id, auth.uid(), v_email, v_email, '', true, now(), now())
    returning jsonb_build_object('linked', true, 'customer_id', id, 'user_id', user_id) into v_result;
  end if;

  -- Link the account_request if it exists for this email
  update public.account_requests
  set status = case when request_scope = 'customer' then 'approved' else status end,
      customer_id = coalesce(customer_id, v_existing_id, v_customer_id),
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
$function$;

-- -----------------------------------------------------------------------------
-- 2. get_customer_portal_access: handle the existing-email case
-- -----------------------------------------------------------------------------
create or replace function public.get_customer_portal_access()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_email text;
  v_customer public.customers%rowtype;
  v_customer_id text;
  v_existing_id text;
begin
  if auth.uid() is null then
    return jsonb_build_object('allowed', false, 'state', 'no_session', 'message', 'Login required');
  end if;

  v_email := lower(nullif(auth.jwt()->>'email', ''));
  if v_email is null then
    return jsonb_build_object('allowed', false, 'state', 'no_email', 'message', 'Email unavailable');
  end if;

  perform public.link_customer_after_registration();

  -- Look up by user_id first, then by email
  select *
  into v_customer
  from public.customers
  where user_id = auth.uid()
     or lower(email) = v_email
  order by case when user_id = auth.uid() then 0 else 1 end
  limit 1;

  if not found then
    v_customer_id := 'CUST-' || substring(regexp_replace(v_email, '[^a-z0-9]', '', 'gi') from 1 for 30);

    -- Check if a customer with this email already exists with a different id
    select id into v_existing_id
    from public.customers
    where lower(email) = v_email
    limit 1;

    if v_existing_id is not null then
      -- Update the existing row
      update public.customers
      set user_id = coalesce(public.customers.user_id, auth.uid()),
          is_active = true,
          archived_at = null,
          updated_at = now()
      where id = v_existing_id
      returning * into v_customer;
    else
      -- Insert a new row
      insert into public.customers (id, user_id, name, email, phone, is_active, created_at, updated_at)
      values (v_customer_id, auth.uid(), v_email, v_email, '', true, now(), now())
      on conflict (email) do update
        set user_id = coalesce(public.customers.user_id, auth.uid()),
            is_active = true,
            archived_at = null,
            updated_at = now()
      returning * into v_customer;
    end if;
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
$function$;

-- Re-grant (in case they were lost)
grant execute on function public.link_customer_after_registration() to authenticated;
grant execute on function public.get_customer_portal_access() to authenticated;

notify pgrst, 'reload schema';

commit;
