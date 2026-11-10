// MNLOVO SAVER — official Telegram bot.
// • Telegram → webhook: /start <code> links a chat; being added to a group/channel links it too.
// • App → { action: "link" | "status" | "remove" | "toggle" | "send" } with the user's Supabase session.
// The bot token is read from public.saver_tg_config with the service role and never leaves the server.
import { createClient } from "npm:@supabase/supabase-js@2.49.4";

declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void } | undefined;
const later = (p: Promise<unknown>) => { try { EdgeRuntime?.waitUntil(p); } catch (_) { /* best effort */ } };
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

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

/** Uploads a JPEG (base64) to a chat as a photo with an HTML caption. */
async function tgPhoto(cfg: Config, chatId: number, b64: string, caption: string) {
  const bin = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
  const form = new FormData();
  form.append("chat_id", String(chatId));
  form.append("caption", caption);
  form.append("parse_mode", "HTML");
  form.append("photo", new Blob([bin], { type: "image/jpeg" }), "intruder.jpg");
  const r = await fetch(`https://api.telegram.org/bot${cfg.bot_token}/sendPhoto`, { method: "POST", body: form });
  return await r.json();
}

async function ensureWebhook(cfg: Config, force = false) {
  const info = await tg(cfg, "getWebhookInfo", {});
  const upToDate = info?.result?.url === SELF_URL && (info?.result?.allowed_updates ?? []).includes("callback_query");
  if (!force && upToDate) return info.result;
  await tg(cfg, "setWebhook", {
    url: SELF_URL,
    secret_token: cfg.webhook_secret,
    allowed_updates: ["message", "my_chat_member", "callback_query"],
  });
  // Bot profile, in Arabic and English
  await tg(cfg, "setMyName", { name: "MNLOVO SAVER" });
  await tg(cfg, "setMyDescription", {
    description: "The official MNLOVO SAVER bot. Link it from the app and whatever you add arrives here, neatly formatted.",
  });
  await tg(cfg, "setMyDescription", {
    language_code: "ar",
    description: "البوت الرسمي لتطبيق MNLOVO SAVER 🔐\nاربطه من التطبيق، وأي شي تضيفه يوصلك هنا مرتّب ومنسّق.\nومشوّش، المسه عشان يبين.",
  });
  await tg(cfg, "setMyShortDescription", { short_description: "Official MNLOVO SAVER bot · © MNLOVO 2026" });
  await tg(cfg, "setMyShortDescription", { language_code: "ar", short_description: "البوت الرسمي لتطبيق MNLOVO SAVER · © MNLOVO 2026" });
  await tg(cfg, "setMyCommands", { commands: [
    { command: "menu", description: "Controls: pause, share, unlink, recovery help" },
    { command: "start", description: "Link MNLOVO SAVER" },
    { command: "help", description: "Help & support" },
  ] });
  await tg(cfg, "setMyCommands", { language_code: "ar", commands: [
    { command: "menu", description: "التحكم: إيقاف، مشاركة، فصل، مساعدة الاسترجاع" },
    { command: "start", description: "ربط MNLOVO SAVER" },
    { command: "help", description: "المساعدة والدعم الفني" },
  ] });
  await tg(cfg, "setMyDefaultAdministratorRights", { for_channels: true, rights: {
    is_anonymous: false, can_manage_chat: false, can_delete_messages: false, can_manage_video_chats: false,
    can_restrict_members: false, can_promote_members: false, can_change_info: false, can_invite_users: false,
    can_post_messages: true, can_edit_messages: false, can_post_stories: false, can_edit_stories: false, can_delete_stories: false,
  } });
  return (await tg(cfg, "getWebhookInfo", {}))?.result;
}

const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

function welcome(kind: string, role = "owner") {
  if (role === "friend") {
    return `✅ <b>تم الربط</b>\n${LINE}\nصاحب حساب MNLOVO SAVER شاركك تحديثاته، وبتوصلك هنا مرتّبة ومنسّقة.\n${LINE}\n<i>MNLOVO SAVER · © MNLOVO 2026</i>`;
  }
  const where = kind === "channel" ? "هذي القناة" : kind === "private" ? "هنا" : "هذا القروب";
  return `✅ <b>تم ربط MNLOVO SAVER</b>\n${LINE}\nمن الحين أي شي تضيفه في التطبيق بيوصل ${where} مرتّب ومنسّق.\nالنصوص تجي مشوّشة، المسها عشان تبين.\n${LINE}\n<i>MNLOVO SAVER · © MNLOVO 2026</i>`;
}

