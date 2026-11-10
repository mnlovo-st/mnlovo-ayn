import SwiftUI

enum VaultSpace: String, Codable, CaseIterable {
    case real, decoy
}

enum Sensitivity: Int, Codable, CaseIterable, Identifiable, Comparable {
    case normal = 0, sensitive = 1, secret = 2
    var id: Int { rawValue }

    static func < (a: Sensitivity, b: Sensitivity) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .normal: return tr("عادي", "Normal")
        case .sensitive: return tr("حساس", "Sensitive")
        case .secret: return tr("سري جداً", "Top secret")
        }
    }
    var subtitle: String {
        switch self {
        case .normal: return tr("يفتح مع القسم", "Opens with the section")
        case .sensitive: return tr("مخفي حتى تضغط عليه", "Hidden until tapped")
        case .secret: return tr("بصمة + كلمة سر القسم كل مرة، ومخفي من البحث", "Face ID + section password every time, hidden from search")
        }
    }
    var color: Color {
        switch self {
        case .normal: return Theme.ok
        case .sensitive: return Theme.warn
        case .secret: return Theme.danger
        }
    }
    var icon: String {
        switch self {
        case .normal: return "shield"
        case .sensitive: return "shield.lefthalf.filled"
        case .secret: return "lock.shield.fill"
        }
    }
}

struct AccountItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var service: String
    var login: String
    var password: String
    var url: String = ""
    var notes: String = ""
    var totp: TOTP?
    var sensitivity: Sensitivity = .sensitive
    var favorite = false
    var created = Date()
    var updated = Date()
    var passwordChanged = Date()
}

struct SecureNote: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var body: String
    var sensitivity: Sensitivity = .sensitive
    var created = Date()
    var updated = Date()
}

enum VaultFileKind: String, Codable {
    case image, video, pdf, document, scan

    var icon: String {
        switch self {
        case .image: return "photo"
        case .video: return "play.rectangle.fill"
        case .pdf: return "doc.richtext"
        case .document: return "doc.fill"
        case .scan: return "doc.viewfinder"
        }
    }
}

struct VaultFile: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var kind: VaultFileKind
    var size: Int64
    var sensitivity: Sensitivity
    var created = Date()
    var thumbnail: Data?
    var ocrText: String?
}

enum ReminderKind: String, Codable, CaseIterable, Identifiable {
    case appointment, task, homework, routine
    var id: String { rawValue }
    var title: String {
        switch self {
        case .appointment: return tr("موعد", "Appointment")
        case .task: return tr("مهمة", "Task")
        case .homework: return tr("واجب", "Homework")
        case .routine: return tr("روتين", "Routine")
        }
    }
    var icon: String {
        switch self {
        case .appointment: return "calendar.badge.clock"
        case .task: return "checklist"
        case .homework: return "book.closed.fill"
        case .routine: return "repeat.circle.fill"
        }
    }
}

/// A daily/weekly routine: chosen weekdays at a set time, every week or just this week,
/// with its own reminder personality and a streak.
struct Routine: Codable, Hashable {
    enum Mode: String, Codable, CaseIterable { case weekly, once }
    enum Style: String, Codable, CaseIterable, Identifiable {
        case gentle, coach, alarm, quiet
        var id: String { rawValue }
        var title: String {
            switch self {
            case .gentle: return tr("لطيف", "Gentle")
            case .coach: return tr("مدرّب", "Coach")
            case .alarm: return tr("منبّه", "Alarm")
            case .quiet: return tr("هادي", "Quiet")
            }
        }
        var icon: String {
            switch self {
            case .gentle: return "leaf.fill"
            case .coach: return "flame.fill"
            case .alarm: return "alarm.waves.left.and.right.fill"
            case .quiet: return "moon.zzz.fill"
            }
        }
        var blurb: String {
            switch self {
            case .gentle: return tr("رسالة ناعمة بوقتها، وتذكير خفيف بعد نص ساعة إذا ما سويتها.", "A soft nudge on time, and a light follow-up 30 min later if needed.")
            case .coach: return tr("يحمّسك ويعدّ سلسلة الأيام 🔥 ما يخليك تكسرها.", "Hypes you up and counts your streak 🔥 so you don't break it.")
            case .alarm: return tr("يلحّ عليك: الحين، وبعد ١٠ و٢٠ و٣٠ دقيقة لين تأكّد.", "Insists: now, then at 10, 20 and 30 minutes until you confirm.")
            case .quiet: return tr("بدون صوت، بس إشعار هادي على الشاشة.", "No sound, just a quiet banner.")
            }
        }
    }

    var mode: Mode = .weekly
    var days: [Int] = [1, 2, 3, 4, 5, 6, 7]     // Calendar weekdays (1 = Sunday)
    var hour = 8
    var minute = 0
    var style: Style = .gentle
    var early = 0                               // heads-up minutes before (0 = none)
    var emoji = "💧"
    var doneDays: [String] = []                 // yyyy-MM-dd
    var skipDays: [String] = []
    var startedAt = Date()

