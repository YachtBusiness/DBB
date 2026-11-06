-- 0.3.4: organisation profiles. Logo, short description, website, social links and a public contact email
-- on organisation entries. Editors write them for now (existing editor rights on entities); owners and
-- claims come with paid organisation editing in 0.4. Everyone can read them, like the rest of the book.

alter table public.entities
  add column if not exists logo_path text check (logo_path is null or logo_path ~ '^[a-z0-9-]+/[0-9]{10,16}\.(png|jpg)$'),
  add column if not exists about text not null default '' check (length(about) <= 600),
  add column if not exists website text not null default '' check (length(website) <= 300),
  add column if not exists linkedin text not null default '' check (length(linkedin) <= 300),
  add column if not exists instagram text not null default '' check (length(instagram) <= 300),
  add column if not exists other_social text not null default '' check (length(other_social) <= 300),
  add column if not exists contact_email text not null default '' check (contact_email = '' or (length(contact_email) <= 200 and contact_email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'));

-- logos: public to view; only editors add or remove them
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('logos', 'logos', true, 307200, array['image/png','image/jpeg'])
on conflict (id) do update set public = true, file_size_limit = 307200, allowed_mime_types = array['image/png','image/jpeg'];

create policy "editors add logos" on storage.objects for insert to authenticated
  with check (bucket_id = 'logos' and (select public.is_editor()));
create policy "editors remove logos" on storage.objects for delete to authenticated
  using (bucket_id = 'logos' and (select public.is_editor()));
create policy "editors list logos" on storage.objects for select to authenticated
  using (bucket_id = 'logos' and (select public.is_editor()));
