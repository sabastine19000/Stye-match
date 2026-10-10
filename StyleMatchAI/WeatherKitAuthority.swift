@preconcurrency import CoreLocation
import Foundation
import SwiftUI
import WeatherKit

/// Apple-supplied attribution is part of the weather fact, not optional view chrome.
/// A WeatherSnapshot cannot be created or persisted without this value.
struct WeatherAttributionMetadata: Codable, Equatable {
    let serviceName: String
    let combinedMarkLightURL: URL
    let combinedMarkDarkURL: URL
    let legalPageURL: URL
    /// Apple-provided legal wording for use when the legal page cannot be opened.
    let legalAttributionText: String

    var isUsable: Bool {
        !serviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && combinedMarkLightURL.scheme?.lowercased() == "https"
            && combinedMarkDarkURL.scheme?.lowercased() == "https"
            && legalPageURL.scheme?.lowercased() == "https"
    }

    init?(
        serviceName: String,
        combinedMarkLightURL: URL,
        combinedMarkDarkURL: URL,
        legalPageURL: URL,
        legalAttributionText: String
    ) {
        guard !serviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              combinedMarkLightURL.scheme?.lowercased() == "https",
              combinedMarkDarkURL.scheme?.lowercased() == "https",
              legalPageURL.scheme?.lowercased() == "https",
              !legalAttributionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        self.serviceName = serviceName
        self.combinedMarkLightURL = combinedMarkLightURL
        self.combinedMarkDarkURL = combinedMarkDarkURL
        self.legalPageURL = legalPageURL
        self.legalAttributionText = legalAttributionText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init?(_ attribution: WeatherKit.WeatherAttribution) {
        let legalAttributionText: String
        if #available(iOS 16.4, macOS 13.3, *) {
            legalAttributionText = attribution.legalAttributionText
        } else {
            // The legal wording is required when the legal page cannot open;
            // do not expose Apple Weather data on runtimes that cannot supply it.
            return nil
        }
        self.init(
            serviceName: attribution.serviceName,
            combinedMarkLightURL: attribution.combinedMarkLightURL,
            combinedMarkDarkURL: attribution.combinedMarkDarkURL,
            legalPageURL: attribution.legalPageURL,
            legalAttributionText: legalAttributionText
        )
    }

    func combinedMarkURL(for colorScheme: ColorScheme) -> URL {
        colorScheme == .dark ? combinedMarkDarkURL : combinedMarkLightURL
    }
}

/// Every surface that renders Apple Weather facts must be registered here and
/// use `WeatherKitAttributionView` (or `weatherAttributed`) with its surface.
/// This prevents future weather UI from silently introducing an unattributed
/// presentation path.
enum WeatherAttributionSurface: String, CaseIterable {
    case home
    case weatherStyling
    case hourlyForecast
    case tenDayForecast
    case scanWeatherGuidance
    case closetWeatherGuidance
    case aiWeatherStylist
    case weatherChat
}

/// Describes how a registered surface presents Apple Weather input. Direct
/// facts require the full Apple-provided mark and legal link. Derived styling
/// guidance also identifies that StyleMatch modified the underlying data.
enum WeatherAttributionPresentation {
    case direct
    case transformedGuidance
    case mixedFactsAndGuidance

    var includesModifiedDataNotice: Bool {
        self != .direct
    }
}

extension WeatherAttributionSurface {
    /// Direct forecast surfaces keep the complete Apple attribution. Surfaces
    /// that combine facts with StyleMatch styling output also disclose the
    /// transformation. This mapping is centralized so a future caller cannot
    /// accidentally omit the notice.
    var presentation: WeatherAttributionPresentation {
        switch self {
        case .home, .hourlyForecast, .tenDayForecast:
            return .direct
        case .weatherStyling, .scanWeatherGuidance, .closetWeatherGuidance,
             .aiWeatherStylist, .weatherChat:
            return .mixedFactsAndGuidance
        }
    }
}

/// The sole persisted authority for iOS displayed weather.
/// Do not add another weather provider or a snapshot initializer without attribution.
struct WeatherHourlyForecastEntry: Codable, Equatable, Identifiable {
    let date: Date
    let temperatureFahrenheit: Int
    let condition: String
    /// WeatherKit's own SF Symbol preserves the provider's daylight decision.
    /// The presentation layer must not infer a sun symbol from condition text.
    let symbolName: String?
    let precipitationProbabilityPercent: Int?

