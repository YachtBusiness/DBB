-- 0.3.39: confirmation links that last as long as the application, separate from sign-in.
-- Sign-in links expire after an hour, which is too short for "confirm your email" (people open it the next day).
-- The application email and the reminder now carry a confirm link (app.darkbluebook.com/#confirm=<token>) that only
-- confirms the email: it moves the application to pending and does NOT sign anyone in, so it's safe to work for days.
-- It works until the application is confirmed or deleted (at most 7 days, or 2 days after the reminder).
-- Tokens are random (32 bytes), stored only as a SHA-256 hash, and all of an applicant's tokens go once one is used.

create table if not exists public.application_tokens (
  token_hash text primary key,
  user_id uuid not null references public.members (user_id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists application_tokens_user on public.application_tokens (user_id);
alter table public.application_tokens enable row level security;
revoke all on public.application_tokens from anon, authenticated;

-- A new confirm token for an unconfirmed application (apply and remind Edge Functions, service role).
create or replace function public.application_token_new(p_user uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare t text;
begin
  if not exists (select 1 from public.members where user_id = p_user and status = 'unconfirmed') then return null; end if;
  t := translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/=', '-_');
  insert into public.application_tokens (token_hash, user_id)
  values (encode(extensions.digest(t, 'sha256'), 'hex'), p_user);
  return t;
end $$;

-- Opening the confirm link: anyone holding the token can confirm that application, nothing more.
create or replace function public.confirm_application_token(p_token text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare u uuid; st text; nm text;
begin
  if p_token is null or length(p_token) < 40 or length(p_token) > 60 then return jsonb_build_object('result', 'invalid'); end if;
  select t.user_id into u from public.application_tokens t where t.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex');
  if u is null then return jsonb_build_object('result', 'invalid'); end if;
  select status, name into st, nm from public.members where user_id = u;
  if st = 'unconfirmed' then
    update public.members set status = 'pending', confirmed_at = now(), updated_at = now() where user_id = u;
    st := 'confirmed';
  end if;
  delete from public.application_tokens where user_id = u;
  return jsonb_build_object('result', case when st = 'confirmed' then 'confirmed' else 'already' end,
                            'first_name', split_part(btrim(coalesce(nm, '')), ' ', 1));
end $$;

-- Confirming by signing in (the old way, still works) also clears the tokens.
create or replace function public.confirm_application() returns text
language plpgsql security definer set search_path = '' as $$
declare st text;
begin
  update public.members set status = 'pending', confirmed_at = now(), updated_at = now()
   where user_id = (select auth.uid()) and status = 'unconfirmed';
  delete from public.application_tokens where user_id = (select auth.uid());
  select status into st from public.members where user_id = (select auth.uid());
  return st;
end $$;

revoke execute on function public.application_token_new(uuid) from public, anon, authenticated;
grant execute on function public.application_token_new(uuid) to service_role;
revoke execute on function public.confirm_application_token(text) from public;
grant execute on function public.confirm_application_token(text) to anon, authenticated, service_role;
