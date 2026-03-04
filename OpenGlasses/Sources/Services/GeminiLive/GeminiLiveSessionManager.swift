import Foundation
import SwiftUI
import UIKit

/// Coordinator that ties all Gemini Live components together:
/// AudioManager → GeminiLiveService (audio), GeminiLiveService → AudioManager (playback),
/// GeminiLiveService → ToolCallRouter → OpenClawBridge (tool calls),
/// CameraService → FrameThrottler → GeminiLiveService (video).
@MainActor
class GeminiLiveSessionManager: ObservableObject {
    @Published var isActive: Bool = false
    @Published var connectionState: GeminiConnectionState = .disconnected
    @Published var isModelSpeaking: Bool = false
    @Published var userTranscript: String = ""
    @Published var aiTranscript: String = ""
    @Published var toolCallStatus: ToolCallStatus = .idle
    @Published var openClawConnectionState: OpenClawConnectionState = .notConfigured
    @Published var reconnecting: Bool = false
    @Published var errorMessage: String?

    // Shared OpenClaw bridge (injected from AppState)
    var openClawBridge: OpenClawBridge?

    // Internal components
    private let geminiService = GeminiLiveService()
    private let audioManager = GeminiLiveAudioManager()
    private let frameThrottler = FrameThrottler()
    private var toolCallRouter: ToolCallRouter?
    private var stateObservation: Task<Void, Never>?

    // Camera frame source — set by AppState to the existing CameraService's periodic captures
    var onRequestVideoFrame: (() async -> UIImage?)?

    // Location context — set by AppState from LocationService
    var locationContext: (() -> String?)?

    // Camera streaming control — set by AppState to start/check camera streaming
    var onRequestStartCamera: (() async -> Bool)?

    /// Whether the camera is actively streaming frames (used to conditionalise the vision prompt).
    var isCameraStreaming: Bool = false

    /// Whether to use iPhone audio mode (voiceChat with echo suppression) or glasses mode (videoChat).
    /// When true: aggressive echo cancellation + mic muting during model speech (co-located speaker/mic).
    /// When false: mild AEC suitable for remote mic on glasses (speaker on phone, mic on glasses).
    var useIPhoneAudioMode: Bool = true

    // Diagnostic counters
    private var submittedFrameCount = 0
    private var droppedNotActive = 0
    private var droppedNotReady = 0

    /// Submit a video frame directly (called from CameraService's continuous streaming callback).
    /// This bypasses the polling timer for lower latency.
    func submitVideoFrame(_ image: UIImage) {
        guard isActive else {
            droppedNotActive += 1
            if droppedNotActive <= 3 {
                NSLog("[Session] submitVideoFrame dropped — not active (count: %d)", droppedNotActive)
            }
            return
        }
        if !isCameraStreaming {
            isCameraStreaming = true
            NSLog("[Session] First camera frame received — camera streaming confirmed active")
        }
        guard connectionState == .ready else {
            droppedNotReady += 1
            if droppedNotReady <= 5 || droppedNotReady % 30 == 0 {
                NSLog("[Session] submitVideoFrame dropped — state: %@ (count: %d)",
                      String(describing: connectionState), droppedNotReady)
            }
            return
        }
        submittedFrameCount += 1
        if submittedFrameCount <= 3 || submittedFrameCount % 30 == 0 {
            NSLog("[Session] submitVideoFrame #%d forwarded to throttler (%dx%d)",
                  submittedFrameCount, Int(image.size.width), Int(image.size.height))
        }
        frameThrottler.submit(image)
    }

    // Timer for periodic frame capture
    private var frameTimer: Task<Void, Never>?

    // MARK: - Session Lifecycle