function chatTitle(chat: Record<string, any>) {
  return chat.title || [chat.first_name, chat.last_name].filter(Boolean).join(" ") || chat.username || String(chat.id);
}

async function alreadyLinked(cfg: Config, chatId: number, fromId?: number) {
  const { data } = await admin.from("saver_tg_targets").select("enabled, role").eq("chat_id", chatId);
  const on = (data ?? []).some((t: any) => t.enabled);
  await tg(cfg, "sendMessage", {
    chat_id: chatId, parse_mode: "HTML",
    text: `✅ <b>مربوط من قبل</b>\n${LINE}\nهالمحادثة مربوطة بـ MNLOVO SAVER ${on ? "والنشر شغّال 🟢" : "بس النشر موقّف ⏸️"}.\nما تحتاج تسوي شي ثاني.\n\nتبي تتحكم؟ اضغط الزر تحت أو اكتب /menu`,
    reply_markup: { inline_keyboard: [[{ text: "⚙️ التحكم", callback_data: "tg:menu" }]] },
  });
}

/** Links a chat. "new" = just linked, "recent" = linked a moment ago (join event + /start), "old" = was already linked. */
async function linkChat(cfg: Config, userId: string, chat: Record<string, any>, tgUserId: number | null, role = "owner") {
  const { data: existing } = await admin.from("saver_tg_targets").select("chat_id, created_at")
    .eq("user_id", userId).eq("chat_id", chat.id).maybeSingle();
  if (existing) {
    await admin.from("saver_tg_targets").update({ title: chatTitle(chat) }).eq("user_id", userId).eq("chat_id", chat.id);
    return Date.now() - new Date(existing.created_at).getTime() < 120_000 ? "recent" : "old";
  }
  await admin.from("saver_tg_targets").insert({
    user_id: userId, chat_id: chat.id, title: chatTitle(chat), type: chat.type ?? "private",
    tg_user_id: tgUserId, enabled: true, role,
  });
  const sent = await tg(cfg, "sendMessage", { chat_id: chat.id, text: welcome(chat.type, role), parse_mode: "HTML",
    reply_markup: { inline_keyboard: [[{ text: "⚙️ التحكم بالبوت", callback_data: "tg:menu" }]] } });
  // In groups and channels the big welcome tidies itself away after 10 seconds, leaving a small note.
  if (chat.type !== "private" && sent?.ok) {
    later((async () => {
      await sleep(10_000);
      await tg(cfg, "deleteMessage", { chat_id: chat.id, message_id: sent.result.message_id });
      await tg(cfg, "sendMessage", { chat_id: chat.id, text: "تم الربط بنجاح ✔️", disable_notification: true });
    })());
  }
  return "new";
}

const FOOT = `${LINE}\n<i>MNLOVO SAVER · © MNLOVO 2026</i>`;
const SUPPORT_ROW = [
  { text: "💬 الدعم — تيليجرام", url: "https://t.me/bscoolvi" },
  { text: "📸 إنستغرام", url: "https://instagram.com/4saf" },
];

type Target = { user_id: string; chat_id: number; type: string; enabled: boolean; role: string; tg_user_id: number | null; title: string };

async function targetsOf(chatId: number): Promise<Target[]> {
  const { data } = await admin.from("saver_tg_targets").select("*").eq("chat_id", chatId);
  return (data ?? []) as Target[];
}

/** Is this Telegram user the owner of the account linked here? */
async function ownerOf(t: Target, fromId?: number) {
  if (!fromId) return false;
  if (t.role === "owner" && t.tg_user_id === fromId) return true;
  const { data } = await admin.from("saver_tg_targets").select("chat_id")
    .eq("user_id", t.user_id).eq("tg_user_id", fromId).eq("role", "owner").limit(1);
  return !!(data && data.length);
}

