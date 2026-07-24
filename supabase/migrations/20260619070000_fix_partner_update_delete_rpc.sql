begin;

alter table public.partners add column if not exists archived_at timestamptz;
alter table public.partners add column if not exists updated_at timestamptz;
alter table public.drivers add column if not exists archived_at timestamptz;

create or replace function public.update_partner(
    p_partner_id int,
    p_name text default null,
    p_email text default null,
    p_phone text default null,
    p_prefix text default null,
    p_is_hoofd boolean default null,
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
    if auth.uid() is null or not public.is_operator() then
        raise exception 'Operator access required' using errcode = '42501';
    end if;

    if not exists (select 1 from public.partners where id = p_partner_id) then
        raise exception 'Partner not found';
    end if;

    update public.partners
       set name = coalesce(nullif(trim(p_name), ''), name),
           email = case when p_email is null then email else lower(nullif(trim(p_email), '')) end,
           phone = case when p_phone is null then phone else nullif(trim(p_phone), '') end,
           prefix = case when p_prefix is null then prefix else upper(nullif(regexp_replace(p_prefix, '[^a-zA-Z0-9]', '', 'g'), '')) end,
           is_hoofd = coalesce(p_is_hoofd, is_hoofd),
           archived_at = case
             when p_archived is true then now()
             when p_archived is false then null
             else archived_at
           end,
           updated_at = now()
     where id = p_partner_id
     returning to_jsonb(partners.*) into v_result;

    return v_result;
end;
$$;

create or replace function public.delete_operator_partner(p_partner_id integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_partner public.partners%rowtype;
  v_driver_count integer;
  v_booking_count integer;
begin
  if auth.uid() is null or not public.is_operator() then
    raise exception 'Operator access required' using errcode = '42501';
  end if;

  select * into v_partner from public.partners where id = p_partner_id;
  if not found then
    raise exception 'Partner not found';
  end if;

  select count(*) into v_driver_count
    from public.drivers
   where partner_id = p_partner_id;

  select count(*) into v_booking_count
    from public.bookings
   where partner_id = p_partner_id
      or assigned_driver_id in (select id from public.drivers where partner_id = p_partner_id);

  if v_driver_count > 0 or v_booking_count > 0 then
    raise exception 'Partner heeft chauffeurs of ritgeschiedenis. Archiveer deze partner zodat de Supabase-historiek bewaard blijft.';
  end if;

  delete from public.partners where id = p_partner_id;

  return jsonb_build_object('status', 'deleted', 'partner_id', p_partner_id, 'name', v_partner.name);
end;
$$;

revoke all on function public.update_partner(integer, text, text, text, text, boolean, boolean) from public;
revoke all on function public.delete_operator_partner(integer) from public;
revoke all on function public.update_partner(integer, text, text, text, text, boolean, boolean) from anon;
revoke all on function public.delete_operator_partner(integer) from anon;
grant execute on function public.update_partner(integer, text, text, text, text, boolean, boolean) to authenticated;
grant execute on function public.delete_operator_partner(integer) to authenticated;

commit;
