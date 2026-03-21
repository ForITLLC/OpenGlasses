import SwiftUI

/// Bottom control bar with circular action buttons.
/// Direct mode only — mic and camera controls.
struct BottomControlBar: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 16) {
            Spacer()

            // Camera — capture photo from glasses
            if !appState.isConnected {
                CircleButton(
                    icon: "camera.fill",
                    size: 56
                ) {
                    Task { await appState.glassesService.connect() }
                    appState.errorMessage = "Connecting glasses for camera..."
                }
            } else {
                CircleButton(
                    icon: "camera.fill",
                    size: 56,
                    isActive: appState.cameraService.isCaptureInProgress,
                    isDisabled: appState.cameraService.isCaptureInProgress
                ) {
                    Task { await appState.capturePhotoFromGlasses() }
                }
            }

            // Listen toggle
            CircleButton(
                icon: appState.isListening ? "mic.fill" : "mic",
                size: 64,
                isActive: appState.isListening
            ) {
                if !appState.isListening {
                    Task { await appState.handleWakeWordDetected() }
                }
            }

            Spacer()
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