async function sendMenu(cfg: Config, chatId: number, fromId?: number, editId?: number) {
  const ts = await targetsOf(chatId);
  if (!ts.length) {
    await tg(cfg, "sendMessage", { chat_id: chatId, parse_mode: "HTML",
      text: `👋 <b>هالمحادثة مو مربوطة</b>\n${LINE}\nافتح تطبيق MNLOVO SAVER ← الإعدادات ← تيليجرام ← «ربط تيليجرام بضغطة».\n${FOOT}`,
      reply_markup: { inline_keyboard: [SUPPORT_ROW] } });
    return;
  }
  const t = ts[0];
  const owner = await ownerOf(t, fromId);
  const kb: any[][] = [[{ text: t.enabled ? "⏸️ وقّف النشر هنا" : "▶️ شغّل النشر هنا", callback_data: "tg:toggle" }]];
  if (owner) {
    kb.push([{ text: "👤 أضف شخص ثاني يستقبل", callback_data: "tg:share" }]);
    if (t.type === "private") kb.push([{ text: "🆘 مساعدة في استرجاع الحساب", callback_data: "tg:recover" }]);
  }
  kb.push([{ text: t.role === "friend" ? "🚪 وقّف استقبالي نهائياً" : "🔌 فصل البوت من هنا", callback_data: "tg:unlink" }]);
  kb.push(SUPPORT_ROW);
  const text = `⚙️ <b>التحكم بـ MNLOVO SAVER</b>\n${LINE}\nالحالة: ${t.enabled ? "🟢 النشر شغّال" : "⏸️ النشر موقّف"}\nالنوع: ${
    t.type === "channel" ? "قناة" : t.type === "private" ? (t.role === "friend" ? "شخص مشارَك" : "محادثتك الخاصة") : "قروب"}\n${FOOT}`;
  if (editId) await tg(cfg, "editMessageText", { chat_id: chatId, message_id: editId, text, parse_mode: "HTML", reply_markup: { inline_keyboard: kb } });
  else await tg(cfg, "sendMessage", { chat_id: chatId, text, parse_mode: "HTML", reply_markup: { inline_keyboard: kb } });
}


// MARK: - Heartbeat / legacy delivery

const DAY = 86_400_000;

async function legacyAlive(cfg: Config, userId: string, chatId?: number) {
  await admin.from("saver_legacy")
    .update({ last_seen: new Date().toISOString(), state: "ok", asked_count: 0, asked_at: null, updated_at: new Date().toISOString() })
    .eq("user_id", userId);
  if (chatId) {
    await tg(cfg, "sendMessage", { chat_id: chatId, parse_mode: "HTML",
      text: `\u2764\ufe0f <b>\u0627\u0644\u062d\u0645\u062f\u0644\u0644\u0647</b>\n${LINE}\n\u0633\u062c\u0651\u0644\u0646\u0627 \u0625\u0646\u0643 \u0628\u062e\u064a\u0631 \u2713 \u0648\u0631\u062c\u0639 \u0627\u0644\u0639\u062f\u0627\u062f \u0645\u0646 \u0627\u0644\u0623\u0648\u0644.\n${FOOT}` });
  }
}

/** Splits a long bundle into Telegram-sized chunks. */
function chunk(text: string, size = 3500): string[] {
  const out: string[] = [];
  let rest = text;
  while (rest.length > size) {
    let cut = rest.lastIndexOf("\n", size);
    if (cut < size * 0.5) cut = size;
    out.push(rest.slice(0, cut));
    rest = rest.slice(cut);
  }
  if (rest.trim()) out.push(rest);
  return out;
}

