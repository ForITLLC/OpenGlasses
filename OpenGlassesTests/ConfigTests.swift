import XCTest
@testable import OpenGlasses

final class ConfigTests: XCTestCase {

    private let testKeys = [
        "wakePhrase",
        "alternativeWakePhrases",
        "customSystemPrompt",
        "elevenLabsAPIKey",
        "elevenLabsVoiceId",
    ]

    override func setUp() {
        super.setUp()
        for key in testKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for key in testKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        super.tearDown()
    }

    // MARK: - Dolores Config (hardcoded)

    func testDoloresAPIKeyIsSet() {
        XCTAssertFalse(Config.doloresAPIKey.isEmpty)
    }

    func testDoloresBaseURLIsValid() {
        XCTAssertTrue(Config.doloresBaseURL.hasPrefix("https://"))
        XCTAssertNotNil(URL(string: Config.doloresBaseURL))
    }

    // MARK: - Wake Word

    func testWakePhraseDefault() {
        XCTAssertEqual(Config.wakePhrase, "hey dolores")
    }

    func testWakePhraseSetAndGet() {
        Config.setWakePhrase("hey jarvis")
        XCTAssertEqual(Config.wakePhrase, "hey jarvis")
    }

    func testDefaultAlternativesForDolores() {
        let alts = Config.defaultAlternativesForPhrase("hey dolores")
        XCTAssertFalse(alts.isEmpty)
        XCTAssertTrue(alts.contains("hey delores"))
    }

    // MARK: - System Prompt

    func testSystemPromptDefault() {
        XCTAssertTrue(Config.systemPrompt.contains("Dolores"))
    }

    func testSystemPromptSetAndGet() {
        Config.setSystemPrompt("Custom prompt")
        XCTAssertEqual(Config.systemPrompt, "Custom prompt")
    }

    func testSystemPromptReset() {
        Config.setSystemPrompt("Custom prompt")
        Config.resetSystemPrompt()
        XCTAssertEqual(Config.systemPrompt, Config.defaultSystemPrompt)
    }

    // MARK: - ElevenLabs

    func testElevenLabsAPIKeyDefault() {
        XCTAssertEqual(Config.elevenLabsAPIKey, "")
    }

    func testElevenLabsAPIKeySetAndGet() {
        Config.setElevenLabsAPIKey("test-key")
        XCTAssertEqual(Config.elevenLabsAPIKey, "test-key")
    }

    func testElevenLabsVoiceIdDefault() {
        XCTAssertEqual(Config.elevenLabsVoiceId, "21m00Tcm4TlvDq8ikWAM")
    }
}
