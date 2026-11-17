-- 0.4.0 (first part): job board, and the paid flag it depends on.
-- Decided 9 and 17 Nov 2026:
--   Who posts: owners and managers of an organisation who are paid members (editors can always post). Each job is for
--     that organisation. Up to 5 live jobs per organisation.
--   Who sees what: the public (and applicants not yet accepted) see a teaser: title, location, workplace, type and
--     date posted; no organisation, no salary. Accepted members who are signed in (free for now) also see the
--     organisation, salary, description and how to apply. Organisation entries show their open jobs to members only.
--   Applying happens elsewhere: each job has a link or email to apply at. No CVs here.
--   Expiry: 30 days (or the closing date, if sooner). A few days before, the poster gets an email with a one-click
--     link to keep it open another 30 days (remind Edge Function). Expired or closed jobs are deleted after 180 days.
--   No editor step: jobs go straight up; editors can edit or close any, and see new ones on the dashboard.
-- Everything goes through the functions below; the jobs table itself can't be read or written directly.
-- Switch for later: who sees the full ad is decided in one place, public.can_see_jobs().

-- ---------- paid flag ----------
alter table public.members add column if not exists tier text not null default 'free';
do $$ begin
  alter table public.members add constraint members_tier_check check (tier in ('free', 'paid'));
exception when duplicate_object then null; end $$;

create or replace function public.set_member_tier(p_user uuid, p_tier text) returns text
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_editor() then raise exception 'not_editor' using errcode = '42501'; end if;
  if p_tier not in ('free', 'paid') then raise exception 'bad_tier' using errcode = 'P0001'; end if;
  update public.members set tier = p_tier, updated_at = now() where user_id = p_user and status = 'member';
  if not found then raise exception 'not_member' using errcode = 'P0001'; end if;
  return p_tier;
end $$;

