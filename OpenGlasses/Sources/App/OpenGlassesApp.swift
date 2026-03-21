import SwiftUI
import MWDATCore
import AppIntents
import UIKit

private func processWearablesCallbackURL(_ url: URL, source: String) {
    NSLog("[OpenGlasses] [\(source)] Received URL callback: \(url.absoluteString)")
    Task { @MainActor in
        AppStateProvider.shared?.recordCallback(url: url, source: source)
    }
    Task {
        do {
            let result = try await Wearables.shared.handleUrl(url)
            NSLog("[OpenGlasses] [\(source)] handleUrl result: \(String(describing: result))")
            Task { @MainActor in
                AppStateProvider.shared?.addDebugEvent("handleUrl success from \(source): \(String(describing: result))")
            }
        } catch {
            NSLog("[OpenGlasses] [\(source)] handleUrl failed: \(error.localizedDescription)")
            Task { @MainActor in
                AppStateProvider.shared?.addDebugEvent("handleUrl failed from \(source): \(error.localizedDescription)")
            }
        }
    }
}

final class OpenGlassesAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if !options.urlContexts.isEmpty {
            for context in options.urlContexts {
                processWearablesCallbackURL(context.url, source: "SceneConnect")
            }
        }
        if let userActivity = options.userActivities.first,
           let url = userActivity.webpageURL {
            processWearablesCallbackURL(url, source: "SceneConnectUserActivity")
        }

        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = OpenGlassesSceneDelegate.self
        return configuration
    }

    func application(_ application: UIApplication,
                     continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        if let url = userActivity.webpageURL {
            processWearablesCallbackURL(url, source: "UserActivity")
            return true
        }
        return false
    }
}

final class OpenGlassesSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts {
            processWearablesCallbackURL(context.url, source: "SceneDelegate")
        }
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        if let url = userActivity.webpageURL {
            processWearablesCallbackURL(url, source: "SceneDelegateUserActivity")
        }
    }
}

/// Static accessor so AppIntents (Action Button) can reach the running AppState.
@MainActor
enum AppStateProvider {
    static weak var shared: AppState?
}

@main
struct OpenGlassesApp: App {
    @UIApplicationDelegateAdaptor(OpenGlassesAppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        configureWearables()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .onAppear { AppStateProvider.shared = appState }
                .onOpenURL { url in
                    processWearablesCallbackURL(url, source: "SwiftUI")
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                print("App moved to background — keeping audio alive")
            case .active:
                print("App became active")
                Task {
                    // Give onOpenURL time to process any pending Meta Auth callbacks
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    
                    let state = Wearables.shared.registrationState
                    if state.rawValue < 3 {
                        print("Registration dropped to \(state.rawValue) after background — waiting for natural reconnect...")
                    }
                }
                // Restart wake word listener on foreground
                Task {
                    let regState = appState.registrationStateRaw
                    guard regState >= 3 else {
                        appState.addDebugEvent("Skipping wake word restart on foreground: registration state=\(regState)")
                        return
                    }

                    if !appState.wakeWordService.isListening && !appState.isListening {
                        print("Restarting wake word listener after foreground...")
                        appState.wakeWordService.reconfigureAudioSessionIfNeeded()
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        try? await appState.wakeWordService.startListening()
                    }
                }
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }

    private func configureWearables() {
        do {
            NSLog("[OpenGlasses] Logging active")
            try Wearables.configure()
            NSLog("[OpenGlasses] Meta Wearables SDK configured successfully")
            let state = Wearables.shared.registrationState
            NSLog("[OpenGlasses] Registration state: \(state.rawValue)")
            let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
            let mwdat = Bundle.main.object(forInfoDictionaryKey: "MWDAT") as? [String: Any]
            if let mwdat {
                NSLog("[OpenGlasses] MWDAT keys: \(mwdat.keys.sorted().joined(separator: ", "))")
            } else {
                NSLog("[OpenGlasses] MWDAT dictionary missing from Info.plist")
            }
            let appLinkURL = mwdat?["AppLinkURLScheme"] as? String
            let metaAppID = mwdat?["MetaAppID"] as? String

            NSLog("[OpenGlasses] Bundle ID: \(bundleId)")
            NSLog("[OpenGlasses] AppLinkURLScheme (Universal Link): \(appLinkURL ?? "nil")")
            NSLog("[OpenGlasses] MetaAppID: \(metaAppID ?? "nil")")

            do {
                let parsed = try Configuration(bundle: .main)
                let app = parsed.appConfiguration
                NSLog("[OpenGlasses] Parsed config bundleIdentifier=\(app.bundleIdentifier)")
                NSLog("[OpenGlasses] Parsed config appLinkURLScheme=\(app.appLinkURLScheme ?? "nil")")
                NSLog("[OpenGlasses] Parsed config metaAppId=\(app.metaAppId ?? "nil")")
                NSLog("[OpenGlasses] Parsed config clientTokenPresent=\(app.clientToken != nil)")
                NSLog("[OpenGlasses] Parsed config teamID=\(app.teamID ?? "nil")")
                NSLog("[OpenGlasses] Parsed attestation hasCompleteData=\(parsed.attestationConfiguration.hasCompleteData)")
            } catch {
                NSLog("[OpenGlasses] Configuration(bundle:) parse failed: \(error.localizedDescription)")
            }
        } catch {
            NSLog("[OpenGlasses] Failed to configure Wearables SDK: \(error.localizedDescription)")
        }
    }
}

/// Global application state
@MainActor
class AppState: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var registrationStateRaw: Int = 0
    @Published var lastCallbackSource: String = "—"
    @Published var lastCallbackURL: String = "—"
    @Published var lastCallbackAt: Date?
    @Published var debugEvents: [String] = []
    @Published var isListening: Bool = false
    @Published var currentTranscription: String = ""
    @Published var lastResponse: String = ""
    @Published var errorMessage: String?

