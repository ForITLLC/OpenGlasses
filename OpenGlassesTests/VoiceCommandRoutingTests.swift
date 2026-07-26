import XCTest
@testable import OpenGlasses

/// `VoiceCommandRouter` is the layer that ACTUALLY executes on this client. There is no
/// client-side tool-call dispatch in this app — tool execution is server-side and
/// `ToolCallStatus` is a display enum — so this is where a spoken utterance turns into a
/// real action: speech is cut off, the conversation is torn down, the glasses camera fires
/// and a JPEG is written to the photo library. All of it happens BEFORE the assistant is
/// consulted, from string matching alone.
///
/// The invariant under test: an utterance in an unexpected or ambiguous shape must fail
/// LOUDLY and OBSERVABLY — never be silently swallowed. These tests assert both directions,
/// because a warning nobody can see is the same as no warning: the decision carries the
/// warning, and the warning reaches the app's error surface.
///
/// Every transcript here is synthesised. No recording or transcript of a real person's
/// speech appears in this file.
@MainActor
final class VoiceCommandRoutingTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ErrorReporter.shared.resetTestCapture()
    }

    override func tearDown() {
        ErrorReporter.shared.resetTestCapture()
        super.tearDown()
    }

    // MARK: - Legacy predicates (the shipped behaviour these replace)

    /// `AppState.isGoodbyeCommand` as it stood before this change: `lower.contains(phrase)`
    /// over the same list. Kept so the comparisons below measure against what actually
    /// shipped rather than against a description of it.
    private func legacyGoodbye(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return VoiceCommandRouter.goodbyePhrases.contains(where: { lower.contains($0) })
    }

    private func legacyPhoto(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return ["take a picture", "take a photo", "take photo", "take picture",
                "capture photo", "snap a photo", "snap a picture", "take a snap"]
            .contains(where: { lower.contains($0) })
    }

    // MARK: - Happy path

    /// If the negative cases below passed while the router had simply stopped matching
    /// anything, they would prove nothing. This pins that each command class still fires.
    func testEachCommandClassStillFires() {
        XCTAssertEqual(VoiceCommandRouter.route("stop").command, .stop)
        XCTAssertEqual(VoiceCommandRouter.route("nevermind").command, .stop)
        XCTAssertEqual(VoiceCommandRouter.route("goodbye").command, .goodbye)
        XCTAssertEqual(VoiceCommandRouter.route("go to sleep").command, .goodbye)
        XCTAssertEqual(VoiceCommandRouter.route("take a picture").command, .photo)
        XCTAssertEqual(VoiceCommandRouter.route("snap a photo").command, .photo)
    }

    /// A clean command routes with no warnings at all — the observability contract must
    /// not degrade into noise on every utterance.
    func testCleanCommandsWarnAboutNothing() {
        for utterance in ["stop", "goodbye", "good bye", "take a picture", "be quiet"] {
            let decision = VoiceCommandRouter.route(utterance)
            XCTAssertTrue(decision.warnings.isEmpty,
                          "'\(utterance)' must route cleanly, got: \(decision.warnings)")
        }
    }

    /// Ordinary speech reaches the assistant, silently and correctly.
    func testOrdinarySpeechRoutesToTheAssistant() {
        for utterance in ["what time is the flight to montreal",
                          "remind me to call the hangar in the morning",
                          "how cold is it outside"] {
            let decision = VoiceCommandRouter.route(utterance)
            XCTAssertEqual(decision.command, .message, "'\(utterance)'")
            XCTAssertTrue(decision.warnings.isEmpty, "'\(utterance)': \(decision.warnings)")
        }
    }

    /// ASR emits "stop." and "please stop" — the old prefix/suffix predicate matched
    /// neither, so the user said stop and the assistant kept talking.
    func testStopSurvivesRealisticASRShapes() {
        for utterance in ["stop", "stop.", "stop!", "please stop", "stop it", "okay stop"] {
            XCTAssertEqual(VoiceCommandRouter.route(utterance).command, .stop, "'\(utterance)'")
        }
    }

    // MARK: - Silent swallows, made observable

    /// The empty transcript used to be forwarded to the assistant as an empty message,
    /// producing a reply to nothing with no record that the transcript had been empty.
    func testEmptyTranscriptIsObservableInsteadOfSentAsAnEmptyMessage() {
        for raw in ["", "   ", "\n", "..."] {
            let decision = VoiceCommandRouter.route(raw)
            XCTAssertEqual(decision.command, .message)
            XCTAssertEqual(decision.warnings.count, 1, "raw=\(raw.debugDescription)")
            XCTAssertTrue(decision.warnings[0].contains("empty transcript"),
                          "warning must name the condition: \(decision.warnings)")
            print("VOICE-ROUTER-OBSERVABLE empty | \(decision.warnings[0])")
        }
    }

    /// The case that motivated this work. "cancel" is a stop phrase, so the whole
    /// request is consumed as a barge-in and never reaches the assistant — the user asks
    /// for something and nothing happens. The routing decision is deliberately left
    /// unchanged (which command wins is a product call, not this extraction's to make);
    /// what changes is that the discard is now reported instead of invisible.
    func testACommandThatSwallowsARequestIsObservable() {
        let cases = ["cancel my flight tomorrow", "stop the music", "quiet the alarm in the hangar"]
        for utterance in cases {
            let decision = VoiceCommandRouter.route(utterance)
            XCTAssertEqual(decision.command, .stop, "'\(utterance)'")
            let discard = decision.warnings.filter { $0.contains("discarded") }
            XCTAssertEqual(discard.count, 1,
                           "'\(utterance)' swallowed a request without reporting it: \(decision.warnings)")
            print("VOICE-ROUTER-OBSERVABLE swallow | \(discard[0])")
        }
    }

    /// Word-boundary matching does not help the photo classifier: a question ABOUT taking
    /// photos still contains the phrase as whole tokens, so it still fires the camera and
    /// still writes a JPEG. Asserted as-is rather than quietly "fixed" — the honest state
    /// is that the misfire remains and is now at least reported.
    func testAQuestionAboutPhotosStillFiresTheCameraButIsNowReported() {
        let decision = VoiceCommandRouter.route("how do i take a photo with these glasses")
        XCTAssertEqual(decision.command, .photo, "characterization: this still misfires")
        XCTAssertEqual(decision.warnings.count, 1, "\(decision.warnings)")
        XCTAssertTrue(decision.warnings[0].contains("discarded"))
        print("VOICE-ROUTER-OBSERVABLE photo-misfire | \(decision.warnings[0])")
    }

    /// Two command classes match at once. Branch order silently picked a winner before;
    /// now the loser is named.
    func testAmbiguousUtteranceNamesTheDiscardedCandidates() {
        let decision = VoiceCommandRouter.route("take a picture and then goodbye")
        XCTAssertEqual(decision.command, .goodbye, "priority order must be unchanged")

        let ambiguity = decision.warnings.filter { $0.contains("ambiguous") }
        XCTAssertEqual(ambiguity.count, 1, "\(decision.warnings)")
        XCTAssertTrue(ambiguity[0].contains("photo"),
                      "the warning must name what was dropped: \(ambiguity[0])")
        print("VOICE-ROUTER-OBSERVABLE ambiguous | \(ambiguity[0])")
    }

    // MARK: - The warning must reach the error surface

    /// A warning that stays inside the decision is not observability. This proves the
    /// bridge `handleTranscription` calls actually lands on the app's error surface —
    /// captured rather than POSTed, because `ErrorReporter` returns before building a
    /// request under XCTest. Zero network egress.
    func testWarningsReachTheErrorSurface() {
        let decision = VoiceCommandRouter.route("cancel my flight tomorrow")
        XCTAssertFalse(decision.warnings.isEmpty)

        VoiceCommandRouter.reportWarnings(decision)

        let captured = ErrorReporter.shared.testCapturedReports
        XCTAssertEqual(captured.count, decision.warnings.count,
                       "every warning must reach the error surface: \(captured)")
        for line in captured {
            XCTAssertTrue(line.hasPrefix("[warning] voice-router: "),
                          "wrong level or component: \(line)")
            print("VOICE-ROUTER-REPORTED \(line)")
        }
    }

    func testACleanUtteranceReportsNothing() {
        VoiceCommandRouter.reportWarnings(VoiceCommandRouter.route("stop"))
        XCTAssertTrue(ErrorReporter.shared.testCapturedReports.isEmpty,
                      "clean utterances must not spam the error surface: \(ErrorReporter.shared.testCapturedReports)")
    }

    /// The error surface POSTs to a server in production. A transcript is a recording of
    /// a person speaking, so warnings carry shapes and counts only — never the words.
    func testWarningsNeverCarryTheSpokenWords() {
        let synthetic = "cancel my zblorptrip tomorrow"
        let decision = VoiceCommandRouter.route(synthetic)
        VoiceCommandRouter.reportWarnings(decision)

        for line in ErrorReporter.shared.testCapturedReports {
            XCTAssertFalse(line.contains("zblorptrip"),
                           "spoken words must never reach the error surface: \(line)")
        }
        XCTAssertFalse(ErrorReporter.shared.testCapturedReports.isEmpty,
                       "positive control: something must have been reported")
    }

    // MARK: - Word boundaries (the defect WO#816 ruled on, in its second copy)

    /// Under the shipped `contains` matching, any word embedding a goodbye phrase ended
    /// the conversation.
    ///
    /// This corpus is deliberately narrow, because the substring surface here IS narrow —
    /// an earlier draft of this test claimed "maybe" contains "bye" and the positive
    /// control below caught that it does not (m-a-y-b-e). The control stays for exactly
    /// that reason: it fails if the "defect" being fixed was never real.
    func testGoodbyeNoLongerFiresOnWordsMerelyContainingBye() {
        let falsePositives = ["goodbyes", "say your goodbyes to the crew", "the byes are posted"]

        let legacyFired = falsePositives.filter(legacyGoodbye).count
        XCTAssertEqual(legacyFired, falsePositives.count,
                       "positive control: the shipped predicate fired on all of these")

        for utterance in falsePositives {
            XCTAssertNotEqual(VoiceCommandRouter.route(utterance).command, .goodbye,
                              "'\(utterance)' must not end the conversation")
        }
        print("VOICE-ROUTER-BOUNDARY goodbye false_positives=\(falsePositives.count) legacy_fired=\(legacyFired) new_fired=0")
    }

    /// The bigger false-positive surface, and the one word boundaries do NOT close: a
    /// command phrase sitting inside an ordinary sentence. "that's all i wanted to ask
    /// about the weather" ends the conversation under the shipped matcher AND under this
    /// one — the phrase really is there as whole tokens. Asserted as-is rather than
    /// claimed fixed. What catches it is the discard warning: the classifier consumed a
    /// nine-word question to fire a three-word command.
    func testACommandPhraseInsideASentenceStillFiresButIsNowReported() {
        let cases = ["that's all i wanted to ask about the weather",
                     "i want to go to sleep early tonight",
                     "thanks claude that was helpful can you also check the hangar"]

        for utterance in cases {
            let decision = VoiceCommandRouter.route(utterance)
            XCTAssertEqual(decision.command, .goodbye,
                           "characterization: word boundaries do not fix this class")
            XCTAssertTrue(legacyGoodbye(utterance),
                          "positive control: the shipped predicate fired here too")
            let discard = decision.warnings.filter { $0.contains("discarded") }
            XCTAssertEqual(discard.count, 1, "\(utterance): \(decision.warnings)")
            print("VOICE-ROUTER-OBSERVABLE sentence-swallow | \(discard[0])")
        }
    }

    /// Tightening a predicate moves risk from false-positive to false-negative, and the
    /// false negative is the direction that costs the user a working command. Every shape
    /// the shipped `contains` caught must still be caught.
    func testGoodbyeRecallIsNoWorseThanTheShippedPredicate() {
        let genuine = ["goodbye", "good bye", "bye", "bye bye", "ok bye", "goodbye dolores",
                       "okay goodbye then", "that's all", "thats all", "i'm done", "im done",
                       "end conversation", "go to sleep", "thanks claude", "thank you claude"]

        var regressions: [String] = []
        for utterance in genuine where legacyGoodbye(utterance) {
            if VoiceCommandRouter.route(utterance).command != .goodbye { regressions.append(utterance) }
        }
        XCTAssertEqual(regressions, [], "word boundaries lost genuine goodbyes")
        print("VOICE-ROUTER-RECALL goodbye corpus=\(genuine.count) legacy_fired=\(genuine.filter(legacyGoodbye).count) regressions=\(regressions.count)")
    }

    /// `"take a photo"` was a substring of `"take a photograph"`, so the shipped matcher
    /// got inflections for free. Word boundaries do not — the inflected forms are listed
    /// explicitly, and this pins that none were missed.
    func testPhotoRecallIsNoWorseThanTheShippedPredicate() {
        let genuine = ["take a picture", "take a photo", "take photo", "take picture",
                       "capture photo", "snap a photo", "snap a picture", "take a snap",
                       "take a photograph of the sunset", "take photographs now",
                       "take pictures of this", "take photos", "capture photos of the room",
                       "snap a photograph", "hey dolores take a photo of this"]

        var regressions: [String] = []
        for utterance in genuine where legacyPhoto(utterance) {
            if VoiceCommandRouter.route(utterance).command != .photo { regressions.append(utterance) }
        }
        XCTAssertEqual(regressions, [], "word boundaries lost genuine photo commands")
        print("VOICE-ROUTER-RECALL photo corpus=\(genuine.count) legacy_fired=\(genuine.filter(legacyPhoto).count) regressions=\(regressions.count)")
    }
}
