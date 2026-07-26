import Foundation

/// What the app will actually DO with a finished utterance.
enum VoiceCommand: String, Equatable {
    case stop
    case goodbye
    case photo
    case message
}

/// A routing decision, plus anything about the utterance the router could not resolve
/// cleanly.
///
/// `warnings` is the observability contract. This layer executes real actions — it stops
/// speech, it tears down the conversation, it fires the glasses camera and writes a JPEG
/// to the photo library — and it does so BEFORE the assistant is ever consulted. An
/// utterance that lands here in an unexpected shape must leave a trace. The failure mode
/// being made impossible is the undebuggable one: the user speaks, something (or nothing)
/// happens, and no record anywhere explains why.
struct VoiceCommandDecision: Equatable {
    let command: VoiceCommand
    /// Non-fatal shape problems, in the order encountered. Empty for a clean utterance.
    let warnings: [String]
}

/// The client-side voice-command router — the layer that ACTUALLY executes.
///
/// This app has no client-side tool-call dispatch: tool execution is server-side and
/// `ToolCallStatus` is a display enum. What executes locally is this: a transcript is
/// classified and a real action is taken from it. Extracted out of
/// `AppState.handleTranscription` so the decision is reachable from tests without
/// constructing the app's service graph (microphone, speech recognition, glasses session),
/// none of which exist on a CI simulator.
///
/// Matching is on WORD BOUNDARIES via the tokeniser `WakeWordService` already uses, rather
/// than a second copy of the logic. These classifiers previously used
/// `lower.contains(phrase)` — the same defect ruled on for stop phrases — so "say your
/// goodbyes to the crew" ended the conversation, because it contains "goodbye".
///
/// That substring surface is narrower than it is for "stop": few English words embed
/// "bye" or "goodbye". The larger false-positive surface for these classifiers is a
/// command phrase appearing inside an ordinary sentence — "that's all i wanted to ask
/// about the weather" ends the conversation under BOTH matchers, and word boundaries do
/// not help. What catches that class is the discard warning below, not the tokeniser.
@MainActor
enum VoiceCommandRouter {

    // MARK: - Phrase lists

    static let stopPhrases = ["stop", "nevermind", "never mind", "cancel", "shut up",
                              "be quiet", "quiet"]

    static let goodbyePhrases = ["goodbye", "good bye", "bye", "that's all", "thats all",
                                 "thanks claude", "thank you claude", "i'm done", "im done",
                                 "end conversation", "go to sleep"]

    /// The trailing entries exist to preserve recall the old substring match got for free:
    /// `"take a photo"` was a substring of `"take a photograph"`, and `"take picture"` of
    /// `"take pictures"`. Word-boundary matching does not see those, so the inflected forms
    /// are listed explicitly and pinned by a no-worse-than-legacy test.
    static let photoPhrases = ["take a picture", "take a photo", "take photo", "take picture",
                               "capture photo", "snap a photo", "snap a picture", "take a snap",
                               "take a photograph", "take photograph", "take photographs",
                               "take pictures", "take photos", "capture photos",
                               "snap a photograph"]

    /// How many further spoken words a command may consume before the discard is worth
    /// reporting. One trailing word ("stop please") is ordinary; several ("cancel my flight
    /// tomorrow") means the user asked for something that never reached the assistant.
    static let discardWarningThreshold = 2

    // MARK: - Routing

    /// Classify an utterance into the action this layer will take.
    ///
    /// Priority is stop > goodbye > photo > message, which is the branch order in
    /// `handleTranscription`. Priority is preserved deliberately: this extraction is not
    /// the place to change which command wins, only the place to make the choice visible.
    static func route(_ transcript: String) -> VoiceCommandDecision {
        let spoken = WakeWordService.tokenize(transcript.lowercased())

        guard !spoken.isEmpty else {
            // Previously this went to the assistant as an empty message and produced a
            // reply to nothing, with no record that the transcript had been empty.
            return VoiceCommandDecision(
                command: .message,
                warnings: ["empty transcript — no spoken words to route (\(transcript.count) raw characters)"])
        }

        var matched: [(command: VoiceCommand, tokens: Int)] = []
        if let n = longestMatch(spoken, stopPhrases) { matched.append((.stop, n)) }
        if let n = longestMatch(spoken, goodbyePhrases) { matched.append((.goodbye, n)) }
        if let n = longestMatch(spoken, photoPhrases) { matched.append((.photo, n)) }

        guard let winner = matched.first else {
            return VoiceCommandDecision(command: .message, warnings: [])
        }

        var warnings: [String] = []

        if matched.count > 1 {
            let losers = matched.dropFirst().map { $0.command.rawValue }.joined(separator: ", ")
            warnings.append("ambiguous utterance matched \(matched.count) command classes — ran '\(winner.command.rawValue)', discarded [\(losers)]")
        }

        let discarded = spoken.count - winner.tokens
        if discarded >= discardWarningThreshold {
            warnings.append("'\(winner.command.rawValue)' consumed the utterance and discarded \(discarded) further spoken word(s) — the rest of what was said never reached the assistant")
        }

        return VoiceCommandDecision(command: winner.command, warnings: warnings)
    }

    /// Token count of the longest phrase in `phrases` appearing as a whole-token run in
    /// `spoken`, or nil when none match. Longest wins so "good bye" is not scored as "bye".
    private static func longestMatch(_ spoken: [Substring], _ phrases: [String]) -> Int? {
        var best: Int?
        for phrase in phrases {
            let needle = WakeWordService.tokenize(phrase)
            guard WakeWordService.tokens(spoken, containSequence: needle) else { continue }
            if best == nil || needle.count > best! { best = needle.count }
        }
        return best
    }

    // MARK: - Observability

    /// Push a decision's warnings to the app's error surface.
    ///
    /// The warnings carry shapes and counts only — never the utterance text. This surface
    /// POSTs to a server in production, and a transcript is a recording of a person
    /// speaking; it is not going there to make a log line more convenient to read.
    static func reportWarnings(_ decision: VoiceCommandDecision) {
        for warning in decision.warnings {
            print("⚠️ [voice-router] \(warning)")
            ErrorReporter.shared.report(warning, source: "voice-router", level: "warning")
        }
    }
}