async function releaseLegacy(cfg: Config, row: any) {
  if (!row.recipient_chat_id || !row.bundle) return;
  const { data: reg } = await admin.from("saver_accounts").select("username, email_hint").eq("user_id", row.user_id).maybeSingle();
  const who = reg?.username ? esc(reg.username) : (reg?.email_hint ?? "");
  await tg(cfg, "sendMessage", { chat_id: row.recipient_chat_id, parse_mode: "HTML",
    text: `\ud83d\udd4a\ufe0f <b>\u0623\u0645\u0627\u0646\u0629 \u0645\u0646 MNLOVO SAVER</b>\n${LINE}\n\u0635\u0627\u062d\u0628 \u0627\u0644\u062d\u0633\u0627\u0628 ${who} \u0627\u062e\u062a\u0627\u0631\u0643 \u0623\u0645\u064a\u0646\u0627\u064b \u0639\u0644\u0649 \u0628\u064a\u0627\u0646\u0627\u062a\u0647.\n\u0645\u0627 \u0641\u062a\u062d \u0627\u0644\u062a\u0637\u0628\u064a\u0642 \u0645\u0646 ${row.interval_days} \u064a\u0648\u0645\u060c \u0648\u0645\u0627 \u0631\u062f\u0651 \u0639\u0644\u0649 \u0631\u0633\u0627\u0626\u0644\u0646\u0627 \u0637\u0648\u0627\u0644 ${row.grace_days} \u0623\u064a\u0627\u0645.\n\n\u062a\u062d\u062a \u0628\u064a\u0627\u0646\u0627\u062a\u0647 \u0632\u064a \u0645\u0627 \u062a\u0631\u0643\u0647\u0627. \u062d\u0627\u0641\u0638 \u0639\u0644\u064a\u0647\u0627.\n${FOOT}` });
  for (const part of chunk(row.bundle)) {
    await tg(cfg, "sendMessage", { chat_id: row.recipient_chat_id, text: `<pre>${esc(part)}</pre>`, parse_mode: "HTML" });
  }
  await admin.from("saver_legacy").update({ state: "released", released_at: new Date().toISOString() }).eq("user_id", row.user_id);
  // Tell the owner too, in case they are simply away.
  const { data: own } = await admin.from("saver_tg_targets").select("chat_id")
    .eq("user_id", row.user_id).eq("role", "owner").eq("type", "private").limit(1).maybeSingle();
  if (own) {
    await tg(cfg, "sendMessage", { chat_id: own.chat_id, parse_mode: "HTML",
      text: `\u2139\ufe0f <b>\u0627\u0646\u0631\u0633\u0644\u062a \u0627\u0644\u0623\u0645\u0627\u0646\u0629</b>\n${LINE}\n\u0645\u0627 \u0648\u0635\u0644\u0646\u0627 \u0645\u0646\u0643 \u0631\u062f\u060c \u0641\u0633\u0644\u0651\u0645\u0646\u0627 \u0628\u064a\u0627\u0646\u0627\u062a\u0643 \u0644\u0640 ${esc(row.recipient_name || "\u0627\u0644\u0634\u062e\u0635 \u0627\u0644\u0644\u064a \u0627\u062e\u062a\u0631\u062a\u0647")}.\n\u0644\u0648 \u0647\u0630\u0627 \u0635\u0627\u0631 \u0628\u0627\u0644\u063a\u0644\u0637\u060c \u0627\u0641\u062a\u062d \u0627\u0644\u062a\u0637\u0628\u064a\u0642 \u0648\u0639\u062f\u0651\u0644 \u0627\u0644\u0625\u0639\u062f\u0627\u062f\u0627\u062a.\n${FOOT}` });
  }
}

/** Runs the heartbeat checks. Called daily by the keep-alive workflow. */
async function runLegacyCron(cfg: Config) {
  const now = Date.now();
  const { data: rows } = await admin.from("saver_legacy").select("*").eq("enabled", true).neq("state", "released");
  let asked = 0, released = 0;
  for (const row of rows ?? []) {
    const quiet = now - new Date(row.last_seen).getTime();
    if (quiet < row.interval_days * DAY) continue;
    const { data: own } = await admin.from("saver_tg_targets").select("chat_id")
      .eq("user_id", row.user_id).eq("role", "owner").eq("type", "private").limit(1).maybeSingle();
    const overGrace = quiet >= (row.interval_days + row.grace_days) * DAY;
    if (overGrace && row.recipient_chat_id && row.bundle) {
      await releaseLegacy(cfg, row);
      released++;
      continue;
    }
    // Ask at most once a day.
    if (row.asked_at && now - new Date(row.asked_at).getTime() < DAY * 0.9) continue;
    if (!own) continue;
    const left = Math.max(0, Math.ceil(((row.interval_days + row.grace_days) * DAY - quiet) / DAY));
    await tg(cfg, "sendMessage", { chat_id: own.chat_id, parse_mode: "HTML",
      text: `\ud83e\udec0 <b>\u0637\u0645\u0651\u0646\u0651\u0627 \u0639\u0646\u0643</b>\n${LINE}\n\u0635\u0627\u0631 \u0644\u0643 ${row.interval_days} \u064a\u0648\u0645 \u0645\u0627 \u0641\u062a\u062d\u062a MNLOVO SAVER.\n\u0627\u0636\u063a\u0637 \u0627\u0644\u0632\u0631 \u062a\u062d\u062a \u0639\u0634\u0627\u0646 \u0646\u0639\u0631\u0641 \u0625\u0646\u0643 \u0628\u062e\u064a\u0631.\n\n\u23f3 \u0628\u0627\u0642\u064a ${left} \u064a\u0648\u0645\u060c \u0648\u0628\u0639\u062f\u0647\u0627 \u062a\u0646\u0633\u0644\u0651\u0645 \u0623\u0645\u0627\u0646\u062a\u0643 \u0644\u0640 ${esc(row.recipient_name || "\u0627\u0644\u0634\u062e\u0635 \u0627\u0644\u0644\u064a \u0627\u062e\u062a\u0631\u062a\u0647")}.\n${FOOT}`,
      reply_markup: { inline_keyboard: [
        [{ text: "\u2764\ufe0f \u0623\u0646\u0627 \u0628\u062e\u064a\u0631", callback_data: "tg:alive" }],
        [{ text: "\u23f8\ufe0f \u0623\u0648\u0642\u0650\u0641 \u0627\u0644\u062e\u0627\u0635\u064a\u0629", callback_data: "tg:legacy_off" }],
      ] } });
    await admin.from("saver_legacy").update({
      state: "asking", asked_at: new Date().toISOString(), asked_count: (row.asked_count ?? 0) + 1,
    }).eq("user_id", row.user_id);
    asked++;
  }
  return { checked: rows?.length ?? 0, asked, released };
}

