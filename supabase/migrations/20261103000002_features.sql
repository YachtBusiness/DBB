-- Curated picks for the overview panel: one Featured entry and up to three In the News entries.
create table public.features (
  slot text not null check (slot in ('featured','news')),
  position int not null check (position between 1 and 9),
  entity_id text not null references public.entities(id) on update cascade on delete cascade,
  headline text not null default '',
  link text not null default '',
  updated_at timestamptz not null default now(),
  primary key (slot, position)
);
alter table public.features enable row level security;
create policy "public reads features" on public.features for select to anon, authenticated using (true);
create policy "editors write features" on public.features for all to authenticated
  using ((select public.is_editor())) with check ((select public.is_editor()));
