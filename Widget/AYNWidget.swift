import AppIntents
import WidgetKit
import SwiftUI
import ActivityKit

private let teal = Color(red: 0.224, green: 0.902, blue: 0.784)
private let indigo = Color(red: 0.482, green: 0.424, blue: 1.0)
private let night = Color(red: 0.027, green: 0.031, blue: 0.051)

/// Somar Sans in the widget (falls back to the system font if missing).
private func wf(_ size: CGFloat, _ weight: Font.Weight) -> Font {
    let name: String
    switch weight {
    case .medium: name = "SomarSans-Medium"
    case .semibold: name = "SomarSans-SemiBold"
    case .bold: name = "SomarSans-Bold"
    case .heavy, .black: name = "SomarSans-ExtraBold"
    default: name = "SomarSans-Regular"
    }
    return .custom(name, fixedSize: size)
}

@main
struct SaverWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextTasksWidget()
        RoutinesWidget()
        CountdownWidget()
        StreakWidget()
        SubscriptionWidget()
        SecurityWidget()
        QuickOpenWidget()
        ReminderLiveActivity()
    }
}

// MARK: - Nothing from the app yet

/// Shown instead of "all clear" when no data from the app has reached the widget at all, so an empty
/// list never pretends to be an empty day.
private struct Linked<Content: View>: View {
    let p: WidgetShared.Payload
    @ViewBuilder var content: Content
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if p.live {
            content
        } else {
            switch family {
            case .accessoryCircular:
                Image(systemName: "eye.trianglebadge.exclamationmark").font(.system(size: 20, weight: .bold))
            case .accessoryInline:
                Text(p.isArabic ? "افتح SAVER مرة" : "Open SAVER once")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Label("SAVER", systemImage: "eye.fill").font(wf(12, .bold))
                    Text(p.isArabic ? "افتح التطبيق مرة عشان يوصل الودجت" : "Open the app once to link this widget")
                        .font(wf(11, .medium))
                }
            default:
                VStack(spacing: 8) {
                    Image(systemName: "eye.trianglebadge.exclamationmark")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(LinearGradient(colors: [teal, indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text(p.isArabic ? "الودجت بعده ما وصل" : "Not linked yet")
                        .font(wf(14, .bold)).foregroundStyle(.white)
                    Text(p.isArabic ? "افتح MNLOVO SAVER مرة وحدة" : "Open MNLOVO SAVER once")
                        .font(wf(11, .medium)).foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - The ✓ button

/// Tick a task or routine off right from the widget. Secret ones get a lock instead: tapping the
/// widget there opens the app, which asks for Face ID first.
private struct TickButton: View {
    let id: String
    let routine: Bool
    let secret: Bool
    var tint: Color = .white

    var body: some View {
        if secret {
            Image(systemName: "lock.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
                .frame(width: 22, height: 22)
        } else {
            Button(intent: CompleteFromWidgetIntent(id: id, routine: routine)) {
                Image(systemName: "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint.opacity(0.6))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .invalidatableContent()
        }
    }
}

// MARK: - Home / Lock Screen widget

struct TasksEntry: TimelineEntry {
    let date: Date
    let payload: WidgetShared.Payload
}

struct TasksProvider: TimelineProvider {
    func placeholder(in context: Context) -> TasksEntry {
        TasksEntry(date: Date(), payload: WidgetShared.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (TasksEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : TasksEntry(date: Date(), payload: WidgetShared.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TasksEntry>) -> Void) {
        let now = Date()
        let p = WidgetShared.load()
        // One entry now, plus one at each routine time and task time in the next few hours, so
        // "next up" and the colours move on by themselves without the app being opened.
        var moments = p.routines.map(\.at) + p.items.map(\.due)
        moments.append(Calendar.current.startOfDay(for: now).addingTimeInterval(86400))   // midnight
        let upcoming = Array(Set(moments.filter { $0 > now && $0 < now.addingTimeInterval(12 * 3600) })).sorted().prefix(12)
        WidgetShared.beat(p)   // lets the app see that the widget ran and what reached it
        let entries = [TasksEntry(date: now, payload: p)] + upcoming.map { TasksEntry(date: $0, payload: p) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
    }
}

struct NextTasksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.kind, provider: TasksProvider()) { entry in
            Linked(p: entry.payload) { TasksWidgetView(entry: entry) }
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [night, Color(red: 0.06, green: 0.06, blue: 0.12)], startPoint: .top, endPoint: .bottom)
                }
        }
        .configurationDisplayName("MNLOVO SAVER")
        .description("Next reminders · التذكيرات القادمة")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

struct TasksWidgetView: View {
    var entry: TasksEntry
    @Environment(\.widgetFamily) private var family

    private var ar: Bool { entry.payload.isArabic }
    private var items: [WidgetShared.Item] { entry.payload.items.filter { $0.due > entry.date.addingTimeInterval(-86400) } }

    private func color(_ due: Date) -> Color {
        let left = due.timeIntervalSince(entry.date)
        if left < 0 { return Color(red: 1, green: 0.35, blue: 0.43) }
        if left < 86400 { return Color(red: 1, green: 0.48, blue: 0.27) }
        if left < 3 * 86400 { return Color(red: 1, green: 0.75, blue: 0.28) }
        return teal
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            if let f = items.first {
                Text("👁 \(f.title) · \(f.due, style: .relative)")
            } else {
                Text(ar ? "👁 ما في مهام" : "👁 All clear")
            }
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "eye.fill").font(.system(size: 12))
                    Text("\(items.count)").font(wf(18, .bold))
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("SAVER", systemImage: "eye.fill").font(wf(12, .bold))
                if let f = items.first {
                    Text(f.title).font(wf(14, .semibold)).lineLimit(1)
                    Text(f.due, style: .relative).font(wf(12, .regular))
                } else {
                    Text(ar ? "ما في مهام 🎉" : "All clear 🎉").font(wf(14, .semibold))
                }
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "eye.fill").foregroundStyle(LinearGradient(colors: [teal, indigo], startPoint: .leading, endPoint: .trailing))
                    Text(ar ? "التذكيرات" : "Reminders").font(wf(14, .heavy)).foregroundStyle(.white)
                    Spacer()
                    Text("\(items.count)").font(wf(13, .bold)).foregroundStyle(.white.opacity(0.5))
                }
                if items.isEmpty {
                    Spacer()
                    Text(ar ? "ولا شي 🎉" : "All clear 🎉").font(wf(16, .bold)).foregroundStyle(.white)
                    Spacer()
                } else if family == .systemSmall {
                    ForEach(items.prefix(2)) { item in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2).fill(color(item.due)).frame(width: 4, height: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title).font(wf(13, .bold)).foregroundStyle(.white).lineLimit(1)
                                Text(item.due, style: .relative).font(wf(11, .semibold)).foregroundStyle(color(item.due))
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            TickButton(id: item.id, routine: item.routine ?? false, secret: item.secret, tint: color(item.due))
                        }
                    }
                    Spacer(minLength: 0)
                } else {
                    // Wide sizes: one line per task — title on one side, time left on the other — so
                    // the header never gets pushed off the top.
                    ForEach(items.prefix(family == .systemLarge ? 7 : 3)) { item in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2).fill(color(item.due)).frame(width: 4, height: 20)
                            Text(item.title).font(wf(13, .bold)).foregroundStyle(.white).lineLimit(1)
                            Spacer(minLength: 6)
                            Text(item.due, style: .relative).font(wf(11, .semibold)).foregroundStyle(color(item.due))
                                .lineLimit(1).multilineTextAlignment(.trailing).frame(maxWidth: 110, alignment: .trailing)
                            TickButton(id: item.id, routine: item.routine ?? false, secret: item.secret, tint: color(item.due))
                        }
                        .frame(height: 24)
                    }
                    Spacer(minLength: 0)
                }
            }
            .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
        }
    }
}

