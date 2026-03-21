import SwiftUI

/// Bottom control bar — single mic button centered at the bottom.
/// Settings gear moved to ConnectionBanner (top-right).
struct BottomControlBar: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 8) {
            // Mic button — the ONLY bottom control
            CircleButton(
                icon: micIcon,
                size: 64,
                isActive: appState.isListening || appState.isProcessing || appState.speechService.isSpeaking
            ) {
                if appState.isProcessing || appState.speechService.isSpeaking {
                    // Interrupt — cancel current response
                    appState.cancelCurrentResponse()
                } else if appState.isListening || appState.inConversation {
                    appState.isListening = false
                    appState.inConversation = false
                    appState.transcriptionService.stopRecording()
                } else {
                    Task { await appState.handleWakeWordDetected(manualActivation: true) }
                }
            }

            // Status text below mic
            Text(micLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(micLabelColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 16)
        .sheet(isPresented: $appState.showSettings) {
            SettingsView()
                .environmentObject(appState)
        }
    }

    private var micIcon: String {
        if appState.isProcessing { return "stop.fill" }
        if appState.speechService.isSpeaking { return "stop.fill" }
        if appState.isListening { return "mic.fill" }
        return "mic"
    }

    private var micLabel: String {
        if appState.isProcessing { return "Tap to cancel" }
        if appState.speechService.isSpeaking { return "Tap to stop" }
        if appState.isListening { return "Listening" }
        return "Ready"
    }

    private var micLabelColor: Color {
        if appState.isProcessing || appState.speechService.isSpeaking { return .orange }
        if appState.isListening { return .green }
        return Color(hex: "E1EFF3").opacity(0.6)
    }
}
