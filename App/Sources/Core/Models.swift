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
    case appointment, task, homework
    var id: String { rawValue }
    var title: String {
        switch self {
        case .appointment: return tr("موعد", "Appointment")
        case .task: return tr("مهمة", "Task")
        case .homework: return tr("واجب", "Homework")
        }
    }
    var icon: String {
        switch self {
        case .appointment: return "calendar.badge.clock"
        case .task: return "checklist"
        case .homework: return "book.closed.fill"
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
