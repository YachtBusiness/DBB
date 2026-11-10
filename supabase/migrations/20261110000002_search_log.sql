-- 0.3.18: anonymous search log. Records the entry picked from the search box, and the text typed when a
-- search finds nothing. No account, IP or device is stored. Editors' own searches are not logged.
-- Rows older than 12 months are deleted monthly. Only editors can read it, through search_report().
create table if not exists public.search_log (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  term text not null default '',
  entity_id text references public.entities(id) on delete set null,
  found boolean not null
);
create index if not exists search_log_at on public.search_log (at desc);
alter table public.search_log enable row level security;
revoke all on public.search_log from anon, authenticated;

create or replace function public.log_search(p_term text, p_entity text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare t text := left(btrim(coalesce(p_term, '')), 80);
begin
  if public.is_editor() then return; end if;
  if p_entity is not null and not exists (select 1 from public.entities where id = p_entity) then p_entity := null; end if;
  if p_entity is null and char_length(t) < 3 then return; end if;
  -- flood brake
  if (select count(*) from public.search_log where at > now() - interval '1 hour') >= 3000 then return; end if;
  insert into public.search_log (term, entity_id, found) values (t, p_entity, p_entity is not null);
end $$;
revoke all on function public.log_search(text, text) from public;
grant execute on function public.log_search(text, text) to anon, authenticated;

-- Editors' report: most picked entries and most common no-result terms over the last p_days days.
create or replace function public.search_report(p_days int default 30) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare since timestamptz := now() - make_interval(days => greatest(1, least(coalesce(p_days, 30), 400)));
begin
  if not public.is_editor() then raise exception 'editors only'; end if;
  return jsonb_build_object(
    'total', (select count(*) from public.search_log where at >= since),
    'picked', coalesce((select jsonb_agg(x order by x.n desc, x.last desc) from (
        select entity_id as id, count(*) as n, max(at) as last from public.search_log
        where at >= since and entity_id is not null group by entity_id order by n desc, last desc limit 50) x), '[]'),
    'missed', coalesce((select jsonb_agg(x order by x.n desc, x.last desc) from (
        select lower(term) as term, count(*) as n, max(at) as last from public.search_log
        where at >= since and not found group by lower(term) order by n desc, last desc limit 50) x), '[]'));
end $$;
revoke all on function public.search_report(int) from public;
grant execute on function public.search_report(int) to authenticated;

select cron.schedule('delete-old-searches', '23 3 1 * *',
  $$delete from public.search_log where at < now() - interval '12 months'$$);
