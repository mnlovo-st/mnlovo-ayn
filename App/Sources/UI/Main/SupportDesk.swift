import SwiftUI

/// MNLOVO support desk — opened by tapping the copyright in Settings 7 times, then the support key.
/// Search is forgiving (typos, a missing letter, a birth date a few days off, part of a phone number),
/// and every similar account is listed so you can compare. Vaults are end-to-end encrypted on users'
/// phones: support can find, compare, change the email and send recovery help — never read the vault.
struct SupportDeskView: View {
    @EnvironmentObject var state: AppState

    struct Row: Identifiable, Hashable {
        let id: String
        let email: String
        let username: String
        let phone: String
        let dob: String
        let created: String
        let registered: Bool
        let emailScore: Double
        let userScore: Double
        let phoneMatch: Bool
        let dobDays: Int?
        let score: Double
    }

    @State private var key = (Keychain.get("admin.key").flatMap { String(data: $0, encoding: .utf8) }) ?? ""
    @State private var authed = false
    @State private var qEmail = ""
    @State private var qUser = ""
    @State private var qPhone = ""
    @State private var useDob = false
    @State private var qDob = Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date()
    @State private var results: [Row] = []
    @State private var selected: Row?
    @State private var info: [String: Any] = [:]
    @State private var newEmail = ""
    @State private var busy = false
    @State private var error: String?
    @State private var confirmDelete = false
    @State private var confirmEmail = false
    @State private var logLines: [String] = []
    @FocusState private var focus: AYNFieldID?

    private let sb = SupabaseClient.shared

    var body: some View {
        SheetScaffold(title: tr("مكتب الدعم الفني", "Support desk")) {
            Label(tr("بيانات الخزنة نفسها مشفّرة في جوال المستخدم، ما تنشاف ولا تنغيّر كلمة سرها. تقدر تلقى الحساب وتقارن معلوماته وتغيّر إيميله وترسل له مساعدة الاسترجاع.",
                     "Vault contents are encrypted on the user's phone and can't be read or reset. You can find the account, compare details, change the email and send recovery help."),
                  systemImage: "lock.shield.fill")
                .font(Theme.font(12, .medium)).foregroundStyle(Theme.accent)
                .glass(12, tint: Theme.accent)

            if !authed { keyCard } else {
                searchCard
                if !results.isEmpty { resultsCard }
                if let selected { detailsCard(selected) }
                if !logLines.isEmpty { logCard }
            }
            if let error { Text(error).font(Theme.font(13, .semibold)).foregroundStyle(Theme.danger) }
        }
        .task { if !key.isEmpty { await login(silent: true) } }
        .confirmationDialog(tr("حذف الحساب نهائياً من السيرفر؟", "Delete this account from the server for good?"),
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(tr("حذف نهائي", "Delete permanently"), role: .destructive) { Task { await act("delete_user") } }
        } message: {
            Text(tr("ينحذف الإيميل والنسخة السحابية وروابط تيليجرام. البيانات اللي في جواله تبقى عنده.", "Email, cloud backup and Telegram links are removed. Data on their phone stays there."))
        }
        .confirmationDialog(tr("تغيير إيميل الحساب إلى \(newEmail)؟", "Change the account email to \(newEmail)?"),
                            isPresented: $confirmEmail, titleVisibility: .visible) {
            Button(tr("غيّر الإيميل", "Change email")) { Task { await act("change_email", ["email": newEmail]) } }
        } message: {
            Text(tr("تأكد إنك قارنت معلوماته. بعدها اضغط «أرسل له مساعدة الاسترجاع».", "Make sure you compared their details. Then tap “Send recovery help”."))
        }
    }

    // MARK: Cards

    private var keyCard: some View {
        VStack(spacing: 12) {
            AYNField(title: tr("مفتاح الدعم", "Support key"), icon: "key.fill", text: $key, secure: true, focus: $focus, id: .secret)
                .environment(\.layoutDirection, .leftToRight)
            PrimaryButton(title: tr("دخول", "Enter"), icon: "lock.open.fill", loading: busy, enabled: key.count > 10) { Task { await login() } }
        }
        .glass(14)
    }

