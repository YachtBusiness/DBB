-- 0.3: applications and members.
-- One row per applicant or member, keyed to their sign-in account. Status runs
-- unconfirmed (applied, email link not yet opened) -> pending (email confirmed, waiting for review) -> member.
-- Declining or withdrawing deletes the sign-in account, which deletes the row with it.
-- Nobody writes the table directly: applications arrive through the apply Edge Function (service role),
-- applicants edit and withdraw through RPCs, editors accept and decline through RPCs.

create table public.members (
  user_id uuid primary key references auth.users(id) on delete cascade,
  status text not null default 'unconfirmed' check (status in ('unconfirmed','pending','member')),
  name text not null check (length(btrim(name)) between 2 and 120),
  email text not null check (length(email) <= 200 and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  phone text not null default '' check (length(phone) <= 40),
  linkedin text not null default '' check (length(linkedin) <= 300),
  instagram text not null default '' check (length(instagram) <= 300),
  other_social text not null default '' check (length(other_social) <= 300),
  nationality text not null check (nationality ~ '^[A-Z]{3}$'),
  bio text not null default '' check (length(bio) <= 600),
  connection text not null default '' check (connection in ('','sailor','team','owner','sponsor','industry','events','club','media','other')),
  connection_detail text not null default '' check (length(connection_detail) <= 300),
  worked_with text not null default '' check (length(worked_with) <= 500),
  referred_by text not null default '' check (length(referred_by) <= 200),
  -- [{entity_id, other_name, role, current, since, until}], checked by public.clean_application_roles
  roles jsonb not null default '[]' check (jsonb_typeof(roles) = 'array' and jsonb_array_length(roles) between 1 and 10),
  claim_entity_id text references public.entities(id) on update cascade on delete set null,
  entity_id text unique references public.entities(id) on update cascade on delete set null,
  applied_at timestamptz not null default now(),
  confirmed_at timestamptz,
  accepted_at timestamptz,
  accepted_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);
create index members_status_idx on public.members(status, applied_at desc);

-- Editor-only notes on an application or member ("WhatsApp'd 6 Nov, confirmed he's at Luna Rossa").
create table public.member_notes (
  user_id uuid primary key references public.members(user_id) on delete cascade,
  note text not null default '' check (length(note) <= 2000),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid() references auth.users(id) on delete set null
);

alter table public.members enable row level security;
alter table public.member_notes enable row level security;

create policy "members read own row, editors read all" on public.members for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_editor()));
create policy "editors manage notes" on public.member_notes for all to authenticated
  using ((select public.is_editor())) with check ((select public.is_editor()));

revoke all on public.members from anon, authenticated;
revoke all on public.member_notes from anon, authenticated;
grant select on public.members to authenticated;
grant select, insert, update, delete on public.member_notes to authenticated;

-- ---------- validation ----------

