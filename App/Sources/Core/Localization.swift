import SwiftUI

/// In-app language switch (Arabic / English) that works instantly without restarting.
enum AppLanguage: String, CaseIterable, Identifiable {
    case ar, en
    var id: String { rawValue }

    static let storageKey = "app.lang"

    static var systemDefault: AppLanguage {
        let first = Locale.preferredLanguages.first ?? "ar"
        return first.hasPrefix("ar") ? .ar : .en
    }

    static var current: AppLanguage {
        if let raw = UserDefaults.standard.string(forKey: storageKey), let l = AppLanguage(rawValue: raw) { return l }
        return systemDefault
    }

    var isRTL: Bool { self == .ar }
    var locale: Locale { Locale(identifier: self == .ar ? "ar_AE" : "en_US") }
    var nativeName: String { self == .ar ? "العربية" : "English" }
}

/// Translate inline: tr("عربي", "English")
func tr(_ ar: String, _ en: String) -> String {
    AppLanguage.current == .ar ? ar : en
}

enum Fmt {
    static func date(_ d: Date, time: Bool = true) -> String {
        let f = DateFormatter()
        f.locale = AppLanguage.current.locale
        f.dateStyle = .medium
        f.timeStyle = time ? .short : .none
        return f.string(from: d)
    }

    static func relative(_ d: Date, now: Date = Date()) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = AppLanguage.current.locale
        f.unitsStyle = .full
        return f.localizedString(for: d, relativeTo: now)
    }

    static func bytes(_ n: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: n)
    }

    static func number(_ n: Int) -> String {
        let f = NumberFormatter()
        f.locale = AppLanguage.current.locale
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    /// "3d 4h" style remaining time.
    static func remaining(until d: Date, now: Date = Date()) -> String {
        let secs = Int(d.timeIntervalSince(now))
        let abs = Swift.abs(secs)
        let days = abs / 86400, hours = (abs % 86400) / 3600, mins = (abs % 3600) / 60
        var parts: [String] = []
        if days > 0 { parts.append(tr("\(days) يوم", "\(days)d")) }
        if hours > 0 { parts.append(tr("\(hours) ساعة", "\(hours)h")) }
        if days == 0 && mins > 0 { parts.append(tr("\(mins) دقيقة", "\(mins)m")) }
        if parts.isEmpty { parts.append(tr("أقل من دقيقة", "< 1m")) }
        let joined = parts.joined(separator: tr(" و", " "))
        return secs >= 0 ? tr("باقي \(joined)", "\(joined) left") : tr("متأخرة \(joined)", "\(joined) overdue")
    }
}
