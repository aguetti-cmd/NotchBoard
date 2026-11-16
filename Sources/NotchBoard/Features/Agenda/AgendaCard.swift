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
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(agenda.events.prefix(3)) { EventRow(event: $0) }
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
                .frame(width: 70, alignment: .leading)
            Text(event.title).font(.system(size: 12)).lineLimit(1)
        }
    }

    private var isNow: Bool { !event.isAllDay && event.start <= .now && event.end > .now }

    private var timeLabel: String {
        let tomorrow = !Calendar.current.isDateInToday(event.start) && event.start > .now
        if event.isAllDay { return tomorrow ? "Tmrw all day" : "All day" }
        if isNow { return "Now" }
        let time = event.start.formatted(date: .omitted, time: .shortened)
        return tomorrow ? "Tmrw \(time)" : time
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
