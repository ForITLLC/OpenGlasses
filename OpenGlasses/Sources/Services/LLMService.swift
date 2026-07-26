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

        let parsed = try Self.parseResponse(data)

        // Shape problems used to be swallowed here. Surface them: a reply whose audio
        // failed to decode produced no voice and no explanation, which is precisely the
        // failure you cannot debug afterwards.
        for warning in parsed.warnings {
            print("⚠️ [Dolores] \(warning)")
        }

        if !parsed.toolsUsed.isEmpty {
            print("🔧 [Dolores] Tools used: \(parsed.toolsUsed.joined(separator: ", "))")
        }

        if let audioData = parsed.audio {
            print("🔊 [Dolores] Server provided TTS audio (\(audioData.count) bytes)")
            self.speechService?.preloadedAudio = audioData
        }

        return parsed.text
    }

    /// Parse a voice-endpoint reply.
    ///
    /// Split out of `sendMessage` so the unhappy paths are reachable from tests without
    /// any network egress — the request itself cannot be exercised in CI, because the
    /// API key falls back to the Secrets.plist that CI writes, so a test that reached
    /// the transport would POST at the production endpoint. A test send is a send.
    ///
    /// An unrecognised shape is never silently dropped: anything we cannot use comes
    /// back in `warnings` for the caller to surface.
    static func parseResponse(_ data: Data) throws -> DoloresResponse {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any] else {
            throw LLMError.invalidResponse("Dolores")
        }
        guard let text = json["response"] as? String else {
            throw LLMError.invalidResponse("Dolores")
        }

        var warnings: [String] = []

        var toolsUsed: [String] = []
        if let raw = json["toolsUsed"] {
            if let list = raw as? [String] {
                toolsUsed = list
            } else {
                warnings.append("toolsUsed present but not [String] (got \(type(of: raw))) — ignored")
            }
        }

        var audio: Data?
        if let raw = json["audio"] {
            if let base64 = raw as? String {
                if let decoded = Data(base64Encoded: base64) {
                    audio = decoded
                } else {
                    warnings.append("audio present but not valid base64 (\(base64.count) chars) — reply will have no voice")
                }
            } else {
                warnings.append("audio present but not a string (got \(type(of: raw))) — reply will have no voice")
            }
        }

        return DoloresResponse(text: text, toolsUsed: toolsUsed, audio: audio, warnings: warnings)
    }

    func clearHistory() { /* server manages history */ }
    func refreshActiveModel() { activeModelName = "Dolores" }
}

// MARK: - Parsed response

/// A parsed voice-endpoint reply, including anything about its shape we could not use.
struct DoloresResponse: Equatable {
    let text: String
    let toolsUsed: [String]
    let audio: Data?
    /// Non-fatal shape problems, in the order encountered. Empty for a clean reply.
    /// These exist so an unusable field is observable rather than invisible.
    let warnings: [String]
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

// MARK: - Tool Call Status (replaces deleted ToolCallModels.swift)

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
