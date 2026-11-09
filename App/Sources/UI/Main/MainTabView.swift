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
        case .accounts: return "key.fill"
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
                    SectionGate(title: MainTab.accounts.title, icon: "key.fill") { AccountsView() }
                case .vault:
                    SectionGate(title: MainTab.vault.title, icon: "lock.doc.fill") { VaultView() }
                case .reminders:
                    RemindersView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 78) }

            tabBar
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(MainTab.allCases, id: \.rawValue) { t in
                Button {
                    guard t != tab else { return }
                    FX.toggle()
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) { tabRaw = t.rawValue }
                } label: {
                    VStack(spacing: 3) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: t.icon).font(.system(size: 19, weight: .semibold))
                            if t == .settings && state.newIntrusions > 0 {
                                Circle().fill(Theme.danger).frame(width: 9, height: 9).offset(x: 6, y: -3)
                            }
                        }
                        Text(t.title).font(Theme.font(11, .bold))
                    }
                    .foregroundStyle(t == tab ? Theme.bg : Theme.sub)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background {
                        if t == tab {
                            Capsule().fill(Theme.gradient)
                                .matchedGeometryEffect(id: "tab", in: ns)
                                .shadow(color: Theme.accent.opacity(0.45), radius: 12)
                        }
                    }
                }
                .buttonStyle(PressScale())
            }
        }
        .padding(6)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().strokeBorder(Theme.stroke))
        .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }
}

/// Header used at the top of each tab.
struct TabHeader<Trailing: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var trailing: () -> Trailing

    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.font(32, .heavy)).foregroundStyle(Theme.text)
                Text(subtitle).font(Theme.font(14, .medium)).foregroundStyle(Theme.sub)
            }
            Spacer()
            trailing()
            CircleIconButton(icon: "lock.fill", size: 42, tint: Theme.accent) { state.lock() }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

// MARK: - Section password gate

struct SectionGate<Content: View>: View {
    @EnvironmentObject var state: AppState
    var title: String
    var icon: String
    @ViewBuilder var content: () -> Content

    @State private var password = ""
    @State private var confirm = ""
    @State private var error: String?
    @State private var loading = false
    @State private var mood: EyeMood = .idle
    @FocusState private var focus: AYNFieldID?

    private var creating: Bool { !state.hasSectionPassword }
    private var useBio: Bool { UserDefaults.standard.bool(forKey: "sec.sectionBiometric") && Biometrics.isAvailable }

    var body: some View {
        if state.sectionUnlocked {
            content()
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    Spacer(minLength: 30)
                    EyeView(mood: currentMood, size: 140, sounds: true)
                    Text(creating ? tr("أنشئ كلمة سر للأقسام", "Create a section password") : title)
                        .font(Theme.font(26, .heavy)).foregroundStyle(Theme.text)
                    Text(creating
                         ? tr("تحمي «الحسابات» و«الخزنة». خلّها مختلفة عن كلمة سر الدخول.", "Protects Accounts and Vault. Make it different from your main password.")
                         : tr("اكتب كلمة سر الأقسام", "Enter your section password"))
                        .font(Theme.font(15)).foregroundStyle(Theme.sub).multilineTextAlignment(.center)

                    AYNField(title: tr("كلمة سر الأقسام", "Section password"), icon: icon, text: $password, secure: true,
                             focus: $focus, id: .section) {
                        if creating { focus = .sectionConfirm } else { Task { await submit() } }
                    }
                    if creating {
                        AYNField(title: tr("أكّدها", "Confirm it"), icon: "checkmark.shield.fill", text: $confirm, secure: true,
                                 focus: $focus, id: .sectionConfirm)
                    }
                    if let error {
                        Text(error).font(Theme.font(14, .semibold)).foregroundStyle(Theme.danger)
                    }
                    PrimaryButton(title: creating ? tr("حفظ وفتح", "Save & open") : tr("فتح", "Open"),
                                  icon: "lock.open.fill", loading: loading, enabled: canSubmit) { Task { await submit() } }
                    if !creating && useBio {
                        SecondaryButton(title: Biometrics.name, icon: Biometrics.icon) { Task { await bio() } }
                    }
                }
                .padding(.horizontal, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: password) { _, _ in FX.key() }
            .onChange(of: confirm) { _, _ in FX.key() }
            .onAppear { if !creating && useBio { Task { await bio() } } }
        }
    }

    private var currentMood: EyeMood {
        if mood == .angry || mood == .happy { return mood }
        if creating {
            return PasswordCreator.mood(password: password, confirm: confirm, focused: focus, first: .section, second: .sectionConfirm)
        }
        return focus == .section ? .lookUp : .idle
    }

    private var canSubmit: Bool {
        creating ? (password.count >= 4 && password == confirm) : !password.isEmpty
    }

    private func bio() async {
        if await Biometrics.authenticate(reason: tr("افتح القسم", "Open section")) != nil {
            state.sectionUnlocked = true
            SoundFX.shared.play(.unlock, volume: 0.5)
        }
    }

    private func submit() async {
        guard canSubmit, !loading else { return }
        loading = true
        defer { loading = false }
        if creating {
            if await state.verifyMainPassword(password) {
                error = tr("خلّها مختلفة عن كلمة سر الدخول.", "Use something different from your main password.")
                FX.error()
                return
            }
            await state.setSectionPassword(password)
            withAnimation { mood = .happy }
            SoundFX.shared.play(.unlock, volume: 0.6)
        } else if await state.checkSectionPassword(password) {
            withAnimation { mood = .happy }
            SoundFX.shared.play(.unlock, volume: 0.6)
        } else {
            withAnimation { mood = .angry }
            error = tr("غلط.", "Wrong.")
            password = ""
            state.logScreenEvent(.wrongPassword)
            await pause(1)
            withAnimation { mood = .idle }
        }
    }
}

