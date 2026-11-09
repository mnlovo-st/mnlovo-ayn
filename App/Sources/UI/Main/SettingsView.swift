import SwiftUI
import AppIntents
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @AppStorage(AppLanguage.storageKey) private var lang: String = AppLanguage.systemDefault.rawValue
    @AppStorage("fx.sound") private var sound = true
    @AppStorage("fx.haptics") private var haptics = true
    @AppStorage("fx.liveActivity") private var liveActivity = true
    @AppStorage("sec.screenshotAlert") private var screenshotAlert = true
    @AppStorage("sec.sectionBiometric") private var sectionBio = false
    @AppStorage("sec.intruder") private var intruder = false

    @State private var sheet: SettingsSheet?
    @State private var confirmErase = false
    @State private var bioOn = false

    enum SettingsSheet: String, Identifiable {
        case password, section, twoFA, recovery, duress, intruders, cloudSetup, backup
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                TabHeader(title: MainTab.settings.title, subtitle: state.profile?.username ?? "") { EmptyView() }

                if let p = state.profile { profileCard(p) }

                group(tr("الحساب", "Account"), "person.crop.circle") {
                    row("key.fill", tr("تغيير كلمة السر", "Change password")) { sheet = .password }
                    divider
                    row("circle.grid.3x3.fill", tr("رمز الأقسام", "Section passcode"), value: state.sectionKind.title) { sheet = .section }
                    divider
                    row("lock.rotation", tr("التحقق بخطوتين (QR)", "Two-factor (QR)")) { sheet = .twoFA }
                    divider
                    row("key.horizontal.fill", tr("مفتاح استرجاع جديد", "New recovery key")) { sheet = .recovery }
                }

                group(tr("الأمان", "Security"), "lock.shield.fill") {
                    toggleRow(Biometrics.icon, tr("\(Biometrics.name) + كلمة السر عند الدخول", "\(Biometrics.name) + password to enter"),
                              sub: bioOn ? nil : tr("بدونه: كلمة السر + رمز التحقق كل مرة", "Without it: password + 2FA code each time"),
                              $bioOn)
                        .onChange(of: bioOn) { _, v in
                            guard v != state.biometricsOn else { return }
                            Task {
                                let ok = await state.setBiometrics(v)
                                if !ok { bioOn = state.biometricsOn }
                            }
                        }
                        .disabled(state.isDecoy || !Biometrics.isAvailable)
                    divider
                    toggleRow("faceid", tr("\(Biometrics.name) بدل رمز الأقسام", "\(Biometrics.name) instead of section passcode"), $sectionBio)
                    divider
                    Menu {
                        ForEach([5, 30, 60, 300, 0], id: \.self) { s in
                            Button(lockLabel(s)) { state.autoLockSeconds = s; Haptics.selection() }
                        }
                    } label: {
                        rowLabel("timer", tr("يقفل إذا طلعت من التطبيق", "Locks after leaving the app"), value: lockLabel(state.autoLockSeconds))
                    }
                    divider
                    toggleRow("camera.metering.spot", tr("تصوير المتطفل (٣ محاولات)", "Intruder photo (3 attempts)"), $intruder)
                        .onChange(of: intruder) { _, v in
                            if v { Task { intruder = await IntruderCam.requestPermission() } }
                        }
                    divider
                    row("eye.trianglebadge.exclamationmark.fill", tr("سجل المتطفلين", "Intruder log"),
                        badge: state.newIntrusions > 0 ? "\(state.newIntrusions)" : nil) { sheet = .intruders }
                    divider
                    toggleRow("camera.viewfinder", tr("تنبيه لقطة الشاشة", "Screenshot alert"), $screenshotAlert)
                    if !state.isDecoy {
                        divider
                        row("theatermasks.fill", tr("كلمة سر الطوارئ", "Duress password"),
                            value: state.hasDuress ? tr("مفعّلة", "On") : tr("مطفأة", "Off")) { sheet = .duress }
                    }
                }

                group(tr("النسخ الاحتياطي", "Backup"), "icloud.fill") {
                    backupStatus
                    divider
                    row("arrow.up.arrow.down.circle.fill", tr("النسخ والاستعادة", "Backup & restore")) { sheet = .backup }
                    if SupabaseConfig.url.isEmpty {
                        divider
                        row("cloud.fill", tr("إعداد السحابة", "Cloud setup"),
                            value: SupabaseClient.shared.isConfigured ? tr("جاهز", "Ready") : tr("غير مُعد", "Not set")) { sheet = .cloudSetup }
                    }
                }

                group(tr("التذكيرات", "Reminders"), "bell.badge.fill") {
                    toggleRow("platter.filled.top.iphone", tr("العد التنازلي في Dynamic Island", "Dynamic Island countdown"), $liveActivity)
                        .onChange(of: liveActivity) { _, _ in LiveActivityManager.sync() }
                    divider
                    row("bell.and.waves.left.and.right.fill", tr("إشعار تجريبي", "Test notification")) { Task { await testNotification() } }
                    divider
                    VStack(alignment: .leading, spacing: 8) {
                        Text(tr("Siri والاختصارات: «Add a reminder in MNLOVO SAVER»", "Siri & Shortcuts: “Add a reminder in MNLOVO SAVER”"))
                            .font(Theme.font(13, .semibold)).foregroundStyle(Theme.sub)
                        ShortcutsLink()
                            .shortcutsLinkStyle(.automaticOutline)
                    }
                    .padding(.vertical, 10)
                }

                group(tr("المظهر والصوت", "Look & sound"), "paintpalette.fill") {
                    Menu {
                        ForEach(AppLanguage.allCases) { l in
                            Button(l.nativeName) { lang = l.rawValue; WidgetBridge.update(); Haptics.selection() }
                        }
                    } label: {
                        rowLabel("globe", tr("اللغة", "Language"), value: (AppLanguage(rawValue: lang) ?? .ar).nativeName)
                    }
                    divider
                    toggleRow("speaker.wave.2.fill", tr("الأصوات", "Sounds"),
                              sub: tr("بس في اللحظات المهمة: الفتح، النجاح، الخطأ", "Only key moments: unlock, success, error"), $sound)
                    divider
                    toggleRow("hand.tap.fill", tr("الاهتزازات", "Haptics"), $haptics)
                }

                group(tr("منطقة الخطر", "Danger zone"), "exclamationmark.triangle.fill") {
                    row("trash.fill", tr("حذف كل شي من الجوال", "Erase everything on this iPhone"), tint: Theme.danger) { confirmErase = true }
                }

                VStack(spacing: 8) {
                    BrandMark(size: 44)
                    Text("\(Brand.appName) · v2.0").font(Theme.font(14, .heavy)).foregroundStyle(Theme.sub)
                    Text(tr("AES-256 · Secure Enclave · مشفّر على جهازك", "AES-256 · Secure Enclave · encrypted on device"))
                        .font(Theme.font(11)).foregroundStyle(Theme.faint)
                    Text(Brand.copyright).font(Theme.font(12, .bold)).foregroundStyle(Theme.faint)
                }
                .padding(.top, 8)
            }
            .padding(.bottom, 20)
        }
        .onAppear { bioOn = state.biometricsOn }
        .sheet(item: $sheet) { s in
            Group {
                switch s {
                case .password: ChangePasswordSheet()
                case .section: SectionPasswordSheet()
                case .twoFA: TwoFAShowSheet()
                case .recovery: RecoveryRegenSheet()
                case .duress: DuressSheet()
                case .intruders: IntruderLogView()
                case .cloudSetup: CloudSetupView()
                case .backup: BackupView()
                }
            }
            .environmentObject(state)
        }
        .confirmationDialog(tr("حذف كل البيانات؟ ما ينفع التراجع.", "Erase all data? This can't be undone."),
                            isPresented: $confirmErase, titleVisibility: .visible) {
            Button(tr("حذف نهائي", "Erase permanently"), role: .destructive) { state.eraseEverything() }
        }
    }

    private func profileCard(_ p: Profile) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.softGradient)
                Text(String(p.username.prefix(1)).uppercased())
                    .font(Theme.font(26, .heavy)).foregroundStyle(Theme.gradient)
            }
            .frame(width: 58, height: 58)
            .overlay(Circle().strokeBorder(Theme.gradient, lineWidth: 1.5))
            VStack(alignment: .leading, spacing: 3) {
                Text(p.username).font(Theme.font(20, .heavy)).foregroundStyle(Theme.text)
                HStack(spacing: 6) {
                    Text(p.email).font(Theme.font(13)).foregroundStyle(Theme.sub).lineLimit(1)
                    if p.emailVerified { Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.ok).font(.system(size: 12)) }
                }
                Text(tr("عضو منذ \(Fmt.date(p.created, time: false))", "Member since \(Fmt.date(p.created, time: false))"))
                    .font(Theme.font(11)).foregroundStyle(Theme.faint)
            }
            Spacer()
        }
        .glass(16)
        .padding(.horizontal, 20)
    }

    private var backupStatus: some View {
        HStack(spacing: 12) {
            Image(systemName: state.cloudReady ? (state.syncError == nil ? "checkmark.icloud.fill" : "exclamationmark.icloud.fill") : "icloud.slash")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(state.cloudReady ? (state.syncError == nil ? Theme.ok : Theme.warn) : Theme.faint)
                .symbolEffect(.pulse, isActive: state.syncing)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.cloudReady ? tr("النسخ التلقائي شغّال", "Auto-backup is on") : tr("السحابة غير مربوطة", "Cloud not connected"))
                    .font(Theme.font(15, .semibold)).foregroundStyle(Theme.text)
                Text(statusLine).font(Theme.font(12)).foregroundStyle(Theme.sub)
            }
            Spacer()
            if state.syncing { ProgressView().tint(Theme.accent) }
        }
        .padding(.vertical, 10)
    }

    private var statusLine: String {
        if state.isDecoy { return tr("آخر مزامنة: قبل لحظات", "Last sync: moments ago") }
        if !state.cloudReady { return tr("اربطها من «النسخ والاستعادة» بكود الإيميل", "Connect it in Backup & restore with an email code") }
        if let e = state.syncError { return e }
        if let d = state.lastBackup { return tr("آخر مزامنة \(Fmt.relative(d)) · بدون الصور والملفات", "Last sync \(Fmt.relative(d)) · photos & files excluded") }
        return tr("بتنسخ أول ما تعدّل شي", "Will sync after your next change")
    }

    private func lockLabel(_ s: Int) -> String {
        switch s {
        case 0: return tr("فوراً", "Immediately")
        case 5: return tr("بعد ٥ ثواني", "After 5 seconds")
        case 30: return tr("بعد ٣٠ ثانية", "After 30 seconds")
        case 60: return tr("بعد دقيقة", "After 1 minute")
        default: return tr("بعد ٥ دقايق", "After 5 minutes")
        }
    }

    private func testNotification() async {
        guard await ReminderEngine.requestPermission() else {
            state.show(tr("الإشعارات مقفلة من إعدادات الآيفون", "Notifications are off in iOS Settings"), icon: "bell.slash.fill", style: .warning)
            return
        }
        let c = UNMutableNotificationContent()
        c.title = Brand.appName
        c.body = tr("هذا شكل التذكير 👀 سويتها؟", "This is how reminders look 👀 Done yet?")
        c.sound = UNNotificationSound(named: UNNotificationSoundName("notify.wav"))
        c.categoryIdentifier = ReminderEngine.category
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "test", content: c, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)))
        state.show(tr("بيوصلك بعد ٣ ثواني", "Arriving in 3 seconds"), icon: "bell.fill")
    }

    // MARK: Building blocks

    private var divider: some View { Divider().overlay(Theme.stroke).padding(.leading, 40) }

    private func group<Content: View>(_ title: String, _ icon: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: title, icon: icon)
            VStack(spacing: 0) { content() }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .glass(0, radius: 22)
        }
        .padding(.horizontal, 20)
    }

    private func rowLabel(_ icon: String, _ title: String, value: String? = nil, badge: String? = nil, tint: Color = Theme.accent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 9).fill(tint.opacity(0.13)))
            Text(title).font(Theme.font(15, .semibold)).foregroundStyle(tint == Theme.danger ? Theme.danger : Theme.text)
            Spacer()
            if let badge {
                Text(badge).font(Theme.font(12, .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(Theme.danger))
            }
            if let value { Text(value).font(Theme.font(13)).foregroundStyle(Theme.sub) }
            Image(systemName: "chevron.forward").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.faint)
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private func row(_ icon: String, _ title: String, value: String? = nil, badge: String? = nil,
                     tint: Color = Theme.accent, action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: { rowLabel(icon, title, value: value, badge: badge, tint: tint) }
            .buttonStyle(.plain)
    }

    private func toggleRow(_ icon: String, _ title: String, sub: String? = nil, _ binding: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 9).fill(Theme.accent.opacity(0.13)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.font(15, .semibold)).foregroundStyle(Theme.text)
                if let sub { Text(sub).font(Theme.font(11)).foregroundStyle(Theme.sub) }
            }
            Spacer()
            Toggle("", isOn: binding).labelsHidden().tint(Theme.accent)
        }
        .padding(.vertical, 8)
        .onChange(of: binding.wrappedValue) { _, _ in Haptics.selection() }
    }
}

