import Foundation

// MARK: - Gemini Tool Call (parsed from WebSocket JSON)

struct GeminiFunctionCall {
    let id: String
    let name: String
    let args: [String: Any]
}

struct GeminiToolCall {
    let functionCalls: [GeminiFunctionCall]

    init?(json: [String: Any]) {
        guard let toolCall = json["toolCall"] as? [String: Any],
              let calls = toolCall["functionCalls"] as? [[String: Any]] else {
            return nil
        }
        self.functionCalls = calls.compactMap { call in
            guard let id = call["id"] as? String,
                  let name = call["name"] as? String else { return nil }
            let args = call["args"] as? [String: Any] ?? [:]
            return GeminiFunctionCall(id: id, name: name, args: args)
        }
    }
}

// MARK: - Gemini Tool Call Cancellation

struct GeminiToolCallCancellation {
    let ids: [String]

    init?(json: [String: Any]) {
        guard let cancellation = json["toolCallCancellation"] as? [String: Any],
              let ids = cancellation["ids"] as? [String] else {
            return nil
        }
        self.ids = ids
    }
}

// MARK: - Tool Result

enum ToolResult {
    case success(String)
    case failure(String)

    var responseValue: [String: Any] {
        switch self {
        case .success(let result):
            return ["result": result]
        case .failure(let error):
            return ["error": error]
        }
    }
}

// MARK: - Tool Call Status (for UI)

enum ToolCallStatus: Equatable {
    case idle
    case executing(String)
    case completed(String)
    case failed(String, String)
    case cancelled(String)

    var displayText: String {
        switch self {
        case .idle: return ""
        case .executing(let name): return "Running: \(name)..."
        case .completed(let name): return "Done: \(name)"
        case .failed(let name, let err): return "Failed: \(name) — \(err)"
        case .cancelled(let name): return "Cancelled: \(name)"
        }
    }

    var isActive: Bool {
        if case .executing = self { return true }
        return false
    }
}

// MARK: - Tool Declarations

/// Shared tool definitions used by both Gemini Live (WebSocket) and Direct Mode (REST API tool calling).
/// The `execute` tool delegates tasks to the OpenClaw gateway.
enum ToolDeclarations {

    static func allDeclarations() -> [[String: Any]] {
        return [execute]
    }

    /// The single "execute" tool that routes all actions through OpenClaw.
    static let execute: [String: Any] = [
        "name": "execute",
        "description": """
            Your only way to take action. You have no memory, storage, or ability to do anything on your own — \
            use this tool for everything: sending messages, searching the web, adding to lists, setting reminders, \
            creating notes, research, drafts, scheduling, smart home control, app interactions, or any request \
            that goes beyond answering a question. When in doubt, use this tool.
            """,
        "parameters": [
            "type": "object",
            "properties": [
                "task": [
                    "type": "string",
                    "description": "Clear, detailed description of what to do. Include all relevant context: names, content, platforms, quantities, etc."
                ]
            ],
            "required": ["task"]
        ] as [String: Any],
        "behavior": "BLOCKING"
    ]

    // MARK: - Provider-Specific Formats

    /// Anthropic tool format for the Messages API
    static func anthropicTools() -> [[String: Any]] {
        return [[
            "name": "execute",
            "description": execute["description"] as! String,
            "input_schema": [
                "type": "object",
                "properties": [
                    "task": [
                        "type": "string",
                        "description": "Clear, detailed description of what to do. Include all relevant context: names, content, platforms, quantities, etc."
                    ]
                ],
                "required": ["task"]
            ] as [String: Any]
        ]]
    }

    /// OpenAI / Groq / Custom tool format
    static func openAITools() -> [[String: Any]] {
        return [[
            "type": "function",
            "function": [
                "name": "execute",
                "description": execute["description"] as! String,
                "parameters": [
                    "type": "object",
                    "properties": [
                        "task": [
                            "type": "string",
                            "description": "Clear, detailed description of what to do. Include all relevant context: names, content, platforms, quantities, etc."
                        ]
                    ],
                    "required": ["task"]
                ] as [String: Any]
            ] as [String: Any]
        ]]
    }

    /// Gemini REST API tool format
    static func geminiRESTTools() -> [[String: Any]] {
        return [[
            "functionDeclarations": allDeclarations()
        ]]
    }
}