    let glassesService = GlassesConnectionService()
    let wakeWordService = WakeWordService()
    let transcriptionService = TranscriptionService()
    let llmService = LLMService()
    let speechService = TextToSpeechService()
    let cameraService = CameraService()
    let locationService = LocationService()

    private var cancellables: [Any] = []
    private var isProcessing: Bool = false
    private var hasEverRegistered: Bool = false
    private var inConversation: Bool = false

    func addDebugEvent(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        debugEvents.append("[\(timestamp)] \(message)")
        if debugEvents.count > 80 {
            debugEvents.removeFirst(debugEvents.count - 80)
        }
    }

    func recordCallback(url: URL, source: String) {
        lastCallbackSource = source
        lastCallbackURL = url.absoluteString
        lastCallbackAt = Date()
        addDebugEvent("Callback received via \(source)")
    }

    private func waitForRegistration(minState: Int, timeoutSeconds: Double) async -> Int {
        let waitStart = ContinuousClock.now
        while true {
            let state = Wearables.shared.registrationState.rawValue
            if state >= minState { return state }
            if ContinuousClock.now - waitStart > .seconds(timeoutSeconds) { return state }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    init() {
        addDebugEvent("AppState initialized")
        transcriptionService.sharedAudioEngineProvider = wakeWordService
        llmService.speechService = speechService
        setupServiceCallbacks()
        observeGlassesConnection()
        autoConnectGlasses()
        autoStartListening()
        locationService.startTracking()
    }

    private func setupServiceCallbacks() {
        wakeWordService.onWakeWordDetected = { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                guard !self.inConversation && !self.isProcessing else {
                    print("Wake word ignored - already in conversation")
                    return
                }
                await self.handleWakeWordDetected()
            }
        }

        wakeWordService.onStopCommand = { [weak self] in
            Task { @MainActor in
                self?.stopSpeakingAndResume()
            }
        }

        transcriptionService.onTranscriptionComplete = { [weak self] text in
            Task { @MainActor in
                guard let self = self else { return }
                guard !self.isProcessing else {
                    print("Transcription ignored - already processing")
                    return
                }
                await self.handleTranscription(text)
            }
        }

        transcriptionService.onSilenceTimeout = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                print("User silent — ending conversation, back to wake word")
                await self.returnToWakeWord()
            }
        }
    }

    private func observeGlassesConnection() {
        let deviceToken = Wearables.shared.addDevicesListener { [weak self] deviceIds in
            Task { @MainActor in
                guard let self else { return }
                print("Devices changed: \(deviceIds)")
                self.addDebugEvent("Devices changed: \(deviceIds.count)")
                if !deviceIds.isEmpty {
                    self.hasEverRegistered = true
                    self.isConnected = true
                }
            }
        }
        cancellables.append(deviceToken)

        let regToken = Wearables.shared.addRegistrationStateListener { [weak self] newState in
            Task { @MainActor in
                guard let self else { return }
                print("Registration state changed: \(newState.rawValue)")
                self.addDebugEvent("Registration state -> \(newState.rawValue)")
                self.registrationStateRaw = newState.rawValue
                if newState.rawValue >= 3 {
                    self.hasEverRegistered = true
                    self.isConnected = true
                    UserDefaults.standard.set(true, forKey: "hasRegisteredWithMeta")
                }
            }
        }
        cancellables.append(regToken)

        let initialState = Wearables.shared.registrationState
        print("Initial registration state: \(initialState.rawValue)")
        addDebugEvent("Initial registration state: \(initialState.rawValue)")
        registrationStateRaw = initialState.rawValue
        if initialState.rawValue >= 3 {
            hasEverRegistered = true
            isConnected = true
            print("Already registered on launch")
        }
    }

    private func autoConnectGlasses() {
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            let state = Wearables.shared.registrationState
            self.registrationStateRaw = state.rawValue
            print("Launch state check: state=\(state.rawValue)")
            self.addDebugEvent("Launch state check: state=\(state.rawValue)")

            if state.rawValue >= 3 {
                self.hasEverRegistered = true
                self.isConnected = true
                self.addDebugEvent("Already registered on launch")
            } else {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                let settledState = Wearables.shared.registrationState
                self.registrationStateRaw = settledState.rawValue
                if settledState.rawValue >= 3 {
                    self.hasEverRegistered = true
                    self.isConnected = true
                    self.addDebugEvent("SDK auto-reconnected to state \(settledState.rawValue)")
                } else {
                    self.isConnected = false
                    self.addDebugEvent("State \(settledState.rawValue) — tap Connect to register")
                }
            }
        }
    }

    func completeAuthorizationInMetaAI() async {
        addDebugEvent("Manual Meta authorization requested")
        do {
            try await Wearables.shared.startRegistration()
        } catch {
            print("Manual registration start failed: \(error)")
            addDebugEvent("Manual registration start failed: \(error.localizedDescription)")
        }

        let currentState = Wearables.shared.registrationState.rawValue
        registrationStateRaw = currentState
        if currentState >= 3 { return }

        await MainActor.run {
            guard let viewAppUrl = URL(string: "fb-viewapp://") else { return }
            if UIApplication.shared.canOpenURL(viewAppUrl) {
                UIApplication.shared.open(viewAppUrl, options: [:])
            }
        }
    }

    func resetMetaRegistration() async {
        addDebugEvent("Manual reset requested: startUnregistration")
        do {
            try await Wearables.shared.startUnregistration()
            addDebugEvent("startUnregistration succeeded")
        } catch {
            addDebugEvent("startUnregistration failed: \(error.localizedDescription)")
        }

        UserDefaults.standard.set(false, forKey: "hasRegisteredWithMeta")
        registrationStateRaw = Wearables.shared.registrationState.rawValue
        addDebugEvent("State after unregistration: \(registrationStateRaw)")

        try? await Task.sleep(nanoseconds: 1_000_000_000)

        addDebugEvent("Manual reset: startRegistration")
        do {
            try await Wearables.shared.startRegistration()
            let settled = await waitForRegistration(minState: 3, timeoutSeconds: 20)
            registrationStateRaw = settled
            addDebugEvent("Manual reset registration result: state=\(settled)")
        } catch {
            addDebugEvent("Manual reset startRegistration failed: \(error.localizedDescription)")
        }
    }

    private func autoStartListening() {
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)

            if registrationStateRaw < 3 {
                addDebugEvent("Wake word auto-start deferred: registration state=\(registrationStateRaw)")
                let settled = await waitForRegistration(minState: 3, timeoutSeconds: 20)
                registrationStateRaw = settled
                addDebugEvent("Wake word auto-start registration wait result: state=\(settled)")
                guard settled >= 3 else {
                    addDebugEvent("Skipping wake word auto-start: registration did not reach state 3")
                    return
                }
            }

            if !wakeWordService.isListening {
                print("Auto-starting wake word listener...")
                do {
                    try await wakeWordService.startListening()
                    print("Wake word listener auto-started")
                } catch {
                    print("Auto-start failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func stopSpeakingAndResume() {
        print("User tapped stop")
        speechService.stopSpeaking()
        isProcessing = false
        if inConversation {
            print("Listening for follow-up after stop...")
            isListening = true
            transcriptionService.startRecording()
        } else {
            Task { await returnToWakeWord() }
        }
    }

    func capturePhotoFromGlasses() async {
        guard isConnected else {
            errorMessage = "Connect glasses first"
            return
        }
        do {
            let photoData = try await cameraService.capturePhoto()
            cameraService.saveToPhotoLibrary(photoData)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            lastResponse = "Photo saved to camera roll"
        } catch {
            errorMessage = "Photo failed: \(error.localizedDescription)"
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
    }

    func handleWakeWordDetected() async {
        print("Wake word detected! Starting conversation...")
        inConversation = true
        isListening = true
        speechService.playAcknowledgmentTone()
        transcriptionService.startRecording()
    }

    // MARK: - Voice Commands

    private static let stopPhrases = ["stop", "nevermind", "never mind", "cancel", "shut up", "be quiet", "quiet"]
    private static let goodbyePhrases = ["goodbye", "good bye", "bye", "that's all", "thats all",
                                          "thanks claude", "thank you claude", "i'm done", "im done",
                                          "end conversation", "go to sleep"]
    private static let photoPhrases = ["take a picture", "take a photo", "take photo", "take picture",
                                        "capture photo", "snap a photo", "snap a picture", "take a snap"]

    private func isStopCommand(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.stopPhrases.contains(where: { lower == $0 || lower.hasPrefix($0 + " ") || lower.hasSuffix(" " + $0) })
    }

    private func isGoodbyeCommand(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.goodbyePhrases.contains(where: { lower.contains($0) })
    }

    private func isPhotoCommand(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.photoPhrases.contains(where: { lower.contains($0) })
    }

    func handleTranscription(_ text: String) async {
        guard !isProcessing else {
            print("Already processing, ignoring: \(text)")
            return
        }

        currentTranscription = text
        isListening = false
        errorMessage = nil
        speechService.playEndListeningTone()
        print("Transcription: \(text)")

        if isStopCommand(text) {
            print("Voice command: stop")
            speechService.stopSpeaking()
            if inConversation {
                print("Stopped — listening for next question...")
                isListening = true
                transcriptionService.startRecording()
            } else {
                await returnToWakeWord()
            }
            return
        }

        if isGoodbyeCommand(text) {
            print("Voice command: goodbye")
            speechService.stopSpeaking()
            inConversation = false
            lastResponse = "Goodbye!"
            await speechService.speak("Goodbye!")
            await returnToWakeWord()
            return
        }

        if isPhotoCommand(text) {
            print("Voice command: take a picture")
            isProcessing = true
            await speechService.speak("Taking a picture.")
            do {
                let photoData = try await cameraService.capturePhoto()
                cameraService.saveToPhotoLibrary(photoData)
                print("Photo saved, sending to LLM with prompt: \(text)")

                let response = try await llmService.sendMessage(text, locationContext: locationService.locationContext, imageData: photoData)
                lastResponse = response
                print("Dolores (vision): \(response)")

                startStopListener()
                await speechService.speak(response)
                stopStopListener()

            } catch {
                print("Photo capture failed: \(error)")
                lastResponse = "Photo failed: \(error.localizedDescription)"
                await speechService.speak("Sorry, I couldn't take a photo or process the image. \(error.localizedDescription)")
            }
            isProcessing = false
            if inConversation {
                isListening = true
                transcriptionService.startRecording()
            } else {
                await returnToWakeWord()
            }
            return
        }

        // Normal message — send to LLM
        isProcessing = true

        do {
            let response = try await llmService.sendMessage(text, locationContext: locationService.locationContext)
            lastResponse = response
            print("Dolores: \(response)")

            startStopListener()
            await speechService.speak(response)
            stopStopListener()
        } catch {
            errorMessage = "Failed to get response: \(error.localizedDescription)"
            await speechService.speak("Sorry, I encountered an error.")
        }

        isProcessing = false
        if inConversation {
            print("Continuing conversation — listening for follow-up...")
            isListening = true
            transcriptionService.startRecording()
        } else {
            await returnToWakeWord()
        }
    }

    private func startStopListener() {
        wakeWordService.listenForStop = true
        if wakeWordService.getAudioEngine()?.isRunning == true {
            Task {
                do {
                    try await wakeWordService.startListening()
                    print("Stop listener active during TTS")
                } catch {
                    print("Could not start stop listener: \(error)")
                }
            }
        } else {
            print("No running engine for stop listener — skipping")
        }
    }

    private func stopStopListener() {
        wakeWordService.listenForStop = false
        wakeWordService.pauseRecognitionPublic()
    }

    private func returnToWakeWord() async {
        isListening = false
        inConversation = false
        wakeWordService.listenForStop = false
        speechService.playDisconnectTone()
        do {
            try await wakeWordService.startListening()
            print("Wake word restarted")
        } catch {
            print("Failed to restart listener: \(error)")
            errorMessage = "Tap Test Microphone to restart"
        }
    }
}
