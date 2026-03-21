import SwiftUI

/// Floating transcript cards — shows what user said and what the AI responded.
/// Positioned above the bottom control bar, fading in/out as content arrives.
struct TranscriptOverlay: View {
    @EnvironmentObject var appState: AppState

    private var userText: String {
        appState.currentTranscription
    }

    private var aiText: String {
        appState.lastResponse
    }

    private var aiLabel: String {
        appState.llmService.activeModelName
    }

    var body: some View {
        VStack(spacing: 8) {
            if let error = appState.errorMessage {
                transcriptCard(label: "Error", text: error, accent: .red)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if !aiText.isEmpty {
                transcriptCard(label: aiLabel, text: aiText, accent: .cyan)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if !userText.isEmpty {
                transcriptCard(label: "You", text: userText, accent: .white)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .animation(.easeInOut(duration: 0.3), value: userText)
        .animation(.easeInOut(duration: 0.3), value: aiText)
    }

    // MARK: - Card

    private func transcriptCard(label: String, text: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(accent.opacity(0.7))
                .textCase(.uppercase)
                .tracking(0.5)

            Text(text)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(accent.opacity(0.15), lineWidth: 0.5)
        )
    }
}
