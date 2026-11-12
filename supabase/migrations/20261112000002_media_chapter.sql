-- 0.3.26: the Media cohort.
-- A new kind of entry, "group" (shown as Cohort): a grouping rather than a real organisation. Not drawn on the map;
-- opening one shows its page. The first is Media, for freelancers with nothing else to link to.
-- Media organisations can carry a media type (magazine, website, YouTube channel...), to sort the cohort.
alter table public.entities drop constraint if exists entities_type_check;
alter table public.entities add constraint entities_type_check
  check (type in ('person','team','club','org','event','entry','class','venue','record','group'));
alter table public.entities add column if not exists media_type text not null default ''
  check (media_type in ('','magazine','website','youtube','podcast','tv','film','photo agency','agency','publisher','social','other'));
insert into public.entities (id, name, type, note)
values ('media', 'Media', 'group',
  'The Media cohort: the outlets of yacht racing and the people who work for them. Freelancers with no company of their own in the book are linked here.')
on conflict (id) do nothing;
