/* The Dark Blue Book: pages built on Cloudflare's side, readable without JavaScript (0.3.25).
   /news      every news story as plain HTML, for search engines, AI tools and anyone without JavaScript
   /news.xml  the same stories as an RSS feed
   Only these paths reach this worker (see _routes.json); everything else is served as static files.
   Live and preview read the live book; any other address reads the sandbox, as the app does. */
const LIVE_HOSTS = ['app.darkbluebook.com', 'preview.dbb-2k3.pages.dev', 'dbb-2k3.pages.dev'];
const DB = {
  live: ['https://mntfwjwjcfdanxfpipgm.supabase.co', 'sb_publishable_XfrmGdoOfFhWgK0ybagpdA_MxfVZauP'],
  sandbox: ['https://kttiojuuynaznqrcwbyy.supabase.co', 'sb_publishable_x3NTVTSCTWkt3aaYtsncwA__-Xd-tt2'],
};
const APP = 'https://app.darkbluebook.com/';
const KINDS = { person: 'Person', team: 'Team', club: 'Yacht club', org: 'Organisation', event: 'Event', entry: 'Entry', class: 'Boat class', venue: 'Venue', record: 'Record' };
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const host = (u) => { try { return new URL(u).hostname.replace(/^www\./, ''); } catch { return ''; } };
const day = (d) => d ? new Date(d + 'T12:00:00Z').toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC' }) : '';

async function stories(hostname) {
  const [url, key] = LIVE_HOSTS.includes(hostname) ? DB.live : DB.sandbox;
  const r = await fetch(`${url}/rest/v1/stories?select=id,url,title,published,created_at,story_entities(entities(id,name,type))&limit=500`,
    { headers: { apikey: key } });
  if (!r.ok) throw new Error('stories ' + r.status);
  const rows = await r.json();
  return rows.map((s) => ({
    ...s,
    ents: (s.story_entities || []).map((t) => t.entities).filter(Boolean).sort((a, b) => a.name.localeCompare(b.name)),
  })).sort((a, b) => (b.published || '').localeCompare(a.published || '') || (b.created_at || '').localeCompare(a.created_at || ''));
}

function html(list) {
  const items = list.map((s) => {
    const h = host(s.url), d = day(s.published);
    const ents = s.ents.map((e) => `<a href="${APP}#${encodeURIComponent(e.id)}">${esc(e.name)}</a> <span class="k">${esc(KINDS[e.type] || '')}</span>`).join(', ');
    return `<li><article><h2><a href="${esc(s.url)}" rel="noopener">${esc(s.title || h || 'Read the story')}</a></h2>
<p class="m">${[d && `<time datetime="${esc(s.published)}">${esc(d)}</time>`, h && esc(h)].filter(Boolean).join(' · ')}</p>
${ents ? `<p class="t">In the book: ${ents}</p>` : ''}</article></li>`;
  }).join('\n');
  const ld = {
    '@context': 'https://schema.org', '@type': 'ItemList', name: 'Yacht racing news from The Dark Blue Book',
    itemListElement: list.slice(0, 100).map((s, i) => ({
      '@type': 'ListItem', position: i + 1,
      item: { '@type': 'NewsArticle', headline: s.title || host(s.url), url: s.url, ...(s.published ? { datePublished: s.published } : {}),
        about: s.ents.map((e) => ({ '@type': e.type === 'person' ? 'Person' : 'Organization', name: e.name, url: `${APP}#${e.id}` })) },
    })),
  };
  return `<!doctype html><html lang="en-GB"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Yacht racing news · The Dark Blue Book</title>
<meta name="description" content="The latest yacht racing news linked to the people, teams, clubs, organisations and events in The Dark Blue Book, the who’s who of yacht racing. Newest first.">
<link rel="canonical" href="${APP}news"><link rel="alternate" type="application/rss+xml" title="The Dark Blue Book: yacht racing news" href="${APP}news.xml">
<link rel="icon" href="/icons/icon-32.png" sizes="32x32"><meta name="theme-color" content="#12264d">
<meta property="og:title" content="Yacht racing news · The Dark Blue Book"><meta property="og:type" content="website"><meta property="og:url" content="${APP}news"><meta property="og:image" content="${APP}og.jpg"><meta property="og:image:width" content="1200"><meta property="og:image:height" content="630"><meta name="twitter:card" content="summary_large_image">
<script type="application/ld+json">${JSON.stringify(ld).replace(/</g, '\\u003c')}</script>
<style>
:root{--navy:#12264d;--ink:#0e1d3a;--muted:#5a6680;--line:#dde3ee;--bg:#f6f8fc;--surface:#fff;--link:#1d5fc4}
@media (prefers-color-scheme:dark){:root{--ink:#e8edf7;--muted:#9aa6bf;--line:#2a3550;--bg:#0b1428;--surface:#111d36;--link:#8db4ff}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif}
header{background:var(--navy);color:#f2f5fb;padding:16px}header a{color:inherit;text-decoration:none}header .b{font:600 22px Georgia,serif}header p{margin:2px 0 0;opacity:.75;font-size:13px}
main{max-width:760px;margin:0 auto;padding:20px 16px 48px}h1{font:600 28px Georgia,serif;margin:8px 0 4px}.n{color:var(--muted);margin:0 0 20px}
ol{list-style:none;margin:0;padding:0}li{background:var(--surface);border:1px solid var(--line);border-radius:8px;padding:14px 16px;margin:0 0 12px}
h2{font-size:17px;margin:0}a{color:var(--link)}h2 a{color:var(--ink)}.m{margin:4px 0 0;color:var(--muted);font-size:13px}.t{margin:6px 0 0;font-size:14px}.k{color:var(--muted);font-size:12px}
.app{display:inline-block;margin:0 8px 8px 0;padding:8px 14px;border-radius:6px;background:var(--navy);color:#fff;text-decoration:none;font-size:14px}
footer{color:var(--muted);font-size:13px;margin-top:24px}
</style></head><body>
<header><a href="${APP}"><div class="b">The Dark Blue Book</div><p>The who’s who of yacht racing</p></a></header>
<main><h1>Yacht racing news</h1>
<p class="n">Stories about the people, teams, clubs, organisations and events in The Dark Blue Book, newest first. ${list.length} ${list.length === 1 ? 'story' : 'stories'}.</p>
<p><a class="app" href="${APP}#yacht-racing-news">Open in the app</a><a class="app" href="${APP}news.xml">RSS feed</a></p>
<ol>
${items || '<li>No stories yet.</li>'}
</ol>
<footer>Updated ${esc(new Date().toUTCString())}. The book: <a href="${APP}">app.darkbluebook.com</a> · <a href="${APP}privacy">Privacy</a></footer>
</main></body></html>`;
}

