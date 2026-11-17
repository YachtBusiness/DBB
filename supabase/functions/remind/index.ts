// The Dark Blue Book: reminder for applicants who haven't confirmed their email, sent through Resend.
// Called hourly by public.applications_housekeeping() (pg_cron + pg_net) when someone is due: unconfirmed
// for 5 days and not yet reminded. Each gets one email with a confirm link (0.3.39: app#confirm=<token>, made by
// public.application_token_new). It only confirms the email, doesn't sign anyone in, and works until the
// application is deleted: at 7 days, and never sooner than 2 days after the reminder.
// Callers must send Vault's remind_secret as x-remind-secret (checked by public.remind_key_ok). Needs RESEND_API_KEY.
// Without the email key (the sandbox) nothing is sent and nobody is marked as reminded.
// {"preview_to": "<editor's email>"} sends samples of both emails (application and reminder) to an editor instead;
// their buttons open a sample link that confirms nothing.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const URL_ = Deno.env.get("SUPABASE_URL")!;
const firstKey = (json: string | undefined) => {
  try { const o = JSON.parse(json || "{}"); return (Object.values(o)[0] as string) || ""; } catch { return ""; }
};
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || firstKey(Deno.env.get("SUPABASE_SECRET_KEYS"));
const RESEND = Deno.env.get("RESEND_API_KEY") || "";
const FROM = Deno.env.get("WELCOME_FROM") || "Dave at The Dark Blue Book <no-reply@darkbluebook.com>";
const REPLY_TO = Deno.env.get("WELCOME_REPLY_TO") || "editor@darkbluebook.com";
const APP = "https://app.darkbluebook.com/";

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

// ---- the confirm emails (same layout in the apply function) ----
const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));
const day = (d: Date) => d.toLocaleDateString("en-GB", { day: "numeric", month: "long", timeZone: "UTC" });
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
function remindEmail(name: string, applied: Date, link: string) {
  const first = name.trim().split(/\s+/)[0] || "there";
  const by = new Date(Math.max(applied.getTime() + 7 * 864e5, Date.now() + 2 * 864e5));
  return { subject: "Confirm your email to finish your application", ...layout([
    `Hi ${first},`,
    `You applied to join The Dark Blue Book on ${day(applied)}, but your email isn't confirmed yet, so your application hasn't reached the editors.`,
    `LINK`,
    `The link works until ${day(by)}, on any device. After that, unconfirmed applications are deleted, and you're welcome to apply again.`,
    `If you didn't apply, ignore this email.`,
  ], link) };
}
// ----

async function send(to: string, m: { subject: string; text: string; html: string }) {
  const r = await fetch("https://api.resend.com/emails", {
    method: "POST", headers: { Authorization: `Bearer ${RESEND}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from: FROM, to: [to], reply_to: REPLY_TO, subject: m.subject, text: m.text, html: m.html }),
  });
  return r.ok;
}

Deno.serve(async (req) => {
  const reply = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
  if (req.method !== "POST") return reply(405, { error: "method" });
  const key = req.headers.get("x-remind-secret") || "";
  if (!key || !(await rpc("remind_key_ok", { p_key: key }).catch(() => false))) return reply(401, { error: "unauthorised" });
  let b: { preview_to?: string } = {};
  try { b = await req.json(); } catch { /* empty body */ }
  try {
    if (!RESEND) return reply(200, { result: "not_configured", due: ((await rpc("applications_due_reminder")) || []).length });

    if (b.preview_to) {
      const email = String(b.preview_to).trim().toLowerCase();
      const found = await rpc("apply_lookup", { p_email: email });
      const ed = found?.user_id ? await (await svc(`/rest/v1/editors?select=user_id&user_id=eq.${found.user_id}`)).json() : [];
      if (!ed.length) return reply(403, { error: "not_editor" });
      const sample = APP + "#confirm=sample";
      const a = await send(email, applyEmail("Dave", sample));
      const r = await send(email, remindEmail("Dave", new Date(Date.now() - 5 * 864e5), sample));
      return reply(a && r ? 200 : 502, { result: a && r ? "preview_sent" : "failed" });
    }

    const due: { user_id: string; name: string; email: string; applied_at: string }[] = (await rpc("applications_due_reminder")) || [];
    let sent = 0, failed = 0;
    for (const a of due) {
      const token = await rpc("application_token_new", { p_user: a.user_id });
      if (token && await send(a.email, remindEmail(a.name || "", new Date(a.applied_at), `${APP}#confirm=${token}`))) {
        await rpc("application_reminded", { p_user: a.user_id });
        sent++;
      } else failed++;
    }
    return reply(200, { result: "ok", due: due.length, sent, failed });
  } catch (e) {
    return reply(500, { error: "server", detail: String((e as Error).message || e).slice(0, 300) });
  }
});
