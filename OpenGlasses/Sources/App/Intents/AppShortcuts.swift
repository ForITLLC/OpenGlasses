import AppIntents

struct ActivateDoloresIntent: AppIntent {
    static var title: LocalizedStringResource = "Talk to Dolores"
    static var description = IntentDescription("Start listening for voice commands")

    static var isDiscoverable: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let appState = AppStateProvider.shared else {
            throw IntentError.appNotRunning
        }

        if appState.isListening {
            appState.speechService.stopSpeaking()
        } else {
            await appState.handleWakeWordDetected()
        }

        return .result()
    }

    enum IntentError: Error, CustomLocalizedStringResourceConvertible {
        case appNotRunning

        var localizedStringResource: LocalizedStringResource {
            "Dolores is not running. Open the app first."
        }
    }
}

struct DoloresShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ActivateDoloresIntent(),
            phrases: ["Talk to \(.applicationName)", "Hey \(.applicationName)"],
            shortTitle: "Talk to Dolores",
            systemImageName: "waveform"
        )
    }
}