function rss(list) {
  const items = list.slice(0, 100).map((s) => {
    const names = s.ents.map((e) => e.name).join(', ');
    const desc = (names ? `In The Dark Blue Book: ${names}.` : '') + (host(s.url) ? ` Source: ${host(s.url)}.` : '');
    const date = s.published ? new Date(s.published + 'T12:00:00Z') : new Date(s.created_at || Date.now());
    return `<item><title>${esc(s.title || host(s.url))}</title><link>${esc(s.url)}</link><guid isPermaLink="false">dbb-story-${esc(s.id)}</guid><pubDate>${date.toUTCString()}</pubDate><description>${esc(desc.trim())}</description>${s.ents.map((e) => `<category>${esc(e.name)}</category>`).join('')}</item>`;
  }).join('\n');
  return `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom"><channel>
<title>The Dark Blue Book: yacht racing news</title><link>${APP}news</link>
<atom:link href="${APP}news.xml" rel="self" type="application/rss+xml"/>
<description>Yacht racing news linked to the people, teams, clubs, organisations and events in The Dark Blue Book.</description>
<language>en-gb</language><lastBuildDate>${new Date().toUTCString()}</lastBuildDate>
${items}
</channel></rss>`;
}

export default {
  async fetch(request, env, ctx) {
    const u = new URL(request.url);
    const path = u.pathname.replace(/\/+$/, '') || '/';
    if (path !== '/news' && path !== '/news.xml') return env.ASSETS.fetch(request);
    const cache = caches.default, key = new Request(u.origin + path);
    const hit = await cache.match(key);
    if (hit) return hit;
    let res;
    try {
      const list = await stories(u.hostname);
      res = path === '/news.xml'
        ? new Response(rss(list), { headers: { 'Content-Type': 'application/rss+xml; charset=utf-8' } })
        : new Response(html(list), { headers: { 'Content-Type': 'text/html; charset=utf-8' } });
      res.headers.set('Cache-Control', 'public, max-age=600');
      if (u.hostname !== 'app.darkbluebook.com') res.headers.set('X-Robots-Tag', 'noindex'); // only the live address is indexed
      ctx.waitUntil(cache.put(key, res.clone()));
    } catch (e) {
      res = new Response('The news could not be loaded just now. Please try again in a moment.', { status: 503, headers: { 'Content-Type': 'text/plain; charset=utf-8', 'Retry-After': '60' } });
    }
    return res;
  },
};
