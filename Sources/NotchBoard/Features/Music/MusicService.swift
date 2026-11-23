import AppKit
import Observation
import NotchBoardCore

/// Apple Music now-playing and transport, through AppleScript.
/// Never launches Music on its own: scripts only run while it is open.
@MainActor @Observable
final class MusicService {
    enum Status: Equatable {
        /// Nothing known yet: the first refresh has not finished.
        case checking
        /// macOS or Music has not answered for a few seconds.
        case waiting
        case notRunning
        case ready
        /// macOS has not been asked yet, or the prompt is still open.
        case needsPermission
        /// The user said no; only System Settings can change it.
        case notAuthorized
        case failed(String)
    }

    static let bundleID = "com.apple.Music"

    private(set) var status: Status = .checking
    /// False for `--snapshot`, which must not put macOS prompts on screen.
    var promptsAllowed = true
    private(set) var nowPlaying: NowPlaying?
    private(set) var artwork: NSImage?
    /// Poll every second while the panel is open, every five otherwise.
    var fastPolling = false

    var isPlaying: Bool { status == .ready && nowPlaying?.state == .playing }
    var hasTrack: Bool { status == .ready && (nowPlaying.map { $0.state != .stopped } ?? false) }
    /// For the Settings row: false while permission is missing or unconfirmed.
    var automationLooksAllowed: Bool {
        switch status {
        case .ready, .notRunning, .failed: return true
        case .checking, .waiting, .needsPermission, .notAuthorized: return false
        }
    }

    private let runner = AppleScriptRunner()
    private var artworkKey: String?
    private var loop: Task<Void, Never>?
    private var observer: NSObjectProtocol?
    /// Skips the permission check once macOS has said yes.
    private var permissionGranted = false
    private var didAutoPrompt = false
    private var promptInFlight = false
    private var refreshing = false
    /// False once the no-prompt permission check has failed to answer.
    private var precheckUsable = true

    func start() {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.Music.playerInfo"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.refresh() }
            }
        }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: .seconds(self.fastPolling ? 1 : 5))
            }
        }
    }

    private var isMusicRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
    }

    func refresh() async {
        guard isMusicRunning else { clear(.notRunning); return }
        // One refresh at a time: a call that is stuck must not queue more behind it.
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        // The permission check and the script can both block (an open macOS
        // prompt, a locked screen, a busy Music). After 3 s, say so on the
        // card instead of leaving whatever was there before.
        let watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !Task.isCancelled else { return }
            self.clear(.waiting)
        }
        defer { watchdog.cancel() }
        // Ask macOS first, without prompting. A script sent before consent
        // blocks behind the prompt and would leave a stale state on the card.
        if !permissionGranted {
            if precheckUsable {
                let permission = await runner.permission(for: Self.bundleID, timeout: 2)
                if ProcessInfo.processInfo.environment["NOTCHBOARD_DEBUG"] != nil {
                    FileHandle.standardError.write(Data("Music automation permission: \(permission.map { "\($0)" } ?? "no answer in 2 s")\n".utf8))
                }
                switch permission {
                case .granted?:
                    permissionGranted = true
                case .denied?:
                    clear(.notAuthorized)
                    return
                case .needsConsent?:
                    clear(.needsPermission)
                    if promptsAllowed, !didAutoPrompt { requestPermission() }
                    return
                case .appNotRunning?:
                    clear(.notRunning)
                    return
                case .unknown?, nil:
                    // No usable answer. Stop asking for this launch and let
                    // the script find out, as it did before this check existed.
                    precheckUsable = false
                }
            }
            // Without a yes from macOS the script could show a prompt, and a
            // snapshot run must not.
            if !permissionGranted, !promptsAllowed {
                clear(.waiting)
                return
            }
        }
        let result = await runner.run(MusicScript.state)
        watchdog.cancel()  // artwork loading below may take longer; that is fine
        switch result {
        case .success(.string(let output)):
            guard let parsed = MusicScript.parseState(output) else {
                clear(.failed("Unexpected reply from Music"))
                return
            }
            permissionGranted = true  // Music answered, so macOS allows it
            status = .ready
            nowPlaying = parsed
            if parsed.state == .stopped {
                artwork = nil
                artworkKey = nil
            } else if parsed.trackKey != artworkKey {
                artworkKey = parsed.trackKey
                await loadArtwork(for: parsed.trackKey)
            }
        case .success:
            clear(.failed("Empty reply from Music"))
        case .failure(let error):
            if error.isNotAuthorized {
                permissionGranted = false
                clear(.notAuthorized)
            }
            else if error.isAppGone { clear(.notRunning) }
            // Same state the watchdog set at 3 s, so the card text stays put.
            else if error.isTimeout { clear(.waiting) }
            else {
                // Short fixed text in the UI; script detail only in debug logs.
                if ProcessInfo.processInfo.environment["NOTCHBOARD_DEBUG"] != nil {
                    FileHandle.standardError.write(Data("Music script error \(error.code): \(error.message)\n".utf8))
                }
                clear(.failed("Couldn't read Music right now."))
            }
        }
    }

    private func loadArtwork(for key: String) async {
        let result = await runner.run(MusicScript.artwork, wantsData: true)
        guard key == artworkKey else { return }  // track changed meanwhile
        if case .success(.data(let data)) = result, let image = NSImage(data: data) {
            artwork = image
        } else {
            artwork = nil
        }
    }

    /// Sends one Apple event so macOS shows its "control Music" prompt.
    /// Runs once on its own at launch; the card's Allow button calls it again.
    func requestPermission() {
        didAutoPrompt = true
        guard isMusicRunning, !promptInFlight else { return }
        promptInFlight = true
        Task {
            _ = await runner.run(MusicScript.state)
            promptInFlight = false
            await refresh()
        }
    }

    private func clear(_ newStatus: Status) {
        status = newStatus
        nowPlaying = nil
        artwork = nil
        artworkKey = nil
    }

    // MARK: Transport

    func playPause() { send(MusicScript.playPause) }
    func next() { send(MusicScript.next) }
    func previous() { send(MusicScript.previous) }

    private func send(_ script: String) {
        guard isMusicRunning else { return }
        Task {
            _ = await runner.run(script)
            await refresh()
        }
    }

    func openMusic() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