// MARK: - Live Activity (Dynamic Island + Lock Screen)

struct ReminderLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReminderActivityAttributes.self) { context in
            LockScreenActivity(attrs: context.attributes, due: context.state.due)
                .activityBackgroundTint(night.opacity(0.94))
                .activitySystemActionForegroundColor(teal)
        } dynamicIsland: { context in
            let a = context.attributes
            let due = context.state.due
            let ar = a.isArabic
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ActivityIcon(icon: a.icon, size: 46)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Countdown(due: due, size: 22)
                            .frame(width: 96, alignment: .trailing)
                        Text(ar ? "باقي" : "left")
                            .font(wf(11, .semibold)).foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(a.title)
                            .font(wf(16, .bold)).foregroundStyle(.white)
                            .lineLimit(1)
                        Text(a.kindTitle.isEmpty ? (a.badge.isEmpty ? (ar ? "آخر ساعة" : "Last hour") : a.badge)
                             : "\(a.kindTitle) · \(a.badge.isEmpty ? (ar ? "آخر ساعة" : "last hour") : a.badge)")
                            .font(wf(11, .semibold)).foregroundStyle(teal.opacity(0.85))
                            .lineLimit(1)
                    }
                    .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        ProgressView(timerInterval: a.start...max(a.start.addingTimeInterval(1), due), countsDown: true) {
                            EmptyView()
                        } currentValueLabel: {
                            EmptyView()
                        }
                        .progressViewStyle(.linear)
                        .tint(LinearGradient(colors: [teal, indigo], startPoint: .leading, endPoint: .trailing))
                        HStack(spacing: 6) {
                            Image(systemName: "eye.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(teal)
                            if a.title.hasPrefix("🔒") {
                                // secret: confirming needs Face ID, so it's done in the app
                                Text(ar ? "خلصتها؟ افتح التطبيق وأكّد" : "Done? Open the app to confirm")
                                    .font(wf(11, .medium)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                                Spacer(minLength: 0)
                            } else {
                                Text(ar ? "خلصتها؟" : "Done?")
                                    .font(wf(12, .semibold)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                                Spacer(minLength: 0)
                                Button(intent: CompleteFromWidgetIntent(id: a.reminderID, routine: false)) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy))
                                        Text(ar ? "تم" : "Done").font(wf(12, .bold))
                                    }
                                    .foregroundStyle(night)
                                    .padding(.horizontal, 14).padding(.vertical, 5)
                                    .background(Capsule().fill(LinearGradient(colors: [teal, indigo], startPoint: .leading, endPoint: .trailing)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 2)
                }
            } compactLeading: {
                ActivityIcon(icon: "eye.fill", size: 22)
            } compactTrailing: {
                // A timer Text claims the widest time it could ever show, which stretched the
                // island to both edges. An invisible "00:00" decides the width instead, and the
                // live timer is drawn over it.
                Text(due.timeIntervalSinceNow >= 3600 ? "0:00:00" : "00:00")
                    .font(wf(13, .heavy))
                    .monospacedDigit()
                    .hidden()
                    .overlay(alignment: .trailing) { Countdown(due: due, size: 13) }
                    .fixedSize()
            } minimal: {
                ProgressView(timerInterval: a.start...max(a.start.addingTimeInterval(1), due), countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    Image(systemName: "eye.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(teal)
                }
                .progressViewStyle(.circular)
                .tint(teal)
            }
            .keylineTint(teal)
        }
    }
}

