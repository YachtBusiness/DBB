// The Dark Blue Book: welcome email for a newly accepted member, sent through Resend.
// Called by the app straight after an editor accepts an application. Only editors can call it.
// Needs the RESEND_API_KEY secret. Sends once per member unless {again: true}.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const URL_ = Deno.env.get("SUPABASE_URL")!;
const firstKey = (json: string | undefined) => {
  try { const o = JSON.parse(json || "{}"); return (Object.values(o)[0] as string) || ""; } catch { return ""; }
};
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || firstKey(Deno.env.get("SUPABASE_SECRET_KEYS"));
const PUBLIC = Deno.env.get("SUPABASE_ANON_KEY") || firstKey(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS"));
const RESEND = Deno.env.get("RESEND_API_KEY") || "";
const FROM = Deno.env.get("WELCOME_FROM") || "Dave at The Dark Blue Book <no-reply@darkbluebook.com>";
const REPLY_TO = Deno.env.get("WELCOME_REPLY_TO") || "editor@darkbluebook.com";
const APP = "https://app.darkbluebook.com/";

const ALLOWED = [/^https:\/\/app\.darkbluebook\.com$/, /^https:\/\/([a-z0-9-]+\.)?dbb-2k3\.pages\.dev$/];
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
const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));

function compose(name: string, entityId: string) {
  const first = name.trim().split(/\s+/)[0] || "there";
  const link = APP + (entityId ? "#" + encodeURIComponent(entityId) : "");
  const subject = "Welcome to The Dark Blue Book";
  const text = `Hi ${first},

Your application's been accepted, welcome aboard. You're now on the map: ${link}

Sign in to finish your profile: add a photo and choose which contact details other members can see.

You're one of our first members, so some things are still being worked out. If something's missing, wrong or annoying, tell us: use Send feedback in the app or just reply to this email.

Dave
Editor, The Dark Blue Book`;
  const p = "margin:0 0 16px";
  const html = `<!doctype html><html><body style="margin:0;padding:24px;background:#eef1f7;font-family:Georgia,'Times New Roman',serif;color:#0e1d3a">
<div style="max-width:560px;margin:0 auto;background:#ffffff;border-radius:6px;overflow:hidden">
<div style="background:#12264d;color:#f2f5fb;padding:18px 24px;font-size:22px;font-weight:600">The Dark Blue Book</div>
<div style="padding:24px;font-size:16px;line-height:1.5">
<p style="${p}">Hi ${esc(first)},</p>
<p style="${p}">Your application's been accepted, welcome aboard. You're now on the map: <a href="${esc(link)}" style="color:#1d5fc4">see your entry</a>.</p>
<p style="${p}">Sign in to finish your profile: add a photo and choose which contact details other members can see.</p>
<p style="${p}">You're one of our first members, so some things are still being worked out. If something's missing, wrong or annoying, tell us: use Send feedback in the app or just reply to this email.</p>
<p style="margin:0">Dave<br>Editor, The Dark Blue Book</p>
</div></div></body></html>`;
  return { subject, text, html };
}

Deno.serve(async (req) => {
  const h = { ...cors(req.headers.get("origin") || ""), "Content-Type": "application/json" };
  const reply = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: h });
  if (req.method === "OPTIONS") return new Response("ok", { headers: h });
  if (req.method !== "POST") return reply(405, { error: "method" });

  // the caller must be a signed-in editor
  const tok = (req.headers.get("authorization") || "").replace(/^Bearer\s+/i, "");
  if (!tok) return reply(401, { error: "not_signed_in" });
  const u = await fetch(`${URL_}/auth/v1/user`, { headers: { apikey: PUBLIC, Authorization: `Bearer ${tok}` } });
  if (!u.ok) return reply(401, { error: "not_signed_in" });
  const caller = await u.json();
  const ed = await svc(`/rest/v1/editors?select=user_id&user_id=eq.${encodeURIComponent(caller.id)}`);
  if (!ed.ok || !(await ed.json()).length) return reply(403, { error: "not_editor" });

  let body: { user_id?: string; again?: boolean };
  try { body = await req.json(); } catch { return reply(400, { error: "bad_request" }); }
  const id = String(body.user_id || "");
  if (!/^[0-9a-f-]{36}$/i.test(id)) return reply(400, { error: "bad_request" });

  const r = await svc(`/rest/v1/members?select=name,email,status,entity_id,welcome_sent_at&user_id=eq.${id}`);
  const m = r.ok ? (await r.json())[0] : null;
  if (!m) return reply(404, { error: "no_member" });
  if (m.status !== "member") return reply(400, { error: "not_accepted" });
  if (m.welcome_sent_at && !body.again) return reply(200, { result: "already", sent_at: m.welcome_sent_at });
  if (!RESEND) return reply(503, { error: "not_configured" });

  const mail = compose(m.name, m.entity_id || "");
  const s = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${RESEND}`,
      "Content-Type": "application/json",
      ...(body.again ? {} : { "Idempotency-Key": `welcome-${id}` }),
    },
    body: JSON.stringify({ from: FROM, to: [m.email], reply_to: REPLY_TO, subject: mail.subject, text: mail.text, html: mail.html }),
  });
  const sj = await s.json().catch(() => ({}));
  if (!s.ok) return reply(502, { error: "send_failed", detail: String(sj.message || sj.name || s.status).slice(0, 300) });

  const now = new Date().toISOString();
  await svc(`/rest/v1/members?user_id=eq.${id}`, { method: "PATCH", body: JSON.stringify({ welcome_sent_at: now }) });
  return reply(200, { result: "sent", sent_at: now, to: m.email });
});
