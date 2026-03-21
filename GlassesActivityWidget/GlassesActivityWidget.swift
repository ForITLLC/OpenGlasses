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
            // Lock Screen banner — the rectangle widget on the Lock Screen
            HStack(spacing: 12) {
                // Glasses icon with connection dot
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: "eyeglasses")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                    Circle()
                        .fill(context.state.isConnected ? Color.green : Color.gray)
                        .frame(width: 10, height: 10)
                        .offset(x: 3, y: 3)
                }
                .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(context.state.status)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)

                    if !context.state.lastResponse.isEmpty {
                        Text(context.state.lastResponse)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(2)
                    }
                }

                Spacer()

                statusIcon(state: context.state)
                    .font(.system(size: 24))
                    .foregroundColor(statusColor(state: context.state))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .activityBackgroundTint(Color(red: 0.08, green: 0.18, blue: 0.26)) // ForIT navy — visible on Lock Screen
            .activitySystemActionForegroundColor(.white)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "eyeglasses")
                        .font(.system(size: 20))
                        .foregroundColor(context.state.isConnected ? .green : .gray)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    statusIcon(state: context.state)
                        .font(.system(size: 20))
                        .foregroundColor(statusColor(state: context.state))
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
                Image(systemName: "eyeglasses")
                    .foregroundColor(context.state.isConnected ? .green : .gray)
                    .font(.system(size: 14))
            } compactTrailing: {
                statusIcon(state: context.state)
                    .foregroundColor(statusColor(state: context.state))
                    .font(.system(size: 14))
            } minimal: {
                Image(systemName: "eyeglasses")
                    .foregroundColor(context.state.isConnected ? .green : .gray)
                    .font(.system(size: 12))
            }
        }
    }

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
