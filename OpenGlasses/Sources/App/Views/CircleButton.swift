import ForITCommon
import SwiftUI

/// Microphone action using the shared icon control's target and interaction states.
struct CircleButton: View {
    let icon: String
    let actionLabel: String
    let status: String
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(actionLabel, systemImage: icon)
        }
        .buttonStyle(.forITIcon(isSelected: isActive, on: .navy))
        .accessibilityValue(status)
    }
}
