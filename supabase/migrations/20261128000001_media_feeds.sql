-- 0.3.45: media feeds. The Media page goes "upstream": for outlets with an RSS or Atom feed (website, Substack,
-- podcast, YouTube channel), the feeds Edge Function reads the feed every hour and keeps the newest 10 items per feed:
-- headline, link, date, a short snippet (about 220 characters, no HTML) and what it is (article, episode, video).
-- Never the full article or the audio: readers click through to the outlet.
-- Editors add and remove feeds for now (up to 3 per outlet). Letting an outlet's own owners and managers set their
-- feed is the candidate paid feature (see the roadmap, 0.4).

create table if not exists public.media_feeds (
  id bigint generated always as identity primary key,
  entity_id text not null references public.entities(id) on delete cascade,
  url text not null check (url ~* '^https?://[^\s]+$' and char_length(url) <= 500),
  title text not null default '',
  checked_at timestamptz,
  ok_at timestamptz,
  error text not null default '',
  fails int not null default 0,
  etag text not null default '',
  last_modified text not null default '',
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  unique (entity_id, url)
);

create table if not exists public.media_items (
  id bigint generated always as identity primary key,
  feed_id bigint not null references public.media_feeds(id) on delete cascade,
  entity_id text not null references public.entities(id) on delete cascade,
  guid text not null,
  url text not null check (url ~* '^https?://'),
  title text not null,
  snippet text not null default '',
  published_at timestamptz not null,
  kind text not null default 'article' check (kind in ('article','episode','video')),
  duration_s int,
  fetched_at timestamptz not null default now(),
  unique (feed_id, guid)
);
create index if not exists media_items_published on public.media_items (published_at desc);
create index if not exists media_items_entity on public.media_items (entity_id, published_at desc);

alter table public.media_feeds enable row level security;
alter table public.media_items enable row level security;
-- everyone reads the items (they're public headlines with links out); only editors see the feeds and their errors.
-- Nobody writes directly: the feeds function writes with the service key, editors go through the functions below.
drop policy if exists media_items_read on public.media_items;
create policy media_items_read on public.media_items for select to anon, authenticated using (true);
drop policy if exists media_feeds_read on public.media_feeds;
create policy media_feeds_read on public.media_feeds for select to authenticated using (public.is_editor());
revoke insert, update, delete, truncate on public.media_items, public.media_feeds from anon, authenticated;

-- editors: add a feed to a media outlet (the app checks it with the feeds function first)
create or replace function public.media_feed_add(p_entity text, p_url text, p_title text default '') returns bigint
language plpgsql security definer set search_path = '' as $$
declare u text := btrim(coalesce(p_url, '')); fid bigint;
begin
  if not public.is_editor() then raise exception 'not_editor' using errcode = '42501'; end if;
  if not exists (select 1 from public.entities where id = p_entity and type = 'org' and 'media' = any(sectors)) then
    raise exception 'not_media'; end if;
  if u !~* '^https?://[^\s]+$' or char_length(u) > 500 then raise exception 'bad_url'; end if;
  if (select count(*) from public.media_feeds where entity_id = p_entity) >= 3 then raise exception 'too_many_feeds'; end if;
  insert into public.media_feeds (entity_id, url, title) values (p_entity, u, left(btrim(coalesce(p_title, '')), 200))
  on conflict (entity_id, url) do update set title = excluded.title
  returning id into fid;
  return fid;
end $$;

-- editors: remove a feed (its items go with it)
create or replace function public.media_feed_remove(p_id bigint) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_editor() then raise exception 'not_editor' using errcode = '42501'; end if;
  delete from public.media_feeds where id = p_id;
end $$;

-- the feeds function: keep the newest 10 items of a feed
create or replace function public.media_items_prune(p_feed bigint) returns int
language sql security definer set search_path = '' as $$
  with gone as (
    delete from public.media_items where feed_id = p_feed and id not in (
      select id from public.media_items where feed_id = p_feed order by published_at desc limit 10)
    returning 1)
  select count(*)::int from gone;
$$;

-- the feeds function checks the caller's key against Vault, like the remind function
create or replace function public.feeds_key_ok(p_key text) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(length(p_key) >= 32 and p_key = (select decrypted_secret from vault.decrypted_secrets where name = 'feeds_secret'), false);
$$;

-- hourly (pg_cron): ask the feeds function to read every feed
create or replace function public.media_feeds_check() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare sec text; fn text; req bigint; n int;
begin
  select count(*) into n from public.media_feeds;
  if n = 0 then return jsonb_build_object('feeds', 0, 'called', false); end if;
  select decrypted_secret into sec from vault.decrypted_secrets where name = 'feeds_secret';
  select decrypted_secret into fn from vault.decrypted_secrets where name = 'feeds_url';
  if sec is not null and fn is not null then
    req := net.http_post(url := fn,
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-feeds-secret', sec),
      body := '{}'::jsonb, timeout_milliseconds := 60000);
  end if;
  return jsonb_build_object('feeds', n, 'called', req is not null);
end $$;

revoke all on function public.media_feed_add(text, text, text) from public, anon;
grant execute on function public.media_feed_add(text, text, text) to authenticated;
revoke all on function public.media_feed_remove(bigint) from public, anon;
grant execute on function public.media_feed_remove(bigint) to authenticated;
revoke all on function public.media_items_prune(bigint) from public, anon, authenticated;
grant execute on function public.media_items_prune(bigint) to service_role;
revoke all on function public.feeds_key_ok(text) from public, anon, authenticated;
grant execute on function public.feeds_key_ok(text) to service_role;
revoke all on function public.media_feeds_check() from public, anon, authenticated;

-- Then, once per project (not in this file: the secret stays out of the repo):
--   select vault.create_secret('<random 48+ characters>', 'feeds_secret');
--   select vault.create_secret('https://<project>.supabase.co/functions/v1/feeds', 'feeds_url');
--   select cron.schedule('media-feeds', '37 * * * *', 'select public.media_feeds_check()');

-- The spotlit title at the top of the Media page (D, 28 Nov 2026: Yacht Business, front and centre): a features row
-- in a new 'media' slot, changed like Featured (the dark-blue-book-featured skill).
alter table public.features drop constraint if exists features_slot_check;
alter table public.features add constraint features_slot_check check (slot in ('featured','news','media'));
insert into public.features (slot, position, entity_id) values ('media', 1, 'yb') on conflict (slot, position) do update set entity_id = excluded.entity_id;
