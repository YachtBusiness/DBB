# Changelog

Version plan: 0.1 public map live · 0.2 editing moves to Supabase · 0.3 sign-in, applications and claims · 0.4 paid features (contact details for paid members, extra profile links, job board, organisation editing, verified roles), switched on by editors before payments · 0.5 payments (Stripe, tiers, prices) · 1.0 membership network opens · 1.x events and intros. Small fixes in between are 0.x.1, 0.x.2 and so on.

## 0.3.16 (9 November 2026)

- Phone menu tidied: Calendar, News, Send feedback and Privacy at the top; WhatsApp, LinkedIn, Facebook and Email folded under "Contact us" at the bottom.
- News (app.darkbluebook.com/#yacht-racing-news) added to the phone menu and the desktop footer.

## 0.3.15 (8 November 2026)

- Buttons are a lighter blue (#b3cbe8) so the dark text reads on a phone in sunlight.

## 0.3.14 (8 November 2026)

- "Need a source" (the count on the overview) and the "needs source" tag on links are for editors only. The public sees neither.

## 0.3.13 (8 November 2026)

- Buttons are now a mid blue (#779ec9) instead of the grey of the panel's heading bars. Save and other main actions stay dark; Remove and Delete keep a plain background so the red reads.
- "All news" under In the news is a button, like "Full calendar" and the editors' changes list.

## 0.3.12 (8 November 2026)

All news.

- "All news (n) →", a small link under In the news on the overview, opens a list of every News link on the book's entries, newest first (undated ones last). Each shows the headline (opens the story), date, site and the entries it's on; a story on several entries shows once. Copy link, or straight from app.darkbluebook.com/#yacht-racing-news.
- Each entry still holds one News link, so adding a newer story to an entry replaces its old one in the list.

## 0.3.11 (7 November 2026)

- (8 Nov) The title "The Dark Blue Book" at the top left now goes back to the overview.

Calendar.

- Events, editions and rounds can have dates: start, end (blank if only the start is known, the same date for a one-day event) and "not confirmed yet", which shows the month only, "dates to be confirmed". Forward-only: past events don't get dates.
- "Coming up" on the overview: the next five, with "Full calendar".
- Calendar (from Coming up, the menu or the footer, or straight from app.darkbluebook.com/#yacht-racing-calendar, with Copy link): everything ahead, by month, with each event's dates, place and the series or event it belongs to. Filter by series or event, and everything ahead or the next three months. Selecting an event opens its entry and centres the map on it.
- An event's entry shows its dates and place under its name. Editors also see "no venue linked" where there's no venue on the event or its parent: the calendar is built so a travel partner can add "Plan your trip" later, which needs a venue and dates.
- Dates were filled in from the notes for 28 upcoming events, for D to check.

## 0.3.10 (7 November 2026)

- Editors: in the link form, Who, Of and Applies in are now search boxes instead of long dropdowns. Type the start of any word in the name (accents don't matter), then pick from up to 8 suggestions, each showing its kind and country, with the mouse, a tap, or the arrow keys and Enter. Spaces don't matter ("sail gp" finds SailGP) and initials work ("etnz" finds Emirates Team New Zealand). Applies in only suggests events. Swap still works.

## 0.3.9 (7 November 2026)

- Phones: the map hides while the panel shows a form or task (Join, sign-in, your profile, editing entries and links, reports, applications, claims), so forms get the whole screen. It comes back for entries and the overview.

## 0.3.8 (7 November 2026)

- Picking an entry from a link, search or the address now glides the map to centre it. If it's already well in view (for example a dot you just clicked), the map stays put.
- "Latest news" on people's entries is now headed "News" ("Add news" for editors), since a link may be some time old.

## 0.3.7 (7 November 2026)

Layout.

- Desktop: the panel (entries, profiles, forms) moves to the left and takes about 45% of the width; the map is on the right. Text in the panel is capped at a readable width on very wide screens.
- Phones: the map is a band across the top (about 40% of the screen) and the panel scrolls on its own below it, so swiping on the panel never moves the map. "Expand map" gives the map the whole screen; "Show details", or tapping an entry, brings the panel back. The filters (Everything / Money / People, series, year) fold away behind a Filters button, leaving search and the map more room.

## 0.3.6 (7 November 2026)

Latest news on people's entries.

- One "Latest news" link on a person's entry: a headline linking to a press release or story, with the site and an optional date. It only shows when there is one.
- Editors add, change or remove it ("Add latest news" on any person's entry). It's up to editors which stories get one. The idea: press releases and articles that link to people's entries in the book (e.g. app.darkbluebook.com/#bond) get a link back from that entry.
- Separate from "In the news" on the overview.

## 0.3.5 (7 November 2026)

Claims: owners and managers for organisation profiles.

- "Claim this organisation" on organisation entries, for signed-in members whose profile has a photo, a bio and a role (otherwise it says what's missing). The claim gives the connection (staff, owner or director, agency or contractor, other), what they do for the organisation and, optionally, something to help check; only editors see that.
- Editors: Claims (n) beside Applications. Each claim shows the claimant's profile and roles alongside. Approve as owner, approve as manager, or decline. Approving emails the member; declining deletes the claim, with no email.
- Owners and managers edit the organisation's profile (logo, description, links), free until paid tiers launch. Owners also see People: they invite managers by the email they sign in with (the invited member is emailed and accepts on the entry or their profile) and remove managers, for example when the organisation changes PR agency. The owner gets the same answer whether or not the email belongs to a member.
- Editors have the final say: they approve every claim, can change anyone between owner and manager, and remove anyone. Anyone can step down.
- Who manages a profile isn't shown publicly; a commercial link (X is PR agency of Y) covers that.
- Members see their organisations, claims and invitations on their own profile.
- A new notify Edge Function sends invitations and claim-approved emails.

## 0.3.4 (7 November 2026)

Organisation profiles.

- Organisation entries can have a profile at the top of the entry: logo, a short description (About, up to 500 characters), website, LinkedIn, Instagram, another social link and a public contact email. Empty parts don't show, so organisations without a profile look as before.
- Editors: "Add a profile" or "Edit profile" on any organisation. Logos are fitted inside a 400px square in the browser (not cropped), keeping transparency, and stored in Supabase Storage; only editors can add or remove them.
- Organisations only for now: yacht clubs, teams and events will need their own kinds of profile. Owners and claims come with paid organisation editing in 0.4; until then editors look after organisation profiles.

## 0.3.3 (6 November 2026)

Member roles and member content.

- Your roles, on the profile: members add roles to any team, club, organisation or event in the book, and change (current or past, years) or remove the roles they added. Roles from the editors stay as they are; members use Report an error on their entry.
- If it isn't in the book, members add it: team, yacht club, organisation or event, with an optional country and, for organisations, an optional sector. "Other" is now a twelfth sector, with a short "What does the business do?" that only editors see. Before adding, the app suggests close matches already in the book ("Did you mean…").
- Members never set a source. Every member-added link reads "added by member" and is never a link. Web addresses, emails and handles are refused in anything a member types (roles, names), so links stay on profiles.
- Member content on the map: dotted lines for member-added links, a dashed ring for member-added entries, and "added by member" in entry panels. It's shown by default; "Added by members: shown/hidden" in the legend switches it off.
- Editors: "Mark as checked" on a member-added entry makes it editorial. Editors can still edit or remove anything. (A "Checked" button on members' roles was removed after release: a member's own roles stay theirs to change. Verified roles may come back as a paid feature.)
- Limits: 20 new roles and 10 new entries per member per day. A member-added entry is removed with the last role that uses it.

## 0.3.2 (6 November 2026)

Member profiles.

- Your profile: signed-in members open their profile from their name at the top right. Photo, bio, LinkedIn, Instagram, other social or website, a contact email (separate from the sign-in email) and WhatsApp or mobile.
- Who sees what, one switch per field: name, nationality and roles always; photo, LinkedIn and other social on by default, for everyone; contact email and WhatsApp off by default, and for paid members only once paid membership starts (nobody sees them before then).
- Finish your profile: a checklist above the profile (add a photo, check what's visible, review your bio, see yourself on the map) that goes once done or dismissed. Members signing in by link land on their profile until it's done.
- Photos are cropped to a 400px square JPEG in the browser before upload, which also strips location and camera data, and stored in Supabase Storage. Members can only add or remove their own. A plain silhouette stands in until there's a photo.
- Members' entries on the map now show their profile: photo, "Member since", bio and links, as their switches allow. Members see "Edit your profile" on their own entry.
- The owner can make a member an editor, or remove the role, from the member's entry.
- Send feedback fills in a signed-in member's name.
- Fix (6 Nov, after release): on a slow connection, clicking Save again no longer saves twice. Each form is locked while its save and the reload after it are under way, and the database refuses an exact duplicate link (same entries, role, context and dates).
- Fix (after release): accepting someone who claimed an existing entry no longer duplicates the links the book already has. Roles already in the book show as such in review and are skipped. The 8 duplicate links on David Fuller's entry were removed.
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
