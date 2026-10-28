import XCTest
import UIKit

/// DEBUG fixture proof only. These samples suppress external services and disable
/// main-canvas hit testing; they do not test glasses, microphone, camera, transport
/// or account mutations. No credential or persisted preference is reset here.
///
/// Run the requested-light/dark methods separately with the simulator's appearance
/// set by the owning runner. Launch arguments are requests, not appearance proof:
/// Common 0.31.9's native-iOS harness does not override appearance, and the current
/// home/detail/settings/launch product views explicitly prefer dark rendering.
@MainActor
final class OpenGlassesVisualProofTests: XCTestCase {
    private enum Scene: String, CaseIterable {
        case gate, home, detail, settings, launch

        var sourceAppearancePolicy: String {
            self == .gate ? "actual-appearance-unverified" : "source-prefers-dark-actual-unverified"
        }
    }

    private enum Appearance: String {
        case light, dark

        var appleArgument: String { self == .light ? "Light" : "Dark" }
    }

    private enum TextSize: String, CaseIterable {
        case standard, ax5

        var launchArgument: String {
            switch self {
            case .standard: return "UICTContentSizeCategoryL"
            case .ax5: return "UICTContentSizeCategoryAccessibilityXXXL"
            }
        }
    }

    private enum FixtureFailure: Error {
        case notReady(String)
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    // Stable -only-testing selectors. Each scene test captures five named scenes.
    func testFixtureScenesRequestedLightStandard() throws {
        try captureScenes(appearance: .light, size: .standard)
    }

    func testFixtureScenesRequestedDarkStandard() throws {
        try captureScenes(appearance: .dark, size: .standard)
    }

    func testFixtureScenesRequestedLightAX5() throws {
        try captureScenes(appearance: .light, size: .ax5)
    }

    func testFixtureScenesRequestedDarkAX5() throws {
        try captureScenes(appearance: .dark, size: .ax5)
    }

    // These exercise the real toolbar button and shared panel, not a pre-open mock.
    func testProfilePanelRequestedLightStandardAndAX5() throws {
        try captureProfilePanels(appearance: .light)
    }

    func testProfilePanelRequestedDarkStandardAndAX5() throws {
        try captureProfilePanels(appearance: .dark)
    }

    private func launch(scene: Scene, appearance: Appearance, size: TextSize) -> XCUIApplication {
        // XCUIApplication() resolves the app selected by this UI target's dependency.
        let app = XCUIApplication()
        app.launchArguments = [
            "-screenshot-scene", scene.rawValue,
            "-forit-appearance", appearance.rawValue,
            "-AppleInterfaceStyle", appearance.appleArgument,
            "-UIPreferredContentSizeCategoryName", size.launchArgument
        ]
        app.launch()
        return app
    }

    private func captureScenes(appearance: Appearance, size: TextSize) throws {
        for scene in Scene.allCases {
            try XCTContext.runActivity(named: "fixture-\(scene.rawValue)-requested-\(appearance.rawValue)-\(size.rawValue)") { _ in
                let app = launch(scene: scene, appearance: appearance, size: size)
                defer { app.terminate() }
                try requireForegroundWindow(app)
                try requireSceneReady(scene, app: app)
                attachScreen(app: app, scene: scene, appearance: appearance, size: size,
                             presentation: scene.rawValue)
            }
        }
    }

    private func captureProfilePanels(appearance: Appearance) throws {
        for size in TextSize.allCases {
            try XCTContext.runActivity(named: "real-profile-panel-requested-\(appearance.rawValue)-\(size.rawValue)") { _ in
                let app = launch(scene: .home, appearance: appearance, size: size)
                defer { app.terminate() }
                try requireForegroundWindow(app)
                try requireSceneReady(.home, app: app)
                let menu = app.buttons["forit.profileMenu"]
                try requireHittable(menu, description: "actual shared profile toolbar button")
                menu.tap()
                let panel = app.descendants(matching: .any).matching(identifier: "forit.panel").firstMatch
                try requireExists(panel, description: "actual shared profile panel")
                try requireExists(panel.buttons["Settings"], description: "Settings row inside the shared panel")
                attachScreen(app: app, scene: .home, appearance: appearance, size: size,
                             presentation: "profile-panel")
            }
        }
    }

