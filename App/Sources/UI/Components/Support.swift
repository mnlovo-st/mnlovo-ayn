import SwiftUI

/// Direct line to MNLOVO support (Saif) on Telegram or Instagram.
enum Support {
    static let telegram = "bscoolvi"
    static let instagram = "4saf"
    static var telegramURL: URL { URL(string: "https://t.me/\(telegram)")! }
    static var instagramURL: URL { URL(string: "https://instagram.com/\(instagram)")! }
}

/// Small "Need help?" button that opens the support chooser.
struct SupportButton: View {
    var prominent = false
    var context: String = ""
    @State private var show = false

    var body: some View {
        Button {
            Haptics.tap()
            show = true
        } label: {
            if prominent {
                HStack(spacing: 8) {
                    Image(systemName: "lifepreserver.fill")
                    Text(tr("تواصل مع الدعم الفني", "Contact support"))
                }
                .font(Theme.font(15, .bold))
                .foregroundStyle(Theme.accent2)
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(Capsule().fill(Theme.accent2.opacity(0.14)))
                .overlay(Capsule().strokeBorder(Theme.accent2.opacity(0.4)))
            } else {
                Label(tr("الدعم الفني", "Support"), systemImage: "lifepreserver.fill")
                    .font(Theme.font(14, .semibold))
                    .foregroundStyle(Theme.accent2)
            }
        }
        .buttonStyle(PressScale())
        .sheet(isPresented: $show) {
            SupportSheet(context: context).presentationDetents([.height(430)])
        }
    }
}

struct SupportSheet: View {
    var context: String = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            AuroraBackground()
            VStack(spacing: 14) {
                SheetHeader(title: tr("الدعم الفني", "Support")) { dismiss() }
                EyeView(mood: .happy, size: 70, sounds: false)
                Text(tr("تورّطت؟ ولا يهمك 🤝 كلّمنا مباشرة، وين تحب؟", "Stuck? No worries 🤝 Talk to us directly. Where would you like?"))
                    .font(Theme.font(16, .bold)).foregroundStyle(Theme.text).multilineTextAlignment(.center)
                channel(icon: "paperplane.fill", title: "Telegram", handle: "@\(Support.telegram)",
                        colors: [Color(hex: 0x2AABEE), Color(hex: 0x229ED9)]) { openURL(Support.telegramURL) }
                channel(icon: "camera.fill", title: "Instagram", handle: "@\(Support.instagram)",
                        colors: [Color(hex: 0xF58529), Color(hex: 0xDD2A7B), Color(hex: 0x8134AF)]) { openURL(Support.instagramURL) }
                Text(tr("ما نطلب منك أبداً كلمة السر أو مفتاح الاسترجاع.", "We'll never ask for your password or recovery key."))
                    .font(Theme.font(12, .medium)).foregroundStyle(Theme.warn)
            }
            .padding(20)
        }
    }

    private func channel(icon: String, title: String, handle: String, colors: [Color], action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap(.medium)
            action()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(RoundedRectangle(cornerRadius: 14).fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.font(17, .heavy)).foregroundStyle(Theme.text)
                    Text(handle).font(Theme.font(14, .medium)).foregroundStyle(Theme.sub)
                        .environment(\.layoutDirection, .leftToRight)
                }
                Spacer()
                Image(systemName: "arrow.up.forward.app.fill").font(.system(size: 20)).foregroundStyle(Theme.sub)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 20).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.stroke))
        }
        .buttonStyle(PressScale())
    }
}
