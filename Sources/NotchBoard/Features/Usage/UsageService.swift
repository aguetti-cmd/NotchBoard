import Foundation
import Observation
import NotchBoardCore

/// Claude Code usage on this Mac, read from local session logs.
/// Nothing is sent anywhere.
@MainActor @Observable
final class UsageService {
    private(set) var days: [DayUsage] = []
    private(set) var lastScan: Date?
    private(set) var logsFound = true

    private let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects", isDirectory: true)
    private let scanner: UsageScanner
    private var loop: Task<Void, Never>?

    init() {
        scanner = UsageScanner(root: root)
    }

    var today: DayUsage? { days.last }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    func refresh() async {
        logsFound = FileManager.default.fileExists(atPath: root.path)
        guard logsFound else { days = []; return }
        days = await scanner.scan(now: .now, dayCount: 7)
        lastScan = .now
    }
}
