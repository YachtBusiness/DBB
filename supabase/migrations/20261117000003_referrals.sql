-- 0.3.35: referrals, tied to points. Each member has a personal invite code (made the first time they ask for it).
-- An application made through an invite link is tied to the referrer when the applicant confirms their email.
-- When an editor accepts the application, the referrer earns the 'referral' reward (100 points to start), once per
-- person referred, and only if the referrer is still a member. Editor approval stays: referral is not a fast lane.
-- The owner can change reward amounts or switch rules off.
alter table public.members
  add column if not exists ref_code text unique check (ref_code is null or ref_code ~ '^[a-z0-9]{8}$'),
  add column if not exists referrer_id uuid references auth.users(id) on delete set null;

drop index if exists public.points_ledger_reward_once;
create unique index if not exists points_ledger_reward_once on public.points_ledger (user_id, ref) where reason in ('reward','referral');

insert into public.points_rules (key, points, label) values ('referral', 100, 'Referred a new member')
on conflict (key) do nothing;

-- the signed-in member's invite code and how it's done
create or replace function public.my_invite() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare me uuid := auth.uid(); c text; tries int := 0;
begin
  if not exists (select 1 from public.members where user_id = me and status = 'member') then return null; end if;
  select ref_code into c from public.members where user_id = me;
  while c is null and tries < 10 loop
    tries := tries + 1;
    c := lower(substr(translate(encode(extensions.gen_random_bytes(10), 'base64'), '+/=OoIl01', ''), 1, 8));
    if c !~ '^[a-z0-9]{8}$' or exists (select 1 from public.members where ref_code = c) then c := null; continue; end if;
    update public.members set ref_code = c where user_id = me;
  end loop;
  return jsonb_build_object(
    'code', c,
    'joined', (select count(*) from public.members where referrer_id = me and status = 'member'),
    'waiting', (select count(*) from public.members where referrer_id = me and status in ('unconfirmed','pending')),
    'points', coalesce((select sum(delta) from public.points_ledger where user_id = me and reason = 'referral'), 0));
end $$;
revoke all on function public.my_invite() from public, anon;
grant execute on function public.my_invite() to authenticated;

-- who an invite code belongs to, for "You were invited by ..." on the Apply form (codes are shared on purpose)
create or replace function public.invite_name(p_code text) returns text
language sql stable security definer set search_path = '' as $$
  select name from public.members where ref_code = lower(btrim(p_code)) and status = 'member';
$$;
revoke all on function public.invite_name(text) from public;
grant execute on function public.invite_name(text) to anon, authenticated;

-- an applicant ties their own application to a referrer, once, before it's decided
create or replace function public.set_referrer(p_code text) returns text
language plpgsql security definer set search_path = '' as $$
declare me uuid := auth.uid(); r record;
begin
  select user_id, name into r from public.members where ref_code = lower(btrim(p_code)) and status = 'member';
  if not found or r.user_id = me then return null; end if;
  update public.members set referrer_id = r.user_id
   where user_id = me and status in ('unconfirmed','pending') and referrer_id is null;
  if not found then return null; end if;
  return r.name;
end $$;
revoke all on function public.set_referrer(text) from public, anon;
grant execute on function public.set_referrer(text) to authenticated;

-- pay the referrer when the referred application is accepted
create or replace function public.members_referral_reward() returns trigger
language plpgsql security definer set search_path = '' as $$
declare pts int; lbl text;
begin
  if new.status = 'member' and coalesce(old.status, '') <> 'member' and new.referrer_id is not null
     and exists (select 1 from public.members where user_id = new.referrer_id and status = 'member') then
    select points, label into pts, lbl from public.points_rules where key = 'referral' and active;
    if found then
      insert into public.points_ledger (user_id, delta, reason, note, ref, created_by)
      values (new.referrer_id, pts, 'referral', lbl || ': ' || left(new.name, 120), 'referral:' || new.user_id::text, null)
      on conflict (user_id, ref) where reason in ('reward','referral') do nothing;
    end if;
  end if;
  return new;
end $$;
revoke all on function public.members_referral_reward() from public, anon, authenticated;
drop trigger if exists members_referral_reward on public.members;
create trigger members_referral_reward after update of status on public.members
  for each row execute function public.members_referral_reward();

-- the owner changes reward amounts or switches rules on and off
create or replace function public.set_points_rule(p_key text, p_points int, p_active boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_owner() then raise exception 'owner only'; end if;
  if p_points is null or p_points < 1 or p_points > 1000000 then raise exception 'bad_amount'; end if;
  update public.points_rules set points = p_points, active = coalesce(p_active, active), updated_at = now() where key = p_key;
  if not found then raise exception 'no_rule'; end if;
end $$;
revoke all on function public.set_points_rule(text, int, boolean) from public, anon;
grant execute on function public.set_points_rule(text, int, boolean) to authenticated;

-- editors see all rules, including switched-off ones
drop policy if exists points_rules_read on public.points_rules;
create policy points_rules_read on public.points_rules for select to anon, authenticated using (active or (select public.is_editor()));

-- the Apply function ties a new application to its referrer when it's sent, so it doesn't matter which device the
-- applicant later confirms on (service role only)
create or replace function public.apply_set_referrer(p_user uuid, p_code text) returns void
language plpgsql security definer set search_path = '' as $$
declare r uuid;
begin
  select user_id into r from public.members where ref_code = lower(btrim(coalesce(p_code, ''))) and status = 'member';
  if r is null or r = p_user then return; end if;
  update public.members set referrer_id = r where user_id = p_user and status in ('unconfirmed','pending') and referrer_id is null;
end $$;
revoke all on function public.apply_set_referrer(uuid, text) from public, anon, authenticated;
grant execute on function public.apply_set_referrer(uuid, text) to service_role;