// MARK: - Sheets

struct SheetScaffold<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(spacing: 14) {
                    SheetHeader(title: title) { dismiss() }
                    content()
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

struct ChangePasswordSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var new = ""
    @State private var confirm = ""
    @State private var error: String?
    @State private var loading = false
    @FocusState private var focus: AYNFieldID?

    var body: some View {
        SheetScaffold(title: tr("تغيير كلمة السر", "Change password")) {
            AYNField(title: tr("كلمة السر الحالية", "Current password"), icon: "lock.fill", text: $current, secure: true,
                     contentType: .password, focus: $focus, id: .current) { focus = .new }
            PasswordCreator(password: $new, confirm: $confirm, focus: $focus, firstID: .new, secondID: .newConfirm,
                            eyeSize: 120, titleFirst: tr("كلمة السر الجديدة", "New password"))
            if let error { Text(error).font(Theme.font(14, .semibold)).foregroundStyle(Theme.danger) }
            PrimaryButton(title: tr("حفظ", "Save"), icon: "checkmark", loading: loading,
                          enabled: !current.isEmpty && PasswordCreator.isAcceptable(new, confirm)) {
                Task {
                    loading = true
                    defer { loading = false }
                    do {
                        try await state.changePassword(current: current, new: new)
                        state.show(tr("تم تغيير كلمة السر ✓", "Password changed ✓"))
                        dismiss()
                    } catch { self.error = error.localizedDescription; FX.error() }
                }
            }
        }
    }
}

