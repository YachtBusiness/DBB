# Changelog

Version plan: 0.1 public map live · 0.2 editing moves to Supabase · 0.3 sign-in, applications and claims · 0.4 paid tiers, organisation editing, contact details · 1.0 membership network opens · 1.x events and intros. Small fixes in between are 0.x.1, 0.x.2 and so on.

## 0.1.10 (3 November 2026)

- The Year slider starts at 2010 instead of the oldest dated link (1857). Older links still show under All time.

## 0.1.9 (3 November 2026)

- On a person's entry, the People group is headed "Role".

## 0.1.8 (3 November 2026)

- Entry panel: link groups show only links current in the selected year. Earlier ones move to a collapsed "Past" group at the bottom.

## 0.1.7 (3 November 2026)

- Entry panel: every link group (People, Commercial, Ownership, Structure) is collapsible, with a count. The first group with links opens by default; the rest start closed.

## 0.1.6 (3 November 2026)

- Entry panel: link groups in the order People, Commercial, Ownership, Structure. Timeline moved to the bottom and collapsed by default.

## 0.1.5 (3 November 2026)

- Anywhere other than app.darkbluebook.com (the preview site), the browser tab reads "[Preview] The Dark Blue Book" and a PREVIEW badge shows next to the version.

## 0.1.4 (3 November 2026)

- Overview panel: "Featured" (one curated entry with its partners and people) and "In the news" (three curated entries with a headline), above Latest changes. Picks live in the `features` table.

## 0.1.3 (3 November 2026)

- Overview panel: "Latest changes" (the three people and three organisations most recently linked) replaces the sponsor and multi-role lists.

## 0.1.2 (3 November 2026)

- Contact links (WhatsApp, LinkedIn group, Facebook, email): a footer bar on desktop, a menu button in the header on mobile.

## 0.1.1 (3 November 2026)

- "Season" renamed "Year" in the header slider and the overview heading.

## 0.1.0 (3 November 2026)

First public release at app.darkbluebook.com (www.darkbluebook.com and darkbluebook.com redirect to it).

- Map reads live from Supabase (London): 884 entries, 1,250 links, imported from the claude.ai book.
- Nine kinds: person, team, club, organisation (with sectors), event (with level: series, event, edition, round), entry, class, venue, record.
- Deep links: `#<entry id>` opens an entry; the address bar follows clicks; Back and Forward work; Copy link button on each entry.
- Database: public read of curated entries and links, editor-only writes, audit log of every change.
- Hosted on Cloudflare Pages from this repository; every commit to `main` deploys.

Known limits: editing still happens in the claude.ai book; Supabase is refreshed by re-running `supabase/import_book.sql`.
