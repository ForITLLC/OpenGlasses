import SwiftUI

/// Bottom control bar — floating buttons with status dots, no background bar.
/// Camera button shows glasses connection state, mic button shows listening state.
struct BottomControlBar: View {
    @EnvironmentObject var appState: AppState
    @State private var showSettings = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Single mic button centered at bottom
            VStack(spacing: 8) {
                // Mic button — the ONLY control
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

            // Settings gear — small overlay in bottom-leading corner
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18))
                    .foregroundColor(Color(hex: "8EDCEF").opacity(0.6))
                    .frame(width: 36, height: 36)
            }
            .padding(.leading, 20)
            .padding(.bottom, 20)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
