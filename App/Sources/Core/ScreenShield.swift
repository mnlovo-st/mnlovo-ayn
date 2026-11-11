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

    /// Both allowed until the person turns protection on in Settings.
    static var allowScreenshots: Bool { UserDefaults.standard.object(forKey: "sec.allowScreenshots") as? Bool ?? true }
    static var allowRecording: Bool { UserDefaults.standard.object(forKey: "sec.allowRecording") as? Bool ?? true }

    /// Puts the window inside the secure layer — but only once someone has actually turned
    /// protection on. With both switches on "allow" the window is never touched at all.
    func install() {
        guard field == nil, !(Self.allowScreenshots && Self.allowRecording),
              let win = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows)
                .first(where: \.isKeyWindow),
              let root = win.layer.superlayer else { return }

        // The field covers the whole window, so its drawing layer starts at the window's corner.
        // (Build 28 centred a zero-size field instead, and the whole app was drawn from the middle
        // of the screen — that's the half-screen picture.)
        let f = UITextField()
        f.isSecureTextEntry = true
        f.isUserInteractionEnabled = false
        f.borderStyle = .none
        f.translatesAutoresizingMaskIntoConstraints = false
        win.addSubview(f)
        NSLayoutConstraint.activate([
            f.leadingAnchor.constraint(equalTo: win.leadingAnchor),
            f.trailingAnchor.constraint(equalTo: win.trailingAnchor),
            f.topAnchor.constraint(equalTo: win.topAnchor),
            f.bottomAnchor.constraint(equalTo: win.bottomAnchor),
        ])
        win.layoutIfNeeded()
        f.layoutIfNeeded()

        guard let canvas = secureLayer(of: f) else {
            f.removeFromSuperview()
            return
        }
        canvas.masksToBounds = false
        f.layer.masksToBounds = false
        root.addSublayer(f.layer)
        canvas.addSublayer(win.layer)
        field = f
        window = win
        self.root = root
        self.canvas = canvas

        // Did it take, and is the app still drawn exactly where it was? Anything else, undo.
        guard win.layer.superlayer === canvas, aligned() else {
            uninstall()
            return
        }
        apply(captured: UIScreen.main.isCaptured)
    }

    private weak var root: CALayer?
    private weak var canvas: CALayer?

    /// The window must land on the screen's corner, to the point. A shifted window means the trick
    /// doesn't fit this iOS version, and the app is better off unprotected than drawn off-screen.
    private func aligned() -> Bool {
        guard let win = window, let root, win.layer.superlayer != nil else { return false }
        let corner = win.layer.convert(CGPoint.zero, to: root)
        let size = win.layer.bounds.size
        return abs(corner.x) < 1 && abs(corner.y) < 1
            && abs(size.width - win.bounds.width) < 1 && abs(size.height - win.bounds.height) < 1
    }

    /// Puts the window back where iOS had it.
    private func uninstall() {
        if let win = window, let root { root.addSublayer(win.layer) }
        field?.layer.removeFromSuperlayer()
        field?.removeFromSuperview()
        field = nil
        window = nil
    }

    /// Screenshots blocked unless allowed. While a recording is running and recordings are allowed,
    /// the layer has to be open, because the same layer hides the app from both.
    func apply(captured: Bool) {
        if field == nil { install() }
        guard let field else { return }
        // Re-check on every change: rotation or a new iOS layout could shift things later.
        guard aligned() else { uninstall(); return }
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
