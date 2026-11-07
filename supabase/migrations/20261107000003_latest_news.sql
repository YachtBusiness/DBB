-- 0.3.6: one "Latest news" link on a person's entry, added by editors: a link back to a press release or story
-- that links to that person's entry in the book. Shown only when set. Editors write it (existing editor rights).
alter table public.entities
  add column if not exists news_url text not null default '' check (news_url = '' or (length(news_url) <= 500 and news_url ~* '^https?://')),
  add column if not exists news_title text not null default '' check (length(news_title) <= 200),
  add column if not exists news_date text not null default '' check (news_date = '' or news_date ~ '^\d{4}-\d{2}-\d{2}$');
