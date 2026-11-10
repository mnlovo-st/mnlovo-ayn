// MNLOVO SAVER — support desk (admin only).
// Every request needs the header "x-admin-key". Vault contents are end-to-end encrypted on the
// user's iPhone, so support can look up and verify an account, change its email, unlink Telegram
// or delete it — but can never read or reset what's inside the vault.
import { createClient } from "npm:@supabase/supabase-js@2.49.4";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-admin-key",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", ...cors } });

async function sha256(s: string) {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
function same(a: string, b: string) {
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}
const log = (action: string, target: string | null, detail = "") =>
  admin.from("saver_admin_log").insert({ action, target, detail });

function westernDigits(s: string) {
  return s.replace(/[٠-٩]/g, (d) => String(d.charCodeAt(0) - 0x0660)).replace(/[۰-۹]/g, (d) => String(d.charCodeAt(0) - 0x06f0));
}
function hint(email: string) {
  const e = email.trim().toLowerCase();
  const at = e.indexOf("@");
  if (at < 1) return e;
  const local = e.slice(0, at), domain = e.slice(at);
  if (local.length <= 2) return `${local[0]}•${domain}`;
  return `${local[0]}${"•".repeat(Math.max(2, Math.min(6, local.length - 2)))}${local[local.length - 1]}${domain}`;
}

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

async function authUsers(): Promise<any[]> {
  const { data } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
  return data?.users ?? [];
}

async function details(userId: string) {
  const { data: reg } = await admin.from("saver_accounts").select("*").eq("user_id", userId).maybeSingle();
  const { data: au } = await admin.auth.admin.getUserById(userId);
  const { data: files } = await admin.storage.from("backups").list(userId);
  const backup = (files ?? []).find((f: any) => f.name === "vault.saver");
  const { count } = await admin.from("saver_tg_targets").select("*", { count: "exact", head: true }).eq("user_id", userId);
  return {
    user_id: userId,
    email: au?.user?.email ?? reg?.email ?? null,
    username: reg?.username ?? null,
    phone: reg?.phone ?? null,
    dob: reg?.dob ?? null,
    registered: !!reg,
    created_at: au?.user?.created_at ?? reg?.created_at ?? null,
    last_sign_in_at: au?.user?.last_sign_in_at ?? null,
    has_phone: !!reg?.phone_hash,
    has_dob: !!reg?.dob_hash,
    backup: backup ? { size: backup.metadata?.size ?? null, updated_at: backup.updated_at ?? backup.created_at } : null,
    telegram_chats: count ?? 0,
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method" }, 405);

  // Brute-force guard: 8 bad keys in 15 minutes locks the desk.
  const since = new Date(Date.now() - 15 * 60 * 1000).toISOString();
  const { count: bad } = await admin.from("saver_admin_log").select("*", { count: "exact", head: true })
    .eq("action", "bad_key").gte("at", since);
  if ((bad ?? 0) >= 8) return json({ error: "locked" }, 429);

  const { data: cfg } = await admin.from("saver_admin").select("key_hash").eq("id", 1).maybeSingle();
  const key = req.headers.get("x-admin-key") ?? "";
  if (!cfg || !key || !same(await sha256(key.trim()), cfg.key_hash)) {
    await log("bad_key", null);
    return json({ error: "forbidden" }, 403);
  }

  const body = await req.json().catch(() => ({}));
  const uid = typeof body.user_id === "string" ? body.user_id : null;

  switch (body.action) {
    case "ping":
      return json({ ok: true });

    case "search": {
      // Any mix of email / phone / username / birth date. Tolerant: typos, missing letters, a few days off.
      const clean = (v: unknown) => String(v ?? "").trim();
      let email = clean(body.email), username = clean(body.username);
      const phone = clean(body.phone), dob = clean(body.dob);
      const q = clean(body.q);
      if (q && !email && !username) { email = q; username = q; }
      if (!email && !username && !phone && !dob) return json({ results: [] });
      const { data, error } = await admin.rpc("saver_admin_search", {
        p_email: email || null, p_phone: phone || null, p_username: username || null, p_dob: dob || null,
      });
      if (error) return json({ error: error.message }, 400);
      const results: any[] = (data ?? []).map((r: any) => ({ ...r, registered: true }));
      // Accounts that signed in to the cloud but never finished registering still show up by email.
      if (email) {
        const e = email.toLowerCase();
        for (const u of await authUsers()) {
          if (!u.email || results.some((r) => r.user_id === u.id)) continue;
          if (u.email.toLowerCase().includes(e) || e.includes(u.email.toLowerCase().split("@")[0])) {
            results.push({ user_id: u.id, email: u.email, username: null, phone: null, dob: null, created_at: u.created_at,
                           email_score: 0.5, username_score: 0, phone_match: false, dob_days: null, score: 1.5, registered: false });
          }
        }
      }
      await log("search", null, [email, username, phone, dob].filter(Boolean).join(" | "));
      return json({ results });
    }

    case "details": {
      if (!uid) return json({ error: "user_id" }, 400);
      await log("details", uid);
      return json(await details(uid));
    }

    case "verify": {
      if (!uid) return json({ error: "user_id" }, 400);
      const { data: reg } = await admin.from("saver_accounts").select("phone_hash, dob_hash, email").eq("user_id", uid).maybeSingle();
      if (!reg) return json({ error: "not_found" }, 404);
      const digits = westernDigits(String(body.phone ?? "")).replace(/\D/g, "");
      const phoneOK = digits.length >= 7 && reg.phone_hash === await sha256(`saver|${digits.slice(-9)}`);
      const dob = String(body.dob ?? "").trim(); // yyyy-mm-dd
      const dobOK = reg.dob_hash ? reg.dob_hash === await sha256(`saver|dob|${dob}`) : null;
      const emailOK = body.email ? String(body.email).trim().toLowerCase() === reg.email : null;
      await log("verify", uid, `phone:${phoneOK} dob:${dobOK} email:${emailOK}`);
      return json({ phone: phoneOK, dob: dobOK, email: emailOK });
    }

    case "change_email": {
      const email = String(body.email ?? "").trim().toLowerCase();
      if (!uid || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json({ error: "bad_email" }, 400);
      const { data: taken } = await admin.from("saver_accounts").select("user_id").eq("email", email).neq("user_id", uid).maybeSingle();
      if (taken) return json({ error: "email_taken" }, 409);
      const { error } = await admin.auth.admin.updateUserById(uid, { email, email_confirm: true });
      if (error) return json({ error: error.message }, 400);
      await admin.from("saver_accounts").update({ email, email_hint: hint(email), updated_at: new Date().toISOString() }).eq("user_id", uid);
      await log("change_email", uid, email);
      return json({ ok: true, ...(await details(uid)) });
    }

    case "send_reset": {
      // Sends a fresh sign-in code to the account email, plus recovery steps on Telegram if it's linked.
      if (!uid) return json({ error: "user_id" }, 400);
      const info = await details(uid);
      if (!info.email) return json({ error: "no_email" }, 400);
      const r = await fetch(`${SUPABASE_URL}/auth/v1/otp`, {
        method: "POST",
        headers: { "content-type": "application/json", apikey: SERVICE, authorization: `Bearer ${SERVICE}` },
        body: JSON.stringify({ email: info.email, create_user: false }),
      });
      let telegram = 0;
      const { data: cfg } = await admin.from("saver_tg_config").select("bot_token").eq("id", 1).maybeSingle();
      const { data: chats } = await admin.from("saver_tg_targets").select("chat_id").eq("user_id", uid).eq("role", "owner").eq("type", "private");
      for (const c of chats ?? []) {
        if (!cfg) break;
        const t = await fetch(`https://api.telegram.org/bot${cfg.bot_token}/sendMessage`, {
          method: "POST", headers: { "content-type": "application/json" },
          body: JSON.stringify({ chat_id: c.chat_id, parse_mode: "HTML", text:
            `🛟 <b>الدعم الفني — MNLOVO SAVER</b>\n━━━━━━━━━━━━━━\nجهّزنا حسابك للاسترجاع.\n✉️ إيميل الحساب: <code>${info.email}</code>\n\n<b>جوال جديد أو حذفت التطبيق؟</b>\n«عندي حساب، تسجيل دخول» ← بالإيميل ← حط الكود اللي وصلك ← كلمة المرور أو مفتاح الاسترجاع.\n\n<b>نسيت كلمة المرور؟</b>\nمن شاشة الدخول ← «نسيت كلمة المرور؟» واتبع الخطوات.\n\n🔒 ما نطلب منك أبداً كلمة المرور أو مفتاح الاسترجاع.` }),
        });
        if (t.ok) telegram++;
      }
      await log("send_reset", uid, `email:${r.ok} telegram:${telegram}`);
      return json({ ok: true, email_sent: r.ok, telegram });
    }

    case "unlink_telegram": {
      if (!uid) return json({ error: "user_id" }, 400);
      await admin.from("saver_tg_targets").delete().eq("user_id", uid);
      await admin.from("saver_tg_links").delete().eq("user_id", uid);
      await log("unlink_telegram", uid);
      return json({ ok: true });
    }

    case "delete_backup": {
      if (!uid) return json({ error: "user_id" }, 400);
      await admin.storage.from("backups").remove([`${uid}/vault.saver`]);
      await log("delete_backup", uid);
      return json({ ok: true });
    }

    case "delete_user": {
      if (!uid) return json({ error: "user_id" }, 400);
      await admin.storage.from("backups").remove([`${uid}/vault.saver`]);
      const { error } = await admin.auth.admin.deleteUser(uid);
      if (error) return json({ error: error.message }, 400);
      await log("delete_user", uid);
      return json({ ok: true });
    }

    case "log": {
      const { data } = await admin.from("saver_admin_log").select("at, action, target, detail")
        .neq("action", "bad_key").order("at", { ascending: false }).limit(40);
      return json({ entries: data ?? [] });
    }

    default:
      return json({ error: "unknown_action" }, 400);
  }
});
