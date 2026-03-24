import SwiftUI

/// Primary interaction view — Dolores-branded with ForIT colors.
/// Layout (top to bottom):
///   1. Mic + Camera status pills (top corners)
///   2. Dolores avatar + ForIT logo + quick actions (TRUE CENTER)
///   3. Transcript overlay (above mic button)
///   4. Mic button (bottom center)
struct MainView: View {
    @EnvironmentObject var appState: AppState

    // 5 quick actions arranged in a circle around the avatar
    // Quick actions — voice-first starting prompts around the ring
    private let quickActions: [(icon: String, label: String, action: QuickActionType)] = [
        ("calendar", "Meetings", .prompt("Give me a summary of my meetings today")),
        ("checklist", "Tasks", .prompt("Give me a summary of my tasks today")),
        ("camera.fill", "Photo → Task", .photoThen("Turn this photo into a task")),
        ("person.text.rectangle", "Lead Lookup", .photoThen("Look at this business card or name tag. Extract the person's name, company, email, and any other details visible. Then follow this exact sequence: 1) FIRST call enrich_lookup with their email and/or company domain — this gives you Lusha data (title, seniority, company size, revenue, LinkedIn). 2) THEN search the CRM by name and company to see if we already know them. 3) If found in CRM, call the AI summary tool to get our relationship briefing. 4) Combine everything into a concise verbal brief: who they are (from enrichment), our history with them (from CRM), and any open deals or flags. If not in CRM, tell me what enrichment found and offer to create them as a lead. Keep it short — I'm wearing glasses.")),
        ("camera.viewfinder", "New Lead", .photoThen("Create a lead from this business card")),
        ("envelope", "Emails", .prompt("Summarize my unread emails")),
    ]

    enum QuickActionType {
        case prompt(String)
        case photo
        case photoThen(String)  // Take photo, then send prompt with image
    }

    var body: some View {
        ZStack {
            // ForIT dark background gradient
            LinearGradient(
                colors: [Color(hex: "0A1A26"), Color(hex: "142F43")],
                startPoint: .top,
                endPoint: .bottom
            ).ignoresSafeArea()

            // Main content stack
            VStack(spacing: 0) {
                // Top: Connection banner + power button
                HStack {
                    ConnectionBanner()
                    Spacer()
                    Button {
                        let newState = !Config.listeningEnabled
                        Config.setListeningEnabled(newState)
                        if !newState {
                            appState.wakeWordService.stopListening()
                        } else {
                            Task { try? await appState.wakeWordService.startListening() }
                        }
                    } label: {
                        Image(systemName: Config.listeningEnabled ? "power" : "power.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(Config.listeningEnabled ? Color(hex: "8EDCEF").opacity(0.5) : .red)
                            .padding(8)
                    }
                }
                .padding(.top, 4)
                .padding(.horizontal, 8)

                Spacer()

                // CENTER: Dolores avatar + ForIT logo + quick action ring
                ZStack {
                    StatusIndicator()

                    // Quick action ring — hidden during processing/listening
                    // Ring is 340pt wide to push icons further from avatar
                    if !appState.isProcessing && !appState.isListening {
                        RadialLayout() {
                            ForEach(Array(quickActions.enumerated()), id: \.offset) { _, action in
                                quickActionButton(icon: action.icon, label: action.label) {
                                    switch action.action {
                                    case .prompt(let text):
                                        await appState.handleTranscription(text)
                                    case .photo:
                                        await appState.capturePhotoFromGlasses()
                                    case .photoThen(let prompt):
                                        await appState.capturePhotoAndSend(prompt: prompt)
                                    }
                                }
                            }
                        }
                        .frame(width: 340, height: 340)
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
