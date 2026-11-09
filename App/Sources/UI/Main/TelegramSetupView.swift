import SwiftUI

/// Looping animation: something is added in the app → a paper plane flies → a neat message lands in Telegram.
struct TelegramExplainer: View {
    @State private var phase = 0          // 0 add, 1 fly, 2 delivered
    @State private var fly: CGFloat = 0
    @State private var bubble = false
    @State private var newRow = false

    private var caption: String {
        switch phase {
        case 0: return tr("تضيف حساب أو تذكير أو ملاحظة…", "You add an account, reminder or note…")
        case 1: return tr("التطبيق يرسله لحاله…", "The app sends it on its own…")
        default: return tr("ويوصل لتيليجرام مرتّب ومنسّق ✓", "and it lands in Telegram, neatly formatted ✓")
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            GeometryReader { g in
                let w = g.size.width
                ZStack {
                    // phone
                    VStack(spacing: 6) {
                        ForEach(0..<2, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 6).fill(Theme.surfaceHi).frame(height: 14)
                        }
                        HStack(spacing: 4) {
                            Image(systemName: "key.horizontal.fill").font(.system(size: 9, weight: .bold))
                            RoundedRectangle(cornerRadius: 3).fill(Theme.accent.opacity(0.7)).frame(height: 8)
                        }
                        .foregroundStyle(Theme.accent)
                        .padding(5)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.accent.opacity(0.14)))
                        .scaleEffect(newRow ? 1 : 0.3)
                        .opacity(newRow ? 1 : 0)
                    }
                    .padding(10)
                    .frame(width: 84, height: 132)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.stroke))
                    .position(x: 56, y: 72)

                    // telegram chat
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            Image(systemName: "paperplane.circle.fill").foregroundStyle(Color(hex: 0x2AABEE))
                            RoundedRectangle(cornerRadius: 3).fill(Theme.surfaceHi).frame(width: 50, height: 7)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("🔐 " + tr("حساب جديد", "New account")).font(Theme.font(10, .bold))
                            RoundedRectangle(cornerRadius: 2).fill(Theme.faint).frame(width: 70, height: 5)
                            RoundedRectangle(cornerRadius: 2).fill(Theme.faint).frame(width: 52, height: 5)
                            RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0x2AABEE).opacity(0.6)).frame(width: 60, height: 5)
                        }
                        .foregroundStyle(Theme.text)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0x2AABEE).opacity(0.18)))
                        .scaleEffect(bubble ? 1 : 0.4, anchor: .topLeading)
                        .opacity(bubble ? 1 : 0)
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .frame(width: 120, height: 132)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color(hex: 0x2AABEE).opacity(0.5)))
                    .position(x: w - 70, y: 72)

                    // paper plane along an arc
                    let startX: CGFloat = 100, endX = w - 130
                    let x = startX + (endX - startX) * fly
                    let y = 72 - sin(fly * .pi) * 52
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color(hex: 0x2AABEE))
                        .rotationEffect(.degrees(Double(-35 + fly * 70)))
                        .shadow(color: Color(hex: 0x2AABEE).opacity(0.8), radius: 8)
                        .position(x: x, y: y)
                        .opacity(phase == 1 ? 1 : 0)
                }
            }
            .frame(height: 144)
            .environment(\.layoutDirection, .leftToRight)

            Text(caption)
                .font(Theme.font(15, .bold)).foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
                .id(phase)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: phase)
        }
        .padding(16)
        .glass(0, radius: 24, tint: Color(hex: 0x2AABEE))
        .task { await loop() }
    }

    private func loop() async {
        while !Task.isCancelled {
            withAnimation { phase = 0; bubble = false; newRow = false }
            fly = 0
            await pause(0.5)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { newRow = true }
            await pause(1.1)
            withAnimation { phase = 1 }
            withAnimation(.easeInOut(duration: 1.0)) { fly = 1 }
            await pause(1.0)
            withAnimation { phase = 2 }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.62)) { bubble = true }
            await pause(2.4)
        }
    }
}

