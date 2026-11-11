import SwiftUI

// MARK: - Shared shell for the first-visit intros
//
// The reminders intro landed well, so the Accounts and Vault intros borrow its shape instead of
// inventing a new one: a phone mock on an aurora background, a caption underneath, dots, and a
// Next button. Everything that differs per section — the scenes and their beats — is passed in,
// so each intro file stays about its own story.

/// Drives one intro. `beats` is how many animation steps each scene plays before it moves on;
/// `screen(scene, step)` draws the inside of the phone for that moment.
struct IntroShell<Screen: View>: View {
    let captions: [(String, String)]
    let beats: [Int]
    let finishIcon: String
    let tint: Color
    @ViewBuilder let screen: (Int, Int) -> Screen
    var onDone: () -> Void

    @State private var scene = 0
    @State private var step = 0
    @State private var auto = true

    private var count: Int { captions.count }

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
                .frame(minHeight: 112, alignment: .top)
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
                              icon: scene == count - 1 ? finishIcon : "arrow.forward") {
                    auto = false
                    if scene == count - 1 { finish() } else { go(scene + 1) }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
        // Swiping feels natural on a card stack like this, and it's faster than reaching for Next.
        .gesture(
            DragGesture(minimumDistance: 24).onEnded { g in
                guard abs(g.translation.width) > abs(g.translation.height) else { return }
                auto = false
                // In Arabic the pages read right-to-left, so a drag to the right means "next".
                let rtl = AppLanguage.current.isRTL
                let forward = rtl ? g.translation.width > 0 : g.translation.width < 0
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
        for b in 1...max(1, beats[scene]) {
            await pause(0.66)
            if Task.isCancelled { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { step = b }
            Haptics.soft(0.28)
        }
        await pause(2.1)
        if auto && !Task.isCancelled && scene < count - 1 { go(scene + 1) }
    }

    private var phone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34).fill(Color.black.opacity(0.62))
            screen(scene, step)
                .padding(.horizontal, 14).padding(.top, 34).padding(.bottom, 16)
            RoundedRectangle(cornerRadius: 34).strokeBorder(
                LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)], startPoint: .top, endPoint: .bottom),
                lineWidth: 2)
            Capsule().fill(Color.black).frame(width: 64, height: 18).frame(maxHeight: .infinity, alignment: .top).padding(.top, 10)
        }
        .shadow(color: tint.opacity(0.28), radius: 24)
    }
}

/// Small shared pieces the section screens draw with.
enum IntroBits {
    static func bar(_ w: CGFloat, _ c: Color = Theme.surfaceHi, h: CGFloat = 6) -> some View {
        RoundedRectangle(cornerRadius: 3).fill(c).frame(width: w, height: h)
    }

    static func row(_ icon: String, _ title: String, _ sub: String, tint: Color, on: Bool) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 8).fill(on ? AnyShapeStyle(tint.opacity(0.9)) : AnyShapeStyle(Theme.surfaceHi))
                .frame(width: 24, height: 24)
                .overlay(Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(on ? .white : Theme.faint))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.font(10, .bold)).foregroundStyle(Theme.text)
                Text(sub).font(Theme.font(8)).foregroundStyle(Theme.sub)
            }
            Spacer(minLength: 0)
        }
        .padding(7)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
        .opacity(on ? 1 : 0.35)
    }
}

// MARK: - Accounts

/// Four scenes: add an account → the vault locks it → the rotating code → it travels to Telegram,
/// ciphered if you want. The point to land is that nothing leaves the phone readable.
struct AccountsIntro: View {
    var onDone: () -> Void

