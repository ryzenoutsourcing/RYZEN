create table if not exists public.ride_reviews (
  id uuid primary key default gen_random_uuid(),
  booking_id text not null references public.bookings(id) on delete cascade,
  rating integer not null check (rating between 1 and 5),
  comment text,
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists idx_ride_reviews_booking_id on public.ride_reviews(booking_id);

alter table public.ride_reviews enable row level security;

drop policy if exists "operators can read ride reviews" on public.ride_reviews;
create policy "operators can read ride reviews"
on public.ride_reviews
for select
to authenticated
using (public.is_operator());

create or replace function public.submit_ride_review(
  p_booking_id text,
  p_rating integer,
  p_comment text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.bookings%rowtype;
  v_review public.ride_reviews%rowtype;
begin
  if p_booking_id is null or btrim(p_booking_id) = '' then
    raise exception 'Booking id required';
  end if;

  if p_rating is null or p_rating < 1 or p_rating > 5 then
    raise exception 'Rating must be between 1 and 5';
  end if;

  select *
  into v_booking
  from public.bookings
  where id = p_booking_id;

  if not found then
    raise exception 'Booking not found';
  end if;

  if v_booking.status <> 'completed' then
    raise exception 'Reviews are only available after ride completion';
  end if;

  insert into public.ride_reviews (booking_id, rating, comment, metadata)
  values (
    p_booking_id,
    p_rating,
    nullif(btrim(coalesce(p_comment, '')), ''),
    jsonb_build_object('source', 'review-page')
  )
  returning * into v_review;

  return to_jsonb(v_review);
end;
$$;

revoke all on function public.submit_ride_review(text, integer, text) from public;
grant execute on function public.submit_ride_review(text, integer, text) to anon;
grant execute on function public.submit_ride_review(text, integer, text) to authenticated;

notify pgrst, 'reload schema';
