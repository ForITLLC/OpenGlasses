import Foundation

/// Sends app errors/crashes to the ForIT AI Engine for tracking in App Insights.
/// Fire-and-forget — never blocks the UI.
class ErrorReporter {
    static let shared = ErrorReporter()
    
    private let endpoint = Config.doloresBaseURL.replacingOccurrences(of: "/voice", with: "/log")
    private let apiKey = Config.doloresAPIKey
    
    /// Report an error to the server. Non-blocking.
    func report(_ message: String, source: String = "app", level: String = "error", extra: [String: String] = [:]) {
        var body: [String: Any] = [
            "source": "dolores-ios",
            "component": source,
            "level": level,
            "message": message,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "device": UIDevice.current.name,
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        ]
        if !extra.isEmpty { body["extra"] = extra }
        
        guard let url = URL(string: endpoint) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 10
        
        URLSession.shared.dataTask(with: request) { _, _, error in
            if let error = error {
                NSLog("[ErrorReporter] Failed to send: \(error.localizedDescription)")
            }
        }.resume()
    }
    
    /// Report a crash/exception
    func reportCrash(_ error: Error, source: String = "app") {
        report(error.localizedDescription, source: source, level: "crash")
    }
}

// Import for UIDevice
import UIKit
