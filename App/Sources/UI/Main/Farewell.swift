import SwiftUI

/// The goodbye, played over everything while the phone is cleaned underneath.
/// • Sign out: the eye smiles and waves, the vault folds into the cloud, «نشوفك على خير».
/// • Delete: everything the account held drifts away and dissolves, the eye closes, «مع السلامة».
struct FarewellOverlay: View {
    @EnvironmentObject var state: AppState
    let farewell: AppState.Farewell
    var onFinish: () -> Void

    @State private var shown = false
    @State private var line = -1
    @State private var mood: EyeMood = .happy
    @State private var wave = false
    @State private var lifted = false        // sign out: the bundle rises into the cloud
    @State private var gone = Set<Int>()     // delete: the items that have dissolved
    @State private var closing = false

    private var isDelete: Bool { if case .delete = farewell { return true } else { return false } }
    private var name: String {
        switch farewell { case .signOut(let n), .delete(let n): return n }
    }
    private var hello: String { name.isEmpty ? "" : " يا \(name)" }

    private var lines: [String] {
        isDelete
            ? [tr("مع السلامة\(hello) 🤍", "Goodbye\(name.isEmpty ? "" : ", \(name)") 🤍"),
               tr("انمسح كل شي، وما بقى منه ولا أثر.", "Everything is gone, without a trace."),
               tr("شكراً إنك وثقت فينا. بابنا مفتوح لك دايماً.", "Thank you for trusting us. Our door is always open.")]
            : [tr("نشوفك على خير\(hello) 👋", "See you soon\(name.isEmpty ? "" : ", \(name)") 👋"),
               tr("بياناتك محفوظة ومشفّرة في السحابة ☁️", "Your data is safe and encrypted in the cloud ☁️"),
               tr("ترجع بأي وقت بالإيميل وكلمة السر، ويرجع كل شي.", "Come back any time with your email and password.")]
    }

    private let items = ["key.horizontal.fill", "photo.fill", "bell.fill", "note.text", "paperplane.fill", "lock.fill"]

    var body: some View {
        ZStack {
            background
            VStack(spacing: 26) {
                Spacer()
                ZStack {
                    if isDelete { dissolvingItems } else { cloudBundle }
                    EyeView(mood: mood, size: 150)
                        .scaleEffect(closing ? 0.85 : 1)
                        .opacity(closing ? 0 : 1)
                    if !isDelete {
                        Text("👋")
                            .font(.system(size: 44))
                            .rotationEffect(.degrees(wave ? 22 : -14), anchor: .bottomTrailing)
                            .offset(x: 92, y: 52)
                            .opacity(line >= 0 && !closing ? 1 : 0)
                    }
                }
                .frame(height: 260)

                VStack(spacing: 12) {
                    ForEach(lines.indices, id: \.self) { i in
                        Text(lines[i])
                            .font(Theme.font(i == 0 ? 26 : 16, i == 0 ? .black : .semibold))
                            .foregroundStyle(i == 0 ? Theme.text : Theme.sub)
                            .multilineTextAlignment(.center)
                            .opacity(line >= i && !closing ? 1 : 0)
                            .offset(y: line >= i ? 0 : 14)
                            .blur(radius: line >= i ? 0 : 6)
                    }
                }
                .padding(.horizontal, 28)

                Spacer()
                Text(Brand.copyright)
                    .font(Theme.font(11, .semibold)).foregroundStyle(Theme.text.opacity(0.25))
                    .padding(.bottom, 30)
                    .opacity(closing ? 0 : 1)
            }
        }
        .opacity(shown ? 1 : 0)
        .ignoresSafeArea()
        .allowsHitTesting(true)
        .task { await play() }
    }

    // MARK: Pieces

    private var background: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x0B1016), Color(hex: 0x05080B)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [(isDelete ? Theme.danger : Theme.accent).opacity(closing ? 0 : 0.18), .clear],
                           center: .init(x: 0.5, y: 0.36), startRadius: 0, endRadius: 340)
        }
        .ignoresSafeArea()
    }

    /// Sign out: a little sealed bundle lifts off the eye and rises into a cloud.
    private var cloudBundle: some View {
        ZStack {
            Image(systemName: "icloud.fill")
                .font(.system(size: 54))
                .foregroundStyle(LinearGradient(colors: [Theme.accent, Theme.accent2], startPoint: .leading, endPoint: .trailing))
                .offset(y: -118)
                .opacity(line >= 1 && !closing ? 1 : 0)
                .scaleEffect(line >= 1 ? 1 : 0.6)
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Theme.accent)
                .offset(y: lifted ? -112 : 20)
                .scaleEffect(lifted ? 0.55 : 1)
                .opacity(lifted ? 0 : (line >= 1 ? 1 : 0))
        }
    }

    /// Delete: everything the account held circles the eye, then each piece dissolves in turn.
    private var dissolvingItems: some View {
        ZStack {
            ForEach(items.indices, id: \.self) { i in
                let angle = Double(i) / Double(items.count) * 2 * .pi - .pi / 2
                let out = gone.contains(i)
                Image(systemName: items[i])
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.text.opacity(0.85))
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Color.white.opacity(0.06)))
                    .overlay(Circle().strokeBorder(Theme.danger.opacity(0.35)))
                    .offset(x: cos(angle) * (out ? 150 : 118), y: sin(angle) * (out ? 150 : 118))
                    .scaleEffect(out ? 1.6 : 1)
                    .blur(radius: out ? 14 : 0)
                    .opacity(out ? 0 : 1)
            }
        }
    }

    // MARK: Timeline

    private func play() async {
        withAnimation(.easeOut(duration: 0.5)) { shown = true }
        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { wave = true }
        if isDelete {
            mood = .sleepy
            await step(0.5) { line = 0 }
            for i in items.indices {
                await step(0.32, anim: .easeIn(duration: 0.6)) { _ = gone.insert(i) }
            }
            await step(0.6) { line = 1 }
            await step(1.4) { line = 2; mood = .love }
            await pause(1.8)
        } else {
            await step(0.4) { line = 0 }
            await step(1.1) { line = 1 }
            await step(0.5, anim: .easeInOut(duration: 1.0)) { lifted = true }
            await step(0.9) { line = 2 }
            await pause(1.6)
        }
        // Stay until the phone has really been cleaned underneath.
        var waited = 0.0
        while state.phase != .welcome && waited < 25 {
            await pause(0.25); waited += 0.25
        }
        await step(0, anim: .easeInOut(duration: 0.6)) { mood = .closed }
        await step(0.5, anim: .easeInOut(duration: 0.7)) { closing = true }
        await pause(0.6)
        withAnimation(.easeInOut(duration: 0.6)) { shown = false }
        await pause(0.6)
        onFinish()
    }

    private func step(_ delay: Double, anim: Animation = .spring(response: 0.6, dampingFraction: 0.8), _ change: () -> Void) async {
        if delay > 0 { await pause(delay) }
        withAnimation(anim) { change() }
    }
}

