import SwiftUI
import UIKit

/// Top-of-screen status pills showing glasses connection state.
/// Each pill is tappable — expands to show details and actions.
struct ConnectionBanner: View {
    @EnvironmentObject var appState: AppState

    @State private var expandedPill: PillType? = nil
    @State private var cameraPermissionStatus: String?

    enum PillType { case glasses, model }

    private var registrationStateLabel: String {
        switch appState.registrationStateRaw {
        case 3: return "Registered"
        case 2: return "Registering"
        case 1: return "Pending Auth"
        default: return "Disconnected"
        }
    }

    private var registrationStateColor: Color {
        switch appState.registrationStateRaw {
        case 3: return .green
        case 2: return .orange
        case 1: return .yellow
        default: return .red.opacity(0.8)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                glassesPill
                activeModelPill
                Spacer()
            }

            // Expanded dropdown
            if let expanded = expandedPill {
                expandedCard(for: expanded)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .animation(.easeInOut(duration: 0.2), value: expandedPill)
    }

    // MARK: - Pills

    private var glassesPill: some View {
        let connected = appState.isConnected
        let color: Color
        let label: String

        if connected {
            color = .green
            label = appState.glassesService.deviceName ?? "Glasses"
        } else if appState.registrationStateRaw > 0 {
            color = registrationStateColor
            label = registrationStateLabel
        } else {
            color = .red.opacity(0.7)
            label = "No Glasses"
        }

        return iconPill(
            systemIcon: "eyeglasses",
            color: color,
            label: label,
            isExpanded: expandedPill == .glasses
        ) {
            withAnimation { expandedPill = expandedPill == .glasses ? nil : .glasses }
        }
    }

    private var activeModelPill: some View {
        HStack(spacing: 5) {
            Image(systemName: "brain")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.purple)
            Text(appState.llmService.activeModelName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
        }
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    // MARK: - Reusable Pill

    private func iconPill(systemIcon: String, color: Color, label: String, isExpanded: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemIcon)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white.opacity(0.4))
                .rotationEffect(isExpanded ? .degrees(180) : .zero)
        }
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule().strokeBorder(
                isExpanded ? color.opacity(0.4) : Color.white.opacity(0.08),
                lineWidth: 0.5
            )
        )
        .onTapGesture(perform: action)
    }

    // MARK: - Expanded Card

    @ViewBuilder
    private func expandedCard(for type: PillType) -> some View {
        switch type {
        case .glasses:
            glassesCard
        case .model:
            EmptyView()
        }
    }

    private var glassesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appState.glassesService.connectionStatus)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))

            HStack(spacing: 8) {
                Circle()
                    .fill(registrationStateColor)
                    .frame(width: 7, height: 7)
                Text("Registration: \(appState.registrationStateRaw) \u{2014} \(registrationStateLabel)")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.75))
            }

            if appState.registrationStateRaw < 3 {
                Button {
                    Task { await appState.completeAuthorizationInMetaAI() }
                    withAnimation { expandedPill = nil }
                } label: {
                    Text("Complete in Meta AI")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.orange)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Debug")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))

                Text("Callback source: \(appState.lastCallbackSource)")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.7))

                Text("Callback URL: \(appState.lastCallbackURL)")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.65))
                    .lineLimit(2)

                if let callbackAt = appState.lastCallbackAt {
                    Text("Last callback at: \(callbackAt.formatted(date: .omitted, time: .standard))")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(appState.debugEvents.suffix(20).enumerated()), id: \.offset) { _, entry in
                            Text(entry)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.72))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 120)
                .padding(8)
                .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 12) {
                    Button {
                        let payload = appState.debugEvents.joined(separator: "\n")
                        UIPasteboard.general.string = payload
                    } label: {
                        Text("Copy Debug Log")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.cyan)
                    }

                    Button {
                        appState.debugEvents.removeAll()
                    } label: {
                        Text("Clear")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.orange)
                    }

                    Button {
                        Task { await appState.resetMetaRegistration() }
                    } label: {
                        Text("Reset Reg")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.yellow)
                    }
                }
            }

            if !appState.isConnected {
                Button {
                    Task { await appState.glassesService.connect() }
                    withAnimation { expandedPill = nil }
                } label: {
                    Text("Connect Glasses")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.cyan)
                }
            } else {
                if let battery = appState.glassesService.batteryLevel {
                    Text("Battery: \(battery)%")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                }

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
                    HStack(spacing: 6) {
                        if let status = cameraPermissionStatus {
                            switch status {
                            case "granted":
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 11))
                                Text("Camera Ready")
                                    .font(.system(size: 13, weight: .semibold))
                            case "error":
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11))
                                Text("Retry")
                                    .font(.system(size: 13, weight: .semibold))
                            default:
                                ProgressView().scaleEffect(0.7).tint(.white)
                                Text("Checking...")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                        } else {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 11))
                            Text("Camera Permission")
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                    .foregroundColor(
                        cameraPermissionStatus == "granted" ? .green :
                        cameraPermissionStatus == "error" ? .orange : .cyan
                    )
                }
                .disabled(cameraPermissionStatus != nil && cameraPermissionStatus != "granted" && cameraPermissionStatus != "error")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
    }
}
