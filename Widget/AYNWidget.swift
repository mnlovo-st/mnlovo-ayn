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
        StreakWidget()
        SubscriptionWidget()
        QuickOpenWidget()
        ReminderLiveActivity()
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
        let entry = TasksEntry(date: Date(), payload: WidgetShared.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

struct NextTasksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.kind, provider: TasksProvider()) { entry in
            TasksWidgetView(entry: entry)
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
                } else {
                    ForEach(items.prefix(family == .systemSmall ? 2 : 3)) { item in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2).fill(color(item.due)).frame(width: 4, height: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title).font(wf(13, .bold)).foregroundStyle(.white).lineLimit(1)
                                Text(item.due, style: .relative).font(wf(11, .semibold)).foregroundStyle(color(item.due))
                            }
                            Spacer(minLength: 0)
                        }
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
                        Text(a.kindTitle.isEmpty ? (ar ? "آخر يوم" : "Last day") : (ar ? "\(a.kindTitle) · آخر يوم" : "\(a.kindTitle) · last day"))
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
                        HStack(spacing: 5) {
                            Image(systemName: "eye.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(teal)
                            Text(ar ? "خلصتها؟ افتح التطبيق وأكّد عشان أوقف التذكير" : "Done? Open the app and confirm to stop reminders")
                                .font(wf(11, .medium)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                        }
                        .environment(\.layoutDirection, ar ? .rightToLeft : .leftToRight)
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 2)
                }
            } compactLeading: {
                ActivityIcon(icon: "eye.fill", size: 22)
            } compactTrailing: {
                Countdown(due: due, size: 13)
                    .frame(width: 54, alignment: .trailing)
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
                Text(ar ? "آخر يوم" : "LAST DAY")
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
            StreakView(p: entry.payload)
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
            SubscriptionView(p: entry.payload)
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
                    Text(p.isArabic ? "الجاي" : "Next up").font(wf(11, .bold)).foregroundStyle(.white.opacity(0.6))
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