    func startSession() async {
        guard !isActive else { return }

        guard Config.isGeminiLiveConfigured else {
            errorMessage = "Gemini API key not configured. Add it in Settings."
            return
        }

        isActive = true
        errorMessage = nil

        // Ensure camera streaming is active (may have failed on mode switch if glasses weren't connected).
        // If startCamera succeeds, trust that frames will arrive — the user has approved camera permission
        // through the Meta companion app dialog, so we should build the vision prompt immediately rather
        // than waiting for the first frame (which may take seconds after permission approval).
        if let startCamera = onRequestStartCamera {
            let cameraOk = await startCamera()
            NSLog("[Session] Camera streaming start result: %@", cameraOk ? "success" : "failed (will work audio-only)")
            if cameraOk {
                isCameraStreaming = true
            }
        }
        NSLog("[Session] Building system instruction — isCameraStreaming: %@", isCameraStreaming ? "YES" : "NO")

        // Configure Gemini with system instruction, vision context, location, and tools
        let systemInstruction = buildSystemInstruction()
        NSLog("[Session] System instruction built — length: %d chars, camera streaming: %@",
              systemInstruction.count, isCameraStreaming ? "YES" : "NO")
        var toolDefs: [[String: Any]] = []
        if Config.isOpenClawConfigured {
            toolDefs = ToolDeclarations.allDeclarations()
        }
        geminiService.configure(systemInstruction: systemInstruction, toolDeclarations: toolDefs)

        // Wire audio capture → Gemini
        // In iPhone mode, mute mic while the model is speaking to prevent echo feedback.
        // The co-located loudspeaker + mic overwhelms iOS echo cancellation, causing
        // the model to hear itself and interrupt or produce garbled output.
        audioManager.onAudioCaptured = { [weak self] data in
            guard let self else { return }
            Task { @MainActor in
                // Echo suppression: skip sending mic audio while model speaks on iPhone speaker
                if self.useIPhoneAudioMode && self.geminiService.isModelSpeaking { return }
                self.geminiService.sendAudio(data: data)
            }
        }

        // Wire Gemini audio → playback
        geminiService.onAudioReceived = { [weak self] data in
            self?.audioManager.playAudio(data: data)
        }

        // Wire interruption → stop playback
        geminiService.onInterrupted = { [weak self] in
            self?.audioManager.stopPlayback()
        }

        // Wire turn complete
        geminiService.onTurnComplete = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.userTranscript = ""
            }
        }

        // Wire transcriptions
        geminiService.onInputTranscription = { [weak self] text in
            guard let self else { return }
            Task { @MainActor in
                self.userTranscript += text
                self.aiTranscript = ""
            }
        }

        geminiService.onOutputTranscription = { [weak self] text in
            guard let self else { return }
            Task { @MainActor in
                self.aiTranscript += text
            }
        }

        // Wire disconnection
        geminiService.onDisconnected = { [weak self] reason in
            guard let self else { return }
            Task { @MainActor in
                guard self.isActive else { return }
                if !self.geminiService.reconnecting {
                    self.stopSession()
                    self.errorMessage = "Connection lost: \(reason ?? "Unknown error")"
                }
            }
        }

        // Wire reconnection
        geminiService.onReconnected = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                NSLog("[Session] Reconnected — re-configuring session")
                // Re-configure with current settings (including fresh location)
                var toolDefs: [[String: Any]] = []
                if Config.isOpenClawConfigured {
                    toolDefs = ToolDeclarations.allDeclarations()
                }
                self.geminiService.configure(
                    systemInstruction: self.buildSystemInstruction(),
                    toolDeclarations: toolDefs
                )
                // Re-start audio capture
                do {
                    try self.audioManager.startCapture()
                } catch {
                    NSLog("[Session] Failed to restart audio after reconnect: %@", error.localizedDescription)
                }
                // Re-start frame capture
                self.startFrameCapture()
            }
        }

        // Wire OpenClaw tool calls
        if let bridge = openClawBridge, Config.isOpenClawConfigured {
            await bridge.checkConnection()
            bridge.resetSession()

            toolCallRouter = ToolCallRouter(bridge: bridge)

            geminiService.onToolCall = { [weak self] toolCall in
                guard let self else { return }
                Task { @MainActor in
                    for call in toolCall.functionCalls {
                        self.toolCallRouter?.handleToolCall(call) { [weak self] response in
                            self?.geminiService.sendToolResponse(response)
                        }
                    }
                }
            }

            geminiService.onToolCallCancellation = { [weak self] cancellation in
                guard let self else { return }
                Task { @MainActor in
                    self.toolCallRouter?.cancelToolCalls(ids: cancellation.ids)
                }
            }
        }

        // State observation — poll Gemini + OpenClaw state every 100ms
        stateObservation = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard !Task.isCancelled else { break }
                self.connectionState = self.geminiService.connectionState
                self.isModelSpeaking = self.geminiService.isModelSpeaking
                self.reconnecting = self.geminiService.reconnecting
                if let bridge = self.openClawBridge {
                    self.toolCallStatus = bridge.lastToolCallStatus
                    self.openClawConnectionState = bridge.connectionState
                }
            }
        }

        // Wire frame throttler to Gemini
        frameThrottler.reset()
        frameThrottler.onThrottledFrame = { [weak self] image in
            guard let self else { return }
            self.geminiService.sendVideoFrame(image: image)
        }

        // Audio setup — use iPhone mode when camera NOT streaming (no glasses connected),
        // use glasses/videoChat mode when camera IS streaming (mic is on remote device)
        useIPhoneAudioMode = !isCameraStreaming
        NSLog("[Session] Audio mode: %@", useIPhoneAudioMode ? "iPhone (voiceChat)" : "Glasses (videoChat)")
        do {
            try audioManager.setupAudioSession(useIPhoneMode: useIPhoneAudioMode)
        } catch {
            errorMessage = "Audio setup failed: \(error.localizedDescription)"
            isActive = false
            return
        }

        // Connect to Gemini
        let setupOk = await geminiService.connect()

        // Immediately sync connection state so submitVideoFrame doesn't block
        // waiting for the next 100ms poll cycle
        connectionState = geminiService.connectionState
        NSLog("[Session] Post-connect state: %@, videoFramesSent: %d",
              String(describing: connectionState), geminiService.videoFramesSent)

        if !setupOk {
            let msg: String
            if case .error(let err) = geminiService.connectionState {
                msg = err
            } else {
                msg = "Failed to connect to Gemini"
            }
            errorMessage = msg
            geminiService.disconnect()
            stateObservation?.cancel()
            stateObservation = nil
            isActive = false
            connectionState = .disconnected
            return
        }

        // Start mic capture
        do {
            try audioManager.startCapture()
        } catch {
            errorMessage = "Mic capture failed: \(error.localizedDescription)"
            geminiService.disconnect()
            stateObservation?.cancel()
            stateObservation = nil
            isActive = false
            connectionState = .disconnected
            return
        }

        // Late camera retry: if camera failed initially (SDK wasn't ready),
        // try again now that Gemini is connected (SDK has had more time to register).
        // VisionClaw avoids this by starting camera separately before Gemini.
        if !isCameraStreaming, let startCamera = onRequestStartCamera {
            NSLog("[Session] Camera was not streaming — retrying after Gemini connect...")
            let cameraOk = await startCamera()
            if cameraOk {
                isCameraStreaming = true
                NSLog("[Session] Late camera start succeeded! Reconfiguring for vision...")
                // Reconfigure Gemini with the vision prompt now that camera works
                let updatedInstruction = buildSystemInstruction()
                let visionNow = updatedInstruction.contains("You CAN see")
                NSLog("[Session] Reconfigured — vision enabled: %@", visionNow ? "YES" : "NO")
                // Switch to glasses audio mode since camera implies glasses are connected
                if !useIPhoneAudioMode {
                    NSLog("[Session] Already in glasses audio mode")
                } else {
                    useIPhoneAudioMode = false
                    NSLog("[Session] Switching to glasses audio mode (videoChat)")
                    do {
                        try audioManager.setupAudioSession(useIPhoneMode: false)
                    } catch {
                        NSLog("[Session] Audio mode switch failed: %@", error.localizedDescription)
                    }
                }
            } else {
                NSLog("[Session] Late camera retry also failed — continuing audio-only")
            }
        }

        // Start periodic camera frame capture
        startFrameCapture()
    }

    func stopSession() {
        NSLog("[Session] stopSession — submitted: %d, droppedNotActive: %d, droppedNotReady: %d",
              submittedFrameCount, droppedNotActive, droppedNotReady)
        toolCallRouter?.cancelAll()
        toolCallRouter = nil
        frameTimer?.cancel()
        frameTimer = nil
        audioManager.stopCapture()
        geminiService.disconnect()
        stateObservation?.cancel()
        stateObservation = nil
        isActive = false
        isCameraStreaming = false
        connectionState = .disconnected
        isModelSpeaking = false
        userTranscript = ""
        aiTranscript = ""
        toolCallStatus = .idle
        errorMessage = nil
        submittedFrameCount = 0
        droppedNotActive = 0
        droppedNotReady = 0
    }

    // MARK: - System Instruction

    /// Build the full system instruction for Gemini Live, including vision capabilities,
    /// tool usage instructions, and the user's current location.
    private func buildSystemInstruction() -> String {
        var prompt = Config.systemPrompt

        // Vision prompt depends on whether camera frames are actually flowing.
        // When streaming: full vision instructions.
        // When not streaming: tell Gemini camera is connecting, and critically —
        // do NOT describe things you cannot see. This prevents hallucinated vision.
        if isCameraStreaming {
            prompt += """


            VISION:
            You are connected to the camera on the user's Ray-Ban Meta smart glasses. You can see through their \
            camera and have a voice conversation. You receive live video frames from the glasses camera approximately \
            once per second. When the user asks you to look at something or asks "what do you see?", analyze the \
            most recent video frames and describe what you observe. You have full visual awareness of the user's \
            environment through these camera frames.
            """
        } else {
            prompt += """


            VISION:
            You are running on the user's Ray-Ban Meta smart glasses. The camera is still connecting and you have \
            NOT received any video frames yet. If the user asks you to look at something or describe what you see, \
            tell them the camera is still connecting and to try again in a moment. Do NOT describe or guess what \
            the user might be looking at — only describe things from actual video frames you have received.
            """
        }

        // Add OpenClaw tool instructions if configured
        if Config.isOpenClawConfigured {
            prompt += """


            TOOLS:
            You have access to a tool called "execute" that connects you to a powerful personal assistant (OpenClaw). \
            Use it when the user asks you to take any action: send messages, search the web, manage lists, set reminders, \
            create notes, control smart home devices, or anything beyond answering a question from your knowledge. \
            Be detailed in your task description — include names, content, platforms, quantities, etc.

            IMPORTANT: Before calling execute, ALWAYS speak a brief acknowledgment first. For example:
            - "Sure, let me add that to your shopping list." then call execute.
            - "Got it, searching for that now." then call execute.
            """
        }

        // Add location context if available
        if let location = locationContext?() {
            prompt += "\n\nUSER LOCATION: \(location)"
        }

        return prompt
    }

    // MARK: - Frame Capture

    /// Periodically request frames from the camera and submit to the throttler.
    /// This is a fallback polling mechanism — the primary path is direct push via submitVideoFrame().
    private func startFrameCapture() {
        frameTimer?.cancel()
        NSLog("[Session] Starting frame capture polling (fallback for direct push)")
        frameTimer = Task { [weak self] in
            guard let self else { return }
            var pollCount = 0
            while !Task.isCancelled && self.isActive {
                if let image = await self.onRequestVideoFrame?() {
                    pollCount += 1
                    if pollCount <= 3 || pollCount % 10 == 0 {
                        NSLog("[Session] Polled frame #%d from camera", pollCount)
                    }
                    self.frameThrottler.submit(image)
                }
                // Sleep for half the frame interval so throttler can do its job
                let sleepMs = UInt64(Config.geminiLiveVideoFrameInterval * 500_000_000)
                try? await Task.sleep(nanoseconds: sleepMs)
            }
        }
    }
}
