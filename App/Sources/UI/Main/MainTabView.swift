import SwiftUI

enum MainTab: Int, CaseIterable {
    case accounts, vault, reminders, settings

    var title: String {
        switch self {
        case .accounts: return tr("الحسابات", "Accounts")
        case .vault: return tr("الخزنة", "Vault")
        case .reminders: return tr("التذكيرات", "Reminders")
        case .settings: return tr("الإعدادات", "Settings")
        }
    }
    var icon: String {
        switch self {
        case .accounts: return "key.horizontal.fill"
        case .vault: return "lock.doc.fill"
        case .reminders: return "bell.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var state: AppState
    @AppStorage("ui.lastTab") private var tabRaw = MainTab.accounts.rawValue
    @Namespace private var ns

    private var tab: MainTab { MainTab(rawValue: tabRaw) ?? .accounts }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .accounts:
                    SectionGate(title: MainTab.accounts.title, icon: "key.horizontal.fill") { AccountsView() }
                case .vault:
                    SectionGate(title: MainTab.vault.title, icon: "lock.doc.fill") { VaultView() }
                case .reminders:
                    RemindersView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 84) }

            tabBar
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(MainTab.allCases, id: \.rawValue) { t in
                let selected = t == tab
                Button {
                    guard !selected else { return }
                    Haptics.selection()
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { tabRaw = t.rawValue }
                } label: {
                    VStack(spacing: 4) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: t.icon)
                                .font(.system(size: 19, weight: .semibold))
                                .symbolEffect(.bounce, value: selected)
                            if t == .settings && state.newIntrusions > 0 {
                                Circle().fill(Theme.danger).frame(width: 9, height: 9).offset(x: 7, y: -3)
                            }
                        }
                        Text(t.title).font(Theme.font(11, .bold)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(selected ? Theme.text : Theme.faint)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background {
                        if selected {
                            Capsule()
                                .fill(LinearGradient(colors: [Theme.accent.opacity(0.28), Theme.accent2.opacity(0.28)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                                .overlay(Capsule().strokeBorder(LinearGradient(colors: [Theme.accent.opacity(0.7), Theme.accent2.opacity(0.5)],
                                                                               startPoint: .top, endPoint: .bottom), lineWidth: 1))
                                .matchedGeometryEffect(id: "tab", in: ns)
                                .shadow(color: Theme.accent.opacity(0.35), radius: 14)
                        }
                    }
                }
                .buttonStyle(PressScale())
            }
        }
        .padding(6)
        .background(Capsule().fill(.ultraThinMaterial))
        .background(Capsule().fill(Theme.bg.opacity(0.6)))
        .overlay(Capsule().strokeBorder(LinearGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0.03)],
                                                       startPoint: .top, endPoint: .bottom)))
        .shadow(color: .black.opacity(0.5), radius: 26, y: 10)
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
    }
}

