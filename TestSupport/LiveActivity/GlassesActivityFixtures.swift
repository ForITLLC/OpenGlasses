#if DEBUG
import ActivityKit

/// Deterministic input to the real GlassesActivityWidget; never starts an activity.
/// Add only to an explicitly approved DEBUG widget/fixture-host target.
enum GlassesActivityFixtures {
    struct Fixture: Identifiable {
        let id: String
        let state: GlassesActivityAttributes.ContentState
        /// A recorded expectation, not a second implementation of statusIconName.
        let expectedStatusSymbol: String
    }

    static let attributes = GlassesActivityAttributes(glassesName: "Fixture Glasses")

    static let disconnected = Fixture(
        id: "disconnected",
        state: .init(status: "Waiting for glasses...", isConnected: false,
                     lastResponse: "", isListening: false, isSpeaking: false,
                     isProcessing: false),
        expectedStatusSymbol: "mic.slash"
    )
    static let ready = Fixture(
        id: "ready",
        state: .init(status: "Ready", isConnected: true,
                     lastResponse: "", isListening: false, isSpeaking: false,
                     isProcessing: false),
        expectedStatusSymbol: "mic.fill"
    )
    static let listening = Fixture(
        id: "listening",
        state: .init(status: "Listening...", isConnected: true,
                     lastResponse: "", isListening: true, isSpeaking: false,
                     isProcessing: false),
        expectedStatusSymbol: "waveform"
    )
    static let processing = Fixture(
        id: "processing",
        state: .init(status: "Thinking...", isConnected: true,
                     lastResponse: "", isListening: false, isSpeaking: false,
                     isProcessing: true),
        expectedStatusSymbol: "brain"
    )
    static let speaking = Fixture(
        id: "speaking",
        state: .init(status: "Speaking...", isConnected: true,
                     lastResponse: "The next appointment starts at ten.",
                     isListening: false, isSpeaking: true, isProcessing: false),
        expectedStatusSymbol: "speaker.wave.2.fill"
    )

    /// Deliberately exceeds LiveActivityManager's 80-Character response boundary.
    /// The fixture supplies its bounded output to WidgetKit, like the manager does.
    /// This prepares layout coverage; it does not verify the manager's truncation.
    static let longResponseInput =
        "Turn left after the pedestrian crossing, then continue past the café ☕️ " +
        "and meet the accessibility team near the northern entrance at ten thirty."
    static let longContent = Fixture(
        id: "long-content",
        state: .init(status: "Speaking...", isConnected: true,
                     lastResponse: String(longResponseInput.prefix(80)),
                     isListening: false, isSpeaking: true, isProcessing: false),
        expectedStatusSymbol: "speaker.wave.2.fill"
    )

    static let all: [Fixture] = [
        disconnected, ready, listening, processing, speaking, longContent
    ]
}
#endif
