begin;

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

revoke all on function public.get_operator_dashboard_snapshot() from public;
revoke all on function public.get_operator_dashboard_snapshot() from anon;
grant execute on function public.get_operator_dashboard_snapshot() to authenticated;

notify pgrst, 'reload schema';

commit;
