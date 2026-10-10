import Foundation

enum LocalTimeBucket: String, Codable, CaseIterable, Sendable {
    case morning
    case afternoon
    case evening
    case night

    var greetingTitle: String {
        switch self {
        case .morning: "Morning"
        case .afternoon: "Afternoon"
        case .evening, .night: "Evening"
        }
    }

    var greetingLowercase: String {
        greetingTitle.lowercased()
    }
}

/// Permission-free device-local time information. This model intentionally contains no calendar-event data.
struct LocalDateContext: Equatable, Sendable {
    let referenceDate: Date
    let dateComponents: DateComponents
    let weekday: Int
    let localizedWeekdayName: String
    let localTime: Date
    let timeBucket: LocalTimeBucket
    let isWeekend: Bool
    let localeIdentifier: String
    let timeZoneIdentifier: String
    let utcOffsetSeconds: Int

    init(
        date: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale? = nil,
        timeZone: TimeZone? = nil
    ) {
        var localCalendar = calendar
        let resolvedLocale = locale ?? calendar.locale ?? .autoupdatingCurrent
        let resolvedTimeZone = timeZone ?? calendar.timeZone
        localCalendar.locale = resolvedLocale
        localCalendar.timeZone = resolvedTimeZone

        let components = localCalendar.dateComponents(
            [.calendar, .timeZone, .era, .year, .month, .day, .weekday, .hour, .minute, .second],
            from: date
        )
        let formatter = DateFormatter()
        formatter.calendar = localCalendar
        formatter.locale = resolvedLocale
        formatter.timeZone = resolvedTimeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEE")

        referenceDate = date
        dateComponents = components
        weekday = components.weekday ?? localCalendar.component(.weekday, from: date)
        localizedWeekdayName = formatter.string(from: date)
        localTime = date
        timeBucket = Self.bucket(hour: components.hour ?? localCalendar.component(.hour, from: date))
        isWeekend = localCalendar.isDateInWeekend(date)
        localeIdentifier = resolvedLocale.identifier
        timeZoneIdentifier = resolvedTimeZone.identifier
        utcOffsetSeconds = resolvedTimeZone.secondsFromGMT(for: date)
    }

    static func bucket(hour: Int) -> LocalTimeBucket {
        switch hour {
        case 5..<12: .morning
        case 12..<17: .afternoon
        case 17..<22: .evening
        default: .night
        }
    }
}

enum CalendarAwarenessState: String, Codable, CaseIterable, Sendable {
    case off
    case permissionRequired
    case on
    case denied
    case restricted
    case unavailable
    case noRelevantEvents
}

/// Stores only a user's Calendar Context consent/status. It never stores
/// calendar records, identifiers, or event-derived context.
enum CalendarAwarenessPreferenceStore {
    static let baseKey = "calendarAwarenessPreference"

    static func state(for userID: String, defaults: UserDefaults = .standard) -> CalendarAwarenessState {
        let key = PersonalStylistStorage.scopedKey(baseKey, userID: userID)
        guard let rawValue = defaults.string(forKey: key),
              let state = CalendarAwarenessState(rawValue: rawValue) else {
            return .off
        }
        return state
    }

    static func setFoundationEnabled(_ enabled: Bool, for userID: String, defaults: UserDefaults = .standard) {
        let state: CalendarAwarenessState = enabled ? .permissionRequired : .off
        set(state, for: userID, defaults: defaults)
    }

    static func set(_ state: CalendarAwarenessState, for userID: String, defaults: UserDefaults = .standard) {
        defaults.set(state.rawValue, forKey: PersonalStylistStorage.scopedKey(baseKey, userID: userID))
    }

    static func clear(for userID: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: PersonalStylistStorage.scopedKey(baseKey, userID: userID))
    }

    static func supportingText(for state: CalendarAwarenessState) -> String {
        switch state {
        case .off:
            "Use upcoming calendar events to improve outfit suggestions. Date and day awareness work without calendar access."
        case .permissionRequired:
            "Enable Calendar Context to let KigoStylist request read access only when you choose."
        case .on:
            "Calendar Context is enabled. Only a bounded, local occasion summary may inform outfit suggestions."
        case .denied, .restricted, .unavailable, .noRelevantEvents:
            "Calendar events are unavailable. KigoStylist can still use date and day awareness without calendar access."
        }
    }
}