/// Countdown text that keeps a fixed width (so it never pushes the layout around).
private struct Countdown: View {
    var due: Date
    var size: CGFloat
    var body: some View {
        Text(timerInterval: min(Date(), due)...due, countsDown: true, showsHours: true)
            .font(wf(size, .heavy))
            .monospacedDigit()
            .foregroundStyle(teal)
            .multilineTextAlignment(.trailing)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .environment(\.layoutDirection, .leftToRight)
    }
}

/// The task icon in a soft gradient ring.
private struct ActivityIcon: View {
    var icon: String
    var size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [teal.opacity(0.25), indigo.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().strokeBorder(LinearGradient(colors: [teal, indigo], startPoint: .top, endPoint: .bottom), lineWidth: max(1, size * 0.05))
            Image(systemName: icon)
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundStyle(LinearGradient(colors: [teal, indigo], startPoint: .top, endPoint: .bottom))
        }
        .frame(width: size, height: size)
    }
}

private struct LockScreenActivity: View {
    var attrs: ReminderActivityAttributes
    var due: Date

    var body: some View {
        let ar = attrs.isArabic
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "eye.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(teal)
                Text("MNLOVO SAVER").font(wf(11, .heavy)).foregroundStyle(.white.opacity(0.55)).tracking(1)
                Spacer()
                Text(attrs.badge.isEmpty ? (ar ? "آخر ساعة" : "LAST HOUR") : attrs.badge)
                    .font(wf(10, .heavy)).foregroundStyle(night)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(LinearGradient(colors: [teal, indigo], startPoint: .leading, endPoint: .trailing)))
            }
            .environment(\.layoutDirection, .leftToRight)
            HStack(spacing: 12) {
                ActivityIcon(icon: attrs.icon, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(attrs.title).font(wf(17, .bold)).foregroundStyle(.white).lineLimit(1)
                    Text(ar ? "سويتها؟ أكّد من التطبيق" : "Done yet? Confirm in the app")
                        .font(wf(12, .semibold)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 0) {
                    Countdown(due: due, size: 24)
                        .frame(width: 112, alignment: .trailing)
                    Text(ar ? "باقي" : "left").font(wf(10, .semibold)).foregroundStyle(.white.opacity(0.45))
                }
            }
            .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
            ProgressView(timerInterval: attrs.start...max(attrs.start.addingTimeInterval(1), due), countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(LinearGradient(colors: [teal, indigo], startPoint: .leading, endPoint: .trailing))
        }
        .padding(16)
    }
}


