-- SANDBOX ONLY (dbb-sandbox). Yachting Ventures Startup Directory demo for the 1 Dec 2026 call.
-- Needs migration 20261127000001_communities.sql. Safe to re-run. A sandbox book refresh (refresh_from_live.sql)
-- deletes the community's people and startups, so re-run this afterwards.
-- Startups and founders are real Yachting Ventures members, using only facts from their own sites and press coverage.
-- Fields marked sample (stage aside) hold demo values, shown with a "sample" tag in the directory.

insert into public.communities (id, name, product, tagline, about, website, join_url, book_entity_id, brand) values
('yv', 'Yachting Ventures', 'Startup Directory',
 'Discover the startups and scaleups building the future of leisure marine.',
 'Yachting Ventures supports startups and scaleups in leisure marine with community, marketing, fundraising and events. Every member is personally reviewed before joining.',
 'https://www.yachtingventures.co', 'https://www.yachtingventures.co', 'yachtingventures',
 '{"ink":"#0c2f45","primary":"#0f4c6e","accent":"#1fa7a0","soft":"#e7f4f3","wordmark":"Yachting Ventures"}')
on conflict (id) do update set name = excluded.name, product = excluded.product, tagline = excluded.tagline, about = excluded.about,
  website = excluded.website, join_url = excluded.join_url, book_entity_id = excluded.book_entity_id, brand = excluded.brand;

-- Directory fields
delete from public.community_fields where community_id = 'yv';
insert into public.community_fields (community_id, key, label, applies_to, type, options, visibility, filter, sample, sort) values
('yv','sector','Sector','startup','select','{"Electric propulsion","Boats & foiling","Marina & charter software","Crew & yacht operations","Marine finance","Robotics & autonomy","Safety & navigation"}','public',true,false,10),
('yv','hq','Based in','startup','text','{}','public',false,false,20),
('yv','founded','Founded','startup','year','{}','public',false,false,30),
('yv','stage','Stage','startup','select','{"Pre-seed","Seed","Series A","Growth"}','members',true,false,40),
('yv','funding','Funding to date (public reports)','startup','text','{}','members',false,false,50),
('yv','looking_for','Looking for','startup','multi','{"Investors","Distribution partners","Boatbuilder partners","Pilot customers","Hires"}','members',true,true,60),
('yv','raising','Raising now','startup','bool','{}','investors',true,true,70),
('yv','round','Round','startup','text','{}','investors',false,true,80),
('yv','deck','Pitch deck','startup','url','{}','investors',false,true,90),
('yv','yv_programme','YV programme','startup','text','{}','admins',false,true,100),
('yv','yv_notes','Team notes','startup','longtext','{}','admins',false,true,110),
('yv','person_role','Role in the community','person','text','{}','public',false,false,200);

-- Startups (new entries are community-only until they opt in to the book)
insert into public.entities (id, name, type, sectors, country, website, about, status, origin) values
('zerojet','ZeroJet','org','{supplier}','NZL','https://www.zerojet.com','Turnkey electric jet propulsion for small boats and tenders, built in New Zealand and fitted by boatbuilders including Highfield.','community','community'),
('metarina','Metarina','org','{supplier}','DEU','https://www.metarina.com','Marina management software covering occupancy planning, booking, billing and analytics, linking marinas with boaters.','community','community'),
('ripple-boats','Ripple Boats','org','{}','NOR','https://www.rippleboats.com','Long-range electric leisure boats using Pascal Technologies'' air-cushion hull, built with Norwegian yard Frydenbø Marine.','community','community'),
('visionanchor','VisionAnchor','org','{supplier}','SVN','https://visionanchor.net','A smart buoy that tracks the anchor itself, not just the boat, and alerts the crew''s phone when it drags.','community','community'),
('crewdentials','Crewdentials','org','{supplier}','','https://www.crewdentials.co','Credential management and verification for yacht crew and the managers who hire them.','community','community'),
('salt-finance','SALT','org','{}','GBR','https://www.salt-finance.com','Boat finance through an app and a panel of lenders, plus BoatsOnFinance.com for searching boats by monthly budget.','community','community'),
('ankor','Ankor Software','org','{supplier}','AUS','https://ankor.io','Software for the superyacht charter market: shared availability calendars, itineraries and AnkorPay for onboard payments.','community','community'),
('sevenstar','Sevenstar','org','{supplier}','CAN','','Digital guest-preference and provisioning software for interior crew on private and charter yachts.','community','community'),
('floatist','Floatist','org','{supplier}','AND','https://www.floatist.com','Fleet and charter operations software: mobile check-in and check-out, maintenance, inventory and team scheduling.','community','community'),
('edorado','Edorado','org','{}','NLD','https://www.edoradomarine.com','Zero-emission electric powerboats on retractable hydrofoils, led by the Edorado 8S.','community','community'),
('hullbot','Hullbot','org','{supplier}','AUS','https://www.hullbot.com','Autonomous underwater robots that clean and inspect hulls early and often, cutting fuel use without biocidal paint.','community','community'),
('charter-itinerary','Charter Itinerary','org','{supplier}','ESP','https://www.charteritinerary.com','Digital trip planning and preparation for superyacht charter guests and the brokers who serve them.','community','community'),
('envgo','ENVGO','org','{}','CAN','https://www.envgo.com','Electric hydrofoil boats, starting with the NV1 cruiser, plus electrification and autonomy systems for other builders.','community','community'),
('seabird-tech','Seabird Technologies','org','{supplier}','GBR','https://www.seabirdtechnologies.com','Electric marine propulsion, born out of building the RaceBird electric foiling raceboat for the E1 championship.','community','community')
on conflict (id) do update set name = excluded.name, country = excluded.country, website = excluded.website, about = excluded.about
  where public.entities.origin = 'community';

