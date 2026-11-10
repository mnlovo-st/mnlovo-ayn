import SwiftUI

// MARK: - Routine strip on the Reminders tab

struct RoutineStrip: View {
    @EnvironmentObject var state: AppState
    var routines: [Reminder]
    var onEdit: (Reminder) -> Void
    var onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(tr("روتينك", "Your routines"), systemImage: "repeat.circle.fill")
                    .font(Theme.font(17, .heavy)).foregroundStyle(Theme.text)
                Spacer()
                let today = routines.filter { $0.routine?.scheduledToday == true }
                let done = today.filter { $0.routine?.isDone(on: Date()) == true }.count
                if !today.isEmpty {
                    Text(tr("اليوم \(done)/\(today.count)", "Today \(done)/\(today.count)"))
                        .font(Theme.font(13, .bold)).foregroundStyle(done == today.count ? Theme.ok : Theme.sub)
                }
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(routines) { r in
                        RoutineCard(reminder: r) {
                            let wasDone = r.routine?.isDone(on: Date()) == true
                            state.markRoutine(r, done: !wasDone)
                            if !wasDone { FX.success() } else { FX.toggle() }
                        }
                        .onTapGesture { onEdit(r) }
                        .contextMenu {
                            Button { onEdit(r) } label: { Label(tr("تعديل", "Edit"), systemImage: "pencil") }
                            Button { state.markRoutine(r, done: false, skip: true) } label: {
                                Label(tr("تخطّي اليوم", "Skip today"), systemImage: "forward.end.fill")
                            }
                            Button(role: .destructive) { state.delete(r) } label: { Label(tr("حذف", "Delete"), systemImage: "trash") }
                        }
                    }
                    Button(action: onAdd) {
                        VStack(spacing: 8) {
                            Image(systemName: "plus").font(.system(size: 22, weight: .bold))
                            Text(tr("روتين جديد", "New routine")).font(Theme.font(13, .bold))
                        }
                        .foregroundStyle(Theme.accent)
                        .frame(width: 120, height: 178)
                        .background(RoundedRectangle(cornerRadius: 24).strokeBorder(Theme.accent.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                    }
                    .buttonStyle(PressScale())
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
        }
    }
}

struct RoutineCard: View {
    var reminder: Reminder
    var onTick: () -> Void

    private var ro: Routine { reminder.routine ?? Routine() }
    private var doneToday: Bool { ro.isDone(on: Date()) }
    private var skipped: Bool { ro.isSkipped(on: Date()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(ro.emoji.isEmpty ? "⭐️" : ro.emoji).font(.system(size: 30))
                Spacer()
                let streak = ro.streak()
                if streak > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                        Text("\(streak)")
                    }
                    .font(Theme.font(13, .heavy))
                    .foregroundStyle(Color(hex: 0xFF8A3D))
                    .padding(.horizontal, 8).frame(height: 24)
                    .background(Capsule().fill(Color(hex: 0xFF8A3D).opacity(0.15)))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.sensitivity == .secret ? tr("🔒 سري", "🔒 Secret") : reminder.title)
                    .font(Theme.font(15, .heavy)).foregroundStyle(Theme.text).lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: ro.style.icon)
                    Text(ro.timeText)
                    if ro.mode == .once { Text(tr("· هالأسبوع", "· this week")) }
                }
                .font(Theme.font(11, .semibold)).foregroundStyle(Theme.sub)
            }
            HStack(spacing: 3) {
                ForEach(Routine.orderedDays, id: \.0) { d in
                    let on = ro.days.contains(d.0)
                    let isToday = Calendar.current.component(.weekday, from: Date()) == d.0
                    Text(String(d.1.prefix(1)))
                        .font(Theme.font(9, .heavy))
                        .foregroundStyle(on ? Theme.bg : Theme.faint)
                        .frame(width: 15, height: 15)
                        .background(Circle().fill(on ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.surfaceHi)))
                        .overlay(Circle().strokeBorder(isToday ? Theme.text : .clear, lineWidth: 1))
                }
            }
            Button(action: onTick) {
                HStack(spacing: 6) {
                    Image(systemName: doneToday ? "checkmark.circle.fill" : (skipped ? "forward.end.fill" : "circle"))
                        .contentTransition(.symbolEffect(.replace))
                    Text(doneToday ? tr("سويتها اليوم", "Done today") : (skipped ? tr("متخطّى", "Skipped") : tr("سويتها؟", "Did it?")))
                }
                .font(Theme.font(13, .bold))
                .foregroundStyle(doneToday ? Theme.bg : Theme.text)
                .frame(maxWidth: .infinity).frame(height: 34)
                .background(Capsule().fill(doneToday ? AnyShapeStyle(Theme.ok) : AnyShapeStyle(Theme.surfaceHi)))
            }
            .buttonStyle(PressScale())
            .disabled(!ro.scheduledToday)
            .opacity(ro.scheduledToday ? 1 : 0.4)
        }
        .padding(14)
        .frame(width: 172, height: 178)
        .background(RoundedRectangle(cornerRadius: 24).fill(doneToday ? Theme.ok.opacity(0.12) : Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(doneToday ? Theme.ok.opacity(0.5) : Theme.stroke))
        .shadow(color: doneToday ? Theme.ok.opacity(0.3) : .clear, radius: 12)
        .animation(.spring(response: 0.4), value: doneToday)
    }
}

