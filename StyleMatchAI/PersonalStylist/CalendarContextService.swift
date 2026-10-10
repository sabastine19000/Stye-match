import EventKit
import Foundation

/// The only EventKit boundary. Raw EKEvent values never cross this service.
protocol CalendarContextAccessing {
    var authorizationStatus: EKAuthorizationStatus { get }
    func requestReadAccess() async throws -> Bool
    func events(from start: Date, to end: Date) throws -> [EKEvent]
}

final class EventKitCalendarContextAccess: CalendarContextAccessing {
    private let store = EKEventStore()
    var authorizationStatus: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .event) }

    func requestReadAccess() async throws -> Bool {
        if #available(iOS 17.0, macOS 14.0, *) {
            return try await store.requestFullAccessToEvents()
        }
        return try await withCheckedThrowingContinuation { continuation in
            store.requestAccess(to: .event) { granted, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: granted) }
            }
        }
    }

    func events(from start: Date, to end: Date) throws -> [EKEvent] {
        // Ask EventKit for every event calendar that the customer has made
        // available to this app. Supplying the visible calendars explicitly
        // avoids silently depending on a default-calendar selection.
        let calendars = store.calendars(for: .event)
        return store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: calendars))
    }

    /// Debug-owner evidence only. It intentionally returns counts and
    /// minimized categories, never event titles, identifiers, notes, people,
    /// locations, URLs, or calendar names.
    func runtimeDiagnostics(now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> CalendarContextRuntimeDiagnostics {
        let window = CalendarContextWindow.range(from: now)
        guard CalendarContextConsentStore.isEnabled(), CalendarContextProvider.hasReadAccess(authorizationStatus) else {
            return CalendarContextRuntimeDiagnostics(
                authorizationStatus: CalendarContextRuntimeDiagnostics.authorizationText(for: authorizationStatus),
                consentEnabled: CalendarContextConsentStore.isEnabled(),
                eventQueryState: "NOT_ATTEMPTED",
                eventCalendarsVisibleCount: 0,
                eventsFetchedCount: 0,
                eventsInWindowCount: 0,
                eventsMinimizedCount: 0,
                eventsClassifiedCount: 0,
                eventsRejectedCount: 0,
                rejectionReasonCounts: [:],
                windowStart: window.start,
                windowEnd: window.end
            )
        }

        let calendars = store.calendars(for: .event)
        let fetchedEvents: [EKEvent]
        do {
            fetchedEvents = try self.events(from: window.start, to: window.end)
        } catch {
            return CalendarContextRuntimeDiagnostics(
                authorizationStatus: CalendarContextRuntimeDiagnostics.authorizationText(for: authorizationStatus),
                consentEnabled: true,
                eventQueryState: "QUERY_FAILED",
                eventCalendarsVisibleCount: calendars.count,
                eventsFetchedCount: 0,
                eventsInWindowCount: 0,
                eventsMinimizedCount: 0,
                eventsClassifiedCount: 0,
                eventsRejectedCount: 0,
                rejectionReasonCounts: [:],
                windowStart: window.start,
                windowEnd: window.end
            )
        }
        let batch = CalendarContextBatch.make(events: fetchedEvents, now: now, calendar: calendar)
        return CalendarContextRuntimeDiagnostics(
            authorizationStatus: CalendarContextRuntimeDiagnostics.authorizationText(for: authorizationStatus),
            consentEnabled: true,
            eventQueryState: "QUERY_SUCCEEDED",
            eventCalendarsVisibleCount: calendars.count,
            eventsFetchedCount: fetchedEvents.count,
            eventsInWindowCount: batch.eventsInWindowCount,
            eventsMinimizedCount: batch.projections.count,
            eventsClassifiedCount: batch.classifiedCount,
            eventsRejectedCount: batch.rejectionReasonCounts.values.reduce(0, +),
            rejectionReasonCounts: batch.rejectionReasonCounts,
            windowStart: window.start,
            windowEnd: window.end
        )
    }
}

