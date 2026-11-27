-- Communities: partner networks "powered by The Dark Blue Book" (27 Nov 2026, experimental: sandbox only until D signs it off).
-- A community has its own members, directory fields, visibility rules and branding, but its people and organisations
-- are ordinary book entities and links, so someone who is in both (e.g. Gabbi Richardson, Robobuoy) is one record
-- wearing several hats.
--
-- Walled garden: entities and links a community adds carry status 'community'. The book's public never sees them,
-- and neither do book editors (a partner's private members aren't the book's business). Communities read everything
-- through the security-definer functions below; the community tables themselves have RLS on and no policies.
--
-- Origin 'community' marks rows a community added (alongside 'editorial' and 'member').
-- Opt-in: a community member can choose to share their entry with The Dark Blue Book. Sharing turns a community-only
-- entry into a 'draft' book entry, which book editors review as usual; un-sharing turns it back (only for entries the
-- community created). Entries already in the book are never changed by a community.

-- 1. Book status: add 'community', and keep community rows out of the book (editors included)
alter table public.entities drop constraint entities_status_check;
alter table public.entities add constraint entities_status_check check (status in ('curated','draft','hidden','community'));
alter table public.links drop constraint links_status_check;
alter table public.links add constraint links_status_check check (status in ('curated','draft','hidden','community'));
alter table public.entities drop constraint entities_origin_check;
alter table public.entities add constraint entities_origin_check check (origin in ('editorial','member','community'));
alter table public.links drop constraint links_origin_check;
alter table public.links add constraint links_origin_check check (origin in ('editorial','member','community'));

drop policy "public reads curated entities" on public.entities;
create policy "public reads curated entities" on public.entities for select to anon, authenticated
  using (status = 'curated' or ((select public.is_editor()) and status <> 'community'));
drop policy "editors write entities" on public.entities;
create policy "editors write entities" on public.entities for all to authenticated
  using ((select public.is_editor()) and status <> 'community') with check ((select public.is_editor()) and status <> 'community');
drop policy "public reads curated links" on public.links;
create policy "public reads curated links" on public.links for select to anon, authenticated
  using (status = 'curated' or ((select public.is_editor()) and status <> 'community'));
drop policy "editors write links" on public.links;
create policy "editors write links" on public.links for all to authenticated
  using ((select public.is_editor()) and status <> 'community') with check ((select public.is_editor()) and status <> 'community');

-- 2. Community tables
create table public.communities (
  id text primary key check (id ~ '^[a-z0-9][a-z0-9-]*$'),
  name text not null,
  product text not null default 'Directory',          -- e.g. "Startup Directory"
  tagline text not null default '',
  about text not null default '',
  website text not null default '',
  join_url text not null default '',
  book_entity_id text references public.entities(id) on update cascade on delete set null,  -- the community's own entry in the book
  brand jsonb not null default '{}',                   -- colours, wordmark text
  created_at timestamptz not null default now()
);

create table public.community_members (
  community_id text not null references public.communities(id) on delete cascade,
  entity_id text not null references public.entities(id) on update cascade on delete cascade,
  kind text not null check (kind in ('startup','person')),
  listed boolean not null default true,
  featured boolean not null default false,
  share_with_book boolean not null default false,
  joined_at date not null default current_date,
  primary key (community_id, entity_id)
);

create table public.community_fields (
  community_id text not null references public.communities(id) on delete cascade,
  key text not null check (key ~ '^[a-z][a-z0-9_]*$'),
  label text not null,
  applies_to text not null default 'startup' check (applies_to in ('startup','person')),
  type text not null check (type in ('text','longtext','select','multi','year','url','bool')),
  options text[] not null default '{}',
  visibility text not null default 'public' check (visibility in ('public','members','investors','admins')),
  filter boolean not null default false,
  sample boolean not null default false,              -- demo values, not real data
  sort int not null default 0,
  primary key (community_id, key)
);

create table public.community_values (
  community_id text not null,
  entity_id text not null,
  key text not null,
  value jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (community_id, entity_id, key),
  foreign key (community_id, entity_id) references public.community_members(community_id, entity_id) on update cascade on delete cascade,
  foreign key (community_id, key) references public.community_fields(community_id, key) on delete cascade
);

create table public.community_users (
  community_id text not null references public.communities(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('member','investor','admin')),
  label text not null default '',                      -- how they're shown in the account menu
  manages text[] not null default '{}',                -- entries this account can edit and share
  primary key (community_id, user_id)
);

alter table public.communities enable row level security;
alter table public.community_members enable row level security;
alter table public.community_fields enable row level security;
alter table public.community_values enable row level security;
alter table public.community_users enable row level security;

-- 3. Who's looking: public 0, member 1, investor 2, admin 3. A field is shown when its rank is at or below the
--    viewer's, or when the viewer manages that entry (founders always see their own private fields).
create or replace function public.community_vis_rank(v text) returns int language sql immutable set search_path = '' as $$
  select case v when 'public' then 0 when 'members' then 1 when 'investors' then 2 when 'admins' then 3 else 9 end;
$$;

create or replace function public.community_me(p text) returns public.community_users
language sql stable security definer set search_path = '' as $$
  select u.* from public.community_users u where u.community_id = p and u.user_id = (select auth.uid());
$$;

-- 4. The directory: everything a viewer may see, in one call
create or replace function public.community_directory(p text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare me public.community_users; r int; mg text[];
begin
  if not exists (select 1 from public.communities where id = p) then raise exception 'no_community' using errcode = 'P0002'; end if;
  me := public.community_me(p);
  r := public.community_vis_rank(case coalesce(me.role,'') when 'admin' then 'admins' when 'investor' then 'investors' when 'member' then 'members' else 'public' end);
  mg := coalesce(me.manages, '{}');
  return jsonb_build_object(
    'community', (select to_jsonb(c) - 'created_at' from public.communities c where c.id = p),
    'viewer', jsonb_build_object('role', coalesce(me.role, 'public'), 'label', coalesce(me.label, ''), 'manages', to_jsonb(mg)),
    'fields', (select coalesce(jsonb_agg(jsonb_build_object('key',f.key,'label',f.label,'applies_to',f.applies_to,'type',f.type,'options',f.options,
                 'visibility',f.visibility,'filter',f.filter,'sample',f.sample,'open',public.community_vis_rank(f.visibility) <= r) order by f.sort), '[]')
               from public.community_fields f where f.community_id = p),
    'entries', (select coalesce(jsonb_agg(x order by x->>'kind' desc, x->>'name'), '[]') from (
      select jsonb_build_object(
        'id', e.id, 'name', e.name, 'kind', m.kind, 'country', e.country, 'website', e.website, 'linkedin', e.linkedin,
        'about', coalesce(nullif(e.about,''), e.note), 'featured', m.featured, 'shared', m.share_with_book,
        'in_book', e.status = 'curated', 'book_draft', e.status = 'draft', 'mine', e.id = any(mg), 'joined', m.joined_at,
        'values', (select coalesce(jsonb_object_agg(v.key, v.value), '{}') from public.community_values v
                   join public.community_fields f on f.community_id = v.community_id and f.key = v.key
                   where v.community_id = p and v.entity_id = e.id and (public.community_vis_rank(f.visibility) <= r or e.id = any(mg))),
        'people', (select coalesce(jsonb_agg(jsonb_build_object('id',pe.id,'name',pe.name,'role',l.role,'in_book',pe.status='curated') order by l.created_at), '[]')
                   from public.links l join public.entities pe on pe.id = l.from_id
                   join public.community_members pm on pm.community_id = p and pm.entity_id = pe.id and pm.listed
                   where l.to_id = e.id and l.cat = 'ppl' and l.status <> 'hidden'),
        'orgs', (select coalesce(jsonb_agg(jsonb_build_object('id',oe.id,'name',oe.name,'role',l.role) order by l.created_at), '[]')
                 from public.links l join public.entities oe on oe.id = l.to_id
                 join public.community_members om on om.community_id = p and om.entity_id = oe.id and om.listed
                 where l.from_id = e.id and l.cat = 'ppl' and l.status <> 'hidden')
      ) x
      from public.community_members m join public.entities e on e.id = m.entity_id
      where m.community_id = p and m.listed) s)
  );
end $$;

-- 5. "Also in The Dark Blue Book": an entry's public book roles (only for entries that are in the book)
create or replace function public.community_book_hats(p text, p_entity text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('role', l.role, 'other', o.name, 'other_id', o.id,
           'dir', case when l.from_id = p_entity then 'out' else 'in' end) order by o.name), '[]')
  from public.links l
  join public.entities o on o.id = case when l.from_id = p_entity then l.to_id else l.from_id end and o.status = 'curated'
  where (l.from_id = p_entity or l.to_id = p_entity) and l.status = 'curated'
    and exists (select 1 from public.community_members m join public.entities e on e.id = m.entity_id
                where m.community_id = p and m.entity_id = p_entity and m.listed and e.status = 'curated');
$$;

-- 6. Opt in to (or out of) The Dark Blue Book
create or replace function public.community_set_share(p text, p_entity text, p_share boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare me public.community_users; c public.communities; st text; org text;
begin
  me := public.community_me(p);
  if me.user_id is null or not (me.role = 'admin' or p_entity = any(me.manages)) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  select * into c from public.communities where id = p;
  update public.community_members set share_with_book = p_share where community_id = p and entity_id = p_entity;
  if not found then raise exception 'not_a_member' using errcode = 'P0002'; end if;
  select status, origin into st, org from public.entities where id = p_entity;
  if p_share and st = 'community' then
    -- into the book's editorial queue, with its membership of the community as its first role
    update public.entities set status = 'draft' where id = p_entity;
    if c.book_entity_id is not null then
      insert into public.links (id, from_id, to_id, role, cat, source, status, origin)
      values ('c-' || p || '-' || p_entity, p_entity, c.book_entity_id, 'Member', 'ppl', c.name || ' directory (opted in)', 'draft', 'community')
      on conflict (id) do update set status = 'draft';
    end if;
  elsif not p_share and st = 'draft' and org = 'community' then
    update public.entities set status = 'community' where id = p_entity;
    update public.links set status = 'community' where id = 'c-' || p || '-' || p_entity and status = 'draft';
  end if;
  return jsonb_build_object('shared', p_share, 'book_status', (select status from public.entities where id = p_entity));
end $$;

-- 7. Edit a directory field (admins, or the entry's own managers)
create or replace function public.community_save_value(p text, p_entity text, p_key text, p_value jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare me public.community_users;
begin
  me := public.community_me(p);
  if me.user_id is null or not (me.role = 'admin' or p_entity = any(me.manages)) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  if p_value is null or p_value = 'null'::jsonb or p_value = '""'::jsonb then
    delete from public.community_values where community_id = p and entity_id = p_entity and key = p_key;
  else
    insert into public.community_values (community_id, entity_id, key, value) values (p, p_entity, p_key, p_value)
    on conflict (community_id, entity_id, key) do update set value = excluded.value, updated_at = now();
  end if;
end $$;

revoke all on function public.community_me(text) from public, anon, authenticated;
revoke all on function public.community_vis_rank(text) from public, anon, authenticated;
revoke all on function public.community_set_share(text, text, boolean) from public, anon;
revoke all on function public.community_save_value(text, text, text, jsonb) from public, anon;
grant execute on function public.community_directory(text) to anon, authenticated;
grant execute on function public.community_book_hats(text, text) to anon, authenticated;
grant execute on function public.community_set_share(text, text, boolean) to authenticated;
grant execute on function public.community_save_value(text, text, text, jsonb) to authenticated;
