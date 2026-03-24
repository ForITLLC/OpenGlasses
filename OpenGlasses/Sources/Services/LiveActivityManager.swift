import ActivityKit
import Foundation

/// Manages the Glasses Live Activity lifecycle.
/// Start when app is active + glasses connected, update on state changes, end on background.
@MainActor
class LiveActivityManager {
    private var currentActivity: Activity<GlassesActivityAttributes>?

    /// Start a Live Activity (if not already running)
    func start(glassesName: String = "Ray-Ban Meta") {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("[LiveActivity] Activities not enabled")
            return
        }
        guard currentActivity == nil else {
            print("[LiveActivity] Already active")
            return
        }

        let attributes = GlassesActivityAttributes(glassesName: glassesName)
        let initialState = GlassesActivityAttributes.ContentState(
            status: "Ready",
            isConnected: true,
            lastResponse: "",
            isListening: false,
            isSpeaking: false,
            isProcessing: false
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil  // Local updates only
            )
            currentActivity = activity
            print("[LiveActivity] Started: \(activity.id)")
            ErrorReporter.shared.report("LiveActivity started: \(activity.id)", source: "live-activity", level: "info")
        } catch {
            print("[LiveActivity] Failed to start: \(error)")
            ErrorReporter.shared.report("LiveActivity failed to start: \(error)", source: "live-activity", level: "error")
        }
    }

    /// Update the Live Activity with new state
    func update(
        status: String,
        isConnected: Bool,
        lastResponse: String = "",
        isListening: Bool = false,
        isSpeaking: Bool = false,
        isProcessing: Bool = false
    ) {
        guard let activity = currentActivity else { return }

        let state = GlassesActivityAttributes.ContentState(
            status: status,
            isConnected: isConnected,
            lastResponse: String(lastResponse.prefix(80)),
            isListening: isListening,
            isSpeaking: isSpeaking,
            isProcessing: isProcessing
        )

        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    /// End the Live Activity — kills current AND any stale activities
    func end() {
        let finalState = GlassesActivityAttributes.ContentState(
            status: "Disabled",
            isConnected: false,
            lastResponse: "",
            isListening: false,
            isSpeaking: false,
            isProcessing: false
        )

        // End tracked activity
        if let activity = currentActivity {
            Task {
                await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
                print("[LiveActivity] Ended tracked activity")
            }
            currentActivity = nil
        }

        // Also kill any stale activities from previous launches
        Task {
            for activity in Activity<GlassesActivityAttributes>.activities {
                await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
                print("[LiveActivity] Ended stale activity: \(activity.id)")
            }
        }
    }

    var isActive: Bool { currentActivity != nil }
}
