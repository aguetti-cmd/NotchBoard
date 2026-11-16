import SwiftUI
import NotchBoardCore

struct UsageCard: View {
    let usage: UsageService

    var body: some View {
        Card(title: "Claude today", symbol: "sparkle") {
            if !usage.logsFound {
                NoticeView(text: "No Claude Code logs on this Mac.")
            } else if let today = usage.today {
                HStack(alignment: .bottom, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(TokenFormat.compact(today.total))
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                        Text("\(TokenFormat.compact(today.output)) out · \(today.sessions) session\(today.sessions == 1 ? "" : "s")")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.secondary)
                    }
                    Spacer(minLength: 0)
                    WeekBars(days: usage.days)
                }
                .help("Tokens on this Mac today, cache reads included. From ~/.claude/projects.")
            } else {
                NoticeView(text: "Reading logs…")
            }
        }
    }
}

/// Seven bars, oldest to today, scaled to the busiest day.
private struct WeekBars: View {
    let days: [DayUsage]

    var body: some View {
        let peak = max(days.map(\.total).max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(index == days.count - 1 ? Theme.accent : Color.white.opacity(0.28))
                    .frame(width: 6, height: max(2, 30 * CGFloat(day.total) / CGFloat(peak)))
                    .help("\(day.day): \(TokenFormat.compact(day.total))")
            }
        }
        .frame(height: 30, alignment: .bottom)
    }
}
