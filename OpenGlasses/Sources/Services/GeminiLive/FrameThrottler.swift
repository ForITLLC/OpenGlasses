import Foundation
import UIKit

/// Throttles camera frames to a configurable interval before forwarding.
/// Used in Gemini Live mode to rate-limit video frames sent over the WebSocket (default: 1fps).
class FrameThrottler {
    var onThrottledFrame: ((UIImage) -> Void)?

    private var lastFrameTime: Date = .distantPast
    private let interval: TimeInterval

    /// - Parameter interval: Minimum seconds between forwarded frames (default: from Config).
    init(interval: TimeInterval = Config.geminiLiveVideoFrameInterval) {
        self.interval = interval
    }

    /// Total frames received and forwarded (for diagnostics).
    private(set) var receivedCount: Int = 0
    private(set) var forwardedCount: Int = 0

    /// Call with every camera frame. Only forwards if enough time has passed.
    func submit(_ image: UIImage) {
        receivedCount += 1
        let now = Date()
        guard now.timeIntervalSince(lastFrameTime) >= interval else { return }
        lastFrameTime = now
        forwardedCount += 1
        if forwardedCount <= 3 || forwardedCount % 10 == 0 {
            NSLog("[FrameThrottler] Forwarding frame #%d (received %d total)", forwardedCount, receivedCount)
        }
        onThrottledFrame?(image)
    }

    /// Reset the throttle timer (e.g. on session restart).
    func reset() {
        lastFrameTime = .distantPast
        receivedCount = 0
        forwardedCount = 0
    }
}
