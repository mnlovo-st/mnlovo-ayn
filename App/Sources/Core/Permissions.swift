import SwiftUI
import AVFoundation
import LocalAuthentication
import UserNotifications

/// The three things the app can't do its job without:
///   • notifications — reminders, renewals, "are you okay?"
///   • the camera — the intruder photo from the second wrong attempt
///   • Face ID — getting in without typing the password every time
///
/// Photos and Calendar are left out on purpose: they're asked for only when someone actually moves a
/// photo or adds a reminder to the calendar, and the app works fully without them.
@MainActor
final class Permissions: ObservableObject {
    static let shared = Permissions()

    enum Kind: String, CaseIterable, Identifiable {
        case notifications, camera, faceID
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .notifications: return "bell.badge.fill"
            case .camera: return "camera.fill"
            case .faceID: return "faceid"
            }
        }
        var title: String {
            switch self {
            case .notifications: return tr("الإشعارات", "Notifications")
            case .camera: return tr("الكاميرا", "Camera")
            case .faceID: return Biometrics.name
            }
        }
        var why: String {
            switch self {
            case .notifications: return tr("عشان توصلك التذكيرات والاشتراكات ورسالة «إنت بخير؟».",
                                            "So reminders, renewals and “Are you okay?” reach you.")
            case .camera: return tr("عشان نصوّر أي أحد يغلط في كلمة السر من ثاني محاولة.",
                                     "So anyone who gets the password wrong twice is photographed.")
            case .faceID: return tr("عشان تدخل بوجهك بدل ما تكتب كلمة السر كل مرة.",
                                     "So you get in with your face instead of typing the password.")
            }
        }
    }

    enum Status { case granted, notAsked, denied, unavailable }

    @Published private(set) var status: [Kind: Status] = [:]
    @Published private(set) var checked = false

    /// Unavailable counts as fine: a phone without Face ID can't be asked to allow it.
    var allGranted: Bool {
        checked && Kind.allCases.allSatisfy { status[$0] == .granted || status[$0] == .unavailable }
    }

    private let bioAskedKey = "perm.faceid.asked"

    func refresh() async {
        var s: [Kind: Status] = [:]

        let n = await UNUserNotificationCenter.current().notificationSettings()
        switch n.authorizationStatus {
        case .authorized, .provisional, .ephemeral: s[.notifications] = .granted
        case .notDetermined: s[.notifications] = .notAsked
        default: s[.notifications] = .denied
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: s[.camera] = .granted
        case .notDetermined: s[.camera] = .notAsked
        default: s[.camera] = .denied
        }

        s[.faceID] = faceIDStatus()
        status = s
        checked = true
    }

    /// Face ID has no "not asked yet" state to read, so the app remembers whether it has asked.
    private func faceIDStatus() -> Status {
        let ctx = LAContext()
        var err: NSError?
        if ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) {
            // Someone already signing in with their face has obviously allowed it.
            let d = UserDefaults.standard
            return d.bool(forKey: bioAskedKey) || d.bool(forKey: "sec.biometric") ? .granted : .notAsked
        }
        // Not available while the phone has the hardware means the person said no to this app.
        if (err as? LAError)?.code == .biometryNotAvailable, ctx.biometryType != .none { return .denied }
        return .unavailable
    }

    func request(_ k: Kind) async {
        switch k {
        case .notifications:
            if status[k] == .denied { openSettings() } else { _ = await ReminderEngine.requestPermission() }
        case .camera:
            if status[k] == .denied { openSettings() }
            else if await IntruderCam.requestPermission() { IntruderCam.enabled = true }
        case .faceID:
            if status[k] == .denied { openSettings(); break }
            let ctx = LAContext()
            ctx.localizedCancelTitle = tr("بعدين", "Later")
            do {
                _ = try await ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                                 localizedReason: tr("اسمح لـ MNLOVO SAVER يستخدم وجهك للدخول",
                                                                     "Allow MNLOVO SAVER to use your face to sign in"))
                UserDefaults.standard.set(true, forKey: bioAskedKey)
            } catch let e as LAError where e.code != .biometryNotAvailable {
                // The system question was answered with "allow"; the scan itself just didn't finish.
                UserDefaults.standard.set(true, forKey: bioAskedKey)
            } catch {}
        }
        await refresh()
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}

