// MNLOVO SAVER — official Telegram bot.
// • Telegram → webhook: /start <code> links a chat; being added to a group/channel links it too.
// • App → { action: "link" | "status" | "remove" | "toggle" | "send" } with the user's Supabase session.
// The bot token is read from public.saver_tg_config with the service role and never leaves the server.
import { createClient } from "npm:@supabase/supabase-js@2.49.4";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const admin = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});
const SELF_URL = `${SUPABASE_URL}/functions/v1/saver-telegram`;
const LINE = "━━━━━━━━━━━━━━";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
};

type Config = { bot_token: string; bot_username: string; webhook_secret: string };

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", ...cors } });

async function config(): Promise<Config | null> {
  const { data } = await admin.from("saver_tg_config").select("*").eq("id", 1).maybeSingle();
  return data as Config | null;
}

async function tg(cfg: Config, method: string, body: Record<string, unknown>) {
  const r = await fetch(`https://api.telegram.org/bot${cfg.bot_token}/${method}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  return await r.json();
}

async function ensureWebhook(cfg: Config, force = false) {
  const info = await tg(cfg, "getWebhookInfo", {});
  if (!force && info?.result?.url === SELF_URL) return info.result;
  await tg(cfg, "setWebhook", {
    url: SELF_URL,
    secret_token: cfg.webhook_secret,
    allowed_updates: ["message", "my_chat_member"],
  });
  // Bot profile, in Arabic and English
  await tg(cfg, "setMyName", { name: "MNLOVO SAVER" });
  await tg(cfg, "setMyDescription", {
    description: "The official MNLOVO SAVER bot. Link it from the app and whatever you add arrives here, neatly formatted. Top-secret items are never sent.",
  });
  await tg(cfg, "setMyDescription", {
    language_code: "ar",
    description: "البوت الرسمي لتطبيق MNLOVO SAVER 🔐\nاربطه من التطبيق، وأي شي تضيفه يوصلك هنا مرتّب ومنسّق.\n🔴 الأشياء السرية جداً ما تنرسل أبداً.",
  });
  await tg(cfg, "setMyShortDescription", { short_description: "Official MNLOVO SAVER bot · © MNLOVO 2026" });
  await tg(cfg, "setMyShortDescription", { language_code: "ar", short_description: "البوت الرسمي لتطبيق MNLOVO SAVER · © MNLOVO 2026" });
  await tg(cfg, "setMyCommands", { commands: [{ command: "start", description: "Link MNLOVO SAVER" }] });
  await tg(cfg, "setMyCommands", { language_code: "ar", commands: [{ command: "start", description: "ربط MNLOVO SAVER" }] });
  await tg(cfg, "setMyDefaultAdministratorRights", { for_channels: true, rights: {
    is_anonymous: false, can_manage_chat: false, can_delete_messages: false, can_manage_video_chats: false,
    can_restrict_members: false, can_promote_members: false, can_change_info: false, can_invite_users: false,
    can_post_messages: true, can_edit_messages: false, can_post_stories: false, can_edit_stories: false, can_delete_stories: false,
  } });
  return (await tg(cfg, "getWebhookInfo", {}))?.result;
}

const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

function welcome(kind: string) {
  const where = kind === "channel" ? "هذي القناة" : kind === "private" ? "هنا" : "هذا القروب";
  return `✅ <b>تم ربط MNLOVO SAVER</b>\n${LINE}\nمن الحين أي شي تضيفه في التطبيق بيوصل ${where} مرتّب ومنسّق.\n🔴 الأشياء السرية جداً ما تنرسل أبداً.\n${LINE}\n<i>MNLOVO SAVER · © MNLOVO 2026</i>`;
}

function chatTitle(chat: Record<string, any>) {
  return chat.title || [chat.first_name, chat.last_name].filter(Boolean).join(" ") || chat.username || String(chat.id);
}

async function linkChat(cfg: Config, userId: string, chat: Record<string, any>, tgUserId?: number) {
  const { data: existing } = await admin.from("saver_tg_targets").select("chat_id")
    .eq("user_id", userId).eq("chat_id", chat.id).maybeSingle();
  await admin.from("saver_tg_targets").upsert({
    user_id: userId, chat_id: chat.id, title: chatTitle(chat), type: chat.type ?? "private",
    tg_user_id: tgUserId ?? null, enabled: true,
  });
  // Telegram may report the same addition twice (join event + /start); greet only once.
  if (!existing) await tg(cfg, "sendMessage", { chat_id: chat.id, text: welcome(chat.type), parse_mode: "HTML" });
}

async function handleUpdate(cfg: Config, u: Record<string, any>) {
  const m = u.message;
  if (m?.text?.startsWith("/start")) {
    const code = (m.text.split(" ")[1] ?? "").trim();
    if (!code) {
      if (m.chat.type === "private") {
        await tg(cfg, "sendMessage", {
          chat_id: m.chat.id, parse_mode: "HTML",
          text: `👋 <b>أهلاً!</b>\nعشان تربط حسابك: افتح تطبيق MNLOVO SAVER ← الإعدادات ← تيليجرام ← «ربط تيليجرام».`,
        });
      }
      return;
    }
    const { data: link } = await admin.from("saver_tg_links").select("user_id, created_at").eq("code", code).maybeSingle();
    const fresh = link && Date.now() - new Date(link.created_at).getTime() < 30 * 60 * 1000;
    if (!link || !fresh) {
      await tg(cfg, "sendMessage", { chat_id: m.chat.id, text: "⚠️ رابط الربط انتهى. ارجع للتطبيق واضغط «ربط تيليجرام» مرة ثانية." });
      return;
    }
    await linkChat(cfg, link.user_id, m.chat, m.from?.id);
    if (m.chat.type === "private") await admin.from("saver_tg_links").delete().eq("code", code);
    return;
  }
  const cm = u.my_chat_member;
  if (cm) {
    const status = cm.new_chat_member?.status;
    if (status === "left" || status === "kicked") {
      await admin.from("saver_tg_targets").delete().eq("chat_id", cm.chat.id);
      return;
    }
    // Added to a channel (or a group without a code): link it to whoever added the bot, if we know them.
    if ((status === "administrator" || status === "member") && cm.chat.type !== "private" && cm.from?.id) {
      const { data: owner } = await admin.from("saver_tg_targets").select("user_id")
        .eq("tg_user_id", cm.from.id).limit(1).maybeSingle();
      if (owner) await linkChat(cfg, owner.user_id, cm.chat, cm.from.id);
    }
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const cfg = await config();
  if (!cfg) return json({ error: "not_configured" }, 503);

  // Health / setup ping: makes sure the webhook and bot profile are in place.
  if (req.method === "GET") {
    const me = await tg(cfg, "getMe", {});
    const hook = me?.ok ? await ensureWebhook(cfg, new URL(req.url).searchParams.has("force")) : null;
    return json({ ok: !!me?.ok, bot: me?.result?.username ?? null, error: me?.description ?? null,
                  webhook: hook?.url ?? null, pending: hook?.pending_update_count ?? 0, last_error: hook?.last_error_message ?? null });
  }

  // Telegram webhook
  const secret = req.headers.get("x-telegram-bot-api-secret-token");
  if (secret !== null) {
    if (secret !== cfg.webhook_secret) return new Response("forbidden", { status: 403 });
    try { await handleUpdate(cfg, await req.json()); } catch (_) { /* never make Telegram retry */ }
    return new Response("ok");
  }

  // App calls — must carry the user's session
  const jwt = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: auth } = await admin.auth.getUser(jwt);
  const user = auth?.user;
  if (!user) return json({ error: "unauthorized" }, 401);
  const body = await req.json().catch(() => ({}));

  switch (body.action) {
    case "link": {
      await ensureWebhook(cfg);
      const code = crypto.randomUUID().replace(/-/g, "").slice(0, 24);
      await admin.from("saver_tg_links").delete().eq("user_id", user.id)
        .lt("created_at", new Date(Date.now() - 30 * 60 * 1000).toISOString());
      await admin.from("saver_tg_links").insert({ code, user_id: user.id });
      return json({ bot: cfg.bot_username, code });
    }
    case "status": {
      const { data } = await admin.from("saver_tg_targets").select("chat_id, title, type, enabled")
        .eq("user_id", user.id).order("created_at");
      return json({ bot: cfg.bot_username, targets: data ?? [] });
    }
    case "toggle": {
      await admin.from("saver_tg_targets").update({ enabled: !!body.enabled })
        .eq("user_id", user.id).eq("chat_id", body.chat_id);
      return json({ ok: true });
    }
    case "remove": {
      const { data: t } = await admin.from("saver_tg_targets").select("type").eq("user_id", user.id)
        .eq("chat_id", body.chat_id).maybeSingle();
      await admin.from("saver_tg_targets").delete().eq("user_id", user.id).eq("chat_id", body.chat_id);
      if (t && t.type !== "private") await tg(cfg, "leaveChat", { chat_id: body.chat_id });
      return json({ ok: true });
    }
    case "send": {
      const text = String(body.text ?? "").slice(0, 4000);
      if (!text) return json({ error: "empty" }, 400);
      const { data: targets } = await admin.from("saver_tg_targets").select("chat_id")
        .eq("user_id", user.id).eq("enabled", true);
      let sent = 0;
      for (const t of targets ?? []) {
        const msg = { text, parse_mode: "HTML", link_preview_options: { is_disabled: true } };
        let r = await tg(cfg, "sendMessage", { chat_id: t.chat_id, ...msg });
        const moved = r?.parameters?.migrate_to_chat_id;
        if (!r?.ok && moved) { // group was upgraded to a supergroup
          await admin.from("saver_tg_targets").update({ chat_id: moved }).eq("user_id", user.id).eq("chat_id", t.chat_id);
          r = await tg(cfg, "sendMessage", { chat_id: moved, ...msg });
        }
        if (r?.ok) sent++;
        else if (r?.error_code === 403) await admin.from("saver_tg_targets").delete().eq("user_id", user.id).eq("chat_id", t.chat_id);
      }
      return json({ sent });
    }
    default:
      return json({ error: "unknown_action" }, 400);
  }
});
