import SwiftUI

struct AgendaCard: View {
    let agenda: AgendaService

    var body: some View {
        Card(title: "Agenda", symbol: "calendar", action: agenda.openCalendar) {
            VStack(alignment: .leading, spacing: 10) {
                events
                Divider().overlay(Color.white.opacity(0.08))
                reminders
            }
        }
    }

    @ViewBuilder private var events: some View {
        switch agenda.eventAccess {
        case .unknown:
            NoticeView(text: "Calendar access needed.", buttonTitle: "Allow", action: agenda.requestAccessIfNeeded)
        case .denied:
            NoticeView(text: "Calendar access is off.", buttonTitle: "Open Settings") { SystemSettings.open("Privacy_Calendars") }
        case .granted:
            if agenda.events.isEmpty {
                Text("No more events today or tomorrow.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
            } else {
                let shown = Array(agenda.events.prefix(3))
                let today = shown.filter { Calendar.current.isDateInToday($0.start) || $0.start <= .now }
                let tomorrow = shown.filter { !today.contains($0) }
                VStack(alignment: .leading, spacing: 5) {
                    if !today.isEmpty {
                        // Heading only needed when tomorrow is also listed.
                        if !tomorrow.isEmpty { DayHeading(title: "Today") }
                        ForEach(today) { EventRow(event: $0) }
                    }
                    if !tomorrow.isEmpty {
                        DayHeading(title: "Tomorrow")
                        ForEach(tomorrow) { EventRow(event: $0) }
                    }
                    if agenda.events.count > 3 {
                        Text("+\(agenda.events.count - 3) more").font(.system(size: 10)).foregroundStyle(Theme.tertiary)
                    }
                }
            }
        }
    }

    @ViewBuilder private var reminders: some View {
        switch agenda.reminderAccess {
        case .unknown:
            NoticeView(text: "Reminders access needed.", buttonTitle: "Allow", action: agenda.requestAccessIfNeeded)
        case .denied:
            NoticeView(text: "Reminders access is off.", buttonTitle: "Open Settings") { SystemSettings.open("Privacy_Reminders") }
        case .granted:
            if agenda.reminders.isEmpty {
                Text("No reminders due today.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(agenda.reminders.prefix(3)) { item in
                        ReminderRow(item: item) { agenda.complete(item) }
                    }
                    if agenda.reminders.count > 3 {
                        Button("+\(agenda.reminders.count - 3) more", action: agenda.openReminders)
                            .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Theme.tertiary)
                    }
                }
            }
        }
    }
}

private struct EventRow: View {
    let event: AgendaService.EventItem

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(red: event.color.r, green: event.color.g, blue: event.color.b))
                .frame(width: 3, height: 15)
            Text(timeLabel)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(isNow ? Theme.accent : Theme.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 54, alignment: .leading)
            Text(event.title).font(.system(size: 12)).lineLimit(1)
        }
    }

    private var isNow: Bool { !event.isAllDay && event.start <= .now && event.end > .now }

    /// The day is shown by the Today/Tomorrow headings, so this is time only.
    private var timeLabel: String {
        if event.isAllDay { return "All day" }
        if isNow { return "Now" }
        return event.start.formatted(date: .omitted, time: .shortened)
    }
}

private struct DayHeading: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold))
            .textCase(.uppercase)
            .kerning(0.5)
            .foregroundStyle(Theme.tertiary)
            .padding(.top, 2)
    }
}

private struct ReminderRow: View {
    let item: AgendaService.ReminderItem
    let onComplete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onComplete) {
                Image(systemName: hovering ? "checkmark.circle" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(hovering ? Theme.accent : Theme.secondary)
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help("Mark complete")
            Text(item.title).font(.system(size: 12)).lineLimit(1)
            if item.isOverdue {
                Text("overdue").font(.system(size: 9, weight: .semibold)).foregroundStyle(.orange)
            }
        }
    }
}
