import SwiftUI
import AVFoundation

struct AccountsView: View {
    @EnvironmentObject var state: AppState
    @State private var query = ""
    @State private var filter = 0
    @State private var editing: AccountItem?
    @State private var showing: AccountItem?
    @State private var secretAction: SecretAction?
    @FocusState private var focus: AYNFieldID?

    private var reused: Set<UUID> { state.reusedPasswordIDs }

    private var filtered: [AccountItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return state.accounts
            .filter { a in
                if !q.isEmpty {
                    if a.sensitivity == .secret { return false }   // top secret never appears in search
                    return a.service.lowercased().contains(q) || a.login.lowercased().contains(q) || a.url.lowercased().contains(q)
                }
                return true
            }
            .filter { a in
                switch filter {
                case 1: return a.favorite
                case 2: return a.totp != nil
                case 3: return reused.contains(a.id) || PasswordTools.strength(a.password).score < 2
                default: return true
                }
            }
            .sorted { a, b in
                if a.favorite != b.favorite { return a.favorite }
                return a.service.localizedCaseInsensitiveCompare(b.service) == .orderedAscending
            }
    }

    private var issues: Int {
        state.accounts.filter { reused.contains($0.id) || PasswordTools.strength($0.password).score < 2 }.count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                TabHeader(title: MainTab.accounts.title,
                          subtitle: tr("\(state.accounts.count) حساب محفوظ", "\(state.accounts.count) saved")) {
                    CircleIconButton(icon: "plus", size: 42, tint: Theme.bg) {
                        editing = AccountItem(service: "", login: state.profile?.email ?? "", password: "")
                    }
                    .background(Circle().fill(Theme.gradient))
                }

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.sub)
                    TextField(tr("ابحث…", "Search…"), text: $query)
                        .focused($focus, equals: .search)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.faint) }
                    }
                }
                .font(Theme.font(16))
                .padding(.horizontal, 14).frame(height: 46)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
                .padding(.horizontal, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip(0, tr("الكل", "All"), "square.grid.2x2")
                        chip(1, tr("المفضلة", "Favorites"), "star.fill")
                        chip(2, "2FA", "lock.rotation")
                        chip(3, tr("تحتاج انتباه", "Needs attention") + (issues > 0 ? " (\(issues))" : ""), "exclamationmark.triangle.fill")
                    }
                    .padding(.horizontal, 20)
                }

                if issues > 0 && filter == 0 && query.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.shield.fill").font(.system(size: 22)).foregroundStyle(Theme.warn)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr("\(issues) حساب يحتاج كلمة سر أقوى", "\(issues) accounts need a stronger password"))
                                .font(Theme.font(15, .bold)).foregroundStyle(Theme.text)
                            Text(tr("كلمات مكررة أو ضعيفة. اضغط للعرض.", "Reused or weak passwords. Tap to view."))
                                .font(Theme.font(12)).foregroundStyle(Theme.sub)
                        }
                        Spacer()
                    }
                    .glass(14, tint: Theme.warn)
                    .padding(.horizontal, 20)
                    .onTapGesture { withAnimation { filter = 3 }; FX.tap() }
                }

                if filtered.isEmpty {
                    EmptyStateView(mood: query.isEmpty ? .sleepy : .thinking,
                                   title: query.isEmpty ? tr("ما في حسابات بعد", "No accounts yet") : tr("ما لقيت شي", "Nothing found"),
                                   subtitle: query.isEmpty ? tr("اضغط + وضيف أول حساب.", "Tap + to add your first account.") : tr("جرّب كلمة ثانية.", "Try another word."))
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(filtered) { a in
                            AccountRow(item: a, warn: reused.contains(a.id) || PasswordTools.strength(a.password).score < 2)
                                .onTapGesture { open(a) }
                                .contextMenu {
                                    Button { state.upsert(toggled(a)) } label: {
                                        Label(a.favorite ? tr("إزالة من المفضلة", "Unfavorite") : tr("مفضلة", "Favorite"), systemImage: "star")
                                    }
                                    if a.sensitivity != .secret {
                                        Button { Clipboard.copy(a.password) } label: { Label(tr("نسخ كلمة السر", "Copy password"), systemImage: "doc.on.doc") }
                                    }
                                    Button(role: .destructive) { state.delete(a) } label: { Label(tr("حذف", "Delete"), systemImage: "trash") }
                                }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .sheet(item: $showing) { a in AccountDetailView(itemID: a.id).environmentObject(state) }
        .sheet(item: $editing) { a in AccountEditorView(item: a).environmentObject(state) }
        .sheet(item: $secretAction) { act in SecretUnlockSheet(onUnlock: act.run).environmentObject(state) }
    }

    private func toggled(_ a: AccountItem) -> AccountItem { var c = a; c.favorite.toggle(); return c }

    private func open(_ a: AccountItem) {
        FX.tap()
        if a.sensitivity == .secret {
            secretAction = SecretAction { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showing = a } }
        } else {
            showing = a
        }
    }

    private func chip(_ i: Int, _ title: String, _ icon: String) -> some View {
        Button {
            FX.toggle()
            withAnimation(.spring(response: 0.3)) { filter = i }
        } label: {
            Label(title, systemImage: icon)
                .font(Theme.font(13, .bold))
                .foregroundStyle(filter == i ? Theme.bg : Theme.sub)
                .padding(.horizontal, 14).frame(height: 34)
                .background(Capsule().fill(filter == i ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.surface)))
        }
        .buttonStyle(PressScale())
    }
}

