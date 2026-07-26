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

    /// CHARACTERIZATION, NOT ENDORSEMENT.
    ///
    /// `containsStopPhrase` substring-matches "stop", so any word containing it —
    /// "stopped", "stopping", "unstoppable" — cuts Dolores off mid-sentence during
    /// barge-in listening. This test pins the behaviour as it ships today so the
    /// trade-off is visible and any future change is deliberate.
    ///
    /// Whether to tighten this to word-boundary matching is a product/UX call
    /// (responsive barge-in vs. false cutoffs), not a bug fix — flagged for Ben,
    /// deliberately not changed here.
    func testStopAlsoFiresOnWordsMerelyContainingStop() {
        withDefaultPhrases { service in
            XCTAssertTrue(service.containsStopPhrase("it stopped working yesterday"),
                          "current behaviour: substring match on \"stop\" — see doc comment")
        }
    }

    func testStopDoesNotFireOnOrdinarySpeech() {
        withDefaultPhrases { service in
            XCTAssertFalse(service.containsStopPhrase("what is the weather tomorrow"))
        }
    }
}