// MARK: - Routine streak

struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.streakKind, provider: TasksProvider()) { entry in
            Linked(p: entry.payload) { StreakView(p: entry.payload) }
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [Color(red: 0.16, green: 0.07, blue: 0.03), night], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
        }
        .configurationDisplayName("MNLOVO · Routine streak")
        .description("Routine streak · سلسلة الروتين")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct StreakView: View {
    var p: WidgetShared.Payload
    @Environment(\.widgetFamily) private var family

    private var progress: Double {
        p.totalToday == 0 ? 0 : Double(p.doneToday) / Double(p.totalToday)
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Gauge(value: progress) { Image(systemName: "flame.fill") }
                    .gaugeStyle(.accessoryCircularCapacity)
                Text("\(p.streak)").font(.system(size: 15, weight: .bold)).offset(y: 1)
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("\(p.streak) " + (p.isArabic ? "يوم" : "days"), systemImage: "flame.fill").font(.headline)
                Text((p.isArabic ? "اليوم " : "Today ") + "\(p.doneToday)/\(p.totalToday)").font(.caption)
            }
        default:
            VStack(spacing: 6) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.12), lineWidth: 8)
                    Circle().trim(from: 0, to: max(0.02, progress))
                        .stroke(LinearGradient(colors: [Color.orange, Color(red: 1, green: 0.35, blue: 0.2)],
                                               startPoint: .top, endPoint: .bottom),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("🔥").font(.system(size: 18))
                        Text("\(p.streak)").font(wf(24, .heavy)).foregroundStyle(.white)
                    }
                }
                .frame(width: 84, height: 84)
                Text(p.totalToday == 0 ? (p.isArabic ? "ما عندك روتين اليوم" : "No routines today")
                                       : (p.isArabic ? "اليوم \(p.doneToday) من \(p.totalToday)" : "Today \(p.doneToday) of \(p.totalToday)"))
                    .font(wf(11, .semibold)).foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .environment(\.layoutDirection, p.isArabic ? .rightToLeft : .leftToRight)
        }
    }
}

// MARK: - Next subscription renewal

struct SubscriptionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.subsKind, provider: TasksProvider()) { entry in
            Linked(p: entry.payload) { SubscriptionView(p: entry.payload) }
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [Color(red: 0.07, green: 0.05, blue: 0.16), night], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
        }
        .configurationDisplayName("MNLOVO · Subscriptions")
        .description("Next renewal · أقرب تجديد")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct SubscriptionView: View {
    var p: WidgetShared.Payload
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if p.subTitle.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "creditcard").font(.system(size: 22)).foregroundStyle(indigo)
                Text(p.isArabic ? "ما عندك اشتراكات" : "No subscriptions").font(wf(12, .semibold)).foregroundStyle(.white.opacity(0.7))
            }
        } else if family == .accessoryRectangular {
            VStack(alignment: .leading, spacing: 2) {
                Label(p.subTitle, systemImage: "creditcard.fill").font(.headline).lineLimit(1)
                if let d = p.subDue { Text(d, style: .relative).font(.caption) }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "creditcard.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(indigo)
                    Text(p.isArabic ? "الياي" : "Next up").font(wf(11, .bold)).foregroundStyle(.white.opacity(0.6))
                    Spacer()
                }
                Text(p.subTitle).font(wf(16, .heavy)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
                if let d = p.subDue {
                    Text(d, style: .relative)
                        .font(wf(13, .semibold)).foregroundStyle(teal)
                        .environment(\.layoutDirection, .leftToRight)
                }
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline) {
                    Text(p.subPrice).font(wf(15, .bold)).foregroundStyle(.white)
                    Spacer()
                    if !p.subMonthly.isEmpty {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(p.isArabic ? "بالشهر" : "monthly").font(wf(9, .medium)).foregroundStyle(.white.opacity(0.5))
                            Text(p.subMonthly).font(wf(12, .bold)).foregroundStyle(.white.opacity(0.85))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.layoutDirection, p.isArabic ? .rightToLeft : .leftToRight)
        }
    }
}

