import SwiftUI

/// Bottom control bar — single mic button centered at the bottom.
/// Settings gear moved to ConnectionBanner (top-right).
struct BottomControlBar: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 8) {
            // Mic button — the ONLY bottom control
            CircleButton(
                icon: appState.isListening ? "mic.fill" : "mic",
                size: 64,
                isActive: appState.isListening
            ) {
                if appState.isListening || appState.inConversation {
                    appState.isListening = false
                    appState.inConversation = false
                    appState.transcriptionService.stopRecording()
                } else {
                    Task { await appState.handleWakeWordDetected(manualActivation: true) }
                }
            }

            // Status text below mic
            Text(appState.isListening ? "Listening" : "Ready")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(appState.isListening ? .green : Color(hex: "E1EFF3").opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 16)
        .sheet(isPresented: $appState.showSettings) {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
