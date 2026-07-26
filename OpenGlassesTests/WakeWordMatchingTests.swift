import XCTest
@testable import OpenGlasses

/// Wake-phrase matching is the product's front door: if it regresses, Dolores simply
/// never wakes, and nothing else in the suite would notice. `containsWakePhrase` and
/// `containsStopPhrase` are pure string functions over `Config`, so they are testable
/// on a simulator with no microphone, no speech permission and no glasses.
///
/// Both read live `Config` state (UserDefaults), so every test pins the phrase lists
/// explicitly and restores them afterwards.
@MainActor
final class WakeWordMatchingTests: XCTestCase {

    private static let enabledKey = "enabledWakePhrases"
    private static let alternativesKey = "alternativeWakePhrases"

    /// Runs `body` with the wake-phrase config pinned, then restores whatever was there.
    private func withPhrases(enabled: [String],
                             alternatives: [String]?,
                             _ body: (WakeWordService) -> Void) {
        let defaults = UserDefaults.standard
        let savedEnabled = defaults.stringArray(forKey: Self.enabledKey)
        let savedAlternatives = defaults.stringArray(forKey: Self.alternativesKey)
        defer {
            if let savedEnabled { defaults.set(savedEnabled, forKey: Self.enabledKey) }
            else { defaults.removeObject(forKey: Self.enabledKey) }
            if let savedAlternatives { defaults.set(savedAlternatives, forKey: Self.alternativesKey) }
            else { defaults.removeObject(forKey: Self.alternativesKey) }
        }

        Config.setEnabledWakePhrases(enabled)
        if let alternatives {
            Config.setAlternativeWakePhrases(alternatives)
        } else {
            defaults.removeObject(forKey: Self.alternativesKey)
        }
        body(WakeWordService())
    }

    /// The default shipping configuration: "hey dolores" plus its generated misrecognitions.
    private func withDefaultPhrases(_ body: (WakeWordService) -> Void) {
        withPhrases(enabled: ["hey dolores"], alternatives: nil, body)
    }

    // MARK: - Wake phrase

    func testMatchesPrimaryWakePhrase() {
        withDefaultPhrases { service in
            XCTAssertTrue(service.containsWakePhrase("hey dolores what time is it"))
        }
    }

    /// Speech recognition rarely hands over a transcript that starts cleanly at the
    /// wake word — it usually carries leading chatter.
    func testMatchesWakePhraseMidTranscript() {
        withDefaultPhrases { service in
            XCTAssertTrue(service.containsWakePhrase("um okay hey dolores turn the lights on"))
        }
    }

    /// The whole point of the alternatives list: "dolores" is routinely misheard.
    func testMatchesKnownMisrecognition() {
        withDefaultPhrases { service in
            XCTAssertTrue(service.containsWakePhrase("hey delores are you there"))
        }
    }

    func testDoesNotWakeOnUnrelatedSpeech() {
        withDefaultPhrases { service in
            XCTAssertFalse(service.containsWakePhrase("what time is the flight to montreal"))
        }
    }

    /// Documents a real precondition rather than a preference: matching is plain
    /// substring comparison against lowercased phrase lists, so an un-lowercased
    /// transcript silently never matches. The recognition handler lowercases before
    /// calling in; anything new that calls this must do the same.
    func testMatchingRequiresALowercasedTranscript() {
        withDefaultPhrases { service in
            XCTAssertFalse(service.containsWakePhrase("HEY DOLORES"),
                           "callers must lowercase the transcript before matching")
        }
    }

    func testRespectsAReconfiguredWakePhrase() {
        withPhrases(enabled: ["hey jarvis"], alternatives: ["hey jarvas"]) { service in
            XCTAssertTrue(service.containsWakePhrase("hey jarvis play music"))
            XCTAssertTrue(service.containsWakePhrase("hey jarvas play music"))
            XCTAssertFalse(service.containsWakePhrase("hey dolores play music"))
        }
    }

    // MARK: - Stop phrase (barge-in)

    func testStopMatchesBareStop() {
        withDefaultPhrases { service in
            XCTAssertTrue(service.containsStopPhrase("stop"))
        }
    }

    func testStopMatchesWakeWordQualifiedStop() {
        withDefaultPhrases { service in
            XCTAssertTrue(service.containsStopPhrase("hey dolores stop"))
        }
    }

    /// This used to be a characterization test asserting the OPPOSITE — that "it
    /// stopped working yesterday" fired the stop command, because `containsStopPhrase`
    /// substring-matched "stop". WO#816 ruled that a defect rather than a product
    /// decision, so the expectation is inverted here rather than the test weakened.
    ///
    /// Full two-directional corpus (false positives AND genuine-stop recall across
    /// realistic ASR shapes) plus the latency measurement live in
    /// StopPhraseMatchingTests. This one case stays here so the inversion is visible
    /// in the file that originally pinned the bug.
    func testStopDoesNotFireOnWordsMerelyContainingStop() {
        withDefaultPhrases { service in
            XCTAssertFalse(service.containsStopPhrase("it stopped working yesterday"),
                           "word-boundary matching — see StopPhraseMatchingTests")
        }
    }

    func testStopDoesNotFireOnOrdinarySpeech() {
        withDefaultPhrases { service in
            XCTAssertFalse(service.containsStopPhrase("what is the weather tomorrow"))
        }
    }
}
