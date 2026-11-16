import AppKit
import EventKit
import Observation
import NotchBoardCore

/// Today's and tomorrow's events, plus reminders due today or overdue.
@MainActor @Observable
final class AgendaService {
    enum Access: Equatable { case unknown, granted, denied }

    struct EventItem: Identifiable, Sendable, Equatable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        let color: RGB
    }

    struct ReminderItem: Identifiable, Sendable, Equatable {
        let id: String
        let title: String
        let due: Date?
        let isOverdue: Bool
    }

    struct RGB: Sendable, Equatable {
        let r, g, b: Double
        init(_ cg: CGColor?) {
            let c = cg.flatMap { NSColor(cgColor: $0)?.usingColorSpace(.sRGB) }
            r = Double(c?.redComponent ?? 0.6)
            g = Double(c?.greenComponent ?? 0.6)
            b = Double(c?.blueComponent ?? 0.6)
        }
    }

    private(set) var eventAccess: Access = .unknown
    private(set) var reminderAccess: Access = .unknown
    private(set) var events: [EventItem] = []
    private(set) var reminders: [ReminderItem] = []

    private let store = EKEventStore()
    private var observer: NSObjectProtocol?

    func start() {
        eventAccess = Self.access(EKEventStore.authorizationStatus(for: .event))
        reminderAccess = Self.access(EKEventStore.authorizationStatus(for: .reminder))
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        requestAccessIfNeeded()
        refresh()
    }

    private static func access(_ status: EKAuthorizationStatus) -> Access {
        switch status {
        case .fullAccess: return .granted
        case .notDetermined: return .unknown
        default: return .denied
        }
    }

    func requestAccessIfNeeded() {
        if eventAccess == .unknown {
            store.requestFullAccessToEvents { @Sendable [weak self] granted, _ in
                Task { @MainActor in
                    self?.eventAccess = granted ? .granted : .denied
                    self?.refresh()
                }
            }
        }
        if reminderAccess == .unknown {
            store.requestFullAccessToReminders { @Sendable [weak self] granted, _ in
                Task { @MainActor in
                    self?.reminderAccess = granted ? .granted : .denied
                    self?.refresh()
                }
            }
        }
    }

    func refresh() {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        guard let endOfTomorrow = calendar.date(byAdding: .day, value: 2, to: startOfToday),
              let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday)
        else { return }

        if eventAccess == .granted {
            let predicate = store.predicateForEvents(withStart: startOfToday, end: endOfTomorrow, calendars: nil)
            let raw = store.events(matching: predicate)
            events = raw
                .filter { $0.endDate > now }
                .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
                // The same event often arrives from two calendars (work and iCloud).
                .uniqued { EventKey(title: $0.title ?? "", start: $0.startDate, end: $0.endDate, isAllDay: $0.isAllDay) }
                .map {
                    EventItem(id: $0.eventIdentifier ?? UUID().uuidString,
                              title: $0.title ?? "Untitled",
                              start: $0.startDate, end: $0.endDate,
                              isAllDay: $0.isAllDay,
                              color: RGB($0.calendar?.cgColor))
                }
            if ProcessInfo.processInfo.environment["NOTCHBOARD_DEBUG"] != nil {
                let upcoming = raw.filter { $0.endDate > now }.count
                FileHandle.standardError.write(Data("events upcoming \(upcoming), after merging duplicates \(events.count)\n".utf8))
            }
        } else {
            events = []
        }

        if reminderAccess == .granted {
            let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: endOfToday, calendars: nil)
            // EventKit calls this on its own background queue. The closure must be
            // @Sendable (not main-actor isolated), or Swift's runtime check traps.
            store.fetchReminders(matching: predicate) { @Sendable [weak self] found in
                let items = Self.reminderItems(found, startOfToday: startOfToday)
                if ProcessInfo.processInfo.environment["NOTCHBOARD_DEBUG"] != nil {
                    FileHandle.standardError.write(Data("reminders fetched off-main: \(items.count) on \(Thread.isMainThread ? "main" : "background")\n".utf8))
                }
                Task { @MainActor in self?.reminders = items }
            }
        } else {
            reminders = []
        }
    }

    /// Runs on EventKit's queue, so it touches no actor state.
    nonisolated private static func reminderItems(_ found: [EKReminder]?, startOfToday: Date) -> [ReminderItem] {
        (found ?? []).map { r in
            let due = r.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
            return ReminderItem(id: r.calendarItemIdentifier,
                                title: r.title ?? "Untitled",
                                due: due,
                                isOverdue: due.map { $0 < startOfToday } ?? false)
        }
        .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
    }

    func complete(_ item: ReminderItem) {
        guard let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        reminder.isCompleted = true
        do {
            try store.save(reminder, commit: true)
            reminders.removeAll { $0.id == item.id }
        } catch {
            refresh()
        }
    }

    func openCalendar() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    func openReminders() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }
}
