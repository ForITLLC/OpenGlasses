import SwiftUI

/// Bottom control bar with circular action buttons.
/// Adapts layout based on current mode (Direct vs Gemini Live).
struct BottomControlBar: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var session: GeminiLiveSessionManager

    /// Sheet bindings passed down from MainView
    @Binding var showSettings: Bool
    @Binding var showModelPicker: Bool

    private var isGemini: Bool { appState.currentMode == .geminiLive }

    var body: some View {
        HStack(spacing: 16) {
            // Settings
            CircleButton(icon: "gearshape", size: 48) {
                showSettings = true
            }

            // Model Picker
            CircleButton(icon: "brain", size: 48) {
                showModelPicker = true
            }

            Spacer()

            // Camera — behaviour depends on glasses connection + mode
            if !appState.isConnected {
                // No glasses: tapping triggers connection flow
                CircleButton(
                    icon: "camera.fill",
                    size: 56
                ) {
                    Task { await appState.glassesService.connect() }
                    appState.errorMessage = "Connecting glasses for camera…"
                }
            } else if isGemini {
                // Gemini Live: camera streams automatically, button restarts if stalled
                CircleButton(
                    icon: "video.fill",
                    size: 52,
                    isActive: appState.cameraService.isStreaming,
                    isDisabled: !session.isActive
                ) {
                    if session.isActive && !appState.cameraService.isStreaming {
                        Task {
                            do {
                                try await appState.cameraService.startStreaming()
                            } catch {
                                appState.errorMessage = "Camera: \(error.localizedDescription)"
                            }
                        }
                    }
                }
            } else {
                // Direct mode: capture photo from glasses
                CircleButton(
                    icon: "camera.fill",
                    size: 56,
                    isActive: appState.cameraService.isCaptureInProgress,
                    isDisabled: appState.cameraService.isCaptureInProgress
                ) {
                    Task { await appState.capturePhotoFromGlasses() }
                }
            }

            // Session toggle (Gemini Live) or Listen toggle (Direct)
            if isGemini {
                CircleButton(
                    icon: session.isActive ? "stop.fill" : "play.fill",
                    size: 64,
                    isActive: session.isActive
                ) {
                    Task {
                        if session.isActive {
                            session.stopSession()
                        } else {
                            await session.startSession()
                        }
                    }
                }
            } else {
                CircleButton(
                    icon: appState.isListening ? "mic.fill" : "mic",
                    size: 64,
                    isActive: appState.isListening
                ) {
                    if !appState.isListening {
                        Task { await appState.handleWakeWordDetected() }
                    }
                }
            }

            Spacer()

            // Mode switch — clear labelling so user knows what they're getting
            if isGemini {
                CircleButton(icon: "mic.circle", size: 48) {
                    appState.switchMode(to: .direct)
                }
            } else {
                // Quick-launch Gemini Live from Direct mode
                CircleButton(
                    icon: "waveform.circle.fill",
                    size: 48,
                    badge: "G"
                ) {
                    appState.switchMode(to: .geminiLive)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.5), .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .ignoresSafeArea()
        )
    }
}
