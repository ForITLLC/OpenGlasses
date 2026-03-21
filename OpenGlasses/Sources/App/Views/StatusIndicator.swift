import SwiftUI

/// Large central ambient status indicator — the visual heartbeat of the app.
/// Dolores avatar with pulsing ring. ForIT logo underneath (replaces text).
/// Only shows text status during active states (Listening/Speaking/Thinking).
struct StatusIndicator: View {
    @EnvironmentObject var appState: AppState

    /// Outer ring pulse
    @State private var ringScale: CGFloat = 1.0
    @State private var ringOpacity: Double = 0.3

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                // Ambient ring — pulses when active
                Circle()
                    .stroke(ringColor.opacity(ringOpacity), lineWidth: 2)
                    .frame(width: 130, height: 130)
                    .scaleEffect(ringScale)

                // Inner glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [ringColor.opacity(0.15), Color.clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 80
                        )
                    )
                    .frame(width: 110, height: 110)

                // Dolores avatar — always visible
                Image("DoloresAvatar")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 70, height: 70)
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(Color(hex: "8EDCEF").opacity(0.5), lineWidth: 1.5)
                    )
            }
            .animation(.easeInOut(duration: 0.4), value: isActive)
            .onAppear { startRingAnimation() }
            .onChange(of: isPulsing) { _, active in
                if active { startRingAnimation() } else { stopRingAnimation() }
            }

            // ForIT logo — centered under avatar (replaces "Ready" / "ForIT AI" text)
            Image("ForITLogo")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundColor(Color(hex: "E1EFF3"))
                .frame(height: 24)
                .opacity(isActive ? 0.4 : 0.9)

            // Status text — ONLY during active states
            if isActive {
                Text(statusLabel)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(hex: "8EDCEF"))
                    .transition(.opacity)
            }

            // Tool call status
            if appState.llmService.toolCallStatus.isActive {
                toolCallPill(appState.llmService.toolCallStatus.displayText, color: Color(hex: "8EDCEF"))
            }
        }
    }

    // MARK: - Computed Properties

    private var isActive: Bool {
        appState.isListening || appState.speechService.isSpeaking || appState.isProcessing
    }

    private var ringColor: Color {
        if !appState.isConnected { return Color(hex: "8EDCEF").opacity(0.4) }
        if appState.isListening { return Color(hex: "8EDCEF") }
        if appState.speechService.isSpeaking { return Color(hex: "8EDCEF") }
        return Color(hex: "8EDCEF").opacity(0.5)
    }

    private var isPulsing: Bool {
        if !appState.isConnected { return false }
        return appState.isListening
    }

    private var statusLabel: String {
        if appState.isListening { return "Listening..." }
        if appState.speechService.isSpeaking { return "Speaking..." }
        if appState.isProcessing { return "Thinking..." }
        return ""
    }

    // MARK: - Helpers

    private func toolCallPill(_ text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            ProgressView().scaleEffect(0.7).tint(Color(hex: "E1EFF3"))
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(hex: "E1EFF3").opacity(0.9))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(color.opacity(0.3), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.4), lineWidth: 0.5))
    }

    private func startRingAnimation() {
        withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
            ringScale = 1.12
            ringOpacity = 0.6
        }
    }

    private func stopRingAnimation() {
        withAnimation(.easeOut(duration: 0.5)) {
            ringScale = 1.0
            ringOpacity = 0.3
        }
    }
}
