# The Dark Blue Book

The who's who of yacht racing: a relationship map of the people, teams, clubs, organisations and events in the sport, growing into a members' business network.

## Layout

- `supabase/migrations/`: database schema, applied in order. `20261103000001_book_core.sql` creates the book (entities, links), editors and the audit log, with row-level security: the public reads curated rows, only editors write.
- `supabase/import_book.sql`: one-off import of the book from its claude.ai edition. Safe to re-run; existing rows are updated.
- `tools/book_to_sql.py`: rebuilds the import file from a JSON dump of the claude.ai book.

## Plan

1. Public map reads live from Supabase, hosted at app.yachtbusiness.biz.
2. Sign-in, applications and claims.
3. Paid tiers (Stripe), organisation editing, contact details.
4. Events and intros.
