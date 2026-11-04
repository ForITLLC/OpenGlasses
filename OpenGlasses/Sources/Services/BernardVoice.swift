import Foundation

/// Voices are supplied by Bernard's engine, rather than a second provider list in the app.
struct BernardVoice: Equatable, Identifiable {
    let id: String
    let name: String
}

struct BernardVoiceCatalog: Equatable {
    let voices: [BernardVoice]
    let defaultVoiceID: String

    /// Keep an unavailable saved choice visible. Opening Settings must never replace it
    /// with another voice, or make a failed catalogue request look like a successful save.
    func contains(_ voiceID: String) -> Bool {
        voiceID.isEmpty || voices.contains { $0.id == voiceID }
    }

    var defaultVoiceName: String {
        voices.first { $0.id == defaultVoiceID }?.name ?? "Bernard's default"
    }

    @MainActor
    static func load() async throws -> BernardVoiceCatalog {
        let request = try makeRequest(baseURL: Config.doloresBaseURL,
                                      apiKey: Config.doloresAPIKey, userEmail: Config.userEmail)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw BernardVoiceError.invalidResponse }
        switch response.statusCode {
        case 200: return try parse(data)
        case 401: throw BernardVoiceError.unauthorized
        case 403: throw BernardVoiceError.forbidden
        default: throw BernardVoiceError.unavailable
        }
    }

    /// Pure request construction keeps tests away from the live voice endpoint and its keys.
    static func makeRequest(baseURL: String, apiKey: String, userEmail: String) throws -> URLRequest {
        guard !apiKey.isEmpty else { throw BernardVoiceError.missingAPIKey }
        guard var components = URLComponents(string: baseURL),
              ["https", "http"].contains(components.scheme?.lowercased() ?? ""),
              components.host != nil else { throw BernardVoiceError.invalidURL }
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        guard path.hasSuffix("/voice") else { throw BernardVoiceError.invalidURL }
        components.path = path + "/voices"
        var query = components.queryItems ?? []
        query.removeAll { $0.name == "userEmail" }
        if !userEmail.isEmpty { query.append(URLQueryItem(name: "userEmail", value: userEmail)) }
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw BernardVoiceError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        return request
    }

    static func parse(_ data: Data) throws -> BernardVoiceCatalog {
        struct Payload: Decodable {
            struct Voice: Decodable { let id: String; let name: String }
            let defaultVoiceId: String
            let voices: [Voice]
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              !payload.defaultVoiceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              payload.voices.allSatisfy({ !$0.id.isEmpty && $0.id == $0.id.trimmingCharacters(in: .whitespacesAndNewlines)
                  && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              Set(payload.voices.map(\.id)).count == payload.voices.count else {
            throw BernardVoiceError.invalidResponse
        }
        return BernardVoiceCatalog(voices: payload.voices.map { BernardVoice(id: $0.id, name: $0.name) },
                                   defaultVoiceID: payload.defaultVoiceId)
    }
}

enum BernardVoiceError: LocalizedError {
    case missingAPIKey, invalidURL, invalidResponse, unauthorized, forbidden, unavailable

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Add your Bernard API key to load voices."
        case .invalidURL: return "Bernard's address could not be used to load voices."
        case .invalidResponse: return "Bernard returned an unreadable voice list. Your saved choice is unchanged."
        case .unauthorized: return "Your Bernard API key wasn't accepted. Check it and try again."
        case .forbidden: return "This account cannot load Bernard's voices."
        case .unavailable: return "Bernard's voices couldn't be loaded. Your saved choice is unchanged."
        }
    }
}
