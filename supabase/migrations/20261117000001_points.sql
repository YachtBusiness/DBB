-- 0.3.32: rewards points, the basic mechanism. No monetary value; what points are for, how they're earned and how
-- they're redeemed are decided later. A ledger: each change is a row, the balance is the sum, rows are never edited or
-- deleted (mistakes get a correcting entry). Only signed-in members have points. Points go with the account.
create table if not exists public.points_ledger (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  delta integer not null check (delta <> 0 and abs(delta) <= 1000000),
  reason text not null check (reason in ('award','deduct','correction','referral','redeem','other')),
  note text not null default '' check (char_length(note) <= 200),
  ref text not null default '' check (char_length(ref) <= 120),
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid()
);
create index if not exists points_ledger_user on public.points_ledger (user_id, created_at desc);
create index if not exists points_ledger_at on public.points_ledger (created_at desc);
alter table public.points_ledger enable row level security;
revoke all on public.points_ledger from anon, authenticated;
grant select on public.points_ledger to authenticated;
drop policy if exists points_read on public.points_ledger;
create policy points_read on public.points_ledger for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_editor()));
-- no insert, update or delete policies: rows are only written through the functions below

-- the signed-in member's balance and latest 50 entries
create or replace function public.my_points() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'balance', coalesce((select sum(delta) from public.points_ledger where user_id = auth.uid()), 0),
    'history', coalesce((select jsonb_agg(x order by x.created_at desc) from (
        select delta, reason, note, created_at from public.points_ledger where user_id = auth.uid()
        order by created_at desc limit 50) x), '[]'));
$$;
revoke all on function public.my_points() from public, anon;
grant execute on function public.my_points() to authenticated;

-- a member's balance and history, for editors
create or replace function public.member_points(p_user uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_editor() then raise exception 'editors only'; end if;
  return jsonb_build_object(
    'balance', coalesce((select sum(delta) from public.points_ledger where user_id = p_user), 0),
    'history', coalesce((select jsonb_agg(x order by x.created_at desc) from (
        select delta, reason, note, created_at from public.points_ledger where user_id = p_user
        order by created_at desc limit 50) x), '[]'));
end $$;
revoke all on function public.member_points(uuid) from public, anon;
grant execute on function public.member_points(uuid) to authenticated;

-- editors award or deduct points with a reason; the balance can't go below zero. Returns the new balance.
-- Earning rules (referrals) and redemption will add their own checked functions writing to the same ledger.
create or replace function public.points_adjust(p_user uuid, p_delta integer, p_note text) returns integer
language plpgsql security definer set search_path = '' as $$
declare bal integer; n text := btrim(coalesce(p_note, ''));
begin
  if not public.is_editor() then raise exception 'editors only'; end if;
  if p_delta is null or p_delta = 0 or abs(p_delta) > 1000000 then raise exception 'bad_amount'; end if;
  if n = '' then raise exception 'reason_required'; end if;
  if not exists (select 1 from public.members where user_id = p_user and status = 'member') then raise exception 'not_member'; end if;
  perform pg_advisory_xact_lock(hashtext('points:' || p_user::text));
  select coalesce(sum(delta), 0) into bal from public.points_ledger where user_id = p_user;
  if bal + p_delta < 0 then raise exception 'below_zero'; end if;
  insert into public.points_ledger (user_id, delta, reason, note) values (p_user, p_delta, case when p_delta > 0 then 'award' else 'deduct' end, left(n, 200));
  return bal + p_delta;
end $$;
revoke all on function public.points_adjust(uuid, integer, text) from public, anon;
grant execute on function public.points_adjust(uuid, integer, text) to authenticated;

-- recent points activity across members, for the editor dashboard
create or replace function public.points_recent(p_limit int default 50) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_editor() then raise exception 'editors only'; end if;
  return coalesce((select jsonb_agg(x order by x.created_at desc) from (
    select p.delta, p.reason, p.note, p.created_at, m.name, m.entity_id
    from public.points_ledger p left join public.members m on m.user_id = p.user_id
    order by p.created_at desc limit greatest(1, least(coalesce(p_limit, 50), 200))) x), '[]');
end $$;
revoke all on function public.points_recent(int) from public, anon;
grant execute on function public.points_recent(int) to authenticated;
