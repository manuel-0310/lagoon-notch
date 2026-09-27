import AppKit
import EventKit
import Observation
import SwiftUI

enum AccessState: Equatable {
    case notDetermined, granted, denied
}

struct CalendarEvent: Identifiable, Equatable {
    var id: String
    var identifier: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var color: Color
    var location: String?
    var meetingURL: URL?
    var meetingService: String?

    /// "Meet" para el botón "Unirse a Meet".
    var meetingShortName: String? {
        meetingService == "Google Meet" ? "Meet" : meetingService
    }

    /// "10:00 – 10:30 · Google Meet"
    var subtitle: String {
        let time = isAllDay ? "Todo el día" : "\(Formatters.time(start)) – \(Formatters.time(end))"
        if let meetingService { return "\(time) · \(meetingService)" }
        if let location, !location.isEmpty, !location.hasPrefix("http") { return "\(time) · \(location)" }
        return time
    }

    /// "en 12 min" / "ahora · hasta 10:30"
    func relativeDescription(now: Date) -> String {
        if start > now { return Formatters.until(start, now: now) }
        return "ahora · hasta \(Formatters.time(end))"
    }
}

struct ReminderItem: Identifiable, Equatable {
    var id: String
    var title: String
    var due: Date?
    var hasTime: Bool
    var isCompleted: Bool

    var timeLabel: String? {
        guard let due, hasTime else { return nil }
        return Formatters.time(due)
    }

    /// "Recordatorio · 11:00"
    var eyebrow: String {
        if let timeLabel { return "Recordatorio · \(timeLabel)" }
        return "Recordatorio"
    }
}

/// Eventos de hoy y recordatorios (EventKit). Los avisos se programan con un único
/// temporizador hasta el siguiente evento; nada se consulta en bucle.
@Observable
final class CalendarService {
    var eventsAccess: AccessState = .notDetermined
    var remindersAccess: AccessState = .notDetermined
    var todayEvents: [CalendarEvent] = []
    var reminders: [ReminderItem] = []

    @ObservationIgnored weak var notch: NotchViewModel?
    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var alertTimer: Timer?
    @ObservationIgnored private var dayTimer: Timer?
    @ObservationIgnored private var firedKeys = Set<String>()
    @ObservationIgnored private var snoozed: [String: Date] = [:]
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var requested = false

    var nextEvent: CalendarEvent? {
        let now = AppEnvironment.now
        return todayEvents.first { !$0.isAllDay && $0.end > now }
    }

    var featuredEvent: CalendarEvent? { nextEvent }

    var laterEvents: [CalendarEvent] {
        let featured = featuredEvent?.id
        return todayEvents.filter { $0.id != featured }
    }

    var pendingDescription: String {
        let count = reminders.filter { !$0.isCompleted }.count
        return count == 1 ? "1 pendiente" : "\(count) pendientes"
    }

    // MARK: - Arranque y permisos