    var body: some View {
        IntroShell(
            captions: [
                (tr("كل حساباتك في مكان واحد", "All your accounts in one place"),
                 tr("اسم التطبيق، المستخدم، كلمة السر، الرابط. وتحدد حساسية كل حساب: عادي، حساس، أو سري.",
                    "App name, login, password, link. And you set how sensitive each one is: normal, sensitive or secret.")),
                (tr("تنقفل قبل ما تنحفظ", "Locked before they're saved"),
                 tr("كل شي يُشفّر على تلفونك بمفتاح محمي بـ Secure Enclave. لا أنا ولا السيرفر نقدر نقراها.",
                    "Everything is encrypted on your phone with a key held in the Secure Enclave. Neither I nor the server can read it.")),
                (tr("ورمز التحقق المتغير معاك دايماً", "And your rotating code is always here"),
                 tr("تضيف الـ 2FA للحساب، والرمز يتجدد كل ٣٠ ثانية ويتنسخ بضغطة. وتقدر تضيفه لتطبيق كلمات مرور آيفون.",
                    "Add 2FA to an account and the code refreshes every 30 seconds, one tap to copy. You can also add it to the iPhone Passwords app.")),
                (tr("وإذا تبا، يوصل تيليجرامك", "And if you like, it reaches your Telegram"),
                 tr("بعد كل إضافة أسألك: تطرشه؟ وبأي تشفيرة؟ ويوصل مغطّى، ولا أحد يفهمه إلا إنت.",
                    "After each save I ask: send it? and with which cipher? It arrives covered, and only you can read it."))
            ],
            beats: [4, 4, 4, 4],
            finishIcon: "key.horizontal.fill",
            tint: Theme.accent,
            screen: { scene, step in
                Group {
                    switch scene {
                    case 0: addScreen(step)
                    case 1: lockScreen(step)
                    case 2: totpScreen(step)
                    default: sendScreen(step)
                    }
                }
            },
            onDone: onDone
        )
    }

    private func addScreen(_ step: Int) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(tr("حساب جديد", "New account")).font(Theme.font(13, .heavy)).foregroundStyle(Theme.text)
            field(tr("التطبيق", "App"), step >= 1 ? "Instagram" : "")
            field(tr("المستخدم", "Login"), step >= 2 ? "saif@mnlovo" : "")
            field(tr("كلمة السر", "Password"), step >= 3 ? "••••••••••" : "")
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    let names = [tr("عادي", "Normal"), tr("حساس", "Sensitive"), tr("سري", "Secret")]
                    let tints: [Color] = [Theme.ok, Theme.warn, Theme.danger]
                    Text(names[i]).font(Theme.font(8, .bold))
                        .foregroundStyle(i == 2 && step >= 4 ? .white : Theme.sub)
                        .frame(maxWidth: .infinity).frame(height: 22)
                        .background(Capsule().fill(i == 2 && step >= 4 ? AnyShapeStyle(tints[i]) : AnyShapeStyle(Theme.surface)))
                }
            }
            Spacer()
            Text(tr("حفظ", "Save")).font(Theme.font(12, .heavy)).foregroundStyle(Theme.bg)
                .frame(maxWidth: .infinity).frame(height: 32)
                .background(Capsule().fill(Theme.gradient))
                .scaleEffect(step >= 4 ? 0.94 : 1)
        }
    }

    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(Theme.font(8, .bold)).foregroundStyle(Theme.faint)
            Text(value.isEmpty ? " " : value).font(Theme.font(11, .semibold)).foregroundStyle(Theme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
    }

    /// The readable row folds into a locked block — the one picture that explains local encryption.
    private func lockScreen(_ step: Int) -> some View {
        VStack(spacing: 12) {
            Spacer()
            VStack(alignment: .leading, spacing: 4) {
                if step >= 2 {
                    Text("8f3a·c1d9·77be·04aa").font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.accent3)
                    Text("e2b0·9c4f·a518·6d31").font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.accent3.opacity(0.7))
                } else {
                    Text("Instagram").font(Theme.font(11, .bold)).foregroundStyle(Theme.text)
                    Text("saif@mnlovo · ••••••").font(Theme.font(10)).foregroundStyle(Theme.sub)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
            .rotation3DEffect(.degrees(step == 1 ? 180 : 0), axis: (x: 1, y: 0, z: 0))

            ZStack {
                Circle().fill(Theme.ok.opacity(step >= 3 ? 0.18 : 0)).frame(width: 64, height: 64)
                Image(systemName: step >= 3 ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(step >= 3 ? Theme.ok : Theme.faint)
            }
            Text(step >= 4 ? tr("Secure Enclave يحفظ المفتاح 🔑", "Secure Enclave holds the key 🔑") : tr("AES-256", "AES-256"))
                .font(Theme.font(10, .bold)).foregroundStyle(step >= 4 ? Theme.ok : Theme.sub)
            Spacer()
        }
    }

    private func totpScreen(_ step: Int) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Text("Instagram").font(Theme.font(11, .bold)).foregroundStyle(Theme.sub)
            Text(["846 215", "309 774", "521 088", "974 630"][min(step, 3)])
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.text)
                .contentTransition(.numericText())
            // the 30-second ring, draining
            ZStack {
                Circle().stroke(Theme.surfaceHi, lineWidth: 4).frame(width: 46, height: 46)
                Circle().trim(from: 0, to: max(0.05, 1 - Double(step) / 4))
                    .stroke(Theme.gradient, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 46, height: 46)
                Text("\(max(1, 30 - step * 7))").font(Theme.font(12, .heavy)).foregroundStyle(Theme.sub)
            }
            if step >= 3 {
                Label(tr("تنسخ بضغطة", "One tap to copy"), systemImage: "doc.on.doc.fill")
                    .font(Theme.font(9, .bold)).foregroundStyle(Theme.ok)
            }
            Spacer()
        }
    }

    private func sendScreen(_ step: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(TelegramService.blue).frame(width: 20, height: 20)
                    .overlay(Image(systemName: "paperplane.fill").font(.system(size: 9)).foregroundStyle(.white))
                Text("Telegram").font(Theme.font(9, .heavy)).foregroundStyle(Theme.text)
                Spacer(minLength: 0)
            }
            Spacer()
            if step >= 1 {
                VStack(alignment: .leading, spacing: 5) {
                    Text(tr("🔐 حساب جديد", "🔐 New account")).font(Theme.font(10, .heavy)).foregroundStyle(Theme.text)
                    if step >= 3 {
                        Text("◈◆◉○●◐◑◒ ◓▲△▼▽◢◣◈")
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.accent3)
                        Text("◆◑○●◣▽◢◐ ◒◈△▲◓◉●○")
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.accent3.opacity(0.75))
                    } else {
                        IntroBits.bar(84, Theme.faint); IntroBits.bar(64, Theme.faint)
                    }
                }
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surfaceHi))
                .blur(radius: step == 2 ? 4 : 0)
                .transition(.scale(scale: 0.6, anchor: .bottomLeading).combined(with: .opacity))
            }
            if step >= 4 {
                Label(tr("ولا أحد يفهمه غيرك", "Unreadable to everyone else"), systemImage: "eye.slash.fill")
                    .font(Theme.font(9, .bold)).foregroundStyle(Theme.ok)
            }
            Spacer()
        }
    }
}

