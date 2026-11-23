import Foundation

/// What makes two calendar entries the same event for display purposes.
/// Case and surrounding spaces in the title are ignored.
public struct EventKey: Hashable, Sendable {
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool

    public init(title: String, start: Date, end: Date, isAllDay: Bool) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
    }
}

/// Display order for the agenda: today's entries before tomorrow's; within a
/// day, all-day entries first, then by start time. Anything that started
/// before tomorrow counts as today, so a running multi-day event stays on top.
public enum AgendaOrder {
    public static func sorted<T>(
        _ items: [T],
        startOfTomorrow: Date,
        start: (T) -> Date,
        isAllDay: (T) -> Bool
    ) -> [T] {
        func key(_ item: T) -> (Int, Int, Date) {
            let s = start(item)
            return (s < startOfTomorrow ? 0 : 1, isAllDay(item) ? 0 : 1, s)
        }
        return items.sorted { key($0) < key($1) }
    }
}

extension Sequence {
    /// Keeps the first element for each key, preserving order.
    public func uniqued<Key: Hashable>(by key: (Element) -> Key) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert(key($0)).inserted }
    }
}
