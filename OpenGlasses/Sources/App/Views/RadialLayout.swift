import SwiftUI

/// The first child is the center; the remaining children orbit it clockwise from the top.
/// Intrinsic measurements own the extent. A narrow offer makes the orbit taller,
/// rather than shrinking shared controls or placing them beyond the horizontal viewport.
struct RadialLayout: Layout {
    struct Arrangement {
        let size: CGSize
        let offsets: [CGPoint]
        let proposals: [ProposedViewSize]
    }

    struct Cache {
        var arrangement: Arrangement?
    }

    private struct Separation {
        let first: Int
        let second: Int
        let horizontal: CGFloat
        let vertical: CGFloat
    }

    private let tolerance: CGFloat = 0.000001

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let result = arrangement(width: proposal.width, subviews: subviews)
        cache.arrangement = result
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let result: Arrangement
        if let measured = cache.arrangement,
           measured.offsets.count == subviews.count,
           measured.size.width <= bounds.width + tolerance,
           measured.size.height <= bounds.height + tolerance {
            result = measured
        } else {
            result = arrangement(width: bounds.width, subviews: subviews)
        }
        for index in subviews.indices {
            subviews[index].place(
                at: CGPoint(x: bounds.midX + result.offsets[index].x,
                            y: bounds.midY + result.offsets[index].y),
                anchor: .center,
                proposal: result.proposals[index]
            )
        }
    }

    private func arrangement(width: CGFloat?, subviews: Subviews) -> Arrangement {
        guard !subviews.isEmpty else {
            return Arrangement(size: .zero, offsets: [], proposals: [])
        }
        let actionCount = subviews.count - 1
        let directions = [CGPoint.zero] + (0..<actionCount).map { index in
            let angle = 2 * Double.pi * Double(index) / Double(actionCount) - Double.pi / 2
            return CGPoint(x: CGFloat(cos(angle)), y: CGFloat(sin(angle)))
        }
        var separations: [Separation] = []
        for first in subviews.indices {
            for second in subviews.indices where second > first {
                separations.append(Separation(
                    first: first, second: second,
                    horizontal: max(0, max(
                        subviews[first].spacing.distance(to: subviews[second].spacing, along: .horizontal),
                        subviews[second].spacing.distance(to: subviews[first].spacing, along: .horizontal))),
                    vertical: max(0, max(
                        subviews[first].spacing.distance(to: subviews[second].spacing, along: .vertical),
                        subviews[second].spacing.distance(to: subviews[first].spacing, along: .vertical)))
                ))
            }
        }
        let horizontalGap = separations.map(\.horizontal).max() ?? 0
        let hasSameRowActions = separations.contains { pair in
            pair.first > 0 && abs(directions[pair.first].y - directions[pair.second].y) < tolerance
        }
        let columns: CGFloat = hasSameRowActions ? 2 : 1
        let minimumSizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: 0, height: nil)) }
        let minimumActionWidth = minimumSizes.dropFirst().map(\.width).max() ?? 0
        // Below this real intrinsic minimum, fitting the offered width is impossible.
        // Report the minimum honestly; vertical growth cannot separate same-row peers.
        let minimumWidth = max(minimumSizes[0].width,
                               columns * minimumActionWidth + (hasSameRowActions ? horizontalGap : 0))
        let availableWidth = width.flatMap { $0.isFinite ? max(minimumWidth, max(0, $0)) : nil }
        let actionWidth = availableWidth.map { max(0, ($0 - (hasSameRowActions ? horizontalGap : 0)) / columns) }
        let proposals = subviews.indices.map { index in
            ProposedViewSize(width: index == 0 ? availableWidth : actionWidth, height: nil)
        }
        let sizes = subviews.indices.map { subviews[$0].sizeThatFits(proposals[$0]) }

        func required(_ distance: CGFloat, along component: CGFloat) -> CGFloat {
            component > tolerance ? distance / component : .infinity
        }
        func horizontalDistance(_ pair: Separation) -> CGFloat {
            (sizes[pair.first].width + sizes[pair.second].width) / 2 + pair.horizontal
        }
        func verticalDistance(_ pair: Separation) -> CGFloat {
            (sizes[pair.first].height + sizes[pair.second].height) / 2 + pair.vertical
        }
        var radius: CGFloat = 0
        for pair in separations {
            let dx = abs(directions[pair.first].x - directions[pair.second].x)
            let dy = abs(directions[pair.first].y - directions[pair.second].y)
            radius = max(radius, min(required(horizontalDistance(pair), along: dx),
                                     required(verticalDistance(pair), along: dy)))
        }
        var horizontalRadius = radius
        if let availableWidth {
            for index in directions.indices where abs(directions[index].x) > tolerance {
                horizontalRadius = min(horizontalRadius,
                    max(0, (availableWidth - sizes[index].width) / 2) / abs(directions[index].x))
            }
            for pair in separations {
                let dx = abs(directions[pair.first].x - directions[pair.second].x)
                let dy = abs(directions[pair.first].y - directions[pair.second].y)
                if dy < tolerance && dx > tolerance {
                    horizontalRadius = max(horizontalRadius, horizontalDistance(pair) / dx)
                }
            }
        }
        var verticalRadius = radius
        for pair in separations {
            let dx = abs(directions[pair.first].x - directions[pair.second].x)
            let dy = abs(directions[pair.first].y - directions[pair.second].y)
            if horizontalRadius * dx + tolerance < horizontalDistance(pair), dy > tolerance {
                verticalRadius = max(verticalRadius, verticalDistance(pair) / dy)
            }
        }
        let offsets = directions.map { CGPoint(x: $0.x * horizontalRadius, y: $0.y * verticalRadius) }
        let halfWidth = sizes.indices.map { abs(offsets[$0].x) + sizes[$0].width / 2 }.max() ?? 0
        let halfHeight = sizes.indices.map { abs(offsets[$0].y) + sizes[$0].height / 2 }.max() ?? 0
        return Arrangement(size: CGSize(width: halfWidth * 2, height: halfHeight * 2),
                           offsets: offsets, proposals: proposals)
    }
}
