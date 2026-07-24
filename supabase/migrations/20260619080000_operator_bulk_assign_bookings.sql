begin;

alter table public.partners add column if not exists archived_at timestamptz;
alter table public.drivers add column if not exists archived_at timestamptz;

create or replace function public.operator_bulk_assign_bookings(
  p_booking_ids text[],
  p_partner_id integer default null,
  p_driver_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_driver public.drivers%rowtype;
  v_partner public.partners%rowtype;
  v_updated_count integer := 0;
begin
  if auth.uid() is null or not public.is_operator() then
    raise exception 'Operator access required' using errcode = '42501';
  end if;

  if p_booking_ids is null or array_length(p_booking_ids, 1) is null then
    raise exception 'No bookings selected';
  end if;

  if p_partner_id is null and p_driver_id is null then
    raise exception 'Select a partner or driver';
  end if;

  if p_partner_id is not null then
    select * into v_partner
      from public.partners
     where id = p_partner_id
       and archived_at is null;
    if not found then
      raise exception 'Active partner not found';
    end if;
  end if;

  if p_driver_id is not null then
    select * into v_driver
      from public.drivers
     where id = p_driver_id
       and coalesce(is_active, true) = true
       and archived_at is null;
    if not found then
      raise exception 'Active driver not found';
    end if;

    if p_partner_id is not null and v_driver.partner_id <> p_partner_id then
      raise exception 'Selected driver does not belong to selected partner';
    end if;

    p_partner_id := coalesce(p_partner_id, v_driver.partner_id);
  end if;

  if exists (
    select 1
      from public.bookings b
     where b.id = any(p_booking_ids)
       and b.status in ('completed', 'cancelled')
  ) then
    raise exception 'Completed or cancelled rides cannot be bulk reassigned';
  end if;

  if p_driver_id is null then
    update public.bookings b
       set partner_id = p_partner_id,
           metadata = coalesce(b.metadata, '{}'::jsonb) || jsonb_build_object(
             'bulk_partner_assigned_at', now(),
             'bulk_partner_assigned_by', auth.uid()
           )
     where b.id = any(p_booking_ids);

    get diagnostics v_updated_count = row_count;
  else
    update public.bookings b
       set partner_id = p_partner_id,
           status = 'assignment_sent',
           assigned_driver_id = v_driver.id,
           assignment_token = gen_random_uuid()::text,
           assignment_sent_at = now(),
           assignment_accepted_at = null,
           assignment_declined_at = null,
           assigned_driver = jsonb_build_object(
             'id', v_driver.id,
             'name', v_driver.name,
             'email', v_driver.email,
             'phone', v_driver.phone,
             'vehicle', v_driver.vehicle,
             'color', v_driver.color,
             'license_plate', v_driver.license_plate
           ),
           metadata = coalesce(b.metadata, '{}'::jsonb)
             - 'driver_recalled'
             || jsonb_build_object(
               'bulk_driver_assigned_at', now(),
               'bulk_driver_assigned_by', auth.uid(),
               'bulk_previous_driver_id', b.assigned_driver_id,
               'reassignment_pending_driver_acceptance', b.assigned_driver_id is not null and b.assigned_driver_id <> v_driver.id
             )
     where b.id = any(p_booking_ids);

    get diagnostics v_updated_count = row_count;
  end if;

  return jsonb_build_object(
    'status', 'updated',
    'updated_count', v_updated_count,
    'partner_id', p_partner_id,
    'driver_id', p_driver_id
  );
end;
$$;

revoke all on function public.operator_bulk_assign_bookings(text[], integer, uuid) from public;
revoke all on function public.operator_bulk_assign_bookings(text[], integer, uuid) from anon;
grant execute on function public.operator_bulk_assign_bookings(text[], integer, uuid) to authenticated;

commit;
