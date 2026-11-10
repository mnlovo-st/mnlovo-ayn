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

// MARK: - Step-by-step animated guide (mock phone + text)

private struct GuideFinger: View {
    var pressed: Bool
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(pressed ? 0 : 0.6), lineWidth: 2)
                .frame(width: pressed ? 38 : 14, height: pressed ? 38 : 14)
                .opacity(pressed ? 1 : 0)
            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: 24))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
                .offset(x: 10, y: 14)
                .scaleEffect(pressed ? 0.82 : 1)
        }
        .allowsHitTesting(false)
    }
}

struct TelegramGuide: View {
    @State private var scene = 0
    @State private var tap = false
    @State private var reveal = false
    @State private var auto = true
    private let blue = TelegramService.blue

    private struct Step { let title: String; let detail: String }
    private var steps: [Step] {
        [Step(title: tr("١. اضغط «ربط تيليجرام»", "1. Tap “Link Telegram”"),
              detail: tr("من هالصفحة تحت. التطبيق يجهّز لك رابط خاص فيك أنت بس، ويفتح تيليجرام لحاله.",
                         "Right here below. The app prepares a private link just for you and opens Telegram by itself.")),
         Step(title: tr("٢. اضغط «ابدأ» (Start)", "2. Tap “Start”"),
              detail: tr("تيليجرام بيفتح على بوتنا الرسمي MNLOVO SAVER ‏(@mnlovo_sbot). اضغط الزر الأزرق اللي تحت الشاشة.",
                         "Telegram opens our official MNLOVO SAVER bot (@mnlovo_sbot). Tap the blue button at the bottom.")),
         Step(title: tr("٣. خلاص! ارجع للتطبيق", "3. Done! Come back to the app"),
              detail: tr("البوت يرد عليك «تم الربط ✓»، والتطبيق يكتشف الربط لحاله. لا تنسخ ولا تلصق ولا تكتب أي شي.",
                         "The bot replies “Linked ✓” and the app detects it on its own. Nothing to copy, paste or type.")),
         Step(title: tr("٤. تبيه في قروب أو قناة؟ (اختياري)", "4. Want it in a group or channel? (optional)"),
              detail: tr("بعد الربط اضغط «أضف قروب» أو «أضف قناة». تيليجرام يعرض لك قائمتك، اختر وحدة واضغط «إضافة». البوت ياخذ صلاحية النشر بس.",
                         "After linking, tap “Add group” or “Add channel”. Telegram shows your list; pick one and tap “Add”. The bot only gets permission to post.")),
         Step(title: tr("٥. وكل شي يوصل مرتّب", "5. Everything arrives neatly"),
              detail: tr("أي حساب أو تذكير أو ملاحظة تضيفها تنرسل تلقائياً بشكل منسّق مع التاريخ. 🔴 السري جداً ما ينرسل أبداً.",
                         "Every account, reminder or note you add is posted automatically, formatted and dated. 🔴 Top-secret items are never sent."))]
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Label(tr("كيف أربطه؟ خطوة بخطوة", "How to link, step by step"), systemImage: "play.rectangle.fill")
                    .font(Theme.font(15, .heavy)).foregroundStyle(Theme.text)
                Spacer()
                Text("\(scene + 1)/\(steps.count)").font(Theme.mono(13, .bold)).foregroundStyle(Theme.sub)
            }

