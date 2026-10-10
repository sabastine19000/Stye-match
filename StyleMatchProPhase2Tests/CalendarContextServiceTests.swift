import EventKit
import XCTest
@testable import StyleMatchPro

final class CalendarContextServiceTests: XCTestCase {
    func testCalendarContextIsOffByDefaultAndDisconnectClearsOnlyScopedConsent() {
        let suite = "CalendarContextServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let userA = "calendar-a"
        let userB = "calendar-b"
        XCTAssertEqual(CalendarAwarenessPreferenceStore.state(for: userA, defaults: defaults), .off)
        CalendarAwarenessPreferenceStore.set(.on, for: userA, defaults: defaults)
        CalendarAwarenessPreferenceStore.set(.on, for: userB, defaults: defaults)
        CalendarAwarenessPreferenceStore.clear(for: userA, defaults: defaults)

        XCTAssertEqual(CalendarAwarenessPreferenceStore.state(for: userA, defaults: defaults), .off)
        XCTAssertEqual(CalendarAwarenessPreferenceStore.state(for: userB, defaults: defaults), .on)
    }

    func testProjectionContractContainsOnlyBoundedSafeFields() throws {
        let source = try calendarSource()
        XCTAssertTrue(source.contains("let category: CalendarContextCategory"))
        XCTAssertTrue(source.contains("let timeWindow: LocalTimeBucket"))
        XCTAssertTrue(source.contains("let approximateDurationMinutes: Int"))
        XCTAssertTrue(source.contains("let isAllDay: Bool"))
        XCTAssertTrue(source.contains("let expiresAt: Date"))
        XCTAssertFalse(source.contains("event.notes"))
        XCTAssertFalse(source.contains("event.location"))
        XCTAssertFalse(source.contains("event.url"))
        XCTAssertFalse(source.contains("event.eventIdentifier"))
        XCTAssertFalse(source.contains("event.calendar"))
        XCTAssertFalse(source.contains("event.organizer"))
        XCTAssertTrue(source.contains("event.title ?? \"\""), "Title is inspected locally only to classify an occasion.")
        XCTAssertTrue(source.contains("requestFullAccessToEvents()"))
        XCTAssertTrue(source.contains("EKEventStoreChanged" ) == false, "Refresh ownership is intentionally in HomeView, not the data boundary.")
    }

    func testCalendarClassifierSupportsSignificantEventsWithoutRetainingTitles() throws {
        let source = try calendarSource()
        for token in ["anniversary", "birthday", "holiday", "wedding", "concert", "appointment", "ceremony"] {
            XCTAssertTrue(source.contains("(\"\(token)\""), "Expected minimized category classifier for \(token).")
        }
        XCTAssertTrue(source.contains("event.endDate >= now"), "All-day events remain eligible while active.")
        XCTAssertTrue(source.contains("lookAheadDays = 21"), "Calendar relevance remains intentionally bounded for outfit preparation.")
        XCTAssertTrue(source.contains("otherSignificantEvent"), "A legitimate event must not disappear solely because it lacks a known keyword.")
        XCTAssertTrue(source.contains("event.hasRecurrenceRules"), "Recurring event occurrences remain visible as minimized context.")
    }

    func testCalendarClassifierKeepsUnrecognizedUpcomingEventsDistinctFromNoEvent() {
        XCTAssertEqual(CalendarContextSanitizer.classification(for: "Birthday dinner"), .categorized(.birthday))
        XCTAssertEqual(CalendarContextSanitizer.classification(for: "Team offsite"), .otherSignificantEvent)
        XCTAssertEqual(CalendarContextSanitizer.classification(for: "   "), .rejected(.blankTitle))
    }

    func testCalendarRuntimeDiagnosticsAreAggregateOnly() throws {
        let source = try calendarSource()
        XCTAssertTrue(source.contains("func runtimeDiagnostics"))
        XCTAssertTrue(source.contains("eventQueryState"))
        XCTAssertTrue(source.contains("eventCalendarsVisibleCount"))
        XCTAssertTrue(source.contains("rejectionReasonCounts"))
        XCTAssertFalse(source.contains("event.notes"))
        XCTAssertFalse(source.contains("event.location"))
        XCTAssertFalse(source.contains("event.url"))
        XCTAssertFalse(source.contains("event.eventIdentifier"))
    }

    func testNoCalendarReadOccursWhenConsentIsOff() {
        let suite = "CalendarContextServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let access = DeniedCalendarAccess()

        let fact = CalendarContextProvider.occasionFact(access: access, defaults: defaults, now: .now)
        XCTAssertFalse(access.didReadEvents)
        XCTAssertFalse(fact.isAvailable)
    }

    private func calendarSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent("StyleMatchAI/PersonalStylist/CalendarContextService.swift"),
            encoding: .utf8
        )
    }
}

private final class DeniedCalendarAccess: CalendarContextAccessing {
    var authorizationStatus: EKAuthorizationStatus { .denied }
    private(set) var didReadEvents = false

    func requestReadAccess() async throws -> Bool { false }
    func events(from start: Date, to end: Date) throws -> [EKEvent] {
        didReadEvents = true
        return []
    }
}
