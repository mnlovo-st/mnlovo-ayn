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
            VStack(spacing: 16) {
                TabHeader(title: MainTab.settings.title, subtitle: state.profile?.username ?? "") { EmptyView() }

                if let p = state.profile {
                    HStack(spacing: 14) {
                        EyeView(mood: .idle, size: 64)
                            .frame(width: 70, height: 60)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(p.username).font(Theme.font(20, .heavy)).foregroundStyle(Theme.text)
                            HStack(spacing: 6) {
                                Text(p.email).font(Theme.font(13)).foregroundStyle(Theme.sub)
                                if p.emailVerified { Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.ok).font(.system(size: 12)) }
                            }
                            Text(tr("عضو منذ \(Fmt.date(p.created, time: false))", "Member since \(Fmt.date(p.created, time: false))"))
                                .font(Theme.font(11)).foregroundStyle(Theme.faint)
                        }
                        Spacer()
                    }
                    .glass(14)
                    .padding(.horizontal, 20)
                }

                group(tr("الحساب", "Account"), "person.crop.circle") {
                    row("key.fill", tr("تغيير كلمة السر", "Change password")) { sheet = .password }
                    row("lock.square.stack.fill", tr("كلمة سر الأقسام", "Section password")) { sheet = .section }
                    row("lock.rotation", tr("التحقق بخطوتين (QR)", "Two-factor (QR)")) { sheet = .twoFA }
                    row("key.horizontal.fill", tr("مفتاح استرجاع جديد", "New recovery key")) { sheet = .recovery }
                }

                group(tr("الأمان", "Security"), "lock.shield.fill") {
                    toggleRow(Biometrics.icon, tr("الدخول بـ \(Biometrics.name)", "Unlock with \(Biometrics.name)"), $bioOn)
                        .onChange(of: bioOn) { _, v in
                            guard v != state.biometricsOn else { return }
                            Task {
                                let ok = await state.setBiometrics(v)
                                if !ok { bioOn = state.biometricsOn }
                            }
                        }
                        .disabled(state.isDecoy || !Biometrics.isAvailable)
                    toggleRow("faceid", tr("\(Biometrics.name) للأقسام بدل كلمة السر", "\(Biometrics.name) for sections"), $sectionBio)
                    Menu {
                        ForEach([0, 30, 60, 300], id: \.self) { s in
                            Button(lockLabel(s)) { state.autoLockSeconds = s; FX.toggle() }
                        }
                    } label: {
                        rowLabel("timer", tr("القفل التلقائي", "Auto-lock"), value: lockLabel(state.autoLockSeconds))
                    }
                    toggleRow("camera.metering.spot", tr("تصوير المتطفل (٣ محاولات)", "Intruder photo (3 attempts)"), $intruder)
                        .onChange(of: intruder) { _, v in
                            if v { Task { intruder = await IntruderCam.requestPermission() } }
                        }
                    row("eye.trianglebadge.exclamationmark.fill", tr("سجل المتطفلين", "Intruder log"),
                        badge: state.newIntrusions > 0 ? "\(state.newIntrusions)" : nil) { sheet = .intruders }
                    toggleRow("camera.viewfinder", tr("تنبيه لقطة الشاشة", "Screenshot alert"), $screenshotAlert)
                    if !state.isDecoy {
                        row("theatermasks.fill", tr("كلمة سر الطوارئ", "Duress password"),
                            value: state.hasDuress ? tr("مفعّلة", "On") : tr("مطفأة", "Off")) { sheet = .duress }
                    }
                }

                group(tr("الإشعارات والتذكيرات", "Notifications"), "bell.badge.fill") {
                    toggleRow("platter.filled.top.iphone", tr("العد التنازلي في Dynamic Island", "Dynamic Island countdown"), $liveActivity)
                        .onChange(of: liveActivity) { _, _ in LiveActivityManager.sync() }
                    row("bell.and.waves.left.and.right.fill", tr("إشعار تجريبي", "Test notification")) { Task { await testNotification() } }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(tr("Siri والاختصارات: «Add a reminder in AYN»", "Siri & Shortcuts: “Add a reminder in AYN”"))
                            .font(Theme.font(13, .semibold)).foregroundStyle(Theme.sub)
                        ShortcutsLink()
                            .shortcutsLinkStyle(.automaticOutline)
                    }
                    .padding(.vertical, 8)
                }

                group(tr("المظهر والصوت", "Look & sound"), "paintpalette.fill") {
                    Menu {
                        ForEach(AppLanguage.allCases) { l in
                            Button(l.nativeName) { lang = l.rawValue; WidgetBridge.update(); FX.toggle() }
                        }
                    } label: {
                        rowLabel("globe", tr("اللغة", "Language"), value: (AppLanguage(rawValue: lang) ?? .ar).nativeName)
                    }
                    toggleRow("speaker.wave.2.fill", tr("الأصوات", "Sounds"), $sound)
                    toggleRow("hand.tap.fill", tr("الاهتزازات", "Haptics"), $haptics)
                }

                group(tr("النسخ الاحتياطي", "Backup"), "externaldrive.fill.badge.icloud") {
                    row("cloud.fill", tr("إعداد Supabase", "Supabase setup"),
                        value: SupabaseClient.shared.isConfigured ? tr("جاهز", "Ready") : tr("غير مُعد", "Not set")) { sheet = .cloudSetup }
                    row("arrow.up.arrow.down.circle.fill", tr("النسخ والاستعادة", "Backup & restore"),
                        value: state.lastBackup.map { Fmt.relative($0) } ?? tr("ما في", "None")) { sheet = .backup }
                }

                group(tr("منطقة الخطر", "Danger zone"), "exclamationmark.triangle.fill") {
                    row("trash.fill", tr("حذف كل شي من الجوال", "Erase everything on this iPhone"), tint: Theme.danger) { confirmErase = true }
                }

                VStack(spacing: 4) {
                    Text("MNLOVO AYN · v1.0").font(Theme.font(13, .bold)).foregroundStyle(Theme.sub)
                    Text(tr("صُنع بواسطة MNLOVO · AES-256 · Secure Enclave", "Made by MNLOVO · AES-256 · Secure Enclave"))
                        .font(Theme.font(11)).foregroundStyle(Theme.faint)
                }
                .padding(.top, 6)
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

    private func lockLabel(_ s: Int) -> String {
        switch s {
        case 0: return tr("فوراً", "Immediately")
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
        c.title = "MNLOVO AYN"
        c.body = tr("هذا شكل التذكير 👀 سويتها؟", "This is how reminders look 👀 Done yet?")
        c.sound = UNNotificationSound(named: UNNotificationSoundName("notify.wav"))
        c.categoryIdentifier = ReminderEngine.category
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "test", content: c, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)))
        state.show(tr("بيوصلك بعد ٣ ثواني", "Arriving in 3 seconds"), icon: "bell.fill")
    }

    // MARK: Building blocks

    private func group<Content: View>(_ title: String, _ icon: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: title, icon: icon)
            VStack(spacing: 0) { content() }
                .glass(14)
        }
        .padding(.horizontal, 20)
    }

    private func rowLabel(_ icon: String, _ title: String, value: String? = nil, badge: String? = nil, tint: Color = Theme.accent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(tint).frame(width: 28)
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
        Button { FX.tap(); action() } label: { rowLabel(icon, title, value: value, badge: badge, tint: tint) }
            .buttonStyle(.plain)
    }

    private func toggleRow(_ icon: String, _ title: String, _ binding: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.accent).frame(width: 28)
            Text(title).font(Theme.font(15, .semibold)).foregroundStyle(Theme.text)
            Spacer()
            Toggle("", isOn: binding).labelsHidden().tint(Theme.accent)
        }
        .padding(.vertical, 6)
        .onChange(of: binding.wrappedValue) { _, _ in FX.toggle() }
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
    @State private var current = ""
    @State private var new = ""
    @State private var confirm = ""
    @State private var error: String?
    @FocusState private var focus: AYNFieldID?

    var body: some View {
        SheetScaffold(title: tr("كلمة سر الأقسام", "Section password")) {
            Text(tr("تُطلب عند فتح «الحسابات» و«الخزنة»، ومع العناصر السرية جداً.", "Asked when opening Accounts and Vault, and for top-secret items."))
                .font(Theme.font(14)).foregroundStyle(Theme.sub)
            if state.hasSectionPassword {
                AYNField(title: tr("الحالية", "Current"), icon: "lock.fill", text: $current, secure: true, focus: $focus, id: .current)
            }
            AYNField(title: tr("الجديدة (٤ أحرف على الأقل)", "New (4+ characters)"), icon: "lock.square.stack.fill", text: $new,
                     secure: true, focus: $focus, id: .section)
            AYNField(title: tr("أكّدها", "Confirm"), icon: "checkmark.shield.fill", text: $confirm, secure: true, focus: $focus, id: .sectionConfirm)
            if let error { Text(error).font(Theme.font(14, .semibold)).foregroundStyle(Theme.danger) }
            PrimaryButton(title: tr("حفظ", "Save"), icon: "checkmark", enabled: new.count >= 4 && new == confirm) {
                Task {
                    if state.hasSectionPassword, !(await state.checkSectionPassword(current)) {
                        error = tr("الحالية غلط.", "Current is wrong."); FX.error(); return
                    }
                    await state.setSectionPassword(new)
                    state.show(tr("تم ✓", "Saved ✓"))
                    dismiss()
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
                Text(tr("لو غيّرت جوالك أو حذفت الرمز من «كلمات السر»، أضفه من جديد من هنا.", "If you changed phones or removed the code from Passwords, add it again here."))
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
                Text(tr("اكتب كلمة سر الطوارئ بدل كلمتك الأصلية. يفتح خزنة ثانية فاضية تبيّن طبيعية تماماً (نفس اسمك ونفس رمز 2FA وكلمة سر الأقسام). بياناتك الحقيقية تبقى مخفية، والبصمة ما تفتح الخزنة الوهمية.",
                        "Type the duress password instead of your real one. It opens a separate, empty vault that looks completely normal (same name, same 2FA, same section password). Your real data stays hidden."))
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

    var body: some View {
        SheetScaffold(title: tr("سجل المتطفلين", "Intruder log")) {
            if events.isEmpty {
                EmptyStateView(mood: .happy, title: tr("ما في أي محاولة", "No attempts"),
                               subtitle: tr("محد حاول يدخل. نام مرتاح 😌", "Nobody tried to get in. Sleep well 😌"))
            } else {
                ForEach(events) { e in
                    HStack(spacing: 12) {
                        if let d = e.photo, let img = UIImage(data: d) {
                            Image(uiImage: img).resizable().scaledToFill()
                                .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 14))
                        } else {
                            Image(systemName: e.reason == .screenshot ? "camera.viewfinder" : "exclamationmark.lock.fill")
                                .font(.system(size: 24)).foregroundStyle(Theme.warn)
                                .frame(width: 64, height: 64)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.warn.opacity(0.12)))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(e.title).font(Theme.font(15, .bold)).foregroundStyle(Theme.text)
                            Text(Fmt.date(e.date)).font(Theme.font(12)).foregroundStyle(Theme.sub)
                        }
                        Spacer()
                    }
                    .glass(10)
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
                Text(tr("٢. Project Settings ← API: انسخ Project URL و anon public key", "2. Project Settings → API: copy the Project URL and anon public key"))
                Text(tr("٣. شغّل ملف setup.sql (موجود مع المشروع) في SQL Editor", "3. Run setup.sql (included with the project) in the SQL Editor"))
                Text(tr("التفاصيل الكاملة في دليل الإعداد العربي.", "Full details are in the setup guide."))
                    .foregroundStyle(Theme.faint)
            }
            .font(Theme.font(13, .medium)).foregroundStyle(Theme.sub)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(14)

            AYNField(title: "https://xxxx.supabase.co", icon: "link", text: $url, keyboard: .URL, focus: $focus, id: .sbURL)
                .environment(\.layoutDirection, .leftToRight)
            AYNField(title: "anon public key", icon: "key.fill", text: $key, focus: $focus, id: .sbKey)
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
                    if result == true { FX.success() } else { FX.error() }
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
    @State private var autoBackup = true

    private let sb = SupabaseClient.shared

    var body: some View {
        SheetScaffold(title: tr("النسخ الاحتياطي", "Backup")) {
            VStack(alignment: .leading, spacing: 6) {
                Label(tr("كل نسخة تتشفّر على جوالك قبل ما تطلع. السيرفر ما يقدر يقرأها.", "Every backup is encrypted on your phone first. The server can't read it."),
                      systemImage: "lock.shield.fill")
                    .font(Theme.font(13, .semibold)).foregroundStyle(Theme.sub)
                if let last = state.lastBackup {
                    Text(tr("آخر نسخة سحابية: \(Fmt.relative(last))", "Last cloud backup: \(Fmt.relative(last))"))
                        .font(Theme.font(13)).foregroundStyle(Theme.faint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(14)

            SectionTitle(text: tr("السحابة (Supabase)", "Cloud (Supabase)"), icon: "icloud.fill")
            if !sb.isConfigured {
                Text(tr("جهّز Supabase أولاً من الإعدادات.", "Set up Supabase first in Settings.")).font(Theme.font(14)).foregroundStyle(Theme.warn)
            } else if sb.session == nil {
                if !codeSent {
                    PrimaryButton(title: tr("سجّل دخول بكود الإيميل", "Sign in with an email code"), icon: "envelope.fill", loading: loading) {
                        Task { await sendCode() }
                    }
                } else {
                    Text(tr("الكود وصل إلى \(state.profile?.email ?? "")", "Code sent to \(state.profile?.email ?? "")"))
                        .font(Theme.font(14)).foregroundStyle(Theme.sub)
                    CodeField(code: $code, length: 8)
                    PrimaryButton(title: tr("تحقق", "Verify"), icon: "checkmark", loading: loading, enabled: code.count >= 6) {
                        Task { await verify() }
                    }
                }
            } else {
                PrimaryButton(title: tr("انسخ للسحابة الحين", "Back up to cloud now"), icon: "icloud.and.arrow.up.fill", loading: loading) {
                    Task { await cloudBackup() }
                }
                Toggle(isOn: $autoBackup) {
                    Text(tr("نسخ تلقائي أسبوعي", "Weekly auto-backup")).font(Theme.font(15, .semibold))
                }
                .tint(Theme.accent).glass(12)
                .onChange(of: autoBackup) { _, v in state.autoBackup = v }
                Text(tr("الملفات فوق ٥ ميغا (مثل الفيديو) ما تنرفع للسحابة المجانية — استخدم النسخة الكاملة كملف.",
                        "Files over 5 MB (like videos) skip the free cloud — use the full file backup for those."))
                    .font(Theme.font(12)).foregroundStyle(Theme.faint)
                Button { sb.signOut(); state.objectWillChange.send() } label: {
                    Text(tr("تسجيل خروج من السحابة", "Sign out of cloud")).font(Theme.font(13, .semibold)).foregroundStyle(Theme.sub)
                }
            }

            SectionTitle(text: tr("ملف كامل (يشمل الفيديو)", "Full file (includes videos)"), icon: "doc.zipper")
            SecondaryButton(title: tr("صدّر نسخة كاملة (.ayn)", "Export full backup (.ayn)"), icon: "square.and.arrow.up", color: Theme.accent) {
                Task { await exportFile() }
            }
            Text(tr("احفظه في iCloud Drive أو أي مكان. ينفتح بكلمة السر أو مفتاح الاسترجاع.", "Save it to iCloud Drive or anywhere. Opens with your password or recovery key."))
                .font(Theme.font(12)).foregroundStyle(Theme.faint)

            SecondaryButton(title: tr("استعادة نسخة", "Restore a backup"), icon: "arrow.counterclockwise") { showRestore = true }

            if let error { Text(error).font(Theme.font(14, .semibold)).foregroundStyle(Theme.danger) }
        }
        .onAppear { autoBackup = state.autoBackup }
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
            FX.success()
            error = nil
            state.objectWillChange.send()
        } catch { self.error = error.localizedDescription; FX.error() }
    }

    private func cloudBackup() async {
        loading = true
        defer { loading = false }
        state.busy = tr("نشفّر ونرفع…", "Encrypting & uploading…")
        do {
            let skipped = try await state.backupToCloud()
            state.busy = nil
            state.show(skipped > 0 ? tr("تم ✓ (تخطّينا \(skipped) ملف كبير)", "Done ✓ (skipped \(skipped) large files)") : tr("تم النسخ للسحابة ✓", "Backed up to cloud ✓"),
                       icon: "icloud.fill")
            error = nil
        } catch {
            state.busy = nil
            self.error = error.localizedDescription
            FX.error()
        }
    }

    private func exportFile() async {
        state.busy = tr("نجهّز النسخة الكاملة…", "Preparing full backup…")
        defer { state.busy = nil }
        do {
            let (data, _) = try await state.makeBackup(maxFileSize: nil)
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("MNLOVO-AYN-\(f.string(from: Date())).ayn")
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
