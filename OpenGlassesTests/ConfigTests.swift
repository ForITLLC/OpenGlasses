import XCTest
@testable import OpenGlasses

final class ConfigTests: XCTestCase {

    // "wakePhrase" used to be listed here, but Config never reads or writes that key —
    // setWakePhrase() writes "enabledWakePhrases". So the wake-phrase tests were leaking
    // ["hey jarvis"] into the rest of the process, and testWakePhraseDefault passed only
    // because XCTest happens to run it first alphabetically ("Default" < "SetAndGet").
    private let testKeys = [
        "enabledWakePhrases",
        "alternativeWakePhrases",
        "customSystemPrompt",
        "elevenLabsAPIKey",
        "elevenLabsVoiceId",
        "listeningEnabled",
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

    // MARK: - Listening master switch

    /// The switch that decides whether the wake-word listener auto-starts at all.
    /// It is deliberately absent-means-on: a fresh install has never written the key,
    /// and if this regressed to false-by-default the app would ship mute — it would
    /// simply never respond to "hey dolores" and look like a wake-word bug.
    func testListeningIsEnabledByDefaultWhenNeverSet() {
        XCTAssertNil(UserDefaults.standard.object(forKey: "listeningEnabled"),
                     "precondition: the key must be unset for this to test the default")
        XCTAssertTrue(Config.listeningEnabled)
    }

    func testListeningEnabledSetAndGet() {
        Config.setListeningEnabled(false)
        XCTAssertFalse(Config.listeningEnabled)
        Config.setListeningEnabled(true)
        XCTAssertTrue(Config.listeningEnabled)
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
