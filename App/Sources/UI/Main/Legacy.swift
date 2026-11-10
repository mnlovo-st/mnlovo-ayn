import SwiftUI

// MARK: - Animated explainer (used in Settings and during sign-up)

/// Five scenes inside a mock phone, told plainly: you're alive and the app knows it → the app goes
/// silent → it asks you daily to be sure → one tap and everything resets → or you've died, and your
/// trustee receives your will and your data.
///
/// The candle on the left is the whole idea in one object: lit while you're here, guttering while
/// we're unsure, out at the end. It's the part people remember after the words are gone.
struct LegacyExplainer: View {
    @State private var scene = 0
    @State private var beat = false
    @State private var tap = false
    @State private var reveal = false
    private let blue = TelegramService.blue
    private let rose = Color(hex: 0xFF5FA2)
    private let sceneCount = 5

    private var captions: [(String, String)] {
        [(tr("وإنت حي، التطبيق يعرف", "While you're here, the app knows"),
          tr("كل ما تفتح خزنتك نسجّل إنك بخير. ما نطلب منك أي شي زيادة.",
             "Every time you open your vault we note that you're fine. Nothing extra is asked of you.")),
         (tr("لو توفّيت، التطبيق يحس بالسكوت", "If you die, the app notices the silence"),
          tr("لأنك ما بتفتحه. تمر المدة اللي حددتها — ٣٠ يوم مثلاً — بدون أي أثر منك.",
             "Because you stop opening it. The period you chose — say 30 days — passes with no sign of you.")),
         (tr("ما نستعجل: يسألك كل يوم", "It doesn't rush: it asks you daily"),
          tr("البوت يرسل لك «إنت بخير؟» كل يوم لمدة إضافية، عشان ما تنفّذ وصيتك وإنت حي.",
             "The bot messages you “Are you okay?” daily for an extra period, so your will is never executed while you're alive.")),
         (tr("إذا رديت، يرجع كل شي مكانه", "If you answer, everything goes back"),
          tr("ضغطة وحدة على «أنا بخير» — أو تفتح التطبيق — والعدّاد يبدأ من الصفر.",
             "One tap on “I'm fine” — or just open the app — and the counter starts from zero.")),
         (tr("ما رديت أبداً؟ تُسلَّم وصيتك", "No answer at all? Your will is delivered"),
          tr("الشخص اللي اخترته يستلم وصيتك والبيانات اللي حددتها له، مرة وحدة، وبس هو.",
             "The person you chose receives your will and the data you picked for him — once, and only him."))]
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                candle
                phone.frame(width: 150, height: 240)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                Text(captions[scene].0).font(Theme.font(18, .heavy)).foregroundStyle(Theme.text)
                Text(captions[scene].1).font(Theme.font(14)).foregroundStyle(Theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
            .id(scene)
            .transition(.opacity.combined(with: .move(edge: .bottom)))

            HStack(spacing: 6) {
                ForEach(0..<sceneCount, id: \.self) { i in
                    Capsule().fill(i == scene ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.surfaceHi))
                        .frame(width: i == scene ? 22 : 7, height: 7)
                        .onTapGesture { withAnimation(.spring(response: 0.4)) { scene = i } }
                }
            }
        }
        .padding(16)
        .glass(0, radius: 24, tint: scene == 4 ? Theme.accent2 : Theme.accent3)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: scene)
        .task(id: scene) { await play() }
    }

    private func play() async {
        tap = false; reveal = false
        await pause(0.8)
        if scene == 3 {
            withAnimation(.easeOut(duration: 0.18)) { tap = true }
            await pause(0.22)
            withAnimation(.easeOut(duration: 0.25)) { tap = false }
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { reveal = true }
        await pause(scene == 4 ? 4.2 : 3.4)
        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.45)) { scene = (scene + 1) % sceneCount }
    }

    // MARK: The candle

    /// Lit (scenes 0 and 3), guttering (1 and 2), out with a thread of smoke (4).
    private var candle: some View {
        // 0 = steady, 1 = unsteady, 2 = extinguished
        let mode = scene == 4 ? 2 : (scene == 1 || scene == 2 ? 1 : 0)
        return TimelineView(.animation(minimumInterval: 1 / 24)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let flicker = mode == 1 ? 0.55 + 0.45 * abs(sin(t * 5.5)) : 1.0
            let sway = mode == 1 ? sin(t * 4) * 3 : sin(t * 1.4) * 0.8
            VStack(spacing: 0) {
                ZStack {
                    if mode == 2 {
                        // smoke: three soft puffs drifting up and fading
                        ForEach(0..<3, id: \.self) { i in
                            let ph = (t * 0.55 + Double(i) * 0.33).truncatingRemainder(dividingBy: 1)
                            Circle()
                                .fill(Theme.faint.opacity(0.35 * (1 - ph)))
                                .frame(width: 7 + 9 * ph, height: 7 + 9 * ph)
                                .offset(x: sin(ph * 6 + Double(i)) * 9, y: -14 - 34 * ph)
                                .blur(radius: 2.5)
                        }
                    } else {
                        Ellipse()
                            .fill(RadialGradient(colors: [Color(hex: 0xFFE9A8), Color(hex: 0xFF9D3C), Color(hex: 0xFF5A1F).opacity(0.1)],
                                                 center: .center, startRadius: 1, endRadius: 18))
                            .frame(width: 15, height: 27 * flicker)
                            .offset(x: sway, y: -13)
                            .shadow(color: Color(hex: 0xFFB34D).opacity(0.75 * flicker), radius: 16)
                            .blur(radius: 0.4)
                    }
                }
                .frame(height: 34)

                // wick
                Rectangle().fill(mode == 2 ? Theme.faint : Color(hex: 0x4A3520)).frame(width: 2, height: 5)
                // body, burning lower as the story goes on
                RoundedRectangle(cornerRadius: 7)
                    .fill(LinearGradient(colors: [Color(hex: 0xFFF6E3), Color(hex: 0xE9D7B6)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 26, height: mode == 2 ? 46 : (mode == 1 ? 58 : 66))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.black.opacity(0.08)))
                // dish
                Capsule().fill(Theme.surfaceHi).frame(width: 40, height: 6)
            }
            .frame(width: 44, height: 120, alignment: .bottom)
            .animation(.easeInOut(duration: 0.6), value: mode)
        }
        .frame(width: 44, height: 240, alignment: .center)
    }

    // MARK: The phone

    private var phone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30).fill(Color.black.opacity(0.6))
            Group {
                switch scene {
                case 0: livingScreen
                case 1: silentScreen
                case 2: askScreen
                case 3: aliveScreen
                default: willScreen
                }
            }
            .padding(.horizontal, 11).padding(.top, 30).padding(.bottom, 13)
            .id(scene)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
            RoundedRectangle(cornerRadius: 30).strokeBorder(LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)],
                                                                          startPoint: .top, endPoint: .bottom), lineWidth: 2)
            Capsule().fill(Color.black).frame(width: 52, height: 14)
                .frame(maxHeight: .infinity, alignment: .top).padding(.top, 9)
        }
        .shadow(color: (scene == 4 ? Theme.accent2 : Theme.accent3).opacity(0.25), radius: 20)
    }

    private func bar(_ w: CGFloat, _ c: Color = Theme.surfaceHi) -> some View {
        RoundedRectangle(cornerRadius: 3).fill(c).frame(width: w, height: 6)
    }

    private func chatHeader(_ title: String, _ icon: String, _ tint: AnyShapeStyle) -> some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 20, height: 20)
                .overlay(Image(systemName: icon).font(.system(size: 9, weight: .bold)).foregroundStyle(.white))
            Text(title).font(Theme.font(9, .heavy)).foregroundStyle(Theme.text)
            Spacer(minLength: 0)
        }
    }

    /// Scene 0 — alive: the eye is awake and a pulse line runs across.
    private var livingScreen: some View {
        VStack(spacing: 9) {
            Spacer()
            EyeView(mood: .happy, size: 76, sounds: false)
            TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                PulseLine(phase: t)
                    .stroke(Theme.ok, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    .frame(height: 22)
            }
            Text(tr("فتحت الخزنة اليوم ✓", "Vault opened today ✓"))
                .font(Theme.font(10, .bold)).foregroundStyle(Theme.ok)
            Spacer()
        }
    }

    /// Scene 1 — the silence: a month of days filling in, nobody there.
    private var silentScreen: some View {
        VStack(spacing: 8) {
            Spacer()
            EyeView(mood: .sleepy, size: 62, sounds: false)
            Text(tr("٣٠ يوم ما فتح التطبيق", "30 days unopened"))
                .font(Theme.font(10, .bold)).foregroundStyle(Theme.warn)
            // a small month grid filling up day by day
            VStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { r in
                    HStack(spacing: 3) {
                        ForEach(0..<6, id: \.self) { c in
                            let i = r * 6 + c
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Double(i) / 30 < (reveal ? 1.0 : 0.15) ? Theme.warn.opacity(0.85) : Theme.surfaceHi)
                                .frame(width: 11, height: 8)
                        }
                    }
                }
            }
            .animation(.easeOut(duration: 1.6), value: reveal)
            Spacer()
        }
    }

    /// Scene 2 — the bot makes sure, every day.
    private var askScreen: some View {
        VStack(alignment: .leading, spacing: 7) {
            chatHeader("MNLOVO SAVER", "eye.fill", AnyShapeStyle(Theme.brandGradient))
            Spacer()
            VStack(alignment: .leading, spacing: 5) {
                Text(tr("🫀 إنت بخير؟", "🫀 Are you okay?")).font(Theme.font(11, .heavy)).foregroundStyle(Theme.text)
                bar(86, Theme.faint); bar(62, Theme.faint)
                Text(tr("❤️ أنا بخير", "❤️ I'm fine"))
                    .font(Theme.font(10, .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 8).fill(blue))
            }
            .padding(9)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surfaceHi))
            .scaleEffect(reveal ? 1 : 0.5, anchor: .bottomLeading)
            .opacity(reveal ? 1 : 0)
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { i in
                    Image(systemName: "bell.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(Double(i) < (reveal ? 7 : 1) ? Theme.warn : Theme.faint.opacity(0.4))
                }
                Text(tr("كل يوم", "daily")).font(Theme.font(8, .bold)).foregroundStyle(Theme.faint)
            }
            .animation(.easeOut(duration: 1.2), value: reveal)
            Spacer()
        }
    }

    /// Scene 3 — he answered; the counter resets.
    private var aliveScreen: some View {
        VStack(spacing: 10) {
            Spacer()
            ZStack {
                Image(systemName: "heart.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(rose)
                    .scaleEffect(tap ? 0.85 : (reveal ? 1.08 : 1))
                    .shadow(color: rose.opacity(0.7), radius: 14)
                if tap {
                    Circle().stroke(rose.opacity(0.6), lineWidth: 2).frame(width: 76, height: 76)
                }
            }
            Text(tr("الحمدلله — رجع العدّاد للصفر ✓", "Thank God — counter back to zero ✓"))
                .font(Theme.font(10, .bold)).foregroundStyle(Theme.ok)
                .multilineTextAlignment(.center)
                .opacity(reveal ? 1 : 0)
            HStack(spacing: 3) {
                ForEach(0..<10, id: \.self) { i in
                    Capsule().fill(i == 0 && reveal ? Theme.ok : Theme.surfaceHi).frame(width: 9, height: 5)
                }
            }
            Spacer()
        }
    }

    /// Scene 4 — the delivery: a dove carrying the will to the trustee.
    private var willScreen: some View {
        VStack(alignment: .leading, spacing: 7) {
            chatHeader(tr("الأمين", "Your trustee"), "person.fill", AnyShapeStyle(Theme.accent2.opacity(0.85)))
            Spacer()
            ZStack {
                Image(systemName: "bird.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.accent2)
                    .offset(x: reveal ? 34 : -34, y: reveal ? -26 : -8)
                    .opacity(reveal ? 0 : 1)
                    .animation(.easeOut(duration: 1.1), value: reveal)
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("🕊️ وصية ورثها إليك", "🕊️ A will left to you"))
                        .font(Theme.font(10, .heavy)).foregroundStyle(Theme.text)
                    // the will itself: a short handwritten-looking block
                    VStack(alignment: .leading, spacing: 3) {
                        bar(78, Theme.accent2.opacity(0.55))
                        bar(66, Theme.faint); bar(72, Theme.faint); bar(48, Theme.faint)
                    }
                    .padding(7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0xFFF8E7).opacity(0.1)))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.accent2.opacity(0.35)))
                    HStack(spacing: 4) {
                        Image(systemName: "lock.open.fill").font(.system(size: 8)).foregroundStyle(Theme.ok)
                        Text(tr("حساباته وكلمات سرّه", "His accounts and passwords"))
                            .font(Theme.font(8, .bold)).foregroundStyle(Theme.sub)
                    }
                }
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surfaceHi))
                .scaleEffect(reveal ? 1 : 0.4, anchor: .bottomLeading)
                .opacity(reveal ? 1 : 0)
            }
            Spacer()
        }
    }
}

