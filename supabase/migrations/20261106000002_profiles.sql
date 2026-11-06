-- 0.3.2: member profiles. Photo, bio and links, per-field visibility, the first-sign-in checklist,
-- a public view of each member's profile that honours their visibility choices, and the owner
-- promoting members to editor. Also the monthly clean-up of closed reports promised in the privacy notice.

alter table public.members
  add column if not exists photo_path text check (photo_path is null or photo_path ~ '^[0-9a-f-]{36}/[0-9]{10,16}\.jpg$'),
  add column if not exists contact_email text not null default '' check (contact_email = '' or (length(contact_email) <= 200 and contact_email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$')),
  add column if not exists show_photo boolean not null default true,
  add column if not exists show_linkedin boolean not null default true,
  add column if not exists show_social boolean not null default true,
  add column if not exists show_email boolean not null default false,
  add column if not exists show_phone boolean not null default false,
  -- first-sign-in checklist: {"visible": ts, "bio": ts, "map": ts, "dismissed": ts}; the photo item is done when photo_path is set
  add column if not exists checklist jsonb not null default '{}' check (jsonb_typeof(checklist) = 'object');

-- ---------- member edits their own profile ----------
create or replace function public.update_profile(p jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare me uuid := (select auth.uid()); ph text;
begin
  if not exists (select 1 from public.members where user_id = me and status = 'member') then
    raise exception 'not_member' using errcode = '42501';
  end if;
  if p ? 'photo_path' then
    ph := nullif(btrim(coalesce(p->>'photo_path','')), '');
    if ph is not null and split_part(ph, '/', 1) <> me::text then raise exception 'profile_photo_path' using errcode = 'P0001'; end if;
  end if;
  update public.members set
    bio = case when p ? 'bio' then btrim(p->>'bio') else bio end,
    linkedin = case when p ? 'linkedin' then btrim(p->>'linkedin') else linkedin end,
    instagram = case when p ? 'instagram' then btrim(p->>'instagram') else instagram end,
    other_social = case when p ? 'other_social' then btrim(p->>'other_social') else other_social end,
    phone = case when p ? 'phone' then btrim(p->>'phone') else phone end,
    contact_email = case when p ? 'contact_email' then lower(btrim(p->>'contact_email')) else contact_email end,
    show_photo = coalesce((p->>'show_photo')::boolean, show_photo),
    show_linkedin = coalesce((p->>'show_linkedin')::boolean, show_linkedin),
    show_social = coalesce((p->>'show_social')::boolean, show_social),
    show_email = coalesce((p->>'show_email')::boolean, show_email),
    show_phone = coalesce((p->>'show_phone')::boolean, show_phone),
    photo_path = case when p ? 'photo_path' then ph else photo_path end,
    checklist = case when jsonb_typeof(p->'checklist') = 'object'
                     then checklist || (select coalesce(jsonb_object_agg(k, to_jsonb(now())), '{}') from jsonb_object_keys(p->'checklist') k
                                        where k in ('visible','bio','map','dismissed'))
                     else checklist end,
    updated_at = now()
  where user_id = me;
end $$;

-- ---------- what everyone can see of members ----------
-- Name, nationality and roles are in the book already. Photo, bio and links follow each member's switches.
-- Contact email and phone are for paid members only, from 0.4; nobody sees them before then.
create or replace function public.public_profiles()
returns table (entity_id text, name text, nationality text, member_since timestamptz, photo_path text,
               bio text, linkedin text, instagram text, other_social text)
language sql stable security definer set search_path = '' as $$
  select m.entity_id, m.name, m.nationality, m.accepted_at,
         case when m.show_photo then m.photo_path end,
         m.bio,
         case when m.show_linkedin then m.linkedin else '' end,
         case when m.show_social then m.instagram else '' end,
         case when m.show_social then m.other_social else '' end
  from public.members m
  join public.entities e on e.id = m.entity_id and e.status = 'curated'
  where m.status = 'member';
$$;

-- ---------- the owner makes members editors ----------
create or replace function public.is_owner() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.editors e where e.user_id = (select auth.uid()) and e.role = 'owner');
$$;

create or replace function public.set_editor(p_user uuid, p_on boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_owner() then raise exception 'not_owner' using errcode = '42501'; end if;
  if exists (select 1 from public.editors where user_id = p_user and role = 'owner') then
    raise exception 'editor_is_owner' using errcode = 'P0001';
  end if;
  if p_on then
    if not exists (select 1 from public.members where user_id = p_user and status = 'member') then
      raise exception 'editor_not_member' using errcode = 'P0001';
    end if;
    insert into public.editors (user_id, role) values (p_user, 'editor') on conflict (user_id) do nothing;
  else
    delete from public.editors where user_id = p_user and role = 'editor';
  end if;
end $$;

-- editors can see who the other editors are (already allowed); the app needs each member's editor status
create or replace function public.member_roles() returns table (user_id uuid, role text)
language sql stable security definer set search_path = '' as $$
  select e.user_id, e.role from public.editors e where public.is_editor();
$$;

-- ---------- photos ----------
-- Public bucket: anyone can view a photo; a member can add and remove only files in their own folder.
-- Photos are resized in the browser to a 400px square JPEG, which also strips location and camera data.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 262144, array['image/jpeg'])
on conflict (id) do update set public = true, file_size_limit = 262144, allowed_mime_types = array['image/jpeg'];

create policy "members add their own photo" on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text
              and exists (select 1 from public.members m where m.user_id = (select auth.uid()) and m.status = 'member'));
create policy "members remove their own photo" on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "members list their own photos" on storage.objects for select to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- ---------- permissions ----------
revoke execute on function public.update_profile(jsonb) from public, anon;
revoke execute on function public.set_editor(uuid, boolean) from public, anon;
revoke execute on function public.is_owner() from public, anon;
revoke execute on function public.member_roles() from public, anon;
revoke execute on function public.public_profiles() from public;
grant execute on function public.update_profile(jsonb) to authenticated;
grant execute on function public.set_editor(uuid, boolean) to authenticated;
grant execute on function public.is_owner() to authenticated;
grant execute on function public.member_roles() to authenticated;
grant execute on function public.public_profiles() to anon, authenticated;
-- note: is_editor() stays callable by anon, because the public read policies on entities and links call it.

-- ---------- monthly clean-up of closed reports (privacy notice: deleted within 12 months of being closed) ----------
create extension if not exists pg_cron;
select cron.schedule('delete-closed-reports', '17 3 1 * *',
  $$delete from public.reports where status = 'done' and resolved_at < now() - interval '12 months'$$);
