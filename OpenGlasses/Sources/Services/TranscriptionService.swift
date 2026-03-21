import Foundation
import AVFoundation
import Speech

/// On-device speech transcription using iOS Speech Recognition
/// Reuses the shared audio engine from WakeWordService to avoid
/// stopping/restarting the engine (which fails when backgrounded).
@MainActor
class TranscriptionService: ObservableObject {
    @Published var isRecording: Bool = false
    @Published var currentTranscription: String = ""
    @Published var errorMessage: String?

    var onTranscriptionComplete: ((String) -> Void)?
    /// Called when recording times out with no speech detected at all
    var onSilenceTimeout: (() -> Void)?

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var noSpeechTimer: Timer?
    private let silenceThreshold: TimeInterval = 2.0
    private let defaultNoSpeechTimeout: TimeInterval = 5.0
    /// Override for the current recording session (reset on stop)
    private var currentNoSpeechTimeout: TimeInterval?
    private var didReceiveSpeech: Bool = false

    /// Shared audio engine — set by AppState from WakeWordService
    weak var sharedAudioEngineProvider: WakeWordService?

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    /// Start recording. Pass a custom `noSpeechTimeout` to override the default 5s
    /// (e.g. 15s when triggered by manual mic button press vs 5s for wake-word flow).
    func startRecording(noSpeechTimeout: TimeInterval? = nil) {
        print("[MIC] TranscriptionService.startRecording() called. isRecording=\(isRecording) customTimeout=\(String(describing: noSpeechTimeout))")
        guard !isRecording else {
            print("[MIC] startRecording: already recording, returning early")
            return
        }

        currentNoSpeechTimeout = noSpeechTimeout
        didReceiveSpeech = false
        currentTranscription = ""
        do {
            try setupAndStartRecording()
            isRecording = true
            print("[MIC] Recording started successfully. isRecording=\(isRecording)")
            startNoSpeechTimer()
        } catch {
            print("[MIC] Recording setup FAILED: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    func stopRecording() {
        print("[MIC] TranscriptionService.stopRecording() called. isRecording=\(isRecording)")
        guard isRecording else {
            print("[MIC] stopRecording: not recording, returning early")
            return
        }

        silenceTimer?.invalidate()
        silenceTimer = nil
        noSpeechTimer?.invalidate()
        noSpeechTimer = nil
        recognitionTask?.finish()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        isRecording = false
        currentNoSpeechTimeout = nil

        if !currentTranscription.isEmpty {
            let finalText = currentTranscription
            currentTranscription = ""
            print("📤 Transcription complete, sending: \(finalText)")
            onTranscriptionComplete?(finalText)
        } else if !didReceiveSpeech {
            print("🤫 No speech detected, silence timeout")
            onSilenceTimeout?()
        }
    }

    private var effectiveNoSpeechTimeout: TimeInterval {
        currentNoSpeechTimeout ?? defaultNoSpeechTimeout
    }

    private func startNoSpeechTimer() {
        noSpeechTimer?.invalidate()
        let timeout = effectiveNoSpeechTimeout
        noSpeechTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRecording, !self.didReceiveSpeech else {
                    print("[MIC] No-speech timer fired but guard failed: isRecording=\(self?.isRecording ?? false) didReceiveSpeech=\(self?.didReceiveSpeech ?? false)")
                    return
                }
                print("[MIC] No speech after \(timeout)s — stopping recording")
                self.stopRecording()
            }
        }
    }

    private func setupAndStartRecording() throws {
        recognitionTask?.cancel()
        recognitionTask = nil

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw TranscriptionError.setupFailed("Could not create recognition request")
        }
        recognitionRequest.shouldReportPartialResults = true

        // Try to reuse the shared audio engine from WakeWordService
        // This avoids stopping/starting the engine which fails in background
        if let provider = sharedAudioEngineProvider, provider.getAudioEngine() != nil {
            let engine = provider.getAudioEngine()!
            print("[MIC] Reusing shared audio engine. engineRunning=\(engine.isRunning)")
            // Capture request directly — the closure is @Sendable so can't access @MainActor self
            let request = recognitionRequest
            provider.setAudioBufferForwarder { buffer in
                request.append(buffer)
            }
        } else {
            // Fallback: create our own engine (works in foreground only)
            print("🎙️ Creating dedicated audio engine (no shared engine available)")
            let audioEngine = AVAudioEngine()
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
            self.fallbackAudioEngine = audioEngine
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                self?.handleRecognitionResult(result: result, error: error)
            }
        }
    }

    /// Fallback engine used only when shared engine isn't available
    private var fallbackAudioEngine: AVAudioEngine?

    /// Clean up fallback engine and buffer forwarder when stopping
    private func cleanupEngine() {
        sharedAudioEngineProvider?.setAudioBufferForwarder(nil)
        if let engine = fallbackAudioEngine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            fallbackAudioEngine = nil
        }
    }

    private func handleRecognitionResult(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result = result {
            currentTranscription = result.bestTranscription.formattedString
            if !didReceiveSpeech {
                didReceiveSpeech = true
                noSpeechTimer?.invalidate()
                noSpeechTimer = nil
            }
            resetSilenceTimer()

            if result.isFinal {
                cleanupEngine()
                stopRecording()
            }
        }

        if let error = error {
            print("[MIC] Transcription recognition error: \(error.localizedDescription)")
            cleanupEngine()
            stopRecording()
        }
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.cleanupEngine()
                self.stopRecording()
            }
        }
    }
}

enum TranscriptionError: LocalizedError {
    case setupFailed(String)
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .setupFailed(let msg): return "Setup failed: \(msg)"
        case .permissionDenied: return "Speech recognition permission denied"
        }
    }
}
