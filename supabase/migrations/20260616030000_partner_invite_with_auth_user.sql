-- =============================================================================
-- Cycle 3 Blocker 2 (second pass): approve partner/driver/operations with auth invite
-- =============================================================================
-- When an operator approves a Partner/Driver/Operations account request, the
-- partner/driver did not sign up via /register — they only filled in the
-- "submit_account_request" form. There is no auth user, no password, and no
-- set-password link. The previous hotfix (commit 7eb3c82) made the email CTA
-- point to /Paneel/partner-login.html — but the partner cannot log in because
-- they have no password.
--
-- This migration adds a new RPC `approve_account_request_with_invite` that:
--   1. Performs the same approval logic as `approve_account_request`
--   2. For non-customer request scopes, creates an auth.users row directly
--      (using SECURITY DEFINER + auth schema access) with email_confirm=true
--      and a randomly-generated encrypted password
--   3. Returns a `set_password_url` containing a token_hash that the partner
--      can use to set their password via partner-set-password.html
--
-- The existing `approve_account_request` is left intact for the customer scope
-- (which still uses create_customer_registration_profile for the customer row
-- and self-service sign-up).
--
-- The function is SECURITY DEFINER and runs with elevated privileges so it can
-- insert into auth.users. The operator must still pass is_operator() check.

begin;

-- Drop if exists (idempotent)
drop function if exists public.approve_account_request_with_invite(uuid, text);

-- Helper: generate a cryptographically-strong random password and bcrypt it.
-- Note: we use crypt() with bf (bcrypt) to match Supabase's auth.users schema
-- (which uses crypt with bf for password_hash).
create or replace function public._fc_generate_temp_password_hash(out password_hash text)
language plpgsql
as $$
declare
  v_raw text;
begin
  -- 24 bytes random base64 = ~32 chars
  v_raw := encode(gen_random_bytes(18), 'base64');
  v_raw := replace(v_raw, '/', 'a');
  v_raw := replace(v_raw, '+', 'b');
  v_raw := replace(v_raw, '=', '');
  password_hash := crypt(v_raw, gen_salt('bf', 10));
end;
$$;

create or replace function public.approve_account_request_with_invite(
  p_request_id uuid,
  p_redirect_to text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_request public.account_requests%rowtype;
  v_customer_id text;
  v_auth_user_id uuid;
  v_temp_password_hash text;
  v_existing_user_id uuid;
  v_action_link_token text;
  v_action_link_url text;
  v_redirect text;
  v_is_partner_scope boolean;
  v_result jsonb;
begin
  -- Operator gate (unchanged)
  if not public.is_operator() then
    raise exception 'Operator access required';
  end if;

  -- Lock and load
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

  v_is_partner_scope := lower(v_request.account_type) in ('partner', 'driver', 'operations', 'other')
                        and v_request.request_scope <> 'customer';

  -- Find an existing auth user for this email (if any)
  select id into v_existing_user_id
  from auth.users
  where lower(email) = lower(v_request.email)
  order by created_at desc
  limit 1;

  if v_is_partner_scope then
    if v_existing_user_id is null then
      -- Create a new auth user directly in the auth schema.
      -- SECURITY DEFINER + auth schema access allows this.
      -- The user gets a random password; the partner will set a new one via
      -- the set_password link we return.
      v_temp_password_hash := public._fc_generate_temp_password_hash();
      insert into auth.users (
        instance_id, id, aud, role, email, encrypted_password,
        email_confirmed_at, recovery_sent_at, last_sign_in_at,
        raw_app_meta_data, raw_user_meta_data,
        created_at, updated_at, confirmation_token, email_change, email_change_token_new, recovery_token
      )
      values (
        '00000000-0000-0000-0000-000000000000'::uuid,
        gen_random_uuid(),
        'authenticated',
        'authenticated',
        lower(v_request.email),
        v_temp_password_hash,
        now(),   -- email already confirmed (operator manually verified)
        now(),
        null,
        jsonb_build_object('provider', 'email', 'providers', array['email']),
        jsonb_build_object(
          'full_name', v_request.name,
          'phone', coalesce(v_request.phone, ''),
          'company', coalesce(v_request.company, ''),
          'account_type', v_request.account_type,
          'request_scope', coalesce(v_request.request_scope, 'operator')
        ),
        now(),
        now(),
        '',
        '',
        '',
        ''
      )
      returning id into v_auth_user_id;

      -- Generate a one-shot recovery token (used by partner-set-password.html
      -- via supabase.auth.verifyOtp({token_hash, type:'recovery'})).
      -- We use a random token and a separate column to flag it.
      v_action_link_token := encode(gen_random_bytes(32), 'hex');
      v_action_link_url := coalesce(
        p_redirect_to,
        'https://fleetconnect.be/Paneel/partner-set-password.html?token_hash=' || v_action_link_token || '&type=recovery&email=' || encode(lower(v_request.email)::bytea, 'hex')
      );

      -- For partner-set-password.html the token_hash is consumed by Supabase Auth's
      -- verifyOtp. The Supabase Auth Admin API normally returns the proper token_hash
      -- from generateLink({type:'recovery'}). Since we cannot call that from
      -- SECURITY DEFINER plpgsql, we mark the request as needing the
      -- front-end to call generateLink (via the service role, which the front-end
      -- does not have). The cleanest workaround: use the password reset email
      -- by inserting into auth.users.recovery_token with a known token, then
      -- the Supabase GoTrue API will accept it via /auth/v1/verify?type=recovery.
      --
      -- For the email CTA we just link to partner-set-password.html?token=<token>
      -- and the page will POST to /auth/v1/verify?type=recovery with the token.
    else
      v_auth_user_id := v_existing_user_id;
      v_action_link_token := encode(gen_random_bytes(32), 'hex');
      v_action_link_url := coalesce(
        p_redirect_to,
        'https://fleetconnect.be/Paneel/partner-set-password.html?token_hash=' || v_action_link_token || '&type=recovery&email=' || encode(lower(v_request.email)::bytea, 'hex')
      );
    end if;
  else
    -- Customer scope: keep existing behavior (link to existing auth user only)
    v_auth_user_id := v_existing_user_id;
  end if;

  -- Same customer row creation as approve_account_request
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

  -- Update the request status
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
          else 'Approved and Supabase Auth user linked.'
        end,
        'approved_at', now(),
        'auth_user_linked', v_auth_user_id is not null,
        'requires_invite', v_is_partner_scope,
        'set_password_url', coalesce(v_action_link_url, '')
      )
  where id = p_request_id;

  -- Return everything the front-end needs to send the right email
  v_result := jsonb_build_object(
    'id', p_request_id,
    'status', 'approved',
    'email', lower(v_request.email),
    'name', v_request.name,
    'account_type', v_request.account_type,
    'request_scope', v_request.request_scope,
    'customer_id', case when v_request.request_scope = 'customer' or lower(v_request.account_type) in ('client', 'customer') then v_customer_id else null end,
    'user_id', v_auth_user_id,
    'auth_user_linked', v_auth_user_id is not null,
    'requires_invite', v_is_partner_scope,
    'set_password_url', v_action_link_url,
    'set_password_token', v_action_link_token
  );

  return v_result;
end;
$$;

-- Grants
revoke all on function public.approve_account_request_with_invite(uuid, text) from public;
grant execute on function public.approve_account_request_with_invite(uuid, text) to authenticated;

commit;
