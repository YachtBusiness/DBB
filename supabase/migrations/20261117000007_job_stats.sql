-- 0.4.0 (second part): views and Apply clicks on job ads, for the people who manage them.
-- Applications happen on the employer's site or by email, so the book never sees who applied. What it can count:
-- how many members opened an ad (a count only), and who clicked Apply now. Decided 17 Nov 2026: the hirer sees the list
-- of members who clicked Apply (name and their entry) as a trust signal; members are told under the button.
-- Once per member per ad; the organisation's own owners and managers and the editors aren't counted.

create table if not exists public.job_events (
  job_id uuid not null references public.jobs (id) on delete cascade,
  user_id uuid not null references public.members (user_id) on delete cascade,
  kind text not null check (kind in ('view', 'apply')),
  at timestamptz not null default now(),
  primary key (job_id, user_id, kind)
);
alter table public.job_events enable row level security;
revoke all on public.job_events from anon, authenticated;

create or replace function public.job_track(p_job uuid, p_kind text) returns void
language plpgsql security definer set search_path = '' as $$
declare me uuid := auth.uid(); ent text;
begin
  if me is null or p_kind not in ('view', 'apply') then return; end if;
  if not exists (select 1 from public.members where user_id = me and status = 'member') or public.is_editor() then return; end if;
  select entity_id into ent from public.jobs where id = p_job and status = 'live';
  if ent is null or exists (select 1 from public.org_roles where entity_id = ent and user_id = me) then return; end if;
  insert into public.job_events (job_id, user_id, kind) values (p_job, me, p_kind) on conflict do nothing;
end $$;

drop function if exists public.jobs_for_org(text);
create function public.jobs_for_org(p_entity text) returns table (id uuid, title text, location text, workplace text, job_type text,
  salary text, description text, apply_to text, closes_on date, status text, posted_at timestamptz, expires_at timestamptz, posted_by_name text,
  views int, applies int)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not (public.is_editor() or exists (select 1 from public.org_roles where entity_id = p_entity and user_id = (select auth.uid()))) then
    raise exception 'not_manager' using errcode = '42501';
  end if;
  return query
  select j.id, j.title, j.location, j.workplace, j.job_type, j.salary, j.description, j.apply_to, j.closes_on,
         case when j.status = 'live' and j.expires_at <= now() then 'expired' else j.status end, j.created_at, j.expires_at, m.name,
         (select count(*)::int from public.job_events v where v.job_id = j.id and v.kind = 'view'),
         (select count(*)::int from public.job_events a where a.job_id = j.id and a.kind = 'apply')
    from public.jobs j left join public.members m on m.user_id = j.posted_by
   where j.entity_id = p_entity order by (j.status = 'live' and j.expires_at > now()) desc, j.created_at desc;
end $$;

revoke execute on function public.job_track(uuid, text) from public, anon;
grant execute on function public.job_track(uuid, text) to authenticated;
revoke execute on function public.jobs_for_org(text) from public, anon;
grant execute on function public.jobs_for_org(text) to authenticated;

-- Who clicked Apply on an ad: for the organisation's owners and managers, and editors.
create or replace function public.job_applicants(p_job uuid) returns table (name text, entity_id text, clicked_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
declare ent text;
begin
  select j.entity_id into ent from public.jobs j where j.id = p_job;
  if ent is null then raise exception 'job_missing' using errcode = 'P0001'; end if;
  if not (public.is_editor() or exists (select 1 from public.org_roles where org_roles.entity_id = ent and user_id = (select auth.uid()))) then
    raise exception 'not_manager' using errcode = '42501';
  end if;
  return query
  select m.name, m.entity_id, ev.at from public.job_events ev join public.members m on m.user_id = ev.user_id
   where ev.job_id = p_job and ev.kind = 'apply' and m.status = 'member' order by ev.at desc;
end $$;
revoke execute on function public.job_applicants(uuid) from public, anon;
grant execute on function public.job_applicants(uuid) to authenticated;