            phone
                .frame(width: 176, height: 262)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                Text(steps[scene].title).font(Theme.font(18, .heavy)).foregroundStyle(Theme.text)
                Text(steps[scene].detail).font(Theme.font(14)).foregroundStyle(Theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .id(scene)
            .transition(.opacity.combined(with: .move(edge: .bottom)))

            HStack(spacing: 12) {
                CircleIconButton(icon: "chevron.backward", size: 36, tint: Theme.sub) { go(-1) }
                HStack(spacing: 6) {
                    ForEach(0..<steps.count, id: \.self) { i in
                        Capsule().fill(i == scene ? AnyShapeStyle(blue) : AnyShapeStyle(Theme.surfaceHi))
                            .frame(width: i == scene ? 22 : 7, height: 7)
                            .onTapGesture { auto = false; withAnimation(.spring(response: 0.45)) { scene = i } }
                    }
                }
                .frame(maxWidth: .infinity)
                CircleIconButton(icon: "chevron.forward", size: 36, tint: Theme.sub) { go(1) }
            }
        }
        .padding(16)
        .glass(0, radius: 24, tint: blue)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: scene)
        .task(id: scene) { await play() }
    }

    private func go(_ d: Int) {
        auto = false
        Haptics.selection()
        withAnimation(.spring(response: 0.45)) { scene = (scene + d + steps.count) % steps.count }
    }

    private func play() async {
        tap = false
        reveal = false
        await pause(0.7)
        withAnimation(.easeOut(duration: 0.18)) { tap = true }
        await pause(0.25)
        withAnimation(.easeOut(duration: 0.25)) { tap = false }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { reveal = true }
        await pause(auto ? 3.4 : 600)
        guard !Task.isCancelled, auto else { return }
        withAnimation(.spring(response: 0.45)) { scene = (scene + 1) % steps.count }
    }

    // MARK: Mock phone

    private var phone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30).fill(Color.black.opacity(0.6))
            Group {
                switch scene {
                case 0: appScreen
                case 1: botScreen
                case 2: linkedScreen
                case 3: pickerScreen
                default: postScreen
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 30)
            .padding(.bottom, 14)
            .id(scene)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
            RoundedRectangle(cornerRadius: 30).strokeBorder(LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)],
                                                                          startPoint: .top, endPoint: .bottom), lineWidth: 2)
            Capsule().fill(Color.black).frame(width: 56, height: 15)
                .frame(maxHeight: .infinity, alignment: .top).padding(.top, 9)
        }
        .shadow(color: blue.opacity(0.25), radius: 20)
    }

    private func bar(_ w: CGFloat, _ c: Color = Theme.surfaceHi) -> some View {
        RoundedRectangle(cornerRadius: 3).fill(c).frame(width: w, height: 6)
    }

    private var botAvatar: some View {
        Circle().fill(Theme.brandGradient).frame(width: 30, height: 30)
            .overlay(Image(systemName: "eye.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(.white))
    }

    private var appScreen: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("تيليجرام", "Telegram")).font(Theme.font(13, .heavy)).foregroundStyle(Theme.text)
            HStack(spacing: 6) {
                Image(systemName: "paperplane.circle.fill").font(.system(size: 22)).foregroundStyle(blue)
                VStack(alignment: .leading, spacing: 4) { bar(70); bar(46) }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
            bar(110); bar(84)
            Spacer()
            HStack(spacing: 5) {
                Image(systemName: "paperplane.fill").font(.system(size: 10, weight: .bold))
                Text(tr("ربط تيليجرام", "Link Telegram")).font(Theme.font(11, .heavy))
            }
            .foregroundStyle(Theme.bg)
            .frame(maxWidth: .infinity).frame(height: 32)
            .background(Capsule().fill(Theme.gradient))
            .scaleEffect(tap ? 0.92 : 1)
            .shadow(color: Theme.accent.opacity(reveal ? 0.8 : 0.3), radius: reveal ? 12 : 4)
            .overlay(alignment: .center) { GuideFinger(pressed: tap) }
        }
    }

    private var botScreen: some View {
        VStack(spacing: 7) {
            botAvatar.scaleEffect(1.3).padding(.top, 4)
            HStack(spacing: 3) {
                Text("MNLOVO SAVER").font(Theme.font(11, .heavy)).foregroundStyle(Theme.text)
                Image(systemName: "checkmark.seal.fill").font(.system(size: 9)).foregroundStyle(blue)
            }
            Text("@mnlovo_sbot").font(Theme.font(9, .medium)).foregroundStyle(Theme.sub)
            Text(tr("البوت الرسمي لتطبيق MNLOVO SAVER 🔐", "The official MNLOVO SAVER bot 🔐"))
                .font(Theme.font(9, .medium)).foregroundStyle(Theme.text.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
            Spacer()
            Text(tr("ابدأ", "START"))
                .font(Theme.font(12, .heavy)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 10).fill(blue))
                .scaleEffect(tap ? 0.92 : 1)
                .overlay(alignment: .center) { GuideFinger(pressed: tap) }
        }
    }

    private var linkedScreen: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                botAvatar.scaleEffect(0.8)
                Text("MNLOVO SAVER").font(Theme.font(10, .heavy)).foregroundStyle(Theme.text)
                Spacer()
            }
            Spacer()
            Text("/start").font(Theme.font(10, .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 10).fill(blue))
                .frame(maxWidth: .infinity, alignment: .trailing)
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("✅ تم ربط MNLOVO SAVER", "✅ MNLOVO SAVER linked")).font(Theme.font(10, .heavy))
                bar(80, Theme.faint); bar(60, Theme.faint)
            }
            .foregroundStyle(Theme.text)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surfaceHi))
            .frame(maxWidth: .infinity, alignment: .leading)
            .scaleEffect(reveal ? 1 : 0.4, anchor: .bottomLeading)
            .opacity(reveal ? 1 : 0)
            Spacer()
            Label(tr("ارجع للتطبيق", "Back to the app"), systemImage: "arrow.uturn.backward.circle.fill")
                .font(Theme.font(10, .bold)).foregroundStyle(Theme.ok)
                .opacity(reveal ? 1 : 0)
        }
    }

    private var pickerScreen: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(tr("اختر قروب أو قناة", "Choose a group or channel")).font(Theme.font(11, .heavy)).foregroundStyle(Theme.text)
            ForEach(0..<3, id: \.self) { i in
                let names = [tr("العائلة", "Family"), tr("قناتي", "My channel"), tr("الشغل", "Work")]
                HStack(spacing: 7) {
                    Circle().fill(i == 1 ? blue.opacity(0.8) : Theme.surfaceHi).frame(width: 22, height: 22)
                        .overlay(Image(systemName: i == 1 ? "megaphone.fill" : "person.3.fill").font(.system(size: 9)).foregroundStyle(.white))
                    Text(names[i]).font(Theme.font(10, .semibold)).foregroundStyle(Theme.text)
                    Spacer()
                    if i == 1 && reveal { Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(blue) }
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 9).fill(i == 1 && reveal ? blue.opacity(0.18) : Theme.surface))
                .overlay(alignment: .center) { if i == 1 { GuideFinger(pressed: tap).opacity(reveal ? 0 : 1) } }
            }
            Spacer()
            Text(tr("إضافة البوت كمشرف", "Add bot as admin"))
                .font(Theme.font(11, .heavy)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 10).fill(blue))
                .opacity(reveal ? 1 : 0.25)
            Text(tr("صلاحية: نشر الرسائل فقط", "Permission: post messages only"))
                .font(Theme.font(8, .medium)).foregroundStyle(Theme.sub)
                .frame(maxWidth: .infinity)
        }
    }

    private var postScreen: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(blue.opacity(0.8)).frame(width: 22, height: 22)
                    .overlay(Image(systemName: "megaphone.fill").font(.system(size: 9)).foregroundStyle(.white))
                Text(tr("قناتي", "My channel")).font(Theme.font(10, .heavy)).foregroundStyle(Theme.text)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 4) {
                Text("🔐 " + tr("حساب جديد", "New account") + "  #" + tr("حسابات", "accounts"))
                    .font(Theme.font(10, .heavy)).foregroundStyle(Theme.text)
                Text("━━━━━━━━━").font(.system(size: 7)).foregroundStyle(Theme.faint)
                HStack(spacing: 4) { Text(tr("التطبيق:", "App:")).font(Theme.font(9, .bold)); bar(50, Theme.faint) }
                HStack(spacing: 4) { Text(tr("المستخدم:", "Login:")).font(Theme.font(9, .bold)); bar(60, blue.opacity(0.6)) }
                HStack(spacing: 4) { Text("🟢").font(.system(size: 8)); bar(40, Theme.faint) }
                Text("🕒 " + Fmt.date(Date())).font(Theme.font(8)).foregroundStyle(Theme.sub).lineLimit(1)
            }
            .foregroundStyle(Theme.text)
            .padding(9)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surfaceHi))
            .scaleEffect(reveal ? 1 : 0.4, anchor: .bottomLeading)
            .opacity(reveal ? 1 : 0)
            Spacer()
        }
    }
}

