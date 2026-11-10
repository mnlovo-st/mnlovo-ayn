import SwiftUI

// MARK: - Animated explainer (used in Settings and during sign-up)

/// One idea, carried the whole way through: the line of your own pulse.
///
/// It beats while you're here. It goes flat when you stop opening the app. The bot knocks on that
/// flat line, three times, and hears nothing. One answer from you and the beating comes back. No
/// answer at all, and the flat line folds itself into the letter your trustee receives.
///
/// The earlier version put a candle beside a mock phone, which was two pictures competing for the
/// same sentence. This is a single object that changes meaning as the story moves.
struct LegacyExplainer: View {
    @State private var scene = 0
    @State private var step = 0
    @State private var beatPulse = false
    private let sceneCount = 5

    private let alive = Color(hex: 0x35D2B4)
    private let gone = Color(hex: 0x7A8696)
    private let warm = Color(hex: 0xFFB45C)

    private var captions: [(String, String)] {
        [(tr("وإنت موجود، الخط ينبض", "While you're here, the line beats"),
          tr("كل مرة تفتح خزنتك نسجّل إنك بخير. ما نطلب منك أي شي زيادة.",
             "Every time you open your vault we note that you're fine. Nothing extra is asked of you.")),
         (tr("لو توفّيت، الخط يسكت", "If you die, the line goes quiet"),
          tr("لأنك ما بتفتحه. تعدّي المدة اللي حددتها — ٣٠ يوم مثلاً — وما فيه منك أي أثر.",
             "Because you stop opening it. The period you chose — say 30 days — passes with no sign of you.")),
         (tr("ما نستعجل: نسأل عنك كل يوم", "We don't rush: we ask after you daily"),
          tr("البوت يطرش لك «إنت بخير؟» كل يوم مدة إضافية، عشان ما تنفّذ وصيتك وإنت حي.",
             "The bot messages you “Are you okay?” daily for an extra period, so your will is never executed while you're alive.")),
         (tr("ردّة وحدة وكل شي يرجع", "One answer and it all comes back"),
          tr("تضغط «أنا بخير» — أو بس تفتح التطبيق — والعدّاد يبدأ من الصفر من جديد.",
             "Tap “I'm fine” — or just open the app — and the counter starts again from zero.")),
         (tr("ما رديت أبداً؟ تُسلَّم وصيتك", "No answer at all? Your will is delivered"),
          tr("الشخص اللي اخترته يستلم وصيتك والبيانات اللي حددتها له، مرة وحدة، وبس هو.",
             "The person you chose receives your will and the data you picked for him — once, and only him."))]
    }

