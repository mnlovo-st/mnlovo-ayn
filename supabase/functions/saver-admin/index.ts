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
      const q = String(body.q ?? "").trim().toLowerCase().replace(/[%,()]/g, "");
      if (q.length < 2) return json({ results: [] });
      const { data } = await admin.from("saver_accounts").select("user_id, email, username, created_at")
        .or(`email.ilike.%${q}%,username.ilike.%${q}%`).order("created_at", { ascending: false }).limit(20);
      await log("search", null, q);
      return json({ results: data ?? [] });
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