async function handleCallback(cfg: Config, q: Record<string, any>) {
  const chatId: number = q.message?.chat?.id;
  const msgId: number = q.message?.message_id;
  const fromId: number = q.from?.id;
  const data: string = q.data ?? "";
  const answer = (text = "", alert = false) => tg(cfg, "answerCallbackQuery", { callback_query_id: q.id, text, show_alert: alert });
  const ts = chatId ? await targetsOf(chatId) : [];
  if (!ts.length) { await answer("هالمحادثة مو مربوطة."); return; }
  const t = ts[0];
  const owner = await ownerOf(t, fromId);
  const isGroup = t.type !== "private";
  // In groups and channels only the account owner can change anything.
  if (isGroup && !owner) { await answer("بس صاحب الحساب يقدر يتحكم.", true); return; }

  switch (data) {
    case "tg:menu":
      await answer();
      return await sendMenu(cfg, chatId, fromId, msgId);
    case "tg:toggle": {
      await admin.from("saver_tg_targets").update({ enabled: !t.enabled }).eq("chat_id", chatId);
      await answer(t.enabled ? "وقّفنا النشر هنا ⏸️" : "رجع النشر ✓");
      return await sendMenu(cfg, chatId, fromId, msgId);
    }
    case "tg:share": {
      if (!owner) return await answer("بس صاحب الحساب.", true);
      const code = crypto.randomUUID().replace(/-/g, "").slice(0, 24);
      await admin.from("saver_tg_links").insert({ code, user_id: t.user_id, kind: "friend" });
      const link = `https://t.me/${cfg.bot_username}?start=${code}`;
      await answer();
      await tg(cfg, "sendMessage", { chat_id: chatId, parse_mode: "HTML",
        text: `👤 <b>رابط لشخص ثاني</b>\n${LINE}\nأرسل هالرابط للشخص اللي تبيه يستقبل تحديثاتك. أول ما يفتحه ويضغط «ابدأ» ينربط.\n\n<code>${link}</code>\n\n⏳ صالح لمدة ٣٠ دقيقة ولمرة وحدة.\n${FOOT}`,
        reply_markup: { inline_keyboard: [
          [{ text: "📤 أرسل الرابط", url: `https://t.me/share/url?url=${encodeURIComponent(link)}&text=${encodeURIComponent("اضغط الرابط وبعدين «ابدأ» عشان توصلك تحديثات MNLOVO SAVER")}` }],
          [{ text: "↩️ رجوع للتحكم", callback_data: "tg:menu" }],
        ] } });
      return;
    }
    case "tg:recover": {
      if (!owner) return await answer("بس صاحب الحساب.", true);
      const { data: reg } = await admin.from("saver_accounts").select("email_hint, username").eq("user_id", t.user_id).maybeSingle();
      await answer();
      await tg(cfg, "sendMessage", { chat_id: chatId, parse_mode: "HTML",
        text: `🆘 <b>مساعدة في استرجاع الحساب</b>\n${LINE}\nالحساب المربوط هنا:\n👤 ${reg?.username ? esc(reg.username) : "—"}\n✉️ ${reg?.email_hint ?? "—"}\n\n<b>إذا نسيت كلمة المرور:</b>\n١. افتح التطبيق ← «نسيت كلمة المرور؟»\n٢. حط الإيميل ورقم الهاتف وتاريخ الميلاد\n٣. حط الكود اللي يوصلك على الإيميل\n٤. رمز التحقق المتغير + Face ID، أو مفتاح الاسترجاع (٦ مجموعات)\n٥. سوّ كلمة مرور جديدة ✓\n\n<b>جوال جديد؟</b> «عندي حساب، تسجيل دخول» ← بالإيميل ← كلمة المرور أو مفتاح الاسترجاع.\n\n🔒 البوت يساعدك بس، ما يقدر يفتح خزنتك ولا يغيّر كلمة المرور — بياناتك مشفّرة في جوالك.\nما نطلب منك أبداً كلمة المرور أو مفتاح الاسترجاع.\n${FOOT}`,
        reply_markup: { inline_keyboard: [SUPPORT_ROW, [{ text: "↩️ رجوع للتحكم", callback_data: "tg:menu" }]] } });
      return;
    }
    case "tg:unlink": {
      await answer();
      await tg(cfg, "editMessageText", { chat_id: chatId, message_id: msgId, parse_mode: "HTML",
        text: `🔌 <b>متأكد تبي تفصل البوت من هنا؟</b>\nما بيوصل هنا أي شي بعدها. تقدر ترجع تربطه من التطبيق.`,
        reply_markup: { inline_keyboard: [[{ text: "نعم، افصل", callback_data: "tg:unlink_yes" }, { text: "لا", callback_data: "tg:menu" }]] } });
      return;
    }
    case "tg:unlink_yes": {
      await admin.from("saver_tg_targets").delete().eq("chat_id", chatId);
      await answer("تم الفصل");
      await tg(cfg, "editMessageText", { chat_id: chatId, message_id: msgId, parse_mode: "HTML",
        text: `✅ <b>تم فصل MNLOVO SAVER</b>\nما بيوصل هنا شي بعد الحين.\n${FOOT}` });
      if (isGroup) await tg(cfg, "leaveChat", { chat_id: chatId });
      return;
    }
    default:
      await answer();
  }
}

