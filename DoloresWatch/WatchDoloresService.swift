import Foundation
import WatchKit

class WatchDoloresService {
    static let shared = WatchDoloresService()

    private let baseURL = "https://forit-ai-engine.azurewebsites.net/api/voice"
    private let apiKey: String = {
        // Try UserDefaults first (set via Watch app or synced from phone)
        if let key = UserDefaults.standard.string(forKey: "doloresAPIKey"), !key.isEmpty {
            return key
        }
        // Fall back to Secrets.plist
        if let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path),
           let key = dict["DOLORES_API_KEY"] as? String {
            return key
        }
        return ""
    }()

    func send(_ text: String, imageBase64: String? = nil) async throws -> String {
        guard !apiKey.isEmpty else { throw URLError(.userAuthenticationRequired) }
        guard let url = URL(string: baseURL) else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = 120

        // No userEmail needed — engine looks up user from API key
        var body: [String: Any] = ["text": text, "fast": true]
        if let img = imageBase64 { body["imageBase64"] = img }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = json["response"] as? String else {
            throw URLError(.cannotParseResponse)
        }
        return response
    }
}
