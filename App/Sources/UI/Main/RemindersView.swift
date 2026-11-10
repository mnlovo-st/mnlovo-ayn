import SwiftUI
import ActivityKit

struct RemindersView: View {
    @EnvironmentObject var state: AppState
    @State private var segment = 0          // 0 upcoming, 1 overdue, 2 done
    @State private var editing: Reminder?
    @State private var confirming: Reminder?
    @State private var revealed: Set<UUID> = []
    @State private var secretAction: SecretAction?
    @State private var celebrate = false
    @AppStorage("intro.reminders.seen") private var introSeen = false
    @State private var showIntro = false

    private var now: Date { Date() }

    private var oneOff: [Reminder] { state.reminders.filter { !$0.isRoutine } }
    private var routines: [Reminder] { state.reminders.filter { $0.isRoutine && !($0.routine?.finished ?? false) } }
    private var upcoming: [Reminder] { oneOff.filter { !$0.done && $0.due >= now }.sorted { $0.due < $1.due } }
    private var overdue: [Reminder] { oneOff.filter { !$0.done && $0.due < now }.sorted { $0.due < $1.due } }
    private var finished: [Reminder] { oneOff.filter { $0.done }.sorted { ($0.doneAt ?? $0.due) > ($1.doneAt ?? $1.due) } }

    private func newRoutine() -> Reminder {
        var r = Reminder(title: "", due: Date())
        r.kind = .routine
        r.routine = Routine()
        r.due = r.routine?.next() ?? Date()
        return r
    }

    private var list: [Reminder] { [upcoming, overdue, finished][segment] }

    private var weekProgress: (done: Int, total: Int) {
        let start = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        let end = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        let inRange = oneOff.filter { $0.due >= start && $0.due <= end }
        return (inRange.filter { $0.done }.count, inRange.count)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                TabHeader(title: MainTab.reminders.title,
                          subtitle: todaySummary) {
                    Menu {
                        Button {
                            editing = Reminder(title: "", due: Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date())
                        } label: { Label(tr("تذكير (موعد، مهمة، واجب)", "Reminder (appointment, task, homework)"), systemImage: "bell.badge.fill") }
                        Button { editing = newRoutine() } label: {
                            Label(tr("روتين يومي / أسبوعي", "Daily / weekly routine"), systemImage: "repeat.circle.fill")
                        }
                        Button { showIntro = true } label: { Label(tr("كيف تشتغل التذكيرات؟", "How do reminders work?"), systemImage: "play.circle") }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Theme.bg)
                            .frame(width: 42, height: 42)
                            .background(Circle().fill(Theme.gradient))
                    }
                }

                summaryCard

                if !routines.isEmpty {
                    RoutineStrip(routines: routines, onEdit: { editing = $0 }, onAdd: { editing = newRoutine() })
                }

