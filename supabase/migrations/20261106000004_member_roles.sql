-- 0.3.3: member roles and member content.
-- Members add, edit and remove their own roles, and can add a team, club, organisation or event that
-- isn't in the book. Everything they add is marked origin = 'member' with who added it. Member links
-- always carry the source "Added by member": members never set a source, so they can't publish links.
-- Members' typed text (roles, names) may not contain web addresses, emails or handles.
-- Editors can edit or remove anything, and mark member content as editorial once checked.

alter table public.entities
  add column if not exists origin text not null default 'editorial' check (origin in ('editorial','member')),
  add column if not exists created_by uuid references auth.users(id) on delete set null,
  add column if not exists sector_note text not null default '' check (length(sector_note) <= 120);
alter table public.links
  add column if not exists origin text not null default 'editorial' check (origin in ('editorial','member')),
  add column if not exists created_by uuid references auth.users(id) on delete set null;
create index if not exists links_created_by_idx on public.links(created_by) where created_by is not null;
create index if not exists entities_created_by_idx on public.entities(created_by) where created_by is not null;

-- "other" joins the eleven sectors, for member-added organisations that fit none of them
alter table public.entities drop constraint if exists entities_sectors_check;
alter table public.entities add constraint entities_sectors_check check (sectors <@ array['sponsor','supplier','owner','media','agency',
  'organiser','governing body','class association','industry body','public body','nonprofit','other']);

-- text a member types must not carry a link
create or replace function public.member_text_ok(t text) returns boolean
language sql immutable set search_path = '' as $$
  select t !~* '(https?:|//|www\.|@|\m[a-z0-9-]+\.(com|net|org|io|co|biz|info|uk|ae|me|app|xyz|site|online|shop|ly|gg|tv|link)\M)';
$$;

create or replace function public.my_member_entity() returns text
language sql stable security definer set search_path = '' as $$
  select m.entity_id from public.members m join public.entities e on e.id = m.entity_id
  where m.user_id = (select auth.uid()) and m.status = 'member';
$$;

-- checks role, current/past and years; returns the tidied values
create or replace function public.clean_member_role(p jsonb) returns jsonb
language plpgsql immutable set search_path = '' as $$
declare role text := btrim(coalesce(p->>'role','')); cur boolean := coalesce((p->>'current')::boolean, true);
        since text := btrim(coalesce(p->>'since','')); until text := btrim(coalesce(p->>'until',''));
begin
  if length(role) not between 2 and 80 then raise exception 'role_name' using errcode = 'P0001'; end if;
  if not public.member_text_ok(role) then raise exception 'member_text_link' using errcode = 'P0001'; end if;
  if since <> '' and since !~ '^\d{4}$' then raise exception 'role_year' using errcode = 'P0001'; end if;
  if until <> '' and until !~ '^\d{4}$' then raise exception 'role_year' using errcode = 'P0001'; end if;
  if cur then until := ''; elsif until = '' then raise exception 'role_until' using errcode = 'P0001'; end if;
  if since <> '' and until <> '' and since > until then raise exception 'role_year' using errcode = 'P0001'; end if;
  return jsonb_build_object('role', role, 'since', since, 'until', until);
end $$;

-- add a role: to an entry in the book (to_id), or to a new team, club, organisation or event (new_entity)
create or replace function public.member_add_role(p jsonb) returns text
language plpgsql security definer set search_path = '' as $$
declare me uuid := (select auth.uid()); pid text := public.my_member_entity(); r jsonb; ne jsonb; tid text;
        nm text; ty text; sec text; base text; nid text; i int := 1; lid text;
