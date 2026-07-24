begin;

-- Live approval failed with:
--   function gen_random_bytes(integer) does not exist
--
-- The approval RPCs are SECURITY DEFINER functions with an explicit search_path.
-- On Supabase, pgcrypto functions commonly live in the `extensions` schema, so
-- unqualified gen_random_bytes()/crypt()/gen_salt() are not visible unless that
-- schema is included.

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

alter function public._fc_generate_temp_password_hash()
  set search_path = public, auth, extensions;

alter function public.approve_account_request_with_invite(uuid, text)
  set search_path = public, auth, extensions;

notify pgrst, 'reload schema';

commit;
