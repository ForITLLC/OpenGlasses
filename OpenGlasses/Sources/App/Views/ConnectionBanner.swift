import SwiftUI

/// Two separate connection status pills — Mic and Camera.
/// Each pill is tappable and triggers its own permission flow:
///   - Mic pill: tapping when disconnected triggers device pairing + mic permissions
///   - Camera pill: tapping when mic is connected triggers camera permission request
struct ConnectionBanner: View {
    @EnvironmentObject var appState: AppState
    @State private var cameraPermissionGranted: Bool = false
    @State private var cameraPermissionChecking: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            micPill
            cameraPill
            Spacer()
            // Settings gear in top-right
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
                // Trigger device pairing + mic permissions
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
            .overlay(
                Capsule().strokeBorder(
                    (connected ? Color.green : Color(hex: "E1EFF3")).opacity(0.15),
                    lineWidth: 0.5
                )
            )
        }
        .disabled(connected) // Only tappable when disconnected
    }

    // MARK: - Camera Pill

    private var cameraPill: some View {
        let micConnected = appState.isConnected

        return Button {
            guard micConnected else { return }
            // Trigger camera permission request
            cameraPermissionChecking = true
            Task {
                do {
                    try await appState.cameraService.ensurePermission()
                    cameraPermissionGranted = true
                } catch {
                    cameraPermissionGranted = false
                }
                cameraPermissionChecking = false
            }
        } label: {
            HStack(spacing: 5) {
                if cameraPermissionChecking {
                    ProgressView().scaleEffect(0.5).tint(Color(hex: "E1EFF3"))
                } else {
                    Image(systemName: cameraPermissionGranted ? "camera.fill" : "camera")
                        .font(.system(size: 10))
                        .foregroundColor(cameraPermissionGranted ? .green : Color(hex: "E1EFF3").opacity(0.5))
                }
                Circle()
                    .fill(cameraPermissionGranted ? Color.green : Color.gray)
                    .frame(width: 6, height: 6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(hex: "142F43").opacity(0.8), in: Capsule())
            .overlay(
                Capsule().strokeBorder(
                    (cameraPermissionGranted ? Color.green : Color(hex: "E1EFF3")).opacity(0.15),
                    lineWidth: 0.5
                )
            )
        }
        .disabled(!micConnected || cameraPermissionChecking)
        .opacity(micConnected ? 1.0 : 0.4) // Dimmed until mic is connected
    }
}
