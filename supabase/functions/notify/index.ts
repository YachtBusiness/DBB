// The Dark Blue Book: organisation invitations and claim emails, sent through Resend.
//  - kind "invite": an owner (or editor) invites a member to manage an organisation's profile, by email.
//    The invitation is stored by public.invite_manager and the invited member is emailed. The answer to the
//    owner is the same whether or not that email belongs to a member.
//  - kind "claim_approved": after an editor approves a claim, the member is emailed.
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
  fetch(`${URL_}${path}`, { ...init, headers: { apikey: SERVICE, Authorization: `Bearer ${SERVICE}`, "Content-Type": "application/json", ...(init.headers || {}) } });
const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));
const first = (n: string) => n.trim().split(/\s+/)[0] || "there";

async function send(to: string, subject: string, paras: string[]) {
  if (!RESEND) return "not_configured";
  const text = paras.join("\n\n") + "\n\nDave\nEditor, The Dark Blue Book";
  const p = "margin:0 0 16px";
  const html = `<!doctype html><html><body style="margin:0;padding:24px;background:#eef1f7;font-family:Georgia,'Times New Roman',serif;color:#0e1d3a">
<div style="max-width:560px;margin:0 auto;background:#fff;border-radius:6px;overflow:hidden"><div style="background:#12264d;color:#f2f5fb;padding:18px 24px;font-size:22px;font-weight:600">The Dark Blue Book</div>
<div style="padding:24px;font-size:16px;line-height:1.5">${paras.map((x) => `<p style="${p}">${esc(x).replace(/(https:\/\/app\.darkbluebook\.com\/[^\s]*)/g, '<a href="$1" style="color:#1d5fc4">$1</a>')}</p>`).join("")}
<p style="margin:0">Dave<br>Editor, The Dark Blue Book</p></div></div></body></html>`;
  const r = await fetch("https://api.resend.com/emails", {
    method: "POST", headers: { Authorization: `Bearer ${RESEND}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from: FROM, to: [to], reply_to: REPLY_TO, subject, text, html }),
  });
  return r.ok ? "sent" : "failed";
}

Deno.serve(async (req) => {
  const h = { ...cors(req.headers.get("origin") || ""), "Content-Type": "application/json" };
  const reply = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: h });
  if (req.method === "OPTIONS") return new Response("ok", { headers: h });
  if (req.method !== "POST") return reply(405, { error: "method" });

  const tok = (req.headers.get("authorization") || "").replace(/^Bearer\s+/i, "");
  if (!tok) return reply(401, { error: "not_signed_in" });
  const u = await fetch(`${URL_}/auth/v1/user`, { headers: { apikey: PUBLIC, Authorization: `Bearer ${tok}` } });
  if (!u.ok) return reply(401, { error: "not_signed_in" });
  const caller = (await u.json()).id as string;

  let b: { kind?: string; entity_id?: string; email?: string; user_id?: string };
  try { b = await req.json(); } catch { return reply(400, { error: "bad_request" }); }
  const entity = String(b.entity_id || "");
  if (!/^[a-z0-9-]{1,80}$/.test(entity)) return reply(400, { error: "bad_request" });

  if (b.kind === "invite") {
    const email = String(b.email || "").trim();
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email) || email.length > 200) return reply(400, { error: "email" });
    const r = await svc("/rest/v1/rpc/invite_manager", { method: "POST", body: JSON.stringify({ p_entity: entity, p_email: email, p_by: caller }) });
    const t = await r.text();
    if (!r.ok) {
      const m = (() => { try { return JSON.parse(t).message || t; } catch { return t; } })();
      return reply(/not_owner/.test(m) ? 403 : /rate_limit/.test(m) ? 429 : 500, { error: /not_owner|rate_limit/.test(m) ? m : "server" });
    }
    const inv = t && t !== "null" ? JSON.parse(t) : null;
    if (inv && inv.email) {
      await send(inv.email, `Invitation: help manage ${inv.org} on The Dark Blue Book`, [
        `Hi ${first(inv.name || "")},`,
        `${inv.by || "The owner"} has invited you to help manage the profile of ${inv.org} on The Dark Blue Book.`,
        `Sign in and open your profile to accept or decline: ${APP}#${entity}`,
      ]);
    }
    return reply(200, { result: "ok" });
  }

  if (b.kind === "claim_approved") {
    const ed = await svc(`/rest/v1/editors?select=user_id&user_id=eq.${encodeURIComponent(caller)}`);
    if (!ed.ok || !(await ed.json()).length) return reply(403, { error: "not_editor" });
    const uid = String(b.user_id || "");
    if (!/^[0-9a-f-]{36}$/i.test(uid)) return reply(400, { error: "bad_request" });
    const rr = await svc(`/rest/v1/org_roles?select=role&entity_id=eq.${entity}&user_id=eq.${uid}`);
    const role = rr.ok ? ((await rr.json())[0] || {}).role : null;
    if (!role) return reply(404, { error: "no_role" });
    const m = ((await (await svc(`/rest/v1/members?select=name,email&user_id=eq.${uid}`)).json())[0]) || {};
    const org = ((await (await svc(`/rest/v1/entities?select=name&id=eq.${entity}`)).json())[0] || {}).name || "the organisation";
    if (!m.email) return reply(404, { error: "no_member" });
    const s = await send(m.email, `You can now manage ${org} on The Dark Blue Book`, [
      `Hi ${first(m.name || "")},`,
      `Your claim has been approved: you're now ${role === "owner" ? "an owner" : "a manager"} of ${org}'s profile on The Dark Blue Book.`,
      role === "owner"
        ? `You can edit its logo, description and links, and invite or remove managers, such as a PR agency: ${APP}#${entity}`
        : `You can edit its logo, description and links: ${APP}#${entity}`,
    ]);
    return reply(s === "sent" ? 200 : 502, { result: s });
  }
  return reply(400, { error: "bad_request" });
});
