-- 0.3.27: "Latest piece" on media outlets: their newest video, episode or article.
-- Only registered media can set it: owners and managers of a media-ticked organisation (and editors), through
-- set_latest_piece(). Picking it up automatically from the outlet's feed is planned as a paid feature.
alter table public.entities
  add column if not exists latest_url text not null default '',
  add column if not exists latest_title text not null default '',
  add column if not exists latest_date date,
  add column if not exists latest_kind text not null default '' check (latest_kind in ('','video','episode','article','gallery','other'));

create or replace function public.set_latest_piece(p_entity text, p_url text, p_title text, p_date date, p_kind text)
returns void language plpgsql security definer set search_path = '' as $$
declare u text := btrim(coalesce(p_url, '')); t text := btrim(coalesce(p_title, ''));
begin
  if not public.can_edit_org(p_entity) then raise exception 'not_manager' using errcode = '42501'; end if;
  if not exists (select 1 from public.entities where id = p_entity and type = 'org' and 'media' = any(sectors)) then
    raise exception 'not_media'; end if;
  if u <> '' and (u !~* '^https://[^\s.]+\.[^\s]+$' or char_length(u) > 500) then raise exception 'bad_url'; end if;
  if char_length(t) > 160 then raise exception 'title_too_long'; end if;
  if coalesce(p_kind, '') not in ('','video','episode','article','gallery','other') then raise exception 'bad_kind'; end if;
  update public.entities set
    latest_url = u,
    latest_title = case when u = '' then '' else t end,
    latest_date = case when u = '' then null else p_date end,
    latest_kind = case when u = '' then '' else coalesce(p_kind, '') end
  where id = p_entity;
end $$;
revoke all on function public.set_latest_piece(text, text, text, date, text) from public, anon;
grant execute on function public.set_latest_piece(text, text, text, date, text) to authenticated;
