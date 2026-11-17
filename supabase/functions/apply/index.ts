// The Dark Blue Book: membership applications.
// Public sign-up stays off. This function takes an application, creates the applicant's sign-in
// account, stores the application (public.submit_application) and emails a confirm link.
// From 0.3.39 the link is app#confirm=<token> (public.application_token_new), sent through Resend: it only confirms
// the email (public.confirm_application_token), doesn't sign anyone in, and works for 7 days on any device.
// Without RESEND_API_KEY (the sandbox), or if Resend fails, it falls back to a one-hour sign-in link from
// Supabase Auth; signing in confirms the application too (public.confirm_application).
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

async function rpc(name: string, args: unknown) {
  const r = await svc(`/rest/v1/rpc/${name}`, { method: "POST", body: JSON.stringify(args) });
  const t = await r.text();
  if (!r.ok) {
    let m = t;
    try { m = JSON.parse(t).message || t; } catch { /* keep text */ }
    throw new Error(m);
  }
  return t ? JSON.parse(t) : null;
}

async function sendLink(email: string, redirect: string) {
  const r = await fetch(`${URL_}/auth/v1/otp?redirect_to=${encodeURIComponent(redirect)}`, {
    method: "POST",
    headers: { apikey: PUBLIC, "Content-Type": "application/json" },
    body: JSON.stringify({ email, create_user: false }),
  });
  return r.ok ? "sent" : r.status === 429 ? "rate_limited" : "failed";
}

// ---- the confirm email (same layout in the remind function) ----
const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));
function layout(paras: string[], link: string) {
  const text = paras.map((p) => p === "LINK" ? `Confirm your email: ${link}` : p).join("\n\n") + "\n\nDave\nEditor, The Dark Blue Book";
  const p = "margin:0 0 16px";
  const html = `<!doctype html><html><body style="margin:0;padding:24px;background:#eef1f7;font-family:Georgia,'Times New Roman',serif;color:#0e1d3a">
<div style="max-width:560px;margin:0 auto;background:#ffffff;border-radius:6px;overflow:hidden">
<div style="background:#12264d;color:#f2f5fb;padding:18px 24px;font-size:22px;font-weight:600">The Dark Blue Book</div>
<div style="padding:24px;font-size:16px;line-height:1.5">
${paras.map((x) => x === "LINK"
    ? `<p style="${p}"><a href="${esc(link)}" style="display:inline-block;background:#12264d;color:#ffffff;text-decoration:none;padding:10px 18px;border-radius:4px;font-weight:600">Confirm my email</a></p>`
    : `<p style="${p}">${esc(x)}</p>`).join("\n")}
<p style="margin:0">Dave<br>Editor, The Dark Blue Book</p>
</div></div></body></html>`;
  return { text, html };
}
function applyEmail(name: string, link: string) {
  const first = name.trim().split(/\s+/)[0] || "there";
  return { subject: "Confirm your email for The Dark Blue Book", ...layout([
    `Hi ${first},`,
    `Thanks for applying to join The Dark Blue Book. Please confirm your email so your application can go to the editors.`,
    `LINK`,
    `The link works for 7 days, on any device.`,
    `If you didn't apply, ignore this email and the application will be deleted.`,
  ], link) };
}
// ----

// the confirm link by email through Resend; falls back to a sign-in link
async function sendConfirm(userId: string, email: string, name: string, redirect: string) {
  if (RESEND) {
    try {
      const token = await rpc("application_token_new", { p_user: userId });
      if (token) {
        const m = applyEmail(name, `${redirect}#confirm=${token}`);
        const r = await fetch("https://api.resend.com/emails", {
          method: "POST", headers: { Authorization: `Bearer ${RESEND}`, "Content-Type": "application/json" },
          body: JSON.stringify({ from: FROM, to: [email], reply_to: REPLY_TO, subject: m.subject, text: m.text, html: m.html }),
        });
        if (r.ok) return "confirm_sent";
      }
    } catch { /* fall back */ }
  }
  return await sendLink(email, redirect);
}

Deno.serve(async (req) => {
  const origin = req.headers.get("origin") || "";
  const h = { ...cors(origin), "Content-Type": "application/json" };
  const reply = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: h });
  if (req.method === "OPTIONS") return new Response("ok", { headers: h });
  if (req.method !== "POST") return reply(405, { error: "method" });

  let body: { email?: string; application?: Record<string, unknown>; website?: string; redirect?: string; ref?: string };
  try { body = await req.json(); } catch { return reply(400, { error: "bad_request" }); }

  // simple bots fill in the hidden field; pretend all went well
  if (body.website) return reply(200, { result: "sent" });

  const email = String(body.email || "").trim().toLowerCase();
  if (email.length > 200 || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return reply(400, { error: "email" });
  let redirect = "https://app.darkbluebook.com/";
  try { const u = new URL(String(body.redirect || "")); if (ALLOWED.some((r) => r.test(u.origin))) redirect = u.origin + u.pathname; } catch { /* default */ }

  try {
    const found = await rpc("apply_lookup", { p_email: email });
    if (found && (found.status === "pending" || found.status === "member")) {
      // already applied: send a sign-in link so they can see where things stand
      const link = await sendLink(email, redirect);
      return reply(200, { result: "exists", link });
    }

    let userId: string = found?.user_id || "";
    let created = false;
    if (!userId) {
      const r = await svc("/auth/v1/admin/users", { method: "POST", body: JSON.stringify({ email, email_confirm: true }) });
      const j = await r.json().catch(() => ({}));
      if (!r.ok || !j.id) return reply(500, { error: "account", detail: j.msg || j.message || r.status });
      userId = j.id;
      created = true;
    }

    try {
      await rpc("submit_application", { p_user: userId, p: body.application || {} });
    } catch (e) {
      if (created) await svc(`/auth/v1/admin/users/${userId}`, { method: "DELETE" }).catch(() => {});
      const m = String((e as Error).message || "");
      const code = (m.match(/^[a-z_]+$/) || m.match(/(application[a-z_]*|applications_rate_limit|[a-z]+_check)/) || [""])[0];
      return reply(code === "applications_rate_limit" ? 429 : 400, { error: code || "invalid", detail: m.slice(0, 300) });
    }

    // invited through a member's link: tie the application to them now (0.3.35); never blocks the application
    const ref = String(body.ref || "").toLowerCase();
    if (/^[a-z0-9]{8}$/.test(ref)) await rpc("apply_set_referrer", { p_user: userId, p_code: ref }).catch(() => {});

    const how = await sendConfirm(userId, email, String((body.application || {}).name || ""), redirect);
    return reply(200, { result: "sent", link: how === "confirm_sent" ? "sent" : how, lasts: how === "confirm_sent" ? "7d" : "1h" });
  } catch (e) {
    return reply(500, { error: "server", detail: String((e as Error).message || e).slice(0, 300) });
  }
});
