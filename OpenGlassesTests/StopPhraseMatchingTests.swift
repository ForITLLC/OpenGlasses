import XCTest
@testable import OpenGlasses

/// Barge-in: while Dolores is speaking, the recogniser keeps listening so the user can
/// cut her off. `containsStopPhrase` is that trigger.
///
/// It used to be `transcript.contains("stop")`, so "it stopped working yesterday" cut
/// her off mid-sentence. WO#816 ruled that a defect rather than a design position and
/// it now matches on word boundaries.
///
/// Tightening a predicate moves risk from false-positive to false-negative, and the
/// false negative is the dangerous direction: the user says "stop" and the assistant
/// keeps talking over them. A corpus containing only the bug would prove only that the
/// bug is fixed and nothing at all about recall — so both directions are measured here,
/// and the recall cases cover the shapes ASR actually emits (no punctuation, trailing
/// punctuation, joined words, partial hypotheses).
///
/// Every string below is synthesised. No audio or transcript of a real person's speech
/// is captured, stored or transmitted by these tests.
@MainActor
final class StopPhraseMatchingTests: XCTestCase {

    // MARK: - Corpora

    /// MUST NOT fire. The first four are the cases named in WO#816.
    private static let falsePositiveCorpus = [
        "it stopped working yesterday",
        "nonstop",
        "stops",
        "unstoppable",
        "the flight is nonstop to boston",
        "it stopped raining about an hour ago",
        "i keep stopping and starting the download",
        "she stopped by the office earlier",
        "what is the weather tomorrow",
        "please st",                       // partial hypothesis — not yet a stop
    ]

    /// MUST fire. Realistic ASR shapes for a genuine stop command.
    private static let genuineStopCorpus = [
        "stop",                            // bare
        "stop.",                           // trailing punctuation
        "stop,",
        "stop!",
        "stop it",
        "stopit",                          // ASR ran the words together, no space
        "please stop",
        "okay stop",
        "stop now",
        "stop talking",
        "stop stop",
        "hey dolores stop",                // wake-word qualified
        "dolores stop",
        "no wait stop i changed my mind",  // mid-utterance
    ]

    // MARK: - Harness

    /// Pins the wake phrase so `allStopPhrases` is deterministic, then restores it.
    private func withService(_ body: (WakeWordService) -> Void) {
        let defaults = UserDefaults.standard
        let saved = defaults.stringArray(forKey: "enabledWakePhrases")
        defer {
            if let saved { defaults.set(saved, forKey: "enabledWakePhrases") }
            else { defaults.removeObject(forKey: "enabledWakePhrases") }
        }
        Config.setEnabledWakePhrases(["hey dolores"])
        body(WakeWordService())
    }

    /// The predicate exactly as it shipped before WO#816, kept only as the latency
    /// baseline and as proof the corpus really can produce the old false positives.
    private func legacySubstringPredicate(_ transcript: String, phrases: [String]) -> Bool {
        for phrase in phrases where transcript.contains(phrase) { return true }
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "stop" || trimmed.hasSuffix(" stop")
    }

    // MARK: - False positives (the bug WO#816 ruled on)

    func testDoesNotFireOnWordsMerelyContainingStop() {
        withService { service in
            for transcript in Self.falsePositiveCorpus {
                XCTAssertFalse(service.containsStopPhrase(transcript),
                               "must NOT cut the assistant off on: '\(transcript)'")
            }
        }
    }

    /// Positive control for the corpus itself. An empty false-positive count from a set
    /// that cannot produce a true positive carries zero information — so prove the old
    /// predicate really did fire on these strings. If this ever fails, the corpus has
    /// stopped exercising the bug and the test above proves nothing.
    func testFalsePositiveCorpusActuallyReproducedTheOldBug() {
        withService { service in
            let phrases = service.allStopPhrases
            let firedUnderOldPredicate = Self.falsePositiveCorpus.filter {
                legacySubstringPredicate($0, phrases: phrases)
            }
            XCTAssertEqual(firedUnderOldPredicate.count, 8,
                           "expected the old substring predicate to fire on 8 of these; got \(firedUnderOldPredicate)")
        }
    }