struct SectionPasswordSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var verified = false
    @State private var code = ""
    @State private var shakes = 0
    @FocusState private var focus: AYNFieldID?

    var body: some View {
        SheetScaffold(title: tr("رمز الأقسام", "Section passcode")) {
            if verified || !state.hasSectionPassword {
                PasscodeSetupFlow { newCode, kind in
                    Task {
                        await state.setSectionPassword(newCode, kind: kind)
                        state.show(tr("تم تغيير رمز الأقسام ✓", "Section passcode changed ✓"), icon: "lock.fill")
                        dismiss()
                    }
                }
            } else {
                EyeView(mood: code.isEmpty ? .idle : .lookUp, size: 110)
                Text(tr("اكتب الرمز الحالي", "Enter the current passcode"))
                    .font(Theme.font(20, .heavy)).foregroundStyle(Theme.text)
                PasscodeEntry(kind: state.sectionKind, code: $code, shakes: shakes, focus: $focus) { entered in
                    Task {
                        if await state.checkSectionPassword(entered) {
                            withAnimation(.spring) { verified = true }
                        } else {
                            shakes += 1
                            code = ""
                        }
                    }
                }
            }
        }
    }
}

struct TwoFAShowSheet: View {
    @EnvironmentObject var state: AppState
    @State private var password = ""
    @State private var unlocked = false
    @State private var error: String?
    @FocusState private var focus: AYNFieldID?

