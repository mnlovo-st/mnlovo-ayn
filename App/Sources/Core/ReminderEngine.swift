import Foundation
import UserNotifications
import WidgetKit
import ActivityKit
import EventKit

/// Escalating reminder plan:
///   3 days before → 2 days before → 1 day before →
///   last day: every N hours until due ("did you do it?") → at due time →
///   overdue: every 3 hours for 24h until you confirm it's done.
enum ReminderEngine {
    static let category = "AYN_REMINDER"
    static let routineCategory = "AYN_ROUTINE"
    static let maxPending = 60

    struct Planned: Hashable {
        var date: Date
        var title: String
        var body: String
        var category = ReminderEngine.category
        var silent = false
    }

    static func registerCategories() {
        let done = UNNotificationAction(identifier: "DONE", title: tr("✅ خلصتها", "✅ Done"), options: [])
        let snooze = UNNotificationAction(identifier: "SNOOZE", title: tr("⏰ ذكّرني بعد ساعة", "⏰ Remind me in 1h"), options: [])
        let cat = UNNotificationCategory(identifier: category, actions: [done, snooze], intentIdentifiers: [], options: [])
        let rDone = UNNotificationAction(identifier: "ROUTINE_DONE", title: tr("✓ سويتها", "✓ Did it"), options: [])
        let rSnooze = UNNotificationAction(identifier: "ROUTINE_SNOOZE", title: tr("⏰ بعد ١٥ دقيقة", "⏰ In 15 min"), options: [])
        let rSkip = UNNotificationAction(identifier: "ROUTINE_SKIP", title: tr("⏭️ تخطّي اليوم", "⏭️ Skip today"), options: [])
        let rcat = UNNotificationCategory(identifier: routineCategory, actions: [rDone, rSnooze, rSkip], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([cat, rcat])
    }

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Routine notifications for the next days, in the routine's own voice.
    static func routinePlan(for r: Reminder, now: Date = Date()) -> [Planned] {
        guard let ro = r.routine, !r.done, !ro.finished else { return [] }
        let name = (ro.emoji.isEmpty ? "" : ro.emoji + " ") + r.displayTitle
        var out: [Planned] = []
        let gentle = [tr("حان وقتها 😊 خطوة صغيرة كل يوم تفرق.", "It's time 😊 small steps every day add up."),
                      tr("لا تنساها اليوم 🌿", "Don't forget it today 🌿"),
                      tr("دقيقتين وتخلص، يلا 💫", "Two minutes and it's done 💫")]
        for (i, at) in ro.occurrences(from: now, span: 10).enumerated() {
            if ro.isDone(on: at) || ro.isSkipped(on: at) { continue }
            let streak = ro.streak(now: at)
            if ro.early > 0 {
                out.append(Planned(date: at.addingTimeInterval(-Double(ro.early) * 60), title: name,
                                   body: tr("بعد \(ro.early) دقيقة: \(r.displayTitle)", "In \(ro.early) min: \(r.displayTitle)"),
                                   category: routineCategory, silent: ro.style == .quiet))
            }
            switch ro.style {
            case .gentle:
                out.append(Planned(date: at, title: name, body: gentle[i % gentle.count], category: routineCategory))
                out.append(Planned(date: at.addingTimeInterval(1800), title: name,
                                   body: tr("سويتها؟ اضغط «سويتها» وأسكت 🤫", "Done it? Tap “Did it” and I'll hush 🤫"), category: routineCategory))
            case .coach:
                let hype = streak > 0 ? tr("🔥 سلسلتك \(streak) يوم — لا تكسرها!", "🔥 \(streak)-day streak — don't break it!")
                                      : tr("💪 يلا نبدأ سلسلة جديدة اليوم!", "💪 Let's start a new streak today!")
                out.append(Planned(date: at, title: name, body: hype, category: routineCategory))
                out.append(Planned(date: at.addingTimeInterval(2700), title: name,
                                   body: tr("باقي فرصة اليوم ⏳ السلسلة تنتظرك.", "Still time today ⏳ your streak is waiting."), category: routineCategory))
            case .alarm:
                out.append(Planned(date: at, title: tr("⏰ الحين: ", "⏰ Now: ") + name, body: tr("قوم سوّها الحين!", "Go do it now!"), category: routineCategory))
                for m in [10, 20, 30] {
                    out.append(Planned(date: at.addingTimeInterval(Double(m) * 60), title: tr("⏰ للحين ما سويتها: ", "⏰ Still pending: ") + name,
                                       body: tr("بعد \(m) دقيقة… أكّد عشان أوقف.", "\(m) minutes later… confirm so I stop."), category: routineCategory))
                }
            case .quiet:
                out.append(Planned(date: at, title: name, body: tr("وقتها 🌙", "It's time 🌙"), category: routineCategory, silent: true))
            }
        }
        if let s = r.snoozedUntil, s > now {
            out.append(Planned(date: s, title: name, body: tr("رجعت أذكّرك 👀", "Reminding you again 👀"), category: routineCategory))
        }
        return out.filter { $0.date > now.addingTimeInterval(5) }.sorted { $0.date < $1.date }
    }

    static func plan(for r: Reminder, now: Date = Date()) -> [Planned] {
        if r.isRoutine { return routinePlan(for: r, now: now) }
        if let sub = r.subscription, r.kind == .subscription { return subscriptionPlan(for: r, sub: sub, now: now) }
        guard !r.done else { return [] }
        let name = r.displayTitle
        var out: [Planned] = []
        let cal = Calendar.current

        for days in [3, 2, 1] {
            let d = r.due.addingTimeInterval(-Double(days) * 86400)
            let body: String
            switch days {
            case 3: body = tr("باقي ٣ أيام على التسليم. خطط لها من الحين 💪", "3 days left. Plan it now 💪")
            case 2: body = tr("باقي يومين! لا تخليها لآخر لحظة.", "2 days left! Don't leave it to the last minute.")
            default: body = tr("باقي يوم واحد ⚠️ بكرة آخر يوم.", "1 day left ⚠️ Tomorrow is the last day.")
            }
            out.append(Planned(date: d, title: name, body: body))
        }

        // Last day nagging window
        let startOfDay = cal.startOfDay(for: r.due)
        var windowStart = startOfDay.addingTimeInterval(8 * 3600)
        if windowStart >= r.due { windowStart = r.due.addingTimeInterval(-6 * 3600) }
        let step = Double(max(1, r.nagHours)) * 3600
        var t = windowStart
        while t < r.due.addingTimeInterval(-15 * 60) {
            out.append(Planned(date: t, title: name,
                               body: tr("اليوم آخر يوم! سويتها؟ اضغط «خلصتها» عشان أقفل المهمة.",
                                        "Today is the last day! Done yet? Tap “Done” to close it.")))
            t = t.addingTimeInterval(step)
        }
        out.append(Planned(date: r.due, title: name,
                           body: tr("⏰ خلص الوقت الحين. سويتها؟", "⏰ Time's up now. Did you do it?")))

        // Overdue follow-ups
        for h in stride(from: 3, through: 24, by: 3) {
            out.append(Planned(date: r.due.addingTimeInterval(Double(h) * 3600), title: name,
                               body: tr("المهمة متأخرة. إذا خلصتها أكّد عشان أقفلها ✅",
                                        "This is overdue. Confirm when done so I can close it ✅")))
        }

        if let s = r.snoozedUntil, s > now {
            out.append(Planned(date: s, title: name, body: tr("رجعت أذكّرك 👀 سويتها؟", "Reminding you again 👀 Done yet?")))
            // Drop anything between now and the snooze time
            out = out.filter { $0.date >= s || $0.date == s }
        }
        return out.filter { $0.date > now.addingTimeInterval(5) }.sorted { $0.date < $1.date }
    }

    /// Subscriptions renew by themselves, so the warnings come *before* the charge, not after.
    private static func subscriptionPlan(for r: Reminder, sub: Subscription, now: Date) -> [Planned] {
        guard !r.done else { return [] }
        let name = r.displayTitle
        var out: [Planned] = []
        let warn = max(1, sub.warnDaysBefore)
        for days in Set([warn, 1]).sorted(by: >) {
            let when = r.due.addingTimeInterval(-Double(days) * 86400)
            let body = sub.planToCancel
                ? tr("باقي \(days) يوم على التجديد — كنت تبا تلغيه. الحين وقته ✂️", "\(days) day(s) to renewal — you wanted to cancel. Now's the time ✂️")
                : tr("\(name) بيتجدد بعد \(days) يوم بـ \(sub.priceText).", "\(name) renews in \(days) day(s) for \(sub.priceText).")
            out.append(Planned(date: when, title: name, body: body))
        }
        out.append(Planned(date: r.due, title: name,
                           body: sub.planToCancel
                                ? tr("اليوم التجديد! إذا ما ألغيته بينخصم \(sub.priceText) ⚠️", "Renews today! If you didn't cancel, \(sub.priceText) will be charged ⚠️")
                                : tr("تجدد اليوم بـ \(sub.priceText) 💳", "Renewed today for \(sub.priceText) 💳")))
        return out.filter { $0.date > now.addingTimeInterval(5) }.sorted { $0.date < $1.date }
    }

    /// Rebuilds every pending notification from both vault spaces (iOS allows 64 pending).
    static func rescheduleAll() {
        let center = UNUserNotificationCenter.current()
        let now = Date()
        var all: [(Planned, Reminder, VaultSpace)] = []
        for space in VaultSpace.allCases where VaultStorage.exists(space) {
            for r in RemindersStore.load(space) {
                for p in plan(for: r, now: now) { all.append((p, r, space)) }
            }
        }
        all.sort { $0.0.date < $1.0.date }
        center.removeAllPendingNotificationRequests()
        for (i, item) in all.prefix(maxPending).enumerated() {
            let (p, r, space) = item
            let content = UNMutableNotificationContent()
            content.title = p.title
            content.body = p.body
            content.sound = p.silent ? nil : UNNotificationSound(named: UNNotificationSoundName("notify.wav"))
            content.categoryIdentifier = p.category
            content.threadIdentifier = r.id.uuidString
            content.userInfo = ["rid": r.id.uuidString, "space": space.rawValue]
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: p.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: "rem.\(r.id.uuidString).\(i)", content: content, trigger: trigger))
        }
        WidgetBridge.update()
    }

    static func handleAction(_ action: String, userInfo: [AnyHashable: Any]) {
        guard let rid = (userInfo["rid"] as? String).flatMap(UUID.init(uuidString:)) else { return }
        let space = VaultSpace(rawValue: userInfo["space"] as? String ?? "real") ?? .real
        switch action {
        case "DONE":
            RemindersStore.update(space, rid) { r in
                // A subscription doesn't finish — it rolls on to the next charge.
                if let sub = r.subscription, r.kind == .subscription {
                    r.due = sub.cycle.next(after: r.due)
                    r.snoozedUntil = nil
                } else {
                    r.done = true
                    r.doneAt = Date()
                    r.snoozedUntil = nil
                }
            }
        case "SNOOZE":
            RemindersStore.update(space, rid) { $0.snoozedUntil = Date().addingTimeInterval(3600) }
        case "ROUTINE_DONE":
            RemindersStore.update(space, rid) { r in
                guard var ro = r.routine else { return }
                let k = Routine.dayKey(Date())
                if !ro.doneDays.contains(k) { ro.doneDays.append(k) }
                ro.doneDays = Array(ro.doneDays.suffix(400))
                r.routine = ro
                r.snoozedUntil = nil
            }
        case "ROUTINE_SKIP":
            RemindersStore.update(space, rid) { r in
                guard var ro = r.routine else { return }
                let k = Routine.dayKey(Date())
                if !ro.skipDays.contains(k) { ro.skipDays.append(k) }
                r.routine = ro
                r.snoozedUntil = nil
            }
        case "ROUTINE_SNOOZE":
            RemindersStore.update(space, rid) { $0.snoozedUntil = Date().addingTimeInterval(900) }
        default:
            return
        }
        rescheduleAll()
        LiveActivityManager.sync()
    }

    // MARK: Calendar

    static func addToCalendar(_ r: Reminder) async -> String? {
        let store = EKEventStore()
        guard (try? await store.requestWriteOnlyAccessToEvents()) == true else { return nil }
        let ev = EKEvent(eventStore: store)
        ev.title = r.displayTitle
        ev.notes = r.sensitivity == .secret ? nil : r.notes
        if r.kind == .appointment {
            ev.startDate = r.due
            ev.endDate = r.due.addingTimeInterval(3600)
        } else {
            ev.startDate = r.due.addingTimeInterval(-1800)
            ev.endDate = r.due
        }
        ev.calendar = store.defaultCalendarForNewEvents
        do {
            try store.save(ev, span: .thisEvent)
            return ev.eventIdentifier
        } catch {
            return nil
        }
    }
}

