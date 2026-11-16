import Foundation

/// Runs AppleScript on one background queue. NSAppleScript is not thread
/// safe, so every compile and execute happens on that queue.
final class AppleScriptRunner: @unchecked Sendable {
    enum Output: Sendable {
        case string(String)
        case data(Data)
        case none
    }

    struct ScriptError: Error, Sendable {
        let code: Int
        let message: String

        /// errAEEventNotPermitted: the user has not allowed Automation.
        var isNotAuthorized: Bool { code == -1743 }
        /// procNotFound / connectionInvalid: the target app quit.
        var isAppGone: Bool { code == -600 || code == -609 }
    }

    private let queue = DispatchQueue(label: "notchboard.applescript", qos: .userInitiated)
    private var compiled: [String: NSAppleScript] = [:]

    func run(_ source: String, wantsData: Bool = false) async -> Result<Output, ScriptError> {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.execute(source, wantsData: wantsData))
            }
        }
    }

    private func execute(_ source: String, wantsData: Bool) -> Result<Output, ScriptError> {
        let script: NSAppleScript
        if let cached = compiled[source] {
            script = cached
        } else {
            guard let fresh = NSAppleScript(source: source) else {
                return .failure(ScriptError(code: -1, message: "Script could not be created"))
            }
            var compileError: NSDictionary?
            if !fresh.compileAndReturnError(&compileError) {
                return .failure(Self.error(from: compileError))
            }
            compiled[source] = fresh
            script = fresh
        }

        var runError: NSDictionary?
        let descriptor = script.executeAndReturnError(&runError)
        if let runError { return .failure(Self.error(from: runError)) }
        if wantsData {
            let data = descriptor.data
            return .success(data.isEmpty ? .none : .data(data))
        }
        if let string = descriptor.stringValue { return .success(.string(string)) }
        return .success(.none)
    }

    private static func error(from dict: NSDictionary?) -> ScriptError {
        let code = (dict?[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? -1
        let message = dict?[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
        return ScriptError(code: code, message: message)
    }
}
