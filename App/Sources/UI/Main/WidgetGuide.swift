import SwiftUI
import UIKit
import Security
import WidgetKit

// MARK: - The widgets, and how to put one on the Home Screen
//
// iOS doesn't let an app place a widget itself; only the person can, from the Home Screen. So this
// screen does the next best thing: shows every widget the app has, and walks through the four
// taps it takes to add one. The walkthrough plays by itself the first time, and the ? button
// brings it back any time.

struct WidgetGuideSheet: View {
    @AppStorage("intro.widgets.seen") private var seen = false
    @State private var showHowTo = false

    private struct Kind: Identifiable {
        let id: String
        let icon: String
        let title: String
        let blurb: String
        let sizes: String
        let tint: Color
    }

    private var kinds: [Kind] {
        [Kind(id: "tasks", icon: "bell.badge.fill", title: tr("التذكيرات الياية", "Next reminders"),
              blurb: tr("أقرب ٣ مهام، ولونها يتغيّر كل ما قرّب موعدها.", "Your next three tasks, coloured by how close they are."),
              sizes: tr("صغير · متوسط · شاشة القفل", "Small · Medium · Lock Screen"), tint: Theme.accent),
         Kind(id: "routines", icon: "checklist", title: tr("روتين اليوم", "Today's routines"),
              blurb: tr("روتينك اليوم بالترتيب، اللي خلّصته مشطوب، والياي ملوّن.", "Today's routines in order: done ones crossed out, the next one highlighted."),
              sizes: tr("صغير · متوسط · كبير · شاشة القفل", "Small · Medium · Large · Lock Screen"), tint: Theme.ok),
         Kind(id: "countdown", icon: "hourglass", title: tr("العد التنازلي", "Countdown"),
              blurb: tr("كم باقي على المهمة الياية، بخط كبير.", "Time left on your next task, in big type."),
              sizes: tr("صغير · شاشة القفل", "Small · Lock Screen"), tint: Color.orange),
         Kind(id: "streak", icon: "flame.fill", title: tr("سلسلة الأيام", "Streak"),
              blurb: tr("كم يوم ورا بعض كمّلت روتينك 🔥", "How many days in a row you've kept your routines 🔥"),
              sizes: tr("صغير · شاشة القفل", "Small · Lock Screen"), tint: Color(hex: 0xFF7A45)),
         Kind(id: "subs", icon: "creditcard.fill", title: tr("الاشتراكات", "Subscriptions"),
              blurb: tr("أقرب تجديد وكم تدفع بالشهر.", "The next renewal and what you pay each month."),
              sizes: tr("صغير · متوسط · شاشة القفل", "Small · Medium · Lock Screen"), tint: Theme.accent2),
         Kind(id: "safety", icon: "checkmark.shield.fill", title: tr("حالة الأمان", "Safety"),
              blurb: tr("آخر نسخة احتياطية، كلمات السر الضعيفة، ومحاولات الدخول. أرقام بس، بدون أسماء.",
                        "Last backup, weak passwords and intrusion attempts. Numbers only, never names."),
              sizes: tr("صغير · متوسط · شاشة القفل", "Small · Medium · Lock Screen"), tint: Theme.accent3),
         Kind(id: "open", icon: "lock.fill", title: tr("فتح سريع", "Quick open"),
              blurb: tr("ضغطة وحدة وتفتح الخزنة.", "One tap opens the vault."),
              sizes: tr("صغير · شاشة القفل", "Small · Lock Screen"), tint: Theme.sub)]
    }

    var body: some View {
        SheetScaffold(title: tr("الودجت", "Widgets")) {
            // the walkthrough, always one tap away
            Button {
                Haptics.tap()
                showHowTo = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Theme.gradient)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("كيف أضيف ودجت؟", "How do I add one?")).font(Theme.font(16, .heavy)).foregroundStyle(Theme.text)
                        Text(tr("أربع ضغطات من الشاشة الرئيسية — شوف الشرح", "Four taps from the Home Screen — watch how"))
                            .font(Theme.font(12)).foregroundStyle(Theme.sub)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "play.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.accent)
                }
                .padding(14)
                .glass(0, radius: 18, tint: Theme.accent)
            }
            .buttonStyle(PressScale())

            WidgetLinkStatus()

            Text(tr("الأنواع اللي عندك", "What's available"))
                .font(Theme.font(13, .bold)).foregroundStyle(Theme.sub)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)

            ForEach(kinds) { k in
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(k.tint.opacity(0.16))
                        .frame(width: 44, height: 44)
                        .overlay(Image(systemName: k.icon).font(.system(size: 18, weight: .bold)).foregroundStyle(k.tint))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(k.title).font(Theme.font(15, .bold)).foregroundStyle(Theme.text)
                        Text(k.blurb).font(Theme.font(12)).foregroundStyle(Theme.sub)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(k.sizes).font(Theme.font(11, .semibold)).foregroundStyle(Theme.faint)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .glass(0, radius: 16)
            }

            Label(tr("الودجت ما يعرض أي كلمة سر أو حساب. المهام السرية تطلع «🔒 مهمة سرية».",
                     "Widgets never show a password or an account. Secret tasks show as “🔒 Secret task”."),
                  systemImage: "lock.shield")
                .font(Theme.font(11, .medium)).foregroundStyle(Theme.faint)
                .padding(.top, 4)
        }
        .onAppear {
            // Make sure the widgets have fresh data the moment the person goes to add one.
            WidgetBridge.update()
            if !seen {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showHowTo = true }
            }
        }
        .fullScreenCover(isPresented: $showHowTo) {
            WidgetHowTo { seen = true; showHowTo = false }
        }
    }
}

