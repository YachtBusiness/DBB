// The Dark Blue Book: media feeds (0.3.45). Reads media outlets' RSS and Atom feeds (websites, Substack, podcasts,
// YouTube channels) and keeps the newest 10 items per feed in public.media_items: headline, link, date, a short
// snippet with no HTML, what it is (article, episode, video) and, for episodes and videos, how long it runs.
// Never the full article or the audio: the Media page links out to the outlet.
//
// Two kinds of caller:
// - the hourly job (public.media_feeds_check, pg_cron + pg_net), with Vault's feeds_secret as x-feeds-secret:
//   reads every feed. A feed failing 6 times in a row is then only tried once a day until it works again.
// - a signed-in editor, from the app:
//   {"action":"test","url":"..."}   finds the feed (a feed address, or a web page or YouTube channel that links to one)
//                                   and returns its title and newest 5 items, without saving anything;
//   {"action":"check","entity":"x"} reads that outlet's feeds now.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { XMLParser } from "npm:fast-xml-parser@4.5.0";

const URL_ = Deno.env.get("SUPABASE_URL")!;
const firstKey = (json: string | undefined) => {
  try { const o = JSON.parse(json || "{}"); return (Object.values(o)[0] as string) || ""; } catch { return ""; }
};
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || firstKey(Deno.env.get("SUPABASE_SECRET_KEYS"));
const PUBLIC = Deno.env.get("SUPABASE_ANON_KEY") || firstKey(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS"));
const UA = "TheDarkBlueBook/1.0 (+https://app.darkbluebook.com/#yacht-racing-media)";
const KEEP = 10;

const ALLOWED = [/^https:\/\/app\.darkbluebook\.com$/, /^https:\/\/([a-z0-9-]+\.)?dbb-2k3\.pages\.dev$/, /^http:\/\/localhost(:\d+)?$/];
const cors = (origin: string) => ({
  "Access-Control-Allow-Origin": ALLOWED.some((r) => r.test(origin)) ? origin : "https://app.darkbluebook.com",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
});
const svc = (path: string, init: RequestInit = {}) =>
  fetch(`${URL_}${path}`, {
    ...init,
    headers: { apikey: SERVICE, Authorization: `Bearer ${SERVICE}`, "Content-Type": "application/json", ...(init.headers || {}) },
  });
async function rpc(name: string, args: unknown = {}) {
  const r = await svc(`/rest/v1/rpc/${name}`, { method: "POST", body: JSON.stringify(args) });
  const t = await r.text();
  if (!r.ok) throw new Error(`${name}: ${t.slice(0, 200)}`);
  return t ? JSON.parse(t) : null;
}

// ---------- text clean-up ----------
const NAMED: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ", ndash: "–", mdash: "—",
  lsquo: "‘", rsquo: "’", ldquo: "“", rdquo: "”", hellip: "…", pound: "£", euro: "€", eacute: "é", egrave: "è", aacute: "á",
  oacute: "ó", uuml: "ü", ouml: "ö", auml: "ä", ccedil: "ç", copy: "©", reg: "®", trade: "™", middot: "·", bull: "•" };
