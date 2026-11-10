import SwiftUI

// MARK: - Animated explainer (used in Settings and during sign-up)

/// The story told on real screens, the way the Telegram and reminders walkthroughs tell theirs:
/// your phone with the app open → the same phone left untouched while the days count up → the
/// bot's daily "are you okay?" piling up in your chat → one tap that resets everything → and, if
/// that tap never comes, your trustee's phone receiving the will and the data, message by message.
///
/// Earlier versions tried a candle, then an abstract pulse line. Both asked the viewer to decode a
/// metaphor. This one simply shows what will actually happen, on the screens where it happens.
struct LegacyExplainer: View {
    @State private var scene = 0
    @State private var step = 0
    @State private var auto = true
    private let blue = TelegramService.blue
    private let rose = Color(hex: 0xFF5FA2)
    private let beats = [3, 4, 4, 3, 5]

    private var captions: [(String, String)] {
        [(tr("طول ما إنت تستخدم التطبيق، كل شي عادي", "As long as you use the app, nothing happens"),
          tr("كل مرة تفتح خزنتك نسجّل إنك بخير. ما نطلب منك أي شي زيادة.",
             "Every time you open your vault we note that you're fine. Nothing extra is asked of you.")),
         (tr("لو توفّيت — لا سمح الله — التلفون يسكت", "If you die — God forbid — the phone goes quiet"),
          tr("محد يفتح التطبيق. تعدّي المدة اللي حددتها — ٣٠ يوم مثلاً — بدون أي أثر منك.",
             "Nobody opens the app. The period you chose — say 30 days — passes with no sign of you.")),
         (tr("ما نستعجل: البوت يسأل عنك كل يوم", "We don't rush: the bot asks after you daily"),
          tr("يطرش لك «إنت بخير؟» كل يوم مدة إضافية، عشان وصيتك ما تتنفّذ وإنت حي.",
             "It messages you “Are you okay?” daily for an extra period, so your will is never executed while you're alive.")),
         (tr("ضغطة وحدة وكل شي يرجع", "One tap and everything goes back"),
          tr("تضغط «أنا بخير» — أو بس تفتح التطبيق — والعدّاد يبدأ من الصفر.",
             "Tap “I'm fine” — or just open the app — and the counter starts from zero.")),
         (tr("ما رديت أبداً؟ الأمين يستلم", "No answer at all? Your trustee receives it"),
          tr("توصله على تيليجرامه: وصيتك أول شي، وبعدها البيانات اللي حددتها له. مرة وحدة، وله هو بس.",
             "It arrives in his Telegram: your will first, then the data you picked for him. Once, and only him."))]
    }

    private var trusteeScene: Bool { scene == 4 }

    var body: some View {
        VStack(spacing: 14) {
            // whose phone we're looking at
            HStack(spacing: 6) {
                Image(systemName: trusteeScene ? "person.fill" : "iphone")
                    .font(.system(size: 11, weight: .bold))
                Text(trusteeScene ? tr("تلفون الأمين", "Your trustee's phone") : tr("تلفونك", "Your phone"))
                    .font(Theme.font(12, .bold))
            }
            .foregroundStyle(trusteeScene ? Theme.accent2 : Theme.sub)
            .padding(.horizontal, 12).frame(height: 28)
            .background(Capsule().fill((trusteeScene ? Theme.accent2 : Theme.sub).opacity(0.12)))
            .id(trusteeScene)
            .transition(.scale(scale: 0.8).combined(with: .opacity))

            phone
                .frame(width: 204, height: 322)
                .id(trusteeScene)          // the trustee's phone slides in as a different device
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))

