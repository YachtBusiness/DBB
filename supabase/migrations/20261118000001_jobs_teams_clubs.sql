-- 0.3.43: teams and clubs can hold job ads, as well as organisations (decided 18 Nov 2026). Events still can't: their organiser posts.
-- Only job_save checked the entry's type; everything else follows the entity id.

create or replace function public.job_save(p_id uuid, p_entity text, p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare me uuid := auth.uid(); ent text := p_entity; jid uuid; cl date; exp timestamptz;
  t text := btrim(coalesce(p->>'title', '')); loc text := btrim(coalesce(p->>'location', ''));
  wp text := coalesce(nullif(p->>'workplace', ''), 'onsite'); jt text := coalesce(p->>'job_type', '');
  sal text := btrim(coalesce(p->>'salary', '')); d text := btrim(coalesce(p->>'description', ''));
  ap text := btrim(coalesce(p->>'apply_to', ''));
begin
  if p_id is not null then
    select entity_id into ent from public.jobs where id = p_id;
    if ent is null then raise exception 'job_missing' using errcode = 'P0001'; end if;
  end if;
  if ent is null or not exists (select 1 from public.entities where id = ent and type in ('org', 'team', 'club')) then raise exception 'job_org' using errcode = 'P0001'; end if;
  if not public.can_post_jobs(ent) then raise exception 'not_allowed' using errcode = '42501'; end if;
  if ap ~ '^www\.' then ap := 'https://' || ap; end if;
  if nullif(p->>'closes_on', '') is not null then
    begin cl := (p->>'closes_on')::date; exception when others then raise exception 'job_closes_on' using errcode = 'P0001'; end;
    if cl < current_date then raise exception 'job_closes_on' using errcode = 'P0001'; end if;
  end if;
  if p_id is null then
    if not public.is_editor() and (select count(*) from public.jobs where posted_by = me and created_at > now() - interval '1 day') >= 20 then
      raise exception 'job_rate_limit' using errcode = 'P0001';
    end if;
    if public.jobs_live_count(ent) >= 5 then raise exception 'job_limit' using errcode = 'P0001'; end if;
    exp := now() + interval '30 days';
    if cl is not null and cl + 1 < exp then exp := cl + 1; end if;
    insert into public.jobs (entity_id, posted_by, title, location, workplace, job_type, salary, description, apply_to, closes_on, expires_at)
    values (ent, (select user_id from public.members where user_id = me), t, loc, wp, jt, sal, d, ap, cl, exp) returning id into jid;  -- editors without a member row post as nobody
    return jid;
  end if;
  update public.jobs set title = t, location = loc, workplace = wp, job_type = jt, salary = sal, description = d, apply_to = ap,
    closes_on = cl, expires_at = case when cl is not null and cl + 1 < expires_at then cl + 1 else expires_at end, updated_at = now()
   where id = p_id;
  return p_id;
end $$;

revoke execute on function public.job_save(uuid, text, jsonb) from public, anon;
grant execute on function public.job_save(uuid, text, jsonb) to authenticated;