enum WidgetBridge {
    static func update() {
        let now = Date()
        let list = RemindersStore.load(.real)
            .map { r -> Reminder in
                var c = r
                if let n = r.routine?.next(after: now) { c.due = n }
                return c
            }
            .filter { !$0.done && $0.due > now.addingTimeInterval(-86400) && !($0.routine?.finished ?? false) }
            .sorted { $0.due < $1.due }
            .prefix(5)
        let items = list.map {
            WidgetShared.Item(id: $0.id.uuidString,
                              title: $0.sensitivity == .secret ? tr("🔒 مهمة سرية", "🔒 Secret task") : $0.title,
                              due: $0.due, icon: $0.kind.icon, secret: $0.sensitivity == .secret)
        }
        var payload = WidgetShared.Payload()
        payload.items = Array(items)
        payload.isArabic = AppLanguage.current == .ar
        payload.updated = now

        // Routine streak + today's progress
        let all = RemindersStore.load(.real)
        let routines = all.filter { $0.isRoutine && !($0.routine?.finished ?? false) }
        let todays = routines.filter { $0.routine?.scheduledToday ?? false }
        payload.totalToday = todays.count
        payload.doneToday = todays.filter { $0.routine?.isDone(on: now) ?? false }.count
        payload.streak = routines.compactMap { $0.routine?.streak(now: now) }.max() ?? 0
        let cal = Calendar.current
        payload.routines = todays.compactMap { r -> WidgetShared.RoutineItem? in
            guard let rt = r.routine, !rt.isSkipped(on: now),
                  let at = cal.date(bySettingHour: rt.hour, minute: rt.minute, second: 0, of: now) else { return nil }
            return WidgetShared.RoutineItem(id: r.id.uuidString,
                                            title: r.sensitivity == .secret ? tr("روتين سري", "Secret routine") : r.title,
                                            emoji: rt.emoji, at: at, done: rt.isDone(on: now))
        }
        .sorted { $0.at < $1.at }

        // Next subscription renewal and the monthly total in its currency
        let subs = all.filter { $0.isSubscription && !$0.done }.sorted { $0.due < $1.due }
        if let n = subs.first, let s = n.subscription {
            payload.subTitle = n.sensitivity == .secret ? tr("🔒 اشتراك", "🔒 Subscription") : n.title
            payload.subDue = n.due
            payload.subPrice = s.priceText
            let monthly = subs.compactMap { $0.subscription }.filter { $0.currency == s.currency }.reduce(0) { $0 + $1.monthlyCost }
            payload.subMonthly = Subscription.money(monthly, s.currency)
        }

        // The safety snapshot only changes while the vault is open; keep the last known values otherwise.
        let previous = WidgetShared.load()
        payload.lastBackup = previous.lastBackup
        payload.intruders = previous.intruders
        payload.accounts = previous.accounts
        payload.weak = previous.weak
        if let v = vault {
            payload.lastBackup = v.lastBackup
            payload.intruders = v.intruders
            payload.accounts = v.accounts
            payload.weak = v.weak
        }

        WidgetShared.save(payload)
        WidgetCenter.shared.reloadAllTimelines()
    }