// MARK: - The sign-out sheet

struct SignOutSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var understood = false
    @State private var busy = false
    @State private var error: String?
    @State private var mood: EyeMood = .idle
    @State private var shakes = 0
    @FocusState private var focus: AYNFieldID?

    private var fileCount: Int { state.files.count }
    private var ready: Bool { !password.isEmpty && (fileCount == 0 || understood) && state.cloudReady }

    var body: some View {
        SheetScaffold(title: tr("تسجيل الخروج", "Sign out")) {
            EyeView(mood: mood, size: 110)
                .modifier(ShakeEffect(shakes: CGFloat(shakes)))

            VStack(alignment: .leading, spacing: 10) {
                point("icloud.and.arrow.up.fill", tr("قبل ما تطلع، بناخذ نسخة احتياطية جديدة من حساباتك وملاحظاتك وتذكيراتك.",
                                                     "Before you go, we take a fresh backup of your accounts, notes and reminders."))
                point("iphone.slash", tr("وبعدين ننظف هالتلفون من بياناتك.", "Then this iPhone is cleaned of your data."))
                point("arrow.uturn.backward.circle.fill", tr("ترجع بأي وقت بالإيميل وكلمة السر، ويرجع كل شي مثل ما كان.",
                                                              "Sign back in any time with your email and password and it all comes back."))
            }
            .glass(14)

            if fileCount > 0 {
                VStack(alignment: .leading, spacing: 10) {
                    Label(tr("عندك \(fileCount) ملف في الخزنة", "You have \(fileCount) files in the vault"), systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.font(15, .heavy)).foregroundStyle(Theme.warn)
                    Text(tr("الصور والفيديو والمستندات ما تنحفظ في السحابة، فبتنمسح من هالتلفون يوم تطلع. إذا تباها، صدّرها من الخزنة أول.",
                            "Photos, videos and documents aren't kept in the cloud, so they'll be removed from this iPhone. Export them from the vault first if you need them."))
                        .font(Theme.font(13)).foregroundStyle(Theme.sub)
                        .fixedSize(horizontal: false, vertical: true)
                    Toggle(isOn: $understood) {
                        Text(tr("فاهم، كمّل", "Understood, continue")).font(Theme.font(14, .bold)).foregroundStyle(Theme.text)
                    }
                    .tint(Theme.warn)
                }
                .glass(14, tint: Theme.warn)
            }

            if !state.cloudReady {
                Label(tr("لازم تكون مسجّل في السحابة عشان ناخذ النسخة قبل ما تطلع.", "You need to be signed in to the cloud so we can back up first."),
                      systemImage: "icloud.slash")
                    .font(Theme.font(13, .semibold)).foregroundStyle(Theme.danger)
            }

            AYNField(title: tr("كلمة السر", "Password"), icon: "key.fill", text: $password, secure: true,
                     contentType: .password, focus: $focus, id: .password) { Task { await go() } }

            if let error {
                Text(error).font(Theme.font(14, .semibold)).foregroundStyle(Theme.danger)
                    .multilineTextAlignment(.center)
            }

            PrimaryButton(title: tr("سجّل خروج", "Sign out"), icon: "rectangle.portrait.and.arrow.right",
                          loading: busy, enabled: ready) {
                Task { await go() }
            }
        }
        .onChange(of: focus) { _, f in withAnimation { mood = f == .password ? .lookUp : .idle } }
    }

    private func point(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(Theme.accent).frame(width: 24)
            Text(text).font(Theme.font(14, .semibold)).foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func go() async {
        guard ready, !busy else { return }
        busy = true
        error = nil
        focus = nil
        withAnimation { mood = .thinking }
        let result = await state.prepareSignOut(password: password)
        busy = false
        switch result {
        case .done:
            let app = state
            dismiss()
            Task {
                try? await Task.sleep(nanoseconds: 400_000_000)   // let the sheet slide away first
                await app.finishSignOut()
            }
        case .wrongPassword:
            password = ""
            error = AppError.wrongPassword.localizedDescription
            withAnimation(.default) { shakes += 1 }
            withAnimation { mood = .angry }
            FX.error()
        case .noBackup:
            error = tr("ما قدرنا ناخذ نسخة احتياطية الحين، فما طلّعناك عشان ما يضيع شي. تأكد من الإنترنت وجرّب مرة ثانية.",
                       "We couldn't back up right now, so you weren't signed out and nothing was lost. Check your connection and try again.")
            withAnimation { mood = .sleepy }
            FX.error()
        }
    }
}
