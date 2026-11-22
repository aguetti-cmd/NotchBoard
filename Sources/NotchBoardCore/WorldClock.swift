import Foundation

/// A place shown in the world clock row.
public struct ClockZone: Sendable, Equatable, Codable {
    public let name: String
    /// IANA time zone identifier, e.g. "Asia/Bangkok".
    public let identifier: String

    public init(name: String, identifier: String) {
        self.name = name
        self.identifier = identifier
    }

    /// The first zone is home: other places' day labels are relative to it.
    public static let defaults: [ClockZone] = [
        ClockZone(name: "Bangkok", identifier: "Asia/Bangkok"),
        ClockZone(name: "Bangalore", identifier: "Asia/Kolkata"),
        ClockZone(name: "Dublin", identifier: "Europe/Dublin"),
        ClockZone(name: "Austin", identifier: "America/Chicago"),
    ]
}

/// One place's local time at a given instant.
public struct ClockReading: Sendable, Equatable {
    public let name: String
    public let hour: Int
    public let minute: Int
    /// Calendar days ahead (+1) or behind (-1) the home zone.
    public let dayOffset: Int
    /// Short English weekday, e.g. "Mon".
    public let weekday: String
    /// 20:00 to 06:59 local.
    public let isNight: Bool
    public let isHome: Bool

    /// "16:05"
    public var time: String { String(format: "%02d:%02d", hour, minute) }
}

public enum WorldClock {
    /// Local times for each zone at `date`. Zones with an unknown identifier
    /// are dropped. Day offsets are relative to the first valid zone.
    public static func readings(at date: Date, zones: [ClockZone]) -> [ClockReading] {
        let resolved = zones.compactMap { zone in
            TimeZone(identifier: zone.identifier).map { (zone, $0) }
        }
        guard let home = resolved.first else { return [] }
        let homeDay = dayNumber(of: date, in: home.1)
        return resolved.enumerated().map { index, pair in
            let (zone, tz) = pair
            let cal = calendar(in: tz)
            let c = cal.dateComponents([.hour, .minute, .weekday], from: date)
            let hour = c.hour ?? 0
            let weekdayIndex = (c.weekday ?? 1) - 1
            return ClockReading(
                name: zone.name,
                hour: hour,
                minute: c.minute ?? 0,
                dayOffset: dayNumber(of: date, in: tz) - homeDay,
                weekday: cal.shortWeekdaySymbols[weekdayIndex],
                isNight: hour >= 20 || hour < 7,
                isHome: index == 0
            )
        }
    }

    private static func calendar(in tz: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        cal.locale = Locale(identifier: "en_US_POSIX")
        return cal
    }

    /// Days since 1970-01-01 for the local calendar date in `tz`.
    private static func dayNumber(of date: Date, in tz: TimeZone) -> Int {
        let local = calendar(in: tz).dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        guard let midnight = utc.date(from: local) else { return 0 }
        return Int((midnight.timeIntervalSince1970 / 86_400).rounded(.down))
    }
}