    var body: some View {
        SheetScaffold(title: tr("التحقق بخطوتين", "Two-factor")) {
            if unlocked, let t = state.profile?.totp {
                Text(tr("لو غيّرت ايفونك أو حذفت الرمز من «كلمات السر»، أضفه من جديد من هنا.", "If you changed phones or removed the code from Passwords, add it again here."))
                    .font(Theme.font(14)).foregroundStyle(Theme.sub)
                TwoFactorSetupCard(totp: t)
                TOTPBadge(totp: t, big: true)
            } else {
                Text(tr("أكّد كلمة سر الدخول لعرض رمز QR.", "Confirm your main password to show the QR."))
                    .font(Theme.font(14)).foregroundStyle(Theme.sub)
                AYNField(title: tr("كلمة السر", "Password"), icon: "key.fill", text: $password, secure: true, focus: $focus, id: .password)
                if let error { Text(error).foregroundStyle(Theme.danger).font(Theme.font(14, .semibold)) }
                PrimaryButton(title: tr("عرض", "Show"), icon: "qrcode", enabled: !password.isEmpty) {
                    Task {
                        if await state.verifyMainPassword(password) { withAnimation { unlocked = true } }
                        else { error = tr("غلط.", "Wrong."); FX.error() }
                    }
                }
            }
        }
    }
}

struct RecoveryRegenSheet: View {
    @EnvironmentObject var state: AppState
    @State private var password = ""
    @State private var newKey: String?
    @State private var error: String?
    @State private var loading = false
    @FocusState private var focus: AYNFieldID?

    var body: some View {
        SheetScaffold(title: tr("مفتاح استرجاع جديد", "New recovery key")) {
            if let k = newKey {
                Text(tr("المفتاح القديم انلغى. احفظ هذا الحين.", "The old key no longer works. Save this one now."))
                    .font(Theme.font(14, .semibold)).foregroundStyle(Theme.warn)
                RecoveryKeyCard(key: k)
            } else {
                Text(tr("استخدمها إذا ضاع مفتاحك القديم. المفتاح القديم يتوقف فوراً.", "Use this if you lost the old key. The old key stops working immediately."))
                    .font(Theme.font(14)).foregroundStyle(Theme.sub)
                AYNField(title: tr("كلمة سر الدخول", "Main password"), icon: "key.fill", text: $password, secure: true, focus: $focus, id: .password)
                if let error { Text(error).foregroundStyle(Theme.danger).font(Theme.font(14, .semibold)) }
                PrimaryButton(title: tr("إنشاء مفتاح جديد", "Generate new key"), icon: "key.horizontal.fill", loading: loading, enabled: !password.isEmpty) {
                    Task {
                        loading = true
                        defer { loading = false }
                        guard await state.verifyMainPassword(password) else { error = tr("غلط.", "Wrong."); FX.error(); return }
                        newKey = try? await state.regenerateRecoveryKey()
                    }
                }
            }
        }
    }
}

