import Foundation
import ForITCommon
import Security

/// Product credentials obtained by exchanging a verified native identity.
/// The current Entra exchange is provisional pending the central for-Auth contract.
/// The identity token is never persisted. Both app keys belong to this account.
struct ForITAccountSession: Codable, Equatable, Sendable {
    let key: String
    let email: String
    var feedbackKey: String?

    private static let service = "com.forit.openglasses.account"
    private static let account = "session"
    static let store = TasksFeedbackKey.Store.keychain(service: service, account: account)
    static let installationStore = TasksFeedbackKey.Store.keychain(
        service: "com.forit.openglasses.account", account: "installation")
    static let engineOrigin = URL(string: "https://forit-ai-engine.azurewebsites.net")!

    static func load(from store: TasksFeedbackKey.Store = ForITAccountSession.store) -> Self? {
        guard let raw = store.load(),
              let value = try? JSONDecoder().decode(Self.self, from: Data(raw.utf8)),
              !value.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !value.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    func save(to store: TasksFeedbackKey.Store = ForITAccountSession.store) throws {
        let raw = String(decoding: try JSONEncoder().encode(self), as: UTF8.self)
        store.save(raw)
        // The shared store's save has no OSStatus result. Verify before telling the UI.
        guard Self.load(from: store) == self else { throw ForITAccountError.storage }
    }

    static func mintRequest(idToken: String, label: String) throws -> URLRequest {
        struct Body: Encodable { let label: String }
        var request = try ForITKeyMint.request(baseURL: engineOrigin, idToken: idToken,
                                               body: Body(label: label))
        request.timeoutInterval = 30
        return request
    }

    /// Central Auth's one-time code goes only to the existing engine's relying-app route.
    /// PKCE/state validation and browser ownership belong to the shared native Auth client.
    static func appSessionRequest(code: String, codeVerifier: String, nonce: String,
                                  label: String) throws -> URLRequest {
        struct Body: Encodable {
            let app = "openglasses"
            let code: String
            let codeVerifier: String
            let nonce: String
            let label: String
        }
        var request = URLRequest(url: engineOrigin.appendingPathComponent("api/api-keys/app-session"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(code: code, codeVerifier: codeVerifier,
                                                       nonce: nonce, label: label))
        request.timeoutInterval = 30
        return request
    }

    /// The shared store erases Keychain error statuses; sign-out needs checked deletion.
    static func deletePersistedSession() throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ForITAccountError.storage }
    }

    static func decodeMint(_ data: Data, status: Int, expectedEmail: String?) throws -> Self {
        guard (200..<300).contains(status) else {
            if status == 401 || status == 403 { throw ForITAccountError.unauthorized }
            throw ForITAccountError.unavailable
        }
        struct Answer: Decodable { let key: String; let email: String }
        let answer = try ForITKeyMint.decode(Answer.self, from: data, key: \.key)
        let email = answer.email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty,
              expectedEmail.map({ email.caseInsensitiveCompare($0) == .orderedSame }) ?? true else {
            throw ForITAccountError.identityMismatch
        }
        return Self(key: answer.key, email: email, feedbackKey: nil)
    }

    static func mint(idToken: String, email: String?, label: String) async throws -> Self {
        let (data, response) = try await URLSession.shared.data(for: mintRequest(idToken: idToken, label: label))
        return try decodeMint(data, status: (response as? HTTPURLResponse)?.statusCode ?? 0,
                              expectedEmail: email)
    }

    /// Send once. A spent or uncertain code requires a fresh browser sign-in, never a retry.
    static func mintAppSession(code: String, codeVerifier: String, nonce: String,
                               label: String) async throws -> Self {
        let request = try appSessionRequest(code: code, codeVerifier: codeVerifier, nonce: nonce, label: label)
        let transport = URLSession(configuration: .ephemeral, delegate: AppSessionRedirectPolicy(), delegateQueue: nil)
        defer { transport.invalidateAndCancel() }
        let (data, response) = try await transport.data(for: request)
        return try decodeMint(data, status: (response as? HTTPURLResponse)?.statusCode ?? 0,
                              expectedEmail: nil)
    }
}

/// A redirect must never forward a one-time code or PKCE verifier away from the pinned exchange.
final class AppSessionRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum ForITAccountError: LocalizedError {
    case storage, unauthorized, unavailable, identityMismatch

    var errorDescription: String? {
        switch self {
        case .storage: return "Couldn't save your sign-in securely on this iPhone. Try again."
        case .unauthorized: return "This account couldn't sign in to Bernard. Choose your ForIT account and try again."
        case .unavailable: return "Bernard couldn't finish signing you in. Try again."
        case .identityMismatch: return "The sign-in accounts didn't match. Please sign in again."
        }
    }
}
