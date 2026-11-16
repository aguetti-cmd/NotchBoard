import Foundation

/// One assistant API response recorded in a Claude Code session log.
public struct UsageRecord: Sendable, Equatable {
    /// Message id plus request id. Claude Code writes one line per content
    /// block, each repeating the same usage, so this key dedupes them.
    public let key: String
    public let sessionId: String
    public let timestamp: Date
    public let model: String?
    public let input: Int
    public let cacheCreation: Int
    public let cacheRead: Int
    public let output: Int
}

/// Token totals for one local calendar day.
public struct DayUsage: Sendable, Equatable, Identifiable {
    public let day: String  // yyyy-MM-dd, local time
    public var input: Int = 0
    public var cacheCreation: Int = 0
    public var cacheRead: Int = 0
    public var output: Int = 0
    public var sessions: Int = 0
    public var responses: Int = 0

    public var id: String { day }
    /// Everything the model read or wrote, cache included.
    public var total: Int { input + cacheCreation + cacheRead + output }
    /// Fresh input: tokens that were not served from cache.
    public var freshInput: Int { input + cacheCreation }

    public init(day: String) { self.day = day }
}

public enum UsageLineParser {
    /// Cheap byte check before paying for JSON parsing.
    public static let marker = Data("\"usage\"".utf8)

    public static func parse(_ line: Data) -> UsageRecord? {
        guard line.range(of: marker) != nil,
              let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              obj["type"] as? String == "assistant",
              let message = obj["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let stamp = obj["timestamp"] as? String,
              let date = parseDate(stamp)
        else { return nil }

        func int(_ key: String) -> Int { (usage[key] as? NSNumber)?.intValue ?? 0 }

        let messageId = message["id"] as? String ?? obj["uuid"] as? String ?? stamp
        let requestId = obj["requestId"] as? String ?? ""
        return UsageRecord(
            key: messageId + "|" + requestId,
            sessionId: obj["sessionId"] as? String ?? "unknown",
            timestamp: date,
            model: message["model"] as? String,
            input: int("input_tokens"),
            cacheCreation: int("cache_creation_input_tokens"),
            cacheRead: int("cache_read_input_tokens"),
            output: int("output_tokens")
        )
    }

    static func parseDate(_ string: String) -> Date? {
        if let d = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string) { return d }
        return try? Date.ISO8601FormatStyle().parse(string)
    }
}

/// Accumulates records into per-day totals, counting each response once.
public struct UsageAggregator: Sendable {
    private var seen: Set<String> = []
    private var days: [String: DayUsage] = [:]
    private var sessions: [String: Set<String>] = [:]

    public init() {}

    public static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Returns false when the record was already counted.
    @discardableResult
    public mutating func add(_ r: UsageRecord, calendar: Calendar) -> Bool {
        guard seen.insert(r.key).inserted else { return false }
        let key = Self.dayKey(r.timestamp, calendar: calendar)
        var d = days[key] ?? DayUsage(day: key)
        d.input += r.input
        d.cacheCreation += r.cacheCreation
        d.cacheRead += r.cacheRead
        d.output += r.output
        d.responses += 1
        sessions[key, default: []].insert(r.sessionId)
        d.sessions = sessions[key]?.count ?? 0
        days[key] = d
        return true
    }

    /// The last `count` days ending at `end`, oldest first, zero-filled.
    public func days(endingAt end: Date, count: Int, calendar: Calendar) -> [DayUsage] {
        (0..<count).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: end) else { return nil }
            let key = Self.dayKey(date, calendar: calendar)
            return days[key] ?? DayUsage(day: key)
        }
    }
}

/// Reads Claude Code session logs incrementally. Each file is read from the
/// byte offset reached last time, so a refresh only parses new lines.
public actor UsageScanner {
    private let root: URL
    private var offsets: [String: UInt64] = [:]
    private var aggregator = UsageAggregator()
    private let calendar: Calendar

    public init(root: URL, calendar: Calendar = .current) {
        self.root = root
        self.calendar = calendar
    }

    public func scan(now: Date = .now, dayCount: Int = 7) -> [DayUsage] {
        let cutoff = calendar.date(byAdding: .day, value: -(dayCount + 1), to: now) ?? now
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        if let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) {
            for case let url as URL in walker where url.pathExtension == "jsonl" {
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true,
                      let modified = values.contentModificationDate, modified >= cutoff,
                      let size = values.fileSize
                else { continue }
                read(url, size: UInt64(size))
            }
        }
        return aggregator.days(endingAt: now, count: dayCount, calendar: calendar)
    }

    private func read(_ url: URL, size: UInt64) {
        var start = offsets[url.path] ?? 0
        if size < start { start = 0 }  // file was rewritten; dedupe keys protect totals
        guard size > start, let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: start)
            guard let chunk = try handle.read(upToCount: Int(size - start)),
                  let lastNewline = chunk.lastIndex(of: 0x0A)
            else { return }  // no complete line yet
            let complete = chunk[chunk.startIndex...lastNewline]
            for line in complete.split(separator: 0x0A, omittingEmptySubsequences: true) {
                if let record = UsageLineParser.parse(Data(line)) {
                    aggregator.add(record, calendar: calendar)
                }
            }
            offsets[url.path] = start + UInt64(complete.count)
        } catch {
            return
        }
    }
}