    struct VaultSnapshot { var accounts: Int; var weak: Int; var intruders: Int; var lastBackup: Date? }
    /// Set by the app whenever the vault is open, so the safety widget has something to say.
    static var vault: VaultSnapshot?
}

/// The last-hour countdown in the Dynamic Island and on the Lock Screen.
///
/// It appears one hour before a task is due, and only for reminders that have "show in Dynamic
/// Island" switched on (the default). On iOS 26 and later the system starts it at that moment
/// by itself, even with the app closed. Older versions don't allow an app to start one from the
/// background, so there it starts the next time the app is open inside that hour, and a one-minute
/// timer keeps checking while the app stays open.
enum LiveActivityManager {
    static var enabled: Bool { UserDefaults.standard.object(forKey: "fx.liveActivity") as? Bool ?? true }
    static let lead: TimeInterval = 3600
    private static var timer: Timer?

    static func eligible(now: Date = Date()) -> [Reminder] {
        RemindersStore.load(.real)
            .filter { !$0.done && !$0.isRoutine && !$0.isSubscription && $0.showInIsland && $0.due > now }
            .sorted { $0.due < $1.due }
    }

    private static func attributes(_ t: Reminder) -> ReminderActivityAttributes {
        ReminderActivityAttributes(reminderID: t.id.uuidString,
                                   title: t.sensitivity == .secret ? tr("🔒 مهمة سرية", "🔒 Secret task") : t.title,
                                   icon: t.kind.icon,
                                   isArabic: AppLanguage.current == .ar,
                                   start: t.due.addingTimeInterval(-lead),
                                   kindTitle: t.kind.title)
    }

