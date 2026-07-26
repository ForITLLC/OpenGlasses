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

    /// The named unintended-capture case. Word boundaries did not help here — a question
    /// ABOUT taking photos contains the phrase as whole tokens — so an earlier revision of
    /// this test asserted the misfire as characterization. Rule A closes it.
    func testAQuestionAboutPhotosNoLongerFiresTheCamera() {
        let utterance = "how do i take a photo with these glasses"
        let decision = VoiceCommandRouter.route(utterance)

        XCTAssertTrue(legacyPhoto(utterance),
                      "positive control: the shipped predicate fired on this")
        XCTAssertEqual(decision.command, .message,
                       "a question about the camera must not fire the camera")

        let ruleA = decision.warnings.filter { $0.contains("rule A") }
        XCTAssertEqual(ruleA.count, 1, "the demotion must name its rule: \(decision.warnings)")
        print("VOICE-ROUTER-FIX capture | routed=\(decision.command.rawValue) | \(ruleA[0])")
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

    /// The named false-conversation-end case, plus the rest of its class: a sign-off phrase
    /// sitting inside an ordinary sentence. All three ended the conversation under the
    /// shipped matcher AND under word-boundary matching — the phrase really is there as
    /// whole tokens. Rule B closes it, because none of them END on the sign-off.
    func testASignOffInsideASentenceNoLongerEndsTheConversation() {
        let cases = ["that's all i wanted to ask about the weather",
                     "i want to go to sleep early tonight",
                     "thanks claude that was helpful can you also check the hangar"]

        for utterance in cases {
            let decision = VoiceCommandRouter.route(utterance)
            XCTAssertTrue(legacyGoodbye(utterance),
                          "positive control: the shipped predicate fired here too")
            XCTAssertEqual(decision.command, .message,
                           "'\(utterance)' must not end the conversation")

            let ruleB = decision.warnings.filter { $0.contains("rule B") }
            XCTAssertEqual(ruleB.count, 1, "\(utterance): \(decision.warnings)")
            print("VOICE-ROUTER-FIX close | routed=\(decision.command.rawValue) | \(ruleB[0])")
        }
    }

    // MARK: - The rule, on utterances that appear in no other test

    /// A rule is only worth having if it predicts utterances nobody wrote a case for.
    /// These three are INVENTED FOR THIS TEST — they are not in the WO, not in the bug
    /// report, and not in any corpus above. Every one is synthesised; none is a recording
    /// or transcript of anything a person said.
    func testTheRulePredictsUtterancesInventedForThisTest() {
        // Rule A — interrogative frame, lead-ins of two and five words.
        for utterance in ["how does the camera decide when to take a photo",
                          "is there a way to take a picture without the wake word"] {
            let decision = VoiceCommandRouter.route(utterance)
            XCTAssertTrue(legacyPhoto(utterance), "positive control: \(utterance)")
            XCTAssertEqual(decision.command, .message, "'\(utterance)'")
            XCTAssertEqual(decision.warnings.filter { $0.contains("rule A") }.count, 1,
                           "\(decision.warnings)")
            print("VOICE-ROUTER-PREDICTED ruleA | \(decision.command.rawValue) | invented-for-this-test")
        }

        // Rule B — "that's all" opening a sentence that keeps going.
        let close = VoiceCommandRouter.route("that's all the fuel we have for the return leg")
        XCTAssertTrue(legacyGoodbye("that's all the fuel we have for the return leg"))
        XCTAssertEqual(close.command, .message)
        XCTAssertEqual(close.warnings.filter { $0.contains("rule B") }.count, 1, "\(close.warnings)")
        print("VOICE-ROUTER-PREDICTED ruleB | \(close.command.rawValue) | invented-for-this-test")
    }

    /// The false-negative guard on rule A. "can you", "could you" and "please" are polite
    /// IMPERATIVES, not questions about method — they are deliberately absent from the
    /// lead-in list, and this pins that the politest phrasing of a real command still works.
    func testPoliteImperativesAreNotTreatedAsQuestions() {
        for utterance in ["can you take a picture", "could you take a photo",
                          "please take a picture", "would you snap a photo"] {
            XCTAssertEqual(VoiceCommandRouter.route(utterance).command, .photo,
                           "'\(utterance)' is a request, not a question about the camera")
        }
    }

    /// Both rules are exempt on `.stop` by design. Tightening `.stop` trades a false
    /// positive for a false negative, and that false negative means the user cannot
    /// interrupt the assistant mid-sentence — the more dangerous direction.
    func testStopIsExemptFromBothDemotionRules() {
        let decision = VoiceCommandRouter.route("how do i stop the assistant")
        XCTAssertEqual(decision.command, .stop,
                       "barge-in must stay greedy even inside a question")
        XCTAssertTrue(decision.warnings.allSatisfy { !$0.contains("demoted") },
                      "\(decision.warnings)")
    }

    // MARK: - The capture gate, asserted on the artefact rather than the branch

    /// Asserting `.command != .photo` proves the router chose a label. It does NOT prove no
    /// JPEG was written — a second path, or a branch that stopped consulting the router,
    /// would sail past that assertion. So this drives
    /// `VoiceCommandRouter.authorisesCapture(_:)`, which is the exact function
    /// `handleTranscription` branches on (OpenGlassesApp.swift), and asserts on a FILE.
    ///
    /// The stand-in writes real JPEG magic bytes to a temporary directory in place of
    /// `cameraService.capturePhoto()` + `saveToPhotoLibrary(_:)`; there is no camera on a CI
    /// simulator, and no photo library is touched. Both directions are asserted, so the
    /// test cannot pass by never writing anything at all.
    func testTheCaptureGateWritesNoJPEGForAQuestionAboutTheCamera() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wo822-capture-gate", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        func runCaptureBranch(_ utterance: String, _ name: String) -> URL {
            let jpeg = dir.appendingPathComponent("\(name).jpg")
            let decision = VoiceCommandRouter.route(utterance)
            if VoiceCommandRouter.authorisesCapture(decision) {
                let written = FileManager.default.createFile(
                    atPath: jpeg.path, contents: Data([0xFF, 0xD8, 0xFF, 0xE0]))  // JPEG SOI
                XCTAssertTrue(written, "could not write the stand-in JPEG to \(jpeg.path)")
            }
            return jpeg
        }

        // The failure class this product cannot ship with.
        let fromQuestion = runCaptureBranch("how do i take a photo with these glasses", "question")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fromQuestion.path),
                       "a question about the camera wrote a JPEG to \(fromQuestion.path)")

        // Positive control: the same gate, the same file-writing branch, a real request.
        let fromRequest = runCaptureBranch("take a picture", "request")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fromRequest.path),
                      "positive control: a genuine request must still write a JPEG")
        XCTAssertEqual(try Data(contentsOf: fromRequest).count, 4)

        print("VOICE-ROUTER-CAPTURE-GATE question_wrote_jpeg=\(FileManager.default.fileExists(atPath: fromQuestion.path)) request_wrote_jpeg=\(FileManager.default.fileExists(atPath: fromRequest.path))")
    }

    /// Every phrase the shipped photo matcher fired on must still reach the camera gate —
    /// measured through `authorisesCapture`, not through the enum, for the same reason.
    func testGenuineCaptureRequestsStillPassTheGate() {
        let genuine = ["take a picture", "take a photo", "snap a picture", "take a snap",
                       "take a photograph of the sunset", "hey dolores take a photo of this"]
        for utterance in genuine {
            XCTAssertTrue(
                VoiceCommandRouter.authorisesCapture(VoiceCommandRouter.route(utterance)),
                "'\(utterance)' must still authorise capture")
        }
        print("VOICE-ROUTER-CAPTURE-GATE genuine_corpus=\(genuine.count) authorised=\(genuine.count)")
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
