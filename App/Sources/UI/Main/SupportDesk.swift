import SwiftUI

/// MNLOVO support desk — opened by tapping the copyright in Settings 7 times, then the support key.
/// Vaults are end-to-end encrypted on users' phones: support can find & verify an account, change its
/// email so the owner can sign back in and restore, unlink Telegram or delete it. It can't read or reset vault contents.
struct SupportDeskView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    struct Row: Identifiable, Hashable { let id: String; let email: String; let username: String; let created: String }

    @State private var key = (Keychain.get("admin.key").flatMap { String(data: $0, encoding: .utf8) }) ?? ""
    @State private var authed = false
    @State private var query = ""
    @State private var results: [Row] = []
    @State private var selected: Row?
    @State private var info: [String: Any] = [:]
    @State private var phone = ""
    @State private var dob = Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date()
    @State private var claimedEmail = ""
    @State private var verdict: [String: Any]?
    @State private var newEmail = ""
    @State private var busy = false
    @State private var error: String?
    @State private var confirmDelete = false
    @State private var logLines: [String] = []
    @FocusState private var focus: AYNFieldID?

    private let sb = SupabaseClient.shared

    var body: some View {
        SheetScaffold(title: tr("مكتب الدعم الفني", "Support desk")) {
            Label(tr("البيانات داخل الخزنة مشفّرة في جوال المستخدم، فما نقدر نشوفها ولا نغيّر كلمة سرها. نقدر نتأكد من هويته، ونغيّر إيميله عشان يسجّل دخول ويرجّع نسخته بكلمة سره أو مفتاح الاسترجاع.",
                     "Vault contents are encrypted on the user's phone, so we can't see them or reset the password. We can verify identity and change the email so they can sign in and restore with their password or recovery key."),
                  systemImage: "lock.shield.fill")
                .font(Theme.font(12, .medium)).foregroundStyle(Theme.accent)
                .glass(12, tint: Theme.accent)

            if !authed { keyCard } else {
                searchCard
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
    }

    private var keyCard: some View {
        VStack(spacing: 12) {
            AYNField(title: tr("مفتاح الدعم", "Support key"), icon: "key.fill", text: $key, secure: true, focus: $focus, id: .secret)
                .environment(\.layoutDirection, .leftToRight)
            PrimaryButton(title: tr("دخول", "Enter"), icon: "lock.open.fill", loading: busy, enabled: key.count > 10) { Task { await login() } }
        }
        .glass(14)
    }

    private var searchCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                AYNField(title: tr("ابحث بالإيميل أو اسم المستخدم", "Search by email or username"), icon: "magnifyingglass",
                         text: $query, keyboard: .emailAddress, focus: $focus, id: .search) { Task { await search() } }
                CircleIconButton(icon: "arrow.forward", size: 46, tint: Theme.accent) { Task { await search() } }
            }
            ForEach(results) { r in
                Button { Task { await open(r) } } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.username.isEmpty ? r.email : r.username).font(Theme.font(15, .bold)).foregroundStyle(Theme.text)
                            Text(r.email).font(Theme.font(12)).foregroundStyle(Theme.sub)
                        }
                        Spacer()
                        if selected?.id == r.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent) }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(selected?.id == r.id ? Theme.accent.opacity(0.12) : Theme.surface))
                }
                .buttonStyle(PressScale())
            }
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

    private func detailsCard(_ r: Row) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("معلومات الحساب", "Account info")).font(Theme.font(17, .heavy)).foregroundStyle(Theme.text)
            infoLine(tr("المستخدم", "Username"), info["username"] as? String ?? "—")
            infoLine(tr("الإيميل", "Email"), info["email"] as? String ?? r.email)
            infoLine(tr("تاريخ الإنشاء", "Created"), date(info["created_at"]))
            infoLine(tr("آخر دخول للسحابة", "Last cloud sign-in"), date(info["last_sign_in_at"]))
            if let b = info["backup"] as? [String: Any] {
                infoLine(tr("النسخة السحابية", "Cloud backup"),
                         "\(Fmt.bytes(Int64((b["size"] as? NSNumber)?.intValue ?? 0))) · \(date(b["updated_at"]))")
            } else {
                infoLine(tr("النسخة السحابية", "Cloud backup"), tr("ما فيه", "None"))
            }
            infoLine(tr("محادثات تيليجرام", "Telegram chats"), "\((info["telegram_chats"] as? NSNumber)?.intValue ?? 0)")

            Divider().overlay(Theme.stroke)
            Text(tr("تأكد من هويته — اسأله وحط إجاباته:", "Verify identity — ask and enter their answers:"))
                .font(Theme.font(14, .bold)).foregroundStyle(Theme.text)
            AYNField(title: tr("الإيميل اللي يقوله", "Email they state"), icon: "envelope.fill", text: $claimedEmail,
                     keyboard: .emailAddress, focus: $focus, id: .email)
            PhoneField(full: $phone, focus: $focus)
            HStack {
                Image(systemName: "gift.fill").foregroundStyle(Theme.sub)
                Text(tr("تاريخ الميلاد", "Birth date")).font(Theme.font(15, .medium)).foregroundStyle(Theme.sub)
                Spacer()
                DatePicker("", selection: $dob, in: ...Date(), displayedComponents: .date).labelsHidden()
            }
            .padding(.horizontal, 14).frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
            SecondaryButton(title: tr("تحقق", "Verify"), icon: "person.badge.shield.checkmark.fill", color: Theme.accent) { Task { await verify() } }
            if let v = verdict {
                HStack(spacing: 8) {
                    badge(tr("الإيميل", "Email"), v["email"])
                    badge(tr("الرقم", "Phone"), v["phone"])
                    badge(tr("الميلاد", "Birth"), v["dob"])
                }
            }

            Divider().overlay(Theme.stroke)
            Text(tr("تغيير إيميل الحساب", "Change account email")).font(Theme.font(14, .bold)).foregroundStyle(Theme.text)
            AYNField(title: tr("الإيميل الجديد", "New email"), icon: "envelope.badge.fill", text: $newEmail,
                     keyboard: .emailAddress, focus: $focus, id: .login)
            SecondaryButton(title: tr("غيّر الإيميل", "Change email"), icon: "arrow.triangle.2.circlepath", color: Theme.accent) {
                Task { await act("change_email", ["email": newEmail]) }
            }
            .disabled(!isValidEmail(newEmail) || !verifiedEnough)
            .opacity(isValidEmail(newEmail) && verifiedEnough ? 1 : 0.45)
            Text(tr("بعد التغيير: يفتح التطبيق ← «عندي حساب، تسجيل دخول» ← بالإيميل الجديد ← يحط كلمة سره أو مفتاح الاسترجاع.",
                    "After the change: open the app → “I have an account” → new email → enter their password or recovery key."))
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

    private var verifiedEnough: Bool {
        guard let v = verdict else { return false }
        return (v["phone"] as? Bool == true) && (v["dob"] as? Bool ?? true)
    }

    private func infoLine(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).font(Theme.font(13, .semibold)).foregroundStyle(Theme.sub)
            Spacer()
            Text(v).font(Theme.font(13, .bold)).foregroundStyle(Theme.text).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
    }

    private func badge(_ title: String, _ value: Any?) -> some View {
        let ok = value as? Bool
        return Label(title, systemImage: ok == true ? "checkmark.circle.fill" : (ok == false ? "xmark.octagon.fill" : "minus.circle"))
            .font(Theme.font(12, .bold))
            .foregroundStyle(ok == true ? Theme.ok : (ok == false ? Theme.danger : Theme.faint))
            .padding(.horizontal, 10).frame(height: 30)
            .background(Capsule().fill(Theme.surface))
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
        guard let r = await call(["action": "search", "q": query]) else { return }
        results = (r["results"] as? [[String: Any]] ?? []).map {
            Row(id: $0["user_id"] as? String ?? "", email: $0["email"] as? String ?? "",
                username: $0["username"] as? String ?? "", created: $0["created_at"] as? String ?? "")
        }
        if results.isEmpty { error = tr("ما لقيت أحد.", "No one found.") }
    }

    private func open(_ r: Row) async {
        Haptics.selection()
        selected = r; verdict = nil; newEmail = ""; phone = ""; claimedEmail = ""
        info = await call(["action": "details", "user_id": r.id]) ?? [:]
    }

    private func verify() async {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = .current
        let c = cal.dateComponents([.year, .month, .day], from: dob)
        let day = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        guard let id = selected?.id else { return }
        var p: [String: Any] = ["action": "verify", "user_id": id, "phone": phone, "dob": day]
        if !claimedEmail.isEmpty { p["email"] = claimedEmail }
        if let v = await call(p) {
            withAnimation { verdict = v }
            if (v["phone"] as? Bool == true) && (v["dob"] as? Bool ?? true) { Haptics.success() } else { Haptics.warning() }
        }
    }

    private func act(_ action: String, _ extra: [String: Any] = [:]) async {
        guard let id = selected?.id else { return }
        var p = extra; p["action"] = action; p["user_id"] = id
        guard let r = await call(p) else { return }
        Haptics.success()
        switch action {
        case "change_email":
            info = r
            state.show(tr("تغيّر الإيميل ✓", "Email changed ✓"))
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