// MARK: - Routine options inside the reminder editor

struct RoutineEditorSection: View {
    @Binding var routine: Routine
    @State private var time = Date()

    private let emojis = ["💧", "💊", "📖", "🏃", "🧘", "🕌", "🦷", "🛏️", "🍎", "📚", "💪", "🌿", "☕️", "🐈", "🎹", "💰"]

    var body: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: tr("الأيام", "Days"), icon: "calendar")
                HStack(spacing: 6) {
                    ForEach(Routine.orderedDays, id: \.0) { d in
                        let on = routine.days.contains(d.0)
                        Button {
                            Haptics.selection()
                            withAnimation(.spring(response: 0.3)) {
                                if on { routine.days.removeAll { $0 == d.0 } } else { routine.days.append(d.0) }
                            }
                        } label: {
                            Text(d.1)
                                .font(Theme.font(11, .bold))
                                .lineLimit(1).minimumScaleFactor(0.6)
                                .foregroundStyle(on ? Theme.bg : Theme.sub)
                                .frame(maxWidth: .infinity).frame(height: 40)
                                .background(RoundedRectangle(cornerRadius: 12).fill(on ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.surface)))
                        }
                        .buttonStyle(PressScale())
                    }
                }
                HStack(spacing: 8) {
                    quick(tr("كل يوم", "Every day"), [1, 2, 3, 4, 5, 6, 7])
                    quick(tr("أيام الدوام", "Weekdays"), [2, 3, 4, 5, 6])
                    quick(tr("الويكند", "Weekend"), [7, 1])
                }
            }
            .glass(14)

            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: tr("التكرار", "Repeat"), icon: "repeat")
                Picker("", selection: $routine.mode) {
                    Text(tr("كل أسبوع", "Every week")).tag(Routine.Mode.weekly)
                    Text(tr("هالأسبوع بس", "This week only")).tag(Routine.Mode.once)
                }
                .pickerStyle(.segmented)
                HStack {
                    SectionTitle(text: tr("الساعة", "Time"), icon: "clock")
                    Spacer()
                    DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .onChange(of: time) { _, t in
                            let c = Calendar.current.dateComponents([.hour, .minute], from: t)
                            routine.hour = c.hour ?? 8; routine.minute = c.minute ?? 0
                        }
                }
                HStack {
                    SectionTitle(text: tr("تنبيه قبلها", "Heads-up before"), icon: "bell.badge")
                    Spacer()
                    Picker("", selection: $routine.early) {
                        Text(tr("بدون", "None")).tag(0)
                        Text(tr("٥ د", "5 min")).tag(5)
                        Text(tr("١٥ د", "15 min")).tag(15)
                        Text(tr("٣٠ د", "30 min")).tag(30)
                    }
                    .tint(Theme.accent)
                }
            }
            .glass(14)

            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: tr("طريقة التذكير", "Reminder style"), icon: "sparkles")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(Routine.Style.allCases) { st in
                        Button {
                            Haptics.selection()
                            withAnimation(.spring(response: 0.3)) { routine.style = st }
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Image(systemName: st.icon).font(.system(size: 20, weight: .bold))
                                Text(st.title).font(Theme.font(15, .heavy))
                            }
                            .foregroundStyle(routine.style == st ? Theme.bg : Theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 16).fill(routine.style == st ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.surface)))
                        }
                        .buttonStyle(PressScale())
                    }
                }
                Text(routine.style.blurb).font(Theme.font(12)).foregroundStyle(Theme.sub)
                    .id(routine.style).transition(.opacity)
            }
            .glass(14)

            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: tr("أيقونة", "Icon"), icon: "face.smiling")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 8) {
                    ForEach(emojis, id: \.self) { e in
                        Button {
                            Haptics.selection()
                            routine.emoji = e
                        } label: {
                            Text(e).font(.system(size: 22))
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(routine.emoji == e ? Theme.accent.opacity(0.25) : Theme.surface))
                                .overlay(Circle().strokeBorder(routine.emoji == e ? Theme.accent : .clear))
                        }
                        .buttonStyle(PressScale())
                    }
                }
            }
            .glass(14)

            preview
        }
        .onAppear {
            var c = DateComponents(); c.hour = routine.hour; c.minute = routine.minute
            time = Calendar.current.date(from: c) ?? Date()
        }
    }

    private func quick(_ title: String, _ days: [Int]) -> some View {
        let on = Set(routine.days) == Set(days)
        return Button {
            Haptics.selection()
            withAnimation(.spring(response: 0.3)) { routine.days = days }
        } label: {
            Text(title).font(Theme.font(12, .bold))
                .foregroundStyle(on ? Theme.accent : Theme.sub)
                .padding(.horizontal, 12).frame(height: 30)
                .background(Capsule().fill(on ? Theme.accent.opacity(0.15) : Theme.surface))
        }
        .buttonStyle(PressScale())
    }

    private var preview: some View {
        let next = routine.occurrences(from: Date(), span: 14).prefix(4)
        return VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: tr("المرات الجاية", "Next times"), icon: "bell.and.waves.left.and.right")
            if next.isEmpty {
                Text(tr("اختر يوم واحد على الأقل.", "Pick at least one day.")).font(Theme.font(12)).foregroundStyle(Theme.warn)
            }
            ForEach(Array(next), id: \.self) { d in
                HStack(spacing: 8) {
                    Circle().fill(Theme.accent).frame(width: 6, height: 6)
                    Text(Fmt.date(d)).font(Theme.font(12, .semibold)).foregroundStyle(Theme.text)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(14)
    }
}