struct DuressSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirm = ""
    @State private var error: String?
    @State private var loading = false
    @FocusState private var focus: AYNFieldID?

    var body: some View {
        SheetScaffold(title: tr("كلمة سر الطوارئ", "Duress password")) {
            VStack(alignment: .leading, spacing: 8) {
                Label(tr("إذا أحد أجبرك تفتح التطبيق", "If someone forces you to open the app"), systemImage: "theatermasks.fill")
                    .font(Theme.font(16, .bold)).foregroundStyle(Theme.text)
                Text(tr("بعد Face ID، اكتب كلمة سر الطوارئ بدل كلمتك الأصلية. يفتح خزنة ثانية فاضية تبيّن طبيعية تماماً (نفس اسمك ورمز التحقق ورمز الأقسام). بياناتك الحقيقية تبقى مخفية.",
                        "After Face ID, type the duress password instead of your real one. It opens a separate, empty vault that looks completely normal (same name, 2FA and section passcode). Your real data stays hidden."))
                    .font(Theme.font(13)).foregroundStyle(Theme.sub)
            }
            .glass(14, tint: Theme.accent2)

            if state.hasDuress {
                Label(tr("مفعّلة ✓", "Enabled ✓"), systemImage: "checkmark.seal.fill").font(Theme.font(16, .bold)).foregroundStyle(Theme.ok)
                SecondaryButton(title: tr("إيقاف وحذف الخزنة الوهمية", "Turn off & delete decoy"), icon: "trash", color: Theme.danger) {
                    state.removeDuress()
                    state.show(tr("تم الإيقاف", "Turned off"))
                }
            }
            PasswordCreator(password: $password, confirm: $confirm, focus: $focus, firstID: .duress, secondID: .duressConfirm,
                            eyeSize: 110, titleFirst: tr("كلمة سر الطوارئ", "Duress password"))
            if let error { Text(error).foregroundStyle(Theme.danger).font(Theme.font(14, .semibold)) }
            PrimaryButton(title: state.hasDuress ? tr("استبدال", "Replace") : tr("تفعيل", "Enable"), icon: "theatermasks.fill",
                          loading: loading, enabled: PasswordCreator.isAcceptable(password, confirm)) {
                Task {
                    loading = true
                    defer { loading = false }
                    do {
                        try await state.setupDuress(password: password)
                        state.show(tr("كلمة سر الطوارئ جاهزة 🎭", "Duress password ready 🎭"))
                        dismiss()
                    } catch { self.error = error.localizedDescription; FX.error() }
                }
            }
        }
    }
}

struct IntruderLogView: View {
    @EnvironmentObject var state: AppState
    @State private var events: [IntruderEvent] = []
    @State private var confirmClear = false
    @State private var viewing: IntruderEvent?

    var body: some View {
        SheetScaffold(title: tr("سجل المتطفلين", "Intruder log")) {
            if events.isEmpty {
                EmptyStateView(mood: .happy, title: tr("ما في أي محاولة", "No attempts"),
                               subtitle: tr("محد حاول يدخل. نام مرتاح 😌", "Nobody tried to get in. Sleep well 😌"))
            } else {
                ForEach(events) { e in
                    Button {
                        if e.photo != nil { Haptics.tap(); viewing = e }
                    } label: {
                        HStack(spacing: 12) {
                            if let d = e.photo, let img = UIImage(data: d) {
                                Image(uiImage: img).resizable().scaledToFill()
                                    .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 14))
                                    .overlay(alignment: .bottomTrailing) {
                                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                                            .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                                            .padding(4).background(Circle().fill(.black.opacity(0.55))).padding(4)
                                    }
                            } else {
                                Image(systemName: e.reason == .screenshot ? "camera.viewfinder" : "exclamationmark.lock.fill")
                                    .font(.system(size: 24)).foregroundStyle(Theme.warn)
                                    .frame(width: 64, height: 64)
                                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.warn.opacity(0.12)))
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(e.title).font(Theme.font(15, .bold)).foregroundStyle(Theme.text)
                                Text(IntruderStamp.exactDate(e.date)).font(Theme.font(12)).foregroundStyle(Theme.sub)
                            }
                            Spacer()
                            if e.photo != nil {
                                Image(systemName: "chevron.forward").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.faint)
                            }
                        }
                        .glass(10)
                    }
                    .buttonStyle(PressScale())
                }
                SecondaryButton(title: tr("مسح السجل", "Clear log"), icon: "trash", color: Theme.danger) { confirmClear = true }
            }
        }
        .onAppear {
            events = state.intruderEvents()
            state.markIntrusionsSeen()
        }
        .confirmationDialog(tr("مسح السجل؟", "Clear log?"), isPresented: $confirmClear) {
            Button(tr("مسح", "Clear"), role: .destructive) { state.clearIntruderLog(); events = [] }
        }
        .fullScreenCover(item: $viewing) { e in IntruderPhotoViewer(event: e).environmentObject(state) }
    }
}

