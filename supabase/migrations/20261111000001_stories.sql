-- 0.3.19: news stories as their own records. A story (link, headline, date, Featured) tags any number of
-- people, teams, organisations, clubs and events. Replaces the one News link per entry (entities.news_*),
-- which are copied across here; those columns stay until a later clean-up but the app no longer reads them.
create table if not exists public.stories (
  id uuid primary key default gen_random_uuid(),
  url text not null unique check (url ~* '^https?://[^\s.]+\.[^\s]+$' and char_length(url) <= 500),
  title text not null default '' check (char_length(title) <= 200),
  published date,
  featured boolean not null default false,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_at timestamptz not null default now()
);
create table if not exists public.story_entities (
  story_id uuid not null references public.stories(id) on delete cascade,
  entity_id text not null references public.entities(id) on delete cascade,
  primary key (story_id, entity_id)
);
create index if not exists story_entities_entity on public.story_entities (entity_id);

alter table public.stories enable row level security;
alter table public.story_entities enable row level security;
drop policy if exists stories_read on public.stories;
create policy stories_read on public.stories for select to anon, authenticated using (true);
drop policy if exists stories_edit on public.stories;
create policy stories_edit on public.stories for all to authenticated using ((select public.is_editor())) with check ((select public.is_editor()));
drop policy if exists story_entities_read on public.story_entities;
create policy story_entities_read on public.story_entities for select to anon, authenticated using (true);
drop policy if exists story_entities_edit on public.story_entities;
create policy story_entities_edit on public.story_entities for all to authenticated using ((select public.is_editor())) with check ((select public.is_editor()));
grant select on public.stories, public.story_entities to anon, authenticated;
grant insert, update, delete on public.stories, public.story_entities to authenticated;

-- Save a story and its tags in one go (editors only). p_id null creates one. Returns the story's id.
create or replace function public.save_story(p_id uuid, p_url text, p_title text, p_published date, p_entities text[])
returns uuid language plpgsql security definer set search_path = '' as $$
declare sid uuid := p_id; u text := btrim(coalesce(p_url, ''));
begin
  if not public.is_editor() then raise exception 'editors only'; end if;
  if coalesce(array_length(p_entities, 1), 0) = 0 then raise exception 'Tag at least one entry'; end if;
  if sid is null then
    if exists (select 1 from public.stories where url = u) then raise exception 'That story is already in the book'; end if;
    insert into public.stories (url, title, published) values (u, btrim(coalesce(p_title, '')), p_published) returning id into sid;
  else
    update public.stories set url = u, title = btrim(coalesce(p_title, '')), published = p_published, updated_at = now() where id = sid;
    if not found then raise exception 'Story not found'; end if;
    delete from public.story_entities where story_id = sid;
  end if;
  insert into public.story_entities (story_id, entity_id)
    select sid, e.id from public.entities e where e.id = any (p_entities) on conflict do nothing;
  return sid;
end $$;
revoke all on function public.save_story(uuid, text, text, date, text[]) from public;
grant execute on function public.save_story(uuid, text, text, date, text[]) to authenticated;

-- Copy the per-entry News links across: one story per link, tagged with every entry that carried it.
insert into public.stories (url, title, published, featured, created_at)
select e.news_url,
       coalesce(max(nullif(e.news_title, '')), ''),
       max(nullif(e.news_date, '')::date),
       bool_or(e.news_featured),
       now()
from public.entities e
where e.news_url <> '' and e.news_url ~* '^https?://[^\s.]+\.[^\s]+$'
group by e.news_url
on conflict (url) do nothing;
insert into public.story_entities (story_id, entity_id)
select s.id, e.id from public.entities e join public.stories s on s.url = e.news_url
where e.news_url <> ''
on conflict do nothing;
