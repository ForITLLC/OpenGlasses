import XCTest
import UIKit
@testable import OpenGlasses

@MainActor
final class ForITVoiceKeyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let fixtureKey = "dols_" + String(repeating: "a", count: 32)

    private func response(key: String? = nil, scope: String = "voice", email: String = "person@example.test",
                          label: String = "Fixture Muse", expiry: Date? = nil) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "key": key ?? fixtureKey, "scope": scope, "email": email, "label": label,
            "expiresAt": ISO8601DateFormatter().string(from: expiry ?? now.addingTimeInterval(86_400))
        ])
    }

    private func issued() throws -> ForITVoiceKey {
        try ForITVoiceKey.decodeIssued(response(), status: 201, expectedEmail: "person@example.test",
                                       label: "Fixture Muse", now: now)
    }

    func testVoiceMintCannotChangeTheOrdinaryPhoneMint() throws {
        let request = try ForITVoiceKey.mintRequest(code: "fixture-code", codeVerifier: "fixture-verifier",
                                                   nonce: "fixture-nonce", label: "Fixture Muse")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["app"] as? String, "openglasses")
        XCTAssertEqual(body["scope"] as? String, "voice")
        XCTAssertEqual(body["expiresInDays"] as? Int, 30)
        XCTAssertEqual(body["label"] as? String, "Fixture Muse")
        XCTAssertEqual(request.url?.absoluteString, "https://forit-ai-engine.azurewebsites.net/api/api-keys/app-session")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "X-API-Key"))
        let phone = try ForITAccountSession.appSessionRequest(code: "code", codeVerifier: "verifier", nonce: "nonce", label: "Phone")
        let phoneBody = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(phone.httpBody)) as? [String: Any])
        XCTAssertNil(phoneBody["scope"])
        XCTAssertNil(phoneBody["expiresInDays"])
        for days in [0, 91] {
            XCTAssertThrowsError(try ForITVoiceKey.mintRequest(code: "code", codeVerifier: "verifier", nonce: "nonce",
                                                             label: "Fixture Muse", expiresInDays: days))
        }
    }

    func testWrongAuthorityOrLifetimeIsNeverCopiedAsAConnectorCredential() throws {
        let refused = try [response(key: "dol_" + String(repeating: "a", count: 32)),
                           response(scope: "all"), response(email: "other@example.test"), response(label: "Other"),
                           response(expiry: now.addingTimeInterval(-1)),
                           response(expiry: now.addingTimeInterval(91 * 86_400)), response(key: "dols_bad")]
        for data in refused {
            XCTAssertThrowsError(try ForITVoiceKey.decodeIssued(data, status: 201,
                                                               expectedEmail: "person@example.test", label: "Fixture Muse", now: now))
        }
        for status in [200, 400, 401, 502, 503] {
            XCTAssertThrowsError(try ForITVoiceKey.decodeIssued(response(), status: status,
                                                               expectedEmail: "person@example.test", label: "Fixture Muse", now: now))
        }
    }

    func testCredentialDescriptionsDoNotRevealTheValueAndRevokeIsSelfOnly() throws {
        let credential = try issued()
        XCTAssertFalse(String(describing: credential).contains(fixtureKey))
        XCTAssertFalse(String(reflecting: credential).contains(fixtureKey))
        let request = credential.revokeRequest()
        XCTAssertEqual(request.url?.absoluteString, "https://forit-ai-engine.azurewebsites.net/api/api-keys/revoke")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Key"), fixtureKey)
        XCTAssertNil(request.httpBody)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testClosingClearsOnlyOurOwnClipboardValue() throws {
        let pasteboard = UIPasteboard.withUniqueName()
        defer { UIPasteboard.remove(withName: pasteboard.name) }
        let credential = try issued()
        let ownCopy = try credential.copyToPasteboard(pasteboard, now: now)
        XCTAssertEqual(pasteboard.string, fixtureKey)
        ForITVoiceKey.clearCopiedValue(changeCount: ownCopy, pasteboard: pasteboard)
        XCTAssertNil(pasteboard.string)
        let olderCopy = try credential.copyToPasteboard(pasteboard, now: now)
        pasteboard.string = "Something the person copied later"
        ForITVoiceKey.clearCopiedValue(changeCount: olderCopy, pasteboard: pasteboard)
        XCTAssertEqual(pasteboard.string, "Something the person copied later")
        XCTAssertThrowsError(try credential.copyToPasteboard(pasteboard, now: now.addingTimeInterval(2 * 86_400)))
        XCTAssertEqual(pasteboard.string, "Something the person copied later")
    }
}
