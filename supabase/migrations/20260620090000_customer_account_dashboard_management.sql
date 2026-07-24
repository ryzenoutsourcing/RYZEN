begin;

alter table public.customers add column if not exists is_active boolean not null default true;
alter table public.customers add column if not exists archived_at timestamptz;
alter table public.customers add column if not exists updated_at timestamptz;

create or replace function public.update_operator_customer(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer_id text;
  v_email text;
  v_is_active boolean;
  v_result jsonb;
begin
  if auth.uid() is null or not public.is_operator() then
    raise exception 'Operator access required' using errcode = '42501';
  end if;

  v_customer_id := nullif(trim(payload->>'id'), '');
  if v_customer_id is null then
    raise exception 'Customer id is required';
  end if;

  if not exists (select 1 from public.customers where id = v_customer_id) then
    raise exception 'Customer not found';
  end if;

  v_email := lower(nullif(trim(payload->>'email'), ''));
  if v_email is not null and position('@' in v_email) = 0 then
    raise exception 'Valid email is required';
  end if;

  if payload ? 'is_active' then
    v_is_active := (payload->>'is_active')::boolean;
  end if;

  update public.customers
     set name = case when payload ? 'name' then nullif(trim(payload->>'name'), '') else name end,
         email = coalesce(v_email, email),
         phone = case when payload ? 'phone' then nullif(trim(payload->>'phone'), '') else phone end,
         default_pickup_address = case
           when payload ? 'default_pickup_address' then nullif(trim(payload->>'default_pickup_address'), '')
           else default_pickup_address
         end,
         is_active = coalesce(v_is_active, is_active),
         archived_at = case
           when v_is_active is true then null
           when v_is_active is false then coalesce(archived_at, now())
           else archived_at
         end,
         updated_at = now()
   where id = v_customer_id
   returning to_jsonb(customers.*) into v_result;

  return v_result;
end;
$$;

create or replace function public.delete_operator_customer(p_customer_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer public.customers%rowtype;
  v_booking_count integer;
begin
  if auth.uid() is null or not public.is_operator() then
    raise exception 'Operator access required' using errcode = '42501';
  end if;

  select * into v_customer from public.customers where id = p_customer_id;
  if not found then
    raise exception 'Customer not found';
  end if;

  select count(*) into v_booking_count
    from public.bookings
   where customer_id = p_customer_id
      or lower(coalesce(email, '')) = lower(coalesce(v_customer.email, ''));

  if v_booking_count > 0 then
    raise exception 'Customer has ride history. Archive this customer instead of deleting.';
  end if;

  delete from public.account_requests where customer_id = p_customer_id;
  delete from public.customers where id = p_customer_id;

  return jsonb_build_object('status', 'deleted', 'customer_id', p_customer_id, 'email', v_customer.email);
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
    ),
    'operator', jsonb_build_object(
      'user_id', auth.uid(),
      'email', auth.jwt()->>'email'
    )
  );
end;
$$;

revoke all on function public.update_operator_customer(jsonb) from public;
revoke all on function public.update_operator_customer(jsonb) from anon;
grant execute on function public.update_operator_customer(jsonb) to authenticated;

revoke all on function public.delete_operator_customer(text) from public;
revoke all on function public.delete_operator_customer(text) from anon;
grant execute on function public.delete_operator_customer(text) to authenticated;

revoke all on function public.get_operator_dashboard_snapshot() from public;
revoke all on function public.get_operator_dashboard_snapshot() from anon;
grant execute on function public.get_operator_dashboard_snapshot() to authenticated;

notify pgrst, 'reload schema';

commit;
