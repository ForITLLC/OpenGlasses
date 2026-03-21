import ActivityKit
import SwiftUI
import WidgetKit

/// Live Activity widget for Glasses — shows on Lock Screen and Dynamic Island.
struct GlassesActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GlassesActivityAttributes.self) { context in
            // Lock Screen banner
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded view (long press on Dynamic Island)
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.isConnected ? "eyeglasses" : "eyeglasses")
                        .font(.system(size: 20))
                        .foregroundColor(context.state.isConnected ? .green : .gray)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    statusIcon(state: context.state)
                        .font(.system(size: 20))
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.status)
                        .font(.headline)
                        .foregroundColor(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !context.state.lastResponse.isEmpty {
                        Text(context.state.lastResponse)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
            } compactLeading: {
                // Compact left pill (Dynamic Island)
                Image(systemName: "eyeglasses")
                    .foregroundColor(context.state.isConnected ? .green : .gray)
                    .font(.system(size: 14))
            } compactTrailing: {
                // Compact right pill
                statusIcon(state: context.state)
                    .foregroundColor(statusColor(state: context.state))
                    .font(.system(size: 14))
            } minimal: {
                // Minimal (when another Live Activity is competing)
                Image(systemName: "eyeglasses")
                    .foregroundColor(context.state.isConnected ? .green : .gray)
                    .font(.system(size: 12))
            }
        }
    }

    // MARK: - Lock Screen View

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<GlassesActivityAttributes>) -> some View {
        HStack(spacing: 12) {
            // Glasses icon with connection dot
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "eyeglasses")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                Circle()
                    .fill(context.state.isConnected ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                    .offset(x: 2, y: 2)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(context.state.status)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)

                if !context.state.lastResponse.isEmpty {
                    Text(context.state.lastResponse)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            statusIcon(state: context.state)
                .font(.system(size: 20))
                .foregroundColor(statusColor(state: context.state))
        }
        .padding(16)
        .background(Color(red: 0.04, green: 0.10, blue: 0.15)) // ForIT dark navy
    }

    // MARK: - Helpers

    private func statusIcon(state: GlassesActivityAttributes.ContentState) -> Image {
        if state.isListening { return Image(systemName: "waveform") }
        if state.isSpeaking { return Image(systemName: "speaker.wave.2.fill") }
        if state.isProcessing { return Image(systemName: "brain") }
        if state.isConnected { return Image(systemName: "checkmark.circle.fill") }
        return Image(systemName: "circle")
    }

    private func statusColor(state: GlassesActivityAttributes.ContentState) -> Color {
        if state.isListening { return .cyan }
        if state.isSpeaking { return .cyan }
        if state.isProcessing { return .orange }
        if state.isConnected { return .green }
        return .gray
    }
}