    private var searchCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("ابحث بأي معلومة (وحدة أو أكثر)", "Search by any detail (one or more)"))
                .font(Theme.font(15, .heavy)).foregroundStyle(Theme.text)
            AYNField(title: tr("الإيميل (حتى لو ناقص حرف)", "Email (even with a typo)"), icon: "envelope.fill", text: $qEmail,
                     keyboard: .emailAddress, focus: $focus, id: .email)
            AYNField(title: tr("اسم المستخدم", "Username"), icon: "person.fill", text: $qUser, focus: $focus, id: .username)
            PhoneField(full: $qPhone, focus: $focus)
            HStack {
                Toggle(isOn: $useDob) {
                    Label(tr("تاريخ الميلاد (±٣ أيام)", "Birth date (±3 days)"), systemImage: "gift.fill")
                        .font(Theme.font(14, .semibold)).foregroundStyle(Theme.sub)
                }
                .tint(Theme.accent)
            }
            if useDob {
                DatePicker("", selection: $qDob, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.compact).labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            PrimaryButton(title: tr("ابحث", "Search"), icon: "magnifyingglass", loading: busy, enabled: canSearch) { Task { await search() } }
            HStack {
                Button(tr("سجل العمليات", "Activity log")) { Task { await loadLog() } }
                    .font(Theme.font(13, .semibold)).foregroundStyle(Theme.sub)
                Spacer()
                Button(tr("خروج", "Sign out")) {
                    Keychain.delete("admin.key"); key = ""; authed = false; results = []; selected = nil
                }
                .font(Theme.font(13, .semibold)).foregroundStyle(Theme.danger)
            }
        }
        .glass(14)
    }

    private var canSearch: Bool {
        qEmail.count >= 2 || qUser.count >= 2 || PhoneNumber.isValid(qPhone) || qPhone.filter(\.isNumber).count >= 4 || useDob
    }

    private var resultsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("النتائج (\(results.count)) — الأقرب أول", "Results (\(results.count)) — closest first"))
                .font(Theme.font(15, .heavy)).foregroundStyle(Theme.text)
            ForEach(results) { r in
                Button { Task { await open(r) } } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(r.username.isEmpty ? r.email : r.username).font(Theme.font(15, .bold)).foregroundStyle(Theme.text)
                            if !r.registered {
                                Text(tr("غير مكتمل", "Incomplete")).font(Theme.font(10, .bold)).foregroundStyle(Theme.warn)
                                    .padding(.horizontal, 6).frame(height: 18).background(Capsule().fill(Theme.warn.opacity(0.15)))
                            }
                            Spacer()
                            Text(String(format: "%.1f", r.score)).font(Theme.mono(12, .bold)).foregroundStyle(Theme.faint)
                        }
                        Text(r.email).font(Theme.font(12)).foregroundStyle(Theme.sub).textSelection(.enabled)
                        HStack(spacing: 6) {
                            if !r.phone.isEmpty { chip("phone.fill", r.phone, ok: r.phoneMatch) }
                            if !r.dob.isEmpty { chip("gift.fill", r.dob, ok: r.dobDays == 0, near: (r.dobDays ?? 99) <= 3) }
                        }
                        HStack(spacing: 6) {
                            if r.emailScore > 0 { match(tr("الإيميل", "Email"), r.emailScore) }
                            if r.userScore > 0 { match(tr("الاسم", "Name"), r.userScore) }
                            if r.phoneMatch { match(tr("الرقم", "Phone"), 1) }
                            if let d = r.dobDays { match(d == 0 ? tr("الميلاد", "Birth") : tr("الميلاد ±\(d)", "Birth ±\(d)"), d == 0 ? 1 : 0.5) }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(selected?.id == r.id ? Theme.accent.opacity(0.12) : Theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected?.id == r.id ? Theme.accent.opacity(0.5) : .clear))
                }
                .buttonStyle(PressScale())
            }
        }
        .glass(14)
    }

    private func detailsCard(_ r: Row) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("كل معلومات الحساب", "Full account details")).font(Theme.font(17, .heavy)).foregroundStyle(Theme.text)
            infoLine(tr("المستخدم", "Username"), info["username"] as? String ?? "—")
            infoLine(tr("الإيميل", "Email"), info["email"] as? String ?? r.email)
            infoLine(tr("رقم الهاتف", "Phone"), info["phone"] as? String ?? "—")
            infoLine(tr("تاريخ الميلاد", "Birth date"), info["dob"] as? String ?? "—")
            infoLine(tr("تاريخ الإنشاء", "Created"), date(info["created_at"]))
            infoLine(tr("آخر دخول للسحابة", "Last cloud sign-in"), date(info["last_sign_in_at"]))
            if let b = info["backup"] as? [String: Any] {
                infoLine(tr("النسخة السحابية", "Cloud backup"),
                         "\(Fmt.bytes(Int64((b["size"] as? NSNumber)?.intValue ?? 0))) · \(date(b["updated_at"]))")
            } else {
                infoLine(tr("النسخة السحابية", "Cloud backup"), tr("ما فيه", "None"))
            }
            infoLine(tr("محادثات تيليجرام", "Telegram chats"), "\((info["telegram_chats"] as? NSNumber)?.intValue ?? 0)")
            if (info["phone"] as? String) == nil && (info["registered"] as? Bool ?? false) {
                Text(tr("الرقم والميلاد يظهرون بعد ما يفتح التطبيق بالنسخة الجديدة وهو مسجّل في السحابة.", "Phone and birth date appear once they open the new version while signed in to the cloud."))
                    .font(Theme.font(11)).foregroundStyle(Theme.faint)
            }

            Divider().overlay(Theme.stroke)
            Text(tr("١. غيّر إيميل الحساب (إذا يحتاج)", "1. Change the account email (if needed)")).font(Theme.font(14, .bold)).foregroundStyle(Theme.text)
            AYNField(title: tr("الإيميل الجديد", "New email"), icon: "envelope.badge.fill", text: $newEmail,
                     keyboard: .emailAddress, focus: $focus, id: .login)
            SecondaryButton(title: tr("غيّر الإيميل", "Change email"), icon: "arrow.triangle.2.circlepath", color: Theme.accent) {
                confirmEmail = true
            }
            .disabled(!isValidEmail(newEmail))
            .opacity(isValidEmail(newEmail) ? 1 : 0.45)

            Text(tr("٢. أرسل له مساعدة الاسترجاع", "2. Send recovery help")).font(Theme.font(14, .bold)).foregroundStyle(Theme.text)
            PrimaryButton(title: tr("أرسل كود الدخول + الخطوات", "Send sign-in code + steps"), icon: "paperplane.fill", loading: busy) {
                Task { await act("send_reset") }
            }
            Text(tr("يوصله كود على إيميل الحساب، ورسالة بالخطوات في تيليجرام إذا كان رابطه. يدخل بالكود ويرجّع بياناته بكلمة المرور أو مفتاح الاسترجاع، أو من «نسيت كلمة المرور» إذا جواله القديم معه.",
                    "They get a code at the account email, plus the steps on Telegram if linked. They sign in with the code and restore with their password or recovery key, or use “Forgot password” on their old phone."))
                .font(Theme.font(12)).foregroundStyle(Theme.sub)

            Divider().overlay(Theme.stroke)
            HStack(spacing: 10) {
                SecondaryButton(title: tr("فك تيليجرام", "Unlink Telegram"), icon: "paperplane", color: Theme.warn) { Task { await act("unlink_telegram") } }
                SecondaryButton(title: tr("حذف النسخة", "Delete backup"), icon: "icloud.slash", color: Theme.warn) { Task { await act("delete_backup") } }
            }
            SecondaryButton(title: tr("حذف الحساب من السيرفر", "Delete account from server"), icon: "trash.fill", color: Theme.danger) { confirmDelete = true }
        }
        .glass(14)
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tr("سجل العمليات", "Activity log")).font(Theme.font(15, .heavy)).foregroundStyle(Theme.text)
            ForEach(logLines, id: \.self) { Text($0).font(Theme.mono(11)).foregroundStyle(Theme.sub) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(14)
    }

    // MARK: Bits

    private func chip(_ icon: String, _ text: String, ok: Bool, near: Bool = false) -> some View {
        Label(text, systemImage: icon)
            .font(Theme.font(11, .semibold))
            .foregroundStyle(ok ? Theme.ok : (near ? Theme.warn : Theme.sub))
            .padding(.horizontal, 8).frame(height: 24)
            .background(Capsule().fill(Theme.surfaceHi))
            .environment(\.layoutDirection, .leftToRight)
    }

    private func match(_ title: String, _ score: Double) -> some View {
        Text(title + (score >= 0.95 ? " ✓" : " ≈"))
            .font(Theme.font(10, .bold))
            .foregroundStyle(score >= 0.95 ? Theme.ok : Theme.warn)
            .padding(.horizontal, 7).frame(height: 20)
            .background(Capsule().fill((score >= 0.95 ? Theme.ok : Theme.warn).opacity(0.14)))
    }

    private func infoLine(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).font(Theme.font(13, .semibold)).foregroundStyle(Theme.sub)
            Spacer()
            Text(v).font(Theme.font(13, .bold)).foregroundStyle(Theme.text).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
    }

    private func date(_ any: Any?) -> String {
        guard let s = any as? String else { return "—" }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) ?? ISO8601DateFormatter().date(from: s) { return Fmt.date(d) }
        return s
    }

    // MARK: Calls

    private func call(_ payload: [String: Any]) async -> [String: Any]? {
        busy = true; defer { busy = false }
        do { let r = try await sb.adminCall(key: key.trimmingCharacters(in: .whitespaces), payload); error = nil; return r }
        catch { self.error = error.localizedDescription; FX.error(); return nil }
    }

    private func login(silent: Bool = false) async {
        if await call(["action": "ping"]) != nil {
            Keychain.set(Data(key.trimmingCharacters(in: .whitespaces).utf8), account: "admin.key")
            withAnimation { authed = true }
            if !silent { FX.success() }
        } else if silent { error = nil }
    }

    private func search() async {
        focus = nil
        var p: [String: Any] = ["action": "search"]
        if !qEmail.isEmpty { p["email"] = qEmail }
        if !qUser.isEmpty { p["username"] = qUser }
        if !qPhone.isEmpty { p["phone"] = qPhone }
        if useDob { p["dob"] = SupabaseClient.day(qDob) }
        guard let r = await call(p) else { return }
        let list = (r["results"] as? [[String: Any]] ?? []).map { d -> Row in
            func num(_ k: String) -> Double { (d[k] as? NSNumber)?.doubleValue ?? 0 }
            return Row(id: d["user_id"] as? String ?? "", email: d["email"] as? String ?? "",
                       username: d["username"] as? String ?? "", phone: d["phone"] as? String ?? "",
                       dob: d["dob"] as? String ?? "", created: d["created_at"] as? String ?? "",
                       registered: d["registered"] as? Bool ?? true,
                       emailScore: num("email_score"), userScore: num("username_score"),
                       phoneMatch: d["phone_match"] as? Bool ?? false,
                       dobDays: (d["dob_days"] as? NSNumber)?.intValue, score: num("score"))
        }
        withAnimation { results = list; selected = nil }
        if list.isEmpty { error = tr("ما لقيت أحد. جرّب معلومة ثانية أو جزء من الإيميل.", "No one found. Try another detail or part of the email.") }
        else { Haptics.success() }
    }

    private func open(_ r: Row) async {
        Haptics.selection()
        selected = r; newEmail = ""
        info = await call(["action": "details", "user_id": r.id]) ?? [:]
    }

    private func act(_ action: String, _ extra: [String: Any] = [:]) async {
        guard let id = selected?.id else { return }
        var p = extra; p["action"] = action; p["user_id"] = id
        guard let r = await call(p) else { return }
        Haptics.success()
        switch action {
        case "change_email":
            info = r
            state.show(tr("تغيّر الإيميل ✓ الحين أرسل له مساعدة الاسترجاع", "Email changed ✓ now send recovery help"))
        case "send_reset":
            let mailOK = r["email_sent"] as? Bool ?? false
            let tgCount = (r["telegram"] as? NSNumber)?.intValue ?? 0
            state.show(tr("انرسل ✓ إيميل: \(mailOK ? "نعم" : "لا") · تيليجرام: \(tgCount)", "Sent ✓ email: \(mailOK ? "yes" : "no") · Telegram: \(tgCount)"),
                       icon: "paperplane.fill")
        case "delete_user":
            results.removeAll { $0.id == id }; selected = nil
            state.show(tr("انحذف الحساب من السيرفر", "Account deleted from server"), icon: "trash.fill")
        default:
            info = await call(["action": "details", "user_id": id]) ?? info
            state.show(tr("تم ✓", "Done ✓"))
        }
    }

    private func loadLog() async {
        guard let r = await call(["action": "log"]) else { return }
        logLines = (r["entries"] as? [[String: Any]] ?? []).map {
            "\(date($0["at"])) · \($0["action"] as? String ?? "") \(($0["detail"] as? String) ?? "")"
        }
    }
}
