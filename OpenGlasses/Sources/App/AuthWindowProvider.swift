import AuthenticationServices
import SwiftUI
import UIKit

/// Retains the actual scene window for the duration of an authentication session.
@MainActor
final class AuthWindowProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let window: UIWindow

    init(window: UIWindow) {
        self.window = window
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        window
    }
}

/// Resolve the window at tap time, including when the view is hosted in a sheet.
@MainActor
struct AuthWindowReader: UIViewRepresentable {
    let source: WindowSource

    @MainActor
    final class WindowSource {
        weak var view: UIView?
        var window: UIWindow? { view?.window }
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        source.view = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        source.view = uiView
    }
}
