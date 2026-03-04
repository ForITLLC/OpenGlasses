import SwiftUI

/// Primary interaction view — replaces the old ContentView.
/// Full-screen dark canvas with layered components:
///   1. ConnectionBanner (top)
///   2. StatusIndicator (center, ambient)
///   3. TranscriptOverlay (floating cards above controls)
///   4. BottomControlBar (bottom edge)
struct MainView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSettings = false
    @State private var showModelPicker = false

    var body: some View {
        let session = appState.geminiLiveSession

        ZStack {
            // Full-screen dark background
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Center: ambient status indicator
                StatusIndicator(session: session)

                Spacer()

                // Transcript cards floating above the control bar
                TranscriptOverlay(session: session)
                    .padding(.bottom, 8)

                // Connection status pills — above the control bar for easy reach
                ConnectionBanner(session: session, openClawBridge: appState.openClawBridge)
                    .padding(.bottom, 4)

                // Bottom: action buttons
                BottomControlBar(
                    session: session,
                    showSettings: $showSettings,
                    showModelPicker: $showModelPicker
                )
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            SettingsView(appState: appState)
        }
        .sheet(isPresented: $showModelPicker) {
            ModelPickerSheet(appState: appState)
        }
    }
}
