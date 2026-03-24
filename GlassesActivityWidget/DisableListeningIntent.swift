import AppIntents

/// Intent triggered from Live Activity button to disable listening.
/// Widget can't access AppState directly — writes to UserDefaults.
/// App picks up the change on next foreground/syncLiveActivity.
struct DisableListeningIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Disable Listening"
    static var description = IntentDescription("Stop wake word detection and end Live Activity")

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(false, forKey: "listeningEnabled")
        return .result()
    }
}
