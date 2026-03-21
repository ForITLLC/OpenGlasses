import SwiftUI

/// Minimal connection status — top-left pill only.
/// Shows "Connected" (green) or "Disconnected" (gray) with a Connect button when needed.
/// NO camera button, NO redundant controls.
struct ConnectionBanner: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 8) {
            glassesPill
            Spacer()
            if !appState.isConnected {
                connectButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var glassesPill: some View {
        let connected = appState.isConnected

        return HStack(spacing: 5) {
            Circle()
                .fill(connected ? Color.green : Color.gray)
                .frame(width: 7, height: 7)
            Text(connected ? "Connected" : "Disconnected")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(connected ? .green : Color(hex: "E1EFF3").opacity(0.6))
                .lineLimit(1)
        }
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(hex: "142F43").opacity(0.8), in: Capsule())
        .overlay(
            Capsule().strokeBorder(Color(hex: "E1EFF3").opacity(0.08), lineWidth: 0.5)
        )
    }

    private var connectButton: some View {
        Button {
            Task { await appState.glassesService.connect() }
        } label: {
            Text("Connect")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: "0A1A26"))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color(hex: "8EDCEF"), in: Capsule())
        }
    }
}
