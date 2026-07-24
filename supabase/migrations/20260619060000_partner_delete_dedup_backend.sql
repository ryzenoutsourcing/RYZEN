begin;

alter table public.partners add column if not exists archived_at timestamptz;
alter table public.partners add column if not exists updated_at timestamptz;
alter table public.drivers add column if not exists archived_at timestamptz;

create or replace function public.create_operator_partner(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
  v_email text;
  v_phone text;
  v_contact text;
  v_prefix text;
  v_is_hoofd boolean;
  v_action text;
  v_match public.partners%rowtype;
  v_result jsonb;
begin
  if auth.uid() is null or not public.is_operator() then
    raise exception 'Operator access required' using errcode = '42501';
  end if;

  if payload is null then
    raise exception 'Missing partner payload';
  end if;

  v_name := nullif(trim(payload->>'name'), '');
  if v_name is null then
    raise exception 'Partner name is required';
  end if;

  v_email := nullif(lower(trim(payload->>'email')), '');
  v_phone := nullif(regexp_replace(coalesce(payload->>'phone', ''), '[^0-9+]', '', 'g'), '');
  v_contact := nullif(trim(payload->>'contact'), '');
  v_is_hoofd := coalesce((payload->>'is_hoofd')::boolean, false);
  v_action := lower(nullif(trim(payload->>'duplicate_action'), ''));

  v_prefix := upper(nullif(regexp_replace(coalesce(payload->>'prefix', ''), '[^a-zA-Z0-9]', '', 'g'), ''));
  if v_prefix is null then
    v_prefix := upper(substr(regexp_replace(v_name, '[^a-zA-Z0-9]', '', 'g'), 1, 3));
  end if;
  if v_prefix is null or length(v_prefix) = 0 then
    v_prefix := 'PRT';
  end if;

  select *
    into v_match
    from public.partners p
   where (
      (v_email is not null and lower(coalesce(p.email, '')) = v_email)
      or (lower(coalesce(p.name, '')) = lower(v_name))
      or (v_prefix is not null and lower(coalesce(p.prefix, '')) = lower(v_prefix))
      or (v_phone is not null and regexp_replace(coalesce(p.phone, ''), '[^0-9+]', '', 'g') = v_phone)
   )
   order by (p.archived_at is null) desc, p.created_at desc nulls last, p.id desc
   limit 1;

  if found and v_match.archived_at is not null and coalesce(v_action, '') not in ('reactivate', 'replace') then
    return jsonb_build_object(
      'status', 'archived_match',
      'partner', jsonb_build_object(
        'id', v_match.id,
        'name', v_match.name,
        'email', v_match.email,
        'phone', v_match.phone,
        'prefix', v_match.prefix,
        'archived_at', v_match.archived_at
      )
    );
  end if;

  if found and v_match.archived_at is null and coalesce(v_action, '') <> 'replace' then
    return jsonb_build_object(
      'status', 'duplicate_active',
      'partner', jsonb_build_object(
        'id', v_match.id,
        'name', v_match.name,
        'email', v_match.email,
        'phone', v_match.phone,
        'prefix', v_match.prefix
      )
    );
  end if;

  if found and coalesce(v_action, '') in ('reactivate', 'replace') then
    update public.partners
       set name = v_name,
           is_hoofd = v_is_hoofd,
           prefix = v_prefix,
           contact = v_contact,
           email = v_email,
           phone = nullif(trim(payload->>'phone'), ''),
           archived_at = null,
           updated_at = now()
     where id = v_match.id
     returning jsonb_build_object(
       'id', id,
       'name', name,
       'is_hoofd', is_hoofd,
       'prefix', prefix,
       'contact', contact,
       'email', email,
       'phone', phone,
       'archived_at', archived_at
     ) into v_result;

    return jsonb_build_object('status', case when v_action = 'reactivate' then 'reactivated' else 'updated' end, 'partner', v_result);
  end if;

  insert into public.partners (name, is_hoofd, prefix, contact, email, phone, archived_at, updated_at)
  values (
    v_name,
    v_is_hoofd,
    v_prefix,
    v_contact,
    v_email,
    nullif(trim(payload->>'phone'), ''),
    null,
    now()
  )
  returning jsonb_build_object(
    'id', id,
    'name', name,
    'is_hoofd', is_hoofd,
    'prefix', prefix,
    'contact', contact,
    'email', email,
    'phone', phone,
    'archived_at', archived_at
  ) into v_result;

  return jsonb_build_object('status', 'created', 'partner', v_result);
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
  v_active_driver_count integer;
  v_booking_count integer;
begin
  if auth.uid() is null or not public.is_operator() then
    raise exception 'Operator access required' using errcode = '42501';
  end if;

  select * into v_partner from public.partners where id = p_partner_id;
  if not found then
    raise exception 'Partner not found';
  end if;

  if coalesce(v_partner.is_hoofd, false) then
    raise exception 'Hoofdpartners cannot be deleted. Archive only after migration planning.';
  end if;

  select count(*) into v_active_driver_count
    from public.drivers
   where partner_id = p_partner_id
     and coalesce(is_active, true) = true
     and archived_at is null;

  select count(*) into v_booking_count
    from public.bookings
   where partner_id = p_partner_id
      or assigned_driver_id in (select id from public.drivers where partner_id = p_partner_id);

  if v_active_driver_count > 0 or v_booking_count > 0 then
    raise exception 'Partner has active drivers or ride history. Archive the partner instead of deleting.';
  end if;

  delete from public.partners where id = p_partner_id;

  return jsonb_build_object('status', 'deleted', 'partner_id', p_partner_id);
end;
$$;

revoke all on function public.create_operator_partner(jsonb) from public;
revoke all on function public.delete_operator_partner(integer) from public;
revoke all on function public.create_operator_partner(jsonb) from anon;
revoke all on function public.delete_operator_partner(integer) from anon;
grant execute on function public.create_operator_partner(jsonb) to authenticated;
grant execute on function public.delete_operator_partner(integer) to authenticated;

commit;
