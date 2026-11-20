import Foundation
import UIKit

/// An issued connector credential, held only while its native setup screen is open.
/// Deliberately not Codable: the app never persists or renders the secret.
struct ForITVoiceKey: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    private let value: String
    let email: String
    let label: String
    let expiresAt: Date

    var description: String { "ForITVoiceKey(redacted)" }
    var debugDescription: String { description }

    static func mintRequest(code: String, codeVerifier: String, nonce: String,
                            label: String, expiresInDays: Int = 30) throws -> URLRequest {
        guard (1...90).contains(expiresInDays), !label.isEmpty, label.count <= 64,
              label.utf8.allSatisfy({ (32...126).contains($0) }) else {
            throw ForITAccountError.unavailable
        }
        var request = try ForITAccountSession.appSessionRequest(
            code: code, codeVerifier: codeVerifier, nonce: nonce, label: label)
        guard let data = request.httpBody,
              var body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ForITAccountError.unavailable
        }
        body["scope"] = "voice"
        body["expiresInDays"] = expiresInDays
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func decodeIssued(_ data: Data, status: Int, expectedEmail: String,
                             label: String, expiresInDays: Int = 30, now: Date = Date()) throws -> Self {
        guard status == 201 else {
            if status == 401 || status == 403 { throw ForITAccountError.unauthorized }
            throw ForITAccountError.unavailable
        }
        struct Answer: Decodable {
            let key: String
            let email: String
            let label: String
            let scope: String
            let expiresAt: String
        }
        guard let answer = try? JSONDecoder().decode(Answer.self, from: data),
              answer.scope == "voice", answer.label == label,
              answer.key.count == 37, answer.key.hasPrefix("dols_"),
              answer.key.dropFirst(5).utf8.allSatisfy({
                  (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
              }) else { throw ForITAccountError.unavailable }
        guard !expectedEmail.isEmpty,
              answer.email.caseInsensitiveCompare(expectedEmail) == .orderedSame else {
            throw ForITAccountError.identityMismatch
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = fractional.date(from: answer.expiresAt) ?? ISO8601DateFormatter().date(from: answer.expiresAt)
        guard (1...90).contains(expiresInDays), let expiry = date, expiry > now,
              expiry <= now.addingTimeInterval(Double(expiresInDays) * 86_400 + 60) else {
            throw ForITAccountError.unavailable
        }
        return Self(value: answer.key, email: answer.email, label: answer.label, expiresAt: expiry)
    }

    /// The caller supplies a fresh grant from the shared central-Auth client, never an app key.
    static func mint(code: String, codeVerifier: String, nonce: String, expectedEmail: String,
                     label: String, expiresInDays: Int = 30) async throws -> Self {
        let request = try mintRequest(code: code, codeVerifier: codeVerifier, nonce: nonce,
                                      label: label, expiresInDays: expiresInDays)
        let transport = URLSession(configuration: .ephemeral, delegate: AppSessionRedirectPolicy(), delegateQueue: nil)
        defer { transport.invalidateAndCancel() }
        let (data, response) = try await transport.data(for: request)
        return try decodeIssued(data, status: (response as? HTTPURLResponse)?.statusCode ?? 0,
                                expectedEmail: expectedEmail, label: label, expiresInDays: expiresInDays)
    }

    /// Explicit user action only. Keep it off Universal Clipboard and expire it after one minute.
    @MainActor
    func copyToPasteboard(_ pasteboard: UIPasteboard? = nil, now: Date = Date()) throws -> Int {
        guard expiresAt > now else { throw ForITAccountError.unauthorized }
        let target = pasteboard ?? .general
        target.setItems([["public.utf8-plain-text": value]],
                        options: [.localOnly: true, .expirationDate: now.addingTimeInterval(60)])
        return target.changeCount
    }

    /// On close/sign-out, clear only our own unchanged clipboard entry, never somebody's newer copy.
    @MainActor
    static func clearCopiedValue(changeCount: Int, pasteboard: UIPasteboard? = nil) {
        let target = pasteboard ?? .general
        guard target.changeCount == changeCount else { return }
        target.items = []
    }

    /// Self-revocation cannot remove the phone key or another scoped credential.
    func revokeRequest() -> URLRequest {
        var request = URLRequest(url: ForITAccountSession.engineOrigin.appendingPathComponent("api/api-keys/revoke"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(value, forHTTPHeaderField: "X-API-Key")
        return request
    }
}
