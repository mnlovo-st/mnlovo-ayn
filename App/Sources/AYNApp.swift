import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FontBook.registerAll()
        UNUserNotificationCenter.current().delegate = self
        ReminderEngine.registerCategories()
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        ReminderEngine.handleAction(response.actionIdentifier, userInfo: info)
        NotificationCenter.default.post(name: .aynRemindersChanged, object: nil)
        completionHandler()
    }
}

extension Notification.Name {
    static let aynRemindersChanged = Notification.Name("saver.reminders.changed")
    static let aynTelegramSent = Notification.Name("saver.telegram.sent")
}

@main
struct AYNApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState()
    @AppStorage(AppLanguage.storageKey) private var lang: String = AppLanguage.systemDefault.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .environment(\.layoutDirection, lang == "ar" ? .rightToLeft : .leftToRight)
                .environment(\.locale, (AppLanguage(rawValue: lang) ?? .ar).locale)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .id(lang)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("sec.allowScreenshots") private var allowShots = true
    @AppStorage("sec.allowRecording") private var allowRecording = true

    var body: some View {
        ZStack {
            AuroraBackground()

            switch state.phase {
            case .intro:
                IntroView { state.finishIntro() }
                    .transition(.opacity)
            case .welcome:
                WelcomeView()
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            case .locked:
                LoginView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            case .unlocked:
                MainTabView()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if state.privacyCover || (state.screenCaptured && !allowRecording) {
                PrivacyCover(recording: state.screenCaptured)
                    .transition(.opacity)
                    .zIndex(50)
            }

            if let busy = state.busy {
                BusyOverlay(text: busy).zIndex(60)
            }

            ToastHost().zIndex(70)

            if let c = state.celebration {
                CelebrationOverlay(celebration: c) { withAnimation { state.celebration = nil } }
                    .id(c.id)
                    .zIndex(80)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: state.privacyCover)
        .onChange(of: scenePhase) { _, newValue in
            state.scenePhaseChanged(newValue)
            if newValue == .active {
                ScreenShield.shared.install()
                LiveActivityManager.sync()
            }
        }
        .onAppear {
            // The window needs a moment on screen before its layer can be moved.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { ScreenShield.shared.install() }
        }
        .onChange(of: allowShots) { _, _ in ScreenShield.shared.apply(captured: state.screenCaptured) }
        .onChange(of: allowRecording) { _, _ in ScreenShield.shared.apply(captured: state.screenCaptured) }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { _ in
            guard state.isUnlocked else { return }
            state.logScreenEvent(.screenshot)
            if UserDefaults.standard.object(forKey: "sec.screenshotAlert") as? Bool ?? true {
                state.show(tr("📸 تم رصد لقطة شاشة. انتبه للمعلومات الحساسة.", "📸 Screenshot detected. Mind your sensitive data."),
                           icon: "camera.viewfinder", style: .warning)
                Haptics.warning()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
            let captured = UIScreen.main.isCaptured
            if captured && !state.screenCaptured && state.isUnlocked { state.logScreenEvent(.recording) }
            state.screenCaptured = captured
            ScreenShield.shared.apply(captured: captured)
        }
        .onReceive(NotificationCenter.default.publisher(for: .aynTelegramSent)) { _ in
            state.show(tr("تم الإرسال ✓", "Sent ✓"), icon: "paperplane.fill")
        }
        .onReceive(NotificationCenter.default.publisher(for: .aynRemindersChanged)) { _ in
            if state.isUnlocked { state.reminders = RemindersStore.load(state.space) }
        }
    }
}

/// What the app switcher shows: a shut eye and nothing else — never your data.
///
/// The first version was a glowing app icon in the middle of coloured blobs, which read as a
/// splash screen rather than a shut door. This one is deliberately quiet: a dark field, the eye
/// shut, and the wordmark small underneath. It looks like something put away on purpose.
struct PrivacyCover: View {
    var recording: Bool

    private var accentLine: Color { recording ? Theme.danger : Theme.accent }

    var body: some View {
        ZStack {
            // 1. the field: near-black, with one soft breath of colour at the very top
            LinearGradient(colors: [Color(hex: 0x0B1016), Color(hex: 0x05080B)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [accentLine.opacity(0.14), .clear], center: .init(x: 0.5, y: 0.34),
                           startRadius: 0, endRadius: 320)

            // 2. engraved hairlines, like the guilloche on a document — texture without noise
            GeometryReader { geo in
                Path { p in
                    let step: CGFloat = 13
                    var x = -geo.size.height
                    while x < geo.size.width + geo.size.height {
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x + geo.size.height, y: geo.size.height))
                        x += step
                    }
                }
                .stroke(Color.white.opacity(0.022), lineWidth: 1)
            }
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                Spacer()

                // 3. the shut eye
                ClosedEye()
                    .stroke(Theme.text.opacity(0.9), style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                    .frame(width: 128, height: 54)
                    .shadow(color: accentLine.opacity(0.35), radius: 14)
                    .frame(height: 70)

                // 4. the wordmark, quiet
                Text(Brand.appName)
                    .font(Theme.font(16, .heavy))
                    .foregroundStyle(Theme.text.opacity(0.72))
                    .tracking(6)
                    .padding(.top, 26)

                // 5. one line of status, and nothing more
                HStack(spacing: 7) {
                    Image(systemName: recording ? "record.circle" : "lock.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text(recording ? tr("الشاشة تُسجّل — المحتوى مخفي", "Screen is recording — content hidden")
                                   : tr("مقفلة", "Locked"))
                        .font(Theme.font(12, .bold))
                }
                .foregroundStyle(recording ? Theme.danger : Theme.sub)
                .padding(.horizontal, 13).frame(height: 30)
                .background(Capsule().fill(Color.white.opacity(0.05)))
                .overlay(Capsule().strokeBorder(recording ? Theme.danger.opacity(0.4) : Color.white.opacity(0.08)))
                .padding(.top, 14)

                Spacer()

                Text(Brand.copyright)
                    .font(Theme.font(11, .semibold))
                    .foregroundStyle(Theme.text.opacity(0.22))
                    .tracking(1)
                    .padding(.bottom, 34)
            }
        }
        .ignoresSafeArea()
    }
}

/// The mascot's eye with the lid down: one closed curve plus three short lashes.
/// Drawn rather than drawn-from-an-asset so it stays crisp at any size and follows the theme colour.
private struct ClosedEye: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        // the lid: a shallow arc, heavier in the middle than a plain line
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.midY),
                       control: CGPoint(x: r.midX, y: r.midY + h * 0.52))
        // three lashes, falling away from the lid
        let lashes: [(CGFloat, CGFloat, CGFloat)] = [(0.26, 0.30, 0.26), (0.5, 0.42, 0.0), (0.74, 0.30, -0.26)]
        for (fx, len, lean) in lashes {
            let x = r.minX + w * fx
            let y = r.midY + h * (0.52 * (1 - pow((fx - 0.5) * 2, 2)))
            p.move(to: CGPoint(x: x, y: y))
            p.addLine(to: CGPoint(x: x + w * 0.06 * lean, y: y + h * len))
        }
        return p
    }
}

struct BusyOverlay: View {
    var text: String
    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 18) {
                EyeView(mood: .thinking, size: 90)
                Text(text).font(Theme.font(16, .semibold)).foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
            }
            .padding(30)
            .background(RoundedRectangle(cornerRadius: 28).fill(.ultraThinMaterial))
            .padding(40)
        }
        .transition(.opacity)
    }
}
