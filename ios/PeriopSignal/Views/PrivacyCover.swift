import SwiftUI
import UIKit

/// The app-switcher cover. Ben, Nov 19 (after the GPT-6 review): when the app is not the active one (the app switcher, a
/// call, Control Centre, the home gesture), the screen the system takes a picture of must not show patient details. While
/// My Patient is the open tab, or a patient screen is open, the app's plain background and its logo are drawn over
/// everything, sheets included, and removed the moment the app is active again.
enum PrivacyCover {
    /// True when the cover is drawn: the scene is not active, and a patient is on screen (My Patient is the open tab, a
    /// patient has just arrived and waits for an answer, or the case archive is open).
    static func covers(phase: ScenePhase, tab: Router.Tab, patientScreenOpen: Bool) -> Bool {
        phase != .active && (tab == .patient || patientScreenOpen)
    }

    /// The window's interface style for the app's appearance setting (the cover's window is not under the app's
    /// preferredColorScheme, so it is given the style directly).
    static func style(for appearance: Appearance) -> UIUserInterfaceStyle {
        switch appearance {
        case .system: return .unspecified
        case .dark: return .dark
        case .light: return .light
        }
    }
}

/// What the cover shows: the plain background and the logo mark, nothing else.
struct PrivacyCoverView: View {
    var body: some View {
        ZStack {
            PS.bg
            LogoMark(size: 96)
        }
        .ignoresSafeArea()
    }
}

/// The cover's own window, above the app's windows and so above its sheets. It is drawn and removed without animation,
/// takes no touches and never becomes the key window, so it cannot disturb the share sheet, the keyboard or the Face ID
/// prompt (which belongs to the system): it only draws.
@MainActor
final class PrivacyCoverWindow {
    static let shared = PrivacyCoverWindow()
    private var window: UIWindow?

    var isShown: Bool { window != nil }

    func show(style: UIUserInterfaceStyle) {
        guard window == nil else { return }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let w = UIWindow(windowScene: scene)
        w.windowLevel = UIWindow.Level.alert + 1
        w.isUserInteractionEnabled = false
        w.overrideUserInterfaceStyle = style
        let host = UIHostingController(rootView: PrivacyCoverView())
        host.view.backgroundColor = .clear
        w.rootViewController = host
        w.isHidden = false
        w.layoutIfNeeded()
        window = w
    }

    func hide() {
        guard let w = window else { return }
        w.isHidden = true
        w.rootViewController = nil
        window = nil
    }
}