// MARK: - One-tap open

struct QuickOpenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.openKind, provider: TasksProvider()) { entry in
            QuickOpenView(isArabic: entry.payload.isArabic)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [night, Color(red: 0.05, green: 0.10, blue: 0.12)], startPoint: .top, endPoint: .bottom)
                }
        }
        .configurationDisplayName("MNLOVO · Quick open")
        .description("Open the vault · فتح الخزنة")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct QuickOpenView: View {
    var isArabic: Bool
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .accessoryCircular {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "lock.fill").font(.system(size: 18, weight: .bold))
            }
        } else {
            VStack(spacing: 8) {
                ZStack {
                    Circle().fill(teal.opacity(0.14)).frame(width: 56, height: 56)
                    Circle().strokeBorder(LinearGradient(colors: [teal, indigo], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
                        .frame(width: 56, height: 56)
                    Image(systemName: "lock.fill").font(.system(size: 22, weight: .bold)).foregroundStyle(teal)
                }
                Text("MNLOVO SAVER").font(wf(10, .heavy)).foregroundStyle(.white.opacity(0.8)).tracking(1)
                Text(isArabic ? "اضغط لفتح الخزنة" : "Tap to open the vault")
                    .font(wf(10, .medium)).foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }
}


// MARK: - Shared bits for the new widgets

private func bg(_ top: Color) -> some View {
    LinearGradient(colors: [top, night], startPoint: .topLeading, endPoint: .bottomTrailing)
}

private func header(_ title: String, _ icon: String, _ tint: Color, trailing: String? = nil) -> some View {
    HStack(spacing: 6) {
        Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(tint)
        Text(title).font(wf(13, .heavy)).foregroundStyle(.white)
        Spacer(minLength: 0)
        if let trailing { Text(trailing).font(wf(12, .bold)).foregroundStyle(.white.opacity(0.5)) }
    }
}

// MARK: - Today's routines

struct RoutinesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.routinesKind, provider: TasksProvider()) { entry in
            Linked(p: entry.payload) { RoutinesView(entry: entry) }
                .containerBackground(for: .widget) { bg(Color(red: 0.03, green: 0.12, blue: 0.11)) }
        }
        .configurationDisplayName("MNLOVO · Routines")
        .description("Today's routines · روتين اليوم")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular])
    }
}

struct RoutinesView: View {
    var entry: TasksEntry
    @Environment(\.widgetFamily) private var family
    private var p: WidgetShared.Payload { entry.payload }
    private var ar: Bool { p.isArabic }
    private var done: Int { p.routines.filter(\.done).count }
    private var next: WidgetShared.RoutineItem? { p.routines.first { !$0.done && $0.at >= entry.date.addingTimeInterval(-1800) } }
    private var limit: Int { family == .systemLarge ? 8 : (family == .systemMedium ? 3 : 2) }

