import ForITCommon
import SwiftUI

/// Separate microphone and camera status actions using shared control targets.
///   - Microphone: tapping when disconnected triggers device pairing
///   - Camera: tapping when not granted triggers camera permission (one-time)
/// Uses CameraService.isCameraPermissionGranted (published) so the green state persists.
struct ConnectionBanner: View {
    @EnvironmentObject var appState: AppState
    @State private var cameraPermissionChecking: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            micPill
            cameraPill
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Mic Pill

    private var micPill: some View {
        let connected = appState.isConnected
        return Button {
            if !connected {
                Task { await appState.completeAuthorizationInMetaAI() }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: connected ? "mic.fill" : "mic.slash")
                Image(systemName: "circle.fill")
                    .font(.caption2)
                    .foregroundStyle(connected ? Color.green : Color.gray)
            }
        }
        .buttonStyle(.forITIntrinsic(on: .navy))
        .accessibilityLabel(connected ? "Microphone connected" : "Connect glasses microphone")
        .accessibilityValue(connected ? "Connected" : "Disconnected")
        .disabled(connected)
    }

    // MARK: - Camera Pill

    private var cameraPill: some View {
        let micConnected = appState.isConnected
        // Read from CameraService's published property — persists across captures
        let cameraGranted = appState.cameraService.isCameraPermissionGranted

        return Button {
            guard micConnected, !cameraGranted else { return }
            cameraPermissionChecking = true
            Task {
                do {
                    try await appState.cameraService.ensurePermission()
                } catch {
                    ErrorReporter.shared.report("Camera permission denied from banner: \(error)", source: "camera", level: "warning")
                }
                cameraPermissionChecking = false
            }
        } label: {
            HStack(spacing: 5) {
                if cameraPermissionChecking {
                    ProgressView()
                } else {
                    Image(systemName: cameraGranted ? "camera.fill" : "camera")
                }
                Image(systemName: "circle.fill")
                    .font(.caption2)
                    .foregroundStyle(cameraGranted ? Color.green : Color.gray)
            }
        }
        .buttonStyle(.forITIntrinsic(on: .navy))
        .accessibilityLabel(cameraGranted ? "Camera permission granted" : "Enable glasses camera")
        .accessibilityValue(cameraPermissionChecking ? "Checking permission" : (cameraGranted ? "Permission granted" : (micConnected ? "Permission required" : "Connect glasses first")))
        .disabled(!micConnected || cameraPermissionChecking || cameraGranted)
    }
}
