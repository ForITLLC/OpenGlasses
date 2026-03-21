import SwiftUI

/// A translucent glass-morphism circular button. OpenGlasses' own take — no VisionClaw clones.
struct CircleButton: View {
    let icon: String
    var size: CGFloat = 52
    var isActive: Bool = false
    var isDisabled: Bool = false
    var badge: String? = nil
    let action: () -> Void

    private var foreground: Color {
        if isDisabled { return Color(hex: "E1EFF3").opacity(0.25) }
        if isActive { return Color(hex: "8EDCEF") }
        return Color(hex: "E1EFF3").opacity(0.85)
    }

    private var background: some ShapeStyle {
        if isActive {
            return AnyShapeStyle(Color(hex: "142F43").opacity(0.6))
        }
        return AnyShapeStyle(Color(hex: "142F43").opacity(0.6))
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color(hex: "142F43").opacity(0.6))
                    .overlay(
                        Circle()
                            .fill(isActive ? Color(hex: "8EDCEF").opacity(0.25) : Color.clear)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(
                                isActive ? Color(hex: "8EDCEF").opacity(0.6) : Color(hex: "E1EFF3").opacity(0.12),
                                lineWidth: 1
                            )
                    )

                Image(systemName: icon)
                    .font(.system(size: size * 0.36, weight: .medium))
                    .foregroundColor(foreground)

                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color(hex: "E1EFF3"))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color(hex: "8EDCEF"), in: Capsule())
                        .offset(x: size * 0.3, y: -size * 0.3)
                }
            }
            .frame(width: size, height: size)
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
    }
}