/// Shown over the app until all three are allowed — after a fresh install and sign-in as much as
/// after creating an account. Each row asks for one thing and says why in a sentence.
struct PermissionsGate: View {
    @ObservedObject var perms: Permissions
    @State private var asking: Permissions.Kind?
    @State private var appear = false

    private var grantedCount: Int {
        Permissions.Kind.allCases.filter { perms.status[$0] == .granted || perms.status[$0] == .unavailable }.count
    }

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(spacing: 18) {
                    EyeView(mood: .happy, size: 110, sounds: false)
                        .padding(.top, 30)
                    VStack(spacing: 8) {
                        Text(tr("خطوة أخيرة", "One last step")).font(Theme.font(26, .heavy)).foregroundStyle(Theme.text)
                        Text(tr("التطبيق يحتاج هالأذونات الثلاثة عشان يحميك ويذكّرك. ما نستخدمها لأي شي ثاني.",
                                "The app needs these three to protect you and remind you. They're used for nothing else."))
                            .font(Theme.font(14)).foregroundStyle(Theme.sub)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 10)

                    VStack(spacing: 10) {
                        ForEach(Array(Permissions.Kind.allCases.enumerated()), id: \.element) { i, k in
                            row(k)
                                .opacity(appear ? 1 : 0)
                                .offset(y: appear ? 0 : 16)
                                .animation(.spring(response: 0.5, dampingFraction: 0.85).delay(0.08 * Double(i)), value: appear)
                        }
                    }

                    // progress dots
                    HStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { i in
                            Capsule().fill(i < grantedCount ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.surfaceHi))
                                .frame(width: i < grantedCount ? 22 : 8, height: 8)
                        }
                    }
                    .animation(.spring(response: 0.4), value: grantedCount)
                    .padding(.top, 4)

                    Text(tr("رفضت شي بالغلط؟ زر «افتح الإعدادات» يوديك له مباشرة.",
                            "Said no by mistake? “Open Settings” takes you straight there."))
                        .font(Theme.font(12)).foregroundStyle(Theme.faint)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
            }
        }
        .onAppear { appear = true }
    }

    private func row(_ k: Permissions.Kind) -> some View {
        let st = perms.status[k] ?? .notAsked
        let done = st == .granted || st == .unavailable
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(done ? Theme.ok.opacity(0.16) : Theme.accent.opacity(0.14))
                Image(systemName: done ? "checkmark" : k.icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(done ? Theme.ok : Theme.accent)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(k.title).font(Theme.font(15, .bold)).foregroundStyle(Theme.text)
                Text(k.why).font(Theme.font(12)).foregroundStyle(Theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)

            if done {
                Text(st == .unavailable ? tr("ما يحتاج", "Not needed") : tr("مسموح", "Allowed"))
                    .font(Theme.font(12, .bold)).foregroundStyle(Theme.ok)
            } else {
                Button {
                    Haptics.tap()
                    asking = k
                    Task { await perms.request(k); asking = nil }
                } label: {
                    Group {
                        if asking == k { ProgressView().tint(Theme.bg) }
                        else { Text(st == .denied ? tr("افتح الإعدادات", "Open Settings") : tr("اسمح", "Allow")) }
                    }
                    .font(Theme.font(13, .heavy))
                    .foregroundStyle(Theme.bg)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(Capsule().fill(st == .denied ? AnyShapeStyle(Theme.warn) : AnyShapeStyle(Theme.gradient)))
                }
                .buttonStyle(PressScale())
                .disabled(asking != nil)
            }
        }
        .padding(12)
        .glass(0, radius: 18, tint: done ? Theme.ok : nil)
        .animation(.spring(response: 0.4), value: done)
    }
}