    /// What's left today: the ones coming up first (nearest at the top), then any whose time passed
    /// without being ticked. Done ones leave the list so the next one gets the room.
    private var left: [WidgetShared.RoutineItem] {
        let pending = p.routines.filter { !$0.done }
        let cut = entry.date.addingTimeInterval(-1800)
        return pending.filter { $0.at >= cut }.sorted { $0.at < $1.at }
             + pending.filter { $0.at < cut }.sorted { $0.at > $1.at }
    }
    private func missed(_ r: WidgetShared.RoutineItem) -> Bool { r.at < entry.date.addingTimeInterval(-1800) }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Gauge(value: p.routines.isEmpty ? 0 : Double(done) / Double(p.routines.count)) {
                    Image(systemName: "checklist")
                }
                .gaugeStyle(.accessoryCircularCapacity)
                Text("\(done)/\(p.routines.count)").font(.system(size: 12, weight: .bold))
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label(ar ? "الروتين \(done)/\(p.routines.count)" : "Routines \(done)/\(p.routines.count)", systemImage: "checklist")
                    .font(.headline)
                if let n = next {
                    Text("\(n.emoji) \(n.title)").font(.body).lineLimit(1)
                    Text(n.at, style: .time).font(.caption)
                } else {
                    Text(p.routines.isEmpty ? (ar ? "ما عندك روتين اليوم" : "Nothing today") : (ar ? "خلّصت كل شي ✓" : "All done ✓"))
                        .font(.caption)
                }
            }
        default:
            VStack(alignment: .leading, spacing: 7) {
                header(ar ? "روتين اليوم" : "Today", "checklist", teal, trailing: "\(done)/\(p.routines.count)")
                if p.routines.isEmpty {
                    Spacer()
                    Text(ar ? "ما عندك روتين اليوم" : "No routines today").font(wf(14, .bold)).foregroundStyle(.white.opacity(0.8))
                    Spacer()
                } else {
                    // a thin progress line under the header
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.1))
                            Capsule().fill(LinearGradient(colors: [teal, indigo], startPoint: .leading, endPoint: .trailing))
                                .frame(width: g.size.width * CGFloat(done) / CGFloat(max(1, p.routines.count)))
                        }
                    }
                    .frame(height: 4)
                    if left.isEmpty {
                        Spacer(minLength: 0)
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(teal)
                            Text(ar ? "خلّصت روتين اليوم كله" : "All done for today").font(wf(14, .bold)).foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                    } else if family == .systemSmall {
                        ForEach(left.prefix(limit)) { r in
                            HStack(spacing: 8) {
                                Text(r.emoji).font(.system(size: 15))
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(r.title).font(wf(13, .bold)).foregroundStyle(missed(r) ? .white.opacity(0.5) : .white)
                                        .lineLimit(1)
                                    Text(r.at, style: .time).font(wf(10, .semibold))
                                        .foregroundStyle(r.id == next?.id ? teal : .white.opacity(0.45))
                                }
                                Spacer(minLength: 0)
                                TickButton(id: r.id, routine: true, secret: r.secret ?? false, tint: teal)
                            }
                        }
                    } else {
                        ForEach(left.prefix(limit)) { r in
                            HStack(spacing: 8) {
                                Text(r.emoji).font(.system(size: 15))
                                Text(r.title).font(wf(13, .bold)).foregroundStyle(missed(r) ? .white.opacity(0.5) : .white)
                                    .lineLimit(1)
                                Spacer(minLength: 6)
                                Text(r.at, style: .time).font(wf(11, .semibold))
                                    .foregroundStyle(r.id == next?.id ? teal : .white.opacity(0.45))
                                TickButton(id: r.id, routine: true, secret: r.secret ?? false, tint: teal)
                            }
                            .frame(height: 22)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
        }
    }
}

// MARK: - Big countdown to the next task

struct CountdownWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.countdownKind, provider: TasksProvider()) { entry in
            Linked(p: entry.payload) { CountdownView(entry: entry) }
                .containerBackground(for: .widget) { bg(Color(red: 0.12, green: 0.05, blue: 0.03)) }
        }
        .configurationDisplayName("MNLOVO · Countdown")
        .description("Time left on the next task · كم باقي على المهمة الياية")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
    }
}

struct CountdownView: View {
    var entry: TasksEntry
    @Environment(\.widgetFamily) private var family
    private var ar: Bool { entry.payload.isArabic }
    private var next: WidgetShared.Item? { entry.payload.items.first { $0.due > entry.date } }

