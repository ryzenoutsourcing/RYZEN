begin;

create or replace function public.check_duplicate_registration(p_email text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  v_email text;
  v_auth record;
  v_customer_exists boolean;
  v_partner_exists boolean;
  v_driver_exists boolean;
  v_request public.account_requests%rowtype;
begin
  v_email := lower(nullif(trim(p_email), ''));
  if v_email is null or position('@' in v_email) = 0 then
    return jsonb_build_object('exists', false);
  end if;

  select id, email_confirmed_at
  into v_auth
  from auth.users
  where lower(email) = v_email
  order by created_at desc
  limit 1;

  select exists (
    select 1 from public.customers
    where lower(email) = v_email
      and coalesce(is_active, true) = true
  ) into v_customer_exists;

  select exists (
    select 1 from public.partners
    where lower(email) = v_email
  ) into v_partner_exists;

  select exists (
    select 1 from public.drivers
    where lower(email) = v_email
      and coalesce(is_active, true) = true
      and archived_at is null
  ) into v_driver_exists;

  select *
  into v_request
  from public.account_requests
  where lower(email) = v_email
    and status in ('pending', 'approved')
  order by created_at desc
  limit 1;

  if v_partner_exists then
    return jsonb_build_object(
      'exists', true,
      'kind', 'partner_profile',
      'action', 'login',
      'reason', 'Er bestaat al een partneraccount voor dit e-mailadres. Log in via FleetConnect Partner of gebruik wachtwoord vergeten.'
    );
  end if;

  if v_driver_exists then
    return jsonb_build_object(
      'exists', true,
      'kind', 'driver_profile',
      'action', 'login',
      'reason', 'Er bestaat al een chauffeursaccount voor dit e-mailadres. Log in via FleetConnect Partner of gebruik wachtwoord vergeten.'
    );
  end if;

  if v_customer_exists then
    return jsonb_build_object(
      'exists', true,
      'kind', 'customer_profile',
      'action', 'login',
      'reason', 'Dit e-mailadres is al gekoppeld aan een klantaccount. Ga naar de inlogpagina om in te loggen.'
    );
  end if;

  if v_request.id is not null then
    return jsonb_build_object(
      'exists', true,
      'kind', 'account_request',
      'action', case when v_request.status = 'approved' then 'login' else 'wait' end,
      'status', v_request.status,
      'request_scope', v_request.request_scope,
      'account_type', v_request.account_type,
      'created_at', v_request.created_at,
      'reason', case
        when v_request.status = 'approved' then 'Deze accountaanvraag is al goedgekeurd. Log in of gebruik wachtwoord vergeten.'
        else 'Er is al een accountaanvraag voor dit e-mailadres in behandeling. U wordt gecontacteerd zodra deze is goedgekeurd.'
      end
    );
  end if;

  if v_auth.id is not null then
    if v_auth.email_confirmed_at is not null then
      return jsonb_build_object(
        'exists', true,
        'kind', 'verified_user',
        'action', 'login',
        'reason', 'Dit e-mailadres is al geregistreerd en geverifieerd. Ga naar de inlogpagina om in te loggen.'
      );
    end if;

    return jsonb_build_object(
      'exists', true,
      'kind', 'unverified_user',
      'action', 'resend_verification',
      'reason', 'Dit e-mailadres heeft een onvoltooide registratie. Controleer uw inbox voor de verificatielink, of neem contact op met support.'
    );
  end if;

  return jsonb_build_object('exists', false);
end;
$$;

revoke all on function public.check_duplicate_registration(text) from public;
grant execute on function public.check_duplicate_registration(text) to anon, authenticated;

notify pgrst, 'reload schema';

commit;