/// Header at the top of each tab: big title, subtitle, cloud status and a lock button.
struct TabHeader<Trailing: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var trailing: () -> Trailing

    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.font(32, .heavy)).foregroundStyle(Theme.text)
                HStack(spacing: 6) {
                    if state.cloudReady && !state.isDecoy {
                        Image(systemName: state.syncing ? "arrow.triangle.2.circlepath.icloud" : (state.syncError == nil ? "checkmark.icloud" : "exclamationmark.icloud"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(state.syncError == nil ? Theme.accent : Theme.warn)
                            .symbolEffect(.pulse, isActive: state.syncing)
                    }
                    Text(subtitle).font(Theme.font(14, .medium)).foregroundStyle(Theme.sub)
                }
            }
            Spacer()
            trailing()
            CircleIconButton(icon: "lock.fill", size: 42, tint: Theme.accent) { state.lock() }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

// MARK: - Section passcode gate

struct SectionGate<Content: View>: View {
    @EnvironmentObject var state: AppState
    var title: String
    var icon: String
    @ViewBuilder var content: () -> Content

    @State private var code = ""
    @State private var shakes = 0
    @State private var mood: EyeMood = .idle
    @State private var checking = false
    @FocusState private var focus: AYNFieldID?

    private var useBio: Bool { UserDefaults.standard.bool(forKey: "sec.sectionBiometric") && Biometrics.isAvailable }

    var body: some View {
        if state.sectionUnlocked {
            content()
        } else if !state.hasSectionPassword {
            ScrollView {
                PasscodeSetupFlow { code, kind in
                    Task {
                        await state.setSectionPassword(code, kind: kind)
                        SoundFX.shared.play(.unlock, volume: 0.45)
                        state.show(tr("تم إنشاء رمز الأقسام ✓", "Section passcode created ✓"), icon: "lock.fill")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 30)
            }
            .scrollDismissesKeyboard(.interactively)
        } else {
            ScrollView {
                VStack(spacing: 14) {
                    EyeView(mood: currentMood, size: 120, sounds: true)
                        .padding(.top, 26)
                    Label(title, systemImage: icon)
                        .font(Theme.font(24, .heavy)).foregroundStyle(Theme.text)
                    Text(tr("اكتب رمز الأقسام", "Enter your section passcode"))
                        .font(Theme.font(14)).foregroundStyle(Theme.sub)
                    PasscodeEntry(kind: state.sectionKind, code: $code, shakes: shakes,
                                  biometricIcon: useBio ? Biometrics.icon : nil,
                                  onBiometric: { Task { await bio() } },
                                  focus: $focus) { entered in Task { await submit(entered) } }
                        .padding(.top, 6)
                }
                .padding(.horizontal, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear { if useBio { Task { await bio() } } }
        }
    }

    private var currentMood: EyeMood {
        if mood == .angry || mood == .happy { return mood }
        if checking { return .thinking }
        if code.isEmpty { return .idle }
        // Follows each digit across the pad.
        let total = CGFloat(state.sectionKind.length ?? max(code.count, 8))
        return .reading(min(1, CGFloat(code.count) / total))
    }

    private func bio() async {
        if await Biometrics.authenticate(reason: tr("افتح القسم", "Open section")) != nil {
            withAnimation { mood = .happy }
            await pause(0.3)
            state.sectionUnlocked = true
        }
    }

    private func submit(_ entered: String) async {
        guard !checking else { return }
        checking = true
        let ok = await state.checkSectionPassword(entered)
        checking = false
        if ok {
            withAnimation { mood = .happy }
        } else {
            withAnimation { mood = .angry }
            shakes += 1
            code = ""
            await pause(0.9)
            withAnimation { mood = .idle }
        }
    }
}

// MARK: - Extra gate for 🔴 top-secret items: Face ID + section passcode every time

struct SecretUnlockSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    var onUnlock: () -> Void

    @State private var bioOK = false
    @State private var code = ""
    @State private var shakes = 0
    @State private var error: String?
    @State private var mood: EyeMood = .scanning
    @FocusState private var focus: AYNFieldID?

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(spacing: 14) {
                    SheetHeader(title: tr("محتوى سري جداً", "Top secret")) { dismiss() }
                    EyeView(mood: mood, size: 110, sounds: true)
                    Label(bioOK ? tr("تم التحقق ✓", "Verified ✓") : tr("نتحقق من وجهك…", "Checking your face…"),
                          systemImage: Biometrics.icon)
                        .font(Theme.font(15, .semibold))
                        .foregroundStyle(bioOK ? Theme.ok : Theme.sub)
                    if let error { Text(error).font(Theme.font(14, .semibold)).foregroundStyle(Theme.danger) }
                    if bioOK {
                        PasscodeEntry(kind: state.sectionKind, code: $code, shakes: shakes, focus: $focus) { entered in
                            Task { await submit(entered) }
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    } else {
                        SecondaryButton(title: tr("حاول مرة ثانية", "Try again"), icon: Biometrics.icon) { Task { await bio() } }
                    }
                }
                .padding(20)
            }
        }
        .presentationDetents([.large])
        .task { await bio() }
    }

    private func bio() async {
        if !Biometrics.isAvailable { withAnimation { bioOK = true; mood = .idle }; return }
        withAnimation { mood = .scanning }
        await pause(0.25)
        if await Biometrics.authenticate(reason: tr("فتح محتوى سري", "Open secret item")) != nil {
            withAnimation(.spring) { bioOK = true; mood = .lookUp; error = nil }
        } else {
            withAnimation { mood = .angry }
            error = tr("فشل التحقق بالوجه.", "Face check failed.")
        }
    }

    private func submit(_ entered: String) async {
        if await state.checkSectionPassword(entered) {
            withAnimation { mood = .happy }
            await pause(0.35)
            dismiss()
            onUnlock()
        } else {
            withAnimation { mood = .angry }
            shakes += 1
            code = ""
            error = tr("الرمز غلط.", "Wrong passcode.")
            await pause(0.8)
            withAnimation { mood = .lookUp }
        }
    }
}

/// Holds a pending action for a secret item and presents the unlock sheet.
struct SecretAction: Identifiable {
    let id = UUID()
    let run: () -> Void
}
