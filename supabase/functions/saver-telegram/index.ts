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
    return `✅ <b>تم الربط</b>\n\nصاحب حساب MNLOVO SAVER شاركك تحديثاته، وبتوصلك هنا مرتّبة ومنسّقة.\n\n<i>MNLOVO SAVER · © MNLOVO 2026</i>`;
  }
  const where = kind === "channel" ? "هذي القناة" : kind === "private" ? "هنا" : "هذا القروب";
  return `✅ <b>تم ربط MNLOVO SAVER</b>\n\nمن الحين أي شي تضيفه في التطبيق بيوصل ${where} مرتّب ومنسّق.\nالنصوص تجي مشوّشة، المسها عشان تبين.\n\n<i>MNLOVO SAVER · © MNLOVO 2026</i>`;
}

function chatTitle(chat: Record<string, any>) {
  return chat.title || [chat.first_name, chat.last_name].filter(Boolean).join(" ") || chat.username || String(chat.id);
}

async function alreadyLinked(cfg: Config, chatId: number, fromId?: number) {
  const { data } = await admin.from("saver_tg_targets").select("enabled, role").eq("chat_id", chatId);
  const on = (data ?? []).some((t: any) => t.enabled);
  await tg(cfg, "sendMessage", {
    chat_id: chatId, parse_mode: "HTML",
    text: `✅ <b>مربوط من قبل</b>\n\nهالمحادثة مربوطة بـ MNLOVO SAVER ${on ? "والنشر شغّال 🟢" : "بس النشر موقّف ⏸️"}.\nما تحتاج تسوي شي ثاني.\n\nتبا تتحكم؟ اضغط الزر تحت أو اكتب /menu`,
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

const FOOT = `\n<i>MNLOVO SAVER · © MNLOVO 2026</i>`;
const SUPPORT_ROW = [
  { text: "💬 الدعم — تيليجرام", url: "https://t.me/bscoolvi" },
  { text: "📸 إنستغرام", url: "https://instagram.com/4saf" },
];

/** The button under a ciphered message. Telegram copies up to 256 characters straight from a button;
 *  anything longer goes through a callback that hands over a tap-to-copy message for a minute. */
function copyButton(text: string) {
  return text.length <= 256
    ? { text: "📋 انسخ الشفرة", copy_text: { text } }
    : { text: "📋 انسخ الشفرة", callback_data: "tg:copy" };
}


// ---- What goes where ----------------------------------------------------------------------
// Each linked chat can take any of four kinds of message. A chat whose `routes` is still null
// follows the defaults:
//   items    (accounts, passwords, sensitive and 🔴 secret items) → the first group / channel /
//            private chat the owner added; the bot chat only if there's nothing else
//   intruder (the wrong-attempt photo) → the bot chat only
//   alerts   (reminders) and attempts (every wrong try, as text) → off
const KINDS = ["items", "alerts", "intruder", "attempts"];
type RouteRow = { chat_id: number; type: string; role: string; enabled: boolean; routes: string[] | null; created_at?: string; title?: string };
const isBotChat = (t: RouteRow) => t.type === "private" && t.role !== "friend";

function defaultRoutes(t: RouteRow, all: RouteRow[]): string[] {
  const home = all.find((x) => !isBotChat(x)) ?? all.find(isBotChat);
  const r: string[] = [];
  if (home && home.chat_id === t.chat_id) r.push("items");
  if (isBotChat(t)) r.push("intruder");
  return r;
}
function routesOf(t: RouteRow, all: RouteRow[]): string[] {
  return Array.isArray(t.routes) ? t.routes.filter((k) => KINDS.includes(k)) : defaultRoutes(t, all);
}
async function routedTargets(userId: string, kind: string): Promise<RouteRow[]> {
  const { data } = await admin.from("saver_tg_targets").select("chat_id, type, role, enabled, routes, created_at")
    .eq("user_id", userId).order("created_at");
  const all = (data ?? []) as RouteRow[];
  return all.filter((t) => t.enabled && routesOf(t, all).includes(kind));
}

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
      text: `👋 <b>هالمحادثة مب مربوطة</b>\n\nافتح تطبيق MNLOVO SAVER ← الإعدادات ← تيليجرام ← «ربط تيليجرام بضغطة».\n${FOOT}`,
      reply_markup: { inline_keyboard: [SUPPORT_ROW] } });
    return;
  }
  const t = ts[0];
  const owner = await ownerOf(t, fromId);
  const kb: any[][] = [[{ text: t.enabled ? "⏸️ وقّف النشر هنا" : "▶️ شغّل النشر هنا", callback_data: "tg:toggle" }]];
  if (owner) {
    kb.push([{ text: "👤 أضف شخص ثاني يستقبل", callback_data: "tg:share" }]);
    if (t.type === "private") {
      kb.push([{ text: "🧪 جرّب رسالة بعد الوفاة", callback_data: "tg:legacy_test" }]);
      kb.push([{ text: "🆘 مساعدة في استرجاع الحساب", callback_data: "tg:recover" }]);
    }
  }
  kb.push([{ text: t.role === "friend" ? "🚪 وقّف استقبالي نهائياً" : "🔌 فصل البوت من هنا", callback_data: "tg:unlink" }]);
  kb.push(SUPPORT_ROW);
  const text = `⚙️ <b>التحكم بـ MNLOVO SAVER</b>\n\nالحالة: ${t.enabled ? "🟢 النشر شغّال" : "⏸️ النشر موقّف"}\nالنوع: ${
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
      text: `❤️ <b>الحمدلله</b>

