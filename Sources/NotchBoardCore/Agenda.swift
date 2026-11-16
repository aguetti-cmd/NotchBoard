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

extension Sequence {
    /// Keeps the first element for each key, preserving order.
    public func uniqued<Key: Hashable>(by key: (Element) -> Key) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert(key($0)).inserted }
    }
}
