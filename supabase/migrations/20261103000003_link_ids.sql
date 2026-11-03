-- New links get the next l-number automatically, so the app and the intake skill don't have to work it out.
create or replace function public.next_link_id()
returns text language sql volatile security definer set search_path = '' as $$
  select 'l' || (coalesce(max(substring(id from 2)::int), 0) + 1)
  from public.links where id ~ '^l[0-9]+$';
$$;
revoke execute on function public.next_link_id() from public, anon;
grant execute on function public.next_link_id() to authenticated;
alter table public.links alter column id set default public.next_link_id();