/// Is the data actually reaching the widget? The app writes it two ways (App Group and a shared
/// keychain item) and the widget writes back a heartbeat each time it runs, so this card can say
/// which way works on this phone — and "نسخ التقرير" hands over the details when neither does.
struct WidgetLinkStatus: View {
    @State private var beat: WidgetShared.Heartbeat?
    @State private var copied = false
    @State private var tick = 0

    private var groupOK: Bool { WidgetShared.groupGranted }
    private var keychainOK: Bool { WidgetShared.lastKeychainStatus == errSecSuccess }

    private enum LinkState { case working, silent, waiting, blocked }
    private var state: LinkState {
        if let b = beat, Date().timeIntervalSince(b.at) < 6 * 3600 { return b.source == "none" ? .silent : .working }
        return (groupOK || keychainOK) ? .waiting : .blocked
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 20, weight: .bold)).foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.font(15, .heavy)).foregroundStyle(Theme.text)
                    Text(detail).font(Theme.font(12)).foregroundStyle(Theme.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                chip("App Group", groupOK)
                chip("Keychain", keychainOK)
                chip(tr("الودجت", "Widget"), beat.map { $0.source != "none" } ?? false)
            }
            HStack(spacing: 10) {
                Button {
                    Haptics.tap()
                    WidgetBridge.update()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { refresh() }
                } label: {
                    Label(tr("حدّث الحين", "Refresh now"), systemImage: "arrow.clockwise")
                        .font(Theme.font(12, .bold)).foregroundStyle(Theme.accent)
                }
                Spacer()
                Button {
                    UIPasteboard.general.string = report
                    Haptics.tap()
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                } label: {
                    Label(copied ? tr("انّسخ ✓", "Copied ✓") : tr("نسخ التقرير", "Copy report"),
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(Theme.font(12, .bold)).foregroundStyle(Theme.sub)
                }
            }
            .buttonStyle(PressScale())
        }
        .padding(14)
        .glass(0, radius: 18, tint: tint)
        .onAppear { refresh() }
    }

    private func refresh() {
        beat = WidgetShared.lastBeat()
        tick += 1
    }

    private func chip(_ label: String, _ ok: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
            Text(label)
        }
        .font(Theme.font(11, .bold))
        .foregroundStyle(ok ? Theme.ok : Theme.faint)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Capsule().fill((ok ? Theme.ok : Theme.faint).opacity(0.12)))
    }

    private var icon: String {
        switch state {
        case .working: return "checkmark.seal.fill"
        case .silent: return "exclamationmark.triangle.fill"
        case .waiting: return "hourglass"
        case .blocked: return "link.badge.plus"
        }
    }
    private var tint: Color {
        switch state {
        case .working: return Theme.ok
        case .silent, .blocked: return Color.orange
        case .waiting: return Theme.accent
        }
    }
    private var title: String {
        switch state {
        case .working: return tr("الودجت مربوط ويستلم بياناتك", "Widgets are linked")
        case .silent: return tr("الودجت شغّال بس ما يوصله شي", "The widget runs but gets nothing")
        case .waiting: return tr("بانتظار الودجت", "Waiting for the widget")
        case .blocked: return tr("التوقيع ما سمح بالربط", "The signature blocks the link")
        }
    }
    private var detail: String {
        switch state {
        case .working:
            let t = beat.map { $0.at.formatted(date: .omitted, time: .shortened) } ?? ""
            return tr("آخر مرة تحدّث \(t)", "Last updated \(t)")
        case .silent:
            return tr("اضغط «نسخ التقرير» وطرشه لنا عشان نشوف شو اللي ناقص.", "Tap “Copy report” and send it to us.")
        case .waiting:
            return tr("حط أي ودجت عالشاشة الرئيسية، وارجع هني بعد دقيقة.", "Add any widget to the Home Screen, then come back in a minute.")
        case .blocked:
            return tr("التطبيق تثبّت بتوقيع ما يسمح يشارك البيانات مع الودجت. اضغط «نسخ التقرير» وطرشه لنا.",
                      "This install was signed without data sharing. Tap “Copy report” and send it to us.")
        }
    }

    private var report: String {
        let b = beat
        return """
        MNLOVO SAVER widget report
        app: \(Bundle.main.bundleIdentifier ?? "-")  v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")
        profile: \(Provision.hasProfile ? "yes" : "no")  team: \(Provision.teamID ?? "-")
        group: \(WidgetShared.appGroup)  granted: \(groupOK)
        profile groups: \(Provision.appGroups.joined(separator: ", "))
        keychain group: \(SharedKeychain.group ?? "-")  status: \(WidgetShared.lastKeychainStatus)
        profile keychain: \(Provision.keychainGroups.joined(separator: ", "))
        widget beat: \(b.map { "\($0.at.formatted()) via \($0.source) items \($0.items) routines \($0.routines) granted \($0.groupGranted) team \($0.team)" } ?? "none")
        """
    }
}