-- Checks and tidies the roles on an application. Each role names an organisation in the book
-- (a team, club, organisation or event) or gives a name for one that isn't listed.
create or replace function public.clean_application_roles(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare r jsonb; out jsonb := '[]'; eid text; other text; role text; cur boolean; since text; until text;
begin
  if p is null or jsonb_typeof(p) <> 'array' or jsonb_array_length(p) = 0 then
    raise exception 'application_roles_missing' using errcode = 'P0001';
  end if;
  if jsonb_array_length(p) > 10 then raise exception 'application_roles_too_many' using errcode = 'P0001'; end if;
  for r in select * from jsonb_array_elements(p) loop
    eid := nullif(btrim(coalesce(r->>'entity_id','')), '');
    other := btrim(coalesce(r->>'other_name',''));
    role := btrim(coalesce(r->>'role',''));
    cur := coalesce((r->>'current')::boolean, true);
    since := btrim(coalesce(r->>'since',''));
    until := btrim(coalesce(r->>'until',''));
    if length(role) not between 2 and 80 then raise exception 'application_role_name' using errcode = 'P0001'; end if;
    if eid is not null then
      if not exists (select 1 from public.entities e where e.id = eid and e.status = 'curated'
                     and e.type in ('team','club','org','event')) then
        raise exception 'application_role_org' using errcode = 'P0001';
      end if;
      other := '';
    elsif length(other) not between 2 and 120 then
      raise exception 'application_role_org' using errcode = 'P0001';
    end if;
    if since <> '' and since !~ '^\d{4}$' then raise exception 'application_role_year' using errcode = 'P0001'; end if;
    if until <> '' and until !~ '^\d{4}$' then raise exception 'application_role_year' using errcode = 'P0001'; end if;
    if cur then until := ''; elsif until = '' then raise exception 'application_role_until' using errcode = 'P0001'; end if;
    if since <> '' and until <> '' and since > until then raise exception 'application_role_year' using errcode = 'P0001'; end if;
    out := out || jsonb_build_array(jsonb_build_object('entity_id', eid, 'other_name', other, 'role', role,
             'current', cur, 'since', since, 'until', until));
  end loop;
  return out;
end $$;

-- The fields an applicant fills in, tidied. Used for new applications and for edits while pending.
create or replace function public.clean_application(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare claim text := nullif(btrim(coalesce(p->>'claim_entity_id','')), '');
begin
  if claim is not null and not exists (select 1 from public.entities e where e.id = claim and e.type = 'person') then
    claim := null;
  end if;
  if claim is not null and exists (select 1 from public.members m where m.entity_id = claim) then
    claim := null;
  end if;
  return jsonb_build_object(
    'name', btrim(coalesce(p->>'name','')),
    'phone', btrim(coalesce(p->>'phone','')),
    'linkedin', btrim(coalesce(p->>'linkedin','')),
    'instagram', btrim(coalesce(p->>'instagram','')),
    'other_social', btrim(coalesce(p->>'other_social','')),
    'nationality', upper(btrim(coalesce(p->>'nationality',''))),
    'bio', btrim(coalesce(p->>'bio','')),
    'connection', btrim(coalesce(p->>'connection','')),
    'connection_detail', btrim(coalesce(p->>'connection_detail','')),
    'worked_with', btrim(coalesce(p->>'worked_with','')),
    'referred_by', btrim(coalesce(p->>'referred_by','')),
    'roles', public.clean_application_roles(p->'roles'),
    'claim_entity_id', claim);
end $$;

-- ---------- apply (called by the apply Edge Function with the service role) ----------

-- Who already has an account or application under this email.
create or replace function public.apply_lookup(p_email text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('user_id', u.id, 'status', m.status)
  from auth.users u left join public.members m on m.user_id = u.id
  where lower(u.email) = lower(btrim(p_email)) limit 1;
$$;

-- Stores a new application (or replaces an unconfirmed one) for an existing sign-in account.
create or replace function public.submit_application(p_user uuid, p jsonb) returns text
language plpgsql security definer set search_path = '' as $$
declare c jsonb; em text; st text;
begin
  -- tidy up: applications never confirmed within a week are dropped with their accounts
  delete from auth.users u using public.members m
   where m.user_id = u.id and m.status = 'unconfirmed' and m.applied_at < now() - interval '7 days'
     and not exists (select 1 from public.editors e where e.user_id = u.id);
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
    claim_entity_id = excluded.claim_entity_id, applied_at = now(), updated_at = now();
  return 'unconfirmed';
end $$;

-- ---------- applicant ----------

-- Opening the emailed link signs the applicant in; the app then calls this to confirm the email.
create or replace function public.confirm_application() returns text
language plpgsql security definer set search_path = '' as $$
declare st text;
begin
  update public.members set status = 'pending', confirmed_at = now(), updated_at = now()
   where user_id = (select auth.uid()) and status = 'unconfirmed';
  select status into st from public.members where user_id = (select auth.uid());
  return st;
end $$;

-- Applicants can change their application until it has been decided.
create or replace function public.update_application(p jsonb) returns text
language plpgsql security definer set search_path = '' as $$
declare c jsonb; st text;
begin
  select status into st from public.members where user_id = (select auth.uid());
  if st is null then raise exception 'application_missing' using errcode = 'P0001'; end if;
  if st = 'member' then raise exception 'application_decided' using errcode = 'P0001'; end if;
  c := public.clean_application(p);
  update public.members set name = c->>'name', phone = c->>'phone', linkedin = c->>'linkedin', instagram = c->>'instagram',
    other_social = c->>'other_social', nationality = c->>'nationality', bio = c->>'bio', connection = c->>'connection',
    connection_detail = c->>'connection_detail', worked_with = c->>'worked_with', referred_by = c->>'referred_by',
    roles = c->'roles', claim_entity_id = c->>'claim_entity_id', updated_at = now()
   where user_id = (select auth.uid());
  return st;
end $$;

-- Withdrawing deletes the application and the sign-in account with it.
create or replace function public.withdraw_application() returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.members where user_id = (select auth.uid()) and status in ('unconfirmed','pending')) then
    raise exception 'application_missing' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.editors where user_id = (select auth.uid())) then
    delete from public.members where user_id = (select auth.uid());
  else
    delete from auth.users where id = (select auth.uid());
  end if;
end $$;

-- ---------- editors ----------

-- Declining deletes the application and its sign-in account. No email is sent.
create or replace function public.decline_application(p_user uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_editor() then raise exception 'not_editor' using errcode = '42501'; end if;
  if not exists (select 1 from public.members where user_id = p_user and status in ('unconfirmed','pending')) then
    raise exception 'application_missing' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.editors where user_id = p_user) then
    delete from public.members where user_id = p_user;
  else
    delete from auth.users where id = p_user;
  end if;
end $$;

-- Accepting puts the member on the map in one step: their person entry (new, or the one they claimed),
-- any organisations that weren't listed, and a link for each role.
-- p_plan: {person_id, new_person: bool, roles: [{to_id, new_entity: {id,name,type,level,sectors,country} | null,
--          role, cat, current, since, until}]}
create or replace function public.accept_application(p_user uuid, p_plan jsonb) returns text
language plpgsql security definer set search_path = '' as $$
declare m public.members; pid text; r jsonb; ne jsonb; tid text; n int := 0;
begin
  if not public.is_editor() then raise exception 'not_editor' using errcode = '42501'; end if;
  select * into m from public.members where user_id = p_user for update;
  if m.user_id is null or m.status <> 'pending' then raise exception 'application_not_pending' using errcode = 'P0001'; end if;
  pid := btrim(coalesce(p_plan->>'person_id',''));
  if coalesce((p_plan->>'new_person')::boolean, false) then
    insert into public.entities (id, name, type, country) values (pid, m.name, 'person', m.nationality);
  elsif not exists (select 1 from public.entities where id = pid and type = 'person') then
    raise exception 'accept_person_missing' using errcode = 'P0001';
  elsif exists (select 1 from public.members where entity_id = pid) then
    raise exception 'accept_person_taken' using errcode = 'P0001';
  end if;
  for r in select * from jsonb_array_elements(coalesce(p_plan->'roles','[]')) loop
    ne := r->'new_entity';
    if ne is not null and jsonb_typeof(ne) = 'object' then
      insert into public.entities (id, name, type, level, sectors, country)
      values (ne->>'id', btrim(ne->>'name'), ne->>'type',
              case when ne->>'type' = 'event' then coalesce(nullif(ne->>'level',''),'event') end,
              case when ne->>'type' = 'org' then coalesce((select array_agg(x) from jsonb_array_elements_text(ne->'sectors') x), '{}') else '{}' end,
              coalesce(ne->>'country',''))
      returning id into tid;
    else
      tid := r->>'to_id';
    end if;
    insert into public.links (from_id, to_id, role, cat, start_date, end_date, source)
    values (pid, tid, btrim(r->>'role'), coalesce(nullif(r->>'cat',''),'ppl'), coalesce(r->>'since',''),
            case when coalesce((r->>'current')::boolean, true) then '' else coalesce(r->>'until','') end,
            'Member application, ' || to_char(m.applied_at, 'FMDD Mon YYYY'));
    n := n + 1;
  end loop;
  if n = 0 and not exists (select 1 from public.links where from_id = pid or to_id = pid) then
    raise exception 'accept_needs_role' using errcode = 'P0001';
  end if;
  update public.members set status = 'member', entity_id = pid, accepted_at = now(),
         accepted_by = (select auth.uid()), updated_at = now() where user_id = p_user;
  return pid;
end $$;

-- ---------- permissions ----------
revoke execute on function public.clean_application_roles(jsonb) from public, anon, authenticated;
revoke execute on function public.clean_application(jsonb) from public, anon, authenticated;
revoke execute on function public.apply_lookup(text) from public, anon, authenticated;
revoke execute on function public.submit_application(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.apply_lookup(text) to service_role;
grant execute on function public.submit_application(uuid, jsonb) to service_role;
revoke execute on function public.confirm_application() from public, anon;
revoke execute on function public.update_application(jsonb) from public, anon;
revoke execute on function public.withdraw_application() from public, anon;
revoke execute on function public.decline_application(uuid) from public, anon;
revoke execute on function public.accept_application(uuid, jsonb) from public, anon;
grant execute on function public.confirm_application() to authenticated;
grant execute on function public.update_application(jsonb) to authenticated;
grant execute on function public.withdraw_application() to authenticated;
grant execute on function public.decline_application(uuid) to authenticated;
grant execute on function public.accept_application(uuid, jsonb) to authenticated;