    // MARK: - Recall (the dangerous direction)

    func testFiresOnEveryGenuineStopShape() {
        withService { service in
            for transcript in Self.genuineStopCorpus {
                XCTAssertTrue(service.containsStopPhrase(transcript),
                              "must stop the assistant on: '\(transcript)'")
            }
        }
    }

    /// Recall must not have dropped relative to the predicate being replaced.
    func testRecallIsNoWorseThanTheOldPredicate() {
        withService { service in
            let phrases = service.allStopPhrases
            for transcript in Self.genuineStopCorpus where legacySubstringPredicate(transcript, phrases: phrases) {
                XCTAssertTrue(service.containsStopPhrase(transcript),
                              "regression: old predicate caught '\(transcript)', new one does not")
            }
        }
    }

    /// The word-join allowance is a closed list on purpose. If it ever admits an
    /// inflectional suffix, the original bug is back.
    func testWordJoinAllowanceDoesNotAdmitInflections() {
        withService { service in
            XCTAssertTrue(service.containsStopPhrase("stopit"))
            XCTAssertFalse(service.containsStopPhrase("stopped"))
            XCTAssertFalse(service.containsStopPhrase("stopping"))
            XCTAssertFalse(service.containsStopPhrase("stoppable"))
        }
    }

    /// Same precondition as wake-phrase matching: the caller lowercases.
    func testMatchingRequiresALowercasedTranscript() {
        withService { service in
            XCTAssertFalse(service.containsStopPhrase("STOP"),
                           "callers must lowercase the transcript before matching")
        }
    }

    // MARK: - Latency

    /// WO#816 G2: "word-boundary matching vs responsive barge-in" is an empirical claim,
    /// not a trade-off to be asserted. Measure it.
    ///
    /// Method: monotonic clock (`DispatchTime.uptimeNanoseconds`), both predicates run
    /// over the SAME 24-string corpus, same iteration count, after a warm-up pass to
    /// discount first-call costs. Both predicates re-read `allStopPhrases` per call
    /// (a UserDefaults hit), so the comparison is apples-to-apples. Reported as
    /// microseconds per call; the raw numbers are printed for the record.
    ///
    /// The assertion is a deliberately generous absolute ceiling rather than a tight
    /// delta — a wall-clock ratio would be flaky on shared CI hardware, and the number
    /// that actually matters is whether this is perceptible inside a speech pipeline
    /// measured in hundreds of milliseconds.
    func testBargeInLatencyIsImperceptible() {
        withService { service in
            let corpus = Self.falsePositiveCorpus + Self.genuineStopCorpus
            let phrases = service.allStopPhrases
            let iterations = 500

            // Warm-up — exercise both paths so neither pays first-call costs in the timed run.
            for transcript in corpus {
                _ = legacySubstringPredicate(transcript, phrases: phrases)
                _ = service.containsStopPhrase(transcript)
            }

            let legacyStart = DispatchTime.now().uptimeNanoseconds
            for _ in 0..<iterations {
                for transcript in corpus { _ = legacySubstringPredicate(transcript, phrases: service.allStopPhrases) }
            }
            let legacyNs = DispatchTime.now().uptimeNanoseconds - legacyStart

            let newStart = DispatchTime.now().uptimeNanoseconds
            for _ in 0..<iterations {
                for transcript in corpus { _ = service.containsStopPhrase(transcript) }
            }
            let newNs = DispatchTime.now().uptimeNanoseconds - newStart

            let calls = Double(iterations * corpus.count)
            let legacyUs = Double(legacyNs) / calls / 1000.0
            let newUs = Double(newNs) / calls / 1000.0

            print(String(format:
                "BARGE-IN-LATENCY legacy_substring=%.3fus/call new_word_boundary=%.3fus/call delta=%+.3fus/call corpus=%d iterations=%d calls=%.0f",
                legacyUs, newUs, newUs - legacyUs, corpus.count, iterations, calls))

            XCTAssertLessThan(newUs, 1000.0,
                              "a barge-in check costing >1ms would be perceptible against the speech pipeline")
        }
    }
}
