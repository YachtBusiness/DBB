# Changelog

Version plan: 0.1 public map live · 0.2 editing moves to Supabase · 0.3 sign-in, applications and claims · 0.4 paid tiers, organisation editing, contact details · 1.0 membership network opens · 1.x events and intros. Small fixes in between are 0.x.1, 0.x.2 and so on.

## 0.3.2 (6 November 2026)

Member profiles.

- Your profile: signed-in members open their profile from their name at the top right. Photo, bio, LinkedIn, Instagram, other social or website, a contact email (separate from the sign-in email) and WhatsApp or mobile.
- Who sees what, one switch per field: name, nationality and roles always; photo, LinkedIn and other social on by default, for everyone; contact email and WhatsApp off by default, and for paid members only once paid membership starts (nobody sees them before then).
- Finish your profile: a checklist above the profile (add a photo, check what's visible, review your bio, see yourself on the map) that goes once done or dismissed. Members signing in by link land on their profile until it's done.
- Photos are cropped to a 400px square JPEG in the browser before upload, which also strips location and camera data, and stored in Supabase Storage. Members can only add or remove their own. A plain silhouette stands in until there's a photo.
- Members' entries on the map now show their profile: photo, "Member since", bio and links, as their switches allow. Members see "Edit your profile" on their own entry.
- The owner can make a member an editor, or remove the role, from the member's entry.
- Send feedback fills in a signed-in member's name.
- Photo guidance (added after release): a clear, recent photo of your face, head and shoulders; not a logo, boat, animal or group shot.
- Closed reports are deleted automatically 12 months after being closed (monthly job), as the privacy notice says.

## 0.3.1 (6 November 2026)

Privacy.

- Privacy notice at /privacy.html: who runs the book (Aquitude Group Limited), what's held about people in the book and about applicants and members, why, who sees it, how long it's kept, the providers used, and how to use your rights (privacy@darkbluebook.com). Linked from the footer, the menu, the Apply form and the report form.
- Apply: a required tick box, "I'm 18 or over, and I've read the privacy notice".
- Fonts are served from the app itself instead of Google Fonts, so visitors' IP addresses no longer go to Google. Same fonts, same look.

## 0.3.0 (6 November 2026)

First step of 0.3: applications.

- Header: Apply button and Sign in at the top right (Join on mobile). Sign in left the footer and menu; once signed in it shows the member's first name, or Account, and opens their account panel.
- Apply: name, email (sign-in only, never shown), nationality (one, required, from a fuller list), at least one role (team, club, organisation or event from the book, or typed if it isn't there; current or past with years), LinkedIn, WhatsApp/mobile, Instagram, other social, bio, connection to the sport, teams and events worked with, referred by. As the applicant types their name, the app suggests matching people already in the book ("Is this you?"); picking one fills in their roles from the book. Matching copes with accents, middle names and common nicknames.
- Applying creates the sign-in account and emails a one-time link (public sign-up stays off; a new `apply` Edge Function does it). Opening the link confirms the email and shows "Your application is being reviewed", with the date applied. Applicants can edit or withdraw (which deletes their details) and browse the map. Unconfirmed applications are deleted after a week.
- Editors: Applications (n) beside Reports. Each application shows everything given, links to LinkedIn, Instagram and WhatsApp, possible matches in the book, and an editor-only note. Accept puts them on the map in one step: a new person entry or the one they claimed, any organisation that wasn't listed (matched to an existing entry or added as new), and a link for each role (sourced "Member application"). Decline deletes the application and account, with no email.
- Accepting sends the welcome email automatically through Resend (a new `welcome` Edge Function, editors only): from "Dave at The Dark Blue Book", replies to editor@darkbluebook.com, sent once per member. If it can't send, the app says why, with Try again and a send-it-yourself fallback.
- New tables `members` and `member_notes`; applications are only written through database functions, so applicants can't change their own status.

## 0.2.7 (5 November 2026)

- Sign-in with an email that has no account now says so plainly ("There's no account for …") instead of showing Supabase's "Signups not allowed for otp".

## 0.2.6 (5 November 2026)

- Section headings in the side panel (Featured, In the news, Latest changes, Role, People, Commercial, Structure, Past, Timeline) are larger and sit on a grey band, so sections are easier to tell apart.

## 0.2.5 (5 November 2026)

- Latest changes is back, for signed-in editors only. It reads the audit log, so it shows additions, edits (naming the fields changed) and deletions, newest first, each marked app or intake. Ten show by default, up to forty on request.

## 0.2.4 (5 November 2026)

- Link form: help with direction. A one-line rule under the heading; a live sentence reading the link back ("Ichi Ban races in class Volvo 70"); a warning with a Swap button when the book usually has that pair of kinds the other way round; and the usual roles for the pair as one-click suggestions, which also set the kind of link. Suggestions and warnings come from the book's own links, so they keep up as it grows.

## 0.2.3 (5 November 2026)

- Latest changes removed from the overview. It could be gamed once members add their own content; an Upcoming events block will take its place.

## 0.2.2 (5 November 2026)

- "Report an error" on every entry. The reader picks the entry itself or one of its links, says what's wrong, and gives their email (required) and optionally a name.
- "Send feedback" in the footer (desktop) and the menu (mobile), open to anyone; email required.
- Both land in one editor queue: signed-in editors see "Reports (n)" with the open count, can open the entry concerned, mark a report done, reopen it or delete it. Only editors can read reports.
- New `reports` table. Anyone can send; a hidden field catches simple bots, and new reports are refused once 60 have arrived in an hour.

## 0.2.1 (4 November 2026)

- Links that haven't started yet are no longer filed under Past. They show with current links, marked Upcoming and dated "from 2027". Past now means ended.
- The Year slider runs up to the latest year anything in the book starts (2028 for now; contract end dates don't count), still starting on the current year.

## 0.2.0 (3 November 2026)

- Editor sign-in: "Sign in" in the footer (desktop) and the menu (mobile) sends a one-time sign-in link by email. No passwords. Only accounts added in Supabase can sign in, and only accounts in the editors table can change the book.
- Editors can add, edit and delete entries and links from the app. Changes save straight to Supabase and are logged in the audit log.
- New links get the next l-number automatically (database default).
- Country is picked from a list of the codes the book uses (World Sailing style: GBR, SUI, GER, NED). If a save is refused, the message says which field to fix.

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