سجّلنا إنك بخير ✓ ورجع العدّاد من الأول.

خلّك تفتح التطبيق كل فترة وما بنزعجك.${FOOT}` });
  }
}

/** The rehearsal message the trustee gets — worded so it can never be mistaken for the real one. */
async function legacyTest(cfg: Config, chatId: number) {
  await tg(cfg, "sendMessage", { chat_id: chatId, parse_mode: "HTML",
    text: `🧪 <b>تجربة — ما صار شي</b>

هذي رسالة تجريبية طلبها صاحب الحساب بنفسه، عشان يتأكد إنها توصلك.

إنت الأمين على بياناته ووصيته إذا توفّى. لو صارت الرسالة الحقيقية يوم، بتكون واضحة وما فيها كلمة «تجربة».

ما تحتاج تسوي أي شي الحين 🤍${FOOT}` });
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
  const who = reg?.username ? esc(reg.username) : (reg?.email_hint || "صاحب الحساب");
  await tg(cfg, "sendMessage", { chat_id: row.recipient_chat_id, parse_mode: "HTML",
    text: `🕊️ <b>أمانة ${who}</b>

${who} اختارك أميناً على بياناته ووصيته بعد وفاته.

ما فتح التطبيق من ${row.interval_days} يوم، وسألناه كل يوم طوال ${row.grace_days} أيام وما رد.
عشان كذا نسلّمك أمانته الحين.

تحت بياناته ووصيته زي ما تركها. احتفظ فيها ولا تعطيها لأحد 🤲

<i>إذا تعرف إنه بخير، خبّره يفتح التطبيق وبنوقف كل شي.</i>${FOOT}` });
  for (const part of chunk(row.bundle)) {
    await tg(cfg, "sendMessage", { chat_id: row.recipient_chat_id, text: esc(part), parse_mode: "HTML" });
  }
  await admin.from("saver_legacy").update({ state: "released", released_at: new Date().toISOString() }).eq("user_id", row.user_id);
  // Tell the owner too, in case they are simply away.
  const { data: own } = await admin.from("saver_tg_targets").select("chat_id")
    .eq("user_id", row.user_id).eq("role", "owner").eq("type", "private").limit(1).maybeSingle();
  if (own) {
    await tg(cfg, "sendMessage", { chat_id: own.chat_id, parse_mode: "HTML",
      text: `ℹ️ <b>سلّمنا أمانتك</b>

