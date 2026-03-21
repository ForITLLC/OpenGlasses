import ActivityKit
import SwiftUI
import WidgetKit

@main
struct GlassesActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        GlassesActivityWidget()
    }
}

struct GlassesActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GlassesActivityAttributes.self) { context in
            // Lock Screen presentation
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    // Left: Glasses icon with status dot
                    ZStack(alignment: .bottomTrailing) {
                        Image(systemName: "eyeglasses")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(.black)
                        Circle()
                            .fill(context.state.isConnected ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                            .offset(x: 2, y: 2)
                    }

                    // Center: Status + response
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.status)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.black)

                        Text(context.state.lastResponse.isEmpty ? "Dolores AI" : context.state.lastResponse)
                            .font(.system(size: 12))
                            .foregroundStyle(.black.opacity(0.6))
                            .lineLimit(1)
                    }

                    Spacer()

                    // Right: Status icon (mic/brain/speaker)
                    Image(systemName: statusIconName(state: context.state))
                        .font(.system(size: 20))
                        .foregroundStyle(statusColor(state: context.state))
                }
            }
            .padding(16)
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(.black)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: "eyeglasses")
                            .font(.system(size: 18))
                            .foregroundStyle(context.state.isConnected ? .green : .gray)
                        Text("Glasses")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: statusIconName(state: context.state))
                        .font(.system(size: 18))
                        .foregroundStyle(statusColor(state: context.state))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.state.status)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                        if !context.state.lastResponse.isEmpty {
                            Text(context.state.lastResponse)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: "eyeglasses")
                    .foregroundStyle(context.state.isConnected ? .green : .gray)
            } compactTrailing: {
                Image(systemName: statusIconName(state: context.state))
                    .foregroundStyle(statusColor(state: context.state))
            } minimal: {
                Image(systemName: statusIconName(state: context.state))
                    .foregroundStyle(statusColor(state: context.state))
            }
        }
    }

    private func statusIconName(state: GlassesActivityAttributes.ContentState) -> String {
        if state.isListening { return "waveform" }
        if state.isSpeaking { return "speaker.wave.2.fill" }
        if state.isProcessing { return "brain" }
        if state.isConnected { return "mic.fill" }
        return "mic.slash"
    }

    private func statusColor(state: GlassesActivityAttributes.ContentState) -> Color {
        if state.isListening { return .cyan }
        if state.isSpeaking { return .cyan }
        if state.isProcessing { return .orange }
        if state.isConnected { return .green }
        return .gray
    }
}