async function handleUpdate(cfg: Config, u: Record<string, any>) {
  if (u.callback_query) return await handleCallback(cfg, u.callback_query);
  const m = u.message;
  const text: string = m?.text ?? "";
  if (/^\/(menu|settings)(@\w+)?(\s|$)/.test(text)) return await sendMenu(cfg, m.chat.id, m.from?.id);
  if (/^\/(start|help)(@\w+)?(\s|$)/.test(text)) {
    const code = (text.split(/\s+/)[1] ?? "").trim();
    if (!code) {
      const { data: linked } = await admin.from("saver_tg_targets").select("chat_id").eq("chat_id", m.chat.id).limit(1);
      if (linked && linked.length) return await alreadyLinked(cfg, m.chat.id, m.from?.id);
      if (m.chat.type === "private") {
        await tg(cfg, "sendMessage", {
          chat_id: m.chat.id, parse_mode: "HTML",
          text: `👋 <b>أهلاً فيك في MNLOVO SAVER</b>\n${LINE}\nعشان تربط حسابك:\n١. افتح تطبيق MNLOVO SAVER\n٢. الإعدادات ← تيليجرام\n٣. اضغط «ربط تيليجرام بضغطة»\n\nوبس! التطبيق يرجعك هنا ويربط لحاله.\n${LINE}\n<i>MNLOVO SAVER · © MNLOVO 2026</i>`,
        });
      }
      return;
    }
    const { data: link } = await admin.from("saver_tg_links").select("user_id, created_at, kind").eq("code", code).maybeSingle();
    const fresh = link && Date.now() - new Date(link.created_at).getTime() < 30 * 60 * 1000;
    if (!link || !fresh) {
      const { data: linked } = await admin.from("saver_tg_targets").select("chat_id").eq("chat_id", m.chat.id).limit(1);
      if (linked && linked.length) return await alreadyLinked(cfg, m.chat.id, m.from?.id);
      await tg(cfg, "sendMessage", { chat_id: m.chat.id, text: "⚠️ رابط الربط انتهى. ارجع للتطبيق واضغط «ربط تيليجرام» مرة ثانية." });
      return;
    }
    if (link.kind === "legacy" && m.chat.type === "private") {
      const name = chatTitle(m.chat);
      await admin.from("saver_legacy").upsert({
        user_id: link.user_id, recipient_chat_id: m.chat.id, recipient_name: name, updated_at: new Date().toISOString(),
      }, { onConflict: "user_id" });
      await admin.from("saver_tg_links").delete().eq("code", code);
      await tg(cfg, "sendMessage", { chat_id: m.chat.id, parse_mode: "HTML",
        text: `\ud83e\udd1d <b>\u0635\u0631\u062a \u0627\u0644\u0623\u0645\u064a\u0646</b>\n${LINE}\n\u0648\u0627\u062d\u062f \u0645\u0646 \u0645\u0633\u062a\u062e\u062f\u0645\u064a MNLOVO SAVER \u0627\u062e\u062a\u0627\u0631\u0643 \u0623\u0645\u064a\u0646\u0627\u064b \u0639\u0644\u0649 \u0628\u064a\u0627\u0646\u0627\u062a\u0647.\n\n\u0645\u0627 \u0628\u064a\u0648\u0635\u0644\u0643 \u0634\u064a \u0627\u0644\u062d\u064a\u0646. \u0628\u0633 \u0625\u0630\u0627 \u0627\u0646\u0642\u0637\u0639\u062a \u0623\u062e\u0628\u0627\u0631\u0647 \u0645\u062f\u0629 \u0637\u0648\u064a\u0644\u0629\u060c \u0628\u0646\u0633\u0644\u0651\u0645\u0643 \u0623\u0645\u0627\u0646\u062a\u0647.\n\n\ud83e\udd32 \u0627\u062d\u062a\u0641\u0638 \u0641\u064a\u0647\u0627 \u0648\u0644\u0627 \u062a\u0639\u0637\u064a\u0647\u0627 \u0644\u0623\u062d\u062f.\n${FOOT}` });
      return;
    }
    const friend = link.kind === "friend" && m.chat.type === "private";
    if (friend) {
      // The owner opened their own share link: that's just their private chat.
      const { data: own } = await admin.from("saver_tg_targets").select("chat_id")
        .eq("user_id", link.user_id).eq("chat_id", m.chat.id).maybeSingle();
      if (own) { await alreadyLinked(cfg, m.chat.id); return; }
    }
    const result = await linkChat(cfg, link.user_id, m.chat, friend ? null : (m.from?.id ?? null), friend ? "friend" : "owner");
    if (result === "old") await alreadyLinked(cfg, m.chat.id);
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
    // Added to a channel: link it to the app account that asked for it (a fresh "channel" claim),
    // matched through the Telegram user who added the bot. Groups always link through their /start code.
    if ((status === "administrator" || status === "member") && cm.chat.type === "channel" && cm.from?.id) {
      const { data: owners } = await admin.from("saver_tg_targets").select("user_id, created_at")
        .eq("tg_user_id", cm.from.id).eq("role", "owner").order("created_at", { ascending: false });
      const ids = [...new Set((owners ?? []).map((o: any) => o.user_id))];
      if (!ids.length) return;
      const since = new Date(Date.now() - 30 * 60 * 1000).toISOString();
      const { data: claim } = await admin.from("saver_tg_links").select("code, user_id")
        .eq("kind", "channel").in("user_id", ids).gte("created_at", since)
        .order("created_at", { ascending: false }).limit(1).maybeSingle();
      const userId = claim?.user_id ?? ids[0];
      if (claim) await admin.from("saver_tg_links").delete().eq("code", claim.code);
      await linkChat(cfg, userId, cm.chat, cm.from.id);
    }
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const cfg = await config();
  if (!cfg) return json({ error: "not_configured" }, 503);

  // Daily heartbeat sweep (called by the keep-alive workflow); also re-arms the webhook if it drifted.
  if (req.method === "GET" && new URL(req.url).searchParams.has("cron")) {
    await ensureWebhook(cfg);
    return json(await runLegacyCron(cfg));
  }

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
      const kind = ["friend", "channel", "legacy"].includes(body.kind) ? body.kind : "self";
      if (kind === "channel") {
        // Channels are matched through your own Telegram account, so your bot chat must be linked first.
        const { data: own } = await admin.from("saver_tg_targets").select("chat_id")
          .eq("user_id", user.id).eq("role", "owner").eq("type", "private").limit(1);
        if (!own || !own.length) return json({ error: "need_private" }, 409);
      }
      await admin.from("saver_tg_links").insert({ code, user_id: user.id, kind });
      return json({ bot: cfg.bot_username, code });
    }
    case "status": {
      const { data } = await admin.from("saver_tg_targets").select("chat_id, title, type, enabled, role")
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
    case "unlink_all": {
      const { data: all } = await admin.from("saver_tg_targets").select("chat_id, type").eq("user_id", user.id);
      for (const t of all ?? []) {
        if (t.type !== "private") await tg(cfg, "leaveChat", { chat_id: t.chat_id });
      }
      await admin.from("saver_tg_targets").delete().eq("user_id", user.id);
      await admin.from("saver_tg_links").delete().eq("user_id", user.id);
      return json({ ok: true });
    }
    case "legacy_get": {
      const { data } = await admin.from("saver_legacy").select(
        "enabled, interval_days, grace_days, recipient_chat_id, recipient_name, last_seen, state, bundle_at, asked_count"
      ).eq("user_id", user.id).maybeSingle();
      return json(data ?? { enabled: false });
    }
    case "legacy_set": {
      const patch: Record<string, unknown> = { user_id: user.id, updated_at: new Date().toISOString() };
      if (typeof body.enabled === "boolean") { patch.enabled = body.enabled; patch.state = body.enabled ? "ok" : "paused"; }
      if (typeof body.interval_days === "number") patch.interval_days = Math.min(365, Math.max(1, body.interval_days | 0));
      if (typeof body.grace_days === "number") patch.grace_days = Math.min(60, Math.max(1, body.grace_days | 0));
      if (typeof body.bundle === "string") { patch.bundle = body.bundle.slice(0, 200_000); patch.bundle_at = new Date().toISOString(); }
      if (body.clear_recipient) { patch.recipient_chat_id = null; patch.recipient_name = ""; }
      patch.last_seen = new Date().toISOString();
      await admin.from("saver_legacy").upsert(patch, { onConflict: "user_id" });
      const { data } = await admin.from("saver_legacy").select(
        "enabled, interval_days, grace_days, recipient_chat_id, recipient_name, last_seen, state, bundle_at, asked_count"
      ).eq("user_id", user.id).maybeSingle();
      return json(data ?? {});
    }
    case "legacy_checkin": {
      await legacyAlive(cfg, user.id);
      return json({ ok: true });
    }
    case "legacy_test": {
      const { data: row } = await admin.from("saver_legacy").select("*").eq("user_id", user.id).maybeSingle();
      if (!row?.recipient_chat_id) return json({ error: "no_recipient" }, 400);
      await tg(cfg, "sendMessage", { chat_id: row.recipient_chat_id, parse_mode: "HTML",
        text: `\ud83e\uddea <b>\u0631\u0633\u0627\u0644\u0629 \u062a\u062c\u0631\u064a\u0628\u064a\u0629</b>\n${LINE}\n\u0647\u0630\u064a \u0645\u062c\u0631\u062f \u062a\u062c\u0631\u0628\u0629 \u2014 \u0645\u0627 \u0635\u0627\u0631 \u0634\u064a. \u0623\u0646\u062a \u0627\u0644\u0623\u0645\u064a\u0646 \u0639\u0644\u0649 \u0628\u064a\u0627\u0646\u0627\u062a \u0623\u062d\u062f \u0645\u0633\u062a\u062e\u062f\u0645\u064a MNLOVO SAVER.\n${FOOT}` });
      return json({ ok: true });
    }
    case "alert": {
      // An intruder snapshot (or a text-only security alert) to every enabled chat.
      const caption = String(body.caption ?? "").slice(0, 1000);
      const photo = typeof body.photo === "string" ? body.photo : null;
      const { data: targets } = await admin.from("saver_tg_targets").select("chat_id")
        .eq("user_id", user.id).eq("enabled", true);
      let sent = 0;
      for (const t of targets ?? []) {
        const r = photo ? await tgPhoto(cfg, t.chat_id, photo, caption)
                        : await tg(cfg, "sendMessage", { chat_id: t.chat_id, text: caption, parse_mode: "HTML" });
        if (r?.ok) sent++;
      }
      return json({ sent });
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