ما وصلنا منك رد طوال المدة اللي حددتها، فسلّمنا بياناتك ووصيتك لـ ${esc(row.recipient_name || "الشخص اللي اخترته")}.

لو هذا صار بالغلط: افتح التطبيق ← «بعد وفاتي» ← وقّف الخاصية أو عدّل المدة، وغيّر كلمات سرّك المهمة.${FOOT}` });
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
      text: `🫀 <b>إنت بخير؟</b>

صار لك ${row.interval_days} يوم ما فتحت MNLOVO SAVER، وخاصية «بعد وفاتي» شغّالة.

اضغط الزر تحت وبس — عشان نعرف إنك موجود.

⏳ باقي ${left} يوم، وبعدها نسلّم بياناتك ووصيتك لـ ${esc(row.recipient_name || "الشخص اللي اخترته")}.${FOOT}`,
      reply_markup: { inline_keyboard: [
        [{ text: "❤️ أنا بخير", callback_data: "tg:alive" }],
        [{ text: "⏸️ أوقِف الخاصية", callback_data: "tg:legacy_off" }],
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
  if (!ts.length) { await answer("هالمحادثة مب مربوطة."); return; }
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
    case "tg:alive": {
      if (!owner) return await answer("بس صاحب الحساب.", true);
      await answer("الحمدلله ❤️");
      await legacyAlive(cfg, t.user_id, chatId);
      return;
    }
    case "tg:legacy_off": {
      if (!owner) return await answer("بس صاحب الحساب.", true);
      await admin.from("saver_legacy").update({ enabled: false, state: "paused", updated_at: new Date().toISOString() }).eq("user_id", t.user_id);
      await answer("وقّفنا الخاصية ⏸️");
      await tg(cfg, "sendMessage", { chat_id: chatId, parse_mode: "HTML",
        text: `⏸️ <b>وقّفنا «بعد وفاتي»</b>\n\nما بينطرش شي لأحد. تقدر ترجع تشغّلها من التطبيق.${FOOT}` });
      return;
    }
    case "tg:share": {
      if (!owner) return await answer("بس صاحب الحساب.", true);
      const code = crypto.randomUUID().replace(/-/g, "").slice(0, 24);
      await admin.from("saver_tg_links").insert({ code, user_id: t.user_id, kind: "friend" });
      const link = `https://t.me/${cfg.bot_username}?start=${code}`;
      await answer();
      await tg(cfg, "sendMessage", { chat_id: chatId, parse_mode: "HTML",
        text: `👤 <b>رابط لشخص ثاني</b>\n\nطرش هالرابط للشخص اللي تباه يستقبل تحديثاتك. أول ما يفتحه ويضغط «ابدأ» ينربط.\n\n<code>${link}</code>\n\n⏳ صالح لمدة ٣٠ دقيقة ولمرة وحدة.\n${FOOT}`,
        reply_markup: { inline_keyboard: [
          [{ text: "📤 طرش الرابط", url: `https://t.me/share/url?url=${encodeURIComponent(link)}&text=${encodeURIComponent("اضغط الرابط وبعدين «ابدأ» عشان توصلك تحديثات MNLOVO SAVER")}` }],
          [{ text: "↩️ رجوع للتحكم", callback_data: "tg:menu" }],
        ] } });
      return;
    }
    case "tg:recover": {
      if (!owner) return await answer("بس صاحب الحساب.", true);
      const { data: reg } = await admin.from("saver_accounts").select("email_hint, username").eq("user_id", t.user_id).maybeSingle();
      await answer();
      await tg(cfg, "sendMessage", { chat_id: chatId, parse_mode: "HTML",
        text: `🆘 <b>مساعدة في استرجاع الحساب</b>\n\nالحساب المربوط هنا:\n👤 ${reg?.username ? esc(reg.username) : "—"}\n✉️ ${reg?.email_hint ?? "—"}\n\n<b>إذا نسيت كلمة المرور:</b>\n١. افتح التطبيق ← «نسيت كلمة المرور؟»\n٢. حط الإيميل ورقم الهاتف وتاريخ الميلاد\n٣. حط الكود اللي يوصلك على الإيميل\n٤. رمز التحقق المتغير + Face ID، أو مفتاح الاسترجاع (٦ مجموعات)\n٥. سوّ كلمة مرور جديدة ✓\n\n<b>تلفون جديد؟</b> «عندي حساب، تسجيل دخول» ← بالإيميل ← كلمة المرور أو مفتاح الاسترجاع.\n\n🔒 البوت يساعدك بس، ما يقدر يفتح خزنتك ولا يغيّر كلمة المرور — بياناتك مشفّرة في تلفونك.\nما نطلب منك أبداً كلمة المرور أو مفتاح الاسترجاع.\n${FOOT}`,
        reply_markup: { inline_keyboard: [SUPPORT_ROW, [{ text: "↩️ رجوع للتحكم", callback_data: "tg:menu" }]] } });
      return;
    }
    case "tg:legacy_test": {
      if (!owner) return await answer("بس صاحب الحساب.", true);
      const { data: row } = await admin.from("saver_legacy")
        .select("recipient_chat_id, recipient_name, enabled, bundle").eq("user_id", t.user_id).maybeSingle();
      if (!row?.recipient_chat_id) {
        return await answer("ما عيّنت أمين بعد. افتح التطبيق ← بعد وفاتي ← اختر الشخص.", true);
      }
      await answer("طرشناها ✓");
      await legacyTest(cfg, row.recipient_chat_id);
      await tg(cfg, "sendMessage", { chat_id: chatId, parse_mode: "HTML",
        text: `🧪 <b>وصلت التجربة</b>

طرشنا رسالة تجريبية لـ ${esc(row.recipient_name || "الأمين")}، وواضح فيها إنها تجربة بس.
${row.enabled ? (row.bundle ? "الخاصية شغّالة والأمانة محفوظة ✓" : "⚠️ الخاصية شغّالة بس ما حفظت الأمانة بعد — افتح التطبيق واضغط «حدّث الوصية والبيانات».") : "⏸️ الخاصية موقّفة حالياً، فما بينطرش شي فعلاً."}${FOOT}`,
        reply_markup: { inline_keyboard: [[{ text: "↩️ رجوع للتحكم", callback_data: "tg:menu" }]] } });
      return;
    }
    case "tg:copy": {
      // The cipher is the blurred part of the message: read it back by its spoiler entity.
      const ent = (q.message?.entities ?? []).find((e: any) => e.type === "spoiler");
      const blob = ent ? String(q.message.text ?? "").slice(ent.offset, ent.offset + ent.length) : "";
      if (!blob) return await answer("ما لقيت الشفرة في هالرسالة.", true);
      await answer("اضغط على النص اللي وصلك وينسخ بنفسه");
      const sent = await tg(cfg, "sendMessage", { chat_id: chatId, parse_mode: "HTML",
        text: `<code>${esc(blob)}</code>\n\n<i>اضغط عليه وينسخ · ينمسح بعد دقيقة</i>`,
        reply_to_message_id: msgId });
      if (sent?.ok) {
        later((async () => {
          await sleep(60_000);
          await tg(cfg, "deleteMessage", { chat_id: chatId, message_id: sent.result.message_id });
        })());
      }
      return;
    }
    case "tg:unlink": {
      await answer();
      await tg(cfg, "editMessageText", { chat_id: chatId, message_id: msgId, parse_mode: "HTML",
        text: `🔌 <b>متأكد تبا تفصل البوت من هنا؟</b>\nما بيوصل هنا أي شي بعدها. تقدر ترجع تربطه من التطبيق.`,
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
          text: `👋 <b>أهلاً فيك في MNLOVO SAVER</b>\n\nعشان تربط حسابك:\n١. افتح تطبيق MNLOVO SAVER\n٢. الإعدادات ← تيليجرام\n٣. اضغط «ربط تيليجرام بضغطة»\n\nوبس! التطبيق يرجعك هنا ويربط بنفسه.\n\n<i>MNLOVO SAVER · © MNLOVO 2026</i>`,
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
      const { data: whoReg } = await admin.from("saver_accounts").select("username").eq("user_id", link.user_id).maybeSingle();
      const whoName = whoReg?.username ? esc(whoReg.username) : "واحد من مستخدمي MNLOVO SAVER";
      await tg(cfg, "sendMessage", { chat_id: m.chat.id, parse_mode: "HTML",
        text: `🤝 <b>صرت أمينه بعد وفاته</b>

${whoName} اختارك الشخص اللي يستلم بياناته ووصيته إذا توفّى، لا سمح الله.

<b>كيف تمشي؟</b>
• التطبيق يراقب آخر مرة فتحه.
• إذا انقطع مدة طويلة، يسأله أول: «إنت بخير؟»
• إذا ما رد أبداً، يسلّمك أمانته هنا — حساباته وكلمات سرّه ووصيته.

ما بيوصلك شي الحين، ولا تحتاج تسوي أي شي. بس خلّ هالمحادثة موجودة.

🤲 إذا وصلتك يوم، احتفظ فيها ولا تعطيها لأحد.${FOOT}` });
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
      const { data } = await admin.from("saver_tg_targets").select("chat_id, title, type, enabled, role, routes, created_at")
        .eq("user_id", user.id).order("created_at");
      const all = (data ?? []) as RouteRow[];
      const targets = all.map((t) => ({ chat_id: t.chat_id, title: t.title, type: t.type, enabled: t.enabled, role: t.role,
                                         routes: routesOf(t, all), custom: Array.isArray(t.routes) }));
      return json({ bot: cfg.bot_username, targets });
    }
    case "routes": {
      // body.routes: { "<chat_id>": ["items", ...], ... } — the whole picture, saved per chat
      const map = (body.routes && typeof body.routes === "object") ? body.routes as Record<string, unknown> : {};
      for (const [id, list] of Object.entries(map)) {
        const clean = Array.isArray(list) ? [...new Set(list.filter((k) => KINDS.includes(String(k))).map(String))] : [];
        await admin.from("saver_tg_targets").update({ routes: clean }).eq("user_id", user.id).eq("chat_id", Number(id));
      }
      if (body.reset) await admin.from("saver_tg_targets").update({ routes: null }).eq("user_id", user.id);
      return json({ ok: true });
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
      if (body.clear_recipient) {
        // Courtesy: whoever was carrying the trust should hear that they no longer are.
        const { data: old } = await admin.from("saver_legacy")
          .select("recipient_chat_id").eq("user_id", user.id).maybeSingle();
        if (old?.recipient_chat_id) {
          later(tg(cfg, "sendMessage", { chat_id: old.recipient_chat_id, parse_mode: "HTML",
            text: `🤍 <b>انتهت أمانتك</b>

صاحب الحساب في MNLOVO SAVER ألغى تعيينك أميناً على بياناته.

ما بيوصلك شي بعد الحين، ولا تحتاج تسوي أي شي. شكراً إنك كنت الشخص اللي وثّق فيه.${FOOT}` }));
        }
        patch.recipient_chat_id = null; patch.recipient_name = "";
      }
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
      await legacyTest(cfg, row.recipient_chat_id);
      return json({ ok: true });
    }
    case "alert": {
      // An intruder snapshot (or a text-only security alert) to every enabled chat.
      const caption = String(body.caption ?? "").slice(0, 1000);
      const photo = typeof body.photo === "string" ? body.photo : null;
      const targets = await routedTargets(user.id, body.kind === "attempts" ? "attempts" : "intruder");
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
      const copy = typeof body.copy === "string" ? body.copy : "";
      const targets = await routedTargets(user.id, KINDS.includes(body.kind) ? body.kind : "items");
      let sent = 0;
      for (const t of targets ?? []) {
        const msg: Record<string, unknown> = { text, parse_mode: "HTML", link_preview_options: { is_disabled: true } };
        if (copy) msg.reply_markup = { inline_keyboard: [[copyButton(copy)]] };
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
