import SwiftUI

/// Primary interaction view — Dolores-branded, minimal.
/// Full-screen dark canvas with:
///   1. ConnectionBanner (top)
///   2. StatusIndicator (center)
///   3. TranscriptOverlay (floating cards)
///   4. BottomControlBar (bottom)
struct MainView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            // Dark background with subtle gradient
            LinearGradient(
                colors: [Color(hex: "1a1a2e"), Color.black],
                startPoint: .top,
                endPoint: .bottom
            ).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Center: ambient status indicator
                StatusIndicator()

                Spacer()

                // Transcript cards floating above the control bar
                TranscriptOverlay()
                    .padding(.bottom, 8)

                // Connection status pills
                ConnectionBanner()
                    .padding(.bottom, 4)

                // Bottom: mic + camera buttons
                BottomControlBar()
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Color hex extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        r = Double((int >> 16) & 0xFF) / 255.0
        g = Double((int >> 8) & 0xFF) / 255.0
        b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
