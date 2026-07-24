begin;

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
begin
  if auth.uid() is null then
    return jsonb_build_object('allowed', false, 'state', 'no_session', 'message', 'Login required');
  end if;

  v_email := lower(nullif(auth.jwt()->>'email', ''));
  if v_email is null then
    return jsonb_build_object('allowed', false, 'state', 'no_email', 'message', 'Email unavailable');
  end if;

  select *
  into v_request
  from public.account_requests
  where lower(email) = v_email
  order by created_at desc
  limit 1;

  if found and v_request.status = 'pending' then
    return jsonb_build_object('allowed', false, 'state', 'pending', 'message', 'Your account is awaiting approval.');
  end if;

  if found and v_request.status = 'rejected' then
    return jsonb_build_object('allowed', false, 'state', 'rejected', 'message', coalesce(v_request.rejection_reason, 'Account request rejected.'));
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
    return jsonb_build_object('allowed', false, 'state', 'profile_missing', 'message', 'Customer profile not linked.');
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
    and status = 'approved';

  return jsonb_build_object(
    'allowed', true,
    'state', 'approved',
    'customer_id', v_customer.id,
    'email', v_email
  );
end;
$$;

create or replace function public.get_public_ride_reviews(p_limit integer default 25)
returns table (
  booking_id text,
  rating integer,
  comment text,
  created_at timestamptz,
  customer_name text
)
language sql
security definer
set search_path = public
as $$
  select
    r.booking_id,
    r.rating,
    r.comment,
    r.created_at,
    coalesce(nullif(b.name, ''), 'FleetConnect customer') as customer_name
  from public.ride_reviews r
  join public.bookings b on b.id = r.booking_id
  where r.comment is not null
    and b.status = 'completed'
  order by r.created_at desc
  limit greatest(1, least(coalesce(p_limit, 25), 50));
$$;

revoke all on function public.get_customer_portal_access() from public;
revoke all on function public.get_customer_portal_access() from anon;
grant execute on function public.get_customer_portal_access() to authenticated;

revoke all on function public.get_public_ride_reviews(integer) from public;
grant execute on function public.get_public_ride_reviews(integer) to anon, authenticated;

notify pgrst, 'reload schema';

commit;
