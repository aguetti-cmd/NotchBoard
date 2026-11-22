import SwiftUI
import NotchBoardCore

/// A slim row of local times. The first place is home; other places show
/// their weekday when their date differs from home.
struct WorldClockRow: View {
    let zones: [ClockZone]
    @Environment(\.glassAmount) private var glass

    var body: some View {
        TimelineView(.everyMinute) { context in
            let readings = WorldClock.readings(at: context.date, zones: zones)
            HStack(spacing: 0) {
                ForEach(Array(readings.enumerated()), id: \.offset) { index, reading in
                    if index > 0 { Divider().frame(height: 14).overlay(Theme.tertiary.opacity(0.4)) }
                    ClockItem(reading: reading)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
                ZStack {
                    shape.fill(Color.black.opacity(0.28 * glass))
                    shape.fill(Theme.card)
                }
            }
        }
    }
}

private struct ClockItem: View {
    let reading: ClockReading

    var body: some View {
        HStack(spacing: 6) {
            if reading.isHome {
                Circle().fill(Theme.accent).frame(width: 5, height: 5)
            }
            Text(reading.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(reading.isHome ? Theme.accent : Theme.secondary)
            Text(reading.time)
                .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
            if reading.dayOffset != 0 {
                Text(reading.weekday)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.tertiary)
            }
            Image(systemName: reading.isNight ? "moon.fill" : "sun.max.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.tertiary)
        }
        .lineLimit(1)
        .help(helpText)
    }

    private var helpText: String {
        let day = reading.dayOffset == 0 ? "today" : (reading.dayOffset > 0 ? "tomorrow" : "yesterday")
        return "\(reading.name): \(reading.weekday) \(reading.time), \(day) relative to home"
    }
}
