import AppIntents
import Foundation

/// Siri & Shortcuts: add a reminder or ask for the next one — works even while AYN is locked.
struct AddReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "Add AYN reminder"
    static var description = IntentDescription("Adds a reminder to AYN with escalating alerts (3 days, 2 days, 1 day, then nagging on the last day).")
    static var openAppWhenRun = false

    @Parameter(title: "Title")
    var reminderTitle: String

    @Parameter(title: "Due")
    var due: Date

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard VaultStorage.exists(.real), RemindersStore.key(.real) != nil else {
            return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: tr("افتح AYN مرة وحدة أولاً.", "Open AYN once first."))))
        }
        var list = RemindersStore.load(.real)
        list.append(Reminder(title: reminderTitle, due: due))
        RemindersStore.save(list, .real)
        ReminderEngine.rescheduleAll()
        let msg = tr("تمّت إضافة «\(reminderTitle)» — \(Fmt.date(due))", "Added “\(reminderTitle)” — \(Fmt.date(due))")
        return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: msg)))
    }
}

struct NextReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "Next AYN task"
    static var description = IntentDescription("Tells you your nearest unfinished reminder.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let now = Date()
        let next = RemindersStore.load(.real).filter { !$0.done }.sorted { $0.due < $1.due }.first
        let msg: String
        if let n = next {
            msg = "\(n.displayTitle) — \(Fmt.remaining(until: n.due, now: now))"
        } else {
            msg = tr("ما عندك مهام. استانس 🎉", "Nothing pending. Enjoy 🎉")
        }
        return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: msg)))
    }
}

struct AYNShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddReminderIntent(),
                    phrases: ["Add a reminder in \(.applicationName)",
                              "Remind me with \(.applicationName)"],
                    shortTitle: "Add reminder",
                    systemImageName: "bell.badge.fill")
        AppShortcut(intent: NextReminderIntent(),
                    phrases: ["What's next in \(.applicationName)",
                              "Next task in \(.applicationName)"],
                    shortTitle: "Next task",
                    systemImageName: "calendar.badge.clock")
    }
}
