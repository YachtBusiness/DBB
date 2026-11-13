-- 0.3.30: freelance photographers. Photographers are the one standalone media role: a person can be marked as one
-- (media sector plus the photographer tag) and is listed under Photographers on the Media page. Writers come in as
-- contributors to a title, presenters and commentators are commercial arrangements, videographers work via companies.
alter table public.entities drop constraint if exists entities_check1;
alter table public.entities add constraint entities_sectors_kind_check
  check (type = 'org' or sectors = '{}' or (type = 'person' and sectors = array['media']));
alter table public.entities add constraint entities_media_tags_kind_check
  check (type = 'org' or media_tags = '{}' or (type = 'person' and media_tags = array['photographer'] and sectors = array['media']));
