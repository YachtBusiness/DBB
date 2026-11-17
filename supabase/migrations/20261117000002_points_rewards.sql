-- 0.3.33: the first earning rule. Rules live in points_rules (amounts can change without touching the app);
-- each reward is earned once per member, guaranteed by a unique index. First rule: 10 points for adding a profile photo,
-- given automatically by the database when a member's photo is saved, and backdated for members who already have one.
alter table public.points_ledger drop constraint if exists points_ledger_reason_check;
alter table public.points_ledger add constraint points_ledger_reason_check
  check (reason in ('award','deduct','correction','reward','referral','redeem','other'));
create unique index if not exists points_ledger_reward_once on public.points_ledger (user_id, ref) where reason = 'reward';

create table if not exists public.points_rules (
  key text primary key check (key ~ '^[a-z0-9_]+$'),
  points integer not null check (points > 0 and points <= 1000000),
  label text not null check (char_length(label) <= 120),
  active boolean not null default true,
  updated_at timestamptz not null default now()
);
alter table public.points_rules enable row level security;
revoke all on public.points_rules from anon, authenticated;
grant select on public.points_rules to anon, authenticated;
drop policy if exists points_rules_read on public.points_rules;
create policy points_rules_read on public.points_rules for select to anon, authenticated using (true);
insert into public.points_rules (key, points, label) values ('profile_photo', 10, 'Added a profile photo')
on conflict (key) do nothing;

-- give a reward once, if the rule is active and the person is an accepted member; returns points given (0 if none)
create or replace function public.points_reward(p_user uuid, p_key text) returns integer
language plpgsql security definer set search_path = '' as $$
declare r public.points_rules; n integer;
begin
  select * into r from public.points_rules where key = p_key and active;
  if not found then return 0; end if;
  if not exists (select 1 from public.members where user_id = p_user and status = 'member') then return 0; end if;
  insert into public.points_ledger (user_id, delta, reason, note, ref, created_by)
  values (p_user, r.points, 'reward', r.label, p_key, null)
  on conflict (user_id, ref) where reason = 'reward' do nothing;
  get diagnostics n = row_count;
  return case when n > 0 then r.points else 0 end;
end $$;
revoke all on function public.points_reward(uuid, text) from public, anon, authenticated;

create or replace function public.members_photo_reward() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.photo_path is not null and new.status = 'member' then perform public.points_reward(new.user_id, 'profile_photo'); end if;
  return new;
end $$;
revoke all on function public.members_photo_reward() from public, anon, authenticated;
drop trigger if exists members_photo_reward on public.members;
create trigger members_photo_reward after insert or update of photo_path, status on public.members
  for each row execute function public.members_photo_reward();

-- backdate: members who already have a photo
select public.points_reward(user_id, 'profile_photo') from public.members where status = 'member' and photo_path is not null;
