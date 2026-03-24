import AppIntents

/// Intent triggered from Live Activity button to disable listening
struct DisableListeningIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Disable Listening"
    static var description = IntentDescription("Stop wake word detection and end Live Activity")

    @MainActor
    func perform() async throws -> some IntentResult {
        Config.setListeningEnabled(false)
        // AppState will pick up the change on next syncLiveActivity call
        // The Live Activity will end itself when it sees listeningEnabled = false
        if let appState = AppStateProvider.shared {
            appState.setListeningEnabled(false)
        }
        return .result()
    }
}
