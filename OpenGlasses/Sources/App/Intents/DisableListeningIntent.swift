import AppIntents

/// Intent triggered from Live Activity button or Siri to disable listening.
/// Also accessible from app context via AppStateProvider.
struct DisableListeningIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Disable Listening"
    static var description = IntentDescription("Disable Meta voice launch and end Live Activity")

    @MainActor
    func perform() async throws -> some IntentResult {
        // Write to UserDefaults (works from both app and widget)
        UserDefaults.standard.set(false, forKey: "listeningEnabled")
        // If app is running, update observable state immediately
        if let appState = AppStateProvider.shared {
            appState.setListeningEnabled(false)
        }
        return .result()
    }
}
