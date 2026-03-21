import SwiftUI

/// Two separate connection status pills — Mic and Camera.
///   - Mic pill: tapping when disconnected triggers device pairing
///   - Camera pill: tapping when not granted triggers camera permission (one-time)
/// Uses CameraService.isCameraPermissionGranted (published) so the green state persists.
struct ConnectionBanner: View {
    @EnvironmentObject var appState: AppState
    @State private var cameraPermissionChecking: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            micPill
            cameraPill
            Spacer()
            Button {
                appState.showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: "8EDCEF").opacity(0.5))
            }
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
                    .font(.system(size: 10))
                    .foregroundColor(connected ? .green : Color(hex: "E1EFF3").opacity(0.5))
                Circle()
                    .fill(connected ? Color.green : Color.gray)
                    .frame(width: 6, height: 6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(hex: "142F43").opacity(0.8), in: Capsule())
            .overlay(Capsule().strokeBorder((connected ? Color.green : Color(hex: "E1EFF3")).opacity(0.15), lineWidth: 0.5))
        }
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
                    ProgressView().scaleEffect(0.5).tint(Color(hex: "E1EFF3"))
                } else {
                    Image(systemName: cameraGranted ? "camera.fill" : "camera")
                        .font(.system(size: 10))
                        .foregroundColor(cameraGranted ? .green : Color(hex: "E1EFF3").opacity(0.5))
                }
                Circle()
                    .fill(cameraGranted ? Color.green : Color.gray)
                    .frame(width: 6, height: 6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(hex: "142F43").opacity(0.8), in: Capsule())
            .overlay(Capsule().strokeBorder((cameraGranted ? Color.green : Color(hex: "E1EFF3")).opacity(0.15), lineWidth: 0.5))
        }
        .disabled(!micConnected || cameraPermissionChecking || cameraGranted)
        .opacity(micConnected ? 1.0 : 0.4)
    }
}
