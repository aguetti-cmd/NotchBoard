import AppKit
import Observation
import NotchBoardCore

/// Apple Music now-playing and transport, through AppleScript.
/// Never launches Music on its own: scripts only run while it is open.
@MainActor @Observable
final class MusicService {
    enum Status: Equatable {
        case notRunning
        case ready
        case notAuthorized
        case failed(String)
    }

    static let bundleID = "com.apple.Music"

    private(set) var status: Status = .notRunning
    private(set) var nowPlaying: NowPlaying?
    private(set) var artwork: NSImage?
    /// Poll every second while the panel is open, every five otherwise.
    var fastPolling = false

    var isPlaying: Bool { status == .ready && nowPlaying?.state == .playing }
    var hasTrack: Bool { status == .ready && (nowPlaying.map { $0.state != .stopped } ?? false) }

    private let runner = AppleScriptRunner()
    private var artworkKey: String?
    private var loop: Task<Void, Never>?
    private var observer: NSObjectProtocol?

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
        switch await runner.run(MusicScript.state) {
        case .success(.string(let output)):
            guard let parsed = MusicScript.parseState(output) else {
                clear(.failed("Unexpected reply from Music"))
                return
            }
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
            if error.isNotAuthorized { clear(.notAuthorized) }
            else if error.isAppGone { clear(.notRunning) }
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