// MARK: - First-visit intro: how reminders work (animated, with the app in a phone)

struct RemindersIntro: View {
    var onDone: () -> Void

    @State private var scene = 0
    @State private var step = 0         // per-scene animation beat
    @State private var auto = true
    private let count = 5

    private var captions: [(String, String)] {
        [(tr("تضيف موعد أو مهمة أو واجب", "Add an appointment, task or homework"),
          tr("تكتب الاسم وتختار موعد التسليم. ثواني وخلاص.", "Type a name and pick the due date. Seconds, done.")),
         (tr("وأنا أذكّرك قبلها بشكل ذكي", "I remind you ahead, smartly"),
          tr("قبل ٣ أيام، ويومين، ويوم… وفي آخر يوم أسألك كل كم ساعة: «سويتها؟»", "3 days, 2 days, 1 day before… and on the last day I keep asking: “Done yet?”")),
         (tr("الروتين اليومي له طريقته", "Daily routines have their own style"),
          tr("تختار الأيام والساعة، كل أسبوع أو هالأسبوع بس، وطريقة التذكير: لطيف، مدرّب، منبّه أو هادي. وتجمع سلسلة 🔥", "Pick days and time, weekly or just this week, and a style: gentle, coach, alarm or quiet. Build a streak 🔥")),
         (tr("تخلصها؟ أقفلها بضغطة", "Done? Close it in one tap"),
          tr("من الإشعار نفسه أو من التطبيق: «✓ هيه خلصتها» وأوقف التذكير.", "From the notification or the app: “✓ Yes, done” and I stop.")),
         (tr("وأحاسب لك اشتراكاتك", "And I keep your subscriptions in line"),
          tr("تحط سعر كل اشتراك ودورته، وأقول لك كم يكلّفك بالشهر، وأنبّهك قبل التجديد بوقت يكفي تلغيه.",
             "Enter each subscription's price and cycle; I tell you the real monthly cost and warn you early enough to cancel."))]
    }

