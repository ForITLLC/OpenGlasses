import SwiftUI

/// Bottom control bar — single mic button centered at the bottom.
/// Settings opens from the shared profile panel in the navigation bar.
struct BottomControlBar: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 8) {
            // Mic button — the ONLY bottom control
            CircleButton(
                icon: micIcon,
                actionLabel: micActionLabel,
                status: micStatus,
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

    private var micActionLabel: String {
        if appState.isProcessing { return "Cancel response" }
        if appState.speechService.isSpeaking { return "Stop speaking" }
        if appState.isListening || appState.inConversation { return "Stop listening" }
        return "Start listening"
    }

    private var micStatus: String {
        if appState.isProcessing { return "Processing" }
        if appState.speechService.isSpeaking { return "Speaking" }
        if appState.isListening { return "Listening" }
        if appState.inConversation { return "In conversation" }
        return "Ready"
    }

    private var micLabelColor: Color {
        if appState.isProcessing || appState.speechService.isSpeaking { return .orange }
        if appState.isListening { return .green }
        return Color(hex: "E1EFF3").opacity(0.6)
    }
}
