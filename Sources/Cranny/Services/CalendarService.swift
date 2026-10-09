import AppKit
import EventKit

struct CalendarEventInfo: Identifiable, Equatable {
    let id: String
    let eventIdentifier: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: NSColor
    let calendarTitle: String
    let location: String
    let meetingURL: URL?
}

@MainActor
final class CalendarService: ObservableObject {
    static let shared = CalendarService()

    let store = EKEventStore()
    @Published private(set) var status: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    @Published private(set) var revision = 0

    private var cache: [Date: [CalendarEventInfo]] = [:]
    private var observers: [NSObjectProtocol] = []

    var hasAccess: Bool { status == .fullAccess }

    private init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
            MainActor.assumeIsolated { CalendarService.shared.invalidate() }
        })
        observers.append(center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { CalendarService.shared.invalidate() }
        })
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { CalendarService.shared.refreshStatus() }
        })
    }

    func invalidate() {
        cache.removeAll()
        revision += 1
    }

    func refreshStatus() {
        let current = EKEventStore.authorizationStatus(for: .event)
        if current != status {
            status = current
            invalidate()
        }
    }

    func requestAccess() {
        store.requestFullAccessToEvents { _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let service = CalendarService.shared
                    service.status = EKEventStore.authorizationStatus(for: .event)
                    service.store.reset()
                    service.invalidate()
                }
            }
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    var calendars: [EKCalendar] {
        guard hasAccess else { return [] }
        return store.calendars(for: .event).sorted {
            ($0.source.title, $0.title) < ($1.source.title, $1.title)
        }
    }

    func events(on day: Date) -> [CalendarEventInfo] {
        guard hasAccess else { return [] }
        let start = Calendar.current.startOfDay(for: day)
        if let cached = cache[start] { return cached }
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return [] }

        let hidden = Set(AppSettings.shared.hiddenCalendarIDs)
        let visible = store.calendars(for: .event).filter { !hidden.contains($0.calendarIdentifier) }
        guard !visible.isEmpty else { cache[start] = []; return [] }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: visible)
        let result = store.events(matching: predicate)
            .filter { $0.status != .canceled }
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                return lhs.startDate < rhs.startDate
            }
            .map(Self.info(from:))
        cache[start] = result
        return result
    }

    /// The event the calendar live activity should show right now, if any.
    func liveEvent(now: Date = Date()) -> (event: CalendarEventInfo, inProgress: Bool)? {
        let settings = AppSettings.shared
        let lead = Double(settings.calendarMinutesBefore) * 60
        var candidates = events(on: now)
        if let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now),
           Calendar.current.startOfDay(for: tomorrow).timeIntervalSince(now) < lead {
            candidates += events(on: tomorrow)
        }
        candidates = candidates.filter { !$0.isAllDay && (!settings.calendarOnlyMeetings || $0.meetingURL != nil) }

        if let upcoming = candidates.first(where: { $0.start > now && $0.start.timeIntervalSince(now) <= lead }) {
            return (upcoming, false)
        }
        if settings.calendarShowWhileInEvent,
           let current = candidates.first(where: { $0.start <= now && $0.end > now }) {
            return (current, true)
        }
        return nil
    }

    func open(_ event: CalendarEventInfo) {
        let encoded = event.eventIdentifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        if let url = URL(string: "ical://ekevent/\(encoded)?method=show&options=more"), NSWorkspace.shared.open(url) {
            return
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private static let meetingPattern = try! NSRegularExpression(
        pattern: #"https?://[^\s<>"]*(zoom\.us|zoomgov\.com|meet\.google\.com|teams\.microsoft\.com|teams\.live\.com|webex\.com|whereby\.com|meet\.jit\.si|gotomeeting\.com|chime\.aws|around\.co|facetime\.apple\.com|discord\.gg|slack\.com/huddle)[^\s<>"]*"#,
        options: [.caseInsensitive]
    )

    static func meetingURL(in event: EKEvent) -> URL? {
        let candidates = [event.url?.absoluteString, event.location, event.notes].compactMap { $0 }
        for text in candidates {
            let range = NSRange(text.startIndex..., in: text)
            if let match = meetingPattern.firstMatch(in: text, range: range),
               let r = Range(match.range, in: text),
               let url = URL(string: String(text[r])) {
                return url
            }
        }
        return nil
    }

    private static func info(from event: EKEvent) -> CalendarEventInfo {
        CalendarEventInfo(
            id: "\(event.eventIdentifier ?? UUID().uuidString)-\(event.startDate.timeIntervalSince1970)",
            eventIdentifier: event.eventIdentifier ?? "",
            title: event.title?.isEmpty == false ? event.title! : "Untitled",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            color: event.calendar.map { NSColor(cgColor: $0.cgColor) ?? .systemBlue } ?? .systemBlue,
            calendarTitle: event.calendar?.title ?? "",
            location: event.location ?? "",
            meetingURL: meetingURL(in: event)
        )
    }
}