    static func dayKey(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    var timeText: String {
        var c = DateComponents(); c.hour = hour; c.minute = minute
        let d = Calendar.current.date(from: c) ?? Date()
        let f = DateFormatter(); f.locale = AppLanguage.current.locale; f.timeStyle = .short
        return f.string(from: d)
    }

    /// Times this routine fires, from `from` for `span` days (once-mode stops a week after it started).
    func occurrences(from: Date, span: Int = 10) -> [Date] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: from)
        let end = mode == .once ? startedAt.addingTimeInterval(7 * 86400) : .distantFuture
        var out: [Date] = []
        for i in 0..<span {
            guard let day = cal.date(byAdding: .day, value: i, to: start) else { continue }
            guard days.contains(cal.component(.weekday, from: day)),
                  let at = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) else { continue }
            if at > from && at <= end { out.append(at) }
        }
        return out
    }

    func next(after d: Date = Date()) -> Date? { occurrences(from: d, span: 15).first }

    var scheduledToday: Bool { days.contains(Calendar.current.component(.weekday, from: Date())) }
    func isDone(on d: Date) -> Bool { doneDays.contains(Self.dayKey(d)) }
    func isSkipped(on d: Date) -> Bool { skipDays.contains(Self.dayKey(d)) }
    var finished: Bool { mode == .once && Date() > startedAt.addingTimeInterval(7 * 86400) }

    /// Consecutive scheduled days completed, counting back from today (or yesterday if today is still open).
    func streak(now: Date = Date()) -> Int {
        let cal = Calendar.current
        var count = 0
        var day = cal.startOfDay(for: now)
        if days.contains(cal.component(.weekday, from: day)) && !isDone(on: day) {
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        for _ in 0..<400 {
            if days.contains(cal.component(.weekday, from: day)) {
                if isDone(on: day) { count += 1 }
                else if !isSkipped(on: day) { break }
            }
            guard let prev = cal.date(byAdding: .day, value: -1, to: day), prev >= cal.startOfDay(for: startedAt) else { break }
            day = prev
        }
        return count
    }

    /// Short weekday names in display order (week starts per the user's calendar).
    static var orderedDays: [(Int, String)] {
        let cal = Calendar.current
        let ar = ["", "أحد", "إثنين", "ثلاثاء", "أربعاء", "خميس", "جمعة", "سبت"]
        let en = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let first = cal.firstWeekday
        return (0..<7).map { i in
            let d = (first - 1 + i) % 7 + 1
            return (d, tr(ar[d], en[d]))
        }
    }
}

struct Reminder: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var notes: String = ""
    var kind: ReminderKind = .task
    var due: Date
    var sensitivity: Sensitivity = .normal
    var nagHours: Int = 2
    var done = false
    var doneAt: Date?
    var snoozedUntil: Date?
    var calendarEventID: String?
    var created = Date()
    var routine: Routine?

    var isRoutine: Bool { kind == .routine && routine != nil }

    var displayTitle: String {
        sensitivity == .secret ? tr("🔒 تذكير سري", "🔒 Secret reminder") : title
    }

    /// 0 = far, 1 = within 3 days, 2 = last day, 3 = overdue
    func urgency(now: Date = Date()) -> Int {
        if done { return 0 }
        let left = due.timeIntervalSince(now)
        if left < 0 { return 3 }
        if left < 86400 { return 2 }
        if left < 3 * 86400 { return 1 }
        return 0
    }

    func urgencyColor(now: Date = Date()) -> Color {
        if done { return Theme.faint }
        switch urgency(now: now) {
        case 3: return Theme.danger
        case 2: return Color(hex: 0xFF7A45)
        case 1: return Theme.warn
        default: return Theme.ok
        }
    }
}

struct IntruderEvent: Codable, Identifiable {
    enum Reason: String, Codable { case wrongPassword, wrongCode, screenshot, recording }
    var id = UUID()
    var date = Date()
    var reason: Reason
    var photo: Data?

    var title: String {
        switch reason {
        case .wrongPassword: return tr("كلمة سر خاطئة", "Wrong password")
        case .wrongCode: return tr("رمز تحقق خاطئ", "Wrong 2FA code")
        case .screenshot: return tr("لقطة شاشة داخل التطبيق", "Screenshot inside the app")
        case .recording: return tr("تسجيل شاشة", "Screen recording")
        }
    }
}

/// Encrypted profile (inside the vault).
struct Profile: Codable {
    var username: String
    var email: String
    var phone: String
    var birthDate: Date
    var created = Date()
    var emailVerified = false
    var totp: TOTP
    var sectionSalt: Data?
    var sectionHash: Data?
    var sectionKind: String?
    var inboxPrivateKey: Data
    var remindersKey: Data
}

/// Plain metadata (no secrets — only wrapped keys and salted hashes).
struct VaultMeta: Codable {
    var version = 1
    var created = Date()
    var displayName: String
    var salt: Data
    var wrappedByPassword: Data
    var recoverySalt: Data?
    var wrappedByRecovery: Data?
    var identitySalt: Data?
    var identityHash: Data?
    var inboxPublicKey: Data
    /// Phone + birth date only (no email), so support can change the email and recovery still works.
    var identity2Salt: Data?
    var identity2Hash: Data?
}

/// Section lock type: 6-digit passcode (default), 4-digit passcode, or free text.
enum PasscodeKind: String, CaseIterable, Identifiable {
    case pin6, pin4, text
    var id: String { rawValue }
    var length: Int? {
        switch self {
        case .pin6: return 6
        case .pin4: return 4
        case .text: return nil
        }
    }
    var title: String {
        switch self {
        case .pin6: return tr("٦ أرقام", "6 digits")
        case .pin4: return tr("٤ أرقام", "4 digits")
        case .text: return tr("نص", "Text")
        }
    }
}

struct Toast: Identifiable, Equatable {
    enum Style { case info, success, warning, error }
    let id = UUID()
    var text: String
    var icon: String = "checkmark.circle.fill"
    var style: Style = .success

    var color: Color {
        switch style {
        case .info: return Theme.accent
        case .success: return Theme.ok
        case .warning: return Theme.warn
        case .error: return Theme.danger
        }
    }
}
