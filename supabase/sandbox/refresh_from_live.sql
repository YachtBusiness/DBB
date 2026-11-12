-- SANDBOX PROJECT ONLY (dbb-sandbox, kttiojuuynaznqrcwbyy). Never run on the live project.
-- Copies the public book from the live site's public API (the same data any visitor can read): entries, links,
-- Featured, stories and their tags. No members, accounts, applications, reports or searches are copied.
-- Usage, as the database owner: select sandbox.book_fetch();  wait ~10 seconds;  select sandbox.book_import();
create schema if not exists sandbox;
revoke all on schema sandbox from public, anon, authenticated;
create extension if not exists pg_net;
create table if not exists sandbox.fetch (tbl text, page int, req bigint, primary key (tbl, page));

create or replace function sandbox.book_fetch() returns int language plpgsql as $$
declare
  live text := 'https://mntfwjwjcfdanxfpipgm.supabase.co/rest/v1/';
  hdr jsonb := '{"apikey":"sb_publishable_XfrmGdoOfFhWgK0ybagpdA_MxfVZauP"}';
  t text; p int; n int := 0;
begin
  delete from sandbox.fetch;
  foreach t in array array['entities','links','features','stories','story_entities'] loop
    for p in 0..4 loop  -- up to 5,000 rows per table, 1,000 a page
      insert into sandbox.fetch values (t, p,
        net.http_get(live || t || '?select=*&order=' || case when t='story_entities' then 'story_id,entity_id' when t='features' then 'slot,position' else 'id' end
          || '&limit=1000&offset=' || (p * 1000), headers := hdr, timeout_milliseconds := 30000));
      n := n + 1;
    end loop;
  end loop;
  return n;
end $$;

create or replace function sandbox.book_import() returns jsonb language plpgsql as $$
declare missing int;
begin
  select count(*) into missing from sandbox.fetch f left join net._http_response r on r.id = f.req where r.id is null or r.status_code <> 200;
  if missing > 0 then raise exception '% pages not fetched yet (or failed); wait and try again', missing; end if;
  alter table public.entities disable trigger user;
  alter table public.links disable trigger user;
  alter table public.stories disable trigger user;
  truncate public.story_entities, public.stories, public.features, public.links cascade;
  -- keep the sandbox's own entries: test accounts' people and the Media group
  delete from public.entities where id not like 'test-%' and id <> 'media';
  -- created_by points at member accounts, which aren't copied: blank it
  insert into public.entities select (jsonb_populate_record(null::public.entities, '{"media_type":""}'::jsonb || j || '{"created_by":null}')).*
    from sandbox.fetch f join net._http_response r on r.id = f.req, jsonb_array_elements(r.content::jsonb) j where f.tbl = 'entities'
    on conflict (id) do nothing;
  -- only links whose ends are in the copy (anything pointing at a draft or hidden entry is skipped)
  insert into public.links
    select (jsonb_populate_record(null::public.links,
             (case when j->>'context_id' is null or j->>'context_id' in (select id from public.entities) then j else j || '{"context_id":null}' end) || '{"created_by":null}')).*
    from sandbox.fetch f join net._http_response r on r.id = f.req, jsonb_array_elements(r.content::jsonb) j
    where f.tbl = 'links' and j->>'from_id' in (select id from public.entities) and j->>'to_id' in (select id from public.entities);
  insert into public.features select x.* from sandbox.fetch f join net._http_response r on r.id = f.req,
    jsonb_populate_recordset(null::public.features, r.content::jsonb) x where f.tbl = 'features' and x.entity_id in (select id from public.entities);
  insert into public.stories select x.* from sandbox.fetch f join net._http_response r on r.id = f.req,
    jsonb_populate_recordset(null::public.stories, r.content::jsonb) x where f.tbl = 'stories';
  insert into public.story_entities select x.* from sandbox.fetch f join net._http_response r on r.id = f.req,
    jsonb_populate_recordset(null::public.story_entities, r.content::jsonb) x where f.tbl = 'story_entities' and x.entity_id in (select id from public.entities);
  -- the test accounts' roles
  insert into public.links (from_id, to_id, role, cat, source)
    select t.id, 'den', 'crew', 'ppl', 'Member application' from public.entities t
    where t.id in ('test-member','test-editor') and exists (select 1 from public.entities where id='den')
    on conflict do nothing;
  alter table public.entities enable trigger user;
  alter table public.links enable trigger user;
  alter table public.stories enable trigger user;
  return jsonb_build_object('entities', (select count(*) from public.entities), 'links', (select count(*) from public.links),
    'features', (select count(*) from public.features), 'stories', (select count(*) from public.stories),
    'tags', (select count(*) from public.story_entities), 'copied_at', now());
end $$;
revoke all on function sandbox.book_fetch(), sandbox.book_import() from public, anon, authenticated;