            VStack(spacing: 6) {
                Text(captions[scene].0).font(Theme.font(18, .heavy)).foregroundStyle(Theme.text)
                Text(captions[scene].1).font(Theme.font(14)).foregroundStyle(Theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .top)
            .id("cap\(scene)")
            .transition(.opacity.combined(with: .move(edge: .bottom)))

            HStack(spacing: 6) {
                ForEach(0..<captions.count, id: \.self) { i in
                    Capsule().fill(i == scene ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.surfaceHi))
                        .frame(width: i == scene ? 24 : 8, height: 8)
                        .onTapGesture { auto = false; go(i) }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .glass(0, radius: 24, tint: trusteeScene ? Theme.accent2 : Theme.accent3)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 24).onEnded { g in
                guard abs(g.translation.width) > abs(g.translation.height) else { return }
                auto = false
                let forward = AppLanguage.current.isRTL ? g.translation.width > 0 : g.translation.width < 0
                if forward, scene < captions.count - 1 { go(scene + 1) }
                else if !forward, scene > 0 { go(scene - 1) }
            }
        )
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: scene)
        .task(id: scene) { await play() }
    }

    private func go(_ i: Int) {
        Haptics.selection()
        withAnimation { scene = i; step = 0 }
    }

    private func play() async {
        step = 0
        for b in 1...beats[scene] {
            await pause(0.75)
            if Task.isCancelled { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) { step = b }
        }
        await pause(2.6)
        guard auto, !Task.isCancelled else { return }
        go((scene + 1) % captions.count)
    }

    // MARK: The phone

    private var phone: some View {
        let tint = trusteeScene ? Theme.accent2 : (scene == 1 ? Color.gray : Theme.accent3)
        return ZStack {
            RoundedRectangle(cornerRadius: 34).fill(Color.black.opacity(0.66))
            Group {
                switch scene {
                case 0: homeScreen
                case 1: silentScreen
                case 2: askScreen
                case 3: aliveScreen
                default: trusteeScreen
                }
            }
            .padding(.horizontal, 13).padding(.top, 34).padding(.bottom, 15)
            .id(scene)
            .transition(.opacity)
            RoundedRectangle(cornerRadius: 34).strokeBorder(
                LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)], startPoint: .top, endPoint: .bottom),
                lineWidth: 2)
            Capsule().fill(Color.black).frame(width: 62, height: 17)
                .frame(maxHeight: .infinity, alignment: .top).padding(.top, 10)
        }
        .shadow(color: tint.opacity(0.3), radius: 22)
    }

    private func chatHeader(_ title: String, _ sub: String, icon: String, tint: AnyShapeStyle) -> some View {
        HStack(spacing: 7) {
            Circle().fill(tint).frame(width: 24, height: 24)
                .overlay(Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.font(10, .heavy)).foregroundStyle(Theme.text)
                Text(sub).font(Theme.font(8)).foregroundStyle(Theme.faint)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 5)
        .overlay(Rectangle().fill(Theme.stroke).frame(height: 0.5), alignment: .bottom)
    }

    private func bubble<C: View>(_ show: Bool, tint: Color = Theme.surfaceHi, @ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(tint))
            .scaleEffect(show ? 1 : 0.6, anchor: .bottomLeading)
            .opacity(show ? 1 : 0)
    }

    /// Scene 1 — the app, in use: the eye is awake and today's visit is logged.
    private var homeScreen: some View {
        VStack(spacing: 9) {
            Text("MNLOVO SAVER").font(Theme.font(9, .heavy)).tracking(2).foregroundStyle(Theme.faint)
            EyeView(mood: .happy, size: 74, sounds: false)
            IntroBits.row("key.horizontal.fill", "Instagram", "saif@mnlovo", tint: Theme.accent, on: step >= 1)
            IntroBits.row("lock.doc.fill", tr("الجواز", "Passport"), tr("الخزنة", "Vault"), tint: Theme.accent2, on: step >= 2)
            Spacer(minLength: 0)
            Label(tr("آخر دخول: الحين ✓", "Last opened: just now ✓"), systemImage: "heart.fill")
                .font(Theme.font(10, .bold)).foregroundStyle(Theme.ok)
                .padding(.horizontal, 10).frame(height: 26)
                .background(Capsule().fill(Theme.ok.opacity(0.14)))
                .scaleEffect(step >= 3 ? 1 : 0.7).opacity(step >= 3 ? 1 : 0)
        }
    }

    /// Scene 2 — the same phone, untouched: a lock screen whose day counter keeps climbing.
    private var silentScreen: some View {
        let days = [1, 9, 18, 26, 30][min(step, 4)]
        return VStack(spacing: 10) {
            Spacer(minLength: 0)
            EyeView(mood: step >= 2 ? .closed : .sleepy, size: 66, sounds: false)
                .saturation(step >= 2 ? 0.2 : 1)
            VStack(spacing: 0) {
                Text("\(days)")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(step >= 4 ? Theme.warn : Theme.text)
                    .contentTransition(.numericText())
                Text(tr("يوم ما انفتح التطبيق", "days since the app was opened"))
                    .font(Theme.font(10, .bold)).foregroundStyle(Theme.faint)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surfaceHi)
                    Capsule().fill(LinearGradient(colors: [Theme.faint, Theme.warn], startPoint: .leading, endPoint: .trailing))
                        .frame(width: g.size.width * CGFloat(days) / 30)
                }
            }
            .frame(height: 6)
            .environment(\.layoutDirection, .leftToRight)
            Text(step >= 4 ? tr("خلصت المدة ⏳", "The period is over ⏳") : " ")
                .font(Theme.font(10, .bold)).foregroundStyle(Theme.warn)
            Spacer(minLength: 0)
        }
    }

    private func askBubble(_ day: Int, left: Int, show: Bool, dim: Bool) -> some View {
        bubble(show) {
            HStack(spacing: 6) {
                Text("🫀").font(.system(size: 12))
                VStack(alignment: .leading, spacing: 1) {
                    Text(tr("إنت بخير؟", "Are you okay?")).font(Theme.font(10, .heavy)).foregroundStyle(Theme.text)
                    Text(tr("باقي \(left) أيام", "\(left) days left")).font(Theme.font(8)).foregroundStyle(Theme.warn)
                }
                Spacer(minLength: 0)
                Text(tr("يوم \(day)", "Day \(day)")).font(Theme.font(8, .bold)).foregroundStyle(Theme.faint)
            }
        }
        .opacity(dim ? 0.45 : 1)
    }

    /// Scene 3 — the bot's daily question, stacking up unanswered.
    private var askScreen: some View {
        VStack(alignment: .leading, spacing: 6) {
            chatHeader("MNLOVO SAVER", tr("بوت", "bot"), icon: "eye.fill", tint: AnyShapeStyle(Theme.brandGradient))
            Spacer(minLength: 0)
            askBubble(1, left: 7, show: step >= 1, dim: step >= 2)
            askBubble(2, left: 6, show: step >= 2, dim: step >= 3)
            askBubble(3, left: 5, show: step >= 3, dim: false)
            Text(tr("❤️ أنا بخير", "❤️ I'm fine"))
                .font(Theme.font(10, .bold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 9).fill(blue))
                .opacity(step >= 1 ? 1 : 0)
            Text(step >= 4 ? tr("ولا ردّ…", "No reply…") : " ")
                .font(Theme.font(9, .bold)).foregroundStyle(Theme.danger)
                .frame(maxWidth: .infinity)
        }
    }

    /// Scene 4 — he taps the button, and the counter starts over.
    private var aliveScreen: some View {
        VStack(alignment: .leading, spacing: 6) {
            chatHeader("MNLOVO SAVER", tr("بوت", "bot"), icon: "eye.fill", tint: AnyShapeStyle(Theme.brandGradient))
            Spacer(minLength: 0)
            askBubble(3, left: 5, show: true, dim: step >= 2)
            ZStack {
                Text(tr("❤️ أنا بخير", "❤️ I'm fine"))
                    .font(Theme.font(10, .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 9).fill(step >= 1 ? rose : blue))
                    .scaleEffect(step == 1 ? 0.93 : 1)
                if step == 1 {
                    Image(systemName: "hand.tap.fill").font(.system(size: 18)).foregroundStyle(.white)
                        .shadow(radius: 4).offset(x: 34, y: 10)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            bubble(step >= 2, tint: Theme.ok.opacity(0.16)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("❤️ الحمدلله", "❤️ Thank God")).font(Theme.font(10, .heavy)).foregroundStyle(Theme.text)
                    Text(tr("رجع العدّاد من الأول ✓", "Counter starts over ✓")).font(Theme.font(9)).foregroundStyle(Theme.ok)
                }
            }
            HStack(spacing: 3) {
                ForEach(0..<12, id: \.self) { i in
                    Capsule().fill(step >= 3 ? (i == 0 ? Theme.ok : Theme.surfaceHi) : Theme.warn.opacity(0.7))
                        .frame(height: 5)
                }
            }
            .padding(.top, 2)
        }
    }

    /// Scene 5 — the trustee's Telegram: the notice, then the will, then the data.
    private var trusteeScreen: some View {
        VStack(alignment: .leading, spacing: 6) {
            chatHeader("MNLOVO SAVER", tr("رسالة جديدة", "new message"), icon: "eye.fill", tint: AnyShapeStyle(Theme.brandGradient))
            Spacer(minLength: 0)
            bubble(step >= 1) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("🕊️ أمانة سيف", "🕊️ Saif's trust")).font(Theme.font(10, .heavy)).foregroundStyle(Theme.text)
                    Text(tr("اختارك أميناً بعد وفاته", "He chose you as his trustee")).font(Theme.font(8)).foregroundStyle(Theme.sub)
                }
            }
            // the will: a small sheet of paper, the first thing he reads
            bubble(step >= 2, tint: Color(hex: 0xFFF4DC).opacity(0.14)) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(tr("الوصية", "The will"), systemImage: "scroll.fill")
                        .font(Theme.font(9, .heavy)).foregroundStyle(Theme.accent2)
                    IntroBits.bar(120, Theme.faint, h: 4)
                    IntroBits.bar(104, Theme.faint, h: 4)
                    IntroBits.bar(70, Theme.faint, h: 4)
                }
            }
            bubble(step >= 3) {
                Label(tr("الحسابات وكلمات السر", "Accounts and passwords"), systemImage: "key.horizontal.fill")
                    .font(Theme.font(9, .bold)).foregroundStyle(Theme.text)
            }
            bubble(step >= 4) {
                Label(tr("الملاحظات والتذكيرات", "Notes and reminders"), systemImage: "note.text")
                    .font(Theme.font(9, .bold)).foregroundStyle(Theme.text)
            }
            Text(step >= 5 ? tr("مرة وحدة · له هو بس 🤲", "Once · only him 🤲") : " ")
                .font(Theme.font(9, .bold)).foregroundStyle(Theme.accent2)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Settings screen

