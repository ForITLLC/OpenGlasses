import SwiftUI
import WatchKit

struct DoloresWatchView: View {
    @State private var lastResponse = "Say \"Hey Dolores\" on your glasses"
    @State private var isProcessing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Avatar + Name
                Image("DoloresAvatar")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())

                Text("Dolores")
                    .font(.headline)
                    .foregroundColor(Color(red: 0.56, green: 0.86, blue: 0.94))

                // Last response
                Text(lastResponse)
                    .font(.caption2)
                    .foregroundColor(Color(red: 0.88, green: 0.94, blue: 0.95))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(red: 0.08, green: 0.18, blue: 0.26).opacity(0.8))
                    .cornerRadius(8)

                if isProcessing {
                    ProgressView()
                        .tint(Color(red: 0.56, green: 0.86, blue: 0.94))
                }

                // Quick Actions
                HStack(spacing: 8) {
                    quickButton(icon: "mic.fill", label: "Ask") {
                        await sendCommand("What is my next meeting?")
                    }
                    quickButton(icon: "camera.fill", label: "Photo") {
                        await sendCommand("take a picture and describe what you see")
                    }
                    quickButton(icon: "checklist", label: "Tasks") {
                        await sendCommand("what are my tasks today?")
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .background(Color(red: 0.04, green: 0.10, blue: 0.15))
    }

    func quickButton(icon: String, label: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(.system(size: 9))
            }
            .foregroundColor(Color(red: 0.56, green: 0.86, blue: 0.94))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color(red: 0.08, green: 0.18, blue: 0.26).opacity(0.6))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    func sendCommand(_ text: String) async {
        isProcessing = true
        WKInterfaceDevice.current().play(.start)
        do {
            let response = try await WatchDoloresService.shared.send(text)
            lastResponse = response
            WKInterfaceDevice.current().play(.success)
        } catch {
            lastResponse = "Error: \(error.localizedDescription)"
            WKInterfaceDevice.current().play(.failure)
        }
        isProcessing = false
    }
}

#Preview {
    DoloresWatchView()
}
