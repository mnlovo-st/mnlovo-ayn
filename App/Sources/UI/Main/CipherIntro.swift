import SwiftUI

// MARK: - First-time explainer for the cipher feature

/// Three scenes: a plain message anyone can read → the same message run through a cipher →
/// the app's own tool turning it back. Shown once, the first time the send prompt appears.
struct CipherIntro: View {
    var onDone: () -> Void

    var body: some View {
        IntroShell(
            captions: [
                (tr("أي رسالة في تيليجرام، مقروءة", "Any Telegram message is readable"),
                 tr("مغطّاة، صح — بس أي أحد يمسكها يقدر يكشفها بلمسة. وتيليجرام نفسه يشوفها.",
                    "Covered, yes — but anyone holding your phone can tap to reveal it. And Telegram itself can read it.")),
                (tr("فشفّرها قبل ما تطلع", "So cipher it before it leaves"),
                 tr("التطبيق يحوّلها لطلاسم على تلفونك، وبعدين يرسلها. اللي يوصل تيليجرام طلاسم من الأصل.",
                    "The app turns it into gibberish on your phone first, then sends that. What reaches Telegram was never readable.")),
                (tr("وما يفكّها إلا إنت", "And only you can undo it"),
                 tr("ترجع تنسخها وتلصقها في «أداة التشفير» بالتطبيق وتطلع واضحة. وفي AES بكلمة مرور تعرفها إنت بس.",
                    "Copy it back into the app's Cipher tool and it comes out clear. Or use AES with a password only you know."))
            ],
            beats: [3, 5, 4],
            finishIcon: "lock.shield.fill",
            tint: Theme.accent3,
            screen: { scene, step in
                Group {
                    switch scene {
                    case 0: plainScreen(step)
                    case 1: scrambleScreen(step)
                    default: decodeScreen(step)
                    }
                }
            },
            onDone: onDone
        )
    }

    private func bubble<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(Theme.font(10, .heavy)).foregroundStyle(Theme.text)
            content()
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surfaceHi))
    }

    private func chatHeader(_ name: String, _ icon: String, _ tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 20, height: 20)
                .overlay(Image(systemName: icon).font(.system(size: 9, weight: .bold)).foregroundStyle(.white))
            Text(name).font(Theme.font(9, .heavy)).foregroundStyle(Theme.text)
            Spacer(minLength: 0)
        }
    }

    private func plainScreen(_ step: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            chatHeader("Telegram", "paperplane.fill", TelegramService.blue)
            Spacer()
            bubble(tr("🔐 حساب جديد", "🔐 New account")) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Instagram").font(Theme.font(10, .bold)).foregroundStyle(Theme.text)
                    Text("saif@mnlovo").font(Theme.font(10)).foregroundStyle(Theme.sub)
                    Text(step >= 2 ? "Mn!2026$aver" : "••••••••••")
                        .font(Theme.font(10, .bold))
                        .foregroundStyle(step >= 2 ? Theme.danger : Theme.sub)
                }
                .blur(radius: step >= 1 ? 0 : 5)
            }
            if step >= 3 {
                Label(tr("لمسة وحدة وانكشفت", "One tap and it's exposed"), systemImage: "hand.tap.fill")
                    .font(Theme.font(9, .bold)).foregroundStyle(Theme.danger)
            }
            Spacer()
        }
    }

    /// The letters turn from readable into symbols, a few at a time.
    private func scrambleScreen(_ step: Int) -> some View {
        let plain = ["Instagram", "saif@mnlovo", "Mn!2026$aver"]
        let cipherGlyphs = ["◈◇◆◉○●◐◑◒", "◓▲△▼▽◢◣◈◇◆◉", "●◐◑◒◓▲△▼▽◢◣◈"]
        return VStack(alignment: .leading, spacing: 8) {
            chatHeader(tr("على تلفونك", "On your phone"), "iphone", Theme.accent3)
            Spacer()
            bubble(tr("🔐 حساب مشفّر", "🔐 Encrypted account")) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(0..<3, id: \.self) { i in
                        Text(step > i + 1 ? cipherGlyphs[i] : plain[i])
                            .font(step > i + 1 ? .system(size: 11, weight: .bold) : Theme.font(10, .semibold))
                            .foregroundStyle(step > i + 1 ? Theme.accent3 : Theme.sub)
                            .animation(.easeInOut(duration: 0.3), value: step)
                    }
                }
            }
            if step >= 5 {
                Label(tr("كذا ينطرش — ما فيه شي مقروء", "That's what's sent — nothing readable"), systemImage: "checkmark.shield.fill")
                    .font(Theme.font(9, .bold)).foregroundStyle(Theme.ok)
            }
            Spacer()
        }
    }

    private func decodeScreen(_ step: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            chatHeader(tr("أداة التشفير", "Cipher tool"), "character.bubble.fill", Theme.accent)
            Spacer()
            VStack(alignment: .leading, spacing: 6) {
                Text("◈◇◆◉○●◐◑◒ ◓▲△▼▽◢◣")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.accent3)
                    .padding(7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Theme.surface))
                Image(systemName: "arrow.down")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(step >= 2 ? Theme.accent : Theme.faint)
                    .frame(maxWidth: .infinity)
                if step >= 3 {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Instagram").font(Theme.font(10, .bold)).foregroundStyle(Theme.text)
                        Text("saif@mnlovo · Mn!2026$aver").font(Theme.font(10)).foregroundStyle(Theme.ok)
                    }
                    .padding(7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Theme.ok.opacity(0.12)))
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            if step >= 4 {
                Label(tr("الفك يصير عندك، مب عند أحد ثاني", "The undo happens here, nowhere else"), systemImage: "iphone.gen3")
                    .font(Theme.font(9, .bold)).foregroundStyle(Theme.ok)
            }
            Spacer()
        }
    }
}

// MARK: - Live preview inside the send prompt

/// Shows the real cipher output for the account about to be sent, revealing itself character by
/// character. It's the explainer and the proof at once: what you see here is literally what goes out.
struct CipherPreview: View {
    let plain: String
    let cipher: Cipher
    let key: String

    @State private var shown = 0
    @State private var out = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "eye.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.accent3)
                Text(tr("هذا اللي بيوصل تيليجرام", "This is what reaches Telegram"))
                    .font(Theme.font(12, .bold)).foregroundStyle(Theme.sub)
                Spacer()
            }
            Text(visible.isEmpty ? " " : visible)
                .font(.system(size: 12, weight: .bold, design: cipher == .mnlovo || cipher == .emoji || cipher == .morse ? .default : .monospaced))
                .foregroundStyle(Theme.accent3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 64, alignment: .topLeading)
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.accent3.opacity(0.3)))
                .animation(.linear(duration: 0.05), value: shown)
        }
        .task(id: "\(cipher.rawValue)|\(key)") { await run() }
    }

    /// Capped so a long account doesn't turn the sheet into a wall of symbols.
    private var visible: String {
        String(out.prefix(shown).prefix(160))
    }

    private func run() async {
        out = cipher.encode(plain, key: key.isEmpty ? "demo" : key)
        shown = 0
        let target = min(out.count, 160)
        while shown < target {
            await pause(0.012)
            if Task.isCancelled { return }
            shown = min(target, shown + 2)
        }
    }
}
