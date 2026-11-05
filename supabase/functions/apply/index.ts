// The Dark Blue Book: membership applications.
// Public sign-up stays off. This function takes an application, creates the applicant's sign-in
// account, stores the application (public.submit_application) and emails a one-time link.
// Opening the link signs the applicant in, and the app then confirms the email (public.confirm_application).
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const URL_ = Deno.env.get("SUPABASE_URL")!;
const firstKey = (json: string | undefined) => {
  try { const o = JSON.parse(json || "{}"); return (Object.values(o)[0] as string) || ""; } catch { return ""; }
};
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || firstKey(Deno.env.get("SUPABASE_SECRET_KEYS"));
const PUBLIC = Deno.env.get("SUPABASE_ANON_KEY") || firstKey(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS"));

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

Deno.serve(async (req) => {
  const origin = req.headers.get("origin") || "";
  const h = { ...cors(origin), "Content-Type": "application/json" };
  const reply = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: h });
  if (req.method === "OPTIONS") return new Response("ok", { headers: h });
  if (req.method !== "POST") return reply(405, { error: "method" });

  let body: { email?: string; application?: Record<string, unknown>; website?: string; redirect?: string };
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

    const link = await sendLink(email, redirect);
    return reply(200, { result: "sent", link });
  } catch (e) {
    return reply(500, { error: "server", detail: String((e as Error).message || e).slice(0, 300) });
  }
});
