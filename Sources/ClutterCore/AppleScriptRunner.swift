import Foundation

/// Runs AppleScript on one background queue, so the covers never wait on Spotify.
enum AppleScriptRunner {
    static let queue = DispatchQueue(label: "Clutter.AppleScript")

    /// The script's result as a string, or "" (after logging) if it fails.
    static func run(_ source: String) async -> String {
        await withCheckedContinuation { continuation in
            queue.async {
                var error: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                if let error {
                    NSLog("Clutter: AppleScript failed: %@", error)
                }
                continuation.resume(returning: result?.stringValue ?? "")
            }
        }
    }
}
