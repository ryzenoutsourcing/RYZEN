begin;

create table if not exists public.account_requests (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  email text not null,
  phone text,
  company text,
  account_type text not null check (account_type in ('Operations', 'Partner', 'Driver', 'Client', 'Other')),
  notes text,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.account_requests enable row level security;

drop policy if exists "Service role full access account requests" on public.account_requests;
create policy "Service role full access account requests"
on public.account_requests
for all
to service_role
using (true)
with check (true);

drop policy if exists "Operators can view account requests" on public.account_requests;
create policy "Operators can view account requests"
on public.account_requests
for select
to authenticated
using (public.is_operator());

create or replace function public.submit_account_request(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
  v_email text;
  v_phone text;
  v_company text;
  v_account_type text;
  v_notes text;
  v_result jsonb;
begin
  if payload is null then
    raise exception 'Missing account request payload';
  end if;

  v_name := nullif(trim(payload->>'name'), '');
  v_email := lower(nullif(trim(payload->>'email'), ''));
  v_phone := nullif(trim(payload->>'phone'), '');
  v_company := nullif(trim(payload->>'company'), '');
  v_account_type := coalesce(nullif(trim(payload->>'account_type'), ''), 'Other');
  v_notes := nullif(trim(payload->>'notes'), '');

  if v_name is null then
    raise exception 'Name is required';
  end if;

  if v_email is null or position('@' in v_email) = 0 then
    raise exception 'Valid email is required';
  end if;

  if v_account_type not in ('Operations', 'Partner', 'Driver', 'Client', 'Other') then
    raise exception 'Invalid account type';
  end if;

  insert into public.account_requests (
    name, email, phone, company, account_type, notes, metadata
  )
  values (
    v_name,
    v_email,
    v_phone,
    v_company,
    v_account_type,
    v_notes,
    jsonb_build_object(
      'source', coalesce(payload->>'source', 'operator-login'),
      'user_agent', coalesce(payload->>'user_agent', ''),
      'submitted_at', now()
    )
  )
  returning jsonb_build_object(
    'id', id,
    'status', status,
    'created_at', created_at
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.submit_account_request(jsonb) from public;
grant execute on function public.submit_account_request(jsonb) to anon, authenticated;

commit;