    private func requireForegroundWindow(_ app: XCUIApplication) throws {
        guard app.wait(for: .runningForeground, timeout: 10) else {
            XCTFail("Fixture app did not reach foreground")
            throw FixtureFailure.notReady("foreground")
        }
        try requireExists(app.windows.firstMatch, description: "fixture app window")
        guard !app.windows.firstMatch.frame.isEmpty else {
            XCTFail("Fixture app window has no drawable extent")
            throw FixtureFailure.notReady("window extent")
        }
        guard app.windows.firstMatch.frame.height >= app.windows.firstMatch.frame.width else {
            XCTFail("Requested portrait fixture still has a landscape window")
            throw FixtureFailure.notReady("portrait window extent")
        }
    }

    private func requireSceneReady(_ scene: Scene, app: XCUIApplication) throws {
        switch scene {
        case .gate:
            try requireExists(app.staticTexts["Welcome to ForIT Glasses"], description: "onboarding heading")
            try requireExists(app.textFields["Bernard API Key"], description: "empty fixture API-key field")
            let proceed = app.buttons["Continue"]
            try requireExists(proceed, description: "onboarding Continue button")
            guard !proceed.isEnabled else {
                XCTFail("Empty fixture gate unexpectedly enables Continue")
                throw FixtureFailure.notReady("disabled empty-key gate")
            }
        case .home:
            try requireExists(app.navigationBars["ForIT Glasses"], description: "home navigation bar")
            try requireExists(app.buttons["forit.profileMenu"], description: "shared home profile menu")
            try requireExists(app.buttons["Meetings"], description: "fixture quick-action ring")
        case .detail:
            try requireExists(app.staticTexts["What can I ask my glasses?"], description: "fixture transcription")
            try requireExists(app.staticTexts["Ask a question, review your day, or capture a photo. This is a sample conversation."],
                              description: "fixture sample response")
        case .settings:
            try requireExists(app.navigationBars["Settings"], description: "fixture Settings sheet")
            try requireExists(app.textFields["Email"], description: "fixture Settings account field")
        case .launch:
            // The permanent launch fixture has no text heading; its actual named
            // asset is the ready selector. No fallback to an arbitrary image.
            try requireHittable(app.images["DoloresAvatar"], description: "visible launch avatar after fade-in")
        }
    }

    private func requireExists(_ element: XCUIElement, description: String) throws {
        guard element.waitForExistence(timeout: 10) else {
            XCTFail("Missing \(description)")
            throw FixtureFailure.notReady(description)
        }
    }

    private func requireHittable(_ element: XCUIElement, description: String) throws {
        try requireExists(element, description: description)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: element)
        guard XCTWaiter.wait(for: [ready], timeout: 10) == .completed else {
            XCTFail("Not visible/hittable: \(description)")
            throw FixtureFailure.notReady(description)
        }
    }

    private func attachScreen(app: XCUIApplication, scene: Scene, appearance: Appearance,
                              size: TextSize, presentation: String) {
        let idiom = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        let frame = app.windows.firstMatch.frame
        let name = "\(idiom)-portrait-\(presentation)-requested-\(appearance.rawValue)-\(size.rawValue)-\(scene.sourceAppearancePolicy)"
        let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screen.name = name
        screen.lifetime = .keepAlways
        add(screen)

        let metadata = XCTAttachment(string: """
        fixture=\(scene.rawValue); presentation=\(presentation); device=\(idiom); orientation=portrait
        requestedAppearance=\(appearance.rawValue); actualAppearanceVerified=false
        productAppearancePolicy=\(scene.sourceAppearancePolicy)
        requestedContentSizeCategory=\(size.launchArgument); actualContentSizeCategoryVerified=false
        appWindowPoints=\(frame.width)x\(frame.height)
        sampleStateOnly=true; hardwareActionsVerified=false; pixelReviewPerformed=false
        accountStateNotOverridden=true; persistedAccountMayAffectProfilePanel=true
        """)
        metadata.name = name + "-context"
        metadata.lifetime = .keepAlways
        add(metadata)
    }
}