/// Adds a branded caption band (app name + exact date/time) under an intruder photo.
enum IntruderStamp {
    static func exactDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = AppLanguage.current.locale
        f.dateFormat = AppLanguage.current == .ar ? "EEEE d MMMM yyyy · h:mm:ss a" : "EEEE, d MMMM yyyy · h:mm:ss a"
        return f.string(from: d)
    }

    static func stamped(_ img: UIImage, event: IntruderEvent) -> UIImage {
        let w = img.size.width
        let band = max(90, w * 0.2)
        let size = CGSize(width: w, height: img.size.height + band)
        let format = UIGraphicsImageRendererFormat()
        format.scale = img.scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            img.draw(in: CGRect(origin: .zero, size: img.size))
            let bandRect = CGRect(x: 0, y: img.size.height, width: w, height: band)
            UIColor(red: 0.024, green: 0.027, blue: 0.047, alpha: 1).setFill()
            ctx.fill(bandRect)
            let colors = [UIColor(red: 0.22, green: 0.9, blue: 0.78, alpha: 1).cgColor,
                          UIColor(red: 0.48, green: 0.42, blue: 1, alpha: 1).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.cgContext.saveGState()
                ctx.cgContext.clip(to: CGRect(x: 0, y: img.size.height, width: w, height: max(3, band * 0.04)))
                ctx.cgContext.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: w, y: 0), options: [])
                ctx.cgContext.restoreGState()
            }
            let titleFont = UIFont(name: FontBook.name(for: .heavy) ?? "", size: band * 0.24) ?? .boldSystemFont(ofSize: band * 0.24)
            let subFont = UIFont(name: FontBook.name(for: .medium) ?? "", size: band * 0.15) ?? .systemFont(ofSize: band * 0.15)
            let para = NSMutableParagraphStyle()
            para.alignment = .center
            let title = NSAttributedString(string: Brand.appName, attributes: [
                .font: titleFont, .foregroundColor: UIColor(red: 0.22, green: 0.9, blue: 0.78, alpha: 1),
                .kern: band * 0.02, .paragraphStyle: para])
            let sub = NSAttributedString(string: "\(event.title) · \(exactDate(event.date))", attributes: [
                .font: subFont, .foregroundColor: UIColor(white: 0.85, alpha: 1), .paragraphStyle: para])
            title.draw(in: CGRect(x: 8, y: img.size.height + band * 0.18, width: w - 16, height: band * 0.36))
            sub.draw(in: CGRect(x: 8, y: img.size.height + band * 0.56, width: w - 16, height: band * 0.36))
        }
    }
}

