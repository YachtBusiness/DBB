-- The same link can't be saved twice (same people or organisations, same role, same context and dates),
-- e.g. when Save is clicked again on a slow connection.
create unique index if not exists links_no_duplicates on public.links
  (from_id, to_id, lower(btrim(role)), coalesce(context_id, ''), start_date, end_date);
