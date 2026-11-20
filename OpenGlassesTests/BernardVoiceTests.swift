import XCTest
@testable import OpenGlasses

/// Contract fixtures only: no request is sent, no provider is called and no API key is read.
@MainActor
final class BernardVoiceTests: XCTestCase {
    private func json(_ text: String) -> Data { Data(text.utf8) }

    func testCatalogRequestPreservesConfiguredPrefixAndQuery() throws {
        let request = try BernardVoiceCatalog.makeRequest(
            baseURL: "https://engine.example.test/prefix/api/voice/?region=ca&userEmail=old%40example.test",
            apiKey: "fixture-key", userEmail: "user@example.test")
        XCTAssertEqual(request.url?.path, "/prefix/api/voice/voices")
        let query = try XCTUnwrap(URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.filter { $0.name == "region" }.map(\.value), ["ca"])
        XCTAssertEqual(query.filter { $0.name == "userEmail" }.map(\.value), ["user@example.test"])
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Key"), "fixture-key")
        XCTAssertNil(request.httpBody)
    }

    func testCatalogRequestAllowsPerUserKeyWithoutEmail() throws {
        let request = try BernardVoiceCatalog.makeRequest(baseURL: "https://engine.example.test/api/voice",
                                                         apiKey: "dol_fixture", userEmail: "")
        XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Key"), "dol_fixture")
    }

    func testCatalogRequestRejectsMissingKeyAndWrongEndpoint() {
        XCTAssertThrowsError(try BernardVoiceCatalog.makeRequest(baseURL: "https://engine.example.test/api/voice",
                                                                 apiKey: "", userEmail: ""))
        XCTAssertThrowsError(try BernardVoiceCatalog.makeRequest(baseURL: "https://engine.example.test/api/chat",
                                                                 apiKey: "fixture", userEmail: ""))
    }

    func testCatalogDefaultDoesNotHaveToBeAnAvailableExplicitChoice() throws {
        let catalog = try BernardVoiceCatalog.parse(json(#"{"defaultVoiceId":"legacy-default","voices":[{"id":"voice-a","name":"Voice A"}]}"#))
        XCTAssertEqual(catalog.defaultVoiceID, "legacy-default")
        XCTAssertEqual(catalog.voices, [BernardVoice(id: "voice-a", name: "Voice A")])
        XCTAssertTrue(catalog.contains(""), "the empty saved value follows the engine default")
        XCTAssertFalse(catalog.contains("legacy-default"), "do not fabricate membership for an unlisted default")
        XCTAssertFalse(catalog.contains("removed-voice"))
    }

    func testMalformedCatalogsDoNotBecomePartialChoiceLists() {
        for payload in [
            #"{"defaultVoiceId":"default","voices":[{"id":"same","name":"A"},{"id":"same","name":"B"}]}"#,
            #"{"defaultVoiceId":"default","voices":[{"id":"","name":"A"}]}"#,
            #"{"defaultVoiceId":"default","voices":[{"id":"valid","name":" "}]}"#,
            #"{"defaultVoiceId":"","voices":[]}"#,
            #"{"defaultVoiceId":"default","voices":"not a list"}"#
        ] {
            XCTAssertThrowsError(try BernardVoiceCatalog.parse(json(payload)))
        }
    }

    func testRequestIncludesOnlyAnExplicitVoiceChoice() {
        let defaultBody = LLMService.requestBody(text: "Hello", fastValue: "fast", voiceID: "", userEmail: "")
        XCTAssertNil(defaultBody["voiceId"])
        XCTAssertNil(defaultBody["userEmail"])
        let selectedBody = LLMService.requestBody(text: "What is this?", fastValue: false, voiceID: "voice-a",
                                                  userEmail: "user@example.test", imageData: Data("photo".utf8))
        XCTAssertEqual(selectedBody["voiceId"] as? String, "voice-a")
        XCTAssertEqual(selectedBody["text"] as? String, "What is this?")
        XCTAssertEqual(selectedBody["fast"] as? Bool, false)
        XCTAssertEqual(selectedBody["userEmail"] as? String, "user@example.test")
        XCTAssertEqual(selectedBody["imageBase64"] as? String, Data("photo".utf8).base64EncodedString())
    }

    func testSelectedVoiceAudioRequiresThisRepliesMatchingConfirmation() throws {
        let audio = Data("synthetic audio".utf8)
        let response = json(#"{"response":"Hello","audio":"\#(audio.base64EncodedString())","voiceId":"voice-a","effectiveVoiceId":"voice-a"}"#)
        let matching = try LLMService.parseResponse(response, requestedVoiceID: "voice-a")
        XCTAssertEqual(matching.audio, audio)
        XCTAssertTrue(matching.warnings.isEmpty)
        let wrongVoice = try LLMService.parseResponse(response, requestedVoiceID: "voice-b")
        XCTAssertEqual(wrongVoice.text, "Hello")
        XCTAssertNil(wrongVoice.audio)
        XCTAssertTrue(wrongVoice.warnings.contains { $0.contains("not confirmed") })
    }

    func testOldEngineAudioIsRejectedForExplicitChoiceButStillWorksForDefault() throws {
        let audio = Data("synthetic audio".utf8)
        let response = json(#"{"response":"Hello","audio":"\#(audio.base64EncodedString())"}"#)
        let explicit = try LLMService.parseResponse(response, requestedVoiceID: "voice-a")
        XCTAssertNil(explicit.audio)
        XCTAssertEqual(explicit.text, "Hello")
        XCTAssertEqual(explicit.warnings.count, 1)
        let defaultVoice = try LLMService.parseResponse(response)
        XCTAssertEqual(defaultVoice.audio, audio)
        XCTAssertTrue(defaultVoice.warnings.isEmpty)
    }

    func testSelectedConfigurationAloneDoesNotConfirmGeneratedAudio() throws {
        let audio = Data("synthetic audio".utf8).base64EncodedString()
        for fields in [
            #""voiceId":"voice-a""#,
            #""voiceId":"voice-a","effectiveVoiceId":"voice-b""#,
            #""voiceId":"voice-a","effectiveVoiceId":null"#
        ] {
            let response = json(#"{"response":"Hello","audio":"\#(audio)",\#(fields)}"#)
            let parsed = try LLMService.parseResponse(response, requestedVoiceID: "voice-a")
            XCTAssertEqual(parsed.text, "Hello")
            XCTAssertNil(parsed.audio)
            XCTAssertTrue(parsed.warnings.contains { $0.contains("not confirmed") })
        }
    }
}