/// Four scenes on a mock Home Screen: long-press → Edit → Add Widget → search → drop it in.
struct WidgetHowTo: View {
    var onDone: () -> Void

    var body: some View {
        IntroShell(
            captions: [
                (tr("اضغط مطوّل على الشاشة الرئيسية", "Press and hold the Home Screen"),
                 tr("على أي مكان فاضي، لين الأيقونات تبدأ تهتز.", "On any empty spot, until the icons start to jiggle.")),
                (tr("اضغط «تعديل» وبعدين «إضافة أداة»", "Tap “Edit”, then “Add Widget”"),
                 tr("الزر فوق على اليسار.", "The button sits at the top left.")),
                (tr("دوّر على MNLOVO SAVER", "Search for MNLOVO SAVER"),
                 tr("اكتب اسم التطبيق في البحث واختاره.", "Type the app's name and pick it.")),
                (tr("اختار الودجت وحطه", "Pick a widget and place it"),
                 tr("اسحب بين الأنواع والأحجام، واضغط «إضافة أداة». وخلاص ✓", "Swipe between kinds and sizes, then tap “Add Widget”. Done ✓"))
            ],
            beats: [3, 3, 4, 4],
            finishIcon: "square.grid.2x2.fill",
            tint: Theme.accent,
            screen: { scene, step in
                Group {
                    switch scene {
                    case 0: pressScreen(step)
                    case 1: editScreen(step)
                    case 2: searchScreen(step)
                    default: placeScreen(step)
                    }
                }
            },
            onDone: onDone
        )
    }

    private let iconTints: [Color] = [Color(hex: 0x34C759), Color(hex: 0x0A84FF), Color(hex: 0xFF9F0A), Color(hex: 0xFF375F),
                                      Color(hex: 0x5E5CE6), Color(hex: 0x64D2FF), Color(hex: 0xFFD60A), Color(hex: 0xBF5AF2),
                                      Color(hex: 0x30D158), Color(hex: 0xFF453A), Color(hex: 0xAC8E68), Color(hex: 0x8E8E93)]