// MARK: - Vault

/// Four scenes: what goes in → the section passcode → the decoy password → intruder photos.
struct VaultIntro: View {
    var onDone: () -> Void

    var body: some View {
        IntroShell(
            captions: [
                (tr("الخزنة للأشياء اللي ما تنسى", "The vault is for what you can't lose"),
                 tr("صور الهوية والجوازات، ملفات، ملاحظات سرّية، أي شي تباه بعيد عن الألبوم والواتساب.",
                    "ID and passport photos, files, private notes — anything you want out of your gallery and your chats.")),
                (tr("قفل ثاني فوق قفل التطبيق", "A second lock above the app's lock"),
                 tr("للخزنة رمز خاص فيها. يعني لو أحد فتح التطبيق بوجهك وإنت نايم، الخزنة بعدها مقفولة.",
                    "The vault has its own passcode. So even if someone opens the app, the vault is still shut.")),
                (tr("وعندك كلمة مرور مزيّفة", "And you have a decoy password"),
                 tr("لو أحد ضغط عليك، تعطيه الكلمة المزيّفة: التطبيق يفتح على خزنة فاضية وكل شي الحقيقي مخفي.",
                    "If someone pressures you, give them the decoy: the app opens on an empty vault and the real one stays hidden.")),
                (tr("وأصوّر أي أحد يحاول", "And I photograph whoever tries"),
                 tr("من ثاني محاولة غلط تنصوّر بالكاميرا الأمامية مع الوقت، تنحفظ لك وتوصلك على تيليجرام فوراً.",
                    "From the second wrong try: a front-camera photo with the time, kept for you and sent straight to your Telegram."))
            ],
            beats: [4, 4, 3, 4],
            finishIcon: "lock.shield.fill",
            tint: Theme.accent2,
            screen: { scene, step in
                Group {
                    switch scene {
                    case 0: contentsScreen(step)
                    case 1: passcodeScreen(step)
                    case 2: decoyScreen(step)
                    default: intruderScreen(step)
                    }
                }
            },
            onDone: onDone
        )
    }

