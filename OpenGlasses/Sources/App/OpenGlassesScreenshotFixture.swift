#if DEBUG
import Foundation

/// Opt-in sample scenes for the simulator matrix; absent from Release builds.
/// Startup must skip SDK/listener/location work while `suppressesExternalEffects` is true.
enum OpenGlassesScreenshotFixture {
    enum Scene: String {
        case gate, home, detail, settings, launch
    }

    static let scene: Scene? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-screenshot-scene"),
              arguments.indices.contains(flag + 1) else { return nil }
        return Scene(rawValue: arguments[flag + 1])
    }()

    static var isActive: Bool { scene != nil }

    /// Hosted unit tests launch the app before the screenshot process and must not
    /// request permissions or start external services without a screenshot scene.
    static var suppressesExternalEffects: Bool {
        isActive || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Assigns only transient UI state; never stores credentials or starts services.
    @MainActor
    static func prepare(_ state: AppState) {
        state.listeningEnabled = false
        state.isListening = false
        state.isProcessing = false
        state.isConnected = false
        state.inConversation = false
        state.showSettings = scene == .settings
        state.errorMessage = nil
        state.currentTranscription = scene == .detail ? "What can I ask my glasses?" : ""
        state.lastResponse = scene == .detail
            ? "Ask a question, review your day, or capture a photo. This is a sample conversation."
            : ""
    }
}
#endif
