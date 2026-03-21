import SwiftUI

/// Primary interaction view — Dolores-branded with ForIT colors.
/// Layout (top to bottom):
///   1. ForIT logo watermark (top-left)
///   2. Connection pill (top-left, below logo)
///   3. Dolores avatar + quick actions (TRUE CENTER of screen)
///   4. Transcript overlay (above mic button)
///   5. Mic button (bottom center)
struct MainView: View {
    @EnvironmentObject var appState: AppState

    // 5 quick actions arranged in a circle around the avatar
    private let quickActions: [(icon: String, label: String, action: QuickActionType)] = [
        ("checklist", "Tasks", .prompt("What are my tasks today?")),
        ("calendar", "Calendar", .prompt("What's on my calendar today?")),
        ("camera.fill", "Photo", .photo),
        ("envelope", "Emails", .prompt("Check my latest emails")),
        ("note.text", "Notes", .prompt("Create a note")),
    ]

    enum QuickActionType {
        case prompt(String)
        case photo
    }

    var body: some View {
        ZStack {
            // ForIT dark background gradient
            LinearGradient(
                colors: [Color(hex: "0A1A26"), Color(hex: "142F43")],
                startPoint: .top,
                endPoint: .bottom
            ).ignoresSafeArea()

            // Layer 1: ForIT logo (top-left)
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

            // Layer 2: Main content stack
            VStack(spacing: 0) {
                // Connection status (below safe area)
                ConnectionBanner()
                    .padding(.top, 4)

                Spacer()

                // CENTER: Dolores avatar + quick action ring
                ZStack {
                    StatusIndicator()

                    // Quick action ring — hidden during processing/listening
                    if !appState.isProcessing && !appState.isListening {
                        RadialLayout() {
                            ForEach(Array(quickActions.enumerated()), id: \.offset) { _, action in
                                quickActionButton(icon: action.icon, label: action.label) {
                                    switch action.action {
                                    case .prompt(let text):
                                        await appState.handleTranscription(text)
                                    case .photo:
                                        await appState.capturePhotoFromGlasses()
                                    }
                                }
                            }
                        }
                        .frame(width: 280, height: 280)
                        .transition(.opacity.combined(with: .scale))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: appState.isProcessing)
                .animation(.easeInOut(duration: 0.2), value: appState.isListening)

                Spacer()

                // Transcript cards floating above the mic button
                TranscriptOverlay()
                    .padding(.bottom, 8)

                // Bottom: single mic button
                BottomControlBar()
                    .padding(.bottom, 8)
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
