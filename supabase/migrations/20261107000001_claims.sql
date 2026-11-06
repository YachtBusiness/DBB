-- 0.3.5: claims, owners and managers for organisation profiles.
-- A member with a filled-in profile claims an organisation; editors approve (as owner or manager) or decline.
-- Owners invite and remove managers; an invitation takes effect when the invited member accepts.
-- Owners and managers edit the organisation's profile (free until paid tiers in 0.4). Editors have the final say:
-- they can do anything an owner can, change roles and remove anyone. Who manages a profile is not shown publicly.

create table public.org_roles (
  entity_id text not null references public.entities(id) on update cascade on delete cascade,
  user_id uuid not null references public.members(user_id) on delete cascade,
  role text not null check (role in ('owner','manager')),
  added_by uuid references auth.users(id) on delete set null,
  added_at timestamptz not null default now(),
  primary key (entity_id, user_id)
);
create table public.claims (
  id uuid primary key default gen_random_uuid(),
  entity_id text not null references public.entities(id) on update cascade on delete cascade,
  user_id uuid not null references public.members(user_id) on delete cascade,
  connection text not null check (connection in ('staff','owner','agency','other')),
  detail text not null check (length(btrim(detail)) between 2 and 500),
  evidence text not null default '' check (length(evidence) <= 500),
  created_at timestamptz not null default now(),
  unique (entity_id, user_id)
);
create table public.org_invites (
  entity_id text not null references public.entities(id) on update cascade on delete cascade,
  user_id uuid not null references public.members(user_id) on delete cascade,
  invited_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (entity_id, user_id)
);
create index org_roles_user_idx on public.org_roles(user_id);
create index org_invites_user_idx on public.org_invites(user_id);

alter table public.org_roles enable row level security;
alter table public.claims enable row level security;
alter table public.org_invites enable row level security;
-- reads: your own rows; editors read everything. Writes only through the functions below.
create policy "own or editor" on public.org_roles for select to authenticated using (user_id = (select auth.uid()) or (select public.is_editor()));
create policy "own or editor" on public.claims for select to authenticated using (user_id = (select auth.uid()) or (select public.is_editor()));
create policy "own or editor" on public.org_invites for select to authenticated using (user_id = (select auth.uid()) or (select public.is_editor()));
revoke all on public.org_roles, public.claims, public.org_invites from anon, authenticated;
grant select on public.org_roles, public.claims, public.org_invites to authenticated;

-- ---------- helpers ----------
create or replace function public.org_role_of(p_entity text) returns text
language sql stable security definer set search_path = '' as $$
  select role from public.org_roles where entity_id = p_entity and user_id = (select auth.uid());
$$;
create or replace function public.can_run_org(p_entity text) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.is_editor() or public.org_role_of(p_entity) = 'owner';
$$;
create or replace function public.can_edit_org(p_entity text) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.is_editor() or public.org_role_of(p_entity) in ('owner','manager');
$$;
-- what's still missing before a member can claim: photo, bio, a role
create or replace function public.claim_missing() returns text[]
language sql stable security definer set search_path = '' as $$
  select array_remove(array[
    case when m.photo_path is null then 'photo' end,
    case when btrim(m.bio) = '' then 'bio' end,
    case when not exists (select 1 from public.links l where l.from_id = m.entity_id or l.to_id = m.entity_id) then 'role' end
  ], null)
  from public.members m where m.user_id = (select auth.uid()) and m.status = 'member';
$$;

-- ---------- members ----------
create or replace function public.submit_claim(p_entity text, p jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare me uuid := (select auth.uid()); miss text[] := public.claim_missing();
begin
  if miss is null then raise exception 'not_member' using errcode = '42501'; end if;
  if array_length(miss, 1) > 0 then raise exception 'claim_profile_incomplete' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.entities where id = p_entity and type = 'org' and status = 'curated') then
    raise exception 'claim_not_org' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.org_roles where entity_id = p_entity and user_id = me) then raise exception 'claim_already' using errcode = 'P0001'; end if;
  if (select count(*) from public.claims where user_id = me and created_at > now() - interval '1 day') >= 5 then
    raise exception 'claim_rate_limit' using errcode = 'P0001';
  end if;
  insert into public.claims (entity_id, user_id, connection, detail, evidence)
  values (p_entity, me, coalesce(nullif(p->>'connection',''),'other'), btrim(coalesce(p->>'detail','')), btrim(coalesce(p->>'evidence','')))
  on conflict (entity_id, user_id) do update set connection = excluded.connection, detail = excluded.detail, evidence = excluded.evidence;