                Picker("", selection: $segment) {
                    Text(tr("القادمة (\(upcoming.count))", "Upcoming (\(upcoming.count))")).tag(0)
                    Text(tr("المتأخرة (\(overdue.count))", "Overdue (\(overdue.count))")).tag(1)
                    Text(tr("المنجزة", "Done")).tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .onChange(of: segment) { _, _ in FX.toggle() }

                if list.isEmpty {
                    EmptyStateView(mood: segment == 1 ? .happy : .sleepy,
                                   title: [tr("ما عندك شي قادم", "Nothing coming up"), tr("ولا مهمة متأخرة 👏", "Nothing overdue 👏"), tr("ما خلصت شي بعد", "Nothing done yet")][segment],
                                   subtitle: segment == 0 ? tr("أضف موعد أو مهمة أو واجب وأنا أذكّرك.", "Add an appointment, task or homework and I'll remind you.") : "")
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(list) { r in
                            ReminderRow(reminder: r, revealed: revealed.contains(r.id)) {
                                if r.done { state.setDone(r, false); FX.toggle() } else { confirming = r }
                            }
                            .onTapGesture { open(r) }
                            .contextMenu { menu(r) }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 20)
        }
        .overlay { if celebrate { CelebrationView().allowsHitTesting(false) } }
        .sheet(item: $editing) { r in ReminderEditor(reminder: r).environmentObject(state) }
        .sheet(item: $secretAction) { act in SecretUnlockSheet(onUnlock: act.run).environmentObject(state) }
        .confirmationDialog(tr("متأكد إنك خلصتها؟", "Sure you finished it?"),
                            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                            titleVisibility: .visible) {
            Button(tr("✓ هيه خلصتها، اقفل المهمة", "✓ Yes, done — close it")) {
                if let r = confirming { complete(r) }
            }
            Button(tr("لا بعدني", "Not yet"), role: .cancel) { confirming = nil }
        }
        .onAppear {
            state.reminders = RemindersStore.load(state.space)
            if !introSeen { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showIntro = true } }
        }
        .fullScreenCover(isPresented: $showIntro) {
            RemindersIntro { introSeen = true; showIntro = false }
        }
    }

    private var todaySummary: String {
        let cal = Calendar.current
        let today = state.reminders.filter { !$0.done && cal.isDateInToday($0.due) }.count
        if !overdue.isEmpty { return tr("⚠️ \(overdue.count) متأخرة · \(today) اليوم", "⚠️ \(overdue.count) overdue · \(today) today") }
        return today == 0 ? tr("ما عندك شي اليوم", "Nothing due today") : tr("اليوم: \(today) مهام", "Today: \(today) due")
    }

    private var summaryCard: some View {
        let p = weekProgress
        let frac = p.total == 0 ? 0 : Double(p.done) / Double(p.total)
        let next = upcoming.first
        return HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Theme.surfaceHi, lineWidth: 9)
                Circle().trim(from: 0, to: frac)
                    .stroke(Theme.gradient, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.8), value: frac)
                VStack(spacing: 0) {
                    Text("\(Int(frac * 100))%").font(Theme.font(18, .heavy)).foregroundStyle(Theme.text)
                    Text(tr("الأسبوع", "week")).font(Theme.font(10, .bold)).foregroundStyle(Theme.sub)
                }
            }
            .frame(width: 74, height: 74)

            VStack(alignment: .leading, spacing: 5) {
                Text(tr("الأقرب", "Next up")).font(Theme.font(12, .bold)).foregroundStyle(Theme.sub)
                if let n = next {
                    Text(n.displayTitle).font(Theme.font(17, .bold)).foregroundStyle(Theme.text).lineLimit(1)
                    TimelineView(.periodic(from: .now, by: 30)) { ctx in
                        Text(Fmt.remaining(until: n.due, now: ctx.date))
                            .font(Theme.font(14, .semibold)).foregroundStyle(n.urgencyColor(now: ctx.date))
                    }
                } else {
                    Text(tr("ولا شي 🎉", "Nothing 🎉")).font(Theme.font(17, .bold)).foregroundStyle(Theme.text)
                }
            }
            Spacer()
        }
        .glass(16)
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func menu(_ r: Reminder) -> some View {
        Button { editing = r } label: { Label(tr("تعديل", "Edit"), systemImage: "pencil") }
        if !r.done {
            Button {
                var c = r
                c.snoozedUntil = Date().addingTimeInterval(3600)
                state.upsert(c)
                state.show(tr("بذكّرك بعد ساعة ⏰", "I'll remind you in an hour ⏰"), icon: "alarm")
            } label: { Label(tr("ذكّرني بعد ساعة", "Remind me in 1h"), systemImage: "alarm") }
            Button {
                Task {
                    if let id = await ReminderEngine.addToCalendar(r) {
                        var c = r; c.calendarEventID = id; state.upsert(c)
                        state.show(tr("انضاف للتقويم 📅", "Added to Calendar 📅"), icon: "calendar")
                    } else {
                        state.show(tr("ما قدرت أضيفه للتقويم", "Couldn't add to Calendar"), icon: "calendar.badge.exclamationmark", style: .warning)
                    }
                }
            } label: { Label(tr("أضف للتقويم", "Add to Calendar"), systemImage: "calendar.badge.plus") }
        }
        Button(role: .destructive) { state.delete(r) } label: { Label(tr("حذف", "Delete"), systemImage: "trash") }
    }

    private func open(_ r: Reminder) {
        FX.tap()
        if r.sensitivity == .secret && !revealed.contains(r.id) {
            secretAction = SecretAction { withAnimation { _ = revealed.insert(r.id) } }
        } else if r.sensitivity == .sensitive && !revealed.contains(r.id) {
            withAnimation { _ = revealed.insert(r.id) }
        } else {
            editing = r
        }
    }

    private func complete(_ r: Reminder) {
        state.setDone(r, true)
        confirming = nil
        FX.success()
        withAnimation { celebrate = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { withAnimation { celebrate = false } }
    }
}