    func start() {
        updateAccessStates()
        observers.append(NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store,
                                                                queue: .main) { [weak self] _ in
            self?.reload()
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.reload() })
        reload()
    }

    private func updateAccessStates() {
        eventsAccess = Self.map(EKEventStore.authorizationStatus(for: .event))
        remindersAccess = Self.map(EKEventStore.authorizationStatus(for: .reminder))
    }

    private static func map(_ status: EKAuthorizationStatus) -> AccessState {
        switch status {
        case .notDetermined: return .notDetermined
        case .fullAccess: return .granted
        case .denied, .restricted, .writeOnly: return .denied
        @unknown default:
            return status.rawValue == 3 ? .granted : .denied
        }
    }

    /// Pide permiso la primera vez que se abre Inicio o la Agenda.
    func requestAccessIfNeeded() {
        guard !requested, !AppEnvironment.isSnapshot else { return }
        if eventsAccess == .notDetermined || remindersAccess == .notDetermined {
            requested = true
            requestAccess(openSettingsIfDenied: false)
        }
    }

    func requestAccess(openSettingsIfDenied: Bool) {
        if openSettingsIfDenied, eventsAccess == .denied {
            SystemLinks.open(.calendars)
            return
        }
        store.requestFullAccessToEvents { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.updateAccessStates()
                self.store.requestFullAccessToReminders { _, _ in
                    DispatchQueue.main.async {
                        self.updateAccessStates()
                        self.reload()
                    }
                }
            }
        }
    }

    // MARK: - Carga

    func reload() {
        updateAccessStates()
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? now.addingTimeInterval(86_400)

        if eventsAccess == .granted {
            let predicate = store.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
            todayEvents = store.events(matching: predicate)
                .filter { $0.endDate > now }
                .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
                .map(Self.makeEvent)
        } else {
            todayEvents = []
        }

        if remindersAccess == .granted {
            let incomplete = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: endOfDay, calendars: nil)
            let completed = store.predicateForCompletedReminders(withCompletionDateStarting: startOfDay, ending: endOfDay, calendars: nil)
            store.fetchReminders(matching: incomplete) { [weak self] pending in
                let pendingItems = (pending ?? []).map(Self.makeReminder)
                self?.store.fetchReminders(matching: completed) { done in
                    let doneItems = (done ?? []).map(Self.makeReminder)
                    DispatchQueue.main.async {
                        guard let self else { return }
                        let sortedPending = pendingItems.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
                        self.reminders = sortedPending + doneItems
                        self.scheduleAlerts()
                    }
                }
            }
        } else {
            reminders = []
        }

        scheduleAlerts()
        scheduleDayChange(endOfDay)
    }

    private func scheduleDayChange(_ date: Date) {
        dayTimer?.invalidate()
        let timer = Timer(fire: date.addingTimeInterval(5), interval: 0, repeats: false) { [weak self] _ in
            self?.firedKeys.removeAll()
            self?.reload()
        }
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        dayTimer = timer
    }

    private static func makeEvent(_ event: EKEvent) -> CalendarEvent {
        let meeting = MeetingLink.find(in: [event.url?.absoluteString, event.location, event.notes])
        let color = event.calendar.map { Color(cgColor: $0.cgColor) } ?? Palette.blue
        return CalendarEvent(id: "\(event.eventIdentifier ?? UUID().uuidString)-\(event.startDate.timeIntervalSince1970)",
                             identifier: event.eventIdentifier ?? "",
                             title: event.title ?? "Sin título",
                             start: event.startDate,
                             end: event.endDate,
                             isAllDay: event.isAllDay,
                             color: color,
                             location: event.location,
                             meetingURL: meeting?.url,
                             meetingService: meeting?.service)
    }

    private static func makeReminder(_ reminder: EKReminder) -> ReminderItem {
        let components = reminder.dueDateComponents
        let due = components.flatMap { Calendar.current.date(from: $0) }
        return ReminderItem(id: reminder.calendarItemIdentifier,
                            title: reminder.title ?? "Recordatorio",
                            due: due,
                            hasTime: components?.hour != nil,
                            isCompleted: reminder.isCompleted)
    }

    // MARK: - Acciones

    func toggle(_ item: ReminderItem) {
        setCompleted(item, !item.isCompleted)
    }

    func complete(_ item: ReminderItem) {
        setCompleted(item, true)
    }

    private func setCompleted(_ item: ReminderItem, _ completed: Bool) {
        if let index = reminders.firstIndex(where: { $0.id == item.id }) {
            reminders[index].isCompleted = completed
        }
        guard let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        reminder.isCompleted = completed
        try? store.save(reminder, commit: true)
    }

    /// Pospone el aviso 10 minutos.
    func snooze(_ item: ReminderItem) {
        snoozed[item.id] = Date().addingTimeInterval(600)
        scheduleAlerts()
    }

    func addReminder(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, remindersAccess == .granted else { return }
        let reminder = EKReminder(eventStore: store)
        reminder.title = trimmed
        reminder.calendar = store.defaultCalendarForNewReminders()
        reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        try? store.save(reminder, commit: true)
        reload()
    }

    func join(_ event: CalendarEvent) {
        if let url = event.meetingURL { NSWorkspace.shared.open(url) }
    }

    func open(_ event: CalendarEvent) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: - Avisos

    private func scheduleAlerts() {
        alertTimer?.invalidate()
        alertTimer = nil
        guard !AppEnvironment.isSnapshot else { return }
        let now = Date()
        var candidates: [(date: Date, key: String, activity: LiveActivity)] = []

        if Prefs.bool(Prefs.showEvents) {
            let lead = TimeInterval(max(1, Prefs.int(Prefs.eventLeadMinutes)) * 60)
            for event in todayEvents where !event.isAllDay && event.start > now {
                let key = "event-\(event.id)"
                guard !firedKeys.contains(key) else { continue }
                candidates.append((max(now, event.start.addingTimeInterval(-lead)), key, .upcomingEvent(event)))
            }
        }
        if Prefs.bool(Prefs.showReminders) {
            for reminder in reminders where !reminder.isCompleted && reminder.hasTime {
                guard let due = snoozed[reminder.id] ?? reminder.due, due > now.addingTimeInterval(-90) else { continue }
                let key = "reminder-\(reminder.id)-\(Int(due.timeIntervalSince1970))"
                guard !firedKeys.contains(key) else { continue }
                candidates.append((max(now, due), key, .reminderDue(reminder)))
            }
        }

        guard let next = candidates.min(by: { $0.date < $1.date }) else { return }
        if next.date.timeIntervalSince(now) < 1 {
            fire(key: next.key, activity: next.activity)
            return
        }
        let timer = Timer(fire: next.date, interval: 0, repeats: false) { [weak self] _ in
            self?.fire(key: next.key, activity: next.activity)
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        alertTimer = timer
    }

    private func fire(key: String, activity: LiveActivity) {
        firedKeys.insert(key)
        notch?.post(activity)
        DispatchQueue.main.async { [weak self] in self?.scheduleAlerts() }
    }
}

/// Detecta enlaces de videollamada en la URL, la ubicación o las notas del evento.
enum MeetingLink {
    private static let patterns: [(service: String, regex: String)] = [
        ("Meet", #"https://meet\.google\.com/[a-z0-9\-]+"#),
        ("Zoom", #"https://[\w.\-]*zoom\.us/(j|my|w|s)/[^\s<>"']+"#),
        ("Teams", #"https://teams\.(microsoft|live)\.com/l/meetup-join/[^\s<>"']+"#),
        ("Webex", #"https://[\w.\-]*webex\.com/[^\s<>"']+"#),
        ("FaceTime", #"https://facetime\.apple\.com/join[^\s<>"']+"#),
        ("Slack", #"https://app\.slack\.com/huddle/[^\s<>"']+"#),
    ]

    static func find(in texts: [String?]) -> (url: URL, service: String)? {
        for text in texts.compactMap({ $0 }) {
            for (service, pattern) in patterns {
                if let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]),
                   let url = URL(string: String(text[range])) {
                    return (url, service == "Meet" ? "Google Meet" : service)
                }
            }
        }
        return nil
    }
}
