import WidgetKit
import SwiftUI
import ActivityKit

private let teal = Color(red: 0.224, green: 0.902, blue: 0.784)
private let indigo = Color(red: 0.482, green: 0.424, blue: 1.0)
private let night = Color(red: 0.027, green: 0.031, blue: 0.051)

@main
struct AYNWidgetBundle: WidgetBundle {
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
        .configurationDisplayName("AYN")
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
                    Text("\(items.count)").font(.system(size: 18, weight: .bold, design: .rounded))
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("AYN", systemImage: "eye.fill").font(.system(size: 12, weight: .bold, design: .rounded))
                if let f = items.first {
                    Text(f.title).font(.system(size: 14, weight: .semibold, design: .rounded)).lineLimit(1)
                    Text(f.due, style: .relative).font(.system(size: 12, design: .rounded))
                } else {
                    Text(ar ? "ما في مهام 🎉" : "All clear 🎉").font(.system(size: 14, weight: .semibold, design: .rounded))
                }
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "eye.fill").foregroundStyle(LinearGradient(colors: [teal, indigo], startPoint: .leading, endPoint: .trailing))
                    Text(ar ? "التذكيرات" : "Reminders").font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                    Spacer()
                    Text("\(items.count)").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.5))
                }
                if items.isEmpty {
                    Spacer()
                    Text(ar ? "ولا شي 🎉" : "All clear 🎉").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Spacer()
                } else {
                    ForEach(items.prefix(family == .systemSmall ? 2 : 3)) { item in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2).fill(color(item.due)).frame(width: 4, height: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                                Text(item.due, style: .relative).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(color(item.due))
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
                    Text(context.attributes.title).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                    Text(context.attributes.isArabic ? "آخر يوم — سويتها؟" : "Last day — done yet?")
                        .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Text(timerInterval: min(Date(), due)...due, countsDown: true)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
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
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(teal)
                        .frame(width: 80)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "eye.fill").foregroundStyle(teal)
            } compactTrailing: {
                Text(timerInterval: min(Date(), due)...due, countsDown: true)
                    .monospacedDigit()
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(teal)
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "eye.fill").foregroundStyle(teal)
            }
            .keylineTint(teal)
        }
    }
}