    var body: some View {
        if let n = next {
            switch family {
            case .accessoryInline:
                Text("⏳ \(n.title) · \(n.due, style: .relative)")
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Image(systemName: n.icon).font(.system(size: 11, weight: .bold))
                        Text(n.due, style: .timer).font(.system(size: 11, weight: .bold)).monospacedDigit()
                            .multilineTextAlignment(.center).minimumScaleFactor(0.6)
                    }
                    .padding(4)
                }
            default:
                VStack(alignment: .leading, spacing: 6) {
                    header(ar ? "باقي" : "Left", "hourglass", Color.orange)
                    Spacer(minLength: 0)
                    Text(n.due, style: .relative)
                        .font(wf(22, .heavy)).foregroundStyle(.white)
                        .minimumScaleFactor(0.5).lineLimit(2)
                        .environment(\.layoutDirection, .leftToRight)
                    HStack(spacing: 5) {
                        Image(systemName: n.icon).font(.system(size: 11, weight: .bold)).foregroundStyle(Color.orange)
                        Text(n.title).font(wf(12, .bold)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 22)).foregroundStyle(teal)
                if family != .accessoryInline && family != .accessoryCircular {
                    Text(ar ? "ولا مهمة قريبة" : "Nothing coming up").font(wf(12, .semibold)).foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }
}

// MARK: - Safety at a glance

struct SecurityWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.securityKind, provider: TasksProvider()) { entry in
            Linked(p: entry.payload) { SecurityView(p: entry.payload, now: entry.date) }
                .containerBackground(for: .widget) { bg(Color(red: 0.04, green: 0.06, blue: 0.14)) }
        }
        .configurationDisplayName("MNLOVO · Safety")
        .description("Backup, weak passwords, intruders · حالة الأمان")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct SecurityView: View {
    var p: WidgetShared.Payload
    var now: Date
    @Environment(\.widgetFamily) private var family
    private var ar: Bool { p.isArabic }

    /// Backup older than three days counts as a problem worth showing.
    private var backupStale: Bool { p.lastBackup.map { now.timeIntervalSince($0) > 3 * 86400 } ?? true }
    private var allGood: Bool { !backupStale && p.weak == 0 && p.intruders == 0 }

    private func row(_ icon: String, _ text: String, ok: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold))
                .foregroundStyle(ok ? teal : Color(red: 1, green: 0.55, blue: 0.3))
                .frame(width: 14)
            Text(text).font(wf(11, .semibold)).foregroundStyle(.white.opacity(0.85)).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
    }

    private var backupText: String {
        guard let d = p.lastBackup else { return ar ? "ما فيه نسخة احتياطية" : "No backup yet" }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: ar ? "ar" : "en")
        f.unitsStyle = .short
        return (ar ? "نسخة: " : "Backup: ") + f.localizedString(for: d, relativeTo: now)
    }

    var body: some View {
        if family == .accessoryRectangular {
            VStack(alignment: .leading, spacing: 2) {
                Label(allGood ? (ar ? "كل شي سليم" : "All good") : (ar ? "يحتاج انتباه" : "Needs attention"),
                      systemImage: allGood ? "checkmark.shield.fill" : "exclamationmark.shield.fill").font(.headline)
                Text(backupText).font(.caption)
                if p.intruders > 0 { Text(ar ? "\(p.intruders) محاولة دخول" : "\(p.intruders) intrusion attempts").font(.caption) }
            }
        } else {
            VStack(alignment: .leading, spacing: 7) {
                header(ar ? "الأمان" : "Safety", allGood ? "checkmark.shield.fill" : "exclamationmark.shield.fill",
                       allGood ? teal : Color.orange)
                row("icloud.fill", backupText, ok: !backupStale)
                row("key.fill", p.weak == 0 ? (ar ? "كلمات السر قوية" : "Passwords look strong")
                                            : (ar ? "\(p.weak) كلمة سر تحتاج تغيير" : "\(p.weak) passwords to change"), ok: p.weak == 0)
                row("eye.trianglebadge.exclamationmark.fill",
                    p.intruders == 0 ? (ar ? "ما فيه متطفلين" : "No intruders") : (ar ? "\(p.intruders) محاولة دخول" : "\(p.intruders) attempts"),
                    ok: p.intruders == 0)
                if family == .systemMedium {
                    row("person.text.rectangle.fill", ar ? "\(p.accounts) حساب محفوظ" : "\(p.accounts) accounts saved", ok: true)
                }
                Spacer(minLength: 0)
            }
            .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
        }
    }
}
