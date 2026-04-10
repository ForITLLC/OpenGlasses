import Foundation
import WatchKit

class WatchDoloresService {
    static let shared = WatchDoloresService()

    private let baseURL = "https://forit-ai-engine.azurewebsites.net/api/voice"
    private let apiKey: String = {
        if let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path),
           let key = dict["DOLORES_API_KEY"] as? String {
            return key
        }
        return ""
    }()

    func send(_ text: String, imageBase64: String? = nil) async throws -> String {
        guard let url = URL(string: baseURL) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = 120

        let email = UserDefaults.standard.string(forKey: "userEmail") ?? ""
        guard !email.isEmpty else { throw URLError(.userAuthenticationRequired) }
        var body: [String: Any] = ["text": text, "userEmail": email, "fast": true]
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
