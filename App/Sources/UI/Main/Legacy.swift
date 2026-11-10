import SwiftUI

// MARK: - Animated explainer (used in Settings and during sign-up)

/// Four short scenes inside a mock phone: the app goes quiet → the bot checks on you →
/// you tap "I'm fine" → or nobody answers and your trustee receives the parcel.
struct LegacyExplainer: View {
    @State private var scene = 0
    @State private var beat = false
    @State private var tap = false
    @State private var reveal = false
    private let blue = TelegramService.blue

    private var captions: [(String, String)] {
        [(tr("التطبيق سكت مدة طويلة", "The app goes quiet for a long time"),
          tr("كل ما تفتح الخزنة نسجّل إنك بخير. لو مرّت المدة اللي تحددها بدون ما تفتحه…", "Every time you open the vault we note you're fine. If your chosen period passes without that…")),
         (tr("البوت يطمّن عليك", "The bot checks on you"),
          tr("يرسل لك رسالة كل يوم: «طمّنّا عنك» مع زر «أنا بخير».", "It messages you daily: “Just checking in” with an “I'm fine” button.")),
         (tr("ضغطة وحدة وكل شي يرجع", "One tap and it all resets"),
          tr("تضغط الزر — أو تفتح التطبيق — والعدّاد يرجع من الأول.", "Tap the button — or just open the app — and the counter starts over.")),
         (tr("ما ردّيت؟ تنسلّم أمانتك", "No answer? Your parcel is delivered"),
          tr("بعد مهلة إضافية، الشخص اللي اخترته يستلم البيانات اللي حددتها.", "After an extra grace period, the person you chose receives the data you picked."))]
    }