-- Founders and leaders
insert into public.entities (id, name, type, country, status, origin) values
('mans-n','Neil Mans','person','NZL','community','community'),('rempel-b','Bex Rempel','person','NZL','community','community'),
('hooper-h','Henry Hooper','person','','community','community'),('kienzle-n','Nicola Kienzle','person','','community','community'),('entrup-l','Leon Entrup','person','','community','community'),
('gulla-s','Stian Gulla','person','NOR','community','community'),
('jasarov-m','Matija Jašarov','person','SVN','community','community'),('peklenk-a','Anže Peklenk','person','SVN','community','community'),('podbevsek-a','Andrej Podbevšek','person','SVN','community','community'),
('armsden-d','Dan Armsden','person','GBR','community','community'),
('dalton-j','Joe Dalton','person','GBR','community','community'),('shiells-d','Damien Shiells','person','GBR','community','community'),
('sager-m','Mike Sager','person','AUS','community','community'),('cousins-e','Elliot Cousins','person','AUS','community','community'),
('farrow-c','Ciara Farrow','person','CAN','community','community'),
('allis-c','Cindy Allis','person','','community','community'),('yera-gomez-a','Albert Yera Gomez','person','','community','community'),
('groothuis-g','Giel Groothuis','person','NLD','community','community'),('van-hardenbroek-g','Godert van Hardenbroek','person','NLD','community','community'),
('loefler-t','Tom Loefler','person','AUS','community','community'),('watfern-k','Karl Watfern','person','AUS','community','community'),
('de-bel-b','Boris De Bel','person','','community','community'),('christiansen-c','Candice Christiansen','person','','community','community'),
('peasgood-m','Mike Peasgood','person','CAN','community','community'),('masojc-p','Paul Masojc','person','CAN','community','community'),
('morin-m','Matthew Morin','person','USA','community','community'),
('horne-s','Sophi Horne','person','','community','community')
on conflict (id) do nothing;

insert into public.links (id, from_id, to_id, role, cat, source, status, origin) values
('yv-mans-zerojet','mans-n','zerojet','Co-founder and CTO','ppl','ZeroJet','community','community'),
('yv-rempel-zerojet','rempel-b','zerojet','Co-founder','ppl','ZeroJet','community','community'),
('yv-hooper-metarina','hooper-h','metarina','Co-founder','ppl','Metarina','community','community'),
('yv-kienzle-metarina','kienzle-n','metarina','Co-founder','ppl','Metarina','community','community'),
('yv-entrup-metarina','entrup-l','metarina','Co-founder and CTO','ppl','Metarina','community','community'),
('yv-gulla-ripple','gulla-s','ripple-boats','CEO','ppl','Ripple Boats','community','community'),
('yv-jasarov-va','jasarov-m','visionanchor','Co-founder and CEO','ppl','VisionAnchor','community','community'),
('yv-peklenk-va','peklenk-a','visionanchor','Co-founder and CTO','ppl','VisionAnchor','community','community'),
('yv-podbevsek-va','podbevsek-a','visionanchor','Co-founder and CMO','ppl','VisionAnchor','community','community'),
('yv-armsden-crewd','armsden-d','crewdentials','Co-founder','ppl','Crewdentials','community','community'),
('yv-dalton-salt','dalton-j','salt-finance','Founder and CEO','ppl','SALT','community','community'),
('yv-shiells-salt','shiells-d','salt-finance','CTO','ppl','SALT','community','community'),
('yv-sager-ankor','sager-m','ankor','Co-founder and Co-CEO','ppl','Ankor Software','community','community'),
('yv-cousins-ankor','cousins-e','ankor','Co-founder and Co-CEO','ppl','Ankor Software','community','community'),
('yv-farrow-7star','farrow-c','sevenstar','Founder','ppl','Sevenstar','community','community'),
('yv-allis-floatist','allis-c','floatist','Co-founder and CEO','ppl','Floatist','community','community'),
('yv-yera-floatist','yera-gomez-a','floatist','Co-founder and CTO','ppl','Floatist','community','community'),
('yv-groothuis-edo','groothuis-g','edorado','Co-founder and CEO','ppl','Edorado','community','community'),
('yv-vanh-edo','van-hardenbroek-g','edorado','Co-founder and Product Architect','ppl','Edorado','community','community'),
('yv-loefler-hullbot','loefler-t','hullbot','Co-founder and CEO','ppl','Hullbot','community','community'),
('yv-watfern-hullbot','watfern-k','hullbot','Co-founder','ppl','Hullbot','community','community'),
('yv-debel-ci','de-bel-b','charter-itinerary','Co-founder','ppl','Charter Itinerary','community','community'),
('yv-christiansen-ci','christiansen-c','charter-itinerary','Co-founder','ppl','Charter Itinerary','community','community'),
('yv-peasgood-envgo','peasgood-m','envgo','Co-founder and CEO','ppl','ENVGO','community','community'),
('yv-masojc-envgo','masojc-p','envgo','Co-founder and COO','ppl','ENVGO','community','community'),
('yv-morin-m-robobuoy','morin-m','robobuoy','Co-founder','ppl','MarkSetBot','community','community'),
('yv-horne-seabird','horne-s','seabird-tech','Founder and Chairman','ppl','Seabird Technologies','community','community')
on conflict (id) do nothing;

