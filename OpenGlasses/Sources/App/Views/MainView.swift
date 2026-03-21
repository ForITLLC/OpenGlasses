import SwiftUI

/// Primary interaction view — Dolores-branded with ForIT colors.
/// Full-screen dark canvas with:
///   1. ConnectionBanner (top)
///   2. StatusIndicator (center) with circular ring of 7 quick-action buttons
///   3. TranscriptOverlay (floating cards)
///   4. BottomControlBar (bottom)
struct MainView: View {
    @EnvironmentObject var appState: AppState

    // Quick actions arranged in a circle around the avatar — ONLY actions
    private let quickActions: [(icon: String, label: String, prompt: String)] = [
        ("checklist", "Tasks", "What are my tasks today?"),
        ("calendar", "Calendar", "What's on my calendar today?"),
        ("envelope", "Emails", "Check my latest emails"),
        ("note.text", "Notes", "Create a note"),
    ]

    var body: some View {
        ZStack {
            // ForIT dark background gradient
            LinearGradient(
                colors: [Color(hex: "0A1A26"), Color(hex: "142F43")],
                startPoint: .top,
                endPoint: .bottom
            ).ignoresSafeArea()

            // ForIT brand watermark — top-left
            VStack {
                HStack {
                    Image("ForITLogo")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(Color(hex: "E1EFF3"))
                        .frame(height: 30)
                        .opacity(0.9)
                        .padding(.leading, 16)
                        .padding(.top, 8)
                    Spacer()
                }
                Spacer()
            }

            VStack(spacing: 0) {
                Spacer()

                // Center: Dolores avatar + quick action ring
                GeometryReader { geo in
                    let ringSize = min(geo.size.width, geo.size.height) * 0.85

                    ZStack {
                        // Dolores avatar at center
                        StatusIndicator()

                        // Quick action ring — hidden during processing
                        if !appState.isProcessing && !appState.isListening {
                            RadialLayout() {
                                ForEach(Array(quickActions.enumerated()), id: \.offset) { _, action in
                                    quickActionButton(icon: action.icon, label: action.label) {
                                        await appState.handleTranscription(action.prompt)
                                    }
                                }
                            }
                            .frame(width: ringSize, height: ringSize)
                            .transition(.opacity.combined(with: .scale))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .animation(.easeInOut(duration: 0.2), value: appState.isProcessing)
                .animation(.easeInOut(duration: 0.2), value: appState.isListening)

                Spacer()

                // Transcript cards floating above the control bar
                TranscriptOverlay()
                    .padding(.bottom, 8)

                // Connection status pills
                ConnectionBanner()
                    .padding(.bottom, 4)

                // Bottom: mic button
                BottomControlBar()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Quick Action Button

    func quickActionButton(icon: String, label: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "142F43").opacity(0.8))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle().stroke(Color(hex: "8EDCEF").opacity(0.25), lineWidth: 1)
                        )
                    Image(systemName: icon)
                        .font(.system(size: 17))
                        .foregroundColor(Color(hex: "8EDCEF"))
                }
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Color(hex: "E1EFF3").opacity(0.7))
            }
        }
        .buttonStyle(.plain)
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

// MARK: - ForIT Brand Colors
extension Color {
    static let foritNavy = Color(hex: "142F43")
    static let foritLightBlue = Color(hex: "8EDCEF")
    static let foritLightGray = Color(hex: "E1EFF3")
    static let foritDarkBlue = Color(hex: "0A1A26")
}