end $$;

create or replace function public.withdraw_claim(p_entity text) returns void
language sql security definer set search_path = '' as $$
  delete from public.claims where entity_id = p_entity and user_id = (select auth.uid());
$$;

create or replace function public.respond_invite(p_entity text, p_accept boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare me uuid := (select auth.uid()); inv public.org_invites;
begin
  delete from public.org_invites where entity_id = p_entity and user_id = me returning * into inv;
  if inv.user_id is null then raise exception 'invite_missing' using errcode = 'P0001'; end if;
  if p_accept then
    insert into public.org_roles (entity_id, user_id, role, added_by) values (p_entity, me, 'manager', inv.invited_by)
    on conflict (entity_id, user_id) do nothing;
    delete from public.claims where entity_id = p_entity and user_id = me;
  end if;
end $$;

-- the organisations you manage, your claims and your invitations
create or replace function public.my_orgs() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'roles', coalesce((select jsonb_agg(jsonb_build_object('entity_id', entity_id, 'role', role)) from public.org_roles where user_id = (select auth.uid())), '[]'),
    'claims', coalesce((select jsonb_agg(jsonb_build_object('entity_id', entity_id, 'created_at', created_at)) from public.claims where user_id = (select auth.uid())), '[]'),
    'invites', coalesce((select jsonb_agg(jsonb_build_object('entity_id', entity_id, 'created_at', created_at)) from public.org_invites where user_id = (select auth.uid())), '[]'),
    'missing', to_jsonb(coalesce(public.claim_missing(), array['member'])));
$$;

