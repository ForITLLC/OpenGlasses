import XCTest
import SwiftUI
import UIKit
@testable import OpenGlasses

/// Captures the actual shared gate inside the maintained native qualification job.
/// These images are reviewed separately; capture success is not a UX approval.
@MainActor
final class ForAuthGateCaptureTests: XCTestCase {
    func testCaptureSharedGateForNativeReview() async throws {
        guard let output = ProcessInfo.processInfo.environment["OPENGLASSES_RENDER_EVIDENCE"] else {
            throw XCTSkip("Rendered evidence is requested by the maintained Mini release route")
        }
        let account = AppAccount.shared
        let oldProblem = account.problem
        let previousWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        defer { account.problem = oldProblem; previousWindow?.makeKey() }

        for (name, size, category, problem) in [
            ("iphone-default", CGSize(width: 393, height: 852), ContentSizeCategory.large, Optional<String>.none),
            ("iphone-small-error-ax3", CGSize(width: 320, height: 568), .accessibilityExtraExtraExtraLarge,
             Optional("Couldn't finish signing you in. Try again."))
        ] {
            account.problem = problem
            let host = UIHostingController(rootView: OnboardingView(onComplete: {})
                .environment(\.sizeCategory, category))
            let window: UIWindow
            if let scene = previousWindow?.windowScene { window = UIWindow(windowScene: scene) }
            else { window = UIWindow(frame: CGRect(origin: .zero, size: size)) }
            window.frame = CGRect(origin: .zero, size: size)
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.frame = window.bounds
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            await Task.yield()
            let image = UIGraphicsImageRenderer(size: size).image { context in
                host.view.layer.render(in: context.cgContext)
            }
            let data = try XCTUnwrap(image.pngData())
            let attachment = XCTAttachment(image: image)
            attachment.name = "ForAuth-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
            // The existing native evidence collector retains .log files.
            let file = URL(fileURLWithPath: output).appendingPathComponent("ForAuth-\(name).png.base64.log")
            try data.base64EncodedString().write(to: file, atomically: true, encoding: .utf8)
            window.isHidden = true
        }
    }
}