-- ---------- jobs ----------
create table if not exists public.jobs (
  id uuid primary key default gen_random_uuid(),
  entity_id text not null references public.entities (id) on delete cascade,
  posted_by uuid references public.members (user_id) on delete set null,
  title text not null check (length(btrim(title)) between 3 and 120),
  location text not null check (length(btrim(location)) between 2 and 120),
  workplace text not null default 'onsite' check (workplace in ('onsite', 'hybrid', 'remote')),
  job_type text not null check (job_type in ('full_time', 'part_time', 'contract', 'freelance', 'crew', 'internship')),
  salary text not null default '' check (length(salary) <= 120),
  description text not null check (length(btrim(description)) between 30 and 5000),
  apply_to text not null check (length(apply_to) <= 500 and (apply_to ~ '^https?://[^\s]+\.[^\s]+$' or apply_to ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$')),
  closes_on date,
  status text not null default 'live' check (status in ('live', 'expired', 'closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '30 days',
  notice_sent_at timestamptz,
  extend_token_hash text
);
create index if not exists jobs_entity on public.jobs (entity_id);
create index if not exists jobs_live on public.jobs (status, expires_at);
alter table public.jobs enable row level security;
revoke all on public.jobs from anon, authenticated;

-- Who sees full ads: accepted members and editors. Change here to make it paid-only later.
create or replace function public.can_see_jobs() returns boolean
language sql stable security definer set search_path = '' as $$
  select public.is_editor() or exists (select 1 from public.members where user_id = (select auth.uid()) and status = 'member');
$$;

-- Who can post or manage an organisation's jobs: editors, or its owners and managers who are paid members.
create or replace function public.can_post_jobs(p_entity text) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.is_editor() or exists (
    select 1 from public.org_roles r join public.members m on m.user_id = r.user_id
     where r.entity_id = p_entity and r.user_id = (select auth.uid()) and m.status = 'member' and m.tier = 'paid');
$$;

-- Public teaser: no organisation, no salary, no description, no way to apply.
create or replace function public.jobs_public() returns table (id uuid, title text, location text, workplace text, job_type text, posted_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select j.id, j.title, j.location, j.workplace, j.job_type, j.created_at from public.jobs j
   where j.status = 'live' and j.expires_at > now() order by j.created_at desc limit 500;
$$;

-- Full ads, for accepted members and editors. Editors also get who posted.
create or replace function public.jobs_full() returns table (id uuid, entity_id text, org_name text, title text, location text, workplace text,
  job_type text, salary text, description text, apply_to text, closes_on date, posted_at timestamptz, expires_at timestamptz, posted_by_name text)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.can_see_jobs() then raise exception 'members_only' using errcode = '42501'; end if;
  return query
  select j.id, j.entity_id, e.name, j.title, j.location, j.workplace, j.job_type, j.salary, j.description, j.apply_to, j.closes_on,
         j.created_at, j.expires_at, case when public.is_editor() then m.name else null end
    from public.jobs j join public.entities e on e.id = j.entity_id left join public.members m on m.user_id = j.posted_by
   where j.status = 'live' and j.expires_at > now() order by j.created_at desc limit 500;
end $$;

-- An organisation's jobs, live and past, for the people who can manage them.
create or replace function public.jobs_for_org(p_entity text) returns table (id uuid, title text, location text, workplace text, job_type text,
  salary text, description text, apply_to text, closes_on date, status text, posted_at timestamptz, expires_at timestamptz, posted_by_name text)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not (public.is_editor() or exists (select 1 from public.org_roles where entity_id = p_entity and user_id = (select auth.uid()))) then
    raise exception 'not_manager' using errcode = '42501';
  end if;
  return query
  select j.id, j.title, j.location, j.workplace, j.job_type, j.salary, j.description, j.apply_to, j.closes_on,
         case when j.status = 'live' and j.expires_at <= now() then 'expired' else j.status end, j.created_at, j.expires_at, m.name
    from public.jobs j left join public.members m on m.user_id = j.posted_by
   where j.entity_id = p_entity order by (j.status = 'live' and j.expires_at > now()) desc, j.created_at desc;
end $$;

create or replace function public.jobs_live_count(p_entity text) returns int
language sql stable security definer set search_path = '' as $$
  select count(*)::int from public.jobs where entity_id = p_entity and status = 'live' and expires_at > now();
$$;

-- Post (p_id null) or edit a job.
create or replace function public.job_save(p_id uuid, p_entity text, p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare me uuid := auth.uid(); ent text := p_entity; jid uuid; cl date; exp timestamptz;
  t text := btrim(coalesce(p->>'title', '')); loc text := btrim(coalesce(p->>'location', ''));
  wp text := coalesce(nullif(p->>'workplace', ''), 'onsite'); jt text := coalesce(p->>'job_type', '');
  sal text := btrim(coalesce(p->>'salary', '')); d text := btrim(coalesce(p->>'description', ''));
  ap text := btrim(coalesce(p->>'apply_to', ''));
begin
  if p_id is not null then
    select entity_id into ent from public.jobs where id = p_id;
    if ent is null then raise exception 'job_missing' using errcode = 'P0001'; end if;
  end if;
  if ent is null or not exists (select 1 from public.entities where id = ent and type = 'org') then raise exception 'job_org' using errcode = 'P0001'; end if;
  if not public.can_post_jobs(ent) then raise exception 'not_allowed' using errcode = '42501'; end if;
  if ap ~ '^www\.' then ap := 'https://' || ap; end if;
  if nullif(p->>'closes_on', '') is not null then
    begin cl := (p->>'closes_on')::date; exception when others then raise exception 'job_closes_on' using errcode = 'P0001'; end;
    if cl < current_date then raise exception 'job_closes_on' using errcode = 'P0001'; end if;
  end if;
  if p_id is null then
    if not public.is_editor() and (select count(*) from public.jobs where posted_by = me and created_at > now() - interval '1 day') >= 20 then
      raise exception 'job_rate_limit' using errcode = 'P0001';
    end if;
    if public.jobs_live_count(ent) >= 5 then raise exception 'job_limit' using errcode = 'P0001'; end if;
    exp := now() + interval '30 days';
    if cl is not null and cl + 1 < exp then exp := cl + 1; end if;
    insert into public.jobs (entity_id, posted_by, title, location, workplace, job_type, salary, description, apply_to, closes_on, expires_at)
    values (ent, (select user_id from public.members where user_id = me), t, loc, wp, jt, sal, d, ap, cl, exp) returning id into jid;  -- editors without a member row post as nobody
    return jid;
  end if;
  update public.jobs set title = t, location = loc, workplace = wp, job_type = jt, salary = sal, description = d, apply_to = ap,
    closes_on = cl, expires_at = case when cl is not null and cl + 1 < expires_at then cl + 1 else expires_at end, updated_at = now()
   where id = p_id;
  return p_id;
end $$;

-- Close a job early (filled, withdrawn).
create or replace function public.job_close(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare ent text;
begin
  select entity_id into ent from public.jobs where id = p_id;
  if ent is null then raise exception 'job_missing' using errcode = 'P0001'; end if;
  if not (public.is_editor() or exists (select 1 from public.org_roles where entity_id = ent and user_id = (select auth.uid()))) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  update public.jobs set status = 'closed', extend_token_hash = null, updated_at = now() where id = p_id;
end $$;

-- Keep a job open another 30 days (from now or from its current end, whichever is later; at most 60 days ahead).
create or replace function public.job_extend_internal(p_id uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare j record;
begin
  select * into j from public.jobs where id = p_id;
  if j.id is null then return 'missing'; end if;
  if j.status = 'closed' then return 'closed'; end if;
  if (j.status <> 'live' or j.expires_at <= now()) and public.jobs_live_count(j.entity_id) >= 5 then return 'limit'; end if;
  update public.jobs set status = 'live',
    expires_at = least(greatest(expires_at, now()) + interval '30 days', now() + interval '60 days'),
    closes_on = case when closes_on is not null and closes_on < current_date + 30 then null else closes_on end,
    notice_sent_at = null, extend_token_hash = null, updated_at = now()
   where id = p_id;
  return 'extended';
end $$;

create or replace function public.job_extend(p_id uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare ent text;
begin
  select entity_id into ent from public.jobs where id = p_id;
  if ent is null then raise exception 'job_missing' using errcode = 'P0001'; end if;
  if not public.can_post_jobs(ent) then raise exception 'not_allowed' using errcode = '42501'; end if;
  return public.job_extend_internal(p_id);
end $$;

-- The one-click link in the expiry email (app#job-extend=<token>); works without signing in, once.
create or replace function public.job_extend_by_token(p_token text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare jid uuid; r text; t text;
begin
  if p_token is null or length(p_token) < 40 or length(p_token) > 60 then return jsonb_build_object('result', 'invalid'); end if;
  select id, title into jid, t from public.jobs where extend_token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex');
  if jid is null then return jsonb_build_object('result', 'invalid'); end if;
  r := public.job_extend_internal(jid);
  return jsonb_build_object('result', r, 'title', t, 'until', (select expires_at from public.jobs where id = jid));
end $$;

-- ---------- expiry notices (remind Edge Function, service role) ----------
create or replace function public.jobs_due_notice() returns table (job_id uuid, title text, org_name text, expires_at timestamptz, email text, name text)
language sql stable security definer set search_path = '' as $$
  select j.id, j.title, e.name, j.expires_at, m.email, m.name from public.jobs j
    join public.entities e on e.id = j.entity_id join public.members m on m.user_id = j.posted_by
   where j.status = 'live' and j.notice_sent_at is null and j.expires_at > now() and j.expires_at < now() + interval '4 days'
     and m.status = 'member' and (exists (select 1 from public.org_roles r where r.entity_id = j.entity_id and r.user_id = j.posted_by)
                                  or exists (select 1 from public.editors ed where ed.user_id = j.posted_by))  -- still allowed to manage it
   order by j.expires_at limit 50;
$$;

create or replace function public.job_notice_token(p_job uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare t text;
begin
  t := translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/=', '-_');
  update public.jobs set extend_token_hash = encode(extensions.digest(t, 'sha256'), 'hex') where id = p_job and status = 'live';
  if not found then return null; end if;
  return t;
end $$;

create or replace function public.job_notice_sent(p_job uuid) returns void
language sql security definer set search_path = '' as $$
  update public.jobs set notice_sent_at = now() where id = p_job;
$$;

-- ---------- hourly housekeeping: applications (0.3.38) and jobs ----------
create or replace function public.applications_housekeeping() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare n_deleted int; n_due int; n_jobs int; n_exp int; sec text; fn text; req bigint;
begin
  n_deleted := public.stale_applications_delete();
  with x as (update public.jobs set status = 'expired', extend_token_hash = null, updated_at = now()
              where status = 'live' and expires_at <= now() - interval '7 days' returning 1)
  select count(*) into n_exp from x;  -- the extend link keeps working for a week after expiry
  delete from public.jobs where status in ('expired', 'closed') and updated_at < now() - interval '180 days';
  select count(*) into n_due from public.applications_due_reminder();
  select count(*) into n_jobs from public.jobs_due_notice();
  if n_due > 0 or n_jobs > 0 then
    select decrypted_secret into sec from vault.decrypted_secrets where name = 'remind_secret';
    select decrypted_secret into fn from vault.decrypted_secrets where name = 'remind_url';
    if sec is not null and fn is not null then
      req := net.http_post(url := fn,
        headers := jsonb_build_object('Content-Type', 'application/json', 'x-remind-secret', sec),
        body := '{}'::jsonb, timeout_milliseconds := 30000);
    end if;
  end if;
  return jsonb_build_object('deleted', n_deleted, 'due', n_due, 'jobs_due', n_jobs, 'jobs_expired', n_exp, 'called', req is not null);
end $$;

-- ---------- grants ----------
revoke execute on function public.set_member_tier(uuid, text) from public, anon;
grant execute on function public.set_member_tier(uuid, text) to authenticated;
revoke execute on function public.can_see_jobs() from public;
grant execute on function public.can_see_jobs() to anon, authenticated;
revoke execute on function public.can_post_jobs(text) from public, anon;
grant execute on function public.can_post_jobs(text) to authenticated;
revoke execute on function public.jobs_public() from public;
grant execute on function public.jobs_public() to anon, authenticated;
revoke execute on function public.jobs_full() from public, anon;
grant execute on function public.jobs_full() to authenticated;
revoke execute on function public.jobs_for_org(text) from public, anon;
grant execute on function public.jobs_for_org(text) to authenticated;
revoke execute on function public.jobs_live_count(text) from public, anon, authenticated;
revoke execute on function public.job_save(uuid, text, jsonb) from public, anon;
grant execute on function public.job_save(uuid, text, jsonb) to authenticated;
revoke execute on function public.job_close(uuid) from public, anon;
grant execute on function public.job_close(uuid) to authenticated;
revoke execute on function public.job_extend_internal(uuid) from public, anon, authenticated;
revoke execute on function public.job_extend(uuid) from public, anon;
grant execute on function public.job_extend(uuid) to authenticated;
revoke execute on function public.job_extend_by_token(text) from public;
grant execute on function public.job_extend_by_token(text) to anon, authenticated;
revoke execute on function public.jobs_due_notice() from public, anon, authenticated;
revoke execute on function public.job_notice_token(uuid) from public, anon, authenticated;
revoke execute on function public.job_notice_sent(uuid) from public, anon, authenticated;
grant execute on function public.jobs_due_notice() to service_role;
grant execute on function public.job_notice_token(uuid) to service_role;
grant execute on function public.job_notice_sent(uuid) to service_role;
