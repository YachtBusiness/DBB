-- 0.3.38: reminder email for unconfirmed applications, and clean-up that actually runs.
-- Before this, unconfirmed applications were only cleared when someone else applied, so they could sit for weeks.
-- Now an hourly job (pg_cron) clears them and, when anyone is due a reminder, calls the remind Edge Function.
--   Day 5 after applying, still unconfirmed: one reminder email with a fresh one-time link (remind Edge Function).
--   Day 7, and at least 2 days after the reminder: the application and its account are deleted.
--   Day 14: deleted whatever happened (backstop, e.g. if the reminder could never be sent).
-- Editors' own accounts are never deleted. Re-applying while unconfirmed starts the clock again.
-- Needs two Vault secrets per project (set outside this file): remind_url, the remind function's address
-- (https://<ref>.supabase.co/functions/v1/remind), and remind_secret, a random key the function checks callers against.

create extension if not exists pg_net;

alter table public.members add column if not exists reminder_sent_at timestamptz;

create or replace function public.stale_applications_delete() returns int
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  with gone as (
    delete from auth.users u using public.members m
     where m.user_id = u.id and m.status = 'unconfirmed'
       and not exists (select 1 from public.editors e where e.user_id = u.id)
       and ( (m.applied_at < now() - interval '7 days' and m.reminder_sent_at < now() - interval '47 hours')
          or m.applied_at < now() - interval '14 days')
    returning 1)
  select count(*) into n from gone;
  return n;
end $$;

-- Who is due a reminder: unconfirmed for 5 days, not reminded yet.
create or replace function public.applications_due_reminder() returns table (user_id uuid, name text, email text, applied_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select m.user_id, m.name, m.email, m.applied_at from public.members m
   where m.status = 'unconfirmed' and m.reminder_sent_at is null and m.applied_at < now() - interval '5 days'
     and not exists (select 1 from public.editors e where e.user_id = m.user_id)
   order by m.applied_at limit 50;
$$;

create or replace function public.application_reminded(p_user uuid) returns void
language sql security definer set search_path = '' as $$
  update public.members set reminder_sent_at = now() where user_id = p_user and status = 'unconfirmed';
$$;

-- Hourly: clear stale applications, then call the remind function only if someone is due.
create or replace function public.applications_housekeeping() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare n_deleted int; n_due int; sec text; fn text; req bigint;
begin
  n_deleted := public.stale_applications_delete();
  select count(*) into n_due from public.applications_due_reminder();
  if n_due > 0 then
    select decrypted_secret into sec from vault.decrypted_secrets where name = 'remind_secret';
    select decrypted_secret into fn from vault.decrypted_secrets where name = 'remind_url';
    if sec is not null and fn is not null then
      req := net.http_post(
        url := fn,
        headers := jsonb_build_object('Content-Type', 'application/json', 'x-remind-secret', sec),
        body := '{}'::jsonb, timeout_milliseconds := 30000);
    end if;
  end if;
  return jsonb_build_object('deleted', n_deleted, 'due', n_due, 'called', req is not null);
end $$;

-- The remind function checks the caller's key against Vault (so the function needs no secret of its own).
create or replace function public.remind_key_ok(p_key text) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(length(p_key) >= 32 and p_key = (select decrypted_secret from vault.decrypted_secrets where name = 'remind_secret'), false);
$$;

revoke execute on function public.remind_key_ok(text) from public, anon, authenticated;
grant execute on function public.remind_key_ok(text) to service_role;
revoke execute on function public.stale_applications_delete() from public, anon, authenticated;
revoke execute on function public.applications_due_reminder() from public, anon, authenticated;
revoke execute on function public.application_reminded(uuid) from public, anon, authenticated;
revoke execute on function public.applications_housekeeping() from public, anon, authenticated;
grant execute on function public.applications_due_reminder() to service_role;
grant execute on function public.application_reminded(uuid) to service_role;

-- submit_application: use the same clean-up rule, and re-applying while unconfirmed restarts the reminder clock.
create or replace function public.submit_application(p_user uuid, p jsonb) returns text
language plpgsql security definer set search_path = '' as $$
declare c jsonb; em text; st text;
begin
  perform public.stale_applications_delete();
  -- flood brake
  if (select count(*) from public.members where applied_at > now() - interval '1 hour') >= 40 then
    raise exception 'applications_rate_limit' using errcode = 'P0001';
  end if;
  select email into em from auth.users where id = p_user;
  if em is null then raise exception 'application_no_account' using errcode = 'P0001'; end if;
  select status into st from public.members where user_id = p_user;
  if st in ('pending','member') then raise exception 'application_exists' using errcode = 'P0001'; end if;
  c := public.clean_application(p);
  insert into public.members as m (user_id, status, name, email, phone, linkedin, instagram, other_social, nationality, bio,
    connection, connection_detail, worked_with, referred_by, roles, claim_entity_id, applied_at)
  values (p_user, 'unconfirmed', c->>'name', em, c->>'phone', c->>'linkedin', c->>'instagram', c->>'other_social',
    c->>'nationality', c->>'bio', c->>'connection', c->>'connection_detail', c->>'worked_with', c->>'referred_by',
    c->'roles', c->>'claim_entity_id', now())
  on conflict (user_id) do update set name = excluded.name, phone = excluded.phone, linkedin = excluded.linkedin,
    instagram = excluded.instagram, other_social = excluded.other_social, nationality = excluded.nationality,
    bio = excluded.bio, connection = excluded.connection, connection_detail = excluded.connection_detail,
    worked_with = excluded.worked_with, referred_by = excluded.referred_by, roles = excluded.roles,
    claim_entity_id = excluded.claim_entity_id, applied_at = now(), reminder_sent_at = null, updated_at = now();
  return 'unconfirmed';
end $$;

-- Then schedule, once per project:
--   select cron.schedule('application-housekeeping', '11 * * * *', 'select public.applications_housekeeping()');
