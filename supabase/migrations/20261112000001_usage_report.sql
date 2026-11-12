-- 0.3.23: usage figures for the editor dashboard, compared with the Supabase Free plan limits in the app.
-- Database size and file storage come from the database itself; "active users" counts sign-ins in the last 30 days
-- (Supabase bills monthly active users the same way). Egress isn't visible from inside the database.
create or replace function public.usage_report() returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_editor() then raise exception 'editors only'; end if;
  return jsonb_build_object(
    'db_bytes', pg_database_size(current_database()),
    'storage_bytes', (select coalesce(sum((o.metadata->>'size')::bigint), 0) from storage.objects o),
    'storage_files', (select count(*) from storage.objects),
    'users', (select count(*) from auth.users),
    'active_30d', (select count(*) from auth.users u where u.last_sign_in_at > now() - interval '30 days'),
    'entries', (select count(*) from public.entities),
    'links', (select count(*) from public.links),
    'stories', (select count(*) from public.stories),
    'at', now());
end $$;
revoke all on function public.usage_report() from public;
grant execute on function public.usage_report() to authenticated;
