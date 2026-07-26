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
/// not help. What catches that class is the DEMOTION RULE below.
///
/// # The disambiguation rule
///
/// A phrase match makes a command a CANDIDATE, not a decision. A candidate is demoted to
/// `.message` — sent to the assistant as ordinary speech — when either rule fires:
///
/// **Rule A — interrogative frame.** The utterance opens with a question lead-in about
/// method or cause (`interrogativeLeadIns`) and the command phrase begins at or after the
/// end of that lead-in. "how do i take a photo with these glasses" is a question about the
/// camera, not an instruction to fire it. Applies to `.photo` and `.goodbye`.
///
/// **Rule B — non-final close.** A sign-off must END the utterance: every token after the
/// matched phrase must come from `closeTrailerWords`. "that's all i wanted to ask about the
/// weather" keeps going after "that's all", so it is speech about a topic, not a sign-off.
/// Applies to `.goodbye` only — `.photo` and `.stop` take legitimate trailing objects
/// ("take a picture of the sunset").
///
/// **Neither rule applies to `.stop`.** Tightening `.stop` trades a false positive for a
/// false negative, and the false negative there means the user cannot interrupt the
/// assistant mid-sentence. That is the more dangerous direction, so `.stop` stays greedy.
///
/// A demoted candidate is removed from consideration and routing falls to the next
/// candidate in priority order; if none survive, the utterance goes to the assistant. Every
/// demotion emits a warning naming the rule that fired.
///
/// The rule is stated in terms of utterance SHAPE — where the match sits relative to the
/// start and the end — so it predicts utterances that appear in no test corpus. It is
/// deliberately not a list of blocked strings.
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

    // MARK: - Rule A vocabulary

    /// Question lead-ins that reframe a following command phrase as a TOPIC rather than a
    /// request. Matched only as a prefix of the whole utterance.
    ///
    /// `"can you"`, `"could you"` and `"please"` are DELIBERATELY ABSENT. They are polite
    /// imperatives, not questions about method: "can you take a picture" means take one.
    /// Listing them here would turn the politest phrasing of a genuine command into a
    /// no-op, which is the false-negative direction this rule must not drift into.
    static let interrogativeLeadIns = ["how do i", "how do you", "how does", "how can i",
                                       "how would i", "is there a way to", "what happens if",
                                       "what happens when", "why does", "why do i"]

    // MARK: - Rule B vocabulary

    /// Words a genuine sign-off may trail without ceasing to be a sign-off. Closed set, and
    /// closed on purpose: anything outside it means the user kept talking, which is what
    /// distinguishes "okay goodbye then" from "that's all i wanted to ask about the weather".
    static let closeTrailerWords: Set<String> = ["then", "now", "please", "bye", "goodbye",
                                                 "thanks", "thank", "you", "dolores", "claude"]

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

        var matched: [Candidate] = []
        if let m = longestMatch(spoken, stopPhrases) { matched.append(Candidate(.stop, m)) }
        if let m = longestMatch(spoken, goodbyePhrases) { matched.append(Candidate(.goodbye, m)) }
        if let m = longestMatch(spoken, photoPhrases) { matched.append(Candidate(.photo, m)) }

        var warnings: [String] = []

        // A phrase match is a candidate, not a decision. Demoted candidates drop out and
        // routing falls through to the next in priority order.
        var surviving: [Candidate] = []
        for candidate in matched {
            if let reason = demotionReason(candidate, spoken) {
                warnings.append(reason)
            } else {
                surviving.append(candidate)
            }
        }

        guard let winner = surviving.first else {
            return VoiceCommandDecision(command: .message, warnings: warnings)
        }

        if surviving.count > 1 {
            let losers = surviving.dropFirst().map { $0.command.rawValue }.joined(separator: ", ")
            warnings.append("ambiguous utterance matched \(surviving.count) command classes — ran '\(winner.command.rawValue)', discarded [\(losers)]")
        }

        let discarded = spoken.count - winner.tokens
        if discarded >= discardWarningThreshold {
            warnings.append("'\(winner.command.rawValue)' consumed the utterance and discarded \(discarded) further spoken word(s) — the rest of what was said never reached the assistant")
        }

        return VoiceCommandDecision(command: winner.command, warnings: warnings)
    }

    /// A matched command phrase and WHERE it sat in the utterance. Position is what both
    /// demotion rules are written in terms of, so the match cannot be reduced to a length.
    private struct Candidate {
        let command: VoiceCommand
        let start: Int
        let tokens: Int
        var end: Int { start + tokens }

        init(_ command: VoiceCommand, _ match: (start: Int, tokens: Int)) {
            self.command = command
            self.start = match.start
            self.tokens = match.tokens
        }
    }

    /// Start index and token count of the longest phrase in `phrases` appearing as a
    /// whole-token run in `spoken`, or nil when none match. Longest wins so "good bye" is
    /// not scored as "bye"; ties resolve to the earliest occurrence.
    private static func longestMatch(_ spoken: [Substring],
                                    _ phrases: [String]) -> (start: Int, tokens: Int)? {
        var best: (start: Int, tokens: Int)?
        for phrase in phrases {
            let needle = WakeWordService.tokenize(phrase)
            guard let start = firstIndex(of: needle, in: spoken) else { continue }
            if best == nil || needle.count > best!.tokens { best = (start, needle.count) }
        }
        return best
    }

    /// Index of the first whole-token occurrence of `needle` in `haystack`.
    ///
    /// `WakeWordService.tokens(_:containSequence:)` answers only yes/no. Rather than keep a
    /// second copy of the scan, this is the one place that needs the position, and the
    /// boolean helper stays the shared predicate everywhere else.
    private static func firstIndex(of needle: [Substring], in haystack: [Substring]) -> Int? {
        guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
        outer: for start in 0...(haystack.count - needle.count) {
            for offset in 0..<needle.count where haystack[start + offset] != needle[offset] {
                continue outer
            }
            return start
        }
        return nil
    }

    // MARK: - Demotion

    /// Why this candidate must NOT execute, or nil if it survives.
    ///
    /// See the type-level documentation for the rule. The warning text names the rule by
    /// letter so a demotion in the field is traceable to the clause that caused it, and
    /// carries counts only — never the spoken words.
    private static func demotionReason(_ candidate: Candidate, _ spoken: [Substring]) -> String? {
        // Rule A and Rule B both trade a false positive for a false negative. On `.stop`
        // that trade means the user cannot interrupt the assistant, so `.stop` is exempt
        // from both.
        guard candidate.command != .stop else { return nil }

        if let leadIn = interrogativeLeadInLength(spoken), candidate.start >= leadIn {
            return "demoted '\(candidate.command.rawValue)' to message — rule A (interrogative frame): utterance opens with a \(leadIn)-word question lead-in and the command phrase begins \(candidate.start - leadIn) word(s) after it, so it was asked ABOUT rather than issued"
        }

        if candidate.command == .goodbye {
            let trailing = spoken[candidate.end...]
            if let firstNonTrailer = trailing.firstIndex(where: { !closeTrailerWords.contains(String($0)) }) {
                return "demoted 'goodbye' to message — rule B (non-final close): \(spoken.count - candidate.end) word(s) follow the sign-off and the one at offset \(firstNonTrailer - candidate.end) is not a closing trailer, so the utterance kept going"
            }
        }

        return nil
    }

    /// Token length of the longest question lead-in that PREFIXES the utterance, or nil.
    private static func interrogativeLeadInLength(_ spoken: [Substring]) -> Int? {
        var best: Int?
        for leadIn in interrogativeLeadIns {
            let needle = WakeWordService.tokenize(leadIn)
            guard spoken.count >= needle.count, Array(spoken.prefix(needle.count)) == needle
            else { continue }
            if best == nil || needle.count > best! { best = needle.count }
        }
        return best
    }

    // MARK: - The capture gate

    /// Whether this decision authorises the glasses camera to fire and write a JPEG.
    ///
    /// `handleTranscription` branches on THIS function, so a test can drive the real gate
    /// instead of a restatement of it. An unintended capture is the one failure class this
    /// product cannot ship with: the camera is on someone's face, and the person in front
    /// of it never agreed to be photographed because they were answering a question about
    /// how the glasses work.
    static func authorisesCapture(_ decision: VoiceCommandDecision) -> Bool {
        decision.command == .photo
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