    static func sync() {
        let now = Date()
        let all = enabled ? eligible(now: now) : []
        // Running now: due inside the hour. Scheduled ahead (iOS 26+): the next few after that.
        let live = all.filter { $0.due.timeIntervalSince(now) <= lead }.prefix(1)
        var wanted = Set(live.map { $0.id.uuidString })
        var ahead: [Reminder] = []
        if #available(iOS 26.0, *) {
            ahead = Array(all.filter { $0.due.timeIntervalSince(now) > lead && $0.due.timeIntervalSince(now) < 7 * 86400 }.prefix(3))
            wanted.formUnion(ahead.map { $0.id.uuidString })
        }

        for act in Activity<ReminderActivityAttributes>.activities where !wanted.contains(act.attributes.reminderID) {
            Task { await act.end(nil, dismissalPolicy: .immediate) }
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let existing = Set(Activity<ReminderActivityAttributes>.activities.map { $0.attributes.reminderID })

        for t in live where !existing.contains(t.id.uuidString) {
            let content = ActivityContent(state: ReminderActivityAttributes.ContentState(due: t.due),
                                          staleDate: t.due.addingTimeInterval(lead))
            _ = try? Activity.request(attributes: attributes(t), content: content, pushType: nil)
        }
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            for t in ahead where !existing.contains(t.id.uuidString) {
                let content = ActivityContent(state: ReminderActivityAttributes.ContentState(due: t.due),
                                              staleDate: t.due.addingTimeInterval(lead))
                let alert = AlertConfiguration(title: LocalizedStringResource(stringLiteral: tr("باقي ساعة", "One hour left")),
                                               body: LocalizedStringResource(stringLiteral: t.sensitivity == .secret ? tr("مهمة سرية", "A secret task") : t.title),
                                               sound: .default)
                _ = try? Activity.request(attributes: attributes(t), content: content, pushType: nil,
                                          style: .standard, alertConfiguration: alert,
                                          start: t.due.addingTimeInterval(-lead))
            }
        }
        #endif
    }

    /// While the app is open, check every minute so a task that enters its last hour gets its
    /// countdown without waiting for the next launch.
    static func startWatching() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in sync() }
    }

    static func stopWatching() {
        timer?.invalidate()
        timer = nil
    }
}
