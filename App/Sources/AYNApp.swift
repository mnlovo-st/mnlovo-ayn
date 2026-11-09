import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
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
    static let aynRemindersChanged = Notification.Name("ayn.reminders.changed")
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

struct PrivacyCover: View {
    var recording: Bool
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Theme.bg.opacity(0.85)
            VStack(spacing: 16) {
                EyeView(mood: .closed, size: 110)
                Text(recording ? tr("المحتوى مخفي أثناء تسجيل الشاشة", "Hidden during screen recording") : "MNLOVO AYN")
                    .font(Theme.font(recording ? 16 : 22, .bold))
                    .foregroundStyle(Theme.sub)
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