struct TelegramSetupView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var settings = TelegramService.shared.settings
    @State private var token = TelegramService.shared.token ?? ""
    @State private var chats: [TelegramService.Chat] = []
    @State private var verifying = false
    @State private var searching = false
    @State private var error: String?
    @State private var manualChat = ""
    @FocusState private var focus: AYNFieldID?

    private let tg = TelegramService.shared

    var body: some View {
        SheetScaffold(title: tr("تيليجرام", "Telegram")) {
            TelegramExplainer()

            Label(tr("رسائل البوت في تيليجرام مو مشفّرة طرف لطرف. الأشياء 🔴 السرية جداً ما تنرسل أبداً، وكلمات السر ما تنرسل إلا إذا فعّلتها (وتطلع مخفية تحت غطاء).",
                     "Bot messages in Telegram aren't end-to-end encrypted. 🔴 Top-secret items are never sent, and passwords only if you turn it on (shown hidden under a spoiler)."),
                  systemImage: "exclamationmark.shield.fill")
                .font(Theme.font(12, .medium)).foregroundStyle(Theme.warn)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glass(12, tint: Theme.warn)

            // Step 1 — bot
            stepTitle(1, tr("سوّ بوت", "Create a bot"), done: !settings.botName.isEmpty)
            VStack(alignment: .leading, spacing: 8) {
                Text(tr("افتح @BotFather ← اكتب /newbot ← اختر اسم ← انسخ الرمز اللي يعطيك إياه والصقه هنا.",
                        "Open @BotFather → send /newbot → pick a name → copy the token it gives you and paste it here."))
                    .font(Theme.font(13)).foregroundStyle(Theme.sub)
                SecondaryButton(title: tr("افتح BotFather", "Open BotFather"), icon: "paperplane.fill", color: Color(hex: 0x2AABEE)) {
                    if let u = URL(string: "https://t.me/BotFather") { openURL(u) }
                }
                AYNField(title: tr("رمز البوت (Token)", "Bot token"), icon: "key.fill", text: $token, secure: true,
                         focus: $focus, id: .secret)
                    .environment(\.layoutDirection, .leftToRight)
                HStack(spacing: 10) {
                    PasteButton(payloadType: String.self) { items in
                        if let t = items.first { DispatchQueue.main.async { token = t.trimmingCharacters(in: .whitespacesAndNewlines) } }
                    }
                    .buttonBorderShape(.capsule).tint(Theme.accent).controlSize(.small)
                    Spacer()
                    if !settings.botName.isEmpty {
                        Label("@\(settings.botName)", systemImage: "checkmark.seal.fill").font(Theme.font(13, .bold)).foregroundStyle(Theme.ok)
                    }
                }
                PrimaryButton(title: tr("تحقق من البوت", "Verify bot"), icon: "checkmark.shield.fill", loading: verifying,
                              enabled: token.count > 20) { Task { await verifyBot() } }
            }
            .glass(14)

            // Step 2 — chat
            stepTitle(2, tr("اختر وين يوصل", "Choose where it goes"), done: settings.chat != nil)
            VStack(alignment: .leading, spacing: 10) {
                Text(tr("• قناة: أضف البوت مشرف (Admin) فيها.\n• قروب: أضف البوت عضو.\n• محادثة خاصة: افتح البوت واضغط Start.\nبعدها أرسل أي رسالة هناك واضغط «ابحث».",
                        "• Channel: add the bot as an admin.\n• Group: add the bot as a member.\n• Private chat: open the bot and tap Start.\nThen send any message there and tap “Search”."))
                    .font(Theme.font(13)).foregroundStyle(Theme.sub)
                SecondaryButton(title: tr("ابحث عن المحادثات", "Search chats"), icon: "magnifyingglass", color: Theme.accent) {
                    Task { await search() }
                }
                .disabled(settings.botName.isEmpty || searching)
                if searching { ProgressView().tint(Theme.accent).frame(maxWidth: .infinity) }
                ForEach(chats) { c in
                    Button {
                        Haptics.selection()
                        settings.chat = c
                        save()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: c.icon).foregroundStyle(Color(hex: 0x2AABEE)).frame(width: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.title).font(Theme.font(15, .semibold)).foregroundStyle(Theme.text)
                                Text(c.typeTitle).font(Theme.font(11)).foregroundStyle(Theme.sub)
                            }
                            Spacer()
                            if settings.chat?.id == c.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.ok) }
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 14).fill(settings.chat?.id == c.id ? Theme.ok.opacity(0.12) : Theme.surface))
                    }
                    .buttonStyle(PressScale())
                }
                if let c = settings.chat, !chats.contains(where: { $0.id == c.id }) {
                    Label(tr("المختارة: \(c.title)", "Selected: \(c.title)"), systemImage: "checkmark.circle.fill")
                        .font(Theme.font(13, .bold)).foregroundStyle(Theme.ok)
                }
                HStack(spacing: 8) {
                    AYNField(title: tr("أو اكتب رقم المحادثة / @القناة", "Or type a chat ID / @channel"), icon: "number", text: $manualChat,
                             focus: $focus, id: .title)
                        .environment(\.layoutDirection, .leftToRight)
                    CircleIconButton(icon: "checkmark", size: 46, tint: Theme.accent) { useManual() }
                }
            }
            .glass(14)

            // Step 3 — what to send
            stepTitle(3, tr("وش يوصل", "What gets sent"), done: settings.chat != nil)
            VStack(spacing: 0) {
                option("key.horizontal.fill", tr("الحسابات", "Accounts"), $settings.accounts)
                option("eye.slash.fill", tr("كلمات السر (مخفية تحت غطاء)", "Passwords (hidden under a spoiler)"), $settings.passwords)
                option("bell.fill", tr("التذكيرات", "Reminders"), $settings.reminders)
                option("note.text", tr("الملاحظات", "Notes"), $settings.notes)
                option("paperclip", tr("الملفات (الاسم والحجم بس)", "Files (name & size only)"), $settings.files)
                option("pencil", tr("التعديلات كمان", "Edits too"), $settings.updates)
                option("shield.lefthalf.filled", tr("العناصر 🟡 الحساسة", "🟡 Sensitive items"), $settings.includeSensitive)
            }
            .glass(12)
            .onChange(of: settings) { _, _ in save() }

            if let error { Text(error).font(Theme.font(13, .semibold)).foregroundStyle(Theme.danger) }

            HStack(spacing: 10) {
                SecondaryButton(title: tr("رسالة تجريبية", "Test message"), icon: "paperplane") { Task { await test() } }
                    .disabled(settings.chat == nil)
            }
            PrimaryButton(title: settings.enabled ? tr("إيقاف الخاصية", "Turn off") : tr("تفعيل الخاصية", "Turn on"),
                          icon: settings.enabled ? "pause.fill" : "bolt.fill",
                          enabled: settings.enabled || (settings.chat != nil && !settings.botName.isEmpty)) {
                settings.enabled.toggle()
                save()
                if settings.enabled {
                    SoundFX.shared.play(.success, volume: 0.5)
                    state.show(tr("تم التفعيل ✓ أي شي تضيفه بيوصل تيليجرام", "On ✓ new items will be posted to Telegram"), icon: "paperplane.fill")
                    Task { try? await tg.send(tg.testMessage()) }
                }
            }
        }
        .onAppear { if let e = UserDefaults.standard.string(forKey: "tg.lastError"), settings.enabled { error = e } }
    }

    private func stepTitle(_ n: Int, _ title: String, done: Bool) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(done ? AnyShapeStyle(Theme.ok) : AnyShapeStyle(Theme.gradient)).frame(width: 24, height: 24)
                if done { Image(systemName: "checkmark").font(.system(size: 11, weight: .black)).foregroundStyle(Theme.bg) }
                else { Text("\(n)").font(Theme.font(12, .black)).foregroundStyle(Theme.bg) }
            }
            Text(title).font(Theme.font(17, .heavy)).foregroundStyle(Theme.text)
            Spacer()
        }
        .padding(.top, 4)
    }

    private func option(_ icon: String, _ title: String, _ binding: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(hex: 0x2AABEE)).frame(width: 26)
            Text(title).font(Theme.font(14, .semibold)).foregroundStyle(Theme.text)
            Spacer()
            Toggle("", isOn: binding).labelsHidden().tint(Theme.accent)
        }
        .padding(.vertical, 7)
    }

    private func save() { tg.settings = settings }

    private func verifyBot() async {
        verifying = true
        defer { verifying = false }
        do {
            let name = try await tg.verify(token: token)
            tg.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.botName = name
            save()
            error = nil
            Haptics.success()
            await search()
        } catch {
            self.error = error.localizedDescription
            FX.error()
        }
    }

    private func search() async {
        guard let t = tg.token else { return }
        searching = true
        defer { searching = false }
        do {
            chats = try await tg.discoverChats(token: t)
            if chats.isEmpty {
                error = tr("ما لقيت محادثات. أرسل رسالة في القناة/القروب بعد ما تضيف البوت، وجرّب مرة ثانية.",
                           "No chats found. Send a message in the channel/group after adding the bot, then try again.")
            } else { error = nil }
        } catch { self.error = error.localizedDescription }
    }

    private func useManual() {
        let v = manualChat.trimmingCharacters(in: .whitespaces)
        if let id = Int64(v) {
            settings.chat = TelegramService.Chat(id: id, title: v, type: "chat")
            save()
            Haptics.success()
        } else if v.hasPrefix("@") {
            error = tr("للقنوات العامة: أضف البوت مشرف وأرسل رسالة، بعدها اضغط «ابحث عن المحادثات».",
                       "For public channels: add the bot as admin, post a message, then tap “Search chats”.")
        }
    }

    private func test() async {
        do {
            try await tg.send(tg.testMessage())
            Haptics.success()
            state.show(tr("انرسلت رسالة تجريبية ✓", "Test message sent ✓"), icon: "paperplane.fill")
            error = nil
        } catch { self.error = error.localizedDescription; FX.error() }
    }
}
