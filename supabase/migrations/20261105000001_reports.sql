-- Reports and feedback: one editor queue for "Report an error" (on an entry or link) and "Send feedback" (general).
-- Anyone can send one; nobody but editors can read them. From 0.3, signed-in members' reports carry their user id.

create table public.reports (
  id bigint generated always as identity primary key,
  kind text not null check (kind in ('error','feedback')),
  entity_id text references public.entities(id) on update cascade on delete set null,
  link_id text references public.links(id) on update cascade on delete set null,
  page text not null default '' check (length(page) <= 500),
  message text not null check (length(btrim(message)) between 3 and 2000),
  name text not null default '' check (length(name) <= 120),
  email text not null default '' check (length(email) <= 200),
  user_id uuid default auth.uid() references auth.users(id) on delete set null,
  status text not null default 'open' check (status in ('open','done')),
  editor_note text not null default '' check (length(editor_note) <= 1000),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references auth.users(id) on delete set null
);
create index reports_status_idx on public.reports(status, created_at desc);

-- Flood brake: refuse new reports once 60 have arrived in the last hour.
create or replace function public.reports_guard() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if (select count(*) from public.reports where created_at > now() - interval '1 hour') >= 60 then
    raise exception 'reports_rate_limit' using errcode = 'P0001';
  end if;
  return new;
end $$;
revoke execute on function public.reports_guard() from public, anon, authenticated;
create trigger reports_guard before insert on public.reports
  for each row execute function public.reports_guard();

alter table public.reports enable row level security;

create policy "anyone sends a report" on public.reports for insert to anon, authenticated
  with check (status = 'open' and editor_note = '' and resolved_at is null and resolved_by is null
              and (user_id is null or user_id = (select auth.uid())));
create policy "editors read reports" on public.reports for select to authenticated
  using ((select public.is_editor()));
create policy "editors update reports" on public.reports for update to authenticated
  using ((select public.is_editor())) with check ((select public.is_editor()));
create policy "editors delete reports" on public.reports for delete to authenticated
  using ((select public.is_editor()));

grant insert on public.reports to anon, authenticated;
grant select, update, delete on public.reports to authenticated;
