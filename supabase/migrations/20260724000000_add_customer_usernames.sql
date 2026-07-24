begin;

-- 1. Add username column to public.customers if it doesn't already exist
alter table public.customers add column if not exists username text;

-- 2. Add unique constraint on lower(username) if it doesn't already exist
create unique index if not exists idx_customers_username_unique on public.customers (lower(username));

-- 3. Update existing customer records to generate a default username
-- For specifically "The Lodge", assign "TheLodgeVilvoorde"
update public.customers
set username = 'TheLodgeVilvoorde'
where lower(name) = 'the lodge' or lower(email) = 'lodge@lodge.com' or lower(name) like '%the lodge%';

-- For other existing customers, dynamically generate a unique username from their name or email if username is null
update public.customers
set username = regexp_replace(lower(coalesce(name, split_part(email, '@', 1))), '[^a-z0-9]', '', 'g')
where username is null;

-- Ensure any null usernames (if any left) are set to a fallback string + id suffix
update public.customers
set username = 'fcuser_' || substring(id from 1 for 8)
where username is null or username = '';

-- 4. Create resolution helper function: resolve_username_to_email
create or replace function public.resolve_username_to_email(p_username text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_email text;
  v_username text;
begin
  v_username := lower(trim(p_username));
  if v_username is null or v_username = '' then
    return jsonb_build_object('success', false, 'error', 'Gebruikersnaam mag niet leeg zijn');
  end if;

  select email into v_email
  from public.customers
  where lower(username) = v_username
  limit 1;

  if v_email is not null then
    return jsonb_build_object('success', true, 'email', v_email);
  else
    return jsonb_build_object('success', false, 'error', 'Gebruikersnaam niet gevonden');
  end if;
end;
$$;

-- Grant execution permissions
revoke all on function public.resolve_username_to_email(text) from public;
grant execute on function public.resolve_username_to_email(text) to anon, authenticated;

commit;
