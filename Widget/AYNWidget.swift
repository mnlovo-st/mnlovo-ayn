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
        TasksEntry(date: Date(), payload: WidgetShared.Payload(items: [
            .init(id: "1", title: "واجب قواعد البيانات", due: Date().addingTimeInterval(86400 * 2), icon: "book.closed.fill", secret: false),
            .init(id: "2", title: "موعد", due: Date().addingTimeInterval(3600 * 5), icon: "calendar.badge.clock", secret: false)
        ]))
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