// MARK: - Extra gate for 🔴 top-secret items: biometrics + section password every time

struct SecretUnlockSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    var onUnlock: () -> Void

    @State private var bioOK = false
    @State private var password = ""
    @State private var error: String?
    @State private var mood: EyeMood = .thinking
    @FocusState private var focus: AYNFieldID?

    var body: some View {
        ZStack {
            AuroraBackground()
            VStack(spacing: 16) {
                SheetHeader(title: tr("محتوى سري جداً", "Top secret")) { dismiss() }
                EyeView(mood: mood, size: 120, sounds: true)
                Label(bioOK || !Biometrics.isAvailable ? tr("تم التحقق بالوجه ✓", "Face verified ✓") : tr("نتحقق من وجهك…", "Checking your face…"),
                      systemImage: Biometrics.icon)
                    .font(Theme.font(15, .semibold))
                    .foregroundStyle(bioOK ? Theme.ok : Theme.sub)
                AYNField(title: tr("كلمة سر الأقسام", "Section password"), icon: "lock.fill", text: $password,
                         secure: true, focus: $focus, id: .section) { Task { await submit() } }
                    .disabled(!bioOK)
                    .opacity(bioOK ? 1 : 0.4)
                if let error { Text(error).font(Theme.font(14, .semibold)).foregroundStyle(Theme.danger) }
                PrimaryButton(title: tr("افتح", "Open"), icon: "lock.open.fill", enabled: bioOK && !password.isEmpty) {
                    Task { await submit() }
                }
                Spacer()
            }
            .padding(20)
        }
        .presentationDetents([.medium, .large])
        .task {
            if !Biometrics.isAvailable { bioOK = true; mood = .idle; return }
            await pause(0.3)
            if await Biometrics.authenticate(reason: tr("فتح محتوى سري", "Open secret item")) != nil {
                withAnimation { bioOK = true; mood = .lookUp }
                focus = .section
            } else {
                withAnimation { mood = .angry }
                error = tr("فشل التحقق بالوجه.", "Face check failed.")
            }
        }
    }

    private func submit() async {
        if await state.checkSectionPassword(password) {
            withAnimation { mood = .happy }
            await pause(0.35)
            dismiss()
            onUnlock()
        } else {
            withAnimation { mood = .angry }
            error = tr("كلمة السر غلط.", "Wrong password.")
            password = ""
        }
    }
}

/// Holds a pending action for a secret item and presents the unlock sheet.
struct SecretAction: Identifiable {
    let id = UUID()
    let run: () -> Void
}
