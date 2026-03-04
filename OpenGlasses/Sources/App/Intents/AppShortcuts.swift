import AppIntents

/// Makes the Toggle Gemini Live intent discoverable for Shortcuts and Action Button.
struct OpenGlassesShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleGeminiLiveIntent(),
            phrases: [
                "Toggle Gemini Live in \(.applicationName)",
                "Start Gemini Live in \(.applicationName)",
                "Stop Gemini Live in \(.applicationName)"
            ],
            shortTitle: "Toggle Gemini Live",
            systemImageName: "waveform.circle.fill"
        )
    }
}