-- Directory membership (Robobuoy, Kevin Morin and Gabbi Richardson are already in the book and have opted in)
delete from public.community_members where community_id = 'yv';
insert into public.community_members (community_id, entity_id, kind, featured, share_with_book, joined_at)
select 'yv', id, 'startup', id in ('hullbot','floatist','robobuoy'), id = 'robobuoy', date '2024-01-01'
from public.entities where id in ('zerojet','metarina','ripple-boats','visionanchor','crewdentials','salt-finance','ankor','sevenstar','floatist','edorado','hullbot','charter-itinerary','envgo','seabird-tech','robobuoy');
insert into public.community_members (community_id, entity_id, kind, share_with_book)
select 'yv', id, 'person', id in ('richardson','morin-k') from public.entities
where id in ('richardson','morin-k','mans-n','rempel-b','hooper-h','kienzle-n','entrup-l','gulla-s','jasarov-m','peklenk-a','podbevsek-a','armsden-d','dalton-j','shiells-d','sager-m','cousins-e','farrow-c','allis-c','yera-gomez-a','groothuis-g','van-hardenbroek-g','loefler-t','watfern-k','de-bel-b','christiansen-c','peasgood-m','masojc-p','morin-m','horne-s');
-- the YV team itself, so Gabbi shows with her role
update public.community_members set featured = true where community_id = 'yv' and entity_id = 'richardson';

