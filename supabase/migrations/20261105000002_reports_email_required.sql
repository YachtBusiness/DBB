-- Reports and feedback are open to everyone, so every one carries an email address (D, 5 Nov 2026).
alter table public.reports drop constraint if exists reports_email_check;
alter table public.reports add constraint reports_email_check
  check (length(email) <= 200 and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$');