struct ReminderRow: View {
    var reminder: Reminder
    var revealed: Bool
    var onCheck: () -> Void

    private var hidden: Bool { reminder.sensitivity != .normal && !revealed }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(reminder.urgencyColor(now: ctx.date))
                    .frame(width: 5, height: 48)
                Image(systemName: reminder.kind.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(reminder.urgencyColor(now: ctx.date))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(reminder.urgencyColor(now: ctx.date).opacity(0.14)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(hidden ? (reminder.sensitivity == .secret ? tr("🔒 تذكير سري", "🔒 Secret reminder") : tr("مخفي · اضغط للعرض", "Hidden · tap to show")) : reminder.title)
                        .font(Theme.font(16, .bold))
                        .foregroundStyle(reminder.done ? Theme.sub : Theme.text)
                        .strikethrough(reminder.done)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text(reminder.kind.title)
                        Text("·")
                        Text(reminder.done ? tr("خلصت \(Fmt.relative(reminder.doneAt ?? Date(), now: ctx.date))", "Done \(Fmt.relative(reminder.doneAt ?? Date(), now: ctx.date))")
                                           : Fmt.remaining(until: reminder.due, now: ctx.date))
                    }
                    .font(Theme.font(12, .semibold))
                    .foregroundStyle(reminder.done ? Theme.faint : reminder.urgencyColor(now: ctx.date))
                    Text(Fmt.date(reminder.due)).font(Theme.font(11)).foregroundStyle(Theme.faint)
                }
                Spacer()
                Button(action: onCheck) {
                    Image(systemName: reminder.done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(reminder.done ? Theme.ok : Theme.sub)
                }
                .buttonStyle(PressScale())
            }
            .glass(12, radius: 20, tint: reminder.urgency(now: ctx.date) >= 2 ? reminder.urgencyColor(now: ctx.date) : nil)
        }
    }
}

