-- 0.3.11: dates on events for the calendar. Start and end dates (end may equal start), and a provisional flag for
-- dates not yet confirmed (shown by month, "dates to be confirmed"). Forward-only: past events aren't given dates.
alter table public.entities
  add column if not exists start_date date,
  add column if not exists end_date date,
  add column if not exists dates_provisional boolean not null default false;
alter table public.entities add constraint entities_dates_check
  check (end_date is null or (start_date is not null and end_date >= start_date));
create index if not exists entities_start_date_idx on public.entities(start_date) where start_date is not null;