struct IntruderPhotoViewer: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    var event: IntruderEvent
    @State private var scale: CGFloat = 1
    @State private var shareURL: URL?

    private var image: UIImage? { event.photo.flatMap { UIImage(data: $0) } }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    CircleIconButton(icon: "xmark", size: 40) { dismiss() }
                    Spacer()
                    Text(event.title).font(Theme.font(16, .bold)).foregroundStyle(.white)
                    Spacer()
                    Color.clear.frame(width: 40, height: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer(minLength: 10)
                if let img = image {
                    VStack(spacing: 0) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(scale)
                            .gesture(MagnifyGesture().onChanged { v in scale = max(1, min(4, v.magnification)) }
                                .onEnded { _ in withAnimation(.spring) { scale = 1 } })
                        VStack(spacing: 4) {
                            Rectangle().fill(Theme.gradient).frame(height: 3)
                            Text(Brand.appName).font(Theme.font(20, .heavy)).foregroundStyle(Theme.accent).tracking(1.5)
                                .padding(.top, 8)
                            Text(IntruderStamp.exactDate(event.date))
                                .font(Theme.font(14, .medium)).foregroundStyle(.white.opacity(0.85))
                                .padding(.bottom, 12)
                        }
                        .frame(maxWidth: .infinity)
                        .background(Theme.bg)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal, 16)
                }
                Spacer(minLength: 10)

                HStack(spacing: 12) {
                    PrimaryButton(title: tr("حفظ في الصور", "Save to Photos"), icon: "square.and.arrow.down") { saveToPhotos() }
                    CircleIconButton(icon: "square.and.arrow.up", size: 56, tint: Theme.accent) { share() }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
        .sheet(isPresented: Binding(get: { shareURL != nil }, set: { if !$0 { cleanup() } })) {
            if let shareURL { ShareSheet(items: [shareURL]) }
        }
    }

    private func saveToPhotos() {
        guard let img = image else { return }
        UIImageWriteToSavedPhotosAlbum(IntruderStamp.stamped(img, event: event), nil, nil, nil)
        Haptics.success()
        state.show(tr("انحفظت الصورة في الاستوديو ✓", "Saved to Photos ✓"), icon: "photo.fill")
    }

    private func share() {
        guard let img = image, let data = IntruderStamp.stamped(img, event: event).jpegData(compressionQuality: 0.92) else { return }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MNLOVO-SAVER-intruder-\(f.string(from: event.date)).jpg")
        try? data.write(to: url, options: .atomic)
        shareURL = url
    }

    private func cleanup() {
        if let u = shareURL { try? FileManager.default.removeItem(at: u) }
        shareURL = nil
    }
}

struct CloudSetupView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var url = SupabaseClient.shared.baseURL
    @State private var key = SupabaseClient.shared.anon
    @State private var testing = false
    @State private var result: Bool?
    @FocusState private var focus: AYNFieldID?

    var body: some View {
        SheetScaffold(title: tr("إعداد Supabase (مجاني)", "Supabase setup (free)")) {
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("١. أنشئ مشروع مجاني في supabase.com", "1. Create a free project at supabase.com"))
                Text(tr("٢. Project Settings ← API Keys: انسخ الرابط والـ Publishable key", "2. Project Settings → API Keys: copy the URL and the Publishable key"))
                Text(tr("٣. شغّل ملف setup.sql (موجود مع المشروع) في SQL Editor", "3. Run setup.sql (included with the project) in the SQL Editor"))
                Text(tr("التفاصيل الكاملة في دليل الإعداد العربي.", "Full details are in the setup guide."))
                    .foregroundStyle(Theme.faint)
            }
            .font(Theme.font(13, .medium)).foregroundStyle(Theme.sub)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(14)

            AYNField(title: "https://xxxx.supabase.co", icon: "link", text: $url, keyboard: .URL, focus: $focus, id: .sbURL)
                .environment(\.layoutDirection, .leftToRight)
            AYNField(title: "Publishable key (sb_publishable_…) / anon key", icon: "key.fill", text: $key, focus: $focus, id: .sbKey)
                .environment(\.layoutDirection, .leftToRight)
            if let result {
                Label(result ? tr("الاتصال شغّال ✓", "Connected ✓") : tr("ما قدرت أتصل. تأكد من الرابط والمفتاح.", "Couldn't connect. Check the URL and key."),
                      systemImage: result ? "checkmark.seal.fill" : "xmark.octagon.fill")
                    .font(Theme.font(14, .semibold)).foregroundStyle(result ? Theme.ok : Theme.danger)
            }
            PrimaryButton(title: tr("حفظ واختبار", "Save & test"), icon: "bolt.horizontal.fill", loading: testing,
                          enabled: url.hasPrefix("https://") && key.count > 20) {
                Task {
                    testing = true
                    SupabaseClient.shared.baseURL = url
                    SupabaseClient.shared.anon = key
                    result = await SupabaseClient.shared.testConnection()
                    testing = false
                    if result == true { Haptics.success() } else { FX.error() }
                }
            }
        }
    }
}

struct BackupView: View {
    @EnvironmentObject var state: AppState
    @State private var code = ""
    @State private var codeSent = false
    @State private var loading = false
    @State private var error: String?
    @State private var exportURL: URL?
    @State private var showRestore = false

    private let sb = SupabaseClient.shared