    var id: Date { date }

    init?(
        date: Date,
        temperatureFahrenheit: Int,
        condition: String,
        symbolName: String? = nil,
        precipitationProbabilityPercent: Int? = nil
    ) {
        let cleanedCondition = condition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedCondition.isEmpty else { return nil }
        self.date = date
        self.temperatureFahrenheit = temperatureFahrenheit
        self.condition = cleanedCondition
        self.symbolName = Self.clean(symbolName)
        self.precipitationProbabilityPercent = precipitationProbabilityPercent.map { min(max($0, 0), 100) }
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// The sole display authority for persisted hourly WeatherKit facts. Legacy
/// entries without a provider symbol fail neutrally rather than guessing sun.
enum WeatherHourlyPresentationAuthority {
    static func currentOrFuture(
        _ entries: [WeatherHourlyForecastEntry],
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> [WeatherHourlyForecastEntry] {
        let currentHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        return entries.sorted { $0.date < $1.date }.filter { $0.date >= currentHour }
    }

    static func symbolName(for entry: WeatherHourlyForecastEntry) -> String {
        entry.symbolName ?? "cloud.fill"
    }
}

/// Typed WeatherKit-derived daily entries. The snapshot owns the facts; views
/// may choose how many are visible but must never invent forecast rows.
struct WeatherDailyForecastEntry: Codable, Equatable, Identifiable {
    let date: Date
    let highTemperatureFahrenheit: Int
    let lowTemperatureFahrenheit: Int
    let condition: String
    let precipitationProbabilityPercent: Int?

    var id: Date { date }

    init?(
        date: Date,
        highTemperatureFahrenheit: Int,
        lowTemperatureFahrenheit: Int,
        condition: String,
        precipitationProbabilityPercent: Int? = nil
    ) {
        let cleanedCondition = condition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedCondition.isEmpty else { return nil }
        self.date = date
        self.highTemperatureFahrenheit = highTemperatureFahrenheit
        self.lowTemperatureFahrenheit = lowTemperatureFahrenheit
        self.condition = cleanedCondition
        self.precipitationProbabilityPercent = precipitationProbabilityPercent.map { min(max($0, 0), 100) }
    }

    /// Keeps WeatherKit-provided daily facts chronological and distinct without
    /// manufacturing rows to meet a presentation count.
    static func canonicalized(_ entries: [WeatherDailyForecastEntry], limit: Int = 10) -> [WeatherDailyForecastEntry] {
        guard limit > 0 else { return [] }
        var seenDates = Set<Date>()
        return entries
            .sorted { $0.date < $1.date }
            .filter { seenDates.insert($0.date).inserted }
            .prefix(limit)
            .map { $0 }
    }
}

struct WeatherSnapshot: Codable, Equatable {
    let observedAt: Date
    let locationName: String?
    let temperatureFahrenheit: Int
    let feelsLikeFahrenheit: Int
    let condition: String
    let currentSymbolName: String?
    /// WeatherKit CurrentWeather precipitation intensity. This is distinct from
    /// forecast probability and is the only authority for a rain-now claim.
    let currentPrecipitationIntensityKilometersPerHour: Double?
    let rainChancePercent: Int?
    let humidityPercent: Int?
    let windMph: Int?
    let windDirection: String?
    let uvIndex: Int?
    let hourlySummary: String?
    let dailySummary: String?
    /// Typed WeatherKit-derived entries. Older persisted snapshots decode to an empty list.
    let hourlyForecast: [WeatherHourlyForecastEntry]
    /// Typed WeatherKit-derived entries. Older persisted snapshots decode to an empty list.
    let dailyForecast: [WeatherDailyForecastEntry]
    let attribution: WeatherAttributionMetadata

    private enum CodingKeys: String, CodingKey {
        case observedAt, locationName, temperatureFahrenheit, feelsLikeFahrenheit
        case condition, currentSymbolName, currentPrecipitationIntensityKilometersPerHour, rainChancePercent, humidityPercent, windMph, windDirection, uvIndex
        case hourlySummary, dailySummary, hourlyForecast, dailyForecast, attribution
    }

    init?(
        observedAt: Date,
        locationName: String?,
        temperatureFahrenheit: Int,
        feelsLikeFahrenheit: Int,
        condition: String,
        currentSymbolName: String? = nil,
        currentPrecipitationIntensityKilometersPerHour: Double? = nil,
        rainChancePercent: Int?,
        humidityPercent: Int?,
        windMph: Int?,
        windDirection: String? = nil,
        uvIndex: Int?,
        hourlySummary: String?,
        dailySummary: String?,
        hourlyForecast: [WeatherHourlyForecastEntry] = [],
        dailyForecast: [WeatherDailyForecastEntry] = [],
        attribution: WeatherAttributionMetadata
    ) {
        guard attribution.isUsable,
              !condition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        self.observedAt = observedAt
        self.locationName = Self.clean(locationName)
        self.temperatureFahrenheit = temperatureFahrenheit
        self.feelsLikeFahrenheit = feelsLikeFahrenheit
        self.condition = condition.trimmingCharacters(in: .whitespacesAndNewlines)
        self.currentSymbolName = Self.clean(currentSymbolName)
        self.currentPrecipitationIntensityKilometersPerHour = currentPrecipitationIntensityKilometersPerHour.map { max(0, $0) }
        self.rainChancePercent = rainChancePercent
        self.humidityPercent = humidityPercent
        self.windMph = windMph
        self.windDirection = Self.clean(windDirection)
        self.uvIndex = uvIndex
        self.hourlySummary = Self.clean(hourlySummary)
        self.dailySummary = Self.clean(dailySummary)
        self.hourlyForecast = hourlyForecast
        self.dailyForecast = dailyForecast
        self.attribution = attribution
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        observedAt = try values.decode(Date.self, forKey: .observedAt)
        locationName = Self.clean(try values.decodeIfPresent(String.self, forKey: .locationName))
        temperatureFahrenheit = try values.decode(Int.self, forKey: .temperatureFahrenheit)
        feelsLikeFahrenheit = try values.decodeIfPresent(Int.self, forKey: .feelsLikeFahrenheit) ?? temperatureFahrenheit
        condition = try values.decode(String.self, forKey: .condition)
        currentSymbolName = Self.clean(try values.decodeIfPresent(String.self, forKey: .currentSymbolName))
        currentPrecipitationIntensityKilometersPerHour = try values.decodeIfPresent(Double.self, forKey: .currentPrecipitationIntensityKilometersPerHour).map { max(0, $0) }
        rainChancePercent = try values.decodeIfPresent(Int.self, forKey: .rainChancePercent)
        humidityPercent = try values.decodeIfPresent(Int.self, forKey: .humidityPercent)
        windMph = try values.decodeIfPresent(Int.self, forKey: .windMph)
        windDirection = Self.clean(try values.decodeIfPresent(String.self, forKey: .windDirection))
        uvIndex = try values.decodeIfPresent(Int.self, forKey: .uvIndex)
        hourlySummary = Self.clean(try values.decodeIfPresent(String.self, forKey: .hourlySummary))
        dailySummary = Self.clean(try values.decodeIfPresent(String.self, forKey: .dailySummary))
        hourlyForecast = try values.decodeIfPresent([WeatherHourlyForecastEntry].self, forKey: .hourlyForecast) ?? []
        dailyForecast = try values.decodeIfPresent([WeatherDailyForecastEntry].self, forKey: .dailyForecast) ?? []
        attribution = try values.decode(WeatherAttributionMetadata.self, forKey: .attribution)

        guard attribution.isUsable,
              !condition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .attribution, in: values, debugDescription: "Weather snapshots require usable attribution and a condition.")
        }
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Styling alerts are temporal facts, never reusable cached suggestions.
    func isFresh(at date: Date = Date(), maximumAge: TimeInterval = 90 * 60) -> Bool {
        date.timeIntervalSince(observedAt) >= 0 && date.timeIntervalSince(observedAt) <= maximumAge
    }

    /// Current precipitation is an observed WeatherKit fact when the current
    /// WeatherKit observation is fresh. `precipitationIntensity` is the
    /// authority for whether precipitation is occurring now; forecast chance
    /// and a condition icon must never replace it.
    func currentPrecipitationState(at now: Date = Date()) -> CurrentPrecipitationState {
        guard isFresh(at: now) else { return .unknown }
        guard let intensity = currentPrecipitationIntensityKilometersPerHour else { return .unknown }
        guard intensity > 0 else { return .none }
        let classified = CurrentPrecipitationState(condition: condition)
        return classified.isObserved ? classified : .precipitation
    }

    /// A concise user-facing observation that stays separate from the six-hour
    /// probability. WeatherKit may not expose a more specific type for every
    /// current condition, so generic precipitation is deliberately honest.
    var currentPrecipitationDisplayText: String {
        switch currentPrecipitationState() {
        case .none: return "None"
        case .rain: return "Rain \(formattedCurrentPrecipitationIntensity)"
        case .snow: return "Snow \(formattedCurrentPrecipitationIntensity)"
        case .sleetMixed: return "Mixed \(formattedCurrentPrecipitationIntensity)"
        case .precipitation: return "Precipitation \(formattedCurrentPrecipitationIntensity)"
        case .unknown: return "Unavailable"
        }
    }

    private var formattedCurrentPrecipitationIntensity: String {
        guard let intensity = currentPrecipitationIntensityKilometersPerHour else { return "" }
        return String(format: "%.2f km/h", intensity)
    }

    /// Compatibility convenience for presentation that needs any observed
    /// precipitation, never a forecast probability or stale observation.
    var hasCurrentPrecipitation: Bool { currentPrecipitationState().isObserved }
}

/// The sole current-observation authority shared by Home, Weather Styling,
/// scan context, and Stylist handoff. `unknown` is intentionally not treated
/// as rain, snow, or an umbrella requirement.
enum CurrentPrecipitationState: String, Equatable, Codable {
    case none
    case rain
    case snow
    case sleetMixed
    case precipitation
    case unknown

    init(condition: String) {
        let value = condition.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.contains("snow") || value.contains("blizzard") { self = .snow }
        else if value.contains("sleet") || value.contains("hail") || value.contains("freezing rain") || value.contains("ice pellet") || value.contains("wintry mix") { self = .sleetMixed }
        else if value.contains("rain") || value.contains("drizzle") || value.contains("shower") || value.contains("thunderstorm") || value.contains("tropical storm") { self = .rain }
        else { self = .unknown }
    }

    var isObserved: Bool { self == .rain || self == .snow || self == .sleetMixed || self == .precipitation }
}

enum FuturePrecipitationRisk: Equatable {
    case none
    case possible(WeatherHourlyForecastEntry)
    case imminent(WeatherHourlyForecastEntry)
}

@MainActor
final class WeatherKitAuthority: NSObject, ObservableObject {
    static let shared = WeatherKitAuthority()
    nonisolated static let snapshotKey = "weatherKitCanonicalSnapshot.v1"

    @Published private(set) var snapshot: WeatherSnapshot?
    /// Attribution is fetched independently of the forecast. This preserves
    /// Apple's supplied mark and legal link while a forecast is loading or
    /// unavailable, without fabricating an attribution asset.
    @Published private(set) var attribution: WeatherAttributionMetadata?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastErrorMessage: String?
    /// True only after this process receives a successful WeatherKit response.
    /// A snapshot decoded from persistence is deliberately not treated as live.
    @Published private(set) var hasLiveWeatherForCurrentSession = false

    private let defaults: UserDefaults
    private let locationManager: CLLocationManager
    private let geocoder = CLGeocoder()

    init(defaults: UserDefaults = .standard, locationManager: CLLocationManager = CLLocationManager()) {
        self.defaults = defaults
        self.locationManager = locationManager
        let restoredSnapshot = Self.loadSnapshot(defaults: defaults)
        snapshot = restoredSnapshot
        attribution = restoredSnapshot?.attribution
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        // Attribution has no location dependency. Start it independently so
        // the Apple mark and legal link can remain available while location or
        // forecast retrieval is loading, denied, or temporarily unavailable.
        Task { [weak self] in
            guard let self else { return }
            _ = try? await self.replaceAttribution(from: WeatherService.shared)
        }
    }

    nonisolated static func loadSnapshot(defaults: UserDefaults = .standard) -> WeatherSnapshot? {
        guard let data = defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(WeatherSnapshot.self, from: data),
              snapshot.attribution.isUsable,
              snapshot.isFresh() else {
            return nil
        }
        return snapshot
    }

    func refresh() {
        isRefreshing = true
        lastErrorMessage = nil
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.requestLocation()
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            fail("Allow location or choose a city to refresh WeatherKit weather.")
        @unknown default:
            fail("Weather is unavailable right now.")
        }
    }

    func refresh(city: String) {
        let trimmed = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            fail("Enter a city to refresh WeatherKit weather.")
            return
        }
        isRefreshing = true
        lastErrorMessage = nil
        Task {
            do {
                guard let location = try await geocoder.geocodeAddressString(trimmed).first?.location else {
                    throw CLError(.geocodeFoundNoResult)
                }
                try await replaceSnapshot(for: location, locationName: trimmed)
            } catch {
                fail("Weather is unavailable right now.")
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard isRefreshing else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        default:
            fail("Allow location or choose a city to refresh WeatherKit weather.")
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            fail("Weather is unavailable right now.")
            return
        }
        Task {
            let locationName = await resolvedCity(for: location)
            do {
                try await replaceSnapshot(for: location, locationName: locationName)
            } catch {
                fail("Weather is unavailable right now.")
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        fail("Weather is unavailable right now.")
    }

    private func replaceSnapshot(for location: CLLocation, locationName: String?) async throws {
        let service = WeatherService.shared
        // Do not couple attribution to forecast availability. App Review can
        // encounter a temporary network or location failure after the runtime
        // attribution endpoint has succeeded.
        let attributionMetadata = try await replaceAttribution(from: service)
        let weather = try await service.weather(for: location)
        let current = weather.currentWeather
        let now = Date()
        let currentHour = Calendar.autoupdatingCurrent.dateInterval(of: .hour, for: now)?.start ?? now
        let hourlyForecast = WeatherHourlyPresentationAuthority.currentOrFuture(
            weather.hourlyForecast.compactMap { hour in
                WeatherHourlyForecastEntry(
                    date: hour.date,
                    temperatureFahrenheit: Int(hour.temperature.converted(to: .fahrenheit).value.rounded()),
                    condition: hour.condition.description.capitalized,
                    symbolName: hour.symbolName,
                    precipitationProbabilityPercent: Int((hour.precipitationChance * 100).rounded())
                )
            },
            now: now
        )
        let hourly = hourlyForecast.prefix(4).map {
            "\($0.temperatureFahrenheit)°F"
        }.joined(separator: " • ")
        let dailyForecast = WeatherDailyForecastEntry.canonicalized(weather.dailyForecast.compactMap { day in
            WeatherDailyForecastEntry(
                date: day.date,
                highTemperatureFahrenheit: Int(day.highTemperature.converted(to: .fahrenheit).value.rounded()),
                lowTemperatureFahrenheit: Int(day.lowTemperature.converted(to: .fahrenheit).value.rounded()),
                condition: day.condition.description.capitalized,
                precipitationProbabilityPercent: Int((day.precipitationChance * 100).rounded())
            )
        })
        let daily = weather.dailyForecast.first.map {
            "Today: high \(Int($0.highTemperature.converted(to: .fahrenheit).value.rounded()))°F, low \(Int($0.lowTemperature.converted(to: .fahrenheit).value.rounded()))°F"
        }
        guard let snapshot = WeatherSnapshot(
            observedAt: Date(),
            locationName: locationName,
            temperatureFahrenheit: Int(current.temperature.converted(to: .fahrenheit).value.rounded()),
            feelsLikeFahrenheit: Int(current.apparentTemperature.converted(to: .fahrenheit).value.rounded()),
            condition: current.condition.description.capitalized,
            currentSymbolName: current.symbolName,
            currentPrecipitationIntensityKilometersPerHour: current.precipitationIntensity
                .converted(to: .kilometersPerHour)
                .value,
            rainChancePercent: weather.hourlyForecast
                .sorted { $0.date < $1.date }
                .filter { $0.date >= currentHour }
                .prefix(6)
                .map { Int(($0.precipitationChance * 100).rounded()) }
                .max(),
            humidityPercent: Int((current.humidity * 100).rounded()),
            windMph: Int(current.wind.speed.converted(to: .milesPerHour).value.rounded()),
            windDirection: current.wind.compassDirection.abbreviation,
            uvIndex: current.uvIndex.value,
            hourlySummary: hourly,
            dailySummary: daily,
            hourlyForecast: hourlyForecast,
            dailyForecast: dailyForecast,
            attribution: attributionMetadata
        ) else {
            fail("Weather attribution is unavailable.")
            return
        }
        guard let data = try? JSONEncoder().encode(snapshot) else {
            fail("Weather could not be saved safely.")
            return
        }
        defaults.set(data, forKey: Self.snapshotKey)
        self.snapshot = snapshot
        hasLiveWeatherForCurrentSession = true
        isRefreshing = false
        lastErrorMessage = nil
    }

    /// Stores only Apple-provided attribution that was returned by the current
    /// WeatherKit runtime. The persisted snapshot is accepted for at most the
    /// snapshot freshness interval, so StyleMatch never permanently bundles or
    /// reconstructs an Apple mark or legal URL.
    private func replaceAttribution(from service: WeatherService) async throws -> WeatherAttributionMetadata {
        let runtimeAttribution = try await service.attribution
        guard let metadata = WeatherAttributionMetadata(runtimeAttribution) else {
            throw URLError(.cannotParseResponse)
        }
        attribution = metadata
        return metadata
    }

    private func resolvedCity(for location: CLLocation) async -> String? {
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else { return nil }
        return placemark.locality ?? placemark.subAdministrativeArea ?? placemark.administrativeArea
    }

    private func fail(_ message: String) {
        isRefreshing = false
        lastErrorMessage = message
    }
}

extension WeatherKitAuthority: @preconcurrency CLLocationManagerDelegate {}

/// The single precipitation recommendation authority used by Weather Styling
/// and the Stylist. It consumes only WeatherKit facts already preserved in a
/// WeatherSnapshot; it does not infer precipitation from cloud cover.
enum WeatherUmbrellaAdvisory: String, Equatable, Codable {
    case none
    case possibleLater
    case imminent
    case rainingNow
    case snowingNow
    case mixedPrecipitationNow
    case hazardousPrecipitation

    static let nearTermHorizon: TimeInterval = 4 * 60 * 60
    static let meaningfulProbability = 40
    static func make(snapshot: WeatherSnapshot?, now: Date = Date()) -> Self {
        guard let snapshot, snapshot.isFresh(at: now) else { return .none }
        switch snapshot.currentPrecipitationState(at: now) {
        case .rain: return .rainingNow
        case .snow: return .snowingNow
        case .sleetMixed: return .mixedPrecipitationNow
        case .none, .precipitation, .unknown: break
        }
        if isThunderstormRiskCondition(snapshot.condition) { return .hazardousPrecipitation }
        switch futurePrecipitationRisk(in: snapshot) {
        case .none: return .none
        case .imminent: return .imminent
        case .possible: return .possibleLater
        }
    }

    static func nextRelevantPrecipitation(in snapshot: WeatherSnapshot) -> WeatherHourlyForecastEntry? {
        let end = snapshot.observedAt.addingTimeInterval(nearTermHorizon)
        return snapshot.hourlyForecast.filter { entry in
            entry.date >= snapshot.observedAt && entry.date <= end &&
            ((entry.precipitationProbabilityPercent ?? 0) >= meaningfulProbability ||
             (entry.precipitationProbabilityPercent == nil && (isCurrentRainCondition(entry.condition) || isThunderstormRiskCondition(entry.condition))))
        }.sorted { $0.date < $1.date }.first
    }

    static func futurePrecipitationRisk(in snapshot: WeatherSnapshot) -> FuturePrecipitationRisk {
        guard let next = nextRelevantPrecipitation(in: snapshot) else { return .none }
        return next.date <= snapshot.observedAt.addingTimeInterval(60 * 60) ? .imminent(next) : .possible(next)
    }

    func guidance(for currentCondition: String) -> String? {
        switch self {
        case .none: return nil
        case .possibleLater, .imminent: return nil
        case .rainingNow:
            switch Self.normalized(currentCondition) {
            case "drizzle", "freezing drizzle": return "It’s drizzling now — grab an umbrella or light rain protection."
            case "freezing rain": return "Freezing rain is occurring now. Use appropriate rain and slip protection, and follow local safety guidance."
            default: return "It’s raining now — grab an umbrella before you head out."
            }
        case .snowingNow:
            return "Snow is occurring now. Use weather-appropriate layers and footwear with traction."
        case .mixedPrecipitationNow:
            return "Mixed precipitation is occurring now. Use weather-appropriate protection and footwear with traction."
        case .hazardousPrecipitation:
            let condition = Self.normalized(currentCondition)
            if condition.contains("thunderstorm") { return "Thunderstorms are possible nearby. Consider rain protection and follow local safety guidance." }
            return "Hazardous precipitation is possible nearby. Consider rain protection and follow local safety guidance."
        }
    }

    func guidance(for snapshot: WeatherSnapshot, locale: Locale = .current) -> String? {
        guard let current = guidance(for: snapshot.condition) else {
            guard let entry = Self.nextRelevantPrecipitation(in: snapshot) else { return nil }
            let time = DateFormatter.localizedString(from: entry.date, dateStyle: .none, timeStyle: .short)
            let probability = entry.precipitationProbabilityPercent.map { " · \($0)%" } ?? ""
            return self == .imminent ? "Rain is possible around \(time)\(probability). Consider taking an umbrella." : "Rain is possible around \(time)\(probability). Consider taking an umbrella if you’ll still be out then."
        }
        return current
    }

    var guidance: String? { guidance(for: "") }

    var eventKey: String? { self == .none ? nil : rawValue }
    var requiresRainProtection: Bool { self != .none }
    var isImmediateCurrentPrecipitation: Bool {
        self == .rainingNow || self == .snowingNow || self == .mixedPrecipitationNow
    }

    private static func isCurrentRainCondition(_ value: String) -> Bool {
        switch normalized(value) {
        case "rain", "heavy rain", "drizzle", "freezing drizzle", "freezing rain", "sun showers", "showers": return true
        default: return false
        }
    }

    private static func isThunderstormRiskCondition(_ value: String) -> Bool {
        let condition = normalized(value)
        return condition.contains("thunderstorm") || condition == "tropical storm" || condition == "hurricane"
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct GlobalWeatherAlert: Equatable {
    enum Kind: Equatable { case none, currentRain, currentDrizzle, currentFreezingPrecipitation, currentSnow, currentMixedPrecipitation, thunderstormRisk, forecastRainSoon }
    let kind: Kind
    let message: String?
    static func make(snapshot: WeatherSnapshot?) -> Self {
        let advisory = WeatherUmbrellaAdvisory.make(snapshot: snapshot)
        guard let snapshot, let message = advisory.guidance(for: snapshot) else { return Self(kind: .none, message: nil) }
        let condition = snapshot.condition.lowercased()
        let kind: Kind
        if advisory == .hazardousPrecipitation && condition.contains("thunderstorm") { kind = .thunderstormRisk }
        else if advisory == .snowingNow { kind = .currentSnow }
        else if advisory == .mixedPrecipitationNow { kind = .currentMixedPrecipitation }
        else if condition.contains("freezing") { kind = .currentFreezingPrecipitation }
        else if condition.contains("drizzle") { kind = .currentDrizzle }
        else if advisory == .rainingNow { kind = .currentRain }
        else { kind = .forecastRainSoon }
        return Self(kind: kind, message: message)
    }
}

/// Durable event deduplication for an eventual in-app/local-notification
/// presenter. No timer is used: a repeated active condition is suppressed,
/// dry weather clears the event, and a later rain event can be presented.
final class WeatherUmbrellaAlertEventStore {
    private struct State: Codable { var activeEventKey: String? }
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "weatherUmbrellaAlertEvent.v1") {
        self.defaults = defaults
        self.key = key
    }

    func shouldPresent(for advisory: WeatherUmbrellaAdvisory) -> Bool {
        var state = load()
        guard let eventKey = advisory.eventKey else {
            state.activeEventKey = nil
            save(state)
            return false
        }
        guard state.activeEventKey != eventKey else { return false }
        state.activeEventKey = eventKey
        save(state)
        return true
    }

    private func load() -> State {
        guard let data = defaults.data(forKey: key), let state = try? JSONDecoder().decode(State.self, from: data) else { return State(activeEventKey: nil) }
        return state
    }

    private func save(_ state: State) {
        defaults.set(try? JSONEncoder().encode(state), forKey: key)
    }
}

/// Visual state is derived from the same canonical current WeatherKit
/// condition and umbrella authority. It is intentionally unavailable for
/// cached/non-live snapshots so a saved condition is never animated as now.
enum WeatherCurrentConditionVisualState: Equatable {
    case none
    case rain
    case drizzle
    case thunderstorm
    /// A current WeatherKit storm condition without current precipitation.
    /// This supports a risk cue but never rain particles or rain-now wording.
    case thunderstormRisk
    case snow
    case clear
    case cloudy
    case fog

    static func make(snapshot: WeatherSnapshot?, hasLiveWeather: Bool) -> Self {
        guard hasLiveWeather, let snapshot else { return .none }
        let condition = snapshot.condition.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // `hasLiveWeather` is set only after this process receives a current
        // WeatherKit response.  Derive animation from that response's own
        // observation time so testable rendering does not reclassify a live
        // response as stale merely because a later UI pass occurs.
        let currentPrecipitation = snapshot.currentPrecipitationState(at: snapshot.observedAt)
        if condition.contains("thunderstorm") {
            return currentPrecipitation == .rain ? .thunderstorm : .thunderstormRisk
        }
        if condition.contains("snow") || condition.contains("blizzard") { return .snow }
        if currentPrecipitation == .rain && (condition == "drizzle" || condition == "freezing drizzle") { return .drizzle }
        if currentPrecipitation == .snow || currentPrecipitation == .sleetMixed { return .snow }
        if currentPrecipitation == .rain { return .rain }
        if condition.contains("fog") || condition.contains("haze") { return .fog }
        if condition.contains("clear") || condition.contains("sunny") { return .clear }
        if condition.contains("cloud") || condition.contains("overcast") { return .cloudy }
        return .none
    }
}

enum WeatherConditionAnimationPolicy {
    static func continuousMotionEnabled(
        for state: WeatherCurrentConditionVisualState,
        reduceMotion: Bool
    ) -> Bool {
        guard !reduceMotion else { return false }
        return [.rain, .drizzle, .thunderstorm, .snow].contains(state)
    }
}

struct WeatherKitAttributionView: View {
    let attribution: WeatherAttributionMetadata
    let surface: WeatherAttributionSurface
    let presentation: WeatherAttributionPresentation
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @State private var showsLegalFallback = false

    init(
        attribution: WeatherAttributionMetadata,
        surface: WeatherAttributionSurface,
        presentation: WeatherAttributionPresentation? = nil
    ) {
        self.attribution = attribution
        self.surface = surface
        self.presentation = presentation ?? surface.presentation
    }

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: attribution.combinedMarkURL(for: colorScheme)) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 112, maxHeight: 24, alignment: .leading)
                }
            }
            .accessibilityLabel("Apple Weather attribution mark")
            Button("Legal") {
                openURL(attribution.legalPageURL) { accepted in
                    if !accepted {
                        showsLegalFallback = true
                    }
                }
            }
                .font(.caption)
                .accessibilityLabel("Apple Weather legal attribution")
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Weather data attribution: \(attribution.serviceName)")
        .accessibilityIdentifier("weather-attribution-\(surface.rawValue)")
        .safeAreaInset(edge: .top, spacing: 0) {
            if presentation.includesModifiedDataNotice {
                Text("Apple Weather data has been modified by KigoStylist to create this styling guidance.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .accessibilityLabel("Apple Weather data has been modified by KigoStylist to create this styling guidance.")
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial)
            }
        }
        .alert("Weather data sources", isPresented: $showsLegalFallback) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(attribution.legalAttributionText)
        }
    }
}

extension View {
    /// Apply this to a surface that visibly renders a WeatherSnapshot.
    func weatherAttributed(
        _ attribution: WeatherAttributionMetadata,
        surface: WeatherAttributionSurface,
        presentation: WeatherAttributionPresentation? = nil
    ) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            WeatherKitAttributionView(attribution: attribution, surface: surface, presentation: presentation)
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
        }
    }
}

struct WeatherAttributionIfAvailable: ViewModifier {
    let attribution: WeatherAttributionMetadata?
    let surface: WeatherAttributionSurface

    @ViewBuilder
    func body(content: Content) -> some View {
        if let attribution {
            content.weatherAttributed(attribution, surface: surface)
        } else {
            EmptyView()
        }
    }
}