struct AccountRow: View {
    var item: AccountItem
    var warn: Bool

    private var maskedLogin: String {
        switch item.sensitivity {
        case .normal: return item.login
        case .sensitive:
            guard item.login.count > 4 else { return "••••" }
            return String(item.login.prefix(2)) + "•••" + String(item.login.suffix(item.login.contains("@") ? 10 : 2))
        case .secret: return "••••••••"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            BrandAvatar(name: item.sensitivity == .secret ? "🔒" : item.service)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.sensitivity == .secret ? tr("حساب سري", "Secret account") : item.service)
                        .font(Theme.font(16, .bold)).foregroundStyle(Theme.text).lineLimit(1)
                    if item.favorite { Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(Theme.warn) }
                    if warn { Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(Theme.warn) }
                }
                Text(maskedLogin).font(Theme.font(13)).foregroundStyle(Theme.sub).lineLimit(1)
            }
            Spacer(minLength: 6)
            if let t = item.totp, item.sensitivity != .secret {
                TOTPBadge(totp: t)
            } else {
                SensitivityBadge(level: item.sensitivity, compact: true)
            }
        }
        .glass(12, radius: 20)
        .contentShape(Rectangle())
    }
}

// MARK: - Detail

struct AccountDetailView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    var itemID: UUID
    @State private var reveal = false
    @State private var editing: AccountItem?
    @State private var confirmDelete = false

    private var item: AccountItem? { state.accounts.first { $0.id == itemID } }

    var body: some View {
        ZStack {
            AuroraBackground()
            if let a = item {
                ScrollView {
                    VStack(spacing: 14) {
                        HStack {
                            Spacer()
                            CircleIconButton(icon: "xmark", size: 36) { dismiss() }
                        }
                        BrandAvatar(name: a.service, size: 78)
                        Text(a.service).font(Theme.font(26, .heavy)).foregroundStyle(Theme.text)
                        SensitivityBadge(level: a.sensitivity)

                        if let t = a.totp {
                            VStack(spacing: 8) {
                                Text(tr("رمز التحقق", "Verification code")).font(Theme.font(13, .bold)).foregroundStyle(Theme.sub)
                                TOTPBadge(totp: t, big: true)
                                Button { Clipboard.copy(t.code()); state.show(tr("تم نسخ الرمز", "Code copied")) } label: {
                                    Label(tr("نسخ الرمز", "Copy code"), systemImage: "doc.on.doc").font(Theme.font(14, .semibold))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .glass(16, tint: Theme.accent)
                        }

                        VStack(spacing: 0) {
                            fieldRow(tr("الإيميل / اسم المستخدم", "Email / username"), a.login, icon: "person.fill")
                            Divider().overlay(Theme.stroke)
                            HStack(spacing: 12) {
                                Image(systemName: "key.fill").foregroundStyle(Theme.accent).frame(width: 24)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(tr("كلمة السر", "Password")).font(Theme.font(12, .bold)).foregroundStyle(Theme.sub)
                                    Text(reveal ? a.password : String(repeating: "•", count: min(max(a.password.count, 8), 16)))
                                        .font(Theme.mono(16, .semibold)).foregroundStyle(Theme.text)
                                        .textSelection(.enabled)
                                        .environment(\.layoutDirection, .leftToRight)
                                }
                                Spacer()
                                Button { withAnimation { reveal.toggle() }; FX.toggle() } label: {
                                    Image(systemName: reveal ? "eye.slash.fill" : "eye.fill").foregroundStyle(Theme.sub)
                                }
                                Button { Clipboard.copy(a.password); state.show(tr("تم النسخ", "Copied")) } label: {
                                    Image(systemName: "doc.on.doc.fill").foregroundStyle(Theme.accent)
                                }
                                .padding(.leading, 8)
                            }
                            .padding(.vertical, 12)
                            if !a.url.isEmpty {
                                Divider().overlay(Theme.stroke)
                                HStack {
                                    fieldRow(tr("الرابط", "Website"), a.url, icon: "link", copy: false)
                                    Button {
                                        let s = a.url.hasPrefix("http") ? a.url : "https://" + a.url
                                        if let u = URL(string: s) { openURL(u) }
                                    } label: { Image(systemName: "arrow.up.right.square.fill").foregroundStyle(Theme.accent) }
                                }
                            }
                        }
                        .glass(14)

                        VStack(alignment: .leading, spacing: 10) {
                            StrengthMeter(password: a.password)
                            if state.reusedPasswordIDs.contains(a.id) {
                                Label(tr("هذي الكلمة مستخدمة في حساب ثاني", "This password is used on another account"),
                                      systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warn)
                            }
                            let age = Date().timeIntervalSince(a.passwordChanged)
                            Label(tr("آخر تغيير: \(Fmt.relative(a.passwordChanged))", "Changed \(Fmt.relative(a.passwordChanged))"),
                                  systemImage: "clock").foregroundStyle(age > 180 * 86400 ? Theme.warn : Theme.sub)
                            if age > 180 * 86400 {
                                Text(tr("صار لها أكثر من ٦ شهور. فكّر تغيّرها.", "Over 6 months old. Consider changing it."))
                                    .foregroundStyle(Theme.warn)
                            }
                        }
                        .font(Theme.font(13, .semibold))
                        .glass(14)

                        if !a.notes.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(tr("ملاحظات", "Notes")).font(Theme.font(12, .bold)).foregroundStyle(Theme.sub)
                                Text(a.notes).font(Theme.font(15)).foregroundStyle(Theme.text).textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glass(14)
                        }

                        HStack(spacing: 10) {
                            SecondaryButton(title: tr("تعديل", "Edit"), icon: "pencil") { editing = a }
                            SecondaryButton(title: tr("حذف", "Delete"), icon: "trash", color: Theme.danger) { confirmDelete = true }
                        }
                    }
                    .padding(20)
                }
                .sheet(item: $editing) { e in AccountEditorView(item: e).environmentObject(state) }
                .confirmationDialog(tr("حذف الحساب؟", "Delete account?"), isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button(tr("حذف نهائي", "Delete permanently"), role: .destructive) { state.delete(a); dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func fieldRow(_ title: String, _ value: String, icon: String, copy: Bool = true) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Theme.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.font(12, .bold)).foregroundStyle(Theme.sub)
                Text(value).font(Theme.font(16, .semibold)).foregroundStyle(Theme.text).textSelection(.enabled)
            }
            Spacer()
            if copy {
                Button { Clipboard.copy(value); state.show(tr("تم النسخ", "Copied")) } label: {
                    Image(systemName: "doc.on.doc.fill").foregroundStyle(Theme.accent)
                }
            }
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Editor

struct AccountEditorView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State var item: AccountItem
    @State private var showGenerator = false
    @State private var gen = PasswordTools.Options()
    @State private var generated = ""
    @State private var scanning = false
    @State private var secretText = ""
    @State private var totpError: String?
    @FocusState private var focus: AYNFieldID?

    private var isNew: Bool { !state.accounts.contains { $0.id == item.id } }

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(spacing: 14) {
                    SheetHeader(title: isNew ? tr("حساب جديد", "New account") : tr("تعديل", "Edit")) { dismiss() }
                    BrandAvatar(name: item.service.isEmpty ? "?" : item.service, size: 64)
                        .animation(.spring, value: item.service)

                    AYNField(title: tr("التطبيق / الموقع (مثلاً Instagram)", "App / site (e.g. Instagram)"), icon: "app.fill",
                             text: $item.service, focus: $focus, id: .service) { focus = .login }
                    if focus == .service && !item.service.isEmpty {
                        let matches = BrandAvatar.knownNames.filter { $0.lowercased().hasPrefix(item.service.lowercased()) && $0 != item.service }
                        if !matches.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(matches.prefix(6), id: \.self) { m in
                                        Button { item.service = m; focus = .login; FX.tap() } label: {
                                            HStack(spacing: 6) { BrandAvatar(name: m, size: 22); Text(m) }
                                                .font(Theme.font(13, .semibold)).foregroundStyle(Theme.text)
                                                .padding(.horizontal, 10).frame(height: 34)
                                                .background(Capsule().fill(Theme.surface))
                                        }
                                    }
                                }
                            }
                        }
                    }
                    AYNField(title: tr("الإيميل أو اسم المستخدم", "Email or username"), icon: "person.fill",
                             text: $item.login, keyboard: .emailAddress, focus: $focus, id: .login) { focus = .password }
                    AYNField(title: tr("كلمة السر", "Password"), icon: "key.fill", text: $item.password, secure: true,
                             focus: $focus, id: .password,
                             trailing: AnyView(Button { withAnimation(.spring) { showGenerator.toggle() }; regen() } label: {
                                 Image(systemName: "wand.and.stars").foregroundStyle(Theme.accent)
                             }))
                    StrengthMeter(password: item.password)

                    if showGenerator { generatorCard.transition(.opacity.combined(with: .move(edge: .top))) }

                    AYNField(title: tr("الرابط (اختياري)", "Website (optional)"), icon: "link", text: $item.url,
                             keyboard: .URL, focus: $focus, id: .url)

                    totpCard

                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle(text: tr("ملاحظات", "Notes"), icon: "note.text")
                        TextEditor(text: $item.notes)
                            .scrollContentBackground(.hidden)
                            .font(Theme.font(15))
                            .frame(minHeight: 80)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle(text: tr("مستوى الحساسية", "Sensitivity"), icon: "shield.lefthalf.filled")
                        SensitivityPicker(level: $item.sensitivity)
                    }
                    Toggle(isOn: $item.favorite) { Label(tr("مفضلة", "Favorite"), systemImage: "star.fill").font(Theme.font(15, .semibold)) }
                        .tint(Theme.warn).glass(14)

                    PrimaryButton(title: tr("حفظ", "Save"), icon: "checkmark",
                                  enabled: !item.service.trimmingCharacters(in: .whitespaces).isEmpty) {
                        item.service = item.service.trimmingCharacters(in: .whitespaces)
                        state.upsert(item)
                        Haptics.success()
                        dismiss()
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .sheet(isPresented: $scanning) {
            QRScannerSheet { text in
                scanning = false
                applyTOTP(text)
            }
        }
    }

    private func regen() { generated = PasswordTools.generate(gen) }

    private var generatorCard: some View {
        VStack(spacing: 12) {
            Text(generated)
                .font(Theme.mono(18, .bold))
                .foregroundStyle(Theme.accent)
                .multilineTextAlignment(.center)
                .environment(\.layoutDirection, .leftToRight)
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity)
            HStack {
                Text(tr("الطول: \(gen.length)", "Length: \(gen.length)")).font(Theme.font(13, .bold))
                Slider(value: Binding(get: { Double(gen.length) }, set: { gen.length = Int($0) }), in: 8...40, step: 1)
                    .tint(Theme.accent)
            }
            HStack {
                toggleChip("ABC", $gen.upper)
                toggleChip("abc", $gen.lower)
                toggleChip("123", $gen.digits)
                toggleChip("#$&", $gen.symbols)
            }
            HStack(spacing: 10) {
                SecondaryButton(title: tr("جديدة", "New"), icon: "arrow.triangle.2.circlepath") { withAnimation { regen() } }
                SecondaryButton(title: tr("استخدمها", "Use it"), icon: "checkmark", color: Theme.accent) {
                    item.password = generated
                    withAnimation { showGenerator = false }
                }
            }
        }
        .glass(14, tint: Theme.accent)
        .onChange(of: gen) { _, _ in regen() }
    }

    private func toggleChip(_ title: String, _ on: Binding<Bool>) -> some View {
        Button { on.wrappedValue.toggle(); FX.toggle() } label: {
            Text(title).font(Theme.mono(14, .bold))
                .foregroundStyle(on.wrappedValue ? Theme.bg : Theme.sub)
                .frame(maxWidth: .infinity).frame(height: 34)
                .background(Capsule().fill(on.wrappedValue ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.surface)))
        }
        .buttonStyle(PressScale())
    }

    private var totpCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: tr("رمز التحقق 2FA (اختياري)", "2FA code (optional)"), icon: "lock.rotation")
            if let t = item.totp {
                HStack {
                    TOTPBadge(totp: t)
                    Spacer()
                    Button(role: .destructive) { withAnimation { item.totp = nil } } label: {
                        Image(systemName: "trash").foregroundStyle(Theme.danger)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    SecondaryButton(title: tr("مسح QR", "Scan QR"), icon: "qrcode.viewfinder", color: Theme.accent) { scanning = true }
                    SecondaryButton(title: tr("لصق", "Paste"), icon: "doc.on.clipboard") {
                        if let s = UIPasteboard.general.string { applyTOTP(s) }
                    }
                }
                AYNField(title: tr("أو اكتب المفتاح السري", "Or type the secret key"), icon: "character.cursor.ibeam",
                         text: $secretText, focus: $focus, id: .secret) { applyTOTP(secretText) }
                if let totpError { Text(totpError).font(Theme.font(12, .semibold)).foregroundStyle(Theme.danger) }
            }
        }
        .glass(14)
    }

    private func applyTOTP(_ text: String) {
        if var t = TOTP.parse(text) {
            if t.issuer.isEmpty { t.issuer = item.service }
            if item.service.isEmpty { item.service = t.issuer }
            if item.login.isEmpty { item.login = t.account }
            withAnimation { item.totp = t }
            totpError = nil
            Haptics.success()
        } else {
            totpError = tr("ما قدرت أقرأ المفتاح.", "Couldn't read that key.")
            FX.error()
        }
    }
}

