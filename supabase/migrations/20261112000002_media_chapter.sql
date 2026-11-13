-- 0.3.26: the Media cohort.
-- A new kind of entry, "group" (shown as Cohort): a grouping rather than a real organisation. Not drawn on the map;
-- opening one shows its page. The first is Media, for freelancers with nothing else to link to.
alter table public.entities drop constraint if exists entities_type_check;
alter table public.entities add constraint entities_type_check
  check (type in ('person','team','club','org','event','entry','class','venue','record','group'));
-- Media titles can carry any number of tags (website, YouTube channel, podcast...): shown as labels and used as
-- filters in the cohort. A title is listed once, whatever its tags.
alter table public.entities add column if not exists media_tags text[] not null default '{}'
  check (media_tags <@ array['website','youtube','podcast','magazine','newsletter','tv','production company','publisher','photographer','agency','social','other']);
insert into public.entities (id, name, type, note)
values ('media', 'Media', 'group',
  'The Media cohort: the outlets of yacht racing and the people who work for them. Freelancers with no company of their own in the book are linked here.')
on conflict (id) do nothing;
