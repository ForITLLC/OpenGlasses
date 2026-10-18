#if DEBUG && LIVE_ACTIVITY_FIXTURE_HOST
import ActivityKit

/// Opt-in preparation for a minimal local fixture host with the real extension
/// embedded. No app entry point or automatic launch hook is supplied here.
/// Compile only in a separately authorized fixture host, never the shipping app.
@MainActor
final class GlassesActivityFixtureSession {
    private var activity: Activity<GlassesActivityAttributes>?

    /// Call while the fixture host is foreground. Caller handles disabled
    /// activities/request errors as blocked evidence rather than a visual PASS.
    func show(_ fixture: GlassesActivityFixtures.Fixture) async throws {
        let content = ActivityContent(state: fixture.state, staleDate: nil)
        if let activity {
            await activity.update(content)
        } else {
            activity = try Activity.request(
                attributes: GlassesActivityFixtures.attributes,
                content: content,
                pushType: nil
            )
        }
    }

    /// Ends only this fixture session's activity; never enumerates/ends others.
    func end() async {
        guard let activity else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        self.activity = nil
    }
}
#endif