    private func contentsScreen(_ step: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("الخزنة", "Vault")).font(Theme.font(13, .heavy)).foregroundStyle(Theme.text)
            IntroBits.row("person.text.rectangle.fill", tr("الهوية", "ID card"), tr("صورة · 2.1 MB", "image · 2.1 MB"),
                          tint: Theme.accent, on: step >= 1)
            IntroBits.row("airplane", tr("الجواز", "Passport"), tr("صورة · 1.8 MB", "image · 1.8 MB"),
                          tint: Theme.accent2, on: step >= 2)
            IntroBits.row("doc.fill", tr("عقد الشغل", "Work contract"), tr("PDF · 340 KB", "PDF · 340 KB"),
                          tint: Theme.accent3, on: step >= 3)
            IntroBits.row("note.text", tr("ملاحظة سرّية", "Private note"), tr("نص مشفّر", "encrypted text"),
                          tint: Color(hex: 0xFF5FA2), on: step >= 4)
            Spacer()
            Label(tr("كلها مشفّرة على تلفونك", "All encrypted on your phone"), systemImage: "lock.fill")
                .font(Theme.font(9, .bold)).foregroundStyle(Theme.ok)
        }
    }

    private func passcodeScreen(_ step: Int) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: step >= 4 ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(step >= 4 ? Theme.ok : Theme.accent2)
            Text(tr("رمز الخزنة", "Vault passcode")).font(Theme.font(11, .bold)).foregroundStyle(Theme.sub)
            HStack(spacing: 9) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(i < step ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.surfaceHi))
                        .frame(width: 13, height: 13)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(1...9, id: \.self) { n in
                    Text("\(n)").font(Theme.font(12, .bold)).foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity).frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
                }
            }
            .padding(.top, 2)
            Spacer()
        }
    }

    private func decoyScreen(_ step: Int) -> some View {
        VStack(spacing: 10) {
            Spacer()
            HStack(spacing: 10) {
                vaultCard(title: tr("المزيّفة", "Decoy"), empty: true, lit: step >= 2)
                vaultCard(title: tr("الحقيقية", "Real"), empty: false, lit: step >= 3)
            }
            Text(step >= 3 ? tr("الحقيقية تبقى مخفية تماماً", "The real one stays completely hidden")
                           : tr("كلمة مرور مختلفة = خزنة مختلفة", "A different password = a different vault"))
                .font(Theme.font(10, .bold)).foregroundStyle(step >= 3 ? Theme.ok : Theme.sub)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    private func vaultCard(title: String, empty: Bool, lit: Bool) -> some View {
        VStack(spacing: 6) {
            Text(title).font(Theme.font(9, .heavy)).foregroundStyle(Theme.text)
            VStack(spacing: 4) {
                if empty {
                    Image(systemName: "tray").font(.system(size: 16)).foregroundStyle(Theme.faint)
                    Text(tr("فاضية", "Empty")).font(Theme.font(8)).foregroundStyle(Theme.faint)
                } else {
                    IntroBits.bar(50, Theme.accent.opacity(0.8), h: 5)
                    IntroBits.bar(42, Theme.accent2.opacity(0.8), h: 5)
                    IntroBits.bar(46, Theme.accent3.opacity(0.8), h: 5)
                }
            }
            .frame(height: 46)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(lit ? (empty ? Theme.warn : Theme.ok) : Theme.stroke, lineWidth: 1.5))
        .opacity(lit ? 1 : 0.4)
    }

    private func intruderScreen(_ step: Int) -> some View {
        VStack(spacing: 9) {
            Spacer()
            HStack(spacing: 5) {
                ForEach(0..<2, id: \.self) { i in
                    Image(systemName: step > i ? "xmark.circle.fill" : "circle")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(step > i ? Theme.danger : Theme.faint)
                }
            }
            // the "CCTV" frame the app actually stamps
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.75))
                if step >= 2 {
                    Image(systemName: "person.fill.questionmark")
                        .font(.system(size: 30)).foregroundStyle(Theme.faint)
                }
                VStack {
                    HStack {
                        Text(step >= 2 ? "● REC" : "").font(.system(size: 7, weight: .black)).foregroundStyle(Theme.danger)
                        Spacer()
                    }
                    Spacer()
                    HStack {
                        Text(step >= 2 ? "09:41 · \(tr("المحاولة رقم 2", "Attempt no. 2"))" : "")
                            .font(.system(size: 7, weight: .bold, design: .monospaced)).foregroundStyle(.white.opacity(0.8))
                        Spacer()
                    }
                }
                .padding(6)
            }
            .frame(height: 96)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.danger.opacity(step >= 2 ? 0.7 : 0.2), lineWidth: 1.5))
            if step >= 3 {
                Label(tr("وصلت لك الصورة ✓", "The photo reached you ✓"), systemImage: "paperplane.fill")
                    .font(Theme.font(9, .bold)).foregroundStyle(TelegramService.blue)
            }
            Spacer()
        }
    }
}