// MARK: - QR scanner

struct QRScannerSheet: View {
    var onFound: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack(alignment: .top) {
            QRScannerView(onFound: onFound).ignoresSafeArea()
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(Theme.gradient, lineWidth: 4)
                .frame(width: 250, height: 250)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Text(tr("وجّه الكاميرا على رمز QR", "Point at the QR code")).font(Theme.font(16, .bold))
                Spacer()
                CircleIconButton(icon: "xmark", size: 36) { dismiss() }
            }
            .padding(20)
            .background(.ultraThinMaterial)
        }
    }
}

struct QRScannerView: UIViewControllerRepresentable {
    var onFound: (String) -> Void
    func makeUIViewController(context: Context) -> ScannerVC {
        let vc = ScannerVC()
        vc.onFound = onFound
        return vc
    }
    func updateUIViewController(_ uiViewController: ScannerVC, context: Context) {}

    final class ScannerVC: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onFound: ((String) -> Void)?
        private let session = AVCaptureSession()
        private var preview: AVCaptureVideoPreviewLayer?
        private var done = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            AVCaptureDevice.requestAccess(for: .video) { granted in
                guard granted else { return }
                DispatchQueue.main.async { self.setup() }
            }
        }

        private func setup() {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return }
            session.addInput(input)
            let out = AVCaptureMetadataOutput()
            guard session.canAddOutput(out) else { return }
            session.addOutput(out)
            out.setMetadataObjectsDelegate(self, queue: .main)
            out.metadataObjectTypes = [.qr]
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.addSublayer(layer)
            preview = layer
            DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            preview?.frame = view.bounds
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if session.isRunning { session.stopRunning() }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !done, let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject, let s = obj.stringValue else { return }
            done = true
            Haptics.success()
            session.stopRunning()
            onFound?(s)
        }
    }
}
