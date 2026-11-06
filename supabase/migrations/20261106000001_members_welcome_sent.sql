-- When the welcome email went out (set by the welcome Edge Function), so it is never sent twice by accident.
alter table public.members add column if not exists welcome_sent_at timestamptz;
