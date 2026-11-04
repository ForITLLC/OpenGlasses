import Foundation
import SwiftUI
import AVFoundation
import Speech
import MWDATCore
import AppIntents
import UIKit
import ForITCommon

/// Whether `Wearables.configure()` has actually succeeded.
///
/// MWDAT hard-traps (`fatalError`, Wearables.swift:191 "Call `configure()` before
/// attempting to access Wearables!") on ANY `Wearables.shared` access when the SDK
/// was never configured. `configureWearables()` only logs a configure() failure, so
/// without this gate a failed configure turned into a crash the moment the app
/// foregrounded or set up its listeners. Every startup-path access checks this.
enum WearablesRuntime {
    @MainActor static var isConfigured = false
}

private func processWearablesCallbackURL(_ url: URL, source: String) {
    #if DEBUG
    guard !OpenGlassesScreenshotFixture.suppressesExternalEffects else { return }
    #endif
    Task { @MainActor in
        if FeedbackAccount.isSignInLink(url) {
            _ = FeedbackAccount.shared.handle(url)
            return
        }
        guard MetaVoiceInvocationService.isDATURL(url) else { return }
        guard let state = AppStateProvider.shared else {
            // A cold scene callback can precede creation of the SwiftUI state.
            AppStateProvider.pendingMetaURLs.append((url, source))
            return
        }
        await state.handleMetaURL(url, source: source)
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
    static var pendingMetaURLs: [(URL, String)] = []
}

@main
struct OpenGlassesApp: App {
    @UIApplicationDelegateAdaptor(OpenGlassesAppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        guard !OpenGlassesScreenshotFixture.suppressesExternalEffects else { return }
        #endif
        configureWearables()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .forITTint()
                .forITFeedback(FeedbackAccount.shared.center)
                .onAppear { AppStateProvider.shared = appState }
                .onOpenURL { url in
                    processWearablesCallbackURL(url, source: "SwiftUI")
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            #if DEBUG
            guard !OpenGlassesScreenshotFixture.suppressesExternalEffects else { return }
            #endif
            switch newPhase {
            case .background:
                print("App moved to background — keeping audio + Live Activity alive")
            case .active:
                print("App became active")
                Task {
                    // Give onOpenURL time to process any pending Meta Auth callbacks
                    try? await Task.sleep(nanoseconds: 1_500_000_000)

                    guard WearablesRuntime.isConfigured else { return }
                    let state = Wearables.shared.registrationState
                    if state.rawValue < 3 {
                        print("Registration dropped to \(state.rawValue) after background — waiting for natural reconnect...")
                    }
                }
                appState.startMetaVoiceLaunch()

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
            WearablesRuntime.isConfigured = true
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
    @Published var errorMessage: String? {
        // Any other error writer takes ownership, even if its text happens to match.
        didSet { displayedMetaError = nil }
    }
    @Published var showSettings: Bool = false
    @Published var listeningEnabled: Bool = Config.listeningEnabled

    /// Toggle listening on/off — single source of truth for all UI
    func setListeningEnabled(_ enabled: Bool) {
        activationGeneration = UUID()
        listeningEnabled = enabled
        Config.setListeningEnabled(enabled)
        if !enabled {
            metaVoiceService.stop()
            llmService.cancelPendingRequest()
            cameraService.cancelPendingCapture()
            wakeWordService.listenForStop = false
            wakeWordService.stopListening()
            transcriptionService.cancelRecording()
            speechService.stopSpeaking()
            isListening = false
            isProcessing = false
            inConversation = false
            liveActivity.end()
            addDebugEvent("Listening DISABLED by user")
        } else {
            addDebugEvent("Listening ENABLED by user")
            startMetaVoiceLaunch()
            syncLiveActivity()
        }
    }

    let glassesService = GlassesConnectionService()
    let metaVoiceService = MetaVoiceInvocationService()
    let wakeWordService = WakeWordService()
    let transcriptionService = TranscriptionService()
    let llmService = LLMService()
    let speechService = TextToSpeechService()
    let cameraService = CameraService()
    let locationService = LocationService()
    let liveActivity = LiveActivityManager()

    private var cancellables: [Any] = []
    private var lastMetaURL: (url: URL, at: Date)?
    private var activationGeneration = UUID()
    @Published var isProcessing: Bool = false
    private var displayedMetaError: String?
    @Published var inConversation: Bool = false

    func addDebugEvent(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        debugEvents.append("[\(timestamp)] \(message)")
        if debugEvents.count > 80 {
            debugEvents.removeFirst(debugEvents.count - 80)
        }
        // Send all debug events to App Insights via ErrorReporter
        ErrorReporter.shared.report(message, source: "app", level: "debug")
    }

    /// Sync current state to the Live Activity.
    /// Activity starts on first connection and persists even during brief disconnects.
    /// Only ends when app goes to background (handled in scenePhase onChange).
    func syncLiveActivity() {
        // Don't start or update Live Activity if listening is disabled
        guard listeningEnabled else {
            if liveActivity.isActive {
                liveActivity.end()
            }
            return
        }

        let status: String
        if isListening { status = "Listening..." }
        else if speechService.isSpeaking { status = "Speaking..." }
        else if isProcessing { status = "Thinking..." }
        else if !isConnected { status = "Waiting for glasses..." }
        else { status = "Ready" }

        // Start activity on first connection (or if not yet started)
        if !liveActivity.isActive {
            liveActivity.start(glassesName: glassesService.deviceName ?? "Glasses")
        }

        liveActivity.update(
            status: status,
            isConnected: isConnected,
            lastResponse: lastResponse,
            isListening: isListening,
            isSpeaking: speechService.isSpeaking,
            isProcessing: isProcessing
        )
    }

    func recordCallback(url: URL, source: String) {
        lastCallbackSource = source
        lastCallbackURL = url.absoluteString
        lastCallbackAt = Date()
        addDebugEvent("Callback received via \(source)")
    }

    private func waitForRegistration(minState: Int, timeoutSeconds: Double) async -> Int {
        guard WearablesRuntime.isConfigured else { return 0 }
        let waitStart = ContinuousClock.now
        while true {
            let state = Wearables.shared.registrationState.rawValue
            if state >= minState { return state }
            if ContinuousClock.now - waitStart > .seconds(timeoutSeconds) { return state }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    init() {
        observeServiceState()
        #if DEBUG
        if OpenGlassesScreenshotFixture.suppressesExternalEffects {
            AppStateProvider.shared = self
            if OpenGlassesScreenshotFixture.isActive {
                OpenGlassesScreenshotFixture.prepare(self)
            }
            return
        }
        #endif
        addDebugEvent("AppState initialized")
        AppStateProvider.shared = self  // Set immediately so callbacks can record
        transcriptionService.sharedAudioEngineProvider = wakeWordService
        llmService.speechService = speechService
        cancellables.append(speechService.$playbackNotice.sink { [weak self] notice in
            guard let notice else { return }
            self?.errorMessage = notice
        })
        setupServiceCallbacks()
        observeGlassesConnection()
        autoConnectGlasses()
        startMetaVoiceLaunch()
        let pending = AppStateProvider.pendingMetaURLs
        AppStateProvider.pendingMetaURLs.removeAll()
        Task { @MainActor [weak self] in
            for (url, source) in pending { await self?.handleMetaURL(url, source: source) }
        }
        locationService.startTracking()
        observeLiveActivityState()
    }

    private func observeServiceState() {
        // Registration permits a connection; only the actual device link proves one.
        cancellables.append(glassesService.$isConnected.removeDuplicates().sink { [weak self] connected in
            self?.isConnected = connected
        })
        cancellables.append(metaVoiceService.$lastError.sink { [weak self] message in
            self?.presentMetaVoiceError(message)
        })
    }

    private func presentMetaVoiceError(_ message: String?) {
        guard listeningEnabled, let message else {
            if displayedMetaError != nil { errorMessage = nil }
            return
        }
        // A channel retry must not replace an unrelated error the user still needs.
        guard errorMessage == nil || displayedMetaError != nil else { return }
        errorMessage = "Meta voice launch: \(message)"
        displayedMetaError = errorMessage
    }

    func updateRegistrationState(_ state: RegistrationState) {
        registrationStateRaw = state.rawValue
        if state == .registered {
            UserDefaults.standard.set(true, forKey: "hasRegisteredWithMeta")
        }
    }

    private func setupServiceCallbacks() {
        wakeWordService.onStopCommand = { [weak self] in
            guard let self else { return }
            let generation = self.activationGeneration
            Task { @MainActor in
                guard self.listeningEnabled, self.activationGeneration == generation else { return }
                self.stopSpeakingAndResume()
            }
        }

        transcriptionService.onTranscriptionComplete = { [weak self] text in
            guard let self else { return }
            let generation = self.activationGeneration
            Task { @MainActor in
                guard self.listeningEnabled, self.activationGeneration == generation else { return }
                guard !self.isProcessing else {
                    print("Transcription ignored - already processing")
                    return
                }
                await self.handleTranscription(text)
            }
        }

        transcriptionService.onSilenceTimeout = { [weak self] in
            guard let self else { return }
            let generation = self.activationGeneration
            Task { @MainActor in
                guard self.listeningEnabled, self.activationGeneration == generation else { return }
                print("[MIC] User silent - ending conversation, back to wake word")
                await self.safeReturnToWakeWord()
            }
        }
    }

    private func observeGlassesConnection() {
        // Without a configured SDK these calls fatalError. Registration stays at 0
        // and the UI shows the unregistered state, which is the honest outcome when
        // configure() failed.
        guard WearablesRuntime.isConfigured else {
            NSLog("[OpenGlasses] Wearables SDK unconfigured — skipping connection observers")
            addDebugEvent("Wearables SDK unconfigured — glasses features unavailable")
            return
        }

        let deviceToken = Wearables.shared.addDevicesListener { [weak self] deviceIds in
            Task { @MainActor in
                guard let self else { return }
                print("Devices changed: \(deviceIds)")
                self.addDebugEvent("Devices changed: \(deviceIds.count)")
            }
        }
        cancellables.append(deviceToken)

        let regToken = Wearables.shared.addRegistrationStateListener { [weak self] newState in
            Task { @MainActor in
                guard let self else { return }
                print("Registration state changed: \(newState.rawValue)")
                self.addDebugEvent("Registration state -> \(newState.rawValue)")
                self.updateRegistrationState(newState)
            }
        }
        cancellables.append(regToken)

        let initialState = Wearables.shared.registrationState
        print("Initial registration state: \(initialState.rawValue)")
        addDebugEvent("Initial registration state: \(initialState.rawValue)")
        updateRegistrationState(initialState)
        if initialState == .registered {
            print("Already registered on launch")
        }
    }

    private func autoConnectGlasses() {
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard WearablesRuntime.isConfigured else {
                self.addDebugEvent("Wearables SDK unconfigured — skipping launch state check")
                return
            }
            let state = Wearables.shared.registrationState
            self.updateRegistrationState(state)
            print("Launch state check: state=\(state.rawValue)")
            self.addDebugEvent("Launch state check: state=\(state.rawValue)")

            if state.rawValue >= 3 {
                self.addDebugEvent("Already registered on launch")
            } else {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                let settledState = Wearables.shared.registrationState
                self.updateRegistrationState(settledState)
                if settledState.rawValue >= 3 {
                    self.addDebugEvent("SDK auto-reconnected to state \(settledState.rawValue)")
                } else {
                    self.addDebugEvent("State \(settledState.rawValue) — tap Connect to register")
                }
            }
        }
    }

    func completeAuthorizationInMetaAI() async {
        addDebugEvent("Manual Meta authorization requested")
        guard WearablesRuntime.isConfigured else {
            addDebugEvent("Wearables SDK unconfigured — cannot start registration")
            return
        }
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
        guard WearablesRuntime.isConfigured else {
            addDebugEvent("Wearables SDK unconfigured — cannot reset registration")
            return
        }
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

    /// Register Meta's launch channel without opening our microphone or running
    /// an app-specific wake recognizer. Meta's beta app name owns activation.
    func startMetaVoiceLaunch() {
        #if DEBUG
        guard !OpenGlassesScreenshotFixture.suppressesExternalEffects else { return }
        #endif
        guard listeningEnabled else { return }
        metaVoiceService.start { [weak self] in
            guard let self else { throw MetaLaunchError.unavailable }
            guard self.listeningEnabled else { throw MetaLaunchError.disabled }
            guard !self.isProcessing && !self.isListening else { throw MetaLaunchError.busy }
            await self.handleWakeWordDetected(manualActivation: true)
            guard self.transcriptionService.isRecording else { throw MetaLaunchError.microphone }
        }
    }

    func handleMetaURL(_ url: URL, source: String) async {
        guard WearablesRuntime.isConfigured else {
            addDebugEvent("Meta callback ignored: SDK is unavailable")
            return
        }
        if let previous = lastMetaURL, previous.url == url, Date().timeIntervalSince(previous.at) < 2 {
            return // SceneDelegate and SwiftUI may deliver the same callback.
        }
        lastMetaURL = (url, Date())
        recordCallback(url: url, source: source)
        startMetaVoiceLaunch()
        do {
            _ = try await metaVoiceService.handleURL(url)
        } catch {
            errorMessage = "Meta connection failed: \(error.localizedDescription)"
        }
    }

    /// Cancel current processing or speaking — called by mic button tap during active response
    func cancelCurrentResponse() {
        activationGeneration = UUID()
        llmService.cancelPendingRequest()
        print("[MIC] cancelCurrentResponse called. isProcessing=\(isProcessing) isSpeaking=\(speechService.isSpeaking)")
        speechService.stopSpeaking()
        isProcessing = false
        isListening = false
        inConversation = false
        lastResponse = "Cancelled"
        Task { await safeReturnToWakeWord() }
    }

    func stopSpeakingAndResume() {
        guard listeningEnabled else { return }
        print("[MIC] stopSpeakingAndResume called. inConversation=\(inConversation) isListening=\(isListening)")
        // Stopping speech resumes its awaiting reply task. Retire that task
        // before it can tear down the engine now used for follow-up recording.
        activationGeneration = UUID()
        wakeWordService.listenForStop = false
        wakeWordService.pauseRecognitionPublic()
        speechService.stopSpeaking()
        isProcessing = false
        if inConversation {
            print("Listening for follow-up after stop...")
            transcriptionService.startRecording()
            isListening = transcriptionService.isRecording
            if !isListening {
                inConversation = false
                wakeWordService.stopListening()
                errorMessage = transcriptionService.errorMessage ?? "The microphone could not resume."
            }
        } else {
            Task { await safeReturnToWakeWord() }
        }
    }

    func capturePhotoFromGlasses() async {
        print("[CAMERA] capturePhotoFromGlasses called. isConnected=\(isConnected), regState=\(registrationStateRaw)")
        ErrorReporter.shared.report("capturePhotoFromGlasses called. isConnected=\(isConnected), regState=\(registrationStateRaw)", source: "camera", level: "info")
        guard isConnected else {
            print("[CAMERA] Not connected — aborting capture")
            errorMessage = "Connect glasses first"
            ErrorReporter.shared.report("Photo aborted: glasses not connected (regState=\(registrationStateRaw))", source: "camera", level: "warning")
            return
        }
        do {
            print("[CAMERA] Starting photo capture...")
            let photoData = try await cameraService.capturePhoto()
            print("[CAMERA] Photo captured: \(photoData.count) bytes")
            cameraService.saveToPhotoLibrary(photoData)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            lastResponse = "Photo saved to camera roll"
            print("[CAMERA] Photo saved to camera roll")
            ErrorReporter.shared.report("Photo captured successfully: \(photoData.count) bytes", source: "camera", level: "info")
        } catch {
            print("[CAMERA] Photo capture failed: \(error.localizedDescription)")
            errorMessage = "Photo failed: \(error.localizedDescription)"
            ErrorReporter.shared.report("Photo capture failed: \(error.localizedDescription)", source: "camera", level: "error")
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
    }

    /// Capture photo and send to LLM with a prompt (e.g. "Turn this photo into a task")
    func capturePhotoAndSend(prompt: String) async {
        guard listeningEnabled else { return }
        let generation = activationGeneration

        print("[CAMERA] capturePhotoAndSend called. prompt=\(prompt.prefix(50))")
        guard isConnected else {
            errorMessage = "Connect glasses first"
            return
        }
        isProcessing = true
        speechService.playAcknowledgmentTone()  // Tone instead of spoken "Taking a picture" (avoids iOS voice)
        do {
            let photoData = try await cameraService.capturePhoto()
            guard listeningEnabled, activationGeneration == generation else { return }
            cameraService.saveToPhotoLibrary(photoData)
            print("[CAMERA] Photo captured, sending to LLM: \(prompt)")
            let response = try await llmService.sendMessage(prompt, locationContext: locationService.locationContext, imageData: photoData)
            guard listeningEnabled, activationGeneration == generation else { return }
            lastResponse = response
            startStopListener()
            await speechService.speak(response)
            guard listeningEnabled, activationGeneration == generation else { return }
            stopStopListener()
        } catch {
            guard listeningEnabled, activationGeneration == generation else { return }
            print("[CAMERA] Photo+send failed: \(error.localizedDescription)")
            errorMessage = "Photo failed: \(error.localizedDescription)"
            ErrorReporter.shared.report("capturePhotoAndSend failed: \(error.localizedDescription)", source: "camera", level: "error")
            await speechService.speak("Sorry, I couldn't take a photo. \(error.localizedDescription)")
            guard listeningEnabled, activationGeneration == generation else { return }
        }
        isProcessing = false
        if inConversation {
            isListening = true
            transcriptionService.startRecording()
        } else {
            await safeReturnToWakeWord()
        }
    }

    /// Start listening for user speech.
    /// - Parameter manualActivation: true when triggered by mic button (longer timeout), false for wake word
    func handleWakeWordDetected(manualActivation: Bool = false) async {
        print("[MIC] handleWakeWordDetected called. manual=\(manualActivation) isListening=\(isListening) inConversation=\(inConversation) isProcessing=\(isProcessing)")

        guard listeningEnabled else {
            errorMessage = "Enable Meta voice launch in Settings first."
            return
        }
        let activation = UUID()
        activationGeneration = activation
        guard await wakeWordService.requestPermissions() else {
            errorMessage = "Allow microphone and speech access to talk to Bernard."
            return
        }
        guard listeningEnabled, activationGeneration == activation else { return }
        wakeWordService.configureAudioSession()
        // Pause the response Stop recognizer before starting transcription.
        // Pause wake word recognition BEFORE starting transcription.
        // Two speech recognizers cannot share the same audio engine —
        // the wake word task steals buffers and can cause the transcription
        // recognizer to receive no audio, failing silently.
        if wakeWordService.isListening {
            print("[MIC] Pausing wake word service before starting transcription")
            wakeWordService.pauseRecognitionPublic()
        }

        inConversation = true
        isListening = true
        print("[MIC] Set inConversation=true, isListening=true")

        speechService.playAcknowledgmentTone()

        // Small delay to let the wake word recognition task fully release
        // the speech recognizer before we start a new one
        do { try await Task.sleep(nanoseconds: 100_000_000) }
        catch { return }
        guard listeningEnabled, activationGeneration == activation else { return }

        // Manual mic button press gets 15s to start speaking (user may need time)
        // Wake word trigger gets 5s (user already spoke, so they're ready)
        let timeout: TimeInterval? = manualActivation ? 15.0 : nil
        print("[MIC] Calling transcriptionService.startRecording(noSpeechTimeout: \(String(describing: timeout)))")
        transcriptionService.startRecording(noSpeechTimeout: timeout)

        // Verify recording started
        print("[MIC] After startRecording: isRecording=\(transcriptionService.isRecording)")
        if !transcriptionService.isRecording {
            print("[MIC] WARNING: Recording failed to start!")
            ErrorReporter.shared.report("Recording failed to start after handleWakeWordDetected", source: "mic")
            isListening = false
            inConversation = false
            print("[MIC] Reset isListening=false, inConversation=false due to recording failure")
            wakeWordService.stopListening()
            errorMessage = transcriptionService.errorMessage ?? "The microphone could not start."

        }
    }

    // MARK: - Voice Commands

    // Classification lives in `VoiceCommandRouter`, which matches on word boundaries via
    // the same tokeniser `WakeWordService` uses. The three predicates that used to sit
    // here were a second copy of phrase matching — `lower.contains(phrase)` over the same
    // lists, so "say your goodbyes to the crew" ended the conversation.

    func handleTranscription(_ text: String) async {
        guard listeningEnabled else { return }
        let generation = activationGeneration

        guard !isProcessing else {
            // Dropping an utterance outright is the failure nobody can debug afterwards:
            // the user spoke, nothing happened, and only a local print said why. Counts
            // only — the transcript itself is a recording of a person speaking and does
            // not go to the error surface.
            print("Already processing, ignoring: \(text)")
            ErrorReporter.shared.report(
                "utterance dropped: router busy (isProcessing) — \(WakeWordService.tokenize(text.lowercased()).count) spoken word(s) discarded, nothing reached the assistant",
                source: "voice-router", level: "warning")
            return
        }

        currentTranscription = text
        isListening = false
        print("[MIC] handleTranscription: set isListening=false, processing: \(text.prefix(50))")
        errorMessage = nil
        speechService.playEndListeningTone()
        print("Transcription: \(text)")

        let decision = VoiceCommandRouter.route(text)
        VoiceCommandRouter.reportWarnings(decision)

        if decision.command == .stop {
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

        if decision.command == .goodbye {
            print("Voice command: goodbye")
            speechService.stopSpeaking()
            inConversation = false
            lastResponse = "Goodbye!"
            await speechService.speak("Goodbye!")
            guard listeningEnabled, activationGeneration == generation else { return }
            await safeReturnToWakeWord()
            return
        }

        if VoiceCommandRouter.authorisesCapture(decision) {
            print("Voice command: take a picture")
            ErrorReporter.shared.report("Photo voice command detected. isConnected=\(isConnected), regState=\(registrationStateRaw)", source: "camera", level: "info")
            isProcessing = true
            speechService.playAcknowledgmentTone()  // Tone instead of spoken "Taking a picture" (avoids iOS voice)
            do {
                let photoData = try await cameraService.capturePhoto()
                guard listeningEnabled, activationGeneration == generation else { return }
                cameraService.saveToPhotoLibrary(photoData)
                print("Photo saved, sending to LLM with prompt: \(text)")
                ErrorReporter.shared.report("Photo captured via voice: \(photoData.count) bytes, sending to LLM", source: "camera", level: "info")

                let response = try await llmService.sendMessage(text, locationContext: locationService.locationContext, imageData: photoData)
                guard listeningEnabled, activationGeneration == generation else { return }
                lastResponse = response
                print("Bernard (vision): \(response)")

                startStopListener()
                await speechService.speak(response)
                guard listeningEnabled, activationGeneration == generation else { return }
                stopStopListener()

            } catch {
                guard listeningEnabled, activationGeneration == generation else { return }
                print("Photo capture failed: \(error)")
                ErrorReporter.shared.report("Photo voice command failed: \(error.localizedDescription)", source: "camera", level: "error")
                lastResponse = "Photo failed: \(error.localizedDescription)"
                await speechService.speak("Sorry, I couldn't take a photo or process the image. \(error.localizedDescription)")
                guard listeningEnabled, activationGeneration == generation else { return }
            }
            isProcessing = false
            if inConversation {
                isListening = true
                transcriptionService.startRecording()
            } else {
                await safeReturnToWakeWord()
            }
            return
        }

        // Normal message — send to LLM
        isProcessing = true

        do {
            let response = try await llmService.sendMessage(text, locationContext: locationService.locationContext)
            guard listeningEnabled, activationGeneration == generation else { return }
            lastResponse = response
            print("Bernard: \(response)")

            startStopListener()
            await speechService.speak(response)
            guard listeningEnabled, activationGeneration == generation else { return }
            stopStopListener()
        } catch {
            guard listeningEnabled, activationGeneration == generation else { return }
            print("[CRASH] LLM request failed: \(error)")
            ErrorReporter.shared.report("[CRASH] LLM failed: \(error.localizedDescription)", source: "llm")
            errorMessage = "Failed to get response: \(error.localizedDescription)"
            await speechService.speak("Sorry, I encountered an error.")
            guard listeningEnabled, activationGeneration == generation else { return }
        }

        isProcessing = false
        do {
            if inConversation {
                print("[MIC] Continuing conversation - listening for follow-up...")
                isListening = true
                transcriptionService.startRecording()
            } else {
                await safeReturnToWakeWord()
            }
        } catch {
            guard listeningEnabled, activationGeneration == generation else { return }
            print("[CRASH] Post-speech flow failed: \(error)")
            ErrorReporter.shared.report("[CRASH] Post-speech flow: \(error.localizedDescription)", source: "voice")
        }
    }

    private func startStopListener() {
        guard listeningEnabled else { return }
        let generation = activationGeneration
        wakeWordService.listenForStop = true
        Task { @MainActor [weak self] in
            guard let self, self.listeningEnabled,
                  self.activationGeneration == generation,
                  self.wakeWordService.listenForStop else { return }
            do { try await self.wakeWordService.startListening() }
            catch {
                guard self.activationGeneration == generation else { return }
                self.addDebugEvent("Stop listener unavailable: \(error.localizedDescription)")
            }
        }
    }

    private func stopStopListener() {
        wakeWordService.listenForStop = false
        // Follow-up transcription can keep using this engine in the background.
        // Ending the conversation owns the eventual engine teardown.
        wakeWordService.pauseRecognitionPublic()
    }

    /// Dump all state to ErrorReporter (App Insights) for remote diagnostics.
    /// Kept as a single consolidated log entry rather than many individual events.
    func snapshotDebugState() {
        let route = AVAudioSession.sharedInstance().currentRoute
        let inputs = route.inputs.map { "\($0.portName)(\($0.portType.rawValue))" }.joined(separator: ",")
        let outputs = route.outputs.map { "\($0.portName)(\($0.portType.rawValue))" }.joined(separator: ",")
        var parts = [
            "isConnected=\(isConnected)",
            "regState=\(registrationStateRaw)",
            "isListening=\(isListening)",
            "inConversation=\(inConversation)",
            "isProcessing=\(isProcessing)",
            "wakeWord=\(wakeWordService.isListening)",
            "transcribing=\(transcriptionService.isRecording)",
            "audioIn=\(inputs.isEmpty ? "none" : inputs)",
            "audioOut=\(outputs.isEmpty ? "none" : outputs)"
        ]
        if let err = errorMessage { parts.append("lastError=\(err)") }
        let snapshot = parts.joined(separator: ", ")
        addDebugEvent("[DEBUG] Snapshot: \(snapshot)")
    }

    private func returnToWakeWord() async {
        await safeReturnToWakeWord()
    }

    /// Return to Meta activation. No open microphone or custom wake phrase is
    /// needed while Bernard is idle.
    private func safeReturnToWakeWord() async {
        activationGeneration = UUID()
        isListening = false
        inConversation = false
        wakeWordService.listenForStop = false
        wakeWordService.stopListening()
        transcriptionService.cancelRecording()
        speechService.playDisconnectTone()
        startMetaVoiceLaunch()
    }

    // MARK: - Live Activity

    private var lastLiveActivityState: String = ""

    private func observeLiveActivityState() {
        // Poll state every 0.5s and sync to Live Activity when changed
        // This is simpler and more reliable than observing individual @Published properties
        Task {
            while true {
                try? await Task.sleep(nanoseconds: 500_000_000)
                let state = "\(isConnected)|\(isListening)|\(isProcessing)|\(speechService.isSpeaking)|\(lastResponse.prefix(80))"
                if state != lastLiveActivityState {
                    lastLiveActivityState = state
                    syncLiveActivity()
                }
            }
        }
    }
}

private enum MetaLaunchError: LocalizedError {
    case unavailable, disabled, busy, microphone
    var errorDescription: String? {
        switch self {
        case .unavailable: "The app is not ready."
        case .disabled: "Meta voice launch is disabled."
        case .busy: "Bernard is already listening or responding."
        case .microphone: "The microphone could not start."
        }
    }
}
