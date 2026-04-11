import Foundation

/// Dolores-only LLM service. All requests go to the ForIT AI Engine voice endpoint.
@MainActor
class LLMService: ObservableObject {
    /// Reference to speech service for passing server-provided audio
    var speechService: TextToSpeechService?
    @Published var isProcessing: Bool = false
    @Published var activeModelName: String = "Dolores"
    @Published var toolCallStatus: ToolCallStatus = .idle

    func sendMessage(_ text: String, locationContext: String? = nil, imageData: Data? = nil) async throws -> String {
        isProcessing = true
        defer { isProcessing = false }

        let apiKey = Config.doloresAPIKey
        guard !apiKey.isEmpty else {
            throw LLMError.missingAPIKey("Dolores API key not configured")
        }

        guard let url = URL(string: Config.doloresBaseURL) else {
            throw LLMError.invalidConfiguration("Invalid Dolores URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = 120

        // Speed mode: "fastest" (Haiku), "fast"/true (Sonnet), false (Opus)
        let speedMode = UserDefaults.standard.string(forKey: "speedMode") ?? "fast"
        let fastValue: Any = speedMode == "opus" ? false : speedMode  // "fastest" or "fast" as string, false for Opus

        var body: [String: Any] = [
            "text": text,
            "fast": fastValue
        ]
        // Include userEmail if set (legacy support), but per-user API keys don't need it
        let email = Config.userEmail
        if !email.isEmpty { body["userEmail"] = email }
        if let imageData = imageData {
            body["imageBase64"] = imageData.base64EncodedString()
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        print("🤖 [Dolores] Sending: \(text.prefix(100))...")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMsg = errorJson["error"] as? String {
                print("❌ Dolores error \(statusCode): \(errorMsg)")
                throw LLMError.apiError(provider: "Dolores", statusCode: statusCode, message: errorMsg)
            }
            throw LLMError.apiError(provider: "Dolores", statusCode: statusCode, message: nil)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseText = json["response"] as? String else {
            throw LLMError.invalidResponse("Dolores")
        }

        let toolsUsed = json["toolsUsed"] as? [String] ?? []
        if !toolsUsed.isEmpty {
            print("🔧 [Dolores] Tools used: \(toolsUsed.joined(separator: ", "))")
        }

        // Check for server-provided TTS audio
        if let audioBase64 = json["audio"] as? String,
           let audioData = Data(base64Encoded: audioBase64) {
            print("🔊 [Dolores] Server provided TTS audio (\(audioData.count) bytes)")
            self.speechService?.preloadedAudio = audioData
        }

        return responseText
    }

    func clearHistory() { /* server manages history */ }
    func refreshActiveModel() { activeModelName = "Dolores" }
}

// MARK: - Errors

enum LLMError: LocalizedError {
    case missingAPIKey(String)
    case invalidConfiguration(String)
    case apiError(provider: String, statusCode: Int, message: String?)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let msg): return msg
        case .invalidConfiguration(let msg): return msg
        case .apiError(let provider, let code, let msg): return "\(provider) error \(code): \(msg ?? "unknown")"
        case .invalidResponse(let provider): return "Invalid response from \(provider)"
        }
    }
}

// MARK: - Tool Call Status (stub — replaces deleted ToolCallModels.swift)

enum ToolCallStatus: Equatable {
    case idle
    case calling(String)
    case completed(String)
    case failed(String)

    var displayText: String {
        switch self {
        case .idle: return ""
        case .calling(let name): return "Running: \(name)..."
        case .completed(let name): return "Done: \(name)"
        case .failed(let name): return "Failed: \(name)"
        }
    }

    var isActive: Bool {
        if case .calling = self { return true }
        return false
    }
}
