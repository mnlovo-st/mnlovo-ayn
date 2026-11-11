import UIKit

/// Keeps the app out of screenshots and screen recordings.
///
/// iOS has no switch for this. What it does have is the secure text field: anything drawn inside
/// a password field's text layer comes out blank in screenshots, recordings and AirPlay. So the
/// app's whole window layer is moved inside such a layer. Views, touches and sheets are untouched;
/// only what the screenshot system is allowed to copy changes. Turning protection off is just
/// flipping the field back to a normal one.
///
/// Every step checks itself. If a future iOS version lays the text field out differently and the
/// layer can't be found, or the move doesn't take, it puts the window back where it was and the app
/// simply runs unprotected — never blank.
@MainActor
final class ScreenShield {
    static let shared = ScreenShield()

    private var field: UITextField?
    private weak var window: UIWindow?
    private(set) var active = false

    static var allowScreenshots: Bool { UserDefaults.standard.bool(forKey: "sec.allowScreenshots") }
    static var allowRecording: Bool { UserDefaults.standard.bool(forKey: "sec.allowRecording") }

    /// Puts the window inside the secure layer once, then applies the current settings.
    func install() {
        guard field == nil,
              let win = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows)
                .first(where: \.isKeyWindow),
              let root = win.layer.superlayer else { return }

        let f = UITextField()
        f.isSecureTextEntry = true
        f.isUserInteractionEnabled = false
        f.translatesAutoresizingMaskIntoConstraints = false
        win.addSubview(f)
        NSLayoutConstraint.activate([
            f.centerXAnchor.constraint(equalTo: win.centerXAnchor),
            f.centerYAnchor.constraint(equalTo: win.centerYAnchor),
        ])
        f.layoutIfNeeded()

        guard let canvas = secureLayer(of: f) else {
            f.removeFromSuperview()
            return
        }
        canvas.masksToBounds = false
        f.layer.masksToBounds = false
        root.addSublayer(f.layer)
        canvas.addSublayer(win.layer)

        // Did it take? If the window layer isn't where we put it, undo everything.
        guard win.layer.superlayer === canvas else {
            root.addSublayer(win.layer)
            f.layer.removeFromSuperlayer()
            f.removeFromSuperview()
            return
        }
        field = f
        window = win
        active = true
        apply(captured: UIScreen.main.isCaptured)
    }

    /// Screenshots blocked unless allowed. While a recording is running and recordings are allowed,
    /// the layer has to be open, because the same layer hides the app from both.
    func apply(captured: Bool) {
        guard let field else { return }
        let protect = !Self.allowScreenshots && !(captured && Self.allowRecording)
        if field.isSecureTextEntry != protect { field.isSecureTextEntry = protect }
    }

    /// The text field's drawing layer. Found by name first; the position fallback matches what
    /// iOS 17 and later do (earlier versions put it first).
    private func secureLayer(of f: UITextField) -> CALayer? {
        let subs = f.layer.sublayers ?? []
        if let byName = subs.first(where: { layer in
            guard let d = layer.delegate else { return false }
            return String(describing: type(of: d)).contains("Canvas")
        }) { return byName }
        return subs.last ?? subs.first
    }
}
