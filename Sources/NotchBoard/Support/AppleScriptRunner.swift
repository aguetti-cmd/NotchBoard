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
        /// errAETimeout: the target app did not answer in time.
        var isTimeout: Bool { code == -1712 }
    }

    /// Whether macOS lets this app send Apple events to another app.
    enum Permission: Sendable, Equatable {
        case granted
        case denied
        /// Not decided yet: the next Apple event would show the macOS prompt.
        case needsConsent
        case appNotRunning
        case unknown(Int)
    }

    private let queue = DispatchQueue(label: "notchboard.applescript", qos: .userInitiated)
    /// Separate from `queue`, so a script waiting on the consent prompt
    /// cannot hold up the permission check.
    private let permissionQueue = DispatchQueue(label: "notchboard.automation-permission", qos: .userInitiated)
    private var compiled: [String: NSAppleScript] = [:]

    /// Reads the Automation permission for `bundleID` without showing a prompt.
    /// Returns nil when macOS has not answered within `timeout` seconds: the
    /// call has been seen to block for 20 s and more (Music, locked screen),
    /// so callers must not depend on it answering.
    func permission(for bundleID: String, timeout: TimeInterval) async -> Permission? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Permission?, Never>) in
            let once = OnceFlag()
            permissionQueue.async {
                let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
                let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false)
                let permission: Permission
                switch Int(status) {
                case 0: permission = .granted
                case -1743: permission = .denied          // errAEEventNotPermitted
                case -1744: permission = .needsConsent    // errAEEventWouldRequireUserConsent
                case -600: permission = .appNotRunning    // procNotFound
                default: permission = .unknown(Int(status))
                }
                if once.claim() { continuation.resume(returning: permission) }
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) {
                if once.claim() { continuation.resume(returning: nil) }
            }
        }
    }

    /// Lets exactly one of two racing callbacks resume a continuation.
    private final class OnceFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false

        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if claimed { return false }
            claimed = true
            return true
        }
    }

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
