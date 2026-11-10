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

            if state.privacyCover || state.screenCaptured {
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
        .onChange(of: scenePhase) { _, newValue in state.scenePhaseChanged(newValue) }
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
        }
        .onReceive(NotificationCenter.default.publisher(for: .aynRemindersChanged)) { _ in
            if state.isUnlocked { state.reminders = RemindersStore.load(state.space) }
        }
    }
}

/// What the app switcher shows: the brand, locked and protected — never your data.
struct PrivacyCover: View {
    var recording: Bool
    var body: some View {
        ZStack {
            Theme.bg
            RadialGradient(colors: [Theme.accent2.opacity(0.55), .clear], center: .init(x: 0.15, y: 0.1), startRadius: 0, endRadius: 420)
            RadialGradient(colors: [Theme.accent.opacity(0.45), .clear], center: .init(x: 0.9, y: 0.85), startRadius: 0, endRadius: 460)
            RadialGradient(colors: [Theme.accent3.opacity(0.30), .clear], center: .init(x: 0.85, y: 0.15), startRadius: 0, endRadius: 300)
            Rectangle().fill(.ultraThinMaterial).opacity(0.35)

            VStack(spacing: 22) {
                Spacer()
                ZStack(alignment: .bottomTrailing) {
                    ZStack {
                        Circle().fill(Theme.accent.opacity(0.25)).frame(width: 230, height: 230).blur(radius: 40)
                        Circle().strokeBorder(Theme.brandGradient, lineWidth: 1.5).frame(width: 196, height: 196).opacity(0.7)
                        Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 1).frame(width: 226, height: 226)
                        Image("BrandIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 150, height: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 36, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                            .shadow(color: Theme.accent.opacity(0.6), radius: 26)
                    }
                    Image(systemName: recording ? "record.circle" : "lock.fill")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(Theme.bg)
                        .frame(width: 50, height: 50)
                        .background(Circle().fill(recording ? AnyShapeStyle(Theme.danger) : AnyShapeStyle(Theme.gradient)))
                        .overlay(Circle().strokeBorder(Theme.bg, lineWidth: 4))
                        .offset(x: -18, y: -14)
                }
                VStack(spacing: 10) {
                    Text(Brand.appName)
                        .font(Theme.font(34, .black))
                        .foregroundStyle(Theme.brandGradient)
                        .tracking(1.5)
                    HStack(spacing: 8) {
                        Image(systemName: recording ? "eye.slash.fill" : "checkmark.shield.fill")
                        Text(recording ? tr("المحتوى مخفي أثناء تسجيل الشاشة", "Hidden during screen recording")
                                       : tr("مقفلة ومحمية", "Locked & protected"))
                    }
                    .font(Theme.font(15, .bold))
                    .foregroundStyle(Theme.text.opacity(0.9))
                    .padding(.horizontal, 16).frame(height: 38)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.14)))
                }
                Spacer()
                Text("AES-256 · Secure Enclave")
                    .font(Theme.font(12, .semibold)).foregroundStyle(Theme.faint).tracking(1)
                Text(Brand.copyright).font(Theme.font(12, .bold)).foregroundStyle(Theme.faint)
                    .padding(.bottom, 30)
            }
        }
        .ignoresSafeArea()
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
