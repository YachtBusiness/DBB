-- The Dark Blue Book: core book tables (entities, links), editors, audit log.
-- Public can read curated rows; only editors can write.

create table public.editors (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'editor' check (role in ('owner','editor')),
  created_at timestamptz not null default now()
);

create or replace function public.is_editor() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.editors e where e.user_id = (select auth.uid()));
$$;

create table public.entities (
  id text primary key check (id ~ '^[a-z0-9][a-z0-9-]*$'),
  name text not null,
  type text not null check (type in ('person','team','club','org','event','entry','class','venue','record')),
  sectors text[] not null default '{}' check (sectors <@ array['sponsor','supplier','owner','media','agency','organiser','governing body','class association','industry body','public body','nonprofit']),
  level text check (level in ('series','event','edition','round')),
  country text not null default '' check (country = '' or country ~ '^[A-Z]{3}$'),
  note text not null default '',
  legacy_type text,
  status text not null default 'curated' check (status in ('curated','draft','hidden')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((type = 'event') = (level is not null)),
  check (type = 'org' or sectors = '{}')
);

create table public.links (
  id text primary key,
  from_id text not null references public.entities(id) on update cascade on delete restrict,
  to_id text not null references public.entities(id) on update cascade on delete restrict,
  role text not null,
  cat text not null check (cat in ('own','spon','ppl','str')),
  context_id text references public.entities(id) on update cascade on delete set null,
  start_date text not null default '' check (start_date = '' or start_date ~ '^\d{4}(-\d{2})?'),
  end_date text not null default '' check (end_date = '' or end_date ~ '^\d{4}(-\d{2})?'),
  source text not null default '',
  note text not null default '',
  status text not null default 'curated' check (status in ('curated','draft','hidden')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (from_id <> to_id)
);
create index links_from_idx on public.links(from_id);
create index links_to_idx on public.links(to_id);
create index links_context_idx on public.links(context_id);

create table public.audit_log (
  id bigint generated always as identity primary key,
  table_name text not null,
  row_id text not null,
  action text not null,
  old_row jsonb,
  new_row jsonb,
  changed_by uuid default auth.uid(),
  changed_at timestamptz not null default now()
);

create or replace function public.touch_and_audit() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'UPDATE' then new.updated_at := now(); end if;
  insert into public.audit_log(table_name,row_id,action,old_row,new_row)
  values (tg_table_name, coalesce(new.id, old.id), tg_op,
          case when tg_op <> 'INSERT' then to_jsonb(old) end,
          case when tg_op <> 'DELETE' then to_jsonb(new) end);
  return coalesce(new, old);
end $$;

create trigger entities_audit before insert or update or delete on public.entities
  for each row execute function public.touch_and_audit();
create trigger links_audit before insert or update or delete on public.links
  for each row execute function public.touch_and_audit();

alter table public.editors enable row level security;
alter table public.entities enable row level security;
alter table public.links enable row level security;
alter table public.audit_log enable row level security;

create policy "public reads curated entities" on public.entities for select
  to anon, authenticated using (status = 'curated' or (select public.is_editor()));
create policy "editors write entities" on public.entities for all
  to authenticated using ((select public.is_editor())) with check ((select public.is_editor()));

create policy "public reads curated links" on public.links for select
  to anon, authenticated using (status = 'curated' or (select public.is_editor()));
create policy "editors write links" on public.links for all
  to authenticated using ((select public.is_editor())) with check ((select public.is_editor()));

create policy "editors read editors" on public.editors for select
  to authenticated using ((select public.is_editor()));
create policy "editors read audit" on public.audit_log for select
  to authenticated using ((select public.is_editor()));

revoke execute on function public.touch_and_audit() from public, anon, authenticated;
