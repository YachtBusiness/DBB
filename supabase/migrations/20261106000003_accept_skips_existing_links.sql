-- Accepting an application no longer duplicates links the book already has. When an applicant claims an
-- existing entry, their roles are prefilled from the book; a role that matches an existing link
-- (same person, same organisation, same role) is now skipped instead of added again.
create or replace function public.accept_application(p_user uuid, p_plan jsonb) returns text
language plpgsql security definer set search_path = '' as $$
declare m public.members; pid text; r jsonb; ne jsonb; tid text; n int := 0;
begin
  if not public.is_editor() then raise exception 'not_editor' using errcode = '42501'; end if;
  select * into m from public.members where user_id = p_user for update;
  if m.user_id is null or m.status <> 'pending' then raise exception 'application_not_pending' using errcode = 'P0001'; end if;
  pid := btrim(coalesce(p_plan->>'person_id',''));
  if coalesce((p_plan->>'new_person')::boolean, false) then
    insert into public.entities (id, name, type, country) values (pid, m.name, 'person', m.nationality);
  elsif not exists (select 1 from public.entities where id = pid and type = 'person') then
    raise exception 'accept_person_missing' using errcode = 'P0001';
  elsif exists (select 1 from public.members where entity_id = pid) then
    raise exception 'accept_person_taken' using errcode = 'P0001';
  end if;
  for r in select * from jsonb_array_elements(coalesce(p_plan->'roles','[]')) loop
    ne := r->'new_entity';
    if ne is not null and jsonb_typeof(ne) = 'object' then
      insert into public.entities (id, name, type, level, sectors, country)
      values (ne->>'id', btrim(ne->>'name'), ne->>'type',
              case when ne->>'type' = 'event' then coalesce(nullif(ne->>'level',''),'event') end,
              case when ne->>'type' = 'org' then coalesce((select array_agg(x) from jsonb_array_elements_text(ne->'sectors') x), '{}') else '{}' end,
              coalesce(ne->>'country',''))
      returning id into tid;
    else
      tid := r->>'to_id';
    end if;
    -- already in the book: leave the editorial link as it is
    if exists (select 1 from public.links l where l.from_id = pid and l.to_id = tid
               and lower(btrim(l.role)) = lower(btrim(r->>'role'))) then
      continue;
    end if;
    insert into public.links (from_id, to_id, role, cat, start_date, end_date, source)
    values (pid, tid, btrim(r->>'role'), coalesce(nullif(r->>'cat',''),'ppl'), coalesce(r->>'since',''),
            case when coalesce((r->>'current')::boolean, true) then '' else coalesce(r->>'until','') end,
            'Member application, ' || to_char(m.applied_at, 'FMDD Mon YYYY'));
    n := n + 1;
  end loop;
  if n = 0 and not exists (select 1 from public.links where from_id = pid or to_id = pid) then
    raise exception 'accept_needs_role' using errcode = 'P0001';
  end if;
  update public.members set status = 'member', entity_id = pid, accepted_at = now(),
         accepted_by = (select auth.uid()), updated_at = now() where user_id = p_user;
  return pid;
end $$;
revoke execute on function public.accept_application(uuid, jsonb) from public, anon;
grant execute on function public.accept_application(uuid, jsonb) to authenticated;