begin
  if pid is null then raise exception 'not_member' using errcode = '42501'; end if;
  if (select count(*) from public.links where created_by = me and created_at > now() - interval '1 day') >= 20 then
    raise exception 'member_rate_limit' using errcode = 'P0001';
  end if;
  r := public.clean_member_role(p);
  ne := p->'new_entity';
  if ne is not null and jsonb_typeof(ne) = 'object' then
    if (select count(*) from public.entities where created_by = me and created_at > now() - interval '1 day') >= 10 then
      raise exception 'member_rate_limit' using errcode = 'P0001';
    end if;
    nm := btrim(coalesce(ne->>'name','')); ty := ne->>'type'; sec := nullif(btrim(coalesce(ne->>'sector','')), '');
    if length(nm) not between 2 and 120 then raise exception 'entity_name' using errcode = 'P0001'; end if;
    if not public.member_text_ok(nm) or not public.member_text_ok(coalesce(ne->>'sector_note','')) then
      raise exception 'member_text_link' using errcode = 'P0001';
    end if;
    if ty is null or ty not in ('team','club','org','event') then raise exception 'entity_type' using errcode = 'P0001'; end if;
    if exists (select 1 from public.entities where lower(name) = lower(nm) and status = 'curated') then
      raise exception 'entity_exists' using errcode = 'P0001';
    end if;
    base := btrim(regexp_replace(lower(nm), '[^a-z0-9]+', '-', 'g'), '-');
    base := left(coalesce(nullif(base, ''), 'entry'), 40);
    nid := base;
    while exists (select 1 from public.entities where id = nid) loop i := i + 1; nid := base || '-' || i; end loop;
    insert into public.entities (id, name, type, level, sectors, sector_note, country, origin, created_by)
    values (nid, nm, ty, case when ty = 'event' then 'event' end,
            case when ty = 'org' and sec is not null then array[sec] else '{}' end,
            case when ty = 'org' and sec = 'other' then btrim(coalesce(ne->>'sector_note','')) else '' end,
            case when upper(coalesce(ne->>'country','')) ~ '^[A-Z]{3}$' then upper(ne->>'country') else '' end,
            'member', me);
    tid := nid;
  else
    tid := btrim(coalesce(p->>'to_id',''));
    if not exists (select 1 from public.entities where id = tid and status = 'curated' and type in ('team','club','org','event')) then
      raise exception 'role_org' using errcode = 'P0001';
    end if;
  end if;
  if exists (select 1 from public.links where from_id = pid and to_id = tid and lower(btrim(role)) = lower(r->>'role')) then
    raise exception 'role_exists' using errcode = 'P0001';
  end if;
  insert into public.links (from_id, to_id, role, cat, start_date, end_date, source, origin, created_by)
  values (pid, tid, r->>'role', 'ppl', r->>'since', r->>'until', 'Added by member', 'member', me)
  returning id into lid;
  return lid;
end $$;

-- change a role the member added
create or replace function public.member_update_role(p_link text, p jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare pid text := public.my_member_entity(); r jsonb;
begin
  if pid is null then raise exception 'not_member' using errcode = '42501'; end if;
  if not exists (select 1 from public.links where id = p_link and from_id = pid and origin = 'member') then
    raise exception 'role_not_yours' using errcode = 'P0001';
  end if;
  r := public.clean_member_role(p);
  update public.links set role = r->>'role', start_date = r->>'since', end_date = r->>'until' where id = p_link;
end $$;

-- remove a role the member added; a team, club, organisation or event they added goes too if nothing else uses it
create or replace function public.member_remove_role(p_link text) returns void
language plpgsql security definer set search_path = '' as $$
declare me uuid := (select auth.uid()); pid text := public.my_member_entity(); tid text;
begin
  if pid is null then raise exception 'not_member' using errcode = '42501'; end if;
  delete from public.links where id = p_link and from_id = pid and origin = 'member' returning to_id into tid;
  if tid is null then raise exception 'role_not_yours' using errcode = 'P0001'; end if;
  delete from public.entities e where e.id = tid and e.origin = 'member' and e.created_by = me
    and not exists (select 1 from public.links l where l.from_id = e.id or l.to_id = e.id or l.context_id = e.id)
    and not exists (select 1 from public.features f where f.entity_id = e.id)
    and not exists (select 1 from public.members m where m.entity_id = e.id);
end $$;

revoke execute on function public.my_member_entity() from public, anon;
revoke execute on function public.clean_member_role(jsonb) from public, anon, authenticated;
revoke execute on function public.member_add_role(jsonb) from public, anon;
revoke execute on function public.member_update_role(text, jsonb) from public, anon;
revoke execute on function public.member_remove_role(text) from public, anon;
grant execute on function public.my_member_entity() to authenticated;
grant execute on function public.member_add_role(jsonb) to authenticated;
grant execute on function public.member_update_role(text, jsonb) to authenticated;
grant execute on function public.member_remove_role(text) to authenticated;
