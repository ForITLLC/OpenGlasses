import ActivityKit
import Foundation

/// Shared model for the Glasses Live Activity.
/// Static attributes set once when the activity starts.
/// ContentState updates dynamically as state changes.
struct GlassesActivityAttributes: ActivityAttributes {
    /// Static data — set when activity starts
    var glassesName: String

    /// Dynamic state — updated on each state change
    struct ContentState: Codable, Hashable {
        var status: String          // "Ready", "Listening...", "Speaking...", "Thinking..."
        var isConnected: Bool
        var lastResponse: String    // Truncated snippet of last AI response
        var isListening: Bool
        var isSpeaking: Bool
        var isProcessing: Bool
    }
}