    /// A home-screen grid; `jiggle` sets the icons wobbling, `gap` leaves room for a widget on top.
    private func grid(jiggle: Bool, gap: Bool = false) -> some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !jiggle)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(0..<(gap ? 8 : 12), id: \.self) { i in
                    RoundedRectangle(cornerRadius: 8)
                        .fill(iconTints[i % iconTints.count].gradient)
                        .frame(width: 30, height: 30)
                        .rotationEffect(.degrees(jiggle ? sin(t * 14 + Double(i)) * 3 : 0))
                }
            }
        }
    }

    private func finger(_ show: Bool, x: CGFloat, y: CGFloat, pressing: Bool = false) -> some View {
        Circle()
            .fill(Color.white.opacity(pressing ? 0.55 : 0.35))
            .frame(width: pressing ? 34 : 26, height: pressing ? 34 : 26)
            .overlay(Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 1.5))
            .offset(x: x, y: y)
            .opacity(show ? 1 : 0)
    }

    private func pressScreen(_ step: Int) -> some View {
        ZStack {
            VStack {
                grid(jiggle: step >= 3)
                Spacer()
            }
            .padding(.top, 8)
            finger(step >= 1, x: 0, y: 70, pressing: step >= 2)
            if step >= 2 && step < 3 {
                Circle().stroke(Color.white.opacity(0.4), lineWidth: 2).frame(width: 54, height: 54).offset(y: 70)
            }
        }
    }

    private func editScreen(_ step: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(tr("تعديل", "Edit"))
                    .font(Theme.font(10, .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 10).frame(height: 22)
                    .background(Capsule().fill(Color.white.opacity(step >= 1 ? 0.35 : 0.18)))
                    .overlay(Capsule().strokeBorder(Theme.accent, lineWidth: step == 1 ? 2 : 0))
                Spacer()
                Text(tr("تم", "Done")).font(Theme.font(10, .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 10).frame(height: 22)
                    .background(Capsule().fill(Color.white.opacity(0.18)))
            }
            .environment(\.layoutDirection, .leftToRight)
            ZStack(alignment: .topLeading) {
                grid(jiggle: true)
                if step >= 2 {
                    VStack(alignment: .leading, spacing: 0) {
                        Label(tr("إضافة أداة", "Add Widget"), systemImage: "plus.square.on.square")
                            .font(Theme.font(10, .bold)).foregroundStyle(Theme.text)
                            .padding(9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(step >= 3 ? Theme.accent.opacity(0.25) : .clear)
                        Divider().overlay(Theme.stroke)
                        Label(tr("تخصيص", "Customize"), systemImage: "paintbrush")
                            .font(Theme.font(10, .semibold)).foregroundStyle(Theme.sub)
                            .padding(9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(width: 130)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThickMaterial))
                    .environment(\.layoutDirection, .leftToRight)
                    .transition(.scale(scale: 0.6, anchor: .topLeading).combined(with: .opacity))
                }
            }
            Spacer()
        }
    }

    private func searchScreen(_ step: Int) -> some View {
        let typed = String("MNLOVO".prefix(step >= 1 ? min(6, step * 2) : 0))
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.sub)
                Text(typed.isEmpty ? tr("بحث في الأدوات", "Search Widgets") : typed)
                    .font(Theme.font(11, .semibold)).foregroundStyle(typed.isEmpty ? Theme.faint : Theme.text)
                Spacer()
            }
            .padding(.horizontal, 10).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surfaceHi))
            .environment(\.layoutDirection, .leftToRight)

            if step >= 3 {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(LinearGradient(colors: [Color(hex: 0x0B1016), Color(hex: 0x05080B)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 34, height: 34)
                        .overlay(Image(systemName: "eye.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.gradient))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("MNLOVO SAVER").font(Theme.font(11, .heavy)).foregroundStyle(Theme.text)
                        Text(tr("٧ أدوات", "7 widgets")).font(Theme.font(9)).foregroundStyle(Theme.sub)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.faint)
                }
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 12).fill(step >= 4 ? Theme.accent.opacity(0.2) : Theme.surface))
                .environment(\.layoutDirection, .leftToRight)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Spacer()
        }
    }

    private func placeScreen(_ step: Int) -> some View {
        VStack(spacing: 10) {
            // the widget, dropping into the top of the grid
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: "checklist").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.ok)
                    Text(tr("روتين اليوم", "Today")).font(Theme.font(9, .heavy)).foregroundStyle(.white)
                    Spacer()
                    Text("1/3").font(Theme.font(8, .bold)).foregroundStyle(.white.opacity(0.5))
                }
                ForEach(0..<3, id: \.self) { i in
                    HStack(spacing: 5) {
                        Text(["💧", "🏃", "📖"][i]).font(.system(size: 9))
                        IntroBits.bar([46, 38, 42][i], .white.opacity(i == 0 ? 0.3 : 0.7), h: 4)
                        Spacer()
                        Image(systemName: i == 0 ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 9)).foregroundStyle(i == 0 ? Theme.ok : .white.opacity(0.35))
                    }
                }
            }
            .padding(9)
            .frame(height: 74)
            .background(RoundedRectangle(cornerRadius: 14).fill(
                LinearGradient(colors: [Color(hex: 0x08201C), Color(hex: 0x05080B)], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.accent.opacity(step >= 3 ? 0 : 0.6), lineWidth: 1.5))
            .scaleEffect(step >= 3 ? 1 : (step >= 1 ? 1.12 : 0.6))
            .offset(y: step >= 3 ? 0 : (step >= 1 ? 30 : 120))
            .opacity(step >= 1 ? 1 : 0)
            .environment(\.layoutDirection, .leftToRight)

            grid(jiggle: step < 4, gap: true)
            Spacer()
            if step >= 4 {
                Label(tr("انضاف ✓", "Added ✓"), systemImage: "checkmark.circle.fill")
                    .font(Theme.font(11, .bold)).foregroundStyle(Theme.ok)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }
}