-- Values. sector/hq/founded/stage/funding come from public sources; the rest are sample values.
insert into public.community_values (community_id, entity_id, key, value)
select 'yv', v.e, v.k, v.val::jsonb from (values
('zerojet','sector','"Electric propulsion"'),('zerojet','hq','"Auckland, New Zealand"'),('zerojet','founded','2015'),('zerojet','stage','"Seed"'),('zerojet','funding','"Seed capital raised in 2020; UK sales office opened in Southampton"'),
('metarina','sector','"Marina & charter software"'),('metarina','hq','"Germany"'),('metarina','stage','"Growth"'),('metarina','funding','"Named Scale-Up of the Year 2025 at the Smart and Sustainable Marina Rendezvous"'),
('ripple-boats','sector','"Boats & foiling"'),('ripple-boats','hq','"Oslo, Norway"'),('ripple-boats','founded','2023'),('ripple-boats','stage','"Seed"'),
('visionanchor','sector','"Safety & navigation"'),('visionanchor','hq','"Slovenia"'),('visionanchor','stage','"Pre-seed"'),('visionanchor','funding','"€400k from Techstars, EIT Digital, EUSPA and others; won the YV and EBI pitch competition at boot Düsseldorf 2025"'),
('crewdentials','sector','"Crew & yacht operations"'),('crewdentials','stage','"Seed"'),
('salt-finance','sector','"Marine finance"'),('salt-finance','hq','"London, United Kingdom"'),('salt-finance','founded','2021'),('salt-finance','stage','"Seed"'),('salt-finance','funding','"FCA-authorised for consumer lending (2024); second funding round in 2024"'),
('ankor','sector','"Marina & charter software"'),('ankor','hq','"Australia"'),('ankor','founded','2021'),('ankor','stage','"Growth"'),
('sevenstar','sector','"Crew & yacht operations"'),('sevenstar','hq','"Canada"'),('sevenstar','founded','2023'),('sevenstar','stage','"Pre-seed"'),
('floatist','sector','"Marina & charter software"'),('floatist','hq','"Andorra"'),('floatist','founded','2022'),('floatist','stage','"Seed"'),('floatist','funding','"€500k raised in 2025; over 600 yachts on the platform"'),
('edorado','sector','"Boats & foiling"'),('edorado','hq','"Amsterdam, Netherlands"'),('edorado','founded','2014'),('edorado','stage','"Seed"'),('edorado','funding','"€1.75m bridge round opened for the Edorado 8S"'),
('hullbot','sector','"Robotics & autonomy"'),('hullbot','hq','"Sydney, Australia"'),('hullbot','founded','2015'),('hullbot','stage','"Series A"'),('hullbot','funding','"A$16m Series A (Nov 2025)"'),
('charter-itinerary','sector','"Marina & charter software"'),('charter-itinerary','hq','"Mallorca, Spain"'),('charter-itinerary','stage','"Seed"'),
('envgo','sector','"Boats & foiling"'),('envgo','hq','"Waterloo, Canada"'),('envgo','founded','2021'),('envgo','stage','"Seed"'),('envgo','funding','"US$2m seed (2025), further seed funding in 2026"'),
('seabird-tech','sector','"Electric propulsion"'),('seabird-tech','hq','"London, United Kingdom"'),('seabird-tech','stage','"Growth"'),
('robobuoy','sector','"Robotics & autonomy"'),('robobuoy','hq','"United States"'),('robobuoy','stage','"Growth"'),('robobuoy','funding','"Robotic marks supplier to the America''s Cup and SailGP"'),
-- sample values
('zerojet','looking_for','["Boatbuilder partners","Distribution partners"]'),('zerojet','raising','true'),('zerojet','round','"Sample: Series A, opening Q1"'),('zerojet','yv_programme','"Sample: Startup Zone, METSTRADE"'),
('visionanchor','looking_for','["Investors","Distribution partners"]'),('visionanchor','raising','true'),('visionanchor','round','"Sample: pre-seed follow-on"'),
('floatist','looking_for','["Pilot customers","Hires"]'),('floatist','raising','false'),
('envgo','looking_for','["Boatbuilder partners","Investors"]'),('envgo','raising','true'),('envgo','round','"Sample: seed extension"'),
('edorado','looking_for','["Investors"]'),('edorado','raising','true'),('edorado','round','"Sample: bridge to Series A"'),
('salt-finance','looking_for','["Distribution partners"]'),('salt-finance','raising','false'),
('hullbot','looking_for','["Pilot customers","Hires"]'),('hullbot','raising','false'),
('sevenstar','looking_for','["Pilot customers","Investors"]'),('sevenstar','raising','true'),('sevenstar','round','"Sample: pre-seed"'),
('ankor','looking_for','["Distribution partners"]'),
('metarina','looking_for','["Pilot customers"]'),
('hullbot','yv_notes','"Sample: intro to two superyacht management companies requested."'),
('richardson','person_role','"Founder and CEO, Yachting Ventures"')
) v(e, k, val)
where exists (select 1 from public.community_members m where m.community_id = 'yv' and m.entity_id = v.e);

-- Demo accounts (sandbox only; the password is shown on the demo's sign-in panel)
do $$
declare acct record; uid uuid;
begin
  for acct in select * from (values
    ('yv-admin@example.com','admin','YV team (demo)', '{}'::text[]),
    ('yv-investor@example.com','investor','Investor (demo)', '{}'::text[]),
    ('yv-founder@example.com','member','ZeroJet founder (demo)', '{zerojet}'::text[])) a(email, role, label, manages)
  loop
    select id into uid from auth.users where email = acct.email;
    if uid is null then
      uid := gen_random_uuid();
      insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
        created_at, updated_at, confirmation_token, recovery_token, email_change, email_change_token_new, email_change_token_current, phone_change, phone_change_token, reauthentication_token)
      values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', acct.email, extensions.crypt('yv-demo-2026', extensions.gen_salt('bf')), now(),
        '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '', '', '', '', '');
      insert into auth.identities (id, user_id, provider, provider_id, identity_data, created_at, updated_at, last_sign_in_at)
      values (gen_random_uuid(), uid, 'email', uid::text, jsonb_build_object('sub', uid::text, 'email', acct.email, 'email_verified', true), now(), now(), now());
    end if;
    insert into public.community_users (community_id, user_id, role, label, manages) values ('yv', uid, acct.role, acct.label, acct.manages)
    on conflict (community_id, user_id) do update set role = excluded.role, label = excluded.label, manages = excluded.manages;
  end loop;
end $$;
