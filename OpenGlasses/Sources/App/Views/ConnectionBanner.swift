import SwiftUI
import AVFoundation
import UIKit

/// Top-of-screen status pills showing glasses connection status.
/// Single row: connection pill and a contextual action button.
struct ConnectionBanner: View {
    @EnvironmentObject var appState: AppState

    @State private var cameraPermissionStatus: String?

    var body: some View {
        HStack(spacing: 8) {
            glassesPill
            Spacer()
            actionButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Pills

    private var glassesPill: some View {
        let connected = appState.isConnected
        let color = connected ? Color(hex: "8EDCEF") : Color(hex: "E1EFF3").opacity(0.4)
        let label = connected ? (appState.glassesService.deviceName ?? "Connected") : "Disconnected"

        return HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: "E1EFF3").opacity(0.85))
                .lineLimit(1)
        }
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(hex: "142F43").opacity(0.8), in: Capsule())
        .overlay(
            Capsule().strokeBorder(Color(hex: "E1EFF3").opacity(0.08), lineWidth: 0.5)
        )
    }

    // MARK: - Action Button

    @ViewBuilder
    private var actionButton: some View {
        if !appState.isConnected {
            Button {
                Task { await appState.glassesService.connect() }
            } label: {
                Text("Connect")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "0A1A26"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color(hex: "8EDCEF"), in: Capsule())
            }
        } else {
            cameraButton
        }
    }

    private var cameraButton: some View {
        Button {
            cameraPermissionStatus = "checking"
            appState.cameraService.onRegistrationProgress = { state in
                Task { @MainActor in
                    if state < 2 {
                        cameraPermissionStatus = "SDK \(state)..."
                    }
                }
            }
            Task {
                defer { appState.cameraService.onRegistrationProgress = nil }
                do {
                    try await appState.cameraService.ensurePermission()
                    cameraPermissionStatus = "granted"
                } catch {
                    cameraPermissionStatus = "error"
                }
            }
        } label: {
            HStack(spacing: 4) {
                if let status = cameraPermissionStatus {
                    switch status {
                    case "granted":
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "8EDCEF"))
                    case "error":
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "8EDCEF").opacity(0.7))
                    default:
                        ProgressView().scaleEffect(0.6).tint(Color(hex: "E1EFF3"))
                    }
                } else {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "8EDCEF"))
                }
                Text(cameraButtonLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "8EDCEF"))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(hex: "142F43").opacity(0.8), in: Capsule())
            .overlay(
                Capsule().strokeBorder(Color(hex: "8EDCEF").opacity(0.2), lineWidth: 0.5)
            )
        }
        .disabled(cameraPermissionStatus != nil && cameraPermissionStatus != "granted" && cameraPermissionStatus != "error")
    }

    private var cameraButtonLabel: String {
        switch cameraPermissionStatus {
        case "granted": return "Ready"
        case "error": return "Retry"
        case nil: return "Camera"
        default: return "..."
        }
    }
}