enum CalendarContextCategory: String, Codable, CaseIterable, Sendable {
    case workShift, businessMeeting, interview, wedding, birthday, anniversary, holiday, dinner, date, religiousService, travel, vacation, workout, formalEvent, socialGathering, appointment, concertOrShow, celebration, ceremony, otherSignificantEvent
}

struct CalendarContextProjection: Equatable, Sendable {
    let category: CalendarContextCategory
    let timeWindow: LocalTimeBucket
    let approximateDurationMinutes: Int
    let isAllDay: Bool
    let isRecurring: Bool
    let expiresAt: Date

    var safeSummary: String {
        let duration = approximateDurationMinutes >= 180 ? "extended" : "short"
        return "Calendar context: \(category.rawValue), \(timeWindow.rawValue), \(duration) duration\(isAllDay ? ", all-day" : "")\(isRecurring ? ", recurring" : "")"
    }
}

enum CalendarContextWindow {
    /// Three weeks supports outfit preparation for nearby weekends, travel,
    /// ceremonies, and appointments without creating an open-ended calendar
    /// history. The device's autoupdating Calendar supplies local time-zone
    /// semantics for event time buckets.
    static let lookAheadDays = 21

    static func range(from now: Date, calendar: Calendar = .autoupdatingCurrent) -> (start: Date, end: Date) {
        let end = calendar.date(byAdding: .day, value: lookAheadDays, to: now) ?? now.addingTimeInterval(TimeInterval(lookAheadDays * 86_400))
        return (now, end)
    }
}

enum CalendarContextRejectionReason: String, CaseIterable, Sendable {
    case expired
    case blankTitle
}

enum CalendarContextClassification: Equatable, Sendable {
    case categorized(CalendarContextCategory)
    case otherSignificantEvent
    case rejected(CalendarContextRejectionReason)
}

enum CalendarContextSanitizer {
    static func project(_ event: EKEvent, now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> CalendarContextProjection? {
        switch classification(for: event, now: now) {
        case .categorized(let category):
            return projection(event, category: category, now: now, calendar: calendar)
        case .otherSignificantEvent:
            return projection(event, category: .otherSignificantEvent, now: now, calendar: calendar)
        case .rejected:
            return nil
        }
    }

    /// The title is inspected only in memory. A nonempty, upcoming event that
    /// does not match a narrow occasion taxonomy remains a bounded
    /// `otherSignificantEvent`; it is not silently represented as no event.
    static func classification(for title: String) -> CalendarContextClassification {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return .rejected(.blankTitle) }
        guard let category = category(for: trimmedTitle) else { return .otherSignificantEvent }
        return .categorized(category)
    }

    static func classification(for event: EKEvent, now: Date = Date()) -> CalendarContextClassification {
        guard event.endDate >= now else { return .rejected(.expired) }
        return classification(for: event.title ?? "")
    }

    private static func projection(
        _ event: EKEvent,
        category: CalendarContextCategory,
        now: Date,
        calendar: Calendar
    ) -> CalendarContextProjection {
        let minutes = max(0, min(480, Int(event.endDate.timeIntervalSince(event.startDate) / 60)))
        let expiry = min(event.endDate.addingTimeInterval(3600), now.addingTimeInterval(14 * 86_400))
        return CalendarContextProjection(
            category: category,
            timeWindow: LocalDateContext(date: event.startDate, calendar: calendar).timeBucket,
            approximateDurationMinutes: minutes,
            isAllDay: event.isAllDay,
            isRecurring: event.hasRecurrenceRules,
            expiresAt: expiry
        )
    }

    private static func category(for title: String) -> CalendarContextCategory? {
        let words = title.lowercased()
        let matches: [(String, CalendarContextCategory)] = [
            ("anniversary", .anniversary), ("birthday", .birthday), ("holiday", .holiday),
            ("interview", .interview), ("wedding", .wedding), ("ceremony", .ceremony),
            ("graduation", .ceremony), ("concert", .concertOrShow), ("show", .concertOrShow),
            ("celebration", .celebration), ("appointment", .appointment), ("doctor", .appointment),
            ("dentist", .appointment), ("church", .religiousService), ("travel", .travel),
            ("flight", .travel), ("vacation", .vacation), ("gym", .workout), ("workout", .workout),
            ("dinner", .dinner), ("date", .date), ("meeting", .businessMeeting),
            ("work", .workShift), ("formal", .formalEvent), ("party", .socialGathering)
        ]
        return matches.first(where: { words.contains($0.0) })?.1
    }
}