-- ---------- owners (and editors) ----------
-- the people behind an organisation's profile, for its owners and editors only
create or replace function public.org_people(p_entity text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.can_run_org(p_entity) then raise exception 'not_owner' using errcode = '42501'; end if;
  return jsonb_build_object(
    'people', coalesce((select jsonb_agg(jsonb_build_object('user_id', r.user_id, 'name', m.name, 'entity_id', m.entity_id, 'role', r.role) order by r.role desc, m.name)
               from public.org_roles r join public.members m on m.user_id = r.user_id where r.entity_id = p_entity), '[]'),
    'invites', coalesce((select jsonb_agg(jsonb_build_object('user_id', i.user_id, 'name', m.name, 'created_at', i.created_at))
               from public.org_invites i join public.members m on m.user_id = i.user_id where i.entity_id = p_entity), '[]'));
end $$;

-- invite a member to manage the profile, by their sign-in email. Called only by the notify Edge Function
-- (service role), which checks who's asking (p_by), sends the invitation email and gives the owner the same
-- answer whether or not the email belongs to a member, so owners can't use it to find out who's a member.
create or replace function public.invite_manager(p_entity text, p_email text, p_by uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare target uuid; em text; nm text;
begin
  if not (exists (select 1 from public.editors where user_id = p_by)
          or exists (select 1 from public.org_roles where entity_id = p_entity and user_id = p_by and role = 'owner')) then
    raise exception 'not_owner' using errcode = '42501';
  end if;
  if (select count(*) from public.org_invites where invited_by = p_by and created_at > now() - interval '1 day') >= 10 then
    raise exception 'invite_rate_limit' using errcode = 'P0001';
  end if;
  select m.user_id, u.email, m.name into target, em, nm from public.members m join auth.users u on u.id = m.user_id
   where lower(u.email) = lower(btrim(p_email)) and m.status = 'member';
  if target is null or exists (select 1 from public.org_roles where entity_id = p_entity and user_id = target)
     or exists (select 1 from public.org_invites where entity_id = p_entity and user_id = target) then
    return null;
  end if;
  insert into public.org_invites (entity_id, user_id, invited_by) values (p_entity, target, p_by);
  return jsonb_build_object('email', em, 'name', nm, 'org', (select name from public.entities where id = p_entity),
    'by', (select name from public.members where user_id = p_by));
end $$;

create or replace function public.cancel_invite(p_entity text, p_user uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.can_run_org(p_entity) then raise exception 'not_owner' using errcode = '42501'; end if;
  delete from public.org_invites where entity_id = p_entity and user_id = p_user;
end $$;

-- owners remove managers; editors remove anyone; anyone can step down themselves
create or replace function public.remove_org_role(p_entity text, p_user uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare r text;
begin
  select role into r from public.org_roles where entity_id = p_entity and user_id = p_user;
  if r is null then raise exception 'role_missing' using errcode = 'P0001'; end if;
  if not (public.is_editor() or p_user = (select auth.uid()) or (public.org_role_of(p_entity) = 'owner' and r = 'manager')) then
    raise exception 'not_owner' using errcode = '42501';
  end if;
  delete from public.org_roles where entity_id = p_entity and user_id = p_user;
end $$;

-- edit the profile: owners, managers and editors. Links are allowed: these are vetted people.
create or replace function public.update_org_profile(p_entity text, p jsonb) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.can_edit_org(p_entity) then raise exception 'not_manager' using errcode = '42501'; end if;
  if p ? 'logo_path' and nullif(p->>'logo_path','') is not null and split_part(p->>'logo_path', '/', 1) <> p_entity then
    raise exception 'logo_path' using errcode = 'P0001';
  end if;
  update public.entities set
    about = case when p ? 'about' then btrim(p->>'about') else about end,
    website = case when p ? 'website' then btrim(p->>'website') else website end,
    linkedin = case when p ? 'linkedin' then btrim(p->>'linkedin') else linkedin end,
    instagram = case when p ? 'instagram' then btrim(p->>'instagram') else instagram end,
    other_social = case when p ? 'other_social' then btrim(p->>'other_social') else other_social end,
    contact_email = case when p ? 'contact_email' then lower(btrim(p->>'contact_email')) else contact_email end,
    logo_path = case when p ? 'logo_path' then nullif(p->>'logo_path','') else logo_path end,
    updated_at = now()
  where id = p_entity and type = 'org';
end $$;

-- ---------- editors ----------
-- approve as owner or manager, or decline (p_role null): declining deletes the claim, with no email
create or replace function public.decide_claim(p_claim uuid, p_role text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare c public.claims;
begin
  if not public.is_editor() then raise exception 'not_editor' using errcode = '42501'; end if;
  delete from public.claims where id = p_claim returning * into c;
  if c.id is null then raise exception 'claim_missing' using errcode = 'P0001'; end if;
  if p_role in ('owner','manager') then
    insert into public.org_roles (entity_id, user_id, role, added_by) values (c.entity_id, c.user_id, p_role, (select auth.uid()))
    on conflict (entity_id, user_id) do update set role = excluded.role;
    delete from public.org_invites where entity_id = c.entity_id and user_id = c.user_id;
  end if;
  return jsonb_build_object('entity_id', c.entity_id, 'user_id', c.user_id, 'role', p_role);
end $$;

create or replace function public.set_org_role(p_entity text, p_user uuid, p_role text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_editor() then raise exception 'not_editor' using errcode = '42501'; end if;
  if p_role not in ('owner','manager') then raise exception 'role_invalid' using errcode = 'P0001'; end if;
  update public.org_roles set role = p_role where entity_id = p_entity and user_id = p_user;
end $$;

-- ---------- logos: owners and managers may add or remove their organisation's logo ----------
create policy "org managers add logos" on storage.objects for insert to authenticated
  with check (bucket_id = 'logos' and (select public.can_edit_org((storage.foldername(name))[1])));
create policy "org managers remove logos" on storage.objects for delete to authenticated
  using (bucket_id = 'logos' and (select public.can_edit_org((storage.foldername(name))[1])));
create policy "org managers list logos" on storage.objects for select to authenticated
  using (bucket_id = 'logos' and (select public.can_edit_org((storage.foldername(name))[1])));

-- ---------- permissions ----------
do $$ declare f text; begin
  foreach f in array array['org_role_of(text)','can_run_org(text)','can_edit_org(text)','claim_missing()','submit_claim(text, jsonb)',
    'withdraw_claim(text)','respond_invite(text, boolean)','my_orgs()','org_people(text)','cancel_invite(text, uuid)',
    'remove_org_role(text, uuid)','update_org_profile(text, jsonb)','decide_claim(uuid, text)','set_org_role(text, uuid, text)'] loop
    execute format('revoke execute on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
revoke execute on function public.invite_manager(text, text, uuid) from public, anon, authenticated;
grant execute on function public.invite_manager(text, text, uuid) to service_role;
