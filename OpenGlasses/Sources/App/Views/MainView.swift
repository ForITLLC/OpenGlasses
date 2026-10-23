import ForITCommon
import SwiftUI

/// Primary interaction view — Dolores-branded with ForIT colors.
/// Layout (top to bottom):
///   1. Shared profile panel, title and listening power in the navigation bar
///   2. Mic + Camera status pills
///   3. Dolores avatar + ForIT logo + quick actions (TRUE CENTER)
///   4. Transcript overlay (above mic button)
///   5. Mic button (bottom center)
struct MainView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var feedbackAccount = FeedbackAccount.shared

    // Six quick actions arranged around the avatar.
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
        NavigationStack {
            content
                .navigationTitle("ForIT Glasses")
                .forITInlineTitle()
                .forITProfileMenu(
                    account: feedbackAccount.profileAccount,
                    isSettingsPresented: $appState.showSettings,
                    items: {
                        if !feedbackAccount.signedIn {
                            Button {
                                feedbackAccount.askingSignIn = true
                            } label: {
                                Label("Send feedback", systemImage: "exclamationmark.bubble")
                            }
                        }
                    }, settings: {
                        SettingsView()
                            .environmentObject(appState)
                    })
                // Signed-out feedback follows the existing ForIT sign-in flow.
                .environment(\.forITFeedback, feedbackAccount.signedIn ? feedbackAccount.center : nil)
                .feedbackDialogs(isEnabled: !appState.showSettings)
                .toolbar {
                    ToolbarItem(placement: .forITBarTrailing) {
                        powerButton
                    }
                }
        }
        .preferredColorScheme(.dark)
    }

    private var content: some View {
        GeometryReader { geometry in
            ScrollView(.vertical) {
                // Main content stack
                VStack(spacing: 0) {
                    // Device status stays below the shared navigation bar.
                    ConnectionBanner()
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
                // Keep portrait centering; shorter viewports can scroll the full content.
                .frame(minHeight: geometry.size.height)
                #if DEBUG
                .allowsHitTesting(!OpenGlassesScreenshotFixture.isActive)
                #endif
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .forITScreenBackground()
    }

    private var powerButton: some View {
        Button {
            #if DEBUG
            guard !OpenGlassesScreenshotFixture.isActive else { return }
            #endif
            appState.setListeningEnabled(!appState.listeningEnabled)
        } label: {
            Image(systemName: "power")
        }
        .buttonStyle(.forITToolbar(isSelected: appState.listeningEnabled))
        .accessibilityLabel(appState.listeningEnabled ? "Turn listening off" : "Turn listening on")
        .accessibilityValue(appState.listeningEnabled ? "On" : "Off")
    }

    // MARK: - Quick Action Button

    func quickActionButton(icon: String, label: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                Text(label)
                    .font(.caption2)
            }
        }
        .buttonStyle(.forITIntrinsic(on: .navy))
        .accessibilityLabel(label)
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
