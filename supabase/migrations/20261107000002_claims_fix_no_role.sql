-- Fix: someone with no role on an organisation must get "no", not "unknown", from these checks.
create or replace function public.can_run_org(p_entity text) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(public.is_editor(), false) or coalesce(public.org_role_of(p_entity) = 'owner', false);
$$;
create or replace function public.can_edit_org(p_entity text) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(public.is_editor(), false) or coalesce(public.org_role_of(p_entity) in ('owner','manager'), false);
$$;