/// A two-beat heart trace that scrolls right to left — drawn, not animated frame by frame,
/// so it stays smooth at any size.
private struct PulseLine: Shape {
    let phase: Double

    func path(in r: CGRect) -> Path {
        var p = Path()
        let mid = r.midY
        let span = r.width
        let shift = CGFloat((phase * 0.55).truncatingRemainder(dividingBy: 1)) * span
        // one beat, as fractions of the width, plotted twice so the scroll never shows a seam
        let beat: [(CGFloat, CGFloat)] = [(0, 0), (0.30, 0), (0.36, -0.16), (0.42, 0.40), (0.48, -0.95),
                                          (0.54, 0.34), (0.60, -0.08), (0.66, 0), (1, 0)]
        for cycle in -1...1 {
            let base = CGFloat(cycle) * span - shift
            for (i, pt) in beat.enumerated() {
                let x = base + pt.0 * span
                let y = mid + pt.1 * r.height * 0.5
                if i == 0 && cycle == -1 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
            }
        }
        return p
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
            ActivityView(items: [tr("اضغط الرابط وبعدين «ابدأ» — أبيك تكون الأمين على وصيتي وبياناتي في MNLOVO SAVER، الله لا يبلانا:",
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
            Text(tr("مين يستلم وصيتك؟", "Who receives your will?")).font(Theme.font(16, .heavy)).foregroundStyle(Theme.text)
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
                Text(tr("أرسل له رابط، وأول ما يفتحه ويضغط «ابدأ» يصير هو الأمين. ما يوصله ولا حرف إلا إذا توفّيت وتأكّد التطبيق.",
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
            Text(tr("وش يستلم", "What he receives")).font(Theme.font(16, .heavy)).foregroundStyle(Theme.text).padding(.bottom, 6)
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

            Label(tr("هذي وصية شخصية بين إيدين الأمين، مو ورقة رسمية عند جهة حكومية.",
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
            state.show(tr("انرسلت له ✓", "Sent to him ✓"), icon: "paperplane.fill")
        } catch { self.error = error.localizedDescription }
    }
}
