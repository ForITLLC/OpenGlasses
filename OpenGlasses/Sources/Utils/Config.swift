import Foundation

/// App configuration — Dolores-only, no multi-model support.
struct Config {

    // MARK: - Dolores API

    /// API key for the ForIT AI Engine voice endpoint.
    /// Priority: UserDefaults (Settings) > Secrets.plist (build-time)
    static var doloresAPIKey: String {
        // User-configured key takes priority (for multi-user support)
        if let userKey = UserDefaults.standard.string(forKey: "doloresAPIKey"), !userKey.isEmpty {
            return userKey
        }
        // Fall back to Secrets.plist
        guard let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path),
              let key = dict["DOLORES_API_KEY"] as? String, !key.isEmpty else {
            return ""
        }
        return key
    }

    static func setAPIKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: "doloresAPIKey")
    }

    /// User email for the ForIT AI Engine (identifies the user)
    static var userEmail: String {
        UserDefaults.standard.string(forKey: "userEmail") ?? "b.thomas@forit.io"
    }

    static func setUserEmail(_ email: String) {
        UserDefaults.standard.set(email, forKey: "userEmail")
    }

    /// Base URL for the ForIT AI Engine voice endpoint
    static var doloresBaseURL: String {
        UserDefaults.standard.string(forKey: "doloresBaseURL") ?? "https://forit-ai-engine.azurewebsites.net/api/voice"
    }

    // MARK: - Wake Word

    /// The primary wake word phrase (user-configurable)
    static var wakePhrase: String {
        if let phrase = UserDefaults.standard.string(forKey: "wakePhrase"), !phrase.isEmpty {
            return phrase.lowercased()
        }
        return "hey dolores"
    }

    static func setWakePhrase(_ phrase: String) {
        UserDefaults.standard.set(phrase.lowercased(), forKey: "wakePhrase")
    }

    /// Alternative spellings / misrecognitions of the wake phrase
    static var alternativeWakePhrases: [String] {
        if let alts = UserDefaults.standard.stringArray(forKey: "alternativeWakePhrases"), !alts.isEmpty {
            return alts.map { $0.lowercased() }
        }
        return Self.defaultAlternativesForPhrase(wakePhrase)
    }

    static func setAlternativeWakePhrases(_ phrases: [String]) {
        UserDefaults.standard.set(phrases.map { $0.lowercased() }, forKey: "alternativeWakePhrases")
    }

    /// Default alternative spellings for common wake phrases
    static func defaultAlternativesForPhrase(_ phrase: String) -> [String] {
        switch phrase.lowercased() {
        case "hey dolores":
            return ["hey dolorus", "hey delores", "hey dolorus", "hey de lores", "hey the lores"]
        case "hey claude":
            return ["hey cloud", "hey claud", "hey clod", "hey clawed", "hey claudia"]
        case "hey jarvis":
            return ["hey jarvas", "hey jarvus", "hey service"]
        case "hey computer":
            return ["hey compuder", "a computer"]
        case "hey assistant":
            return ["hey assistance", "a assistant"]
        case "hey rayban":
            return ["hey ray ban", "hey ray-ban", "hey raven", "hey rayben", "hey ray band"]
        default:
            return []
        }
    }

    // MARK: - Custom System Prompt

    static let defaultSystemPrompt = """
    You are a voice assistant running on Ray-Ban Meta smart glasses. Your responses will be spoken aloud via text-to-speech.

    RESPONSE STYLE:
    - Keep responses CONCISE but COMPLETE — typically 2-4 sentences, longer for complex topics.
    - Be conversational and natural, like talking to a knowledgeable friend.
    - Never use markdown, bullet points, numbered lists, or special formatting.
    - If you're uncertain, use natural hedges like "probably", "likely", or "roughly" rather than stating guesses as facts.
    - If you genuinely can't answer (e.g., real-time data, personal info you don't have), say so briefly and suggest what the user could do instead.

    CONTEXT:
    - The user is wearing smart glasses and talking to you hands-free while going about their day.
    - Speech recognition may mishear words — interpret the user's intent generously.
    - You have conversational memory within this session, so you can reference previous exchanges.
    - For very complex questions, offer to break the topic into parts: "That's a big topic. Would you like me to start with X?"

    KNOWLEDGE:
    - Answer confidently from your training knowledge for factual questions.
    - Give direct recommendations when asked for opinions.
    - If the user's location is provided, use it for locally relevant answers (nearby places, directions, local knowledge). Only mention the location if it's directly relevant to the question.

    BREVITY GUIDELINES:
    - Simple facts: 1-2 sentences ("Paris is the capital of France, located in northern France along the Seine River.")
    - Explanations: 3-4 sentences (e.g., "how does X work?")
    - Complex topics: 4-6 sentences, offer to continue (e.g., "Want me to explain more about Y?")
    - Directions/instructions: As many steps as needed, but keep each step concise.
    """

    static var systemPrompt: String {
        if let prompt = UserDefaults.standard.string(forKey: "customSystemPrompt"), !prompt.isEmpty {
            return prompt
        }
        return defaultSystemPrompt
    }

    static func setSystemPrompt(_ prompt: String) {
        UserDefaults.standard.set(prompt, forKey: "customSystemPrompt")
    }

    static func resetSystemPrompt() {
        UserDefaults.standard.removeObject(forKey: "customSystemPrompt")
    }

    // MARK: - ElevenLabs TTS

    /// ElevenLabs API key for natural TTS voices
    static var elevenLabsAPIKey: String {
        if let key = UserDefaults.standard.string(forKey: "elevenLabsAPIKey"), !key.isEmpty {
            return key
        }
        return ""
    }

    static func setElevenLabsAPIKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: "elevenLabsAPIKey")
    }

    /// ElevenLabs voice ID - default is "Rachel" (warm, conversational female voice)
    static var elevenLabsVoiceId: String {
        if let voiceId = UserDefaults.standard.string(forKey: "elevenLabsVoiceId"), !voiceId.isEmpty {
            return voiceId
        }
        return "21m00Tcm4TlvDq8ikWAM"  // Rachel
    }

    static func setElevenLabsVoiceId(_ voiceId: String) {
        UserDefaults.standard.set(voiceId, forKey: "elevenLabsVoiceId")
    }
}
