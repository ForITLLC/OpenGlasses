import XCTest
@testable import OpenGlasses

/// Every spoken exchange comes back through this parse. A regression here disables the
/// whole product at once, and it fails quietly rather than loudly: the user speaks,
/// nothing happens, and nothing explains why.
///
/// These tests exercise the parse only — never the transport. `Config.doloresAPIKey`
/// falls back to the Secrets.plist that CI writes, so a test that reached the network
/// would POST at the production endpoint. A test send is a send.
@MainActor
final class LLMResponseParsingTests: XCTestCase {

    private func json(_ raw: String) -> Data { Data(raw.utf8) }

    // MARK: - Happy path

    func testParsesPlainReply() throws {
        let parsed = try LLMService.parseResponse(json(#"{"response":"Hello there"}"#))
        XCTAssertEqual(parsed.text, "Hello there")
        XCTAssertEqual(parsed.toolsUsed, [])
        XCTAssertNil(parsed.audio)
        XCTAssertTrue(parsed.warnings.isEmpty, "a clean reply must not warn: \(parsed.warnings)")
    }

    func testParsesToolsUsedAndAudio() throws {
        let payload = Data("tone".utf8).base64EncodedString()
        let parsed = try LLMService.parseResponse(
            json(#"{"response":"Done","toolsUsed":["search","calendar"],"audio":"\#(payload)"}"#))

        XCTAssertEqual(parsed.toolsUsed, ["search", "calendar"])
        XCTAssertEqual(parsed.audio, Data("tone".utf8))
        XCTAssertTrue(parsed.warnings.isEmpty)
    }

    // MARK: - Loud failures

    /// A body that is not JSON at all — e.g. an HTML error page from a proxy.
    func testThrowsOnNonJSONBody() {
        XCTAssertThrowsError(try LLMService.parseResponse(json("<html>502 Bad Gateway</html>"))) { error in
            guard case LLMError.invalidResponse = error else {
                return XCTFail("expected .invalidResponse, got \(error)")
            }
        }
    }

    /// Valid JSON, but not the object shape we require.
    func testThrowsOnJSONThatIsNotAnObject() {
        XCTAssertThrowsError(try LLMService.parseResponse(json("[1,2,3]"))) { error in
            guard case LLMError.invalidResponse = error else {
                return XCTFail("expected .invalidResponse, got \(error)")
            }
        }
    }

    func testThrowsWhenResponseFieldIsMissing() {
        XCTAssertThrowsError(try LLMService.parseResponse(json(#"{"toolsUsed":["search"]}"#))) { error in
            guard case LLMError.invalidResponse = error else {
                return XCTFail("expected .invalidResponse, got \(error)")
            }
        }
    }

    func testThrowsWhenResponseFieldIsWrongType() {
        XCTAssertThrowsError(try LLMService.parseResponse(json(#"{"response":42}"#))) { error in
            guard case LLMError.invalidResponse = error else {
                return XCTFail("expected .invalidResponse, got \(error)")
            }
        }
    }

    // MARK: - Observable, non-fatal shape problems

    /// The reply is still usable, so this must not throw — but it must not vanish either.
    func testUnexpectedToolsUsedShapeWarnsInsteadOfSilentlyDropping() throws {
        let parsed = try LLMService.parseResponse(
            json(#"{"response":"Fine","toolsUsed":[{"name":"search"}]}"#))

        XCTAssertEqual(parsed.text, "Fine", "an unusable field must not cost the user their answer")
        XCTAssertEqual(parsed.toolsUsed, [])
        XCTAssertEqual(parsed.warnings.count, 1)
        XCTAssertTrue(parsed.warnings[0].contains("toolsUsed"),
                      "warning must name the field: \(parsed.warnings)")
    }

    /// The case that produces a silent, undebuggable failure in production: Dolores
    /// answers and the user simply hears nothing back.
    func testUndecodableAudioWarnsInsteadOfSilentlyDropping() throws {
        let parsed = try LLMService.parseResponse(
            json(#"{"response":"Speaking","audio":"!!!not base64!!!"}"#))

        XCTAssertEqual(parsed.text, "Speaking")
        XCTAssertNil(parsed.audio)
        XCTAssertEqual(parsed.warnings.count, 1)
        XCTAssertTrue(parsed.warnings[0].contains("audio"),
                      "warning must name the field: \(parsed.warnings)")
    }

    func testAudioOfWrongTypeWarns() throws {
        let parsed = try LLMService.parseResponse(json(#"{"response":"Speaking","audio":12345}"#))
        XCTAssertNil(parsed.audio)
        XCTAssertEqual(parsed.warnings.count, 1)
        XCTAssertTrue(parsed.warnings[0].contains("audio"))
    }

    /// Both fields malformed at once — every problem is reported, not just the first.
    func testEveryShapeProblemIsReported() throws {
        let parsed = try LLMService.parseResponse(
            json(#"{"response":"Fine","toolsUsed":"search","audio":"!!!"}"#))
        XCTAssertEqual(parsed.warnings.count, 2, "got: \(parsed.warnings)")
    }
}