    var body: some View {
        VStack(spacing: 16) {
            stage
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.black.opacity(0.28))
                        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.stroke.opacity(0.6)))
                )

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
                        .onTapGesture { withAnimation(.spring(response: 0.4)) { scene = i; step = 0 } }
                }
            }
        }
        .padding(16)
        .glass(0, radius: 24, tint: scene == 4 ? Theme.accent2 : Theme.accent3)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: scene)
        .task(id: scene) { await play() }
    }

    /// Beats: how far the line has flattened, and how green it still is.
    private var flat: Double { scene == 0 ? 0 : (scene == 3 ? (step >= 1 ? 0 : 1) : 1) }
    private var lineColor: Color { flat < 0.5 ? alive : gone }

    private func play() async {
        step = 0
        let beats = [2, 4, 4, 3, 4][scene]
        for b in 1...beats {
            await pause(scene == 3 && b == 1 ? 1.0 : 0.7)
            if Task.isCancelled { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { step = b }
            if scene == 3 && b == 1 {
                beatPulse = true
                Haptics.success()
                withAnimation(.easeOut(duration: 0.6)) { beatPulse = false }
            }
        }
        await pause(scene == 4 ? 2.6 : 1.8)
        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.5)) { scene = (scene + 1) % sceneCount }
    }

    // MARK: The stage

    private var stage: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                // The line itself, alive or flat, running the full width.
                TimelineView(.animation(minimumInterval: 1 / 30, paused: scene == 4 && step >= 2)) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    PulseLine(phase: t, flat: flat)
                        .stroke(lineColor.opacity(scene == 4 && step >= 1 ? 0.25 : 1),
                                style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                        .shadow(color: lineColor.opacity(0.55), radius: beatPulse ? 14 : 6)
                        .animation(.easeInOut(duration: 0.8), value: flat)
                }
                .frame(height: 64)

                sceneLayer(w: w, h: h)
            }
        }
    }

    @ViewBuilder
    private func sceneLayer(w: CGFloat, h: CGFloat) -> some View {
        switch scene {
        case 0: aliveLayer
        case 1: silenceLayer
        case 2: askingLayer
        case 3: answeredLayer
        default: deliveryLayer(w: w)
        }
    }

    /// Scene 1 — the vault was opened today, so the line beats.
    private var aliveLayer: some View {
        VStack {
            Spacer()
            Label(tr("فتحت خزنتك اليوم", "Vault opened today"), systemImage: "checkmark.seal.fill")
                .font(Theme.font(11, .bold)).foregroundStyle(alive)
                .padding(.horizontal, 10).frame(height: 26)
                .background(Capsule().fill(alive.opacity(0.14)))
                .opacity(step >= 1 ? 1 : 0)
        }
        .padding(.bottom, 12)
    }

    /// Scene 2 — the days pile up on a line that no longer moves.
    private var silenceLayer: some View {
        VStack(spacing: 0) {
            Text(tr("\(min(30, step * 8)) يوم بدون أي أثر", "\(min(30, step * 8)) days with no sign"))
                .font(Theme.font(13, .heavy)).foregroundStyle(gone)
                .contentTransition(.numericText())
                .padding(.top, 14)
            Spacer()
            // the days filling in, one tick each
            HStack(spacing: 3) {
                ForEach(0..<30, id: \.self) { i in
                    Capsule()
                        .fill(i < step * 8 ? warm.opacity(0.75) : Theme.surfaceHi)
                        .frame(width: 4, height: i < step * 8 ? 11 : 6)
                }
            }
            .animation(.easeOut(duration: 0.5), value: step)
            .padding(.bottom, 14)
        }
    }

    /// Scene 3 — three knocks on a flat line, none of them answered.
    private var askingLayer: some View {
        VStack(spacing: 8) {
            Spacer()
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { i in
                    HStack(spacing: 5) {
                        Image(systemName: "heart.text.square.fill").font(.system(size: 10))
                        Text(tr("إنت بخير؟", "Okay?")).font(Theme.font(10, .bold))
                    }
                    .foregroundStyle(step > i ? warm : Theme.faint.opacity(0.4))
                    .padding(.horizontal, 9).frame(height: 26)
                    .background(Capsule().fill(step > i ? warm.opacity(0.14) : Theme.surfaceHi.opacity(0.5)))
                    .scaleEffect(step > i ? 1 : 0.8)
                    .offset(y: step > i ? 0 : 8)
                }
            }
            Text(step >= 4 ? tr("ولا ردّ", "No reply") : tr("كل يوم مرة", "Once a day"))
                .font(Theme.font(11, .bold)).foregroundStyle(step >= 4 ? Theme.danger : Theme.faint)
            Spacer()
        }
    }

    /// Scene 4 — he answered: the line comes back to life and the counter empties.
    private var answeredLayer: some View {
        VStack {
            Spacer()
            HStack(spacing: 7) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(hex: 0xFF5FA2))
                    .scaleEffect(beatPulse ? 1.35 : 1)
                Text(step >= 1 ? tr("الحمدلله — العدّاد رجع صفر", "Thank God — counter back to zero")
                               : tr("أنا بخير", "I'm fine"))
                    .font(Theme.font(11, .bold)).foregroundStyle(step >= 1 ? alive : Theme.sub)
            }
            .padding(.horizontal, 12).frame(height: 30)
            .background(Capsule().fill(step >= 1 ? alive.opacity(0.14) : Theme.surfaceHi))
            Spacer()
        }
    }

    /// Scene 5 — the flat line folds into the letter, and the letter reaches one person.
    private func deliveryLayer(w: CGFloat) -> some View {
        ZStack {
            // the trustee, waiting at the end of the line
            Image(systemName: "person.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(step >= 3 ? Theme.accent2 : Theme.faint)
                .frame(width: 34, height: 34)
                .background(Circle().fill(step >= 3 ? Theme.accent2.opacity(0.16) : Theme.surfaceHi))
                .overlay(Circle().strokeBorder(step >= 3 ? Theme.accent2.opacity(0.5) : .clear, lineWidth: 1.5))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 14)

            // the will, folded out of the line and carried across
            WillPaper(open: step >= 3)
                .frame(width: step >= 3 ? 74 : 44, height: step >= 3 ? 56 : 14)
                .opacity(step >= 1 ? 1 : 0)
                .offset(x: step >= 2 ? w * 0.28 : 0)
                .animation(.spring(response: 0.75, dampingFraction: 0.8), value: step)

            if step >= 4 {
                Text(tr("مرة وحدة، وله هو بس", "Once, and only to him"))
                    .font(Theme.font(11, .bold)).foregroundStyle(Theme.accent2)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
        }
    }
}

/// The will: a flat strip that unfolds into a sheet with a few written lines.
private struct WillPaper: View {
    let open: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: open ? 7 : 3)
                .fill(LinearGradient(colors: [Color(hex: 0xFFFBF0), Color(hex: 0xEADFC6)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: .black.opacity(0.35), radius: open ? 10 : 3, y: 3)
            if open {
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 1.5).fill(Theme.accent2.opacity(0.7)).frame(width: 30, height: 3)
                    ForEach(0..<3, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color(hex: 0x6B5A3E).opacity(0.45))
                            .frame(width: [44.0, 50.0, 34.0][i], height: 2.5)
                    }
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            }
        }
    }
}

/// The pulse trace. `flat` morphs it from a beating heart line to a straight one, which is the
/// whole animation in a single number.
private struct PulseLine: Shape {
    let phase: Double
    var flat: Double

    var animatableData: Double {
        get { flat }
        set { flat = newValue }
    }

    func path(in r: CGRect) -> Path {
        var p = Path()
        let mid = r.midY
        let span = r.width
        let amp = 1 - flat
        let shift = CGFloat((phase * 0.4).truncatingRemainder(dividingBy: 1)) * span
        // one beat as fractions of the width; the y values scale to nothing as the line flattens
        let beat: [(CGFloat, CGFloat)] = [(0, 0), (0.30, 0), (0.36, -0.14), (0.42, 0.36), (0.48, -0.92),
                                          (0.54, 0.30), (0.60, -0.07), (0.66, 0), (1, 0)]
        for cycle in -1...1 {
            let base = CGFloat(cycle) * span - shift
            for (i, pt) in beat.enumerated() {
                let x = base + pt.0 * span
                let y = mid + pt.1 * r.height * 0.5 * amp
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