// MARK: - Setup screen

struct TelegramSetupView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var settings = TelegramService.shared.settings
    @State private var busy: String?
    @State private var waitingSince: Date?
    @State private var error: String?
    @State private var party: Date?
    @State private var eye: EyeMood = .idle
    @State private var showCloud = false
    @State private var removing: TelegramService.Target?
    @State private var showChoice = false
    @State private var exclusive = false
    @State private var shareURL: URL?

    private let tg = TelegramService.shared
    private let blue = TelegramService.blue
    private var linked: Bool { !settings.targets.isEmpty }
    private var hasPrivate: Bool { settings.targets.contains { $0.type == "private" && !$0.isFriend } }

    var body: some View {
        SheetScaffold(title: tr("تيليجرام", "Telegram")) {
            if state.isDecoy {
                Label(tr("هالخاصية مو متاحة هنا.", "This feature isn't available here."), systemImage: "nosign")
                    .font(Theme.font(15, .semibold)).foregroundStyle(Theme.sub).glass(16)
            } else {
                header
                if !linked {
                    TelegramExplainer()
                    TelegramGuide()
                }
                if !tg.cloudReady { cloudNeeded } else if !linked { linkCard } else { linkedSection }
                privacyNote
            }
        }
        .overlay {
            if let party {
                ConfettiBurst(start: party).ignoresSafeArea().allowsHitTesting(false)
            }
        }
        .task { await refresh() }
        .task(id: waitingSince) { await poll() }
        .onChange(of: scenePhase) { _, p in
            if p == .active { Task { await refresh() } }
        }
        .sheet(isPresented: $showCloud) { CloudSetupView().environmentObject(state) }
        .sheet(isPresented: $showChoice) {
            DestinationChoiceSheet { choice in
                showChoice = false
                switch choice {
                case .bot: state.show(tr("تمام ✓ بيوصلك كل شي في محادثة البوت", "Done ✓ everything goes to the bot chat"), icon: "paperplane.fill")
                case .group: exclusive = true; Task { await addGroup() }
                case .channel: exclusive = true; addChannel()
                case .person: exclusive = true; Task { await addPerson() }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: Binding(get: { shareURL.map { ShareItem(url: $0) } }, set: { if $0 == nil { shareURL = nil } })) { item in
            ActivityView(items: [tr("اضغط الرابط وبعدين «ابدأ» عشان توصلك تحديثاتي من MNLOVO SAVER:", "Tap the link, then “Start”, to get my MNLOVO SAVER updates:"), item.url])
                .presentationDetents([.medium])
        }
        .confirmationDialog(tr("إلغاء الربط؟", "Unlink?"), isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible, presenting: removing) { t in
            Button(tr("إلغاء ربط \(t.title)", "Unlink \(t.title)"), role: .destructive) { Task { await remove(t) } }
        } message: { t in
            Text(t.type == "private" ? tr("ما بيوصلك شي في المحادثة الخاصة.", "Nothing more will be sent to your private chat.")
                                     : tr("البوت بيطلع من \(t.title) لحاله.", "The bot will leave \(t.title) by itself."))
        }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(blue.opacity(0.18)).frame(width: 64, height: 64)
                Image(systemName: "paperplane.fill").font(.system(size: 28, weight: .bold)).foregroundStyle(blue)
                    .symbolEffect(.bounce, value: party)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("البوت الرسمي", "Official bot")).font(Theme.font(13, .semibold)).foregroundStyle(Theme.sub)
                HStack(spacing: 4) {
                    Text("@\(TelegramService.botUsername)").font(Theme.font(19, .heavy)).foregroundStyle(Theme.text)
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(blue)
                }
                .environment(\.layoutDirection, .leftToRight)
                Text(linked ? tr("مربوط ✓ \(settings.enabled ? "والنشر شغّال" : "والنشر موقّف")", "Linked ✓ \(settings.enabled ? "posting on" : "posting paused")")
                            : tr("جاهز، بس تحتاج تربطه بضغطة", "Ready. One tap to link"))
                    .font(Theme.font(13, .bold)).foregroundStyle(linked ? Theme.ok : Theme.accent)
            }
            Spacer(minLength: 0)
        }
        .glass(16, tint: blue)
    }

    private var cloudNeeded: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(tr("خطوة وحدة قبل", "One step first"), systemImage: "icloud.slash.fill")
                .font(Theme.font(16, .heavy)).foregroundStyle(Theme.warn)
            Text(tr("الربط يمر عن طريق سيرفرنا عشان يعرف إن هذا تيليجرامك أنت. سجّل دخول السحابة بكود الإيميل وارجع هنا.",
                    "Linking goes through our server so it knows this Telegram is yours. Sign in to the cloud with an email code, then come back."))
                .font(Theme.font(13)).foregroundStyle(Theme.sub)
            SecondaryButton(title: tr("تسجيل دخول السحابة", "Sign in to the cloud"), icon: "icloud.fill", color: Theme.accent) { showCloud = true }
        }
        .glass(16, tint: Theme.warn)
    }

    private var linkCard: some View {
        VStack(spacing: 12) {
            if waitingSince != nil {
                EyeView(mood: eye, size: 80, sounds: false)
                Text(tr("ننتظرك تضغط «ابدأ» في تيليجرام…", "Waiting for you to tap “Start” in Telegram…"))
                    .font(Theme.font(15, .bold)).foregroundStyle(Theme.text).multilineTextAlignment(.center)
                Text(tr("أول ما تضغطه ارجع هنا، نكمل لحالنا.", "As soon as you tap it, come back here — we take it from there."))
                    .font(Theme.font(13)).foregroundStyle(Theme.sub).multilineTextAlignment(.center)
            }
            if let error { Text(error).font(Theme.font(13, .semibold)).foregroundStyle(Theme.danger).multilineTextAlignment(.center) }
            PrimaryButton(title: waitingSince == nil ? tr("ربط تيليجرام بضغطة", "Link Telegram in one tap") : tr("افتح تيليجرام مرة ثانية", "Open Telegram again"),
                          icon: "paperplane.fill", loading: busy == "private") { Task { await linkPrivate() } }
        }
        .glass(16)
    }

    private var linkedSection: some View {
        VStack(spacing: 14) {
            // master switch
            HStack(spacing: 12) {
                Image(systemName: "bolt.fill").foregroundStyle(blue).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("النشر التلقائي", "Auto-posting")).font(Theme.font(16, .heavy)).foregroundStyle(Theme.text)
                    Text(tr("أي شي تضيفه يوصل تيليجرام", "New items are posted to Telegram")).font(Theme.font(12)).foregroundStyle(Theme.sub)
                }
                Spacer()
                Toggle("", isOn: $settings.enabled).labelsHidden().tint(Theme.accent)
            }
            .glass(14)

            // where it goes
            VStack(alignment: .leading, spacing: 10) {
                Text(tr("وين يوصل", "Where it goes")).font(Theme.font(16, .heavy)).foregroundStyle(Theme.text)
                ForEach(settings.targets) { t in targetRow(t) }
                if !hasPrivate {
                    SecondaryButton(title: tr("اربط محادثتك الخاصة", "Link your private chat"), icon: "person.fill", color: blue) {
                        Task { await linkPrivate() }
                    }
                }
                HStack(spacing: 8) {
                    addButton(tr("أضف قروب", "Add group"), "person.3.fill", key: "group") { Task { await addGroup() } }
                    addButton(tr("أضف قناة", "Add channel"), "megaphone.fill", key: "channel") { addChannel() }
                    addButton(tr("أضف شخص", "Add person"), "person.2.fill", key: "person") { Task { await addPerson() } }
                }
                Label(tr("تقدر تتحكم من تيليجرام نفسه: اكتب للبوت /menu (إيقاف، مشاركة، فصل، مساعدة في الاسترجاع).",
                         "You can also control it from Telegram: send /menu to the bot (pause, share, unlink, recovery help)."),
                      systemImage: "command")
                    .font(Theme.font(12, .medium)).foregroundStyle(Theme.sub)
                if waitingSince != nil {
                    HStack(spacing: 8) {
                        ProgressView().tint(blue)
                        Text(tr("ننتظر تيليجرام… اختر القروب/القناة واضغط «إضافة» وارجع هنا.", "Waiting for Telegram… pick the group/channel, tap “Add”, then come back."))
                            .font(Theme.font(12, .semibold)).foregroundStyle(Theme.sub)
                    }
                }
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 6) {
                        guideLine("person.3.fill", tr("قروب: اضغط «أضف قروب» ← تيليجرام يفتح قائمة قروباتك ← اختر القروب ← «إضافة». يوصل القروب رسالة «تم الربط ✓».",
                                                       "Group: tap “Add group” → Telegram lists your groups → pick one → “Add”. The group gets a “Linked ✓” message."))
                        guideLine("megaphone.fill", tr("قناة: اضغط «أضف قناة» ← اختر قناتك ← «إضافة كمشرف» (صلاحية النشر بس) ← «حفظ».",
                                                        "Channel: tap “Add channel” → pick your channel → “Add as admin” (post only) → “Save”."))
                        guideLine("person.2.fill", tr("شخص: اضغط «أضف شخص» ← أرسل له الرابط ← يفتحه ويضغط «ابدأ». الرابط لمرة وحدة ولمدة ٣٠ دقيقة.",
                                                       "Person: tap “Add person” → send them the link → they open it and tap “Start”. One-time link, valid 30 minutes."))
                        guideLine("person.badge.minus", tr("تبي توقفه؟ اضغط ✕ جنب أي وحدة، والبوت يطلع لحاله.", "Want to stop? Tap ✕ next to any of them and the bot leaves by itself."))
                    }
                    .padding(.top, 6)
                } label: {
                    Label(tr("كيف أضيف قروب أو قناة أو شخص؟", "How do I add a group, channel or person?"), systemImage: "questionmark.circle.fill")
                        .font(Theme.font(14, .bold)).foregroundStyle(blue)
                }
                .tint(blue)
            }
            .glass(14)

            // what gets sent
            VStack(alignment: .leading, spacing: 0) {
                Text(tr("وش يوصل", "What gets sent")).font(Theme.font(16, .heavy)).foregroundStyle(Theme.text).padding(.bottom, 6)
                option("key.horizontal.fill", tr("الحسابات", "Accounts"), $settings.accounts)
                option("eye.slash.fill", tr("كلمات السر (مخفية تحت غطاء)", "Passwords (hidden under a spoiler)"), $settings.passwords)
                option("bell.fill", tr("التذكيرات", "Reminders"), $settings.reminders)
                option("note.text", tr("الملاحظات", "Notes"), $settings.notes)
                option("paperclip", tr("الملفات (الاسم والحجم بس)", "Files (name & size only)"), $settings.files)
                option("pencil", tr("التعديلات كمان", "Edits too"), $settings.updates)
                option("shield.lefthalf.filled", tr("العناصر 🟡 الحساسة", "🟡 Sensitive items"), $settings.includeSensitive)
                option("eye.trianglebadge.exclamationmark", tr("النصوص مشوّشة (تنكشف باللمس)", "Blurred text (tap to reveal)"), $settings.spoiler)
            }
            .glass(14)

            if let error { Text(error).font(Theme.font(13, .semibold)).foregroundStyle(Theme.danger) }

            SecondaryButton(title: tr("أرسل رسالة تجريبية", "Send a test message"), icon: "paperplane", color: blue) { Task { await test() } }
        }
        .onChange(of: settings) { _, new in
            var s = tg.settings
            s.enabled = new.enabled; s.accounts = new.accounts; s.passwords = new.passwords; s.reminders = new.reminders
            s.notes = new.notes; s.files = new.files; s.updates = new.updates; s.includeSensitive = new.includeSensitive
            s.spoiler = new.spoiler
            tg.settings = s
        }
    }

    private var privacyNote: some View {
        Label(tr("رسائل البوت في تيليجرام مو مشفّرة طرف لطرف. الأشياء 🔴 السرية جداً ما تنرسل أبداً، وكلمات السر ما تنرسل إلا إذا فعّلتها (وتطلع مخفية تحت غطاء). الخزنة الوهمية ما ترسل شي.",
                 "Bot messages in Telegram aren't end-to-end encrypted. 🔴 Top-secret items are never sent, passwords only if you turn it on (hidden under a spoiler). The decoy vault never posts."),
              systemImage: "exclamationmark.shield.fill")
            .font(Theme.font(12, .medium)).foregroundStyle(Theme.warn)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(12, tint: Theme.warn)
    }

    private func targetRow(_ t: TelegramService.Target) -> some View {
        HStack(spacing: 10) {
            Image(systemName: t.icon).foregroundStyle(blue).frame(width: 30, height: 30)
                .background(Circle().fill(blue.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text(t.title).font(Theme.font(15, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Text(t.typeTitle).font(Theme.font(11)).foregroundStyle(Theme.sub)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { t.enabled }, set: { on in Task { await toggle(t, on) } }))
                .labelsHidden().tint(Theme.accent)
            Button { removing = t } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundStyle(Theme.faint)
            }
            .buttonStyle(PressScale())
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    private func addButton(_ title: String, _ icon: String, key: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 6) {
                if busy == key { ProgressView().tint(blue) } else { Image(systemName: icon).font(.system(size: 18, weight: .bold)) }
                Text(title).font(Theme.font(13, .bold))
            }
            .foregroundStyle(blue)
            .frame(maxWidth: .infinity).frame(height: 70)
            .background(RoundedRectangle(cornerRadius: 16).fill(blue.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(blue.opacity(0.35)))
        }
        .buttonStyle(PressScale())
        .disabled(busy != nil || (key == "channel" && !hasPrivate))
        .opacity(key == "channel" && !hasPrivate ? 0.45 : 1)
    }

    private func guideLine(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).font(.system(size: 12, weight: .bold)).foregroundStyle(blue).frame(width: 18)
            Text(text).font(Theme.font(13)).foregroundStyle(Theme.sub).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func option(_ icon: String, _ title: String, _ binding: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(blue).frame(width: 26)
            Text(title).font(Theme.font(14, .semibold)).foregroundStyle(Theme.text)
            Spacer()
            Toggle("", isOn: binding).labelsHidden().tint(Theme.accent)
        }
        .padding(.vertical, 7)
    }

    // MARK: Actions

    private func open(_ url: URL) {
        state.allowShortTrip(180)
        openURL(url)
        withAnimation { waitingSince = Date(); eye = .lookUp }
    }

    private func linkPrivate() async {
        busy = "private"; defer { busy = nil }
        do { open(try await tg.privateLink()); error = nil }
        catch { self.error = error.localizedDescription; FX.error() }
    }

    private func addGroup() async {
        busy = "group"; defer { busy = nil }
        do { open(try await tg.groupLink()); error = nil }
        catch { self.error = error.localizedDescription; FX.error() }
    }

    private func addChannel() { open(tg.channelLink()) }

    private func addPerson() async {
        busy = "person"; defer { busy = nil }
        do {
            let url = try await tg.friendLink()
            shareURL = url
            withAnimation { waitingSince = Date(); eye = .lookUp }
            error = nil
        } catch { self.error = error.localizedDescription; FX.error() }
    }

    private func refresh() async {
        guard tg.cloudReady, !state.isDecoy else { return }
        let before = Set(settings.targets.map(\.id))
        guard let list = try? await tg.refresh() else { return }
        let fresh = tg.settings
        withAnimation(.spring(response: 0.5)) { settings = fresh }
        let added = list.filter { !before.contains($0.id) }
        if let first = added.first, waitingSince != nil || !before.isEmpty {
            celebrate(first)
            let isBotChat = first.type == "private" && !first.isFriend
            if isBotChat && list.count == 1 {
                // First link: let them choose where messages should go.
                Task { await pause(1.6); showChoice = true }
            } else if exclusive, !isBotChat, let botChat = list.first(where: { $0.type == "private" && !$0.isFriend && $0.enabled }) {
                exclusive = false
                await toggle(botChat, false)
                state.show(tr("صار الإرسال لـ \(first.title) بدل محادثة البوت", "Now sending to \(first.title) instead of the bot chat"), icon: "arrow.triangle.swap")
            }
        }
    }

    private func poll() async {
        guard let since = waitingSince else { return }
        while !Task.isCancelled, Date().timeIntervalSince(since) < 300 {
            await pause(2.5)
            if Task.isCancelled { return }
            let before = settings.targets.count
            await refresh()
            if settings.targets.count > before { return }
            if waitingSince != nil { withAnimation { eye = eye == .lookUp ? .thinking : .lookUp } }
        }
        withAnimation { waitingSince = nil }
    }

    private func celebrate(_ t: TelegramService.Target) {
        withAnimation(.spring) { waitingSince = nil; eye = .happy }
        party = Date()
        SoundFX.shared.play(.success, volume: 0.6)
        Haptics.success()
        state.show(tr("تم ربط \(t.typeTitle) ✓ \(t.title)", "\(t.typeTitle) linked ✓ \(t.title)"), icon: "paperplane.fill")
        Task {
            await pause(3)
            withAnimation { party = nil }
        }
    }

    private func toggle(_ t: TelegramService.Target, _ on: Bool) async {
        do { try await tg.setEnabled(t, on); withAnimation { settings = tg.settings } }
        catch { self.error = error.localizedDescription }
    }

    private func remove(_ t: TelegramService.Target) async {
        do {
            try await tg.remove(t)
            withAnimation(.spring) { settings = tg.settings }
            SoundFX.shared.play(.delete, volume: 0.4)
        } catch { self.error = error.localizedDescription; FX.error() }
    }

    private func test() async {
        do {
            let n = try await tg.send(tg.testMessage())
            if n > 0 {
                Haptics.success()
                state.show(tr("انرسلت ✓ (\(n))", "Sent ✓ (\(n))"), icon: "paperplane.fill")
                error = nil
            } else {
                error = tr("ما وصلت لأي محادثة. فعّل وحدة على الأقل.", "It didn't reach any chat. Turn at least one on.")
            }
        } catch { self.error = error.localizedDescription; FX.error() }
    }
}