    var body: some View {
        SheetScaffold(title: tr("النسخ الاحتياطي", "Backup")) {
            VStack(alignment: .leading, spacing: 8) {
                Label(tr("تلقائي: الحسابات والملاحظات والتذكيرات والإعدادات تنحفظ في السحابة بعد كل تعديل.",
                         "Automatic: accounts, notes, reminders and settings sync after every change."),
                      systemImage: "arrow.triangle.2.circlepath.icloud.fill")
                Label(tr("مشفّرة على جوالك بكلمة السر قبل ما تطلع. السيرفر ما يقدر يقرأها.",
                         "Encrypted on your phone with your password first. The server can't read it."),
                      systemImage: "lock.shield.fill")
                Label(tr("الصور والفيديو والملفات ما تنرفع — احفظها بالنسخة الكاملة تحت.",
                         "Photos, videos and files aren't uploaded — use the full backup below for them."),
                      systemImage: "photo.on.rectangle.angled")
            }
            .font(Theme.font(13, .medium)).foregroundStyle(Theme.sub)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(14)

            SectionTitle(text: tr("السحابة", "Cloud"), icon: "icloud.fill")
            if !sb.isConfigured {
                Text(tr("السحابة غير مُعدّة بعد.", "The cloud isn't set up yet.")).font(Theme.font(14)).foregroundStyle(Theme.warn)
            } else if sb.session == nil {
                Text(tr("مرة وحدة بس: بنرسل كود إلى \(state.profile?.email ?? "")", "One time only: we'll send a code to \(state.profile?.email ?? "")"))
                    .font(Theme.font(14)).foregroundStyle(Theme.sub)
                if !codeSent {
                    PrimaryButton(title: tr("اربط السحابة", "Connect cloud"), icon: "envelope.fill", loading: loading) {
                        Task { await sendCode() }
                    }
                } else {
                    CodeField(code: $code, length: 8)
                    PrimaryButton(title: tr("تحقق واربط", "Verify & connect"), icon: "checkmark", loading: loading, enabled: code.count >= 6) {
                        Task { await verify() }
                    }
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.icloud.fill").foregroundStyle(Theme.ok)
                    Text(state.lastBackup.map { tr("آخر مزامنة \(Fmt.relative($0))", "Last sync \(Fmt.relative($0))") } ?? tr("مربوطة ✓", "Connected ✓"))
                        .font(Theme.font(14, .semibold)).foregroundStyle(Theme.text)
                    Spacer()
                }
                SecondaryButton(title: tr("زامن الحين", "Sync now"), icon: "arrow.triangle.2.circlepath", color: Theme.accent) {
                    Task {
                        loading = true
                        if await state.backupNow() { state.show(tr("تمت المزامنة ✓", "Synced ✓"), icon: "icloud.fill") }
                        loading = false
                    }
                }
            }

            SectionTitle(text: tr("نسخة كاملة كملف (مع الصور والفيديو)", "Full file backup (with photos & videos)"), icon: "doc.zipper")
            SecondaryButton(title: tr("صدّر نسخة كاملة", "Export full backup"), icon: "square.and.arrow.up", color: Theme.accent) {
                Task { await exportFile() }
            }
            Text(tr("احفظه في iCloud Drive أو أي مكان. ينفتح بكلمة السر أو مفتاح الاسترجاع.", "Save it to iCloud Drive or anywhere. Opens with your password or recovery key."))
                .font(Theme.font(12)).foregroundStyle(Theme.faint)

            SecondaryButton(title: tr("استعادة نسخة", "Restore a backup"), icon: "arrow.counterclockwise") { showRestore = true }

            if let error { Text(error).font(Theme.font(14, .semibold)).foregroundStyle(Theme.danger) }
        }
        .sheet(isPresented: Binding(get: { exportURL != nil }, set: { if !$0 { cleanupExport() } })) {
            if let exportURL { ShareSheet(items: [exportURL]) }
        }
        .sheet(isPresented: $showRestore) { RestoreView().environmentObject(state) }
    }

    private func sendCode() async {
        guard let email = state.profile?.email else { return }
        loading = true
        defer { loading = false }
        do { try await sb.sendEmailCode(to: email); withAnimation { codeSent = true } }
        catch { self.error = error.localizedDescription }
    }

    private func verify() async {
        guard let email = state.profile?.email else { return }
        loading = true
        defer { loading = false }
        do {
            try await sb.verifyEmailCode(email: email, code: code)
            if var p = state.profile, !p.emailVerified { p.emailVerified = true; state.profile = p; state.saveProfile() }
            Haptics.success()
            error = nil
            state.objectWillChange.send()
            await state.backupNow()
        } catch { self.error = error.localizedDescription; FX.error() }
    }

    private func exportFile() async {
        state.busy = tr("نجهّز النسخة الكاملة…", "Preparing full backup…")
        defer { state.busy = nil }
        do {
            let data = try await state.makeBackup(includeFiles: true)
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("MNLOVO-SAVER-\(f.string(from: Date())).saver")
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            exportURL = url
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func cleanupExport() {
        if let u = exportURL { try? FileManager.default.removeItem(at: u) }
        exportURL = nil
    }
}