const decode = (s: string) => s
  .replace(/&#x([0-9a-f]+);/gi, (_, h) => { try { return String.fromCodePoint(parseInt(h, 16)); } catch { return ""; } })
  .replace(/&#(\d+);/g, (_, d) => { try { return String.fromCodePoint(parseInt(d, 10)); } catch { return ""; } })
  .replace(/&([a-z]+);/gi, (m, n) => NAMED[n.toLowerCase()] ?? m);
const plain = (html: string) => decode(String(html || "")
  .replace(/<(script|style)[\s\S]*?<\/\1>/gi, " ")
  .replace(/<br\s*\/?>|<\/(p|div|li|h\d)>/gi, " ")
  .replace(/<[^>]+>/g, " "))
  .replace(/\s+/g, " ").trim();
// Substack's standard lines say nothing about the piece
const boiler = (s: string) => ((t: string) => t.charAt(0).toUpperCase() + t.slice(1))(s
  .replace(/^.{0,80}? is a reader-supported publication\. To receive new posts and support my work, consider becoming a free or paid subscriber\.\s*/i, "")
  .replace(/^This is a free preview of a paid episode\. To hear more, visit \S+\s*/i, "")
  .replace(/^(In this episode|During our conversation[^:]*|Covered in this episode)\s*:\s*\*\s*/i, ""));
// one feed can carry another outlet's pieces (Sailing Anarchy's carries Seahorse's): only the feed's own site is kept
const domain = (u: string) => { try { return new URL(u).hostname.replace(/^www\./, "").split(".").slice(-2).join("."); } catch { return ""; } };
const cut = (s: string, n: number) => {
  if (s.length <= n) return s;
  const c = s.slice(0, n + 1), sp = c.lastIndexOf(" ");
  return (sp > n * 0.6 ? c.slice(0, sp) : c.slice(0, n)).replace(/[\s,;:.–—-]+$/, "") + "…";
};
const text = (v: unknown): string => {
  if (v == null) return "";
  if (typeof v === "string" || typeof v === "number") return String(v);
  if (Array.isArray(v)) return text(v[0]);
  if (typeof v === "object") { const o = v as Record<string, unknown>; return text(o["#text"] ?? o["@_href"] ?? ""); }
  return "";
};
const arr = <T>(v: T | T[] | undefined): T[] => v == null ? [] : Array.isArray(v) ? v : [v];
function duration(v: unknown): number | null {
  const s = text(v).trim();
  if (!s) return null;
  if (/^\d+$/.test(s)) return parseInt(s, 10);
  const p = s.split(":").map((x) => parseInt(x, 10));
  if (p.some(isNaN)) return null;
  return p.reduce((a, b) => a * 60 + b, 0);
}

// ---------- parsing ----------
type Item = { guid: string; url: string; title: string; snippet: string; published_at: string; kind: string; duration_s: number | null };
type Parsed = { title: string; items: Item[] };
const parser = new XMLParser({ ignoreAttributes: false, attributeNamePrefix: "@_", textNodeName: "#text", processEntities: true, htmlEntities: true, trimValues: true });

function parseFeed(xml: string, base: string): Parsed | null {
  let doc: Record<string, any>;
  try { doc = parser.parse(xml); } catch { return null; }
  const now = Date.now();
  const when = (s: string) => { const t = Date.parse(s); return isNaN(t) ? null : new Date(Math.min(t, now)).toISOString(); };
  const abs = (u: string) => { try { const x = new URL(u, base); return /^https?:$/.test(x.protocol) ? x.href : ""; } catch { return ""; } };
  const out: Item[] = [];
  if (doc.rss?.channel || doc["rdf:RDF"]) {
    const ch = doc.rss?.channel || doc["rdf:RDF"].channel || {};
    const items = arr(doc.rss?.channel?.item ?? doc["rdf:RDF"]?.item);
    for (const it of items) {
      const url = abs(text(it.link) || (it.guid?.["@_isPermaLink"] !== "false" ? text(it.guid) : ""));
      const title = cut(plain(text(it.title)), 300);
      const published_at = when(text(it.pubDate) || text(it["dc:date"]) || text(it.published));
      if (!url || !title || !published_at) continue;
      const enc = arr(it.enclosure).find((e: any) => /^(audio|video)\//.test(String(e?.["@_type"] || "")));
      const isYT = /youtube\.com|youtu\.be/.test(url);
      out.push({
        guid: cut(text(it.guid) || url, 500), url, title,
        snippet: cut(boiler(plain(text(it.description) || text(it["itunes:summary"]) || text(it["content:encoded"]))), 220),
        published_at,
        kind: enc ? (String(enc["@_type"]).startsWith("video") ? "video" : "episode") : isYT ? "video" : "article",
        duration_s: enc || isYT ? duration(it["itunes:duration"]) : null,
      });
    }
    const site = domain(text(ch.link));
    return { title: cut(plain(text(ch.title)), 200), items: site ? out.filter((i) => domain(i.url) === site) : out };
  }
  if (doc.feed) {
    const f = doc.feed;
    for (const e of arr(f.entry) as any[]) {
      const links = arr(e.link) as any[];
      const href = (links.find((l) => !l["@_rel"] || l["@_rel"] === "alternate") || links[0] || {})["@_href"] || text(e.link);
      const url = abs(String(href || ""));
      const title = cut(plain(text(e.title)), 300);
      const published_at = when(text(e.published) || text(e.updated));
      if (!url || !title || !published_at) continue;
      const isYT = /youtube\.com|youtu\.be/.test(url) || !!e["yt:videoId"];
      if (isYT && (/#shorts\b/i.test(title) || /\/shorts\//.test(url))) continue;
      const desc = text(e["media:group"]?.["media:description"]) || text(e.summary) || text(e.content);
      out.push({ guid: cut(text(e.id) || url, 500), url, title, snippet: cut(plain(desc), 220), published_at,
        kind: isYT ? "video" : "article", duration_s: null });
    }
    return { title: cut(plain(text(f.title)), 200), items: out };
  }
  return null;
}

// a web page (or YouTube channel) that links to its feed
function findFeedLink(html: string, base: string): string {
  const links = [...html.matchAll(/<link\b[^>]*>/gi)].map((m) => m[0]);
  const cands: string[] = [];
  for (const l of links) {
    if (!/rel=["']?alternate/i.test(l) || !/type=["']?application\/(rss|atom)\+xml/i.test(l)) continue;
    const h = l.match(/href=["']([^"']+)["']/i);
    if (h) cands.push(decode(h[1]));
  }
  const pick = cands.find((u) => !/comments/i.test(u)) || cands[0];
  if (!pick) return "";
  try { return new URL(pick, base).href; } catch { return ""; }
}

async function get(url: string, extra: Record<string, string> = {}) {
  const r = await fetch(url, {
    headers: { "User-Agent": UA, Accept: "application/rss+xml, application/atom+xml, application/xml, text/xml, text/html;q=0.8, */*;q=0.5", ...extra },
    redirect: "follow", signal: AbortSignal.timeout(15000),
  });
  if (r.status === 304) return { status: 304, body: "", finalUrl: r.url || url, headers: r.headers };
  const buf = await r.arrayBuffer();
  if (buf.byteLength > 6_000_000) throw new Error("too_big");
  return { status: r.status, body: new TextDecoder().decode(buf), finalUrl: r.url || url, headers: r.headers };
}

// YouTube Shorts are left out (D, 28 Nov 2026): a channel's feed (channel_id=UC...) becomes its long-form uploads
// playlist (playlist_id=UULF...), which has no Shorts; titles tagged #shorts are skipped too
const noShorts = (u: string) => u.replace(/(youtube\.com\/feeds\/videos\.xml\?)channel_id=UC([\w-]{22})/i, "$1playlist_id=UULF$2");

// find and read a feed from what an editor pasted
async function discover(input: string): Promise<{ url: string; parsed: Parsed }> {
  let u = noShorts(input.trim());
  if (!/^https?:\/\//i.test(u)) u = "https://" + u;
  const r = await get(u);
  if (r.status >= 400) throw new Error(`http_${r.status}`);
  const p = parseFeed(r.body, r.finalUrl);
  if (p) return { url: r.finalUrl, parsed: p };
  const link = noShorts(findFeedLink(r.body, r.finalUrl));
  if (!link) throw new Error("no_feed");
  const r2 = await get(link);
  if (r2.status >= 400) throw new Error(`http_${r2.status}`);
  const p2 = parseFeed(r2.body, r2.finalUrl);
  if (!p2) throw new Error("not_a_feed");
  return { url: link, parsed: p2 };
}

type Feed = { id: number; entity_id: string; url: string; etag: string; last_modified: string; fails: number; checked_at: string | null };
async function checkFeed(f: Feed) {
  const patch: Record<string, unknown> = { checked_at: new Date().toISOString() };
  let saved = 0;
  try {
    const cond: Record<string, string> = {};
    if (f.etag) cond["If-None-Match"] = f.etag;
    if (f.last_modified) cond["If-Modified-Since"] = f.last_modified;
    const r = await get(f.url, cond);
    if (r.status === 304) {
      Object.assign(patch, { ok_at: patch.checked_at, error: "", fails: 0 });
    } else {
      if (r.status >= 400) throw new Error(`http_${r.status}`);
      const p = parseFeed(r.body, r.finalUrl);
      if (!p) throw new Error("not_a_feed");
      const items = p.items.sort((a, b) => b.published_at.localeCompare(a.published_at)).slice(0, KEEP)
        .map((i) => ({ ...i, feed_id: f.id, entity_id: f.entity_id, fetched_at: patch.checked_at }));
      // the same guid twice in one feed would break the upsert
      const seen = new Set<string>(); const uniq = items.filter((i) => !seen.has(i.guid) && seen.add(i.guid));
      if (uniq.length) {
        const w = await svc(`/rest/v1/media_items?on_conflict=feed_id,guid`, {
          method: "POST", headers: { Prefer: "resolution=merge-duplicates,return=minimal" }, body: JSON.stringify(uniq) });
        if (!w.ok) throw new Error("save: " + (await w.text()).slice(0, 150));
        saved = uniq.length;
      }
      await rpc("media_items_prune", { p_feed: f.id });
      Object.assign(patch, { ok_at: patch.checked_at, error: "", fails: 0, title: p.title || undefined,
        etag: r.headers.get("etag") || "", last_modified: r.headers.get("last-modified") || "" });
      if (!patch.title) delete patch.title;
    }
  } catch (e) {
    Object.assign(patch, { error: String((e as Error).message || e).slice(0, 200), fails: (f.fails || 0) + 1 });
  }
  await svc(`/rest/v1/media_feeds?id=eq.${f.id}`, { method: "PATCH", body: JSON.stringify(patch) });
  return { id: f.id, entity: f.entity_id, saved, error: (patch.error as string) || "" };
}

async function checkAll(filter = "") {
  const r = await svc(`/rest/v1/media_feeds?select=id,entity_id,url,etag,last_modified,fails,checked_at${filter}`);
  const feeds: Feed[] = r.ok ? await r.json() : [];
  const day = Date.now() - 23 * 3600e3;
  const due = filter ? feeds : feeds.filter((f) => f.fails < 6 || !f.checked_at || Date.parse(f.checked_at) < day);
  const out = [];
  for (let i = 0; i < due.length; i += 4) out.push(...await Promise.all(due.slice(i, i + 4).map(checkFeed)));
  return out;
}

Deno.serve(async (req) => {
  const h = { ...cors(req.headers.get("origin") || ""), "Content-Type": "application/json" };
  const reply = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: h });
  if (req.method === "OPTIONS") return new Response("ok", { headers: h });
  if (req.method !== "POST") return reply(405, { error: "method" });

  // the hourly job
  const key = req.headers.get("x-feeds-secret") || "";
  if (key) {
    if (!(await rpc("feeds_key_ok", { p_key: key }))) return reply(403, { error: "bad_key" });
    const res = await checkAll();
    return reply(200, { checked: res.length, failed: res.filter((x) => x.error).length });
  }

  // a signed-in editor
  const tok = (req.headers.get("authorization") || "").replace(/^Bearer\s+/i, "");
  if (!tok) return reply(401, { error: "not_signed_in" });
  const u = await fetch(`${URL_}/auth/v1/user`, { headers: { apikey: PUBLIC, Authorization: `Bearer ${tok}` } });
  if (!u.ok) return reply(401, { error: "not_signed_in" });
  const caller = await u.json();
  const ed = await svc(`/rest/v1/editors?select=user_id&user_id=eq.${encodeURIComponent(caller.id)}`);
  if (!ed.ok || !(await ed.json()).length) return reply(403, { error: "not_editor" });

  let body: { action?: string; url?: string; entity?: string };
  try { body = await req.json(); } catch { return reply(400, { error: "bad_request" }); }
  if (body.action === "test") {
    const input = String(body.url || "").slice(0, 500);
    if (!input) return reply(400, { error: "no_url" });
    try {
      const d = await discover(input);
      const items = d.parsed.items.sort((a, b) => b.published_at.localeCompare(a.published_at)).slice(0, 5);
      return reply(200, { url: d.url, title: d.parsed.title, count: d.parsed.items.length, items });
    } catch (e) { return reply(200, { error: String((e as Error).message || e).slice(0, 120) }); }
  }
  if (body.action === "check") {
    const id = String(body.entity || "");
    if (!/^[a-z0-9-]{1,60}$/i.test(id)) return reply(400, { error: "bad_request" });
    return reply(200, { results: await checkAll(`&entity_id=eq.${encodeURIComponent(id)}`) });
  }
  return reply(400, { error: "bad_request" });
});
