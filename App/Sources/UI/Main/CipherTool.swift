import SwiftUI

/// Encode text into any of the reversible ciphers, or paste a mystery blob and let the app decode it.
struct CipherToolView: View {
    enum Tab { case decode, encode }
    @State private var tab: Tab = .decode
    @State private var input = ""
    @State private var key = ""
    @State private var cipher: Cipher = .mnlovo
    @State private var result = ""
    @State private var detected: Cipher?
    @State private var failed = false
    @FocusState private var focused: Bool
    @FocusState private var keyFocus: AYNFieldID?

    var body: some View {
        SheetScaffold(title: tr("أداة التشفير", "Cipher tool")) {
            picker
            inputCard
            if tab == .encode { cipherChooser } else { autoHint }
            if cipher.needsKey || tab == .decode { keyField }
            actionButton
            if !result.isEmpty || failed { resultCard }
        }
        .onChange(of: tab) { _, _ in result = ""; detected = nil; failed = false }
    }

    private var picker: some View {
        HStack(spacing: 0) {
            seg(tr("فك الترجمة", "Decode"), "lock.open.rotation", .decode)
            seg(tr("تشفير", "Encode"), "lock.rotation", .encode)
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
    }

    private func seg(_ title: String, _ icon: String, _ t: Tab) -> some View {
        Button {
            Haptics.selection()
            withAnimation(.spring(response: 0.3)) { tab = t }
        } label: {
            Label(title, systemImage: icon)
                .font(Theme.font(14, .bold))
                .foregroundStyle(tab == t ? Theme.bg : Theme.sub)
                .frame(maxWidth: .infinity).frame(height: 40)
                .background { if tab == t { Capsule().fill(Theme.gradient) } }
        }
        .buttonStyle(PressScale())
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(tab == .encode ? tr("النص اللي تبا تشفّره", "Text to encode") : tr("الصق النص المشفّر", "Paste the encoded text"))
                    .font(Theme.font(13, .bold)).foregroundStyle(Theme.sub)
                Spacer()
                PasteButton(payloadType: String.self) { items in
                    if let t = items.first { DispatchQueue.main.async { input = t; Haptics.success() } }
                }
                .labelStyle(.iconOnly).buttonBorderShape(.capsule).tint(Theme.accent)
                if !input.isEmpty {
                    Button { input = ""; result = ""; detected = nil; failed = false } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.faint)
                    }
                }
            }
            TextEditor(text: $input)
                .focused($focused)
                .font(Theme.mono(15))
                .foregroundStyle(Theme.text)
                .scrollContentBackground(.hidden)
                .frame(height: 110)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(focused ? Theme.accent.opacity(0.6) : Theme.stroke))
        }
    }

    private var autoHint: some View {
        Label(tr("نكتشف نوع التشفير تلقائياً. لو كان بكلمة مرور أو إزاحة، حطها تحت.",
                 "We auto-detect the cipher. If it used a password or a shift, enter it below."),
              systemImage: "sparkles")
            .font(Theme.font(12, .medium)).foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(10, tint: Theme.accent)
    }

    private var cipherChooser: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("اختر الطريقة", "Choose a method")).font(Theme.font(13, .bold)).foregroundStyle(Theme.sub)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                ForEach(Cipher.allCases) { c in
                    Button {
                        Haptics.selection()
                        withAnimation(.spring(response: 0.3)) { cipher = c }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: c.icon).font(.system(size: 14, weight: .bold))
                                .foregroundStyle(cipher == c ? Theme.accent : Theme.sub).frame(width: 20)
                            Text(c.title).font(Theme.font(13, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(cipher == c ? Theme.accent.opacity(0.14) : Theme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(cipher == c ? Theme.accent.opacity(0.5) : Theme.stroke))
                    }
                    .buttonStyle(PressScale())
                }
            }
            Text(cipher.blurb).font(Theme.font(12)).foregroundStyle(Theme.faint)
                .id(cipher).transition(.opacity)
        }
    }

    private var keyField: some View {
        VStack(alignment: .leading, spacing: 6) {
            if tab == .encode && !cipher.needsKey { EmptyView() } else {
                AYNField(title: cipher.keyIsNumber ? tr("رقم الإزاحة", "Shift number") : tr("كلمة المرور (إن وجدت)", "Password (if any)"),
                         icon: "key.fill", text: $key, secure: !cipher.keyIsNumber,
                         keyboard: cipher.keyIsNumber ? .numberPad : .default, focus: $keyFocus, id: .secret)
                    .environment(\.layoutDirection, .leftToRight)
            }
        }
    }

    private var actionButton: some View {
        PrimaryButton(title: tab == .encode ? tr("شفّر", "Encode") : tr("فك", "Decode"),
                      icon: tab == .encode ? "lock.fill" : "lock.open.fill",
                      enabled: !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            run()
        }
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let d = detected {
                    Label(tr("اكتُشف: \(d.title)", "Detected: \(d.title)"), systemImage: d.icon)
                        .font(Theme.font(12, .bold)).foregroundStyle(Theme.ok)
                } else {
                    Text(tr("النتيجة", "Result")).font(Theme.font(13, .bold)).foregroundStyle(Theme.sub)
                }
                Spacer()
                if !result.isEmpty {
                    Button { Clipboard.copy(result); Haptics.success() } label: {
                        Label(tr("نسخ", "Copy"), systemImage: "doc.on.doc.fill").font(Theme.font(13, .bold)).foregroundStyle(Theme.accent)
                    }
                }
            }
            if failed {
                Label(tr("ما قدرنا نفك هذا. جرّب كلمة المرور أو طريقة ثانية.", "Couldn't decode that. Try a password or another method."),
                      systemImage: "questionmark.circle.fill")
                    .font(Theme.font(14, .semibold)).foregroundStyle(Theme.warn)
            } else {
                Text(result)
                    .font(Theme.mono(16))
                    .foregroundStyle(Theme.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surfaceHi))
            }
        }
        .glass(12)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func run() {
        focused = false
        detected = nil
        failed = false
        let text = input
        if tab == .encode {
            withAnimation { result = cipher.encode(text, key: key) }
            Haptics.success()
        } else {
            if let auto = Cipher.decodeAuto(text, key: key) {
                withAnimation { detected = auto.0; result = auto.1 }
                Haptics.success()
            } else if !key.isEmpty, let p = try? AESText.decrypt(text, pass: key) {
                withAnimation { detected = .aes; result = p }
                Haptics.success()
            } else {
                withAnimation { result = ""; failed = true }
                FX.error()
            }
        }
    }
}