struct CalendarContextBatch: Equatable, Sendable {
    let projections: [CalendarContextProjection]
    let eventsInWindowCount: Int
    let classifiedCount: Int
    let rejectionReasonCounts: [CalendarContextRejectionReason: Int]

    static func make(events: [EKEvent], now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> CalendarContextBatch {
        var projections: [CalendarContextProjection] = []
        var classifiedCount = 0
        var rejected: [CalendarContextRejectionReason: Int] = [:]

        for event in events {
            switch CalendarContextSanitizer.classification(for: event, now: now) {
            case .categorized(let category):
                classifiedCount += 1
                if let projection = CalendarContextSanitizer.project(event, now: now, calendar: calendar), projection.category == category {
                    projections.append(projection)
                }
            case .otherSignificantEvent:
                if let projection = CalendarContextSanitizer.project(event, now: now, calendar: calendar) {
                    projections.append(projection)
                }
            case .rejected(let reason):
                rejected[reason, default: 0] += 1
            }
        }

        return CalendarContextBatch(
            projections: projections.sorted { $0.expiresAt < $1.expiresAt },
            eventsInWindowCount: events.count,
            classifiedCount: classifiedCount,
            rejectionReasonCounts: rejected
        )
    }
}

struct CalendarContextRuntimeDiagnostics: Equatable, Sendable {
    let authorizationStatus: String
    let consentEnabled: Bool
    let eventQueryState: String
    let eventCalendarsVisibleCount: Int
    let eventsFetchedCount: Int
    let eventsInWindowCount: Int
    let eventsMinimizedCount: Int
    let eventsClassifiedCount: Int
    let eventsRejectedCount: Int
    let rejectionReasonCounts: [CalendarContextRejectionReason: Int]
    let windowStart: Date
    let windowEnd: Date

    static func authorizationText(for status: EKAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "NOT_DETERMINED"
        case .restricted: "RESTRICTED"
        case .denied: "DENIED"
        case .authorized, .fullAccess: "FULL_ACCESS"
        case .writeOnly: "WRITE_ONLY"
        @unknown default: "UNKNOWN"
        }
    }
}

/// Stores consent only. It deliberately stores no event data, identifiers, or
/// cached projection; each request reads and sanitizes an event in memory.
enum CalendarContextConsentStore {
    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        let userID = AccountScopedStorage.sessionUserID(defaults: defaults)
        return CalendarAwarenessPreferenceStore.state(for: userID, defaults: defaults) == .on
    }

    static func disconnect(defaults: UserDefaults = .standard) {
        let userID = AccountScopedStorage.sessionUserID(defaults: defaults)
        CalendarAwarenessPreferenceStore.clear(for: userID, defaults: defaults)
    }
}

enum CalendarContextProvider {
    static func occasionFact(
        access: CalendarContextAccessing,
        defaults: UserDefaults = .standard,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> StyleMemoryFact<String> {
        guard CalendarContextConsentStore.isEnabled(defaults: defaults), hasReadAccess(access.authorizationStatus) else { return .unavailable }
        let range = CalendarContextWindow.range(from: now, calendar: calendar)
        guard let events = try? access.events(from: range.start, to: range.end),
              let projection = CalendarContextBatch.make(events: events, now: now, calendar: calendar).projections.first else { return .unavailable }
        return StyleMemoryFact(
            value: projection.safeSummary,
            provenance: .authorizedCalendarEvent,
            observedAt: now,
            expiresAt: projection.expiresAt,
            confidence: .limited,
            permission: .authorized,
            identityScope: StyleMemoryIdentityScope.resolve(defaults: defaults),
            lifetime: .expiresAt
        )
    }

    static func hasReadAccess(_ status: EKAuthorizationStatus) -> Bool {
        if #available(iOS 17.0, macOS 14.0, *) {
            return status == .fullAccess
        }
        return status == .authorized
    }
}