    var body: some View {
        ZStack {
            AuroraBackground()
            VStack(spacing: 18) {
                HStack {
                    Spacer()
                    Button(tr("تخطّي", "Skip")) { finish() }
                        .font(Theme.font(15, .bold)).foregroundStyle(Theme.sub)
                        .padding(.horizontal, 16).frame(height: 36)
                        .background(Capsule().fill(Theme.surface))
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 0)
                phone
                    .frame(width: 210, height: 330)
                    .id(scene)
                    .transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity), removal: .opacity))

                VStack(spacing: 8) {
                    Text(captions[scene].0).font(Theme.font(23, .heavy)).foregroundStyle(Theme.text)
                    Text(captions[scene].1).font(Theme.font(15)).foregroundStyle(Theme.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .frame(minHeight: 110, alignment: .top)
                .id("cap\(scene)")
                .transition(.opacity.combined(with: .move(edge: .bottom)))

                HStack(spacing: 6) {
                    ForEach(0..<count, id: \.self) { i in
                        Capsule().fill(i == scene ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.surfaceHi))
                            .frame(width: i == scene ? 26 : 8, height: 8)
                            .onTapGesture { auto = false; go(i) }
                    }
                }
                Spacer(minLength: 0)

                PrimaryButton(title: scene == count - 1 ? tr("يلا نبدأ", "Let's go") : tr("التالي", "Next"),
                              icon: scene == count - 1 ? "bell.badge.fill" : "arrow.forward") {
                    auto = false
                    if scene == count - 1 { finish() } else { go(scene + 1) }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 24).onEnded { g in
                guard abs(g.translation.width) > abs(g.translation.height) else { return }
                auto = false
                // In Arabic the pages read right-to-left, so a drag to the right means "next".
                let forward = AppLanguage.current.isRTL ? g.translation.width > 0 : g.translation.width < 0
                if forward, scene < count - 1 { go(scene + 1) }
                else if !forward, scene > 0 { go(scene - 1) }
            }
        )
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: scene)
        .task(id: scene) { await play() }
    }

    private func go(_ i: Int) {
        Haptics.selection()
        withAnimation { scene = i; step = 0 }
    }

    private func finish() {
        Haptics.success()
        onDone()
    }

    private func play() async {
        step = 0
        let beats = [4, 6, 5, 4, 5][scene]
        for b in 1...beats {
            await pause(scene == 1 ? 0.55 : 0.7)
            if Task.isCancelled { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { step = b }
            if scene == 3 && b == 3 { Haptics.success() } else { Haptics.soft(0.3) }
        }
        await pause(2.0)
        if auto && !Task.isCancelled && scene < count - 1 { go(scene + 1) }
    }

    // MARK: Phone mock

    private var phone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34).fill(Color.black.opacity(0.62))
            Group {
                switch scene {
                case 0: addScene
                case 1: timelineScene
                case 2: routineScene
                case 3: doneScene
                default: subsScene
                }
            }
            .padding(.horizontal, 14).padding(.top, 34).padding(.bottom, 16)
            RoundedRectangle(cornerRadius: 34).strokeBorder(LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 2)
            Capsule().fill(Color.black).frame(width: 64, height: 18).frame(maxHeight: .infinity, alignment: .top).padding(.top, 10)
        }
        .shadow(color: Theme.accent.opacity(0.25), radius: 24)
    }

    private func bar(_ w: CGFloat, _ c: Color = Theme.surfaceHi) -> some View {
        RoundedRectangle(cornerRadius: 3).fill(c).frame(width: w, height: 6)
    }

    private var addScene: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("تذكير جديد", "New reminder")).font(Theme.font(13, .heavy)).foregroundStyle(Theme.text)
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    let icons = ["calendar.badge.clock", "checklist", "book.closed.fill"]
                    Image(systemName: icons[i]).font(.system(size: 13, weight: .bold))
                        .foregroundStyle(i == 2 && step >= 1 ? Theme.bg : Theme.sub)
                        .frame(maxWidth: .infinity).frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 10).fill(i == 2 && step >= 1 ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.surface)))
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "pencil").font(.system(size: 10)).foregroundStyle(Theme.accent)
                Text(step >= 2 ? tr("واجب قواعد البيانات", "Database homework") : " ")
                    .font(Theme.font(11, .semibold)).foregroundStyle(Theme.text)
                Spacer()
            }
            .padding(8).background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
            VStack(spacing: 4) {
                HStack { bar(50); Spacer(); bar(30) }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 3) {
                    ForEach(0..<21, id: \.self) { i in
                        Circle().fill(i == 16 && step >= 3 ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.surfaceHi))
                            .frame(height: 14)
                    }
                }
            }
            .padding(8).background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
            Spacer()
            Text(tr("حفظ", "Save")).font(Theme.font(12, .heavy)).foregroundStyle(Theme.bg)
                .frame(maxWidth: .infinity).frame(height: 32)
                .background(Capsule().fill(Theme.gradient))
                .scaleEffect(step == 4 ? 0.92 : 1)
                .shadow(color: Theme.accent.opacity(step >= 4 ? 0.8 : 0), radius: 10)
        }
    }

    private var timelineScene: some View {
        let items: [(String, String, Color)] = [
            (tr("باقي ٣ أيام", "3 days left"), tr("خطط لها من الحين 💪", "Plan it now 💪"), Theme.ok),
            (tr("باقي يومين", "2 days left"), tr("لا تخليها لآخر لحظة", "Don't leave it late"), Theme.warn),
            (tr("باقي يوم", "1 day left"), tr("بكرة آخر يوم ⚠️", "Tomorrow's the last day ⚠️"), Color(hex: 0xFF7A45)),
            (tr("اليوم آخر يوم", "Last day"), tr("سويتها؟", "Done yet?"), Theme.danger),
            (tr("اليوم آخر يوم", "Last day"), tr("للحين؟ 👀", "Still? 👀"), Theme.danger),
            (tr("خلص الوقت", "Time's up"), tr("⏰ سويتها؟", "⏰ Did you?"), Theme.danger)]
        return VStack(spacing: 6) {
            Text("9:41").font(Theme.font(26, .heavy)).foregroundStyle(Theme.text.opacity(0.9)).padding(.bottom, 4)
            ForEach(0..<items.count, id: \.self) { i in
                if step > i {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 6).fill(Theme.gradient).frame(width: 20, height: 20)
                            .overlay(Image(systemName: "eye.fill").font(.system(size: 9)).foregroundStyle(.white))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(items[i].0).font(Theme.font(10, .heavy)).foregroundStyle(items[i].2)
                            Text(items[i].1).font(Theme.font(9, .medium)).foregroundStyle(Theme.text.opacity(0.85))
                        }
                        Spacer()
                    }
                    .padding(7)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            Spacer()
        }
    }

    private var routineScene: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("💧").font(.system(size: 26))
                Spacer()
                if step >= 4 {
                    HStack(spacing: 2) { Image(systemName: "flame.fill"); Text("\(step >= 5 ? 8 : 7)").contentTransition(.numericText()) }
                        .font(Theme.font(12, .heavy)).foregroundStyle(Color(hex: 0xFF8A3D))
                        .padding(.horizontal, 7).frame(height: 22)
                        .background(Capsule().fill(Color(hex: 0xFF8A3D).opacity(0.15)))
                        .transition(.scale)
                }
            }
            Text(tr("اشرب ماي", "Drink water")).font(Theme.font(14, .heavy)).foregroundStyle(Theme.text)
            HStack(spacing: 3) {
                ForEach(0..<7, id: \.self) { i in
                    let on = step >= 1 && [0, 1, 2, 3, 4].contains(i) || step >= 2
                    Circle().fill(on ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.surfaceHi))
                        .frame(width: 18, height: 18)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "clock").font(.system(size: 10))
                Text(step >= 3 ? "8:00 ص" : "--:--").font(Theme.mono(12, .bold))
                Spacer()
                Text(tr("كل أسبوع", "Weekly")).font(Theme.font(9, .bold)).foregroundStyle(Theme.accent)
                    .padding(.horizontal, 6).frame(height: 18).background(Capsule().fill(Theme.accent.opacity(0.15)))
            }
            .foregroundStyle(Theme.text)
            HStack(spacing: 5) {
                ForEach(Routine.Style.allCases) { st in
                    Image(systemName: st.icon).font(.system(size: 11, weight: .bold))
                        .foregroundStyle(st == .coach && step >= 3 ? Theme.bg : Theme.sub)
                        .frame(maxWidth: .infinity).frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 8).fill(st == .coach && step >= 3 ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.surface)))
                }
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: step >= 5 ? "checkmark.circle.fill" : "circle")
                Text(step >= 5 ? tr("سويتها اليوم", "Done today") : tr("سويتها؟", "Did it?"))
            }
            .font(Theme.font(12, .bold))
            .foregroundStyle(step >= 5 ? Theme.bg : Theme.text)
            .frame(maxWidth: .infinity).frame(height: 32)
            .background(Capsule().fill(step >= 5 ? AnyShapeStyle(Theme.ok) : AnyShapeStyle(Theme.surfaceHi)))
        }
    }

    private var doneScene: some View {
        VStack(spacing: 10) {
            Spacer()
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 6).fill(Theme.gradient).frame(width: 20, height: 20)
                        .overlay(Image(systemName: "eye.fill").font(.system(size: 9)).foregroundStyle(.white))
                    Text("MNLOVO SAVER").font(Theme.font(9, .heavy)).foregroundStyle(Theme.sub)
                    Spacer()
                }
                Text(tr("واجب قواعد البيانات", "Database homework")).font(Theme.font(11, .heavy)).foregroundStyle(Theme.text)
                Text(tr("اليوم آخر يوم! سويتها؟", "Last day! Done?")).font(Theme.font(10)).foregroundStyle(Theme.text.opacity(0.8))
            }
            .padding(9)
            .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
            if step >= 1 {
                VStack(spacing: 0) {
                    Text(tr("✓ هيه خلصتها، اقفل المهمة", "✓ Yes, done — close it"))
                        .font(Theme.font(11, .bold)).foregroundStyle(step >= 2 ? Theme.bg : Theme.accent)
                        .frame(maxWidth: .infinity).frame(height: 32)
                        .background(RoundedRectangle(cornerRadius: 10).fill(step >= 2 ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.clear)))
                    Divider().overlay(Theme.stroke)
                    Text(tr("لا بعدني", "Not yet")).font(Theme.font(11, .semibold)).foregroundStyle(Theme.sub)
                        .frame(maxWidth: .infinity).frame(height: 30)
                }
                .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if step >= 3 {
                EyeView(mood: .happy, size: 74)
                    .transition(.scale.combined(with: .opacity))
                Text(tr("انقفلت ✓ ووقّف التذكير", "Closed ✓ reminders stopped"))
                    .font(Theme.font(11, .bold)).foregroundStyle(Theme.ok)
            }
            Spacer()
        }
    }

    /// Scene 5 — subscriptions, which now live in this section: the real monthly cost, then the
    /// warning that lands while there's still time to cancel.
    private var subsScene: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(tr("اشتراكاتك", "Your subscriptions")).font(Theme.font(13, .heavy)).foregroundStyle(Theme.text)
            subRow("Netflix", tr("شهري", "monthly"), "56", on: step >= 1)
            subRow("iCloud", tr("شهري", "monthly"), "11", on: step >= 2)
            subRow("Adobe", tr("سنوي", "yearly"), "899", on: step >= 3)
            if step >= 4 {
                HStack(spacing: 6) {
                    Image(systemName: "sum").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.accent)
                    Text(tr("يكلّفك بالشهر", "Costs you monthly")).font(Theme.font(10, .bold)).foregroundStyle(Theme.sub)
                    Spacer()
                    Text(tr("‏141 درهم", "141 AED")).font(Theme.font(12, .heavy)).foregroundStyle(Theme.text)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surfaceHi))
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
            Spacer()
            if step >= 5 {
                HStack(spacing: 7) {
                    Image(systemName: "bell.badge.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.warn)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tr("Adobe يتجدد بعد ٥ أيام", "Adobe renews in 5 days"))
                            .font(Theme.font(10, .heavy)).foregroundStyle(Theme.text)
                        Text(tr("تبي تلغيه قبل ما يُخصم؟", "Cancel before it's charged?"))
                            .font(Theme.font(9)).foregroundStyle(Theme.sub)
                    }
                    Spacer(minLength: 0)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func subRow(_ name: String, _ cycle: String, _ price: String, on: Bool) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 7).fill(Theme.surfaceHi).frame(width: 22, height: 22)
                .overlay(Text(String(name.prefix(1))).font(Theme.font(10, .heavy)).foregroundStyle(Theme.accent))
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(Theme.font(10, .bold)).foregroundStyle(Theme.text)
                Text(cycle).font(Theme.font(8)).foregroundStyle(Theme.faint)
            }
            Spacer(minLength: 0)
            Text(price).font(Theme.font(11, .heavy)).foregroundStyle(Theme.sub)
        }
        .padding(7)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
        .opacity(on ? 1 : 0.3)
    }
}