    var body: some View {
        VStack(spacing: 14) {
            phone
                .frame(width: 168, height: 250)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                Text(captions[scene].0).font(Theme.font(18, .heavy)).foregroundStyle(Theme.text)
                Text(captions[scene].1).font(Theme.font(14)).foregroundStyle(Theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
            .id(scene)
            .transition(.opacity.combined(with: .move(edge: .bottom)))

            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule().fill(i == scene ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.surfaceHi))
                        .frame(width: i == scene ? 22 : 7, height: 7)
                        .onTapGesture { withAnimation(.spring(response: 0.4)) { scene = i } }
                }
            }
        }
        .padding(16)
        .glass(0, radius: 24, tint: Theme.accent3)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: scene)
        .task(id: scene) { await play() }
    }

    private func play() async {
        tap = false; reveal = false
        await pause(0.8)
        if scene == 2 {
            withAnimation(.easeOut(duration: 0.18)) { tap = true }
            await pause(0.22)
            withAnimation(.easeOut(duration: 0.25)) { tap = false }
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { reveal = true }
        await pause(3.4)
        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.45)) { scene = (scene + 1) % 4 }
    }

    private var phone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30).fill(Color.black.opacity(0.6))
            Group {
                switch scene {
                case 0: quietScreen
                case 1: askScreen
                case 2: aliveScreen
                default: deliverScreen
                }
            }
            .padding(.horizontal, 12).padding(.top, 30).padding(.bottom, 14)
            .id(scene)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
            RoundedRectangle(cornerRadius: 30).strokeBorder(LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)],
                                                                          startPoint: .top, endPoint: .bottom), lineWidth: 2)
            Capsule().fill(Color.black).frame(width: 56, height: 15)
                .frame(maxHeight: .infinity, alignment: .top).padding(.top, 9)
        }
        .shadow(color: Theme.accent3.opacity(0.25), radius: 20)
    }

    private func bar(_ w: CGFloat, _ c: Color = Theme.surfaceHi) -> some View {
        RoundedRectangle(cornerRadius: 3).fill(c).frame(width: w, height: 6)
    }

    private var quietScreen: some View {
        VStack(spacing: 10) {
            Spacer()
            EyeView(mood: .sleepy, size: 86, sounds: false)
            Text(tr("٣٠ يوم بدون فتح", "30 days unopened"))
                .font(Theme.font(11, .bold)).foregroundStyle(Theme.sub)
            TimelineView(.animation(minimumInterval: 1 / 20)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                HStack(spacing: 3) {
                    ForEach(0..<10, id: \.self) { i in
                        Capsule()
                            .fill(Double(i) / 10 < (reveal ? 1.0 : 0.2) ? Theme.warn : Theme.surfaceHi)
                            .frame(width: 10, height: 5)
                            .opacity(i == 9 ? 0.5 + 0.5 * abs(sin(t * 2)) : 1)
                    }
                }
            }
            Spacer()
        }
    }

    private var askScreen: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(Theme.brandGradient).frame(width: 22, height: 22)
                    .overlay(Image(systemName: "eye.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(.white))
                Text("MNLOVO SAVER").font(Theme.font(9, .heavy)).foregroundStyle(Theme.text)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 5) {
                Text(tr("🫀 طمّنّا عنك", "🫀 Just checking in")).font(Theme.font(11, .heavy)).foregroundStyle(Theme.text)
                bar(92, Theme.faint); bar(70, Theme.faint)
                Text(tr("❤️ أنا بخير", "❤️ I'm fine"))
                    .font(Theme.font(10, .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 8).fill(blue))
            }
            .padding(9)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surfaceHi))
            .scaleEffect(reveal ? 1 : 0.5, anchor: .bottomLeading)
            .opacity(reveal ? 1 : 0)
            Spacer()
        }
    }

    private var aliveScreen: some View {
        VStack(spacing: 10) {
            Spacer()
            ZStack {
                Image(systemName: "heart.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(Color(hex: 0xFF5FA2))
                    .scaleEffect(tap ? 0.85 : (reveal ? 1.08 : 1))
                    .shadow(color: Color(hex: 0xFF5FA2).opacity(0.7), radius: 14)
                if tap {
                    Circle().stroke(Color(hex: 0xFF5FA2).opacity(0.6), lineWidth: 2)
                        .frame(width: 80, height: 80)
                }
            }
            Text(tr("رجع العدّاد من الأول ✓", "Counter reset ✓"))
                .font(Theme.font(11, .bold)).foregroundStyle(Theme.ok)
                .opacity(reveal ? 1 : 0)
            HStack(spacing: 3) {
                ForEach(0..<10, id: \.self) { i in
                    Capsule().fill(i == 0 && reveal ? Theme.ok : Theme.surfaceHi).frame(width: 10, height: 5)
                }
            }
            Spacer()
        }
    }

    private var deliverScreen: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(Theme.accent2.opacity(0.8)).frame(width: 22, height: 22)
                    .overlay(Image(systemName: "person.fill").font(.system(size: 10)).foregroundStyle(.white))
                Text(tr("الأمين", "Your trustee")).font(Theme.font(9, .heavy)).foregroundStyle(Theme.text)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("🕊️ أمانة من MNLOVO SAVER", "🕊️ A parcel from MNLOVO SAVER"))
                    .font(Theme.font(10, .heavy)).foregroundStyle(Theme.text)
                Text("━━━━━━━━━").font(.system(size: 7)).foregroundStyle(Theme.faint)
                bar(88, Theme.faint); bar(74, Theme.faint); bar(60, Theme.faint)
            }
            .padding(9)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surfaceHi))
            .scaleEffect(reveal ? 1 : 0.5, anchor: .bottomLeading)
            .opacity(reveal ? 1 : 0)
            Spacer()
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
        SheetScaffold(title: tr("نبض الحياة", "Heartbeat")) {
            if state.isDecoy {
                Label(tr("هالخاصية مو متاحة هنا.", "Not available here."), systemImage: "nosign")
                    .font(Theme.font(15, .semibold)).foregroundStyle(Theme.sub).glass(16)
            } else if !TelegramService.shared.cloudReady {
                needsCloud
            } else {
                statusCard
                if !st.isArmed { LegacyExplainer() }
                recipientCard
                if st.hasRecipient {
                    timingCard
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
            ActivityView(items: [tr("اضغط الرابط وبعدين «ابدأ» — أبيك تكون الأمين على بياناتي في MNLOVO SAVER:",
                                    "Open this link and tap Start — I'd like you to be my trustee in MNLOVO SAVER:"), item.url])
                .presentationDetents([.medium])
        }
        .confirmationDialog(tr("توقف نبض الحياة؟", "Turn the heartbeat off?"), isPresented: $confirmOff, titleVisibility: .visible) {
            Button(tr("أوقفها واحذف النسخة من السيرفر", "Turn off and delete the server copy"), role: .destructive) {
                Task { await setArmed(false) }
            }
        } message: {
            Text(tr("ما بينرسل شي لأحد، وتنمسح نسخة الأمانة من السيرفر.", "Nothing will be sent to anyone, and the parcel copy is deleted from the server."))
        }
    }

    // MARK: Cards

    private var needsCloud: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(tr("تحتاج السحابة وتيليجرام", "Needs the cloud and Telegram"), systemImage: "icloud.slash.fill")
                .font(Theme.font(16, .heavy)).foregroundStyle(Theme.warn)
            Text(tr("هالخاصية تشتغل من السيرفر، لأن جوالك ممكن يكون مطفي. سجّل دخول السحابة واربط تيليجرام أول.",
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
                Text(st.isArmed ? tr("شغّالة", "Armed") : tr("مطفأة", "Off"))
                    .font(Theme.font(18, .heavy)).foregroundStyle(Theme.text)
                if st.isArmed, let d = st.deliverAt {
                    Text(tr("لو ما فتحت التطبيق، تنسلّم يوم \(Fmt.date(d))", "If you never open the app, delivery on \(Fmt.date(d))"))
                        .font(Theme.font(12)).foregroundStyle(Theme.sub)
                } else {
                    Text(tr("كل ما تفتح الخزنة يرجع العدّاد من الأول.", "Opening the vault resets the counter."))
                        .font(Theme.font(12)).foregroundStyle(Theme.sub)
                }
                if st.state == "asking" {
                    Label(tr("البوت يسأل عنك الحين (\(st.askedCount))", "The bot is checking on you (\(st.askedCount))"), systemImage: "bell.badge.fill")
                        .font(Theme.font(12, .bold)).foregroundStyle(Theme.warn)
                }
            }
            Spacer(minLength: 0)
        }
        .glass(16, tint: st.isArmed ? Theme.ok : Theme.accent)
    }

    private var recipientCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("مين الأمين؟", "Who's the trustee?")).font(Theme.font(16, .heavy)).foregroundStyle(Theme.text)
            if st.hasRecipient {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.ok).frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(st.recipientName.isEmpty ? tr("مربوط", "Linked") : st.recipientName)
                            .font(Theme.font(15, .bold)).foregroundStyle(Theme.text)
                        Text(tr("يستلم الأمانة إذا انقطعت أخبارك", "Receives the parcel if you go silent"))
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
                    SecondaryButton(title: tr("رسالة تجريبية له", "Send him a test"), icon: "paperplane", color: Theme.accent) {
                        Task { await test() }
                    }
                }
            } else {
                Text(tr("أرسل له رابط، وأول ما يفتحه ويضغط «ابدأ» يصير هو الأمين. ما يوصله شي إلا لو انقطعت أخبارك.",
                        "Send him a link; once he opens it and taps Start he becomes the trustee. He gets nothing unless you go silent."))
                    .font(Theme.font(13)).foregroundStyle(Theme.sub)
                PrimaryButton(title: tr("اختر الأمين", "Choose the trustee"), icon: "person.badge.shield.checkmark",
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
                pickerRow("moon.zzz.fill", tr("إذا ما فتحت التطبيق", "If I don't open the app"), daysLabel(st.intervalDays))
            }
            Divider().overlay(Theme.stroke)
            Menu {
                ForEach([1, 3, 7, 14, 30], id: \.self) { d in
                    Button(daysLabel(d)) { Task { try? await svc.save(grace: d) } }
                }
            } label: {
                pickerRow("bell.badge.fill", tr("يسألني يومياً لمدة", "Then asks me daily for"), daysLabel(st.graceDays))
            }
            Text(tr("يعني الأمانة ما تنسلّم إلا بعد \(st.intervalDays + st.graceDays) يوم من آخر مرة تفتح فيها التطبيق.",
                    "So the parcel is delivered only \(st.intervalDays + st.graceDays) days after you last opened the app."))
                .font(Theme.font(12)).foregroundStyle(Theme.faint)
        }
        .glass(16)
    }

    private var contentCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(tr("وش يستلم", "What he receives")).font(Theme.font(16, .heavy)).foregroundStyle(Theme.text).padding(.bottom, 6)
            option("key.horizontal.fill", tr("الحسابات", "Accounts"), $sel.accounts)
            option("eye.slash.fill", tr("كلمات السر", "Passwords"), $sel.passwords)
            option("note.text", tr("الملاحظات", "Notes"), $sel.notes)
            option("bell.fill", tr("التذكيرات المفتوحة", "Open reminders"), $sel.reminders)
            option("paperclip", tr("أسماء الملفات", "File names"), $sel.fileList)
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("رسالة منك له (اختياري)", "A message from you (optional)"))
                    .font(Theme.font(13, .bold)).foregroundStyle(Theme.sub)
                TextEditor(text: $sel.message)
                    .font(Theme.font(14)).foregroundStyle(Theme.text)
                    .scrollContentBackground(.hidden)
                    .frame(height: 80)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
            }
            .padding(.top, 8)
        }
        .glass(16)
        .onChange(of: sel) { _, v in v.save() }
    }

    private var armCard: some View {
        VStack(spacing: 10) {
            if let at = st.bundleAt {
                Label(tr("آخر تحديث للأمانة: \(Fmt.date(at))", "Parcel last updated: \(Fmt.date(at))"), systemImage: "clock.arrow.circlepath")
                    .font(Theme.font(12, .medium)).foregroundStyle(Theme.sub)
            }
            if st.isArmed {
                SecondaryButton(title: tr("حدّث الأمانة بالبيانات الحالية", "Refresh the parcel with current data"),
                                icon: "arrow.clockwise", color: Theme.accent) { Task { await setArmed(true) } }
                SecondaryButton(title: tr("أوقف نبض الحياة", "Turn the heartbeat off"), icon: "heart.slash", color: Theme.danger) {
                    confirmOff = true
                }
            } else {
                PrimaryButton(title: tr("فعّل نبض الحياة", "Arm the heartbeat"), icon: "heart.fill", loading: busy == "arm") {
                    Task { await setArmed(true) }
                }
            }
        }
    }

    private var warningCard: some View {
        Label(tr("عشان السيرفر يقدر يسلّمها مقروءة، نسخة الأمانة تُحفظ عنده (مقفولة، ما يوصلها إلا السيرفر). باقي خزنتك يبقى مشفّراً في جوالك ولا أحد يشوفه. توقف الخاصية = تنمسح النسخة.",
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
                state.show(tr("نبض الحياة شغّال ✓", "Heartbeat armed ✓"), icon: "heart.fill")
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
            state.show(tr("انرسلت له ✓", "Sent to him ✓"), icon: "paperplane.fill")
        } catch { self.error = error.localizedDescription }
    }
}
