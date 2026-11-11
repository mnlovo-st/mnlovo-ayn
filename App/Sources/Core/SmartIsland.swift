import Foundation

/// Decides, for each reminder, whether it deserves a Dynamic Island countdown and how early.
///
/// A countdown is useful when there's work to finish before a deadline, and the right amount of
/// warning depends on how much work it is: a call takes minutes, a report takes an evening. An
/// appointment isn't work at all — you just need to remember to be there — so it gets two plain
/// messages instead (the day before and that morning), and never a countdown.
///
/// The decision reads the reminder's type first, then its title and notes for the words people
/// actually use ("مشروع", "assignment", "اختبار", "اتصل"…), in Arabic or English.
enum SmartIsland {
    struct Decision {
        /// How long before the time the countdown appears; nil means no countdown.
        var lead: TimeInterval?
        /// One line saying why, shown under the switch in the editor.
        var reason: String
        /// Short label on the countdown itself ("آخر ٣ ساعات").
        var badge: String
    }

    private static let bigWork = ["مشروع", "تقرير", "بحث", "عرض", "بريزنتيشن", "برزنتيشن", "تكليف", "مقال", "لاب",
                                  "assignment", "project", "report", "essay", "research", "presentation", "lab", "paper", "thesis"]
    private static let exams = ["امتحان", "اختبار", "كويز", "ميدترم", "فاينل",
                                "exam", "quiz", "midterm", "final", "test"]
    private static let quick = ["اتصل", "كلم", "رد على", "ادفع", "سدد", "حول", "طرش", "ارسل", "جدد",  // wording:ignore — words people type, not words we show
                                "call", "pay", "reply", "send", "text", "renew", "transfer"]

    /// Lower-case, strip Arabic diacritics and fold the letter forms people type interchangeably,
    /// so "أختبار" and "اختبار" match the same word.
    private static func fold(_ s: String) -> String {
        var t = s.lowercased()
        t = t.unicodeScalars.filter { !(0x064B...0x065F).contains($0.value) && $0.value != 0x0640 }
            .map(String.init).joined()
        for (a, b) in [("أ", "ا"), ("إ", "ا"), ("آ", "ا"), ("ة", "ه"), ("ى", "ي")] { t = t.replacingOccurrences(of: a, with: b) }
        return t
    }

    private static func mentions(_ text: String, _ words: [String]) -> Bool {
        words.contains { text.contains(fold($0)) }
    }

    static func decide(_ r: Reminder) -> Decision {
        let text = fold(r.title + " " + r.notes)

        switch r.kind {
        case .routine, .subscription:
            return Decision(lead: nil, reason: "", badge: "")
        case .appointment:
            return Decision(lead: nil,
                            reason: tr("المواعيد ما تحتاج عدّاد: نذكّرك قبلها بيوم، وصباح نفس اليوم.",
                                       "Appointments don't need a countdown: you get a reminder the day before and that morning."),
                            badge: "")
        case .homework, .task:
            break
        }

        if mentions(text, exams) {
            return Decision(lead: 3600,
                            reason: tr("اختبار: يطلع قبله بساعة عشان توصل على وقتك.", "An exam: appears an hour before so you're on time."),
                            badge: tr("آخر ساعة", "Last hour"))
        }
        if mentions(text, bigWork) {
            return Decision(lead: 3 * 3600,
                            reason: tr("شغل كبير: يطلع قبل التسليم بـ ٣ ساعات، وقت كافي تخلّصه.",
                                       "Big piece of work: appears 3 hours before, enough time to finish."),
                            badge: tr("آخر ٣ ساعات", "Last 3 hours"))
        }
        if mentions(text, quick) {
            return Decision(lead: 15 * 60,
                            reason: tr("شي سريع: يطلع قبله بربع ساعة بس.", "Something quick: appears just 15 minutes before."),
                            badge: tr("آخر ربع ساعة", "Last 15 min"))
        }
        if r.kind == .homework {
            return Decision(lead: 30 * 60,
                            reason: tr("واجب: يطلع قبل التسليم بنص ساعة.", "Homework: appears 30 minutes before it's due."),
                            badge: tr("آخر نص ساعة", "Last 30 min"))
        }
        return Decision(lead: 3600,
                        reason: tr("مهمة: يطلع قبلها بساعة.", "A task: appears an hour before."),
                        badge: tr("آخر ساعة", "Last hour"))
    }

    /// When the countdown should actually start. Nobody wants a countdown waking them at 4 am, so a
    /// start that falls between midnight and 7 is pushed to 7 — unless the deadline itself is before 7.
    static func start(for r: Reminder) -> Date? {
        guard let lead = decide(r).lead else { return nil }
        var start = r.due.addingTimeInterval(-lead)
        let cal = Calendar.current
        let h = cal.component(.hour, from: start)
        if h < 7, let seven = cal.date(bySettingHour: 7, minute: 0, second: 0, of: start), seven < r.due {
            start = seven
        }
        return start
    }
}