struct LegacyView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var svc = LegacyService.shared

    @State private var sel = LegacyService.Selection.saved
    @State private var busy: String?
    @State private var error: String?
    @State private var shareURL: URL?
    @State private var waiting = false
    @State private var confirmOff = false
    @FocusState private var focus: AYNFieldID?

    private var st: LegacyService.Status { svc.status }

    var body: some View {
        SheetScaffold(title: tr("بعد وفاتي", "After I'm gone")) {
            if state.isDecoy {
                Label(tr("هالخاصية مب متاحة هنا.", "Not available here."), systemImage: "nosign")
                    .font(Theme.font(15, .semibold)).foregroundStyle(Theme.sub).glass(16)
            } else if !TelegramService.shared.cloudReady {
                needsCloud
            } else {
                statusCard
                if !st.isArmed { LegacyExplainer() }
                recipientCard
                if st.hasRecipient {
                    timingCard
                    willCard
                    contentCard
                    armCard
                }
                warningCard
            }
            if let error { Text(error).font(Theme.font(13, .semibold)).foregroundStyle(Theme.danger) }
        }
        .task { _ = await svc.refresh() }
        .onChange(of: scenePhase) { _, p in if p == .active && waiting { Task { await pollRecipient() } } }
        .sheet(item: Binding(get: { shareURL.map { ShareItem(url: $0) } }, set: { if $0 == nil { shareURL = nil } })) { item in
            ActivityView(items: [tr("اضغط الرابط وبعدين «ابدأ» — أبيك تكون الأمين على وصيتي وبياناتي في MNLOVO SAVER، لا سمح الله:",
                                    "Open this link and tap Start — I'd like you to hold my will and data in MNLOVO SAVER, God forbid anything happens:"), item.url])
                .presentationDetents([.medium])
        }
        .confirmationDialog(tr("توقف خاصية «بعد وفاتي»؟", "Turn “After I'm gone” off?"), isPresented: $confirmOff, titleVisibility: .visible) {
            Button(tr("أوقفها واحذف النسخة من السيرفر", "Turn off and delete the server copy"), role: .destructive) {
                Task { await setArmed(false) }
            }
        } message: {
            Text(tr("ما بينرسل شي لأحد، وتنمسح نسخة الوصية من السيرفر، ونخبر الأمين إن أمانته انتهت.", "Nothing will be sent to anyone, the server copy of your will is deleted, and your trustee is told the trust has ended."))
        }
    }

    // MARK: Cards

    private var needsCloud: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(tr("تحتاج السحابة وتيليجرام", "Needs the cloud and Telegram"), systemImage: "icloud.slash.fill")
                .font(Theme.font(16, .heavy)).foregroundStyle(Theme.warn)
            Text(tr("هالخاصية تشتغل من السيرفر، لأن تلفونك ممكن يكون مطفي. سجّل دخول السحابة واربط تيليجرام أول.",
                    "This runs on the server, because your phone may be off. Sign in to the cloud and link Telegram first."))
                .font(Theme.font(13)).foregroundStyle(Theme.sub)
        }
        .glass(16, tint: Theme.warn)
    }

    private var statusCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(st.isArmed ? Theme.ok.opacity(0.16) : Theme.surfaceHi).frame(width: 60, height: 60)
                Image(systemName: st.isArmed ? "heart.fill" : "heart.slash")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(st.isArmed ? Theme.ok : Theme.faint)
                    .symbolEffect(.pulse, isActive: st.isArmed)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(st.isArmed ? tr("شغّالة — وصيتك محفوظة", "On — your will is saved") : tr("مطفأة", "Off"))
                    .font(Theme.font(18, .heavy)).foregroundStyle(Theme.text)
                if st.isArmed, let d = st.deliverAt {
                    Text(tr("لو ما فتحت التطبيق أبداً، تُسلَّم وصيتك يوم \(Fmt.date(d))", "If you never open the app, your will is delivered on \(Fmt.date(d))"))
                        .font(Theme.font(12)).foregroundStyle(Theme.sub)
                } else {
                    Text(tr("كل ما تفتح الخزنة يرجع العدّاد من الأول.", "Opening the vault resets the counter."))
                        .font(Theme.font(12)).foregroundStyle(Theme.sub)
                }
                if st.state == "asking" {
                    Label(tr("البوت يسأل إذا إنت بخير (\(st.askedCount))", "The bot is asking whether you're okay (\(st.askedCount))"), systemImage: "bell.badge.fill")
                        .font(Theme.font(12, .bold)).foregroundStyle(Theme.warn)
                }
            }
            Spacer(minLength: 0)
        }
        .glass(16, tint: st.isArmed ? Theme.ok : Theme.accent)
    }

    private var recipientCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("منو يستلم وصيتك؟", "Who receives your will?")).font(Theme.font(16, .heavy)).foregroundStyle(Theme.text)
            if st.hasRecipient {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.ok).frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(st.recipientName.isEmpty ? tr("مربوط", "Linked") : st.recipientName)
                            .font(Theme.font(15, .bold)).foregroundStyle(Theme.text)
                        Text(tr("يستلم وصيتك وبياناتك إذا توفّيت", "Receives your will and data if you die"))
                            .font(Theme.font(11)).foregroundStyle(Theme.sub)
                    }
                    Spacer()
                    Button { Task { await clearRecipient() } } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundStyle(Theme.faint)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
                HStack(spacing: 10) {
                    SecondaryButton(title: tr("جرّب الرسالة عليه", "Rehearse it on him"), icon: "paperplane", color: Theme.accent) {
                        Task { await test() }
                    }
                }
            } else {
                Text(tr("طرش له رابط، وأول ما يفتحه ويضغط «ابدأ» يصير هو الأمين. ما يوصله ولا حرف إلا إذا توفّيت وتأكّد التطبيق.",
                        "Send him a link; once he opens it and taps Start he becomes your trustee. He receives nothing unless you die and the app has made sure."))
                    .font(Theme.font(13)).foregroundStyle(Theme.sub)
                PrimaryButton(title: tr("اختر الأمين", "Choose your trustee"), icon: "person.badge.shield.checkmark",
                              loading: busy == "link") { Task { await makeLink() } }
                if waiting {
                    HStack(spacing: 8) {
                        ProgressView().tint(Theme.accent)
                        Text(tr("ننتظره يضغط «ابدأ»…", "Waiting for him to tap Start…"))
                            .font(Theme.font(12, .semibold)).foregroundStyle(Theme.sub)
                        Button(tr("تحديث", "Refresh")) { Task { await pollRecipient() } }
                            .font(Theme.font(12, .bold)).foregroundStyle(Theme.accent)
                    }
                }
            }
        }
        .glass(16)
    }

    private var timingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("التوقيت", "Timing")).font(Theme.font(16, .heavy)).foregroundStyle(Theme.text)
            Menu {
                ForEach([7, 14, 30, 60, 90, 180, 365], id: \.self) { d in
                    Button(daysLabel(d)) { Task { try? await svc.save(interval: d) } }
                }
            } label: {
                pickerRow("moon.zzz.fill", tr("إذا ما فتحت التطبيق مدة", "If I don't open the app for"), daysLabel(st.intervalDays))
            }
            Divider().overlay(Theme.stroke)
            Menu {
                ForEach([1, 3, 7, 14, 30], id: \.self) { d in
                    Button(daysLabel(d)) { Task { try? await svc.save(grace: d) } }
                }
            } label: {
                pickerRow("bell.badge.fill", tr("يسألني يومياً لمدة", "Then asks me daily for"), daysLabel(st.graceDays))
            }
            Text(tr("يعني وصيتك ما تُسلَّم إلا بعد \(st.intervalDays + st.graceDays) يوم كاملة من آخر مرة تفتح فيها التطبيق، وبعد ما يسألك البوت كل يوم وما ترد.",
                    "So your will is delivered only \(st.intervalDays + st.graceDays) full days after you last opened the app, and only after the bot has asked you daily with no answer."))
                .font(Theme.font(12)).foregroundStyle(Theme.faint)
        }
        .glass(16)
    }

    private var contentCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(tr("شو يستلم", "What he receives")).font(Theme.font(16, .heavy)).foregroundStyle(Theme.text).padding(.bottom, 6)
            option("key.horizontal.fill", tr("الحسابات", "Accounts"), $sel.accounts)
            option("eye.slash.fill", tr("كلمات السر", "Passwords"), $sel.passwords)
            option("note.text", tr("الملاحظات", "Notes"), $sel.notes)
            option("bell.fill", tr("التذكيرات المفتوحة", "Open reminders"), $sel.reminders)
            option("paperclip", tr("أسماء الملفات", "File names"), $sel.fileList)
        }
        .glass(16)
        .onChange(of: sel) { _, v in v.save() }
    }

    /// The will itself. Kept in its own card because it's the part that matters most to the person
    /// writing it, and it deserves room rather than a two-line box at the bottom of a list.
    private var willCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "scroll.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.accent2)
                Text(tr("وصيتك", "Your will")).font(Theme.font(16, .heavy)).foregroundStyle(Theme.text)
                Spacer()
                if willWords > 0 {
                    Text(tr("\(willWords) كلمة", "\(willWords) words"))
                        .font(Theme.font(11, .bold)).foregroundStyle(Theme.faint)
                }
            }
            Text(tr("تُقرأ عليه أول ما يستلم، قبل أي بيانات. تقدر تعدّلها في أي وقت وإنت حي.",
                    "It's the first thing he reads, before any data. You can edit it any time while you're here."))
                .font(Theme.font(12)).foregroundStyle(Theme.sub)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $sel.message)
                    .font(Theme.font(15))
                    .foregroundStyle(Theme.text)
                    .scrollContentBackground(.hidden)
                    .frame(height: 170)
                    .padding(10)
                    .focused($focus, equals: .legacyWill)
                if sel.message.isEmpty {
                    Text(tr("اكتب وصيتك هنا…", "Write your will here…"))
                        .font(Theme.font(15)).foregroundStyle(Theme.faint)
                        .padding(.horizontal, 15).padding(.top, 18)
                        .allowsHitTesting(false)
                }
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(focus == .legacyWill ? Theme.accent2.opacity(0.6) : Theme.stroke))

            if sel.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                SecondaryButton(title: tr("ابدأ من نموذج", "Start from a template"), icon: "text.badge.plus", color: Theme.accent2) {
                    sel.message = Self.willTemplate
                    Haptics.tap()
                    focus = .legacyWill
                }
            }

            Label(tr("هذي وصية شخصية بين إيدين الأمين، مب ورقة رسمية عند جهة حكومية.",
                     "This is a personal will in your trustee's hands, not an official document filed anywhere."),
                  systemImage: "info.circle")
                .font(Theme.font(11, .medium)).foregroundStyle(Theme.faint)
        }
        .glass(16, tint: Theme.accent2)
        .onChange(of: sel) { _, v in v.save() }
    }

    private var willWords: Int {
        sel.message.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// A gentle skeleton — headings only, so the words stay the person's own.
    private static var willTemplate: String {
        tr("""
        بسم الله الرحمن الرحيم

        إذا وصلتك هذي الرسالة، فأنا ما عدت موجود. سامحني على أي تقصير، وأسألك تدعي لي.

        أول شي أبيك تسويه:
        -

        الحسابات المهمة وشو أبي يصير فيها:
        -

        أشياء شخصية ودّي توصل لأهلي:
        -

        وصيتي الأخيرة:
        -
        """,
        """
        If you're reading this, I'm no longer here. Forgive me for anything I left undone.

        The first things I'd like you to do:
        -

        The important accounts and what should happen to them:
        -

        Personal things I'd like passed on to my family:
        -

        My last words:
        -
        """)
    }

    private var armCard: some View {
        VStack(spacing: 10) {
            if let at = st.bundleAt {
                Label(tr("آخر تحديث للوصية والبيانات: \(Fmt.date(at))", "Will and data last updated: \(Fmt.date(at))"), systemImage: "clock.arrow.circlepath")
                    .font(Theme.font(12, .medium)).foregroundStyle(Theme.sub)
            }
            if st.isArmed {
                SecondaryButton(title: tr("حدّث الوصية والبيانات", "Update the will and data"),
                                icon: "arrow.clockwise", color: Theme.accent) { Task { await setArmed(true) } }
                SecondaryButton(title: tr("أوقف الخاصية", "Turn the feature off"), icon: "heart.slash", color: Theme.danger) {
                    confirmOff = true
                }
            } else {
                PrimaryButton(title: tr("فعّل الخاصية", "Turn it on"), icon: "heart.fill", loading: busy == "arm") {
                    Task { await setArmed(true) }
                }
            }
        }
    }

    private var warningCard: some View {
        Label(tr("عشان السيرفر يقدر يسلّمها مقروءة، نسخة الأمانة تُحفظ عنده (مقفولة، ما يوصلها إلا السيرفر). باقي خزنتك يبقى مشفّراً في تلفونك ولا أحد يشوفه. توقف الخاصية = تنمسح النسخة.",
                 "So the server can deliver it readable, the parcel is stored there (locked away, server-only). The rest of your vault stays encrypted on your phone. Turning it off deletes the copy."),
              systemImage: "exclamationmark.shield.fill")
            .font(Theme.font(12, .medium)).foregroundStyle(Theme.warn)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(12, tint: Theme.warn)
    }

    // MARK: Bits

    private func daysLabel(_ d: Int) -> String {
        d == 1 ? tr("يوم", "1 day") : d == 365 ? tr("سنة", "1 year") : tr("\(d) يوم", "\(d) days")
    }

    private func pickerRow(_ icon: String, _ title: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accent).frame(width: 26)
            Text(title).font(Theme.font(14, .semibold)).foregroundStyle(Theme.text)
            Spacer()
            Text(value).font(Theme.font(14, .bold)).foregroundStyle(Theme.sub)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 11)).foregroundStyle(Theme.faint)
        }
        .padding(.vertical, 8)
    }

    private func option(_ icon: String, _ title: String, _ binding: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accent).frame(width: 26)
            Text(title).font(Theme.font(14, .semibold)).foregroundStyle(Theme.text)
            Spacer()
            Toggle("", isOn: binding).labelsHidden().tint(Theme.accent)
        }
        .padding(.vertical, 7)
    }

    // MARK: Actions

    private func makeLink() async {
        busy = "link"; defer { busy = nil }
        do {
            shareURL = try await svc.recipientLink()
            waiting = true
            error = nil
            state.allowShortTrip(180)
        } catch { self.error = error.localizedDescription; FX.error() }
    }

    private func pollRecipient() async {
        for _ in 0..<8 {
            _ = await svc.refresh()
            if st.hasRecipient {
                waiting = false
                FX.success()
                state.show(tr("تم اختيار الأمين ✓", "Trustee chosen ✓"), icon: "person.badge.shield.checkmark")
                return
            }
            await pause(2.5)
        }
        waiting = false
    }

    private func clearRecipient() async {
        do { try await svc.save(enabled: false, clearRecipient: true); SoundFX.shared.play(.delete, volume: 0.4) }
        catch { self.error = error.localizedDescription }
    }

    private func setArmed(_ on: Bool) async {
        busy = "arm"; defer { busy = nil }
        do {
            if on {
                try await svc.save(enabled: true, bundle: state.legacyBundle(sel))
                FX.success()
                state.show(tr("الخاصية شغّالة ✓", "It's on ✓"), icon: "heart.fill")
            } else {
                try await svc.save(enabled: false, bundle: "")
                state.show(tr("تم الإيقاف", "Turned off"), icon: "heart.slash")
            }
            error = nil
        } catch { self.error = error.localizedDescription; FX.error() }
    }

    private func test() async {
        do {
            try await svc.sendTestToRecipient()
            Haptics.success()
            state.show(tr("انطرشت له ✓", "Sent to him ✓"), icon: "paperplane.fill")
        } catch { self.error = error.localizedDescription }
    }
}
