import SwiftUI

/// Bottom control bar — floating buttons with status dots, no background bar.
/// Camera button shows glasses connection state, mic button shows listening state.
struct BottomControlBar: View {
    @EnvironmentObject var appState: AppState
    @State private var showSettings = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Floating buttons centered at bottom
            HStack(spacing: 40) {
                // Camera button with status dot
                ZStack(alignment: .topTrailing) {
                    CircleButton(
                        icon: "camera",
                        size: 48
                    ) {
                        Task { await appState.capturePhotoFromGlasses() }
                    }
                    // Status dot — green when glasses connected
                    Circle()
                        .fill(appState.isConnected ? Color.green : Color(hex: "E1EFF3").opacity(0.3))
                        .frame(width: 8, height: 8)
                        .offset(x: 2, y: -2)
                }

                // Mic button with status dot
                ZStack(alignment: .topTrailing) {
                    CircleButton(
                        icon: appState.isListening ? "mic.fill" : "mic",
                        size: 64,
                        isActive: appState.isListening
                    ) {
                        print("[MIC] Button tapped. isListening=\(appState.isListening) inConversation=\(appState.inConversation) isProcessing=\(appState.isProcessing) isRecording=\(appState.transcriptionService.isRecording) wakeWordListening=\(appState.wakeWordService.isListening)")
                        if appState.isListening || appState.inConversation {
                            // Stop listening
                            print("[MIC] Stopping: setting isListening=false, inConversation=false, calling stopRecording")
                            appState.isListening = false
                            appState.inConversation = false
                            appState.transcriptionService.stopRecording()
                        } else {
                            // Start listening — manual activation gets longer no-speech timeout
                            print("[MIC] Starting listening via mic button (manual)")
                            Task { await appState.handleWakeWordDetected(manualActivation: true) }
                        }
                    }
                    // Status dot — green when listening
                    Circle()
                        .fill(appState.isListening ? Color.green : Color(hex: "E1EFF3").opacity(0.3))
                        .frame(width: 8, height: 8)
                        .offset(x: 2, y: -2)
                }
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