struct ReminderEditor: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State var reminder: Reminder
    @State private var addToCalendar = false
    @FocusState private var focus: AYNFieldID?

    private var isNew: Bool { !state.reminders.contains { $0.id == reminder.id } }

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(spacing: 14) {
                    SheetHeader(title: isNew ? tr("تذكير جديد", "New reminder") : tr("تعديل التذكير", "Edit reminder")) { dismiss() }

                    HStack(spacing: 8) {
                        ForEach(ReminderKind.allCases) { k in
                            Button {
                                withAnimation(.spring(response: 0.3)) {
                                    reminder.kind = k
                                    if k == .routine && reminder.routine == nil { reminder.routine = Routine() }
                                }
                                FX.toggle()
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: k.icon).font(.system(size: 20, weight: .semibold))
                                    Text(k.title).font(Theme.font(12, .bold)).lineLimit(1).minimumScaleFactor(0.7)
                                }
                                .foregroundStyle(reminder.kind == k ? Theme.bg : Theme.sub)
                                .frame(maxWidth: .infinity).frame(height: 70)
                                .background(RoundedRectangle(cornerRadius: 16)
                                    .fill(reminder.kind == k ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.surface)))
                            }
                            .buttonStyle(PressScale())
                        }
                    }

                    AYNField(title: reminder.kind == .routine ? tr("الاسم (مثلاً: اشرب ماي، دواء، ورد)", "Name (e.g. drink water, meds, reading)")
                                                              : tr("العنوان (مثلاً: واجب قواعد البيانات)", "Title (e.g. Database homework)"),
                             icon: "pencil", text: $reminder.title, focus: $focus, id: .title)

                    if reminder.kind == .routine {
                        RoutineEditorSection(routine: Binding(get: { reminder.routine ?? Routine() },
                                                              set: { reminder.routine = $0 }))
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionTitle(text: tr("موعد التسليم", "Due"), icon: "calendar")
                            DatePicker("", selection: $reminder.due, displayedComponents: [.date, .hourAndMinute])
                                .datePickerStyle(.graphical)
                                .tint(Theme.accent)
                        }
                        .glass(12)

                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle(text: tr("في آخر يوم ذكّرني كل", "On the last day, remind me every"), icon: "repeat")
                            Picker("", selection: $reminder.nagHours) {
                                ForEach([1, 2, 3, 4], id: \.self) { h in Text(tr("\(h) ساعة", "\(h)h")).tag(h) }
                            }
                            .pickerStyle(.segmented)
                        }
                        .glass(14)

                        schedulePreview
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle(text: tr("ملاحظات", "Notes"), icon: "note.text")
                        TextEditor(text: $reminder.notes)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 70)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle(text: tr("الحساسية", "Sensitivity"), icon: "shield.lefthalf.filled")
                        SensitivityPicker(level: $reminder.sensitivity)
                    }

                    if isNew && reminder.kind != .routine {
                        Toggle(isOn: $addToCalendar) {
                            Label(tr("أضف للتقويم بعد", "Also add to Calendar"), systemImage: "calendar.badge.plus")
                                .font(Theme.font(15, .semibold))
                        }
                        .tint(Theme.accent).glass(14)
                    }

                    PrimaryButton(title: tr("حفظ", "Save"), icon: "bell.badge.fill",
                                  enabled: !reminder.title.trimmingCharacters(in: .whitespaces).isEmpty
                                    && (reminder.kind != .routine || !(reminder.routine?.days.isEmpty ?? true))) { Task { await save() } }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var schedulePreview: some View {
        let plan = ReminderEngine.plan(for: reminder)
        return VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: tr("خطة التذكير (\(plan.count) إشعار)", "Reminder plan (\(plan.count) alerts)"), icon: "bell.and.waves.left.and.right")
            ForEach(Array(plan.prefix(7).enumerated()), id: \.offset) { _, p in
                HStack(spacing: 8) {
                    Circle().fill(Theme.accent).frame(width: 6, height: 6)
                    Text(Fmt.date(p.date)).font(Theme.font(12, .semibold)).foregroundStyle(Theme.text)
                    Text(p.body).font(Theme.font(11)).foregroundStyle(Theme.sub).lineLimit(1)
                }
            }
            if plan.count > 7 {
                Text(tr("… و\(plan.count - 7) غيرها حتى تأكّد إنك خلصتها", "… and \(plan.count - 7) more until you confirm it's done"))
                    .font(Theme.font(11)).foregroundStyle(Theme.faint)
            }
        }
        .glass(14)
    }

    private func save() async {
        reminder.title = reminder.title.trimmingCharacters(in: .whitespaces)
        if reminder.kind == .routine {
            if reminder.routine == nil { reminder.routine = Routine() }
            if isNew { reminder.routine?.startedAt = Date() }
            reminder.due = reminder.routine?.next() ?? reminder.due
        } else {
            reminder.routine = nil
        }
        var r = reminder
        if isNew && addToCalendar, let id = await ReminderEngine.addToCalendar(r) { r.calendarEventID = id }
        state.upsert(r)
        let granted = await ReminderEngine.requestPermission()
        if !granted {
            state.show(tr("فعّل الإشعارات من الإعدادات عشان توصلك التذكيرات", "Enable notifications in iOS Settings so reminders reach you"),
                       icon: "bell.slash.fill", style: .warning)
        } else {
            state.show(tr("تمام! بذكّرك 🔔", "Done! I'll remind you 🔔"), icon: "bell.fill")
        }
        Haptics.success()
        dismiss()
    }
}

struct CelebrationView: View {
    @State private var go = false
    private let colors: [Color] = [Theme.accent, Theme.accent2, Theme.ok, Theme.warn, .white]
    var body: some View {
        ZStack {
            ForEach(0..<36, id: \.self) { i in
                let angle = Double(i) / 36 * 2 * .pi
                let dist = CGFloat(120 + (i % 5) * 30)
                Circle()
                    .fill(colors[i % colors.count])
                    .frame(width: CGFloat(6 + i % 4 * 2), height: CGFloat(6 + i % 4 * 2))
                    .offset(x: go ? CGFloat(cos(angle)) * dist : 0, y: go ? CGFloat(sin(angle)) * dist : 0)
                    .opacity(go ? 0 : 1)
            }
            EyeView(mood: .happy, size: 110)
                .scaleEffect(go ? 1 : 0.4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { withAnimation(.easeOut(duration: 1.3)) { go = true } }
    }
}
