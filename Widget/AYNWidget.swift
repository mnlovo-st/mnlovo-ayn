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
            let due = context.state.due
            HStack(spacing: 12) {
                Image(systemName: context.attributes.icon)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [teal, indigo], startPoint: .top, endPoint: .bottom))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.white.opacity(0.08)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.title).font(wf(16, .bold)).foregroundStyle(.white).lineLimit(1)
                    Text(context.attributes.isArabic ? "آخر يوم — سويتها؟" : "Last day — done yet?")
                        .font(wf(12, .semibold)).foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Text(timerInterval: min(Date(), due)...due, countsDown: true)
                    .font(wf(20, .heavy))
                    .monospacedDigit()
                    .foregroundStyle(teal)
                    .frame(width: 90)
                    .multilineTextAlignment(.trailing)
            }
            .padding(16)
            .activityBackgroundTint(night.opacity(0.92))
            .activitySystemActionForegroundColor(teal)
        } dynamicIsland: { context in
            let due = context.state.due
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.attributes.icon).font(.system(size: 22, weight: .bold)).foregroundStyle(teal)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: min(Date(), due)...due, countsDown: true)
                        .font(wf(18, .heavy))
                        .monospacedDigit()
                        .foregroundStyle(teal)
                        .frame(width: 80)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.title)
                        .font(wf(15, .bold))
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "eye.fill").foregroundStyle(teal)
            } compactTrailing: {
                Text(timerInterval: min(Date(), due)...due, countsDown: true)
                    .monospacedDigit()
                    .font(wf(13, .bold))
                    .foregroundStyle(teal)
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "eye.fill").foregroundStyle(teal)
            }
            .keylineTint(teal)
        }
    }
}
