begin;

alter table public.partners add column if not exists updated_at timestamptz;
alter table public.partners add column if not exists archived_at timestamptz;
alter table public.customers add column if not exists updated_at timestamptz;
alter table public.customers add column if not exists archived_at timestamptz;
alter table public.drivers add column if not exists updated_at timestamptz;
alter table public.drivers add column if not exists archived_at timestamptz;

create or replace function public.update_account_request(
    p_request_id uuid,
    p_name text default null,
    p_email text default null,
    p_phone text default null,
    p_company text default null,
    p_notes text default null,
    p_status text default null,
    p_metadata jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_existing public.account_requests%rowtype;
    v_new_status text;
    v_result jsonb;
begin
    if auth.uid() is null or not public.is_operator() then
        raise exception 'Operator access required' using errcode = '42501';
    end if;

    select * into v_existing from public.account_requests where id = p_request_id;
    if not found then
        raise exception 'Account request not found';
    end if;

    v_new_status := coalesce(p_status, v_existing.status);
    if v_new_status not in ('pending', 'approved', 'rejected', 'archived') then
        raise exception 'Invalid status';
    end if;

    update public.account_requests
       set name = coalesce(nullif(trim(p_name), ''), name),
           email = case when p_email is null then email else lower(nullif(trim(p_email), '')) end,
           phone = case when p_phone is null then phone else nullif(trim(p_phone), '') end,
           company = case when p_company is null then company else nullif(trim(p_company), '') end,
           notes = case when p_notes is null then notes else nullif(trim(p_notes), '') end,
           status = v_new_status,
           metadata = case when p_metadata is not null then coalesce(metadata, '{}'::jsonb) || p_metadata else metadata end,
           updated_at = now()
     where id = p_request_id
     returning to_jsonb(account_requests.*) into v_result;

    return v_result;
end;
$$;

create or replace function public.update_customer(
    p_customer_id text,
    p_name text default null,
    p_phone text default null,
    p_default_pickup_address text default null,
    p_is_active boolean default null,
    p_archived boolean default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_result jsonb;
begin
    if auth.uid() is null or not (public.is_operator() or public.is_partner()) then
        raise exception 'Operator or partner access required' using errcode = '42501';
    end if;

    if not exists (select 1 from public.customers where id = p_customer_id) then
        raise exception 'Customer not found';
    end if;

    update public.customers
       set name = coalesce(nullif(trim(p_name), ''), name),
           phone = case when p_phone is null then phone else nullif(trim(p_phone), '') end,
           default_pickup_address = case when p_default_pickup_address is null then default_pickup_address else nullif(trim(p_default_pickup_address), '') end,
           is_active = coalesce(p_is_active, is_active),
           archived_at = case when p_archived is true then now() when p_archived is false then null else archived_at end,
           updated_at = now()
     where id = p_customer_id
     returning to_jsonb(customers.*) into v_result;

    return v_result;
end;
$$;

create or replace function public.update_driver(
    p_driver_id uuid,
    p_name text default null,
    p_email text default null,
    p_phone text default null,
    p_vehicle text default null,
    p_license_plate text default null,
    p_color text default null,
    p_is_active boolean default null,
    p_archived boolean default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_result jsonb;
begin
    if auth.uid() is null or not (public.is_operator() or public.is_partner()) then
        raise exception 'Operator or partner access required' using errcode = '42501';
    end if;

    if not exists (select 1 from public.drivers where id = p_driver_id) then
        raise exception 'Driver not found';
    end if;

    update public.drivers
       set name = coalesce(nullif(trim(p_name), ''), name),
           email = case when p_email is null then email else lower(nullif(trim(p_email), '')) end,
           phone = case when p_phone is null then phone else nullif(trim(p_phone), '') end,
           vehicle = case when p_vehicle is null then vehicle else nullif(trim(p_vehicle), '') end,
           license_plate = case when p_license_plate is null then license_plate else nullif(trim(p_license_plate), '') end,
           color = case when p_color is null then color else nullif(trim(p_color), '') end,
           is_active = coalesce(p_is_active, is_active),
           archived_at = case when p_archived is true then now() when p_archived is false then null else archived_at end,
           updated_at = now()
     where id = p_driver_id
     returning to_jsonb(drivers.*) into v_result;

    return v_result;
end;
$$;

create or replace function public.update_booking(
    p_booking_id text,
    p_status text default null,
    p_notes text default null,
    p_amount numeric default null,
    p_payment text default null,
    p_assigned_driver_id uuid default null,
    p_partner_id int default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_result jsonb;
begin
    if auth.uid() is null or not (public.is_operator() or public.is_partner()) then
        raise exception 'Operator or partner access required' using errcode = '42501';
    end if;

    if not exists (select 1 from public.bookings where id = p_booking_id) then
        raise exception 'Booking not found';
    end if;

    update public.bookings
       set status = coalesce(p_status, status),
           notes = coalesce(p_notes, notes),
           amount = coalesce(p_amount, amount),
           payment = coalesce(p_payment, payment),
           assigned_driver_id = coalesce(p_assigned_driver_id, assigned_driver_id),
           partner_id = coalesce(p_partner_id, partner_id)
     where id = p_booking_id
     returning to_jsonb(bookings.*) into v_result;

    return v_result;
end;
$$;

revoke all on function public.update_account_request(uuid, text, text, text, text, text, text, jsonb) from public;
revoke all on function public.update_customer(text, text, text, text, boolean, boolean) from public;
revoke all on function public.update_driver(uuid, text, text, text, text, text, text, boolean, boolean) from public;
revoke all on function public.update_booking(text, text, text, numeric, text, uuid, integer) from public;

grant execute on function public.update_account_request(uuid, text, text, text, text, text, text, jsonb) to authenticated;
grant execute on function public.update_customer(text, text, text, text, boolean, boolean) to authenticated;
grant execute on function public.update_driver(uuid, text, text, text, text, text, text, boolean, boolean) to authenticated;
grant execute on function public.update_booking(text, text, text, numeric, text, uuid, integer) to authenticated;

commit;