// MARK: - Choose where messages go (shown after the first link)

enum TelegramDestination { case bot, group, channel, person }

struct DestinationChoiceSheet: View {
    var onPick: (TelegramDestination) -> Void
    private let blue = TelegramService.blue

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(spacing: 12) {
                    EyeView(mood: .happy, size: 70, sounds: false).padding(.top, 18)
                    Text(tr("وين تبي توصلك الرسائل؟", "Where should messages go?"))
                        .font(Theme.font(22, .heavy)).foregroundStyle(Theme.text)
                    Text(tr("تقدر تغيّر أو تضيف أكثر من وحدة بعدين.", "You can change it or add more later."))
                        .font(Theme.font(13)).foregroundStyle(Theme.sub)
                    choice(.bot, "paperplane.fill", tr("محادثة البوت", "The bot chat"), tr("خاص فيك بس — الأسهل", "Just for you — easiest"))
                    choice(.group, "person.3.fill", tr("قروب", "A group"), tr("تختار قروب من قروباتك", "Pick one of your groups"))
                    choice(.channel, "megaphone.fill", tr("قناة", "A channel"), tr("البوت ينشر فيها كمشرف (نشر فقط)", "The bot posts as an admin (post only)"))
                    choice(.person, "person.2.fill", tr("شخص ثاني", "Another person"), tr("ترسل له رابط ويضغط «ابدأ»", "Send them a link, they tap Start"))
                }
                .padding(20)
            }
        }
    }

    private func choice(_ d: TelegramDestination, _ icon: String, _ title: String, _ sub: String) -> some View {
        Button {
            Haptics.selection()
            onPick(d)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 13).fill(blue))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.font(16, .heavy)).foregroundStyle(Theme.text)
                    Text(sub).font(Theme.font(12)).foregroundStyle(Theme.sub)
                }
                Spacer()
                Image(systemName: "chevron.forward").foregroundStyle(Theme.faint)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.stroke))
        }
        .buttonStyle(PressScale())
    }
}

struct ShareItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct ActivityView: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
