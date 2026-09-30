import Foundation

/// Runs AppleScript on one background queue, so the covers never wait on Spotify or Swinsian.
enum AppleScriptRunner {
    static let queue = DispatchQueue(label: "Clutter.AppleScript")

    /// The script's result as a string, or "" (after logging) if it fails.
    static func run(_ source: String) async -> String {
        await run(source) { $0?.stringValue ?? "" }
    }

    /// Hands `parse` the script's result, or nil (after logging) if it fails.
    static func run<Result: Sendable>(_ source: String, parse: @escaping @Sendable (NSAppleEventDescriptor?) -> Result) async -> Result {
        await withCheckedContinuation { continuation in
            queue.async {
                var error: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                if let error {
                    NSLog("Clutter: AppleScript failed: %@", error)
                }
                continuation.resume(returning: parse(error == nil ? result : nil))
            }
        }
    }
}

enum AppleScriptText {
    /// `text` as an AppleScript string literal.
    static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
