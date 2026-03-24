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

struct EnableListeningIntent: AppIntent {
    static var title: LocalizedStringResource = "Turn On Dolores"
    static var description = IntentDescription("Enable wake word listening and Live Activity")

    static var isDiscoverable: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let appState = AppStateProvider.shared else {
            // App not running — just set the flag so it starts on next launch
            Config.setListeningEnabled(true)
            return .result(value: "Dolores will start listening when you open the app.")
        }

        appState.setListeningEnabled(true)
        return .result(value: "Dolores is now listening.")
    }
}

struct DisableListeningAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Turn Off Dolores"
    static var description = IntentDescription("Disable wake word listening and end Live Activity")

    static var isDiscoverable: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        Config.setListeningEnabled(false)
        if let appState = AppStateProvider.shared {
            appState.setListeningEnabled(false)
        }
        return .result(value: "Dolores stopped listening.")
    }
}

struct LeadLookupIntent: AppIntent {
    static var title: LocalizedStringResource = "Lead Lookup"
    static var description = IntentDescription("Take a photo and look up the person in CRM")

    static var isDiscoverable: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let appState = AppStateProvider.shared else {
            throw ActivateDoloresIntent.IntentError.appNotRunning
        }

        await appState.capturePhotoAndSend(
            prompt: "Look at this business card or name tag. Extract the person's name, company, email, and any other details. Then search the CRM for this person — try searching by name and by company. If found, give me a brief on them: their role, our relationship, recent activity, any open deals. If not found, offer to create them as a new lead. Be concise — I'm wearing glasses and need a quick verbal briefing."
        )

        return .result()
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
        AppShortcut(
            intent: EnableListeningIntent(),
            phrases: ["Turn on \(.applicationName)", "Enable \(.applicationName)", "Start \(.applicationName)"],
            shortTitle: "Turn On",
            systemImageName: "power"
        )
        AppShortcut(
            intent: DisableListeningAppIntent(),
            phrases: ["Turn off \(.applicationName)", "Disable \(.applicationName)", "Stop \(.applicationName)"],
            shortTitle: "Turn Off",
            systemImageName: "power.circle.fill"
        )
        AppShortcut(
            intent: LeadLookupIntent(),
            phrases: ["Look up lead in \(.applicationName)", "Scan business card with \(.applicationName)"],
            shortTitle: "Lead Lookup",
            systemImageName: "person.text.rectangle"
        )
    }
}
