import SwiftUI

/// Custom Layout that arranges subviews in a circle.
/// Uses Apple's Layout protocol for proper sizing and no overlap.
struct RadialLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // Calculate radius to fit all items without overlap
        let radius = min(bounds.width, bounds.height) / 2 * 0.92

        for (index, subview) in subviews.enumerated() {
            let angle = 2 * .pi / Double(subviews.count) * Double(index) - .pi / 2
            let x = cos(angle) * radius + bounds.midX
            let y = sin(angle) * radius + bounds.midY

            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .center,
                proposal: .unspecified
            )
        }
    }
}
