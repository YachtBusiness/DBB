-- 0.3.17: News links on organisations (same columns as people's, from 0.3.6), and "Featured" on News links.
-- Editors tick Featured beside a story on All news; ticked stories show under In the news on the overview,
-- replacing the separately written 'news' rows in the features table. No limit on how many.
alter table public.entities
  add column if not exists news_featured boolean not null default false;

-- A replaced or removed story takes its tick with it: the new story starts unticked.
create or replace function public.entities_news_featured_reset() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.news_url is distinct from old.news_url then
    new.news_featured := false;
  end if;
  return new;
end $$;

drop trigger if exists entities_news_featured_reset on public.entities;
create trigger entities_news_featured_reset before update of news_url on public.entities
  for each row execute function public.entities_news_featured_reset();

-- Carry over today's In the news picks that point at an entry with a News link.
update public.entities e set news_featured = true
  from public.features f
  where f.slot = 'news' and f.entity_id = e.id and e.news_url <> '';
