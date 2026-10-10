import Combine
import CryptoKit
import XCTest
@testable import StyleMatchPro

private func projectSource(_ relativePath: String, filePath: String = #filePath) throws -> String {
    let root = URL(fileURLWithPath: filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let url = root.appendingPathComponent(relativePath)
    return try String(contentsOf: url, encoding: .utf8)
}

// Synthetic attribution is confined to the test bundle. Production metadata
// must carry Apple-provided legal wording so the UI can fail closed.
extension WeatherAttributionMetadata {
    init?(
        serviceName: String,
        combinedMarkLightURL: URL,
        combinedMarkDarkURL: URL,
        legalPageURL: URL
    ) {
        self.init(
            serviceName: serviceName,
            combinedMarkLightURL: combinedMarkLightURL,
            combinedMarkDarkURL: combinedMarkDarkURL,
            legalPageURL: legalPageURL,
            legalAttributionText: "Test-only legal attribution."
        )
    }
}

final class SecurityInputBoundsTests: XCTestCase {
    func testSharedInputBoundsTrimWithoutDamagingUnicode() {
        let value = "  café 👔  "
        XCTAssertEqual(StyleMatchInputBounds.profileFreeText(value), "café 👔")
        XCTAssertEqual(StyleMatchInputBounds.scanTitle(value), "café 👔")
        XCTAssertEqual(StyleMatchInputBounds.shoppingQuery(value), "café 👔")
    }

    func testSharedInputBoundsTruncateAtCharacterBoundary() {
        let emoji = String(repeating: "👔", count: 100)
        let bounded = StyleMatchInputBounds.trimmedAndBounded(emoji, maximumUTF16Length: 3)
        XCTAssertEqual(bounded, "👔")
        XCTAssertLessThanOrEqual(bounded.utf16.count, 3)
    }

    func testSharedInputBoundsLimitPersistenceAndRetailerRequestInputs() throws {
        XCTAssertEqual(
            StyleMatchInputBounds.scanTitle(String(repeating: "S", count: 500)).utf16.count,
            StyleMatchInputBounds.scanTitleMaximumUTF16Length
        )
        XCTAssertEqual(
            StyleMatchInputBounds.profileFreeText(String(repeating: "P", count: 1_000)).utf16.count,
            StyleMatchInputBounds.profileFreeTextMaximumUTF16Length
        )
        XCTAssertEqual(
            StyleMatchInputBounds.shoppingQuery(String(repeating: "Q", count: 1_000)).utf16.count,
            StyleMatchInputBounds.shoppingQueryMaximumUTF16Length
        )

        let profileSource = try projectSource("StyleMatchAI/ProfileView.swift")
        let scanSource = try projectSource("StyleMatchAI/ScanView.swift")
        let retailerSource = try projectSource("StyleMatchAI/Shopping/ShoppingSearchProviders.swift")
        XCTAssertTrue(profileSource.contains("StyleMatchInputBounds.profileFreeText(newValue)"))
        XCTAssertTrue(profileSource.contains("StyleMatchInputBounds.profileFreeText(text)"))
        XCTAssertTrue(scanSource.contains("StyleMatchInputBounds.scanTitle(renameText)"))
        XCTAssertTrue(retailerSource.contains("value.map(StyleMatchInputBounds.shoppingQuery)"))
    }

    private func projectSource(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
}

private func weatherStylistRouteSnapshot(
    rainChancePercent: Int? = 45,
    humidityPercent: Int? = 72,
    windMph: Int? = 12,
    uvIndex: Int? = 7
) throws -> WeatherSnapshot {
    let attribution = try XCTUnwrap(WeatherAttributionMetadata(
        serviceName: "Apple Weather",
        combinedMarkLightURL: try XCTUnwrap(URL(string: "https://example.com/light")),
        combinedMarkDarkURL: try XCTUnwrap(URL(string: "https://example.com/dark")),
        legalPageURL: try XCTUnwrap(URL(string: "https://example.com/legal"))
    ))
    return try XCTUnwrap(WeatherSnapshot(
        observedAt: Date(),
        locationName: "West Point",
        temperatureFahrenheit: 75,
        feelsLikeFahrenheit: 78,
        condition: "Mostly Clear",
        rainChancePercent: rainChancePercent,
        humidityPercent: humidityPercent,
        windMph: windMph,
        windDirection: "SSE",
        uvIndex: uvIndex,
        hourlySummary: nil,
        dailySummary: nil,
        attribution: attribution
    ))
}

extension StyleMatchProPhase2Tests {
    func testCompareStylistRouteWaitsForCompareSheetDismissalBeforeRootPresentation() throws {
        let scanSource = try projectSource("StyleMatchAI/ScanView.swift")
        let contentSource = try projectSource("StyleMatchAI/ContentView.swift")

        XCTAssertTrue(scanSource.contains(".sheet(item: $comparePresentation, onDismiss: resumePendingCompareStylistRoute)"))
        XCTAssertTrue(scanSource.contains("pendingCompareStylistRequest = request"))
        XCTAssertTrue(scanSource.contains("comparePresentation = nil"))
        XCTAssertTrue(scanSource.contains("DispatchQueue.main.async"))
        XCTAssertTrue(scanSource.contains("onOpenStylistComparison(request)"))
        XCTAssertTrue(contentSource.contains("openCompareStylistConversation"))
        XCTAssertTrue(contentSource.contains("publishScanComparison"))
        XCTAssertTrue(contentSource.contains("stylistOverlaySession.presentScreenAwareness(snapshot)"))
    }

    func testWeatherStylingRoutesIntoExistingTypedStylistContext() throws {
        let weather = try weatherStylistRouteSnapshot()
        let recommendation = WeatherStylingRecommendation.make(
            snapshot: weather,
            occasion: "Work",
            favoriteColors: "Navy",
            workplace: "Factory"
        )
        let request = WeatherStylistRouteRequest(
            snapshot: weather,
            recommendation: recommendation,
            occasion: "Work",
            workplace: "Factory"
        )

        var coordinator = StylistAwarenessCoordinator()
        let route = coordinator.publishWeatherStyling(request)
        let context = route.requestContext

        XCTAssertEqual(route.kind, .weatherStyling)
        XCTAssertEqual(route.screenContext.currentTab, .weather)
        XCTAssertEqual(route.screenContext.entryPoint, .weatherStyling)
        XCTAssertEqual(route.screenContext.surface?.screenKind, .weather)
        XCTAssertEqual(route.selectedOccasion, "Work")
        XCTAssertTrue(context.weatherConstraint.contains("West Point"))
        XCTAssertTrue(context.weatherConstraint.contains("75°F"))
        XCTAssertTrue(context.weatherConstraint.contains("Feels like: 78°F"))
        XCTAssertTrue(context.weatherConstraint.contains("Precipitation chance: 45%"))
        XCTAssertTrue(context.weatherConstraint.contains("Work context: Factory"))
        XCTAssertTrue(context.recentOutfits.contains("Safety-toe or slip-resistant footwear"))
        XCTAssertNil(route.localReference)
        XCTAssertNil(context.aiMemoryResolution)
        XCTAssertEqual(coordinator.snapshot, route)
        XCTAssertEqual(coordinator.generation, route.generation)
    }

    func testWeatherStylingRouteOmitsMissingOptionalWeatherFactsAndClosetClaims() throws {
        let weather = try weatherStylistRouteSnapshot(
            rainChancePercent: nil,
            humidityPercent: nil,
            windMph: nil,
            uvIndex: nil
        )
        let recommendation = WeatherStylingRecommendation.make(snapshot: weather, occasion: "", favoriteColors: "")
        let route = ScreenAwarenessSnapshot.weatherStyling(
            WeatherStylistRouteRequest(
                snapshot: weather,
                recommendation: recommendation,
                occasion: "",
                workplace: ""
            ),
            generation: 4
        )

        XCTAssertTrue(route.requestContext.weatherConstraint.contains("Current weather: 75°F"))
        XCTAssertFalse(route.requestContext.weatherConstraint.contains("Precipitation chance:"))
        XCTAssertFalse(route.requestContext.weatherConstraint.contains("Humidity:"))
        XCTAssertFalse(route.requestContext.weatherConstraint.contains("Wind:"))
        XCTAssertFalse(route.requestContext.weatherConstraint.contains("UV:"))
        XCTAssertFalse(route.customerVisibleFacts.joined(separator: " ").localizedCaseInsensitiveContains("closet ownership"))
        XCTAssertFalse(route.customerVisibleFacts.joined(separator: " ").localizedCaseInsensitiveContains("owned"))
    }

    @MainActor
    func testWeatherStylingUsesTheExistingOverlayConversationWithoutAIMemoryState() throws {
        let weather = try weatherStylistRouteSnapshot()
        let request = WeatherStylistRouteRequest(
            snapshot: weather,
            recommendation: WeatherStylingRecommendation.make(snapshot: weather, occasion: "Work", favoriteColors: ""),
            occasion: "Work",
            workplace: ""
        )
        let route = ScreenAwarenessSnapshot.weatherStyling(request, generation: 8)
        let service = StylistChatService()
        let overlay = StylistOverlaySessionCoordinator(service: service)

        overlay.presentScreenAwareness(route)

        XCTAssertTrue(overlay.service === service)
        XCTAssertTrue(overlay.usesScreenAwareness)
        XCTAssertEqual(overlay.route, .screenAwareness(generation: 8, reference: nil))
        XCTAssertEqual(service.activeConversation.scope, .contextualStylist)
        XCTAssertNil(route.requestContext.aiMemoryResolution)
    }

    func testWeatherStylingRoutePreservesPrivacyConsentAndRoutingBoundaries() throws {
        let contentSource = try projectSource("StyleMatchAI/ContentView.swift")
        let presentationSource = try projectSource("StyleMatchAI/WeatherStylingPresentation.swift")

        XCTAssertTrue(contentSource.contains("WeatherStylistRouteAction"))
        XCTAssertTrue(contentSource.contains("openWeatherStylistConversation"))
        XCTAssertTrue(contentSource.contains("publishWeatherStyling"))
        XCTAssertTrue(contentSource.contains("View recommendation details"))
        XCTAssertFalse(presentationSource.contains("CloudSync"))
        XCTAssertFalse(presentationSource.contains("AIMemory"))
        XCTAssertFalse(presentationSource.contains("OpenAI"))
        XCTAssertFalse(presentationSource.localizedCaseInsensitiveContains("consent"))
    }

    func testWeatherKitSnapshotPersistsAttributionWithWeatherFacts() throws {
        let attribution = try XCTUnwrap(WeatherAttributionMetadata(
            serviceName: "Apple Weather",
            combinedMarkLightURL: try XCTUnwrap(URL(string: "https://example.com/light")),
            combinedMarkDarkURL: try XCTUnwrap(URL(string: "https://example.com/dark")),
            legalPageURL: try XCTUnwrap(URL(string: "https://example.com/legal")),
            legalAttributionText: "Apple Weather legal attribution"
        ))
        let snapshot = try XCTUnwrap(WeatherSnapshot(
            observedAt: Date(),
            locationName: "Test City",
            temperatureFahrenheit: 68,
            feelsLikeFahrenheit: 67,
            condition: "Clear",
            rainChancePercent: 10,
            humidityPercent: 45,
            windMph: 6,
            uvIndex: 3,
            hourlySummary: "68°F",
            dailySummary: "Today",
            attribution: attribution
        ))

        defaults.set(try JSONEncoder().encode(snapshot), forKey: WeatherKitAuthority.snapshotKey)

        XCTAssertEqual(WeatherKitAuthority.loadSnapshot(defaults: defaults), snapshot)
        XCTAssertEqual(
            AIStylistContextSelection.weatherConstraint(defaults: defaults),
            AIStylistContextSelection.weatherConstraint(fahrenheit: 67, condition: "Clear")
        )
    }

    func testWeatherSnapshotPersistsTypedHourlyForecastWithAttribution() throws {
        let attribution = try XCTUnwrap(WeatherAttributionMetadata(
            serviceName: "Apple Weather",
            combinedMarkLightURL: try XCTUnwrap(URL(string: "https://example.com/light")),
            combinedMarkDarkURL: try XCTUnwrap(URL(string: "https://example.com/dark")),
            legalPageURL: try XCTUnwrap(URL(string: "https://example.com/legal"))
        ))
        let hour = try XCTUnwrap(WeatherHourlyForecastEntry(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            temperatureFahrenheit: 68,
            condition: "Partly Cloudy"
        ))
        let snapshot = try XCTUnwrap(WeatherSnapshot(
            observedAt: Date(timeIntervalSince1970: 1_700_000_000),
            locationName: "Test City",
            temperatureFahrenheit: 68,
            feelsLikeFahrenheit: 67,
            condition: "Clear",
            rainChancePercent: 10,
            humidityPercent: 45,
            windMph: 6,
            uvIndex: 3,
            hourlySummary: "68°F",
            dailySummary: "Today",
            hourlyForecast: [hour],
            attribution: attribution
        ))

        let decoded = try JSONDecoder().decode(WeatherSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded.hourlyForecast, [hour])
        XCTAssertEqual(decoded.attribution, attribution)
    }

    func testHourlyPresentationExcludesPastEntriesAtCurrentHourBoundaryAndKeepsMidnightOrder() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 13, hour: 15, minute: 23)))
        let entries = try [
            WeatherHourlyForecastEntry(date: now.addingTimeInterval(-17 * 60 * 60), temperatureFahrenheit: 70, condition: "Clear", symbolName: "sun.max.fill"),
            WeatherHourlyForecastEntry(date: now.addingTimeInterval(-60 * 60), temperatureFahrenheit: 70, condition: "Clear", symbolName: "sun.max.fill"),
            WeatherHourlyForecastEntry(date: now.addingTimeInterval(-23 * 60), temperatureFahrenheit: 70, condition: "Clear", symbolName: "sun.max.fill"),
            WeatherHourlyForecastEntry(date: now.addingTimeInterval(37 * 60), temperatureFahrenheit: 69, condition: "Clear", symbolName: "sun.max.fill"),
            WeatherHourlyForecastEntry(date: now.addingTimeInterval(9 * 60 * 60), temperatureFahrenheit: 65, condition: "Clear", symbolName: "moon.stars.fill"),
            WeatherHourlyForecastEntry(date: now.addingTimeInterval(10 * 60 * 60), temperatureFahrenheit: 63, condition: "Mostly Clear", symbolName: "moon.stars.fill")
        ].map { try XCTUnwrap($0) }

        let displayed = WeatherHourlyPresentationAuthority.currentOrFuture(entries, now: now, calendar: calendar)
        let currentHour = try XCTUnwrap(calendar.dateInterval(of: .hour, for: now)?.start)

        XCTAssertEqual(displayed.map(\.date), displayed.map(\.date).sorted())
        XCTAssertTrue(displayed.allSatisfy { $0.date >= currentHour })
        XCTAssertFalse(displayed.contains { $0.date < now.addingTimeInterval(-23 * 60) })
        XCTAssertEqual(displayed.map(\.symbolName), ["sun.max.fill", "sun.max.fill", "moon.stars.fill", "moon.stars.fill"])
    }

    func testHourlyPresentationKeepsProviderNightSymbolAndLegacyClearFailsNeutral() throws {
        let night = try XCTUnwrap(WeatherHourlyForecastEntry(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            temperatureFahrenheit: 64,
            condition: "Mostly Clear",
            symbolName: "moon.stars.fill"
        ))
        let legacyClear = try XCTUnwrap(WeatherHourlyForecastEntry(
            date: Date(timeIntervalSince1970: 1_700_003_600),
            temperatureFahrenheit: 65,
            condition: "Clear"
        ))

        XCTAssertEqual(WeatherHourlyPresentationAuthority.symbolName(for: night), "moon.stars.fill")
        XCTAssertEqual(WeatherHourlyPresentationAuthority.symbolName(for: legacyClear), "cloud.fill")
    }

    func testFullForecastUsesCanonicalHourlyAuthorityAdaptiveDailyRowsAndAttribution() throws {
        let source = try projectSource("StyleMatchAI/ContentView.swift")
        let authority = try projectSource("StyleMatchAI/WeatherKitAuthority.swift")

        XCTAssertTrue(source.contains("WeatherHourlyPresentationAuthority.currentOrFuture(weatherAuthority.snapshot?.hourlyForecast ?? [])"))
        XCTAssertTrue(source.contains("Image(systemName: WeatherHourlyPresentationAuthority.symbolName(for: hour))"))
        XCTAssertTrue(source.contains("private func dailyForecastRow(_ day: WeatherDailyForecastEntry)"))
        XCTAssertFalse(source.contains(".lineLimit(1)\n                                Spacer()\n                                VStack(alignment: .trailing"))
        XCTAssertTrue(source.contains("WeatherAttributionIfAvailable(attribution: weatherAuthority.attribution, surface:"))
        XCTAssertTrue(authority.contains("func weatherAttributed(\n        _ attribution: WeatherAttributionMetadata,\n        surface: WeatherAttributionSurface,"))
        XCTAssertTrue(authority.contains("openURL(attribution.legalPageURL)"))
    }

    func testStyleFriendsSignedOutStateUsesTheCentralProfileRecoveryPath() throws {
        let source = try projectSource("StyleMatchAI/StyleFriendsView.swift")
        let chatSource = try projectSource("StyleMatchAI/StyleFriendsChatUI.swift")

        XCTAssertTrue(source.contains("case .signInRequired:\n                StyleFriendsSignInCard(onReconnect: openAccountProfile)"))
        XCTAssertTrue(source.contains("Reconnect using the same Apple account to reload your friends and conversations."))
        XCTAssertTrue(source.contains("Button(\"Reconnect Account\", action: onReconnect)"))
        XCTAssertTrue(source.contains("dismiss()\n        DispatchQueue.main.async"))
        XCTAssertTrue(source.contains("StyleMatchAccountSessionStore.profileReconnectRequestedNotification"))
        XCTAssertFalse(source.contains("SignInWithAppleButton(.continue)"))
        XCTAssertTrue(chatSource.contains("StyleMatchSessionRecoveryCopy.title"))
        XCTAssertTrue(chatSource.contains("StyleMatchSessionRecoveryCopy.actionTitle"))
        XCTAssertFalse(chatSource.contains("Reconnect KigoStylist in Profile"))
        XCTAssertFalse(chatSource.contains("SignInWithAppleButton(.continue)"))
    }

    func testWeatherSnapshotPersistsTypedDailyForecastWithAttribution() throws {
        let attribution = try XCTUnwrap(WeatherAttributionMetadata(
            serviceName: "Apple Weather",
            combinedMarkLightURL: try XCTUnwrap(URL(string: "https://example.com/light")),
            combinedMarkDarkURL: try XCTUnwrap(URL(string: "https://example.com/dark")),
            legalPageURL: try XCTUnwrap(URL(string: "https://example.com/legal"))
        ))
        let day = try XCTUnwrap(WeatherDailyForecastEntry(
            date: Date(timeIntervalSince1970: 1_700_086_400),
            highTemperatureFahrenheit: 78,
            lowTemperatureFahrenheit: 62,
            condition: "Partly Cloudy"
        ))
        let snapshot = try XCTUnwrap(WeatherSnapshot(
            observedAt: Date(timeIntervalSince1970: 1_700_000_000), locationName: "Test City",
            temperatureFahrenheit: 68, feelsLikeFahrenheit: 67, condition: "Clear",
            rainChancePercent: 10, humidityPercent: 45, windMph: 6, uvIndex: 3,
            hourlySummary: "68°F", dailySummary: "Today", dailyForecast: [day], attribution: attribution
        ))
        XCTAssertEqual(try JSONDecoder().decode(WeatherSnapshot.self, from: JSONEncoder().encode(snapshot)).dailyForecast, [day])
    }

    func testDailyForecastCanonicalizationKeepsTenDistinctChronologicalWeatherKitDays() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = try (0..<10).reversed().map { offset in
            try XCTUnwrap(WeatherDailyForecastEntry(
                date: start.addingTimeInterval(TimeInterval(offset * 86_400)),
                highTemperatureFahrenheit: 80 + offset,
                lowTemperatureFahrenheit: 60 + offset,
                condition: "Clear",
                precipitationProbabilityPercent: offset
            ))
        }

        let canonical = WeatherDailyForecastEntry.canonicalized(entries)

        XCTAssertEqual(canonical.count, 10)
        XCTAssertEqual(canonical.map(\.date), canonical.map(\.date).sorted())
        XCTAssertEqual(Set(canonical.map(\.id)).count, 10)
        XCTAssertEqual(canonical.map(\.precipitationProbabilityPercent), Array(0..<10))
    }

    func testDailyForecastCanonicalizationNeverFabricatesDaysWhenWeatherKitHasFewerEntries() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = try (0..<3).map { offset in
            try XCTUnwrap(WeatherDailyForecastEntry(
                date: start.addingTimeInterval(TimeInterval(offset * 86_400)),
                highTemperatureFahrenheit: 75,
                lowTemperatureFahrenheit: 60,
                condition: "Cloudy"
            ))
        }

        let canonical = WeatherDailyForecastEntry.canonicalized(entries)

        XCTAssertEqual(canonical, entries)
        XCTAssertEqual(canonical.count, 3)
    }

    func testWeatherSnapshotBackwardDecodesWithoutTypedHourlyForecast() throws {
        let attribution = try XCTUnwrap(WeatherAttributionMetadata(
            serviceName: "Apple Weather",
            combinedMarkLightURL: try XCTUnwrap(URL(string: "https://example.com/light")),
            combinedMarkDarkURL: try XCTUnwrap(URL(string: "https://example.com/dark")),
            legalPageURL: try XCTUnwrap(URL(string: "https://example.com/legal"))
        ))
        let snapshot = try XCTUnwrap(WeatherSnapshot(
            observedAt: Date(timeIntervalSince1970: 1_700_000_000),
            locationName: "Test City",
            temperatureFahrenheit: 68,
            feelsLikeFahrenheit: 67,
            condition: "Clear",
            rainChancePercent: 10,
            humidityPercent: 45,
            windMph: 6,
            uvIndex: 3,
            hourlySummary: "68°F",
            dailySummary: "Today",
            attribution: attribution
        ))
        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any]
        )
        legacyObject.removeValue(forKey: "hourlyForecast")
        legacyObject.removeValue(forKey: "dailyForecast")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)

        XCTAssertEqual(try JSONDecoder().decode(WeatherSnapshot.self, from: legacyData).hourlyForecast, [])
        XCTAssertEqual(try JSONDecoder().decode(WeatherSnapshot.self, from: legacyData).dailyForecast, [])
    }

    func testWeatherStylingPanelUsesTypedHourlyForecastAndCanonicalRefreshContract() throws {
        let source = try projectSource("StyleMatchAI/ContentView.swift")
        let authoritySource = try projectSource("StyleMatchAI/WeatherKitAuthority.swift")
        let forecastStart = try XCTUnwrap(source.range(of: "private var forecastCard"))
        let dailyStart = try XCTUnwrap(source.range(of: "private var dailyForecastCard", range: forecastStart.upperBound..<source.endIndex))
        let forecastCardSource = String(source[forecastStart.lowerBound..<dailyStart.lowerBound])

        XCTAssertTrue(source.contains("weatherAuthority.snapshot?.hourlyForecast"))
        XCTAssertTrue(source.contains("ForEach(weatherHourlyEntries)"))
        XCTAssertTrue(source.contains("weatherAuthority.refresh()"))
        XCTAssertTrue(source.contains("Live Weather"))
        XCTAssertTrue(source.contains("Updating Live Weather…"))
        XCTAssertTrue(source.contains("Saved Weather"))
        XCTAssertTrue(source.contains("weatherAuthority.hasLiveWeatherForCurrentSession"))
        XCTAssertTrue(source.contains("snapshot.windDirection"))
        XCTAssertTrue(source.contains("uvSeverity(for: index)"))
        XCTAssertTrue(source.contains("Text(\"Weather Match\")"))
        XCTAssertTrue(source.contains("ViewThatFits(in: .horizontal)"))
        XCTAssertTrue(source.contains("recommendationHeaderStacked"))
        XCTAssertTrue(source.contains("fixedSize(horizontal: false, vertical: true)"))
        XCTAssertTrue(source.contains("private var weatherTabPicker"))
        XCTAssertTrue(source.contains("WeatherStylingTab.allCases"))
        XCTAssertTrue(source.contains("private var currentWeatherCard"))
        XCTAssertTrue(source.contains("weatherMetric(\"Feels Like\""))
        XCTAssertTrue(source.contains("weatherMetric(\"Precipitation Now\""))
        XCTAssertTrue(source.contains("weatherMetric(\"Rain Chance (Next 6h)\""))
        XCTAssertTrue(source.contains("weatherMetric(\"Humidity\""))
        XCTAssertTrue(source.contains("weatherMetric(\"Wind\""))
        XCTAssertTrue(source.contains("weatherMetric(\"UV Index\""))
        XCTAssertTrue(source.contains("weatherMetric(\"Updated\""))
        XCTAssertTrue(source.contains("WeatherPremiumAtmosphere"))
        XCTAssertTrue(source.contains("WeatherPremiumPrecipitationLayer"))
        XCTAssertTrue(source.contains("WeatherPrecipitationCanvas(kind: kind, isActive: isActive, depth: .background)"))
        XCTAssertTrue(source.contains("WeatherConditionAnimationPolicy.continuousMotionEnabled"))
        XCTAssertTrue(source.contains("weatherPrecipitationSummary"))
        XCTAssertTrue(source.contains("dailyTemperatureRangeBar(for: day)"))
        XCTAssertTrue(source.contains("WeatherKitAttributionView(attribution: attribution, surface: .weatherStyling)"))
        XCTAssertTrue(source.contains("@State private var showsManualCityControls = false"))
        XCTAssertTrue(source.contains("if showsManualCityControls"))
        XCTAssertTrue(source.contains("ScrollView(.horizontal, showsIndicators: false)"))
        XCTAssertTrue(source.contains("View Full Hourly"))
        XCTAssertTrue(source.contains("Image(systemName: \"chevron.right\")"))
        XCTAssertTrue(source.contains("destination = .hourly"))
        XCTAssertTrue(source.contains("accessibilityLabel(\"View full hourly forecast\")"))
        XCTAssertTrue(source.contains("dailyForecastActionTitle"))
        XCTAssertTrue(source.contains("dailyForecastDestinationTitle"))
        XCTAssertTrue(source.contains("destination = .daily"))
        XCTAssertTrue(source.contains("Section(dailyForecastDestinationTitle)"))
        XCTAssertTrue(source.contains("precipitationProbabilityPercent"))
        XCTAssertTrue(source.contains("ForEach(Array(weatherDailyEntries.prefix(5)))"))
        XCTAssertTrue(source.contains("ForEach(recommendationPreviewItems)"))
        XCTAssertTrue(source.contains("let previewRoles = [\"Top\", \"Bottom\", \"Shoes\"]"))
        XCTAssertTrue(source.contains("weatherRecommendation.personalizationTier.rawValue"))
        XCTAssertFalse(source.contains("DisclosureGroup(\"Why this works\")"))
        XCTAssertTrue(authoritySource.contains("WeatherDailyForecastEntry.canonicalized"))
        XCTAssertTrue(source.contains("private var recommendationDetailButton"))
        XCTAssertTrue(source.contains("View recommendation details"))
        XCTAssertTrue(source.contains("private var changeCityCard"))
        XCTAssertTrue(source.contains("WeatherStylingTab"))
        XCTAssertFalse(source.contains("Label(\"Swipe\", systemImage: \"hand.point.right\")"))
        XCTAssertFalse(forecastCardSource.localizedCaseInsensitiveContains("swipe"))
        XCTAssertFalse(source.contains("LinearGradient(\n                        colors: [.clear, Color(.systemBackground).opacity(0.9)]"))
        XCTAssertTrue(source.contains("WeatherKitAttributionView(attribution: attribution, surface: .weatherStyling)"))
        XCTAssertTrue(source.contains("weatherStateLabel"))
        XCTAssertFalse(source.contains("weatherHourlyForecast"))
        XCTAssertTrue(authoritySource.contains("hasLiveWeatherForCurrentSession = true"))
        XCTAssertTrue(authoritySource.contains("current.precipitationIntensity"))
        XCTAssertTrue(authoritySource.contains("var hasCurrentPrecipitation"))
        XCTAssertTrue(authoritySource.contains("windDirection: current.wind.compassDirection.abbreviation"))
        XCTAssertTrue(authoritySource.contains("A snapshot decoded from persistence is deliberately not treated as live."))
    }

    func testWeatherStylingRecommendationUsesActualPrecipitationAndNeverInventsAnUmbrella() throws {
        let attribution = try XCTUnwrap(WeatherAttributionMetadata(
            serviceName: "Apple Weather",
            combinedMarkLightURL: try XCTUnwrap(URL(string: "https://example.com/light")),
            combinedMarkDarkURL: try XCTUnwrap(URL(string: "https://example.com/dark")),
            legalPageURL: try XCTUnwrap(URL(string: "https://example.com/legal"))
        ))
        let dry = try XCTUnwrap(WeatherSnapshot(
            observedAt: Date(), locationName: "Test City", temperatureFahrenheit: 76,
            feelsLikeFahrenheit: 78, condition: "Mostly Clear", rainChancePercent: 5,
            humidityPercent: 45, windMph: 4, uvIndex: 4, hourlySummary: nil,
            dailySummary: nil, attribution: attribution
        ))
        let futureRain = try XCTUnwrap(WeatherHourlyForecastEntry(
            date: Date().addingTimeInterval(90 * 60), temperatureFahrenheit: 70,
            condition: "Rain", precipitationProbabilityPercent: 55
        ))
        let wet = try XCTUnwrap(WeatherSnapshot(
            observedAt: Date(), locationName: "Test City", temperatureFahrenheit: 70,
            feelsLikeFahrenheit: 70, condition: "Cloudy", rainChancePercent: 55,
            humidityPercent: 60, windMph: 8, uvIndex: 2, hourlySummary: nil,
            dailySummary: nil, hourlyForecast: [futureRain], attribution: attribution
        ))

        XCTAssertNil(WeatherStylingRecommendation.make(snapshot: dry, occasion: "Work", favoriteColors: "navy").umbrellaGuidance)
        XCTAssertNotNil(WeatherStylingRecommendation.make(snapshot: wet, occasion: "Work", favoriteColors: "navy").umbrellaGuidance)
    }

    func testWeatherStylingRecommendationFailsClosedWithoutCompleteScoreInputs() throws {
        let attribution = try XCTUnwrap(WeatherAttributionMetadata(
            serviceName: "Apple Weather",
            combinedMarkLightURL: try XCTUnwrap(URL(string: "https://example.com/light")),
            combinedMarkDarkURL: try XCTUnwrap(URL(string: "https://example.com/dark")),
            legalPageURL: try XCTUnwrap(URL(string: "https://example.com/legal"))
        ))
        let incomplete = try XCTUnwrap(WeatherSnapshot(
            observedAt: Date(), locationName: "Test City", temperatureFahrenheit: 70,
            feelsLikeFahrenheit: 70, condition: "Clear", rainChancePercent: nil,
            humidityPercent: nil, windMph: nil, uvIndex: nil, hourlySummary: nil,
            dailySummary: nil, attribution: attribution
        ))
        let recommendation = WeatherStylingRecommendation.make(snapshot: incomplete, occasion: "", favoriteColors: "")
        XCTAssertNil(recommendation.weatherMatchScore)
        XCTAssertEqual(recommendation.weatherMatchLabel, "Strong Weather Match")
        XCTAssertTrue(recommendation.items.allSatisfy { $0.source == .generalRecommendation })
    }

    func testWeatherStylingUsesVerifiedClosetEvidenceAndDiffersAcrossUsers() throws {
        let weather = try makePersonalizationWeather()
        let classic = WeatherStylingPersonalizationInput(
            accountID: "synthetic-classic",
            favoriteColors: ["navy"], favoriteBrands: [], styleGoals: ["classic"], learnedPreferences: [],
            preferredFit: "tailored", workContext: "office work", clothingSizes: ["M", "32", "10"],
            closetItems: [
                makeClosetItem("Navy Polo", "Top", "Navy", "M", "Work"),
                makeClosetItem("Khaki Chinos", "Bottom", "Khaki", "32", "Work"),
                makeClosetItem("Brown Loafers", "Shoes", "Brown", "10", "Work")
            ]
        )
        let athletic = WeatherStylingPersonalizationInput(
            accountID: "synthetic-athletic",
            favoriteColors: ["black", "gray"], favoriteBrands: [], styleGoals: ["athletic"], learnedPreferences: [],
            preferredFit: "relaxed", workContext: "gym", clothingSizes: ["L", "34", "11"],
            closetItems: [
                makeClosetItem("Black Performance Tee", "Top", "Black", "L", "Workout"),
                makeClosetItem("Gray Joggers", "Bottom", "Gray", "34", "Workout"),
                makeClosetItem("Running Sneakers", "Shoes", "Gray", "11", "Workout")
            ]
        )

        let classicRecommendation = WeatherStylingRecommendation.make(snapshot: weather, occasion: "Work", personalization: classic)
        let athleticRecommendation = WeatherStylingRecommendation.make(snapshot: weather, occasion: "Work", personalization: athletic)

        XCTAssertEqual(classicRecommendation.personalizationTier, .closet)
        XCTAssertEqual(athleticRecommendation.personalizationTier, .closet)
        XCTAssertTrue(classicRecommendation.items.prefix(3).allSatisfy { $0.source == .closetItem })
        XCTAssertTrue(athleticRecommendation.items.prefix(3).allSatisfy { $0.source == .closetItem })
        XCTAssertNotEqual(classicRecommendation.items.prefix(3).map(\.title), athleticRecommendation.items.prefix(3).map(\.title))
        XCTAssertTrue(classicRecommendation.items.contains { $0.title.localizedCaseInsensitiveContains("Navy Polo") })
        XCTAssertFalse(classicRecommendation.items.contains { $0.title.localizedCaseInsensitiveContains("Performance Tee") })
    }

    func testWeatherStylingUsesProfileThenTruthfulGeneralFallback() throws {
        let weather = try makePersonalizationWeather()
        let profileOnly = WeatherStylingPersonalizationInput(
            accountID: "profile-only", favoriteColors: ["navy"], favoriteBrands: ["Example Brand"],
            styleGoals: ["classic"], learnedPreferences: [], preferredFit: "tailored", workContext: "office work",
            clothingSizes: ["M"], closetItems: []
        )
        let noPersonalData = WeatherStylingPersonalizationInput(
            accountID: "guest", favoriteColors: [], favoriteBrands: [], styleGoals: [], learnedPreferences: [],
            preferredFit: nil, workContext: nil, clothingSizes: [], closetItems: []
        )

        let profileRecommendation = WeatherStylingRecommendation.make(snapshot: weather, occasion: "Work", personalization: profileOnly)
        let generalRecommendation = WeatherStylingRecommendation.make(snapshot: weather, occasion: "Work", personalization: noPersonalData)

        XCTAssertEqual(profileRecommendation.personalizationTier, .profile)
        XCTAssertTrue(profileRecommendation.items.prefix(3).allSatisfy { $0.source == .styleProfile })
        XCTAssertTrue(profileRecommendation.personalizationExplanation.contains("style profile"))
        XCTAssertEqual(generalRecommendation.personalizationTier, .general)
        XCTAssertTrue(generalRecommendation.items.prefix(3).allSatisfy { $0.source == .generalRecommendation })
        XCTAssertTrue(generalRecommendation.personalizationExplanation.contains("No verified Closet"))
    }

    func testWeatherStylingSavedScanEvidenceIsRelevantDeterministicAndDoesNotClaimOwnership() throws {
        let weather = try makePersonalizationWeather(rainChance: 3, condition: "Thunderstorms")
        let input = WeatherStylingPersonalizationInput(
            accountID: "saved-scan-user", favoriteColors: ["red"], favoriteBrands: [], styleGoals: [], learnedPreferences: [],
            preferredFit: "tailored", workContext: "office work", clothingSizes: [], closetItems: [],
            savedScans: [
                makeSavedScan(id: "date-night-99", score: 99, items: ["blouse", "skirt", "heels"], colors: ["red"], occasion: "Date Night"),
                makeSavedScan(id: "work-88", score: 88, items: ["polo", "chinos", "boots"], colors: ["navy"], occasion: "Work")
            ]
        )

        let first = WeatherStylingRecommendation.make(snapshot: weather, occasion: "Work", personalization: input)
        let second = WeatherStylingRecommendation.make(snapshot: weather, occasion: "Work", personalization: input)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.personalizationTier, .savedScan)
        XCTAssertTrue(first.items.prefix(3).allSatisfy { $0.source == .savedScan })
        XCTAssertTrue(first.items.contains { $0.title.localizedCaseInsensitiveContains("navy polo") })
        XCTAssertFalse(first.items.contains { $0.title.localizedCaseInsensitiveContains("heels") || $0.title.localizedCaseInsensitiveContains("skirt") })
        XCTAssertTrue(first.personalizationExplanation.contains("does not claim"))
        XCTAssertFalse(first.items.contains { $0.source == .closetItem })
        XCTAssertEqual(first.umbrellaGuidance, "Thunderstorms are possible nearby. Consider rain protection and follow local safety guidance.")
    }

    func testWeatherStylingClosetOutranksSavedScanAndWorkPPEOverridesSavedFootwear() throws {
        let weather = try makePersonalizationWeather(rainChance: 3, condition: "Thunderstorms")
        let savedWorkLook = makeSavedScan(id: "casual", score: 95, items: ["tee", "jeans", "sneakers"], colors: ["blue"], occasion: "Work")
        let ppeFallback = WeatherStylingPersonalizationInput(
            accountID: "ppe-scan", favoriteColors: ["blue"], favoriteBrands: [], styleGoals: [], learnedPreferences: [],
            preferredFit: nil, workContext: "Factory PPE required", clothingSizes: [], closetItems: [], savedScans: [savedWorkLook]
        )
        let ppeRecommendation = WeatherStylingRecommendation.make(snapshot: weather, occasion: "Work", personalization: ppeFallback)
        XCTAssertEqual(ppeRecommendation.personalizationTier, .savedScan)
        XCTAssertTrue(ppeRecommendation.items.contains { $0.role == "Shoes" && $0.title.contains("Safety-toe") })
        XCTAssertTrue(ppeRecommendation.reasoning.contains { $0.contains("safety footwear") })

        let closet = WeatherStylingPersonalizationInput(
            accountID: "closet-first", favoriteColors: [], favoriteBrands: [], styleGoals: [], learnedPreferences: [],
            preferredFit: nil, workContext: "office work", clothingSizes: [],
            closetItems: [
                makeClosetItem("Navy Polo", "Top", "Navy", "M", "Work"),
                makeClosetItem("Khaki Chinos", "Bottom", "Khaki", "32", "Work"),
                makeClosetItem("Brown Loafers", "Shoes", "Brown", "10", "Work")
            ], savedScans: [savedWorkLook]
        )
        let closetRecommendation = WeatherStylingRecommendation.make(snapshot: weather, occasion: "Work", personalization: closet)
        XCTAssertEqual(closetRecommendation.personalizationTier, .closet)
        XCTAssertTrue(closetRecommendation.items.prefix(3).allSatisfy { $0.source == .closetItem })
    }

    func testWeatherStylingMalformedClosetDoesNotClaimOwnershipAndRainStaysWeatherBound() throws {
        let dry = try makePersonalizationWeather(rainChance: 0, condition: "Clear")
        let wet = try makePersonalizationWeather(rainChance: 70, condition: "Rain", currentPrecipitationIntensityKilometersPerHour: 1)
        let incompleteCloset = WeatherStylingPersonalizationInput(
            accountID: "stale-closet", favoriteColors: [], favoriteBrands: [], styleGoals: [], learnedPreferences: [],
            preferredFit: nil, workContext: nil, clothingSizes: [],
            closetItems: [makeClosetItem("Only Top", "Top", "Blue", "M", "Work")]
        )
        let dryRecommendation = WeatherStylingRecommendation.make(snapshot: dry, occasion: "Work", personalization: incompleteCloset)
        let wetRecommendation = WeatherStylingRecommendation.make(snapshot: wet, occasion: "Work", personalization: incompleteCloset)

        XCTAssertEqual(dryRecommendation.personalizationTier, .general)
        XCTAssertFalse(dryRecommendation.items.contains { $0.source == .closetItem })
        XCTAssertNil(dryRecommendation.umbrellaGuidance)
        XCTAssertNotNil(wetRecommendation.umbrellaGuidance)
    }

    func testWeatherStylingAppliesSavedWorkPPEWithoutClaimingUnverifiedOwnership() throws {
        let weather = try makePersonalizationWeather()
        let profile = WeatherStylingPersonalizationInput(
            accountID: "ppe-profile", favoriteColors: ["blue"], favoriteBrands: [],
            styleGoals: [], learnedPreferences: [], preferredFit: nil,
            workContext: "Factory PPE required", clothingSizes: [], closetItems: []
        )

        let recommendation = WeatherStylingRecommendation.make(snapshot: weather, occasion: "Work", personalization: profile)

        XCTAssertEqual(recommendation.personalizationTier, .profile)
        XCTAssertTrue(recommendation.items.contains { $0.role == "Shoes" && $0.title.contains("Safety-toe") })
        XCTAssertFalse(recommendation.items.contains { $0.source == .closetItem })
        XCTAssertTrue(recommendation.reasoning.contains { $0.contains("safety footwear") })
    }

    func testWeatherContextDoesNotReadLegacySharedWeatherKeys() {
        defaults.set("96°F", forKey: "weather")
        defaults.set("Hot", forKey: "weatherCondition")

        XCTAssertEqual(AIStylistContextSelection.weatherConstraint(defaults: defaults), "")
    }

    func testWeatherSnapshotFailsClosedWithoutUsableAttribution() throws {
        XCTAssertNil(WeatherAttributionMetadata(
            serviceName: "",
            combinedMarkLightURL: try XCTUnwrap(URL(string: "https://example.com/light")),
            combinedMarkDarkURL: try XCTUnwrap(URL(string: "https://example.com/dark")),
            legalPageURL: try XCTUnwrap(URL(string: "https://example.com/legal"))
        ))
    }

    func testProductionWeatherSurfacesUseCanonicalAuthorityAndAttribution() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appRoot = root.appendingPathComponent("StyleMatchAI", isDirectory: true)
        let sourceFiles = [
            "WeatherKitAuthority.swift",
            "ContentView.swift",
            "HomeView.swift",
            "ScanView.swift",
            "ClosetView.swift",
            "AIAssistantsView.swift",
            "ProfileView.swift"
        ]

        let combined = try sourceFiles
            .map { try String(contentsOf: appRoot.appendingPathComponent($0), encoding: .utf8) }
            .joined(separator: "\n")
            .lowercased()

        XCTAssertFalse(combined.contains("open-" + "meteo"))
        XCTAssertTrue(combined.contains("weatherkitauthority"))
        XCTAssertTrue(combined.contains("weatherattributionifavailable"))
        XCTAssertTrue(combined.contains("weatherattributed"))
    }

    func testWeatherServiceIsConfinedToCanonicalAuthority() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appRoot = root.appendingPathComponent("StyleMatchAI", isDirectory: true)
        let swiftFiles = try XCTUnwrap(
            FileManager.default.enumerator(
                at: appRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )?.allObjects as? [URL]
        ).filter { $0.pathExtension == "swift" }

        let sourceFiles = try swiftFiles.map { url in
            (url, try String(contentsOf: url, encoding: .utf8))
        }
        let offenders = sourceFiles
            .filter { $0.0.lastPathComponent != "WeatherKitAuthority.swift" && $0.1.contains("Weather" + "Service") }
            .map(\.0)

        XCTAssertTrue(offenders.isEmpty, "WeatherService must be confined to WeatherKitAuthority: \(offenders.map(\.lastPathComponent))")
    }

    func testProductionWeatherHasNoLegacyParallelChannel() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appRoot = root.appendingPathComponent("StyleMatchAI", isDirectory: true)
        let swiftFiles = try XCTUnwrap(
            FileManager.default.enumerator(
                at: appRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )?.allObjects as? [URL]
        ).filter { $0.pathExtension == "swift" }

        let offenders = try swiftFiles
            .filter { try String(contentsOf: $0, encoding: .utf8).contains("legacy" + "Weather") }
            .map(\.lastPathComponent)

        XCTAssertTrue(offenders.isEmpty, "Legacy weather must not re-enter production source: \(offenders)")
    }

    func testPersonalStylistWeatherAdviceUsesCanonicalSnapshotOnly() throws {
        let scanSource = try projectSource("StyleMatchAI/ScanView.swift")
        let engineSource = try projectSource("StyleMatchAI/PersonalStylist/PersonalStylistEngine.swift")
        let advisorSource = try projectSource("StyleMatchAI/PersonalStylist/WeatherAdvisor.swift")

        XCTAssertTrue(scanSource.contains("guard let snapshot = weatherAuthority.snapshot else"))
        XCTAssertTrue(scanSource.contains("))?.attributed(to: snapshot)"))
        XCTAssertFalse(scanSource.contains("legacy" + "Weather:"))
        XCTAssertFalse(engineSource.contains("WeatherContext" + "Recommendation"))
        XCTAssertTrue(advisorSource.contains("let attribution: WeatherAttributionMetadata?"))
    }

    func testKnownWeatherPresentationSurfacesCarrySharedAttribution() throws {
        let presentationSurfaces = [
            "ContentView.swift",
            "HomeView.swift",
            "ScanView.swift",
            "ClosetView.swift",
            "AIAssistantsView.swift",
            "StylistChat/StylistChatView.swift"
        ]

        for surface in presentationSurfaces {
            let source = try projectSource("StyleMatchAI/\(surface)")
            XCTAssertTrue(
                source.contains("WeatherAttributionIfAvailable")
                    || source.contains("weatherAttributed")
                    || source.contains("WeatherKitAttributionView"),
                "\(surface) presents WeatherKit-derived values without the shared attribution contract"
            )
        }
    }

    func testWeatherAttributionMetadataPreservesWeatherKitRuntimeURLs() throws {
        let authoritySource = try projectSource("StyleMatchAI/WeatherKitAuthority.swift")

        XCTAssertTrue(authoritySource.contains("init?(_ attribution: WeatherKit.WeatherAttribution)"))
        XCTAssertTrue(authoritySource.contains("combinedMarkLightURL: attribution.combinedMarkLightURL"))
        XCTAssertTrue(authoritySource.contains("combinedMarkDarkURL: attribution.combinedMarkDarkURL"))
        XCTAssertTrue(authoritySource.contains("legalPageURL: attribution.legalPageURL"))
        XCTAssertTrue(authoritySource.contains("legalAttributionText = attribution.legalAttributionText"))
        XCTAssertTrue(authoritySource.contains("let service = WeatherService.shared"))
    }

    func testOfficialWeatherAttributionComponentUsesOnlyRuntimeMarkAndLegalURLs() throws {
        let authoritySource = try projectSource("StyleMatchAI/WeatherKitAuthority.swift")

        XCTAssertTrue(authoritySource.contains("combinedMarkURL(for colorScheme: ColorScheme)"))
        XCTAssertTrue(authoritySource.contains("combinedMarkDarkURL : combinedMarkLightURL"))
        XCTAssertTrue(authoritySource.contains("AsyncImage(url: attribution.combinedMarkURL(for: colorScheme))"))
        XCTAssertTrue(authoritySource.contains("openURL(attribution.legalPageURL)"))
        XCTAssertTrue(authoritySource.contains("Text(attribution.legalAttributionText)"))
        XCTAssertTrue(authoritySource.contains("showsLegalFallback = true"))
        XCTAssertTrue(authoritySource.contains("enum WeatherAttributionPresentation"))
        XCTAssertTrue(authoritySource.contains("Apple Weather data has been modified by KigoStylist to create this styling guidance."))
        XCTAssertTrue(authoritySource.contains("EmptyView()"))
        XCTAssertFalse(authoritySource.contains("else {\n            content\n        }"))
        XCTAssertTrue(authoritySource.contains("Apple Weather attribution mark"))
        XCTAssertTrue(authoritySource.contains("Apple Weather legal attribution"))
        XCTAssertTrue(authoritySource.contains("@Published private(set) var attribution: WeatherAttributionMetadata?"))
        XCTAssertTrue(authoritySource.contains("let attributionMetadata = try await replaceAttribution(from: service)"))
        XCTAssertTrue(authoritySource.contains("let weather = try await service.weather(for: location)"))
        XCTAssertTrue(authoritySource.contains("snapshot.isFresh()"))
        XCTAssertFalse(authoritySource.contains("BackendSession"))
        XCTAssertFalse(authoritySource.contains("SignInWithApple"))
        XCTAssertFalse(authoritySource.contains("Text(attribution.serviceName)"))
        XCTAssertFalse(authoritySource.contains("apple.logo"))
    }

    func testWeatherAttributionIsIndependentOfForecastAndFailsClosedWithoutRuntimeMetadata() throws {
        let authoritySource = try projectSource("StyleMatchAI/WeatherKitAuthority.swift")
        let contentSource = try projectSource("StyleMatchAI/ContentView.swift")

        XCTAssertTrue(authoritySource.contains("Task { [weak self] in"))
        XCTAssertTrue(authoritySource.contains("replaceAttribution(from: WeatherService.shared)"))
        XCTAssertTrue(contentSource.contains("if let attribution = weatherAuthority.attribution"))
        XCTAssertTrue(authoritySource.contains("if let attribution {\n            content.weatherAttributed"))
        XCTAssertTrue(authoritySource.contains("else {\n            EmptyView()"))
        XCTAssertTrue(contentSource.contains(".fixedSize(horizontal: false, vertical: true)"))
        XCTAssertTrue(contentSource.contains(".layoutPriority(1)"))
    }

    func testRegisteredWeatherSurfacesUseTheSharedOfficialAttributionContract() throws {
        let authoritySource = try projectSource("StyleMatchAI/WeatherKitAuthority.swift")
        let expectedSurfaces = [
            "case home",
            "case weatherStyling",
            "case hourlyForecast",
            "case tenDayForecast",
            "case scanWeatherGuidance",
            "case closetWeatherGuidance",
            "case aiWeatherStylist",
            "case weatherChat"
        ]
        expectedSurfaces.forEach { XCTAssertTrue(authoritySource.contains($0), "Missing registered WeatherKit surface: \($0)") }

        let expectedUseSites: [(String, String)] = [
            ("HomeView.swift", "surface: .home"),
            ("ContentView.swift", "surface: .weatherStyling"),
            ("ContentView.swift", "destination == .hourly ? .hourlyForecast"),
            ("ContentView.swift", "destination == .daily ? .tenDayForecast"),
            ("ScanView.swift", "surface: .scanWeatherGuidance"),
            ("ClosetView.swift", "surface: .closetWeatherGuidance"),
            ("AIAssistantsView.swift", "surface: .aiWeatherStylist"),
            ("StylistChat/StylistChatView.swift", "surface: .weatherChat")
        ]
        for (path, marker) in expectedUseSites {
            let source = try projectSource("StyleMatchAI/\(path)")
            XCTAssertTrue(source.contains(marker), "Missing attribution surface marker \(marker) in \(path)")
        }
    }

    func testChatRetainsAttributionWhenCanonicalWeatherContextIsAttached() throws {
        let serviceSource = try projectSource("StyleMatchAI/StylistChat/StylistChatService.swift")
        let messageSource = try projectSource("StyleMatchAI/StylistChat/StylistChatModels.swift")
        let viewSource = try projectSource("StyleMatchAI/StylistChat/StylistChatView.swift")

        XCTAssertTrue(serviceSource.contains("WeatherKitAuthority.loadSnapshot"))
        XCTAssertTrue(messageSource.contains("weatherAttribution: WeatherAttributionMetadata?"))
        XCTAssertTrue(viewSource.contains("surface: .weatherChat"))
        let authoritySource = try projectSource("StyleMatchAI/WeatherKitAuthority.swift")
        XCTAssertTrue(authoritySource.contains(".aiWeatherStylist, .weatherChat:"))
    }

    func testWeatherGuidanceSurfaceClassificationIsCentralized() throws {
        let authoritySource = try projectSource("StyleMatchAI/WeatherKitAuthority.swift")

        XCTAssertTrue(authoritySource.contains("extension WeatherAttributionSurface"))
        XCTAssertTrue(authoritySource.contains("case .home, .hourlyForecast, .tenDayForecast:"))
        XCTAssertTrue(authoritySource.contains("case .weatherStyling, .scanWeatherGuidance, .closetWeatherGuidance,"))
        XCTAssertTrue(authoritySource.contains(".aiWeatherStylist, .weatherChat:"))
        XCTAssertTrue(authoritySource.contains("presentation ?? surface.presentation"))
    }

    private func makePersonalizationWeather(rainChance: Int = 15, condition: String = "Mostly Clear", currentPrecipitationIntensityKilometersPerHour: Double? = nil) throws -> WeatherSnapshot {
        let attribution = try XCTUnwrap(WeatherAttributionMetadata(
            serviceName: "Apple Weather",
            combinedMarkLightURL: try XCTUnwrap(URL(string: "https://example.com/light")),
            combinedMarkDarkURL: try XCTUnwrap(URL(string: "https://example.com/dark")),
            legalPageURL: try XCTUnwrap(URL(string: "https://example.com/legal"))
        ))
        return try XCTUnwrap(WeatherSnapshot(
            observedAt: Date(), locationName: "Test City", temperatureFahrenheit: 79,
            feelsLikeFahrenheit: 81, condition: condition, currentPrecipitationIntensityKilometersPerHour: currentPrecipitationIntensityKilometersPerHour, rainChancePercent: rainChance,
            humidityPercent: 55, windMph: 5, uvIndex: 5, hourlySummary: nil,
            dailySummary: nil, attribution: attribution
        ))
    }

    private func makeClosetItem(_ name: String, _ category: String, _ color: String, _ size: String, _ occasion: String) -> ClosetItem {
        ClosetItem(name: name, category: category, color: color, brand: "", size: size, occasion: occasion, notes: "")
    }

    private func makeSavedScan(id: String, score: Int, items: [String], colors: [String], occasion: String?) -> WeatherStylingSavedScan {
        WeatherStylingSavedScan(id: id, score: score, detectedItems: items, colorPalette: colors, occasion: occasion)
    }
}

final class StyleMatchProPhase2Tests: XCTestCase {
    let userA = "test-user-A"
    let userB = "test-user-B"

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var snapshotTestRoot: URL!

    override func setUp() {
        super.setUp()
        suiteName = "StyleMatchProPhase2Tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        XCTAssertNotNil(defaults)
        snapshotTestRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("StyleMatchProPhase2Tests-\(UUID().uuidString)", isDirectory: true)
        XCTAssertNoThrow(try FileManager.default.createDirectory(at: snapshotTestRoot, withIntermediateDirectories: true))

        PersonalStylistStorage.deletePersonalization(for: userA, defaults: defaults, snapshotRoot: snapshotTestRoot)
        PersonalStylistStorage.deletePersonalization(for: userB, defaults: defaults, snapshotRoot: snapshotTestRoot)
    }

    override func tearDown() {
        if let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        if let snapshotTestRoot {
            try? FileManager.default.removeItem(at: snapshotTestRoot)
        }
        defaults = nil
        suiteName = nil
        snapshotTestRoot = nil
        super.tearDown()
    }

    func testPublicAppHasNoSubscriptionOrPaywallSurfaceAndKeepsFreeCoreAndAffiliateShopping() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appRoot = root.appendingPathComponent("StyleMatchAI", isDirectory: true)
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey]
        let auditedExtensions = Set(["swift", "plist", "json", "strings", "xcprivacy"])
        let files = try XCTUnwrap(
            FileManager.default.enumerator(
                at: appRoot,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles]
            )?.allObjects as? [URL]
        ).filter { url in
            (try? url.resourceValues(forKeys: resourceKeys).isRegularFile) == true
                && auditedExtensions.contains(url.pathExtension.lowercased())
        }
        let publicAppSource = try files
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        let normalizedSource = publicAppSource.lowercased()

        let prohibitedPublicTerms = [
            "sub" + "scription",
            "pay" + "wall",
            "restore" + " purchase",
            "manage" + " subscription",
            "free" + " trial",
            "monthly" + " plan",
            "yearly" + " plan"
        ]
        for term in prohibitedPublicTerms {
            XCTAssertFalse(normalizedSource.contains(term), "Public app source or resources contain prohibited term: \(term)")
        }

        let prohibitedPurchaseAPIs = [
            "import " + "StoreKit",
            "SK" + "PaymentQueue",
            "SK" + "Product",
            "Product." + "subscription",
            "AppStore." + "sync"
        ]
        for token in prohibitedPurchaseAPIs {
            XCTAssertFalse(publicAppSource.contains(token), "Public app integrates purchase API: \(token)")
        }

        let contentSource = try projectSource("StyleMatchAI/ContentView.swift")
        for coreView in ["HomeView(", "ScanView(", "ClosetView(", "ShoppingView(", "StylistChatView(", "ProfileView("] {
            XCTAssertTrue(contentSource.contains(coreView), "Core free surface is missing: \(coreView)")
        }
        XCTAssertFalse(contentSource.localizedCaseInsensitiveContains("paid entitlement"))

        let profileSource = try projectSource("StyleMatchAI/ProfileView.swift")
        XCTAssertFalse(profileSource.contains("profileInfoRow(\"Subscription\""))

        let affiliateSource = try projectSource("StyleMatchAI/Shopping/AffiliateProduct.swift")
        let shoppingSource = try projectSource("StyleMatchAI/Shopping/ShoppingView.swift")
        XCTAssertTrue(affiliateSource.contains("enum AffiliateLinkBuilder"))
        XCTAssertTrue(affiliateSource.contains("View Product"))
        XCTAssertTrue(shoppingSource.contains("disclosureSummary"))
        XCTAssertTrue(shoppingSource.contains("AffiliateLinkBuilder.outboundURL(for: product)"))

        XCTAssertTrue(publicAppSource.contains("KigoStylist"), "The product name remains valid branding")
    }

    // MARK: - Profile pants size sync tests

    func testMenPantsSizeParserExtractsWaistAndInseam() {
        XCTAssertEqual(
            PantsSizeSync.measurements(from: "Men 36x32"),
            PantsSizeMeasurements(waist: "36", inseam: "32")
        )
        XCTAssertEqual(
            PantsSizeSync.measurements(from: "36 x 32"),
            PantsSizeMeasurements(waist: "36", inseam: "32")
        )
        XCTAssertEqual(
            PantsSizeSync.measurements(from: "Men 36X32"),
            PantsSizeMeasurements(waist: "36", inseam: "32")
        )
        XCTAssertNil(PantsSizeSync.measurements(from: "Women 12"))
    }

    func testPantsPickerChangeUpdatesWaistAndInseamFields() {
        var state = PantsSizeFieldState(pantsSize: "Men 36x36", waistSize: "36", inseamLength: "36")
        state.applyPickerSelection("Men 36x32")
        XCTAssertEqual(state.visibleValuesForSave, PantsSizeVisibleValues(pantsSize: "Men 36x32", waistSize: "36", inseamLength: "32"))
        XCTAssertEqual(state.lastEditSource, .picker)

        state = PantsSizeFieldState(pantsSize: "Men 34x30", waistSize: "34", inseamLength: "30")
        state.applyPickerSelection("Men 34x32")
        XCTAssertEqual(state.visibleValuesForSave, PantsSizeVisibleValues(pantsSize: "Men 34x32", waistSize: "34", inseamLength: "32"))

        state = PantsSizeFieldState(pantsSize: "Men 32x32", waistSize: "32", inseamLength: "32")
        state.applyPickerSelection("Men 32x30")
        XCTAssertEqual(state.visibleValuesForSave, PantsSizeVisibleValues(pantsSize: "Men 32x30", waistSize: "32", inseamLength: "30"))
    }

    func testManualInseamEditSurvivesVisibleSaveValues() {
        var state = PantsSizeFieldState(pantsSize: "Men 36x32", waistSize: "36", inseamLength: "32", lastEditSource: .picker)
        state.applyManualInseam("34")

        XCTAssertEqual(state.lastEditSource, .manual)
        XCTAssertEqual(state.visibleValuesForSave, PantsSizeVisibleValues(pantsSize: "Men 36x34", waistSize: "36", inseamLength: "34"))
    }

    func testGeneratedPantsSizeComesFromWaistAndInseam() {
        XCTAssertEqual(PantsSizeSync.displayValue(waist: "36", inseam: "32"), "36 × 32")
        XCTAssertEqual(PantsSizeSync.storageValue(category: "Men", waist: "36", inseam: "32"), "Men 36x32")
        XCTAssertEqual(PantsSizeSync.storageValue(category: "Unisex", waist: "34", inseam: "30"), "Unisex 34x30")
    }

    func testChangingWaistOrInseamUpdatesGeneratedPantsSize() {
        var state = PantsSizeFieldState(pantsSize: "Men 34x30", waistSize: "34", inseamLength: "30")

        state.applyManualWaist("36")
        XCTAssertEqual(state.visibleValuesForSave, PantsSizeVisibleValues(pantsSize: "Men 36x30", waistSize: "36", inseamLength: "30"))

        state.applyManualInseam("32")
        XCTAssertEqual(state.visibleValuesForSave, PantsSizeVisibleValues(pantsSize: "Men 36x32", waistSize: "36", inseamLength: "32"))
    }

    func testLegacyCombinedPantsSizeBackfillsMissingMeasurements() {
        let reconciled = PantsSizeSync.reconciledValues(
            pantsSize: "Men 36 × 32",
            waistSize: "",
            inseamLength: "",
            category: "Men"
        )

        XCTAssertEqual(reconciled.pantsSize, "Men 36x32")
        XCTAssertEqual(reconciled.waistSize, "36")
        XCTAssertEqual(reconciled.inseamLength, "32")
    }

    func testSeparateMeasurementsOverrideStaleCombinedPantsSize() {
        let reconciled = PantsSizeSync.reconciledValues(
            pantsSize: "Men 24x27",
            waistSize: "36",
            inseamLength: "32",
            category: "Men"
        )

        XCTAssertEqual(reconciled.pantsSize, "Men 36x32")
        XCTAssertEqual(reconciled.waistSize, "36")
        XCTAssertEqual(reconciled.inseamLength, "32")
    }

    func testBlankPantsMeasurementsDoNotCreateFakeDefault() {
        let reconciled = PantsSizeSync.reconciledValues(
            pantsSize: "",
            waistSize: "",
            inseamLength: "",
            category: "Men"
        )

        XCTAssertEqual(reconciled.pantsSize, "")
        XCTAssertEqual(reconciled.waistSize, "")
        XCTAssertEqual(reconciled.inseamLength, "")
        XCTAssertNil(PantsSizeSync.displayValue(waist: reconciled.waistSize, inseam: reconciled.inseamLength))
    }

    func testWomenCategoryDoesNotGenerateMensPantsSizeFromStaleMeasurements() {
        XCTAssertFalse(PantsSizeSync.categoryUsesGeneratedPants("Women"))
        XCTAssertNil(PantsSizeSync.storageValue(category: "Women", waist: "36", inseam: "32"))
    }

    func testProfileAndClosetCanShareGeneratedPantsDisplayValue() {
        let reconciled = PantsSizeSync.reconciledValues(
            pantsSize: "Men 36x36",
            waistSize: "36",
            inseamLength: "32",
            category: "Men"
        )

        let generatedDisplay = PantsSizeSync.displayValue(
            waist: reconciled.waistSize,
            inseam: reconciled.inseamLength
        )

        XCTAssertEqual(reconciled.pantsSize, "Men 36x32")
        XCTAssertEqual(generatedDisplay, "36 × 32")
    }

    func testReselectingSameSizeCategoryPreservesEverySavedSizeField() {
        var fields = ProfileSizeFieldValues(
            shirtSize: "L",
            pantsSize: "Men 36x36",
            waistSize: "36",
            inseamLength: "36",
            neckSize: "16",
            sleeveLength: "35",
            shoeSize: "11",
        )
        let original = fields

        let change = ProfileSizeCategoryChange.plan(
            currentCategory: "Men",
            fields: fields,
            requestedCategory: "Men"
        )

        XCTAssertFalse(change.requiresConfirmation)
        XCTAssertTrue(change.fieldsToClear.isEmpty)
        change.apply(to: &fields)
        XCTAssertEqual(fields, original)
    }

    func testCompatibleMenToUnisexCategoryChangeDoesNotClearMeasurementsOrPreferences() {
        var fields = ProfileSizeFieldValues(
            shirtSize: "L",
            pantsSize: "Men 36x36",
            waistSize: "36",
            inseamLength: "36",
            neckSize: "16",
            sleeveLength: "35",
            shoeSize: "11"
        )

        let change = ProfileSizeCategoryChange.plan(
            currentCategory: "Men",
            fields: fields,
            requestedCategory: "Unisex / Prefer not to say"
        )

        XCTAssertFalse(change.requiresConfirmation)
        XCTAssertTrue(change.fieldsToClear.isEmpty)
        change.apply(to: &fields)
        XCTAssertEqual(fields.waistSize, "36")
        XCTAssertEqual(fields.inseamLength, "36")
        XCTAssertEqual(fields.shoeSize, "11")
        XCTAssertEqual(fields.neckSize, "16")
        XCTAssertEqual(fields.sleeveLength, "35")
    }

    func testIncompatibleCategoryChangeRequiresConfirmationBeforeClearing() {
        let fields = ProfileSizeFieldValues(
            shirtSize: "L",
            pantsSize: "Men 36x36",
            waistSize: "36",
            inseamLength: "36",
            neckSize: "16",
            sleeveLength: "35",
            shoeSize: "11"
        )

        let change = ProfileSizeCategoryChange.plan(
            currentCategory: "Men",
            fields: fields,
            requestedCategory: "Women"
        )

        XCTAssertTrue(change.requiresConfirmation)
        XCTAssertEqual(
            Set(change.fieldsToClear),
            Set([.shirtSize, .pantsSize, .waistSize, .inseamLength, .neckSize, .sleeveLength, .shoeSize])
        )
        XCTAssertTrue(change.confirmationMessage.contains("Shoe size"))
        XCTAssertTrue(change.confirmationMessage.contains("Waist"))
    }

    func testCancellingIncompatibleCategoryChangeLeavesOriginalDraftUntouched() {
        let fields = ProfileSizeFieldValues(
            shirtSize: "L",
            pantsSize: "Men 36x36",
            waistSize: "36",
            inseamLength: "36",
            shoeSize: "11"
        )
        let original = fields

        let change = ProfileSizeCategoryChange.plan(
            currentCategory: "Men",
            fields: fields,
            requestedCategory: "Women"
        )

        XCTAssertTrue(change.requiresConfirmation)
        XCTAssertEqual(fields, original, "Planning a category change must not mutate the draft before confirmation.")
    }

    func testConfirmedCategoryChangeClearsOnlyIncompatibleFieldsAndRetainsPreferences() {
        var fields = ProfileSizeFieldValues(
            shirtSize: "L",
            pantsSize: "Men 36x36",
            waistSize: "36",
            inseamLength: "36",
            neckSize: "16",
            sleeveLength: "35",
            shoeSize: "11"
        )
        let change = ProfileSizeCategoryChange.plan(
            currentCategory: "Men",
            fields: fields,
            requestedCategory: "Women"
        )

        change.apply(to: &fields)

        XCTAssertEqual(fields.shirtSize, "")
        XCTAssertEqual(fields.pantsSize, "")
        XCTAssertEqual(fields.waistSize, "")
        XCTAssertEqual(fields.inseamLength, "")
        XCTAssertEqual(fields.neckSize, "")
        XCTAssertEqual(fields.sleeveLength, "")
        XCTAssertEqual(fields.shoeSize, "")
    }

    func testRetainedDirectProfileFieldsSurviveUserDefaultsRoundTripAndProfileSavePath() throws {
        let retainedValues = [
            "sizeCategory": "Men",
            "shirtSize": "L",
            "pantsSize": "Men 36x36",
            "waistSize": "36",
            "inseamLength": "36",
            "shoeSize": "11",
            "preferredPantFit": "Tailored",
            "preferredPantRise": "Mid Rise"
        ]
        retainedValues.forEach { defaults.set($0.value, forKey: $0.key) }

        let reloaded = UserDefaults(suiteName: suiteName)
        retainedValues.forEach { key, value in
            XCTAssertEqual(reloaded?.string(forKey: key), value)
        }

        let profileSource = try projectSource("StyleMatchAI/ProfileView.swift")
        let profileModelSource = try projectSource("StyleMatchAI/PersonalStylist/StylistProfileModels.swift")
        for assignment in [
            "sizeCategory = draft.sizeCategory",
            "shirtSize = draft.shirtSize",
            "pantsSize = draft.pantsSize",
            "waistSize = draft.waistSize",
            "inseamLength = draft.inseamLength",
            "shoeSize = draft.shoeSize",
            "preferredPantFit = draft.preferredPantFit",
            "preferredPantRise = draft.preferredPantRise"
        ] {
            XCTAssertTrue(profileSource.contains(assignment), "Profile save path must preserve retained direct UserDefaults fields: \(assignment)")
        }
        XCTAssertTrue(profileSource.contains("showSizeCategoryChangeConfirmation = true"))
        XCTAssertTrue(profileSource.contains("Change Category and Clear Listed Fields"))
        XCTAssertTrue(profileSource.contains("pendingSizeCategoryChange = nil"))
        let policyStart = try XCTUnwrap(profileModelSource.range(of: "enum ProfileSizeField"))
        let policyEnd = try XCTUnwrap(profileModelSource.range(of: "enum PantsSizeEditSource", range: policyStart.upperBound..<profileModelSource.endIndex))
        let policySource = String(profileModelSource[policyStart.lowerBound..<policyEnd.lowerBound])
        XCTAssertFalse(policySource.contains("preferredPantFit"))
        XCTAssertFalse(policySource.contains("preferredPantRise"))
    }

    func testPantsSizeProfileReconciliationPrefersWaistInseamOverStaleCombined() {
        defaults.set("Men", forKey: "sizeCategory")
        defaults.set("Men 24x27", forKey: "pantsSize")
        defaults.set("36", forKey: "waistSize")
        defaults.set("32", forKey: "inseamLength")
        defaults.set("Category: Men; Bottom: Men 24x27", forKey: "sizeProfile")

        var profile = makeStylistProfile(userId: userA)
        profile.clothingSizes = ClothingSizes(pantSize: "Men 24x27")

        let result = PantsSizeProfileReconciliation.reconcile(
            defaults: defaults,
            userID: userA,
            profile: profile
        )

        XCTAssertTrue(result.didChangeProfile)
        XCTAssertEqual(result.profile.clothingSizes.pantSize, "Men 36x32")
        XCTAssertEqual(defaults.string(forKey: "pantsSize"), "Men 36x32")
        XCTAssertEqual(defaults.string(forKey: "waistSize"), "36")
        XCTAssertEqual(defaults.string(forKey: "inseamLength"), "32")
        XCTAssertNil(defaults.string(forKey: "sizeProfile"))
        XCTAssertTrue(defaults.bool(forKey: PantsSizeProfileReconciliation.migrationKey(userID: userA)))
    }

    func testPantsSizeProfileReconciliationParsesPantsSizeOnly() {
        defaults.set("Men", forKey: "sizeCategory")
        defaults.set("Men 34x30", forKey: "pantsSize")

        var profile = makeStylistProfile(userId: userA)
        profile.clothingSizes = ClothingSizes(pantSize: "Men 34x30")

        let result = PantsSizeProfileReconciliation.reconcile(
            defaults: defaults,
            userID: userA,
            profile: profile
        )

        XCTAssertFalse(result.didChangeProfile)
        XCTAssertEqual(result.profile.clothingSizes.pantSize, "Men 34x30")
        XCTAssertEqual(defaults.string(forKey: "pantsSize"), "Men 34x30")
        XCTAssertEqual(defaults.string(forKey: "waistSize"), "34")
        XCTAssertEqual(defaults.string(forKey: "inseamLength"), "30")
    }

    func testPantsSizeProfileReconciliationGeneratesFromWaistInseamOnly() {
        defaults.set("Men", forKey: "sizeCategory")
        defaults.set("36", forKey: "waistSize")
        defaults.set("32", forKey: "inseamLength")

        let profile = makeStylistProfile(userId: userA)

        let result = PantsSizeProfileReconciliation.reconcile(
            defaults: defaults,
            userID: userA,
            profile: profile
        )

        XCTAssertTrue(result.didChangeProfile)
        XCTAssertEqual(result.profile.clothingSizes.pantSize, "Men 36x32")
        XCTAssertEqual(defaults.string(forKey: "pantsSize"), "Men 36x32")
        XCTAssertEqual(defaults.string(forKey: "waistSize"), "36")
        XCTAssertEqual(defaults.string(forKey: "inseamLength"), "32")
    }

    func testPantsSizeProfileReconciliationLeavesBlankSizesBlankAndRunsOnce() {
        let profile = makeStylistProfile(userId: userA)

        let first = PantsSizeProfileReconciliation.reconcile(
            defaults: defaults,
            userID: userA,
            profile: profile
        )

        XCTAssertFalse(first.didChangeProfile)
        XCTAssertNil(first.profile.clothingSizes.pantSize)
        XCTAssertNil(defaults.string(forKey: "pantsSize"))
        XCTAssertNil(defaults.string(forKey: "waistSize"))
        XCTAssertNil(defaults.string(forKey: "inseamLength"))
        XCTAssertTrue(defaults.bool(forKey: PantsSizeProfileReconciliation.migrationKey(userID: userA)))

        defaults.set("Men", forKey: "sizeCategory")
        defaults.set("Men 36x32", forKey: "pantsSize")
        defaults.set("36", forKey: "waistSize")
        defaults.set("32", forKey: "inseamLength")

        let second = PantsSizeProfileReconciliation.reconcile(
            defaults: defaults,
            userID: userA,
            profile: first.profile
        )

        XCTAssertFalse(second.didChangeProfile)
        XCTAssertNil(second.profile.clothingSizes.pantSize)
    }

    func testBlankClothingSizesDoNotReachAIContext() {
        var profile = makeStylistProfile(userId: userA)
        profile.clothingSizes = ClothingSizes(
            shirtSize: " ",
            pantSize: " ",
            shoeSize: "",
            jacketSize: nil,
            dressSize: nil
        )

        let context = PersonalizationContextBuilder.buildContext(profile: profile, recentMemories: [])

        XCTAssertFalse(context.contains("Sizes"))
        XCTAssertFalse(context.localizedCaseInsensitiveContains("pants"))
        XCTAssertFalse(context.localizedCaseInsensitiveContains("shoes"))
        XCTAssertFalse(context.contains("36"))
    }

    // MARK: - Phase 3 feedback loop tests

    func testFeedbackSchedulerEligibilityWindow() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let store = OutfitMemoryStore(defaults: defaults, userId: userA, snapshotRoot: snapshotTestRoot)
        markFeedbackFirstSessionSeen(for: userA)

        var tooRecent = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "too-recent"))
        tooRecent.scanDate = now.addingTimeInterval(-6 * 60 * 60)
        var eligible = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "eligible"))
        eligible.scanDate = now.addingTimeInterval(-13 * 60 * 60)
        var tooOld = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "too-old"))
        tooOld.scanDate = now.addingTimeInterval(-15 * 24 * 60 * 60)

        store.addScan(tooRecent)
        store.addScan(eligible)
        store.addScan(tooOld)

        let scheduler = FeedbackPromptScheduler(store: store, defaults: defaults, userId: userA)
        XCTAssertEqual(scheduler.nextPromptCandidate(now: now)?.id, eligible.id)
    }

    func testFeedbackSchedulerReAskRulesAndOnePerSession() {
        let now = Date(timeIntervalSince1970: 2_500_000)
        let store = OutfitMemoryStore(defaults: defaults, userId: userA, snapshotRoot: snapshotTestRoot)
        markFeedbackFirstSessionSeen(for: userA)

        var capped = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "capped"))
        capped.scanDate = now.addingTimeInterval(-20 * 60 * 60)
        capped.feedbackPromptCount = 2
        store.addScan(capped)

        var dismissed = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "dismissed"))
        dismissed.scanDate = now.addingTimeInterval(-22 * 60 * 60)
        dismissed.feedbackDismissedAt = now.addingTimeInterval(-47 * 60 * 60)
        store.addScan(dismissed)

        let scheduler = FeedbackPromptScheduler(store: store, defaults: defaults, userId: userA)
        XCTAssertNil(scheduler.nextPromptCandidate(now: now))

        store.dismissFeedbackPrompt(for: dismissed.id, now: now.addingTimeInterval(-49 * 60 * 60))
        XCTAssertEqual(scheduler.nextPromptCandidate(now: now)?.id, dismissed.id)

        scheduler.recordPromptShown(for: dismissed.id, now: now)
        XCTAssertNil(scheduler.nextPromptCandidate(now: now), "Only one prompt should show per app session.")

        let freshStore = OutfitMemoryStore(defaults: defaults, userId: userA, snapshotRoot: snapshotTestRoot)
        let freshScheduler = FeedbackPromptScheduler(store: freshStore, defaults: defaults, userId: userA)
        XCTAssertNil(freshScheduler.nextPromptCandidate(now: now.addingTimeInterval(60 * 60)), "Global cap should block prompts for 24 hours.")
    }

    func testFeedbackSchedulerSuppressesVeryFirstSessionOnly() {
        let now = Date(timeIntervalSince1970: 2_700_000)
        let store = OutfitMemoryStore(defaults: defaults, userId: userA, snapshotRoot: snapshotTestRoot)

        var eligible = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "skip-backoff"))
        eligible.scanDate = now.addingTimeInterval(-20 * 60 * 60)
        store.addScan(eligible)

        let scheduler = FeedbackPromptScheduler(store: store, defaults: defaults, userId: userA)
        XCTAssertNil(scheduler.nextPromptCandidate(now: now), "The first app session should not show a feedback prompt.")

        let relaunchedStore = OutfitMemoryStore(defaults: defaults, userId: userA, snapshotRoot: snapshotTestRoot)
        let relaunchedScheduler = FeedbackPromptScheduler(store: relaunchedStore, defaults: defaults, userId: userA)
        XCTAssertEqual(relaunchedScheduler.nextPromptCandidate(now: now)?.id, eligible.id)
    }

    func testFeedbackSchedulerPicksMostRecentEligibleOutfit() {
        let now = Date(timeIntervalSince1970: 3_000_000)
        let store = OutfitMemoryStore(defaults: defaults, userId: userA, snapshotRoot: snapshotTestRoot)
        markFeedbackFirstSessionSeen(for: userA)

        var older = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "older"))
        older.scanDate = now.addingTimeInterval(-4 * 24 * 60 * 60)
        var newer = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "newer"))
        newer.scanDate = now.addingTimeInterval(-13 * 60 * 60)

        store.addScan(older)
        store.addScan(newer)

        let scheduler = FeedbackPromptScheduler(store: store, defaults: defaults, userId: userA)
        XCTAssertEqual(scheduler.nextPromptCandidate(now: now)?.id, newer.id)
    }

    func testFeedbackWornAnswerIncrementsTimesWornExactlyOnce() {
        let now = Date(timeIntervalSince1970: 3_500_000)
        let store = OutfitMemoryStore(defaults: defaults, userId: userA, snapshotRoot: snapshotTestRoot)
        let memory = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "repeat-worn"))
        store.addScan(memory)

        store.recordWornAnswer(for: memory.id, wasWorn: true, now: now)
        store.recordWornAnswer(for: memory.id, wasWorn: true, now: now.addingTimeInterval(60))

        let saved = OutfitMemoryStore(defaults: defaults, userId: userA, snapshotRoot: snapshotTestRoot).memories.first { $0.id == memory.id }
        XCTAssertEqual(saved?.wasWorn, true)
        XCTAssertEqual(saved?.timesWorn, 1)
        XCTAssertEqual(saved?.garmentRecords.first?.timesWorn, 1)
    }

    func testOutfitMemoryDecodesWithoutPhase3FeedbackFields() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "userId": "\(userA)",
          "scanDate": 0,
          "detectedGarments": ["shirt"],
          "colors": ["white"],
          "detectedStyle": "Casual",
          "styleScore": 82,
          "occasion": "casual",
          "isFavorite": false,
          "timesWorn": 0
        }
        """

        let decoded = try JSONDecoder().decode(OutfitMemory.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.id, id)
        XCTAssertNil(decoded.wasWorn)
        XCTAssertNil(decoded.wasLiked)
        XCTAssertNil(decoded.dislikeReason)
        XCTAssertEqual(decoded.feedbackPromptCount, 0)
        XCTAssertNil(decoded.feedbackDismissedAt)
        XCTAssertNil(decoded.feedbackCompletedAt)
        XCTAssertNil(decoded.feedback)
    }

    func testPrePhase3OutfitMemoryJSONFixtureDecodesCleanlyWithoutFeedbackField() throws {
        let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let json = """
        {
          "id": "\(id.uuidString)",
          "userId": "\(userA)",
          "scanDate": 1720310400,
          "detectedGarments": ["shirt", "pants"],
          "colors": ["white", "gray"],
          "detectedStyle": "Casual",
          "styleScore": 84,
          "isFavorite": true,
          "timesWorn": 0
        }
        """

        let decoded = try JSONDecoder().decode(OutfitMemory.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.detectedGarments, ["shirt", "pants"])
        XCTAssertEqual(decoded.colors, ["white", "gray"])
        XCTAssertNil(decoded.feedback)
        XCTAssertNil(decoded.wasWorn)
        XCTAssertNil(decoded.wasLiked)
        XCTAssertNil(decoded.feedbackTimestamp)
        XCTAssertNil(decoded.dislikeReason)
        XCTAssertEqual(decoded.feedbackPromptCount, 0)
        XCTAssertNil(decoded.feedbackDismissedAt)
        XCTAssertNil(decoded.feedbackCompletedAt)
    }

    func testFeedbackNoAnswerCompletesWithoutLikeOrReason() {
        let now = Date(timeIntervalSince1970: 4_000_000)
        let store = OutfitMemoryStore(defaults: defaults, userId: userA, snapshotRoot: snapshotTestRoot)
        let memory = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "not-worn"))
        store.addScan(memory)

        store.recordWornAnswer(for: memory.id, wasWorn: false, now: now)

        let saved = OutfitMemoryStore(defaults: defaults, userId: userA, snapshotRoot: snapshotTestRoot).memories.first { $0.id == memory.id }
        XCTAssertEqual(saved?.wasWorn, false)
        XCTAssertNil(saved?.wasLiked)
        XCTAssertNil(saved?.dislikeReason)
        XCTAssertNotNil(saved?.feedbackCompletedAt)
    }

    func testRecordOutfitFeedbackPersistsAndIncrementsTimesWornOnce() {
        let now = Date(timeIntervalSince1970: 4_300_000)
        let store = OutfitMemoryStore(defaults: defaults, userId: userA, snapshotRoot: snapshotTestRoot)
        let memory = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "verdict"))
        store.addScan(memory)

        let feedback = OutfitFeedback(verdict: .loved, woreIt: true, recordedAt: now)
        store.recordOutfitFeedback(for: memory.id, feedback: feedback)
        store.recordOutfitFeedback(for: memory.id, feedback: feedback)

        let saved = OutfitMemoryStore(defaults: defaults, userId: userA, snapshotRoot: snapshotTestRoot).memories.first { $0.id == memory.id }
        XCTAssertEqual(saved?.feedback, feedback)
        XCTAssertEqual(saved?.wasWorn, true)
        XCTAssertEqual(saved?.wasLiked, true)
        XCTAssertEqual(saved?.timesWorn, 1)
        XCTAssertNotNil(saved?.feedbackCompletedAt)
    }

    func testPersonalizationContextOmitsFeedbackWhenEmptyAndSummarizesWhenPresent() {
        let profile = makeStylistProfile(userId: userA)
        var noFeedback = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "no-feedback"))
        noFeedback.detectedStyle = "Casual"
        let emptyContext = PersonalizationContextBuilder.promptContext(
            profile: profile,
            outfitMemories: [noFeedback],
            memoryLimit: 5
        )
        XCTAssertFalse(emptyContext.contains("Feedback signals"))

        var loved = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "loved-feedback"))
        loved.detectedStyle = "Casual"
        loved.feedback = OutfitFeedback(verdict: .loved, woreIt: true, recordedAt: Date(timeIntervalSince1970: 4_400_000))
        var notForMe = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "not-feedback"))
        notForMe.detectedStyle = "Formal"
        notForMe.feedback = OutfitFeedback(verdict: .notForMe, woreIt: true, recordedAt: Date(timeIntervalSince1970: 4_400_100))

        let summary = PersonalizationContextBuilder.feedbackSummary([loved, notForMe])
        XCTAssertNotNil(summary)
        XCTAssertLessThanOrEqual(summary?.count ?? 0, 220)

        let feedbackContext = PersonalizationContextBuilder.promptContext(
            profile: profile,
            outfitMemories: [loved, notForMe],
            memoryLimit: 5
        )
        XCTAssertTrue(feedbackContext.contains("Feedback signals"))
        XCTAssertTrue(feedbackContext.contains("loved"))
        XCTAssertTrue(feedbackContext.contains("not for me"))
    }

    func testPersonalizationContextSummarizesTapOnlyFeedbackFields() {
        let profile = makeStylistProfile(userId: userA)
        var loved = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "tap-loved"))
        loved.detectedStyle = "Smart Casual"
        loved.wasWorn = true
        loved.wasLiked = true
        loved.timesWorn = 1

        var disliked = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "tap-disliked"))
        disliked.detectedStyle = "Formal"
        disliked.wasWorn = true
        disliked.wasLiked = false
        disliked.dislikeReason = .tooFormal

        let feedbackContext = PersonalizationContextBuilder.promptContext(
            profile: profile,
            outfitMemories: [loved, disliked],
            memoryLimit: 5
        )

        XCTAssertTrue(feedbackContext.contains("Feedback signals"))
        XCTAssertTrue(feedbackContext.contains("loved 1"))
        XCTAssertTrue(feedbackContext.contains("not for me 1"))
        XCTAssertTrue(feedbackContext.contains("wore 2"))
        XCTAssertTrue(feedbackContext.contains("dislike reasons: too formal 1x"))
        XCTAssertTrue(feedbackContext.contains("Recently disliked"))
        XCTAssertTrue(feedbackContext.contains("reason Too formal"))
    }

    // MARK: - Weather & Context Engine regression tests

    func testWeatherSeverityUsesFeelsLikeTemperature() {
        let recommendation = WeatherContextEngine.recommendation(
            for: makeWeatherSnapshot(air: 84, feelsLike: 100, humidity: 72, activity: .walking)
        )

        XCTAssertEqual(recommendation.severity, .extremeHeat)
        XCTAssertFalse(containsHeavyLayer(recommendation.recommendation))
        XCTAssertTrue(recommendation.rationale.contains("feels-like temperature is 100°F"))
    }

    func testNinetyDegreeWeatherDoesNotRecommendJackets() {
        let recommendation = WeatherContextEngine.recommendation(
            for: makeWeatherSnapshot(air: 90, feelsLike: 91, humidity: 68, activity: .office, location: "Miami, Florida")
        )

        XCTAssertEqual(recommendation.severity, .hot)
        XCTAssertFalse(containsHeavyLayer(recommendation.recommendation))
        XCTAssertTrue(recommendation.recommendation.localizedCaseInsensitiveContains("lightweight"))
        XCTAssertTrue(recommendation.regionalNote.localizedCaseInsensitiveContains("hot-humid"))
    }

    func testRainInWarmWeatherUsesUmbrellaInsteadOfJacket() {
        let recommendation = WeatherContextEngine.recommendation(
            for: makeWeatherSnapshot(air: 82, feelsLike: 87, rain: 80, condition: "Rain", activity: .walking)
        )

        XCTAssertFalse(containsHeavyLayer(recommendation.recommendation))
        XCTAssertTrue(recommendation.recommendation.localizedCaseInsensitiveContains("umbrella"))
        XCTAssertTrue(recommendation.rationale.localizedCaseInsensitiveContains("rain risk"))
    }

    func testSnowAllowsColdWeatherLayers() {
        let recommendation = WeatherContextEngine.recommendation(
            for: makeWeatherSnapshot(air: 30, feelsLike: 26, condition: "Snow", activity: .travel, location: "Minneapolis, Minnesota")
        )

        XCTAssertEqual(recommendation.severity, .freezing)
        XCTAssertTrue(recommendation.recommendation.localizedCaseInsensitiveContains("coat"))
        XCTAssertTrue(recommendation.recommendation.localizedCaseInsensitiveContains("boots"))
    }

    func testWindAtCoolTemperatureAllowsRemovableLayer() {
        let recommendation = WeatherContextEngine.recommendation(
            for: makeWeatherSnapshot(air: 55, feelsLike: 52, wind: 22, condition: "Windy", activity: .outdoorEvent)
        )

        XCTAssertEqual(recommendation.severity, .cool)
        XCTAssertTrue(recommendation.recommendation.localizedCaseInsensitiveContains("wind-resistant"))
        XCTAssertTrue(recommendation.guardrail.localizedCaseInsensitiveContains("removable"))
    }

    func testHighUVAddsSunProtectionWithoutHeavyLayer() {
        let recommendation = WeatherContextEngine.recommendation(
            for: makeWeatherSnapshot(air: 86, feelsLike: 89, uv: 9, activity: .beach, location: "Phoenix, Arizona")
        )

        XCTAssertFalse(containsHeavyLayer(recommendation.recommendation))
        XCTAssertTrue(recommendation.recommendation.localizedCaseInsensitiveContains("sunglasses"))
        XCTAssertTrue(recommendation.rationale.localizedCaseInsensitiveContains("UV index is 9"))
    }

    func testWarmNightDoesNotRecommendJacketBecauseItIsNight() {
        let recommendation = WeatherContextEngine.recommendation(
            for: makeWeatherSnapshot(air: 76, feelsLike: 74, activity: .formalEvent, timeOfDay: "Night")
        )

        XCTAssertEqual(recommendation.severity, .warm)
        XCTAssertFalse(containsHeavyLayer(recommendation.recommendation))
        XCTAssertTrue(recommendation.guardrail.localizedCaseInsensitiveContains("nighttime"))
    }

    func testIndoorOfficeEventKeepsHeatAdvicePolishedWithoutJacket() {
        let recommendation = WeatherContextEngine.recommendation(
            for: makeWeatherSnapshot(air: 88, feelsLike: 92, activity: .office)
        )

        XCTAssertFalse(containsHeavyLayer(recommendation.recommendation))
        XCTAssertTrue(recommendation.recommendation.localizedCaseInsensitiveContains("crisp shirt"))
        XCTAssertTrue(recommendation.rationale.localizedCaseInsensitiveContains("activity is office"))
    }

    func testMixedWeatherPrioritizesEffectiveTemperatureAndRainAccessories() {
        let recommendation = WeatherContextEngine.recommendation(
            for: makeWeatherSnapshot(air: 78, feelsLike: 83, humidity: 80, rain: 55, wind: 16, condition: "Humid rain", activity: .travel)
        )

        XCTAssertEqual(recommendation.severity, .hot)
        XCTAssertFalse(containsHeavyLayer(recommendation.recommendation))
        XCTAssertTrue(recommendation.recommendation.localizedCaseInsensitiveContains("water-friendly shoes"))
        XCTAssertTrue(recommendation.rationale.localizedCaseInsensitiveContains("humidity is 80%"))
    }

    func testLowWeatherConfidenceAvoidsSpecificWeatherClothing() {
        let recommendation = WeatherContextEngine.recommendation(
            for: makeWeatherSnapshot(air: 91, feelsLike: 94, activity: .walking, confidence: 82)
        )

        XCTAssertFalse(recommendation.canGiveSpecificWeatherClothingAdvice)
        XCTAssertTrue(recommendation.guardrail.localizedCaseInsensitiveContains("below 90%"))
        XCTAssertFalse(recommendation.recommendation.localizedCaseInsensitiveContains("linen"))
        XCTAssertFalse(containsHeavyLayer(recommendation.recommendation))
    }

    // MARK: - 1. Per-user isolation

    func testTwoUsersDoNotShareData() {
        let recordA = makeGarmentRecord(fingerprint: "pants-black-solid")
        let memoryA = makeOutfitMemory(userId: userA, record: recordA)

        let userAStore = OutfitMemoryStore(defaults: defaults, userId: userA, snapshotRoot: snapshotTestRoot)
        userAStore.addOrMergeScan(memoryA)

        let userBRecords = OutfitMemoryStore(defaults: defaults, userId: userB, snapshotRoot: snapshotTestRoot).garmentRecords
        XCTAssertTrue(userBRecords.isEmpty, "User B should not see User A's saved data")

        let userARecords = OutfitMemoryStore(defaults: defaults, userId: userA, snapshotRoot: snapshotTestRoot).garmentRecords
        XCTAssertTrue(
            userARecords.contains(where: { $0.itemFingerprint == recordA.itemFingerprint }),
            "User A should see their own saved garment record"
        )
    }

    private func makeWeatherSnapshot(
        air: Int?,
        feelsLike: Int? = nil,
        humidity: Int? = nil,
        rain: Int? = nil,
        wind: Int? = nil,
        uv: Int? = nil,
        condition: String = "Clear",
        activity: WeatherActivity = .general,
        location: String = "Current location",
        confidence: Int = 95,
        timeOfDay: String = "Afternoon"
    ) -> WeatherContextSnapshot {
        WeatherContextSnapshot(
            airTemperature: air,
            feelsLikeTemperature: feelsLike,
            humidityPercent: humidity,
            rainChancePercent: rain,
            windMph: wind,
            uvIndex: uv,
            condition: condition,
            locationText: location,
            activity: activity,
            region: WeatherContextEngine.inferRegion(locationText: location),
            season: "Summer",
            timeOfDay: timeOfDay,
            confidence: confidence
        )
    }

    private func containsHeavyLayer(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.contains("jacket")
            || lowered.contains("blazer")
            || lowered.contains("coat")
            || lowered.contains("sweater")
            || lowered.contains("shacket")
            || lowered.contains("heavy layer")
            || lowered.contains("structured layer")
    }

    // MARK: - 2. Repeated item detection (dedup)

    func testSameGarmentScannedTwiceIncrementsTimesSeenNotDuplicate() {
        let fingerprint = "pants-black-solid"
        let firstRecord = makeGarmentRecord(fingerprint: fingerprint, sourceScanIds: ["scan-1"])
        let secondRecord = makeGarmentRecord(fingerprint: fingerprint, sourceScanIds: ["scan-2"])
        let thirdRecord = makeGarmentRecord(fingerprint: fingerprint, sourceScanIds: ["scan-3"])
        let firstMemory = makeOutfitMemory(userId: userA, record: firstRecord)

        let store = OutfitMemoryStore(defaults: defaults, userId: userA, snapshotRoot: snapshotTestRoot)
        store.addOrMergeScan(firstMemory)

        if let existingMemory = store.memories.first(where: { memory in
            memory.garmentRecords.contains(where: { $0.itemFingerprint == secondRecord.itemFingerprint })
        }) {
            store.mergeGarmentRecords([secondRecord], into: existingMemory.id)
        } else {
            XCTFail("Expected the second scan to match an existing garment fingerprint")
        }

        if let existingMemory = store.memories.first(where: { memory in
            memory.garmentRecords.contains(where: { $0.itemFingerprint == thirdRecord.itemFingerprint })
        }) {
            store.mergeGarmentRecords([thirdRecord], into: existingMemory.id)
        } else {
            XCTFail("Expected the third scan to match an existing garment fingerprint")
        }

        let records = OutfitMemoryStore(defaults: defaults, userId: userA, snapshotRoot: snapshotTestRoot)
            .garmentRecords
            .filter { $0.itemFingerprint == fingerprint }

        XCTAssertEqual(records.count, 1, "Should not create a duplicate record")
        XCTAssertEqual(records.first?.timesSeen, 3, "Same garment should increment timesSeen for each repeat scan")
        XCTAssertEqual(records.first?.sourceScanIds.sorted(), ["scan-1", "scan-2", "scan-3"])
    }

    // MARK: - 3. Privacy deletion completeness

    func testDeletionClearsAllPersonalizationKeys() {
        let recordA = makeGarmentRecord(fingerprint: "pants-black-solid-a")
        let recordB = makeGarmentRecord(fingerprint: "shirt-white-solid-b")

        let profileA = ProfileStore(defaults: defaults, userId: userA)
        profileA.currentProfile.favoriteColors = ["black"]
        profileA.save()

        let profileB = ProfileStore(defaults: defaults, userId: userB)
        profileB.currentProfile.favoriteColors = ["white"]
        profileB.save()

        OutfitMemoryStore(defaults: defaults, userId: userA)
            .addOrMergeScan(makeOutfitMemory(userId: userA, record: recordA))
        OutfitMemoryStore(defaults: defaults, userId: userB)
            .addOrMergeScan(makeOutfitMemory(userId: userB, record: recordB))

        let userAFeedbackKey = PersonalStylistStorage.scopedKey(
            PersonalStylistStorage.legacyFeedbackCountKey,
            userID: userA
        )
        let userBFeedbackKey = PersonalStylistStorage.scopedKey(
            PersonalStylistStorage.legacyFeedbackCountKey,
            userID: userB
        )
        defaults.set(3, forKey: userAFeedbackKey)
        defaults.set(2, forKey: userBFeedbackKey)

        PersonalStylistStorage.deletePersonalization(for: userA, defaults: defaults)

        XCTAssertNil(
            defaults.object(forKey: PersonalStylistStorage.scopedKey(PersonalStylistStorage.legacyProfileKey, userID: userA)),
            "User A profile key should be removed"
        )
        XCTAssertNil(
            defaults.object(forKey: PersonalStylistStorage.scopedKey(PersonalStylistStorage.legacyMemoriesKey, userID: userA)),
            "User A outfit memory key should be removed"
        )
        XCTAssertNil(defaults.object(forKey: userAFeedbackKey), "User A feedback key should be removed")

        XCTAssertNotNil(
            defaults.object(forKey: PersonalStylistStorage.scopedKey(PersonalStylistStorage.legacyProfileKey, userID: userB)),
            "User B profile key should not be removed"
        )
        XCTAssertNotNil(
            defaults.object(forKey: PersonalStylistStorage.scopedKey(PersonalStylistStorage.legacyMemoriesKey, userID: userB)),
            "User B outfit memory key should not be removed"
        )
        XCTAssertEqual(defaults.integer(forKey: userBFeedbackKey), 2, "User B feedback key should not be removed")
    }

    // MARK: - 4. Snapshot safety net

    func testSnapshotStoreKeepsDefaultProductionResolverContract() throws {
        let source = try projectSource("StyleMatchAI/PersonalStylist/PersonalStylistSnapshotStore.swift")
        XCTAssertTrue(source.contains("private static func directoryURL() -> URL {"))
        XCTAssertTrue(source.contains("fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)"))
        XCTAssertTrue(source.contains("appendingPathComponent(\"StyleMatchPro/PersonalStylist\", isDirectory: true)"))
    }

    func testSnapshotStoreReportsWriteFailureForNonDirectoryTestRoot() throws {
        let blockedRoot = snapshotTestRoot.appendingPathComponent("blocked-root")
        try Data("not a directory".utf8).write(to: blockedRoot)

        let result = PersonalStylistSnapshotStore.saveData(
            Data("test".utf8),
            store: "OutfitMemoryStore",
            userID: userA,
            rootDirectory: blockedRoot
        )

        guard case .failure = result else {
            return XCTFail("A non-directory test root must expose its write failure")
        }
    }

    func testUpdatingExistingOutfitCreatesPreWriteSnapshot() {
        let fingerprint = "shirt-white-solid"
        let store = OutfitMemoryStore(defaults: defaults, userId: userA, snapshotRoot: snapshotTestRoot)
        let firstMemory = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: fingerprint, sourceScanIds: ["scan-1"]))
        store.addOrMergeScan(firstMemory)

        let updatedMemory = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: fingerprint, sourceScanIds: ["scan-2"]))
        store.addOrMergeScan(updatedMemory)

        XCTAssertGreaterThanOrEqual(
            PersonalStylistSnapshotStore.snapshotCount(store: "OutfitMemoryStore", userID: userA, rootDirectory: snapshotTestRoot),
            1,
            "Updating an existing outfit should leave a pre-write snapshot"
        )
    }

    func testCorruptOutfitStoreRecoversFromSnapshot() throws {
        let fingerprint = "jacket-charcoal-solid"
        let store = OutfitMemoryStore(defaults: defaults, userId: userA, snapshotRoot: snapshotTestRoot)
        store.addOrMergeScan(makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: fingerprint, sourceScanIds: ["scan-1"])))
        store.addOrMergeScan(makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: fingerprint, sourceScanIds: ["scan-2"])))

        try PersonalStylistSnapshotStore.replaceMainDataForTesting(
            Data("not valid json".utf8),
            store: "OutfitMemoryStore",
            userID: userA,
            rootDirectory: snapshotTestRoot
        )

        let recovered = OutfitMemoryStore(defaults: defaults, userId: userA, snapshotRoot: snapshotTestRoot)
        XCTAssertFalse(recovered.memories.isEmpty, "Corrupt main store should recover from the latest valid snapshot")
        XCTAssertTrue(
            recovered.garmentRecords.contains(where: { $0.itemFingerprint == fingerprint }),
            "Recovered snapshot should preserve the stored garment fingerprint"
        )
    }

    func testSnapshotRotationCapsAtThree() {
        let store = OutfitMemoryStore(defaults: defaults, userId: userA)

        for index in 1...5 {
            store.addOrMergeScan(makeOutfitMemory(
                userId: userA,
                record: makeGarmentRecord(fingerprint: "pants-black-solid", sourceScanIds: ["scan-\(index)"])
            ))
        }

        XCTAssertLessThanOrEqual(
            PersonalStylistSnapshotStore.snapshotCount(store: "OutfitMemoryStore", userID: userA),
            3,
            "Snapshot rotation should keep only the last three snapshots"
        )
    }

    func testConcurrentWritesStayScopedAndDecodable() {
        let store = OutfitMemoryStore(defaults: defaults, userId: userA, snapshotRoot: snapshotTestRoot)
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "StyleMatchProPhase2Tests.concurrentWrites", attributes: .concurrent)

        for index in 0..<20 {
            group.enter()
            queue.async {
                let record = self.makeGarmentRecord(
                    fingerprint: "concurrent-shirt-\(index)",
                    sourceScanIds: ["scan-\(index)"]
                )
                store.addOrMergeScan(self.makeOutfitMemory(userId: self.userA, record: record))
                group.leave()
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)

        let reloaded = OutfitMemoryStore(defaults: defaults, userId: userA, snapshotRoot: snapshotTestRoot)
        let normalizedUserA = PersonalStylistStorage.normalizedUserID(userA)
        XCTAssertEqual(reloaded.memories.count, 20)
        XCTAssertTrue(reloaded.memories.allSatisfy { $0.userId == normalizedUserA })
    }

    // MARK: - 5. Casual classifier guardrails

    func testCommonCasualCombosDoNotTriggerTraditionalWear() {
        let samples = [
            "blue polo shirt with khaki pants and casual loafers",
            "plain t-shirt with blue jeans and sneakers",
            "hoodie with joggers and running shoes",
            "button-down shirt with chinos and clean sneakers",
            "dress shirt with slacks and brown dress shoes"
        ]

        for sample in samples {
            let rankings = StyleClassificationGuardrails.rankedStyles(for: sample, baseScore: 84)
            let top = rankings.first?.name
            let traditionalRank = rankings.first(where: { $0.name == "Traditional Wear" })?.rankingScore ?? 0

            XCTAssertNotEqual(top, "Traditional Wear", "\(sample) should not rank as Traditional Wear")
            XCTAssertLessThan(traditionalRank, 50, "\(sample) should not rank Traditional Wear highly")
            XCTAssertTrue(rankings.allSatisfy { $0.customerVisibleConfidence == nil })
        }
    }

    func testPoloKhakisClassifyAsCasualOrSmartCasualNotCeremonial() {
        let rankings = StyleClassificationGuardrails.rankedStyles(
            for: "blue polo shirt khaki pants brown casual shoes",
            baseScore: 84
        )

        XCTAssertTrue(["Casual", "Smart Casual", "Business Casual"].contains(rankings.first?.name ?? ""))
        XCTAssertLessThan(rankings.first(where: { $0.name == "Traditional Wear" })?.rankingScore ?? 0, 50)
        XCTAssertTrue(rankings.allSatisfy { $0.customerVisibleConfidence == nil })
    }

    func testGenericStyleFallbackDoesNotInventMeasuredConfidence() {
        let rankings = StyleClassificationGuardrails.rankedStyles(
            for: "plain visible outfit without a supported style evidence branch",
            baseScore: 80
        )

        XCTAssertFalse(rankings.isEmpty)
        XCTAssertTrue(rankings.allSatisfy { $0.customerVisibleConfidence == nil })
        XCTAssertTrue(rankings.allSatisfy { $0.provenance == .deterministicHeuristic })
    }

    func testEveryStyleRankingBranchWithholdsUncalibratedScoresFromEncodingAndDisplay() throws {
        let fixtures = [
            "",
            "bathrobe pajama pants fuzzy slippers bedroom",
            "traditional cultural ceremonial garment",
            "plaid flannel shirt blue jeans hiking boots",
            "youth graphic shirt everyday home outfit",
            "button-down dress shirt chinos loafers",
            "oversized hoodie streetwear sneakers",
            "plain visible everyday outfit"
        ]

        for fixture in fixtures {
            let rankings = StyleClassificationAuthority.rankedStyles(
                for: fixture,
                baseScore: 84
            )
            let encoded = String(
                decoding: try JSONEncoder().encode(rankings),
                as: UTF8.self
            )

            XCTAssertFalse(rankings.isEmpty, "Expected rankings for fixture: \(fixture)")
            XCTAssertEqual(
                rankings.map(\.rankingScore),
                rankings.map(\.rankingScore).sorted(by: >),
                "Rankings must remain ordered for fixture: \(fixture)"
            )
            XCTAssertTrue(
                rankings.allSatisfy { $0.provenance != .calibratedModelConfidence },
                "No current branch produces calibrated confidence: \(fixture)"
            )
            XCTAssertTrue(
                rankings.allSatisfy { $0.customerVisibleConfidence == nil },
                "Ordering scores must remain hidden for fixture: \(fixture)"
            )
            XCTAssertFalse(encoded.contains("rankingScore"))
            XCTAssertFalse(encoded.contains("customerVisibleConfidence"))
            XCTAssertFalse(encoded.contains("calibrated_model_confidence"))
        }
    }

    func testSleepwearLabelsClassifyAsSleepwearNotBusinessCasual() {
        let samples = [
            "bathrobe pajama pants fuzzy slippers bedroom",
            "plush robe nightwear bedroom slippers",
            "children's sleepwear pajama set house shoes",
            "loungewear lounge set homewear"
        ]

        for sample in samples {
            let rankings = StyleClassificationGuardrails.rankedStyles(for: sample, baseScore: 82)
            XCTAssertEqual(rankings.first?.name, "Sleepwear", "\(sample) should rank as Sleepwear")
            XCTAssertLessThanOrEqual(
                rankings.first(where: { $0.name == "Business Casual" })?.rankingScore ?? 100,
                12,
                "\(sample) should block Business Casual"
            )
            XCTAssertTrue(rankings.allSatisfy { $0.customerVisibleConfidence == nil })
        }
    }

    func testSleepwearImageNetLabelsMapToSleepwearCategory() {
        let samples = [
            "pajama pyjama bathrobe slipper",
            "nightgown bedroom slipper housecoat",
            "robe plush slipper loungewear",
            "sleepwear nightwear onesie house shoe"
        ]

        for sample in samples {
            let rankings = StyleClassificationGuardrails.rankedStyles(for: sample, baseScore: 80)
            XCTAssertEqual(rankings.first?.name, "Sleepwear", "\(sample) should map to Sleepwear")
            XCTAssertLessThanOrEqual(
                rankings.first(where: { $0.name == "Business Casual" })?.rankingScore ?? 100,
                12,
                "\(sample) should not allow Business Casual"
            )
            XCTAssertTrue(rankings.allSatisfy { $0.customerVisibleConfidence == nil })
        }
    }

    func testUnmappedLowConfidenceEvidenceDoesNotDefaultToBusinessCasual() {
        let rankings = StyleClassificationGuardrails.rankedStyles(
            for: "unrecognized category uncertain low confidence",
            baseScore: 90
        )

        XCTAssertEqual(rankings.first?.name, "Unrecognized Item")
        XCTAssertLessThanOrEqual(rankings.first(where: { $0.name == "Business Casual" })?.rankingScore ?? 100, 0)
        XCTAssertTrue(rankings.allSatisfy { $0.customerVisibleConfidence == nil })
    }

    func testRegularCasualDoesNotTriggerSleepwear() {
        let samples = [
            "plain t-shirt blue jeans sneakers",
            "button-down shirt chinos clean sneakers",
            "blue polo shirt khaki pants",
            "hoodie joggers running shoes"
        ]

        for sample in samples {
            let rankings = StyleClassificationGuardrails.rankedStyles(for: sample, baseScore: 82)
            XCTAssertNotEqual(rankings.first?.name, "Sleepwear", "\(sample) should not rank as Sleepwear")
        }
    }

    func testMatchingHomePajamaSetDoesNotFallThroughToCasual() {
        let rankings = StyleClassificationGuardrails.rankedStyles(
            for: "girl wearing matching red and white striped two-piece shirt and pants set in a bedroom at home",
            baseScore: 82
        )

        XCTAssertEqual(rankings.first?.name, "Sleepwear")
        XCTAssertLessThan(
            rankings.first(where: { $0.name == "Casual" })?.rankingScore ?? 100,
            rankings.first?.rankingScore ?? 0
        )
        XCTAssertLessThanOrEqual(
            rankings.first(where: { $0.name == "Business Casual" })?.rankingScore ?? 100,
            12
        )
        XCTAssertTrue(rankings.allSatisfy { $0.customerVisibleConfidence == nil })
    }

    func testStripedPoloWithoutHomeSetContextDoesNotTriggerSleepwear() {
        let rankings = StyleClassificationGuardrails.rankedStyles(
            for: "red and white striped polo shirt with chinos and clean sneakers outdoors",
            baseScore: 82
        )

        XCTAssertNotEqual(rankings.first?.name, "Sleepwear")
    }

    // MARK: - 6. Phase 2 personalization context

    func testEmptyProfileOmitsPersonalizationContext() {
        let profile = makeStylistProfile(userId: userA)
        let context = PersonalizationContextBuilder.buildContext(profile: profile, recentMemories: [])

        XCTAssertTrue(context.isEmpty, "A fresh profile should omit the personalization block and preserve generic AI behavior")
    }

    func testPartialProfileOnlyMentionsPresentFields() {
        var profile = makeStylistProfile(userId: userA)
        profile.favoriteColors = ["navy", "olive"]

        let context = PersonalizationContextBuilder.buildContext(profile: profile, recentMemories: [])

        XCTAssertTrue(context.contains("Favorite colors: navy, olive"))
        XCTAssertFalse(context.contains("Favorite brands"))
        XCTAssertFalse(context.contains("Budget"))
        XCTAssertFalse(context.contains("Sizes"))
        XCTAssertFalse(context.contains(userA), "Prompt context must not expose user IDs")
    }

    func testDeclaredUndertoneStaysLocalAndOutOfNetworkPromptContext() {
        var profile = makeStylistProfile(userId: userA)
        profile.declaredUndertone = .warm

        let declaredContext = PersonalizationContextBuilder.buildContext(profile: profile, recentMemories: [])

        XCTAssertFalse(declaredContext.contains("Declared color undertone"))
        XCTAssertFalse(declaredContext.contains("warm undertone"))

        profile.declaredUndertone = .notSure
        let notSureContext = PersonalizationContextBuilder.buildContext(profile: profile, recentMemories: [])

        XCTAssertFalse(notSureContext.contains("Declared color undertone"))

        profile.declaredUndertone = nil
        let emptyContext = PersonalizationContextBuilder.buildContext(profile: profile, recentMemories: [])

        XCTAssertFalse(emptyContext.contains("Declared color undertone"))
    }

    func testStyleConsultationProfileFieldsRoundTripAndStayOutOfNetworkPromptContext() {
        let store = ProfileStore(defaults: defaults, userId: userA)
        var profile = store.currentProfile
        profile.favoriteColors = ["navy"]
        profile.dislikedColors = ["neon"]
        profile.favoriteBrands = ["Nike"]
        profile.declaredUndertone = .neutral
        profile.preferredPantFit = .relaxed
        profile.styleGoals = ["Build confidence", "Spend more intentionally"]
        profile.preferredNeutrals = ["Black", "White"]
        profile.preferredAccentColors = ["Olive", "Burgundy"]
        profile.comfortPreferences = ["I prioritize comfort", "I prefer lightweight fabrics"]
        profile.preferredPantRise = "Mid"
        profile.shoppingFocus = "Value-focused"
        profile.preferredShoppingCategories = ["Shoes", "Accessories"]
        profile.workSetting = "Office"
        profile.travelFrequency = "Monthly"
        profile.hobbiesActivities = ["Gym", "Travel"]
        profile.stylistVoice = "Encouraging Coach"
        store.currentProfile = profile
        store.save()

        let reloaded = ProfileStore(defaults: defaults, userId: userA).currentProfile

        XCTAssertEqual(reloaded.declaredUndertone, .neutral)
        XCTAssertEqual(reloaded.preferredPantFit, .relaxed)
        XCTAssertEqual(reloaded.styleGoals, ["Build confidence", "Spend more intentionally"])
        XCTAssertEqual(reloaded.preferredNeutrals, ["Black", "White"])
        XCTAssertEqual(reloaded.preferredAccentColors, ["Olive", "Burgundy"])
        XCTAssertEqual(reloaded.comfortPreferences, ["I prioritize comfort", "I prefer lightweight fabrics"])
        XCTAssertEqual(reloaded.preferredPantRise, "Mid")
        XCTAssertEqual(reloaded.shoppingFocus, "Value-focused")
        XCTAssertEqual(reloaded.preferredShoppingCategories, ["Shoes", "Accessories"])
        XCTAssertEqual(reloaded.workSetting, "Office")
        XCTAssertEqual(reloaded.travelFrequency, "Monthly")
        XCTAssertEqual(reloaded.hobbiesActivities, ["Gym", "Travel"])
        XCTAssertEqual(reloaded.stylistVoice, "Encouraging Coach")

        let context = PersonalizationContextBuilder.buildContext(profile: reloaded, recentMemories: [])

        XCTAssertFalse(context.contains("Style goals"))
        XCTAssertFalse(context.contains("Build confidence"))
        XCTAssertFalse(context.contains("Preferred neutrals"))
        XCTAssertFalse(context.contains("Preferred accent colors"))
        XCTAssertFalse(context.contains("Comfort preferences"))
        XCTAssertFalse(context.contains("Declared color undertone"))
        XCTAssertTrue(context.contains("Preferred pant fit: Relaxed Fit"))
        XCTAssertTrue(context.contains("Preferred pant rise: Mid Rise"))
        XCTAssertFalse(context.contains("Shopping focus"))
        XCTAssertFalse(context.contains("Preferred shopping categories"))
        XCTAssertFalse(context.contains("Work setting"))
        XCTAssertFalse(context.contains("Travel frequency"))
        XCTAssertFalse(context.contains("Hobbies and activities"))
        XCTAssertFalse(context.contains("Stylist voice"))
        XCTAssertTrue(context.contains("Personalize only; never change StyleMatch Pro scores."))
        XCTAssertFalse(context.contains(userA), "Prompt context must not expose user IDs")
    }

    func testOlderStoredStylistProfileDecodesWhenStyleConsultationFieldsAreAbsent() throws {
        let olderProfileJSON = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "userId": "\(userA)",
          "givenName": "Alex",
          "favoriteColors": ["Navy", "Olive"],
          "dislikedColors": ["Neon"],
          "favoriteBrands": ["Nike", "Levi's"],
          "preferredFit": "regular",
          "budgetRange": {
            "minPrice": 50,
            "maxPrice": 200,
            "preferredTier": "Mid"
          },
          "clothingSizes": {
            "shirtSize": "L",
            "pantSize": "Men 36x36",
            "shoeSize": "10"
          },
          "stylePreferencesLearned": {},
          "totalScansCompleted": 12,
          "profileConfidenceScore": 64
        }
        """

        let profile = try JSONDecoder().decode(StylistProfile.self, from: Data(olderProfileJSON.utf8))

        XCTAssertEqual(profile.userId, userA)
        XCTAssertEqual(profile.favoriteColors, ["Navy", "Olive"])
        XCTAssertEqual(profile.dislikedColors, ["Neon"])
        XCTAssertEqual(profile.favoriteBrands, ["Nike", "Levi's"])
        XCTAssertEqual(profile.preferredFit, .regular)
        XCTAssertEqual(profile.budgetRange.minPrice, 50)
        XCTAssertEqual(profile.budgetRange.maxPrice, 200)
        XCTAssertEqual(profile.budgetRange.preferredTier, "Mid")
        XCTAssertEqual(profile.clothingSizes.shirtSize, "L")
        XCTAssertEqual(profile.clothingSizes.pantSize, "Men 36x36")
        XCTAssertEqual(profile.clothingSizes.shoeSize, "10")
        XCTAssertNil(profile.declaredUndertone)
        XCTAssertTrue(profile.styleGoals.isEmpty)
        XCTAssertTrue(profile.preferredNeutrals.isEmpty)
        XCTAssertTrue(profile.preferredAccentColors.isEmpty)
        XCTAssertTrue(profile.comfortPreferences.isEmpty)
        XCTAssertTrue(profile.preferredPantRise.isEmpty)
        XCTAssertTrue(profile.shoppingFocus.isEmpty)
        XCTAssertTrue(profile.preferredShoppingCategories.isEmpty)
        XCTAssertTrue(profile.workSetting.isEmpty)
        XCTAssertTrue(profile.travelFrequency.isEmpty)
        XCTAssertTrue(profile.hobbiesActivities.isEmpty)
        XCTAssertTrue(profile.stylistVoice.isEmpty)
    }

    func testPartialConsultationPersistencePreservesExistingProfileValues() {
        let store = ProfileStore(defaults: defaults, userId: userA)
        var profile = store.currentProfile
        profile.favoriteColors = ["Navy"]
        profile.favoriteBrands = ["Nike"]
        profile.preferredFit = .regular
        profile.budgetRange = BudgetRange(minPrice: 50, maxPrice: 200, preferredTier: "Mid")
        profile.clothingSizes = ClothingSizes(shirtSize: "L", pantSize: "Men 36x36", shoeSize: "10")
        store.currentProfile = profile
        store.save()

        let partialStore = ProfileStore(defaults: defaults, userId: userA)
        var partialProfile = partialStore.currentProfile
        partialProfile.styleGoals = ["Build confidence"]
        partialProfile.preferredNeutrals = ["Black"]
        partialProfile.stylistVoice = "Encouraging Coach"
        partialStore.currentProfile = partialProfile
        partialStore.save()

        let reloaded = ProfileStore(defaults: defaults, userId: userA).currentProfile

        XCTAssertEqual(reloaded.favoriteColors, ["Navy"])
        XCTAssertEqual(reloaded.favoriteBrands, ["Nike"])
        XCTAssertEqual(reloaded.preferredFit, .regular)
        XCTAssertEqual(reloaded.budgetRange.minPrice, 50)
        XCTAssertEqual(reloaded.budgetRange.maxPrice, 200)
        XCTAssertEqual(reloaded.clothingSizes.shirtSize, "L")
        XCTAssertEqual(reloaded.clothingSizes.pantSize, "Men 36x36")
        XCTAssertEqual(reloaded.clothingSizes.shoeSize, "10")
        XCTAssertEqual(reloaded.styleGoals, ["Build confidence"])
        XCTAssertEqual(reloaded.preferredNeutrals, ["Black"])
        XCTAssertEqual(reloaded.stylistVoice, "Encouraging Coach")
    }

    func testStyleProfilePersonalizationContextContainsOnlyConfirmedPreferences() {
        var emptyProfile = makeStylistProfile(userId: userA)
        emptyProfile.favoriteColors = ["", "   "]
        emptyProfile.dislikedColors = []
        emptyProfile.favoriteBrands = []
        emptyProfile.declaredUndertone = .notSure
        emptyProfile.preferredFit = .unset
        emptyProfile.styleGoals = []
        emptyProfile.preferredNeutrals = []
        emptyProfile.preferredAccentColors = []
        emptyProfile.comfortPreferences = []
        emptyProfile.preferredPantRise = ""
        emptyProfile.shoppingFocus = ""
        emptyProfile.preferredShoppingCategories = []
        emptyProfile.workSetting = ""
        emptyProfile.travelFrequency = ""
        emptyProfile.hobbiesActivities = []
        emptyProfile.stylistVoice = ""
        emptyProfile.budgetRange = .neutral
        emptyProfile.clothingSizes = ClothingSizes(shirtSize: " ", pantSize: nil, shoeSize: nil)

        let emptyContext = emptyProfile.personalizationContext

        XCTAssertFalse(emptyContext.hasUserConfirmedPreferences)
        XCTAssertNil(emptyContext.declaredUndertone)
        XCTAssertNil(emptyContext.preferredFit)
        XCTAssertNil(emptyContext.budgetRange)
        XCTAssertFalse(emptyContext.clothingSizes.hasAnyValue)

        emptyProfile.declaredUndertone = .preferNotToSay
        XCTAssertNil(emptyProfile.personalizationContext.declaredUndertone)
        XCTAssertFalse(emptyProfile.personalizationContext.hasUserConfirmedPreferences)

        var profile = emptyProfile
        profile.favoriteColors = [" Navy ", "Olive"]
        profile.dislikedColors = ["Neon"]
        profile.favoriteBrands = ["Nike"]
        profile.declaredUndertone = .cool
        profile.preferredFit = .relaxed
        profile.preferredPantFit = .athletic
        profile.styleGoals = ["Build confidence"]
        profile.preferredNeutrals = ["Black", "White"]
        profile.preferredAccentColors = ["Burgundy"]
        profile.comfortPreferences = ["I prioritize comfort"]
        profile.preferredPantRise = "Mid"
        profile.shoppingFocus = "Value-focused"
        profile.preferredShoppingCategories = ["Shoes"]
        profile.workSetting = "Office"
        profile.travelFrequency = "Monthly"
        profile.hobbiesActivities = ["Gym"]
        profile.stylistVoice = "Encouraging Coach"
        profile.budgetRange = BudgetRange(minPrice: 25, maxPrice: 75, preferredTier: "Value")
        profile.clothingSizes = ClothingSizes(shirtSize: "L", pantSize: "36 x 32", shoeSize: "10")

        let context = profile.personalizationContext

        XCTAssertTrue(context.hasUserConfirmedPreferences)
        XCTAssertEqual(context.favoriteColors, ["Navy", "Olive"])
        XCTAssertEqual(context.avoidedColors, ["Neon"])
        XCTAssertEqual(context.favoriteBrands, ["Nike"])
        XCTAssertEqual(context.declaredUndertone, .cool)
        XCTAssertEqual(context.preferredFit, .relaxed)
        XCTAssertEqual(context.preferredPantFit, .athletic)
        XCTAssertEqual(context.styleGoals, ["Build confidence"])
        XCTAssertEqual(context.preferredNeutrals, ["Black", "White"])
        XCTAssertEqual(context.preferredAccentColors, ["Burgundy"])
        XCTAssertEqual(context.comfortPreferences, ["I prioritize comfort"])
        XCTAssertEqual(context.preferredPantRise, "Mid")
        XCTAssertEqual(context.shoppingFocus, "Value-focused")
        XCTAssertEqual(context.preferredShoppingCategories, ["Shoes"])
        XCTAssertEqual(context.workSetting, "Office")
        XCTAssertEqual(context.travelFrequency, "Monthly")
        XCTAssertEqual(context.hobbiesActivities, ["Gym"])
        XCTAssertEqual(context.stylistVoice, "Encouraging Coach")
        XCTAssertEqual(context.budgetRange?.preferredTier, "Value")
        XCTAssertEqual(context.clothingSizes.shirtSize, "L")
        XCTAssertEqual(context.clothingSizes.pantSize, "36 x 32")
        XCTAssertEqual(context.clothingSizes.shoeSize, "10")
    }

    func testPersonalStyleProfileDecodesFromOlderProfileAndPersistsAllowedManualPreferences() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let oldProfileJSON = """
        {
          "id": "\(UUID().uuidString)",
          "userId": "\(userA)",
          "favoriteColors": ["Navy"],
          "dislikedColors": [],
          "favoriteBrands": ["Nike"],
          "declaredUndertone": "olive",
          "preferredFit": "regular",
          "budgetRange": { "minPrice": 50, "maxPrice": 200, "preferredTier": "Mid" },
          "climate": "Mild",
          "workDressCode": "Smart casual",
          "clothingSizes": { "shirtSize": "L", "pantSize": "Men 36x36", "shoeSize": "10" },
          "stylePreferencesLearned": {},
          "createdAt": "2026-07-15T12:00:00Z",
          "lastUpdatedAt": "2026-07-15T12:00:00Z",
          "totalScansCompleted": 0,
          "profileConfidenceScore": 20
        }
        """

        var decoded = try decoder.decode(StylistProfile.self, from: Data(oldProfileJSON.utf8))

        XCTAssertNil(decoded.declaredUndertone, "Unsupported legacy undertones must migrate to not provided")
        XCTAssertTrue(decoded.preferredNeutrals.isEmpty)
        XCTAssertTrue(decoded.preferredAccentColors.isEmpty)
        XCTAssertTrue(decoded.comfortPreferences.isEmpty)
        XCTAssertTrue(decoded.styleGoals.isEmpty)
        XCTAssertEqual(decoded.favoriteColors, ["Navy"])
        XCTAssertEqual(decoded.favoriteBrands, ["Nike"])
        XCTAssertEqual(decoded.preferredFit, .regular)
        XCTAssertEqual(decoded.clothingSizes.shirtSize, "L")

        decoded.declaredUndertone = .warm
        decoded.preferredNeutrals = ["Navy", "Cream"]
        decoded.preferredAccentColors = ["Burgundy"]
        decoded.comfortPreferences = ["Lightweight clothing", "Soft fabrics"]
        decoded.styleGoals = ["Shop more intentionally"]

        let store = ProfileStore(defaults: defaults, userId: userA)
        store.currentProfile = decoded
        store.save()

        let reloaded = ProfileStore(defaults: defaults, userId: userA).currentProfile
        XCTAssertEqual(reloaded.declaredUndertone, .warm)
        XCTAssertEqual(reloaded.preferredNeutrals, ["Navy", "Cream"])
        XCTAssertEqual(reloaded.preferredAccentColors, ["Burgundy"])
        XCTAssertEqual(reloaded.comfortPreferences, ["Lightweight clothing", "Soft fabrics"])
        XCTAssertEqual(reloaded.styleGoals, ["Shop more intentionally"])
        XCTAssertEqual(reloaded.favoriteColors, ["Navy"])
        XCTAssertEqual(reloaded.favoriteBrands, ["Nike"])
        XCTAssertEqual(reloaded.preferredFit, .regular)

        let encoded = try encoder.encode(reloaded)
        let roundTripped = try decoder.decode(StylistProfile.self, from: encoded)
        XCTAssertEqual(roundTripped.declaredUndertone, .warm)
        XCTAssertEqual(roundTripped.preferredNeutrals, ["Navy", "Cream"])
        XCTAssertEqual(roundTripped.preferredAccentColors, ["Burgundy"])
        XCTAssertEqual(roundTripped.comfortPreferences, ["Lightweight clothing", "Soft fabrics"])
        XCTAssertEqual(roundTripped.styleGoals, ["Shop more intentionally"])
    }

    func testStyleProfilePersonalizationContextIsNotInjectedIntoScoreOrNetworkPaths() throws {
        let profileModelSource = try projectSource("StyleMatchAI/PersonalStylist/StylistProfileModels.swift")
        let contextBuilderSource = try projectSource("StyleMatchAI/PersonalStylist/StylistContextBuilder.swift")
        let scanSource = try projectSource("StyleMatchAI/ScanView.swift")
        let openAIClientSource = try projectSource("StyleMatchAI/OpenAIStylistClient.swift")
        let chatTransportSource = try projectSource("StyleMatchAI/StylistChat/StylistChatTransport.swift")
        let shareSource = try projectSource("StyleMatchAI/ShareableScoreCard.swift")

        XCTAssertTrue(profileModelSource.contains("var personalizationContext: StyleProfilePersonalizationContext"))
        XCTAssertFalse(contextBuilderSource.contains("profile.personalizationContext"))
        XCTAssertFalse(openAIClientSource.contains("personalizationContext"))
        XCTAssertFalse(chatTransportSource.contains("personalizationContext"))
        XCTAssertFalse(shareSource.contains("personalizationContext"))

        guard let scoreStart = scanSource.range(of: "private func calculateStyleScore(\n        validation:"),
              let scoreEnd = scanSource.range(of: "private func scoreComponents", range: scoreStart.upperBound..<scanSource.endIndex) else {
            XCTFail("Expected to locate calculateStyleScore block")
            return
        }
        let scoreBlock = String(scanSource[scoreStart.lowerBound..<scoreEnd.lowerBound])

        XCTAssertFalse(scoreBlock.contains("personalizationContext"))
        XCTAssertFalse(scoreBlock.contains("StyleProfilePersonalizationContext"))
    }

    func testFullProfileContextIncludesPreferencesAndMemoryWithoutUserIdentity() {
        var profile = makeStylistProfile(userId: userA)
        profile.favoriteColors = ["navy", "black"]
        profile.dislikedColors = ["neon"]
        profile.favoriteBrands = ["Nike"]
        profile.preferredPantFit = .athletic
        profile.budgetRange = BudgetRange(minPrice: 80, maxPrice: 180, preferredTier: "Mid")
        profile.clothingSizes = ClothingSizes(shirtSize: "XL", pantSize: "36x36", shoeSize: "12")
        profile.stylePreferencesLearned = ["business casual": 0.8]

        var liked = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "shirt-navy-solid"))
        liked.detectedGarments = ["shirt", "pants"]
        liked.colors = ["navy", "black"]
        liked.detectedStyle = "Smart Casual"
        liked.styleScore = 92
        liked.wasLiked = true
        liked.wouldWearAgain = true

        var disliked = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "jacket-neon-plaid"))
        disliked.detectedGarments = ["jacket"]
        disliked.colors = ["neon"]
        disliked.detectedStyle = "Casual"
        disliked.styleScore = 64
        disliked.wasLiked = false
        disliked.dislikeReason = .colorsOff

        let context = PersonalizationContextBuilder.buildContext(
            profile: profile,
            recentMemories: [liked, disliked]
        )

        XCTAssertTrue(context.contains("Favorite colors: navy, black"))
        XCTAssertTrue(context.contains("Avoid colors: neon"))
        XCTAssertTrue(context.contains("Favorite brands: Nike"))
        XCTAssertTrue(context.contains("Preferred pant fit: Athletic Fit"))
        XCTAssertTrue(context.contains("Budget: $80-$180"))
        XCTAssertTrue(context.contains("shirt XL"))
        XCTAssertTrue(context.contains("Recently liked"))
        XCTAssertTrue(context.contains("Recently disliked"))
        XCTAssertTrue(context.contains("Personalize only; never change StyleMatch Pro scores."))
        XCTAssertFalse(context.contains(userA), "Prompt context must not expose user IDs")
    }

    func testChatContextOmitsColorInfoWhenPaletteIsMissing() {
        let profile = makeStylistProfile(userId: userA)
        var record = makeGarmentRecord(fingerprint: "missing-palette")
        record.colors = []
        var memory = makeOutfitMemory(userId: userA, record: record)
        memory.detectedGarments = ["shirt", "pants"]
        memory.detectedStyle = "Casual"
        memory.colors = []

        let context = PersonalizationContextBuilder.chatContext(
            profile: profile,
            outfitMemories: [memory],
            memoryLimit: 1
        )

        XCTAssertTrue(context.recentOutfits.contains("shirt, pants"))
        XCTAssertTrue(context.recentOutfits.contains("Casual"))
        XCTAssertFalse(context.profileSummary.localizedCaseInsensitiveContains("Most worn colors"))
        XCTAssertFalse(context.recentOutfits.localizedCaseInsensitiveContains("colors"))
    }

    func testDirectOpenAIStylistClientUsesCanonicalScoreGuard() {
        XCTAssertTrue(StyleMatchAIGuardrails.directOpenAIStylistSystemInstruction.contains(StyleMatchAIGuardrails.scoreIntegrityInstruction))
        XCTAssertFalse(StyleMatchAIGuardrails.directOpenAIStylistSystemInstruction.contains("explain it, improve it, and personalize it without changing it"))
    }

    func testLiveAIClientUsesAccountAuthenticatedWorkerAndAttachesBuilderContext() throws {
        let source = try projectSource("StyleMatchAI/OpenAIStylistClient.swift")
        let transport = try projectSource("StyleMatchAI/StylistChat/StylistChatTransport.swift")

        XCTAssertTrue(source.contains("LiveChatTransport(configuration: configuration)"))
        XCTAssertTrue(source.contains("PersonalizationContextBuilder.legacyChatContext"))
        XCTAssertFalse(source.contains("profileContextBlock"))
        XCTAssertTrue(source.contains("StyleMatchAIGuardrails.directOpenAIStylistSystemInstruction"))
        XCTAssertTrue(transport.contains("Bearer \\(accountSession.token)"))
        XCTAssertFalse(source.contains("api.openai.com"))
        XCTAssertFalse(transport.contains("X-App-Auth"))
    }

    func testApprovedLiveAICallSitesAreEnumerated() throws {
        let approvedFiles = [
            "StyleMatchAI/ContentView.swift": 1,
            // The fourth route is the rare, bounded classification adjudicator.
            // It uses an empty profile and rejects an unavailable or malformed
            // response locally rather than adding a general scan-AI route.
            "StyleMatchAI/ScanView.swift": 4,
            "StyleMatchAI/AIAssistantsView.swift": 1,
            "StyleMatchAI/AIStyleAdvisor.swift": 1
        ]

        for (path, expectedCount) in approvedFiles {
            let source = try projectSource(path)
            XCTAssertEqual(
                source.components(separatedBy: "OpenAIStylistClient(").count - 1,
                expectedCount,
                "Unexpected live AI client construction count in \(path)."
            )
        }

        let scanSource = try projectSource("StyleMatchAI/ScanView.swift")
        XCTAssertTrue(scanSource.contains("requestOutfitClassificationAdjudication"))
        XCTAssertTrue(scanSource.contains("Bounded scan classification adjudication"))
        XCTAssertTrue(scanSource.contains("OutfitClassificationAdjudicator.applying"))
    }

    func testEveryApprovedAIClientRouteUsesTheConsentGatedSharedTransport() throws {
        let transport = try projectSource("StyleMatchAI/StylistChat/StylistChatTransport.swift")
        let client = try projectSource("StyleMatchAI/OpenAIStylistClient.swift")
        let scan = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(transport.contains("guard aiTransmissionConsentState == .accepted"))
        XCTAssertTrue(transport.contains("StylistChatError.aiTransmissionConsentRequired"))
        XCTAssertTrue(client.contains("LiveChatTransport(configuration: configuration)"))
        XCTAssertTrue(scan.contains("requestChatGPTRecommendationUpgrade"))
        XCTAssertTrue(scan.contains("requestOutfitClassificationAdjudication"))
        XCTAssertTrue(scan.contains("OpenAIStylistClient("))
    }

    func testDirectProviderAdaptersAreRetiredFromTheProductionTree() {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("StyleMatchAI/AIProviderAdapters.swift").path))
    }

    func testPersonalizationContextCapsMemoryDigest() {
        var profile = makeStylistProfile(userId: userA)
        profile.favoriteColors = ["black"]

        let memories = (0..<15).map { index in
            var memory = makeOutfitMemory(
                userId: userA,
                record: makeGarmentRecord(fingerprint: "shirt-\(index)")
            )
            memory.detectedGarments = ["shirt \(index)"]
            memory.wasLiked = true
            memory.scanDate = Date().addingTimeInterval(Double(-index * 60))
            return memory
        }

        let context = PersonalizationContextBuilder.buildContext(
            profile: profile,
            recentMemories: memories,
            maxMemories: 10
        )

        XCTAssertTrue(context.contains("shirt 0"))
        XCTAssertTrue(context.contains("shirt 9"))
        XCTAssertFalse(context.contains("shirt 10"), "Memory digest should be capped for token discipline")
    }

    // MARK: - Phase 4 occasion awareness

    func testOccasionCodableAndLegacyLabelDecoding() throws {
        let encoded = try JSONEncoder().encode(Occasion.weddingGuest)
        let decoded = try JSONDecoder().decode(Occasion.self, from: encoded)
        XCTAssertEqual(decoded, .weddingGuest)

        let legacyWedding = try JSONDecoder().decode(Occasion.self, from: Data("\"wedding\"".utf8))
        XCTAssertEqual(legacyWedding, .weddingGuest)

        XCTAssertEqual(Occasion(label: "General"), .general)
        XCTAssertEqual(Occasion(label: "Everyday"), .casualDay)
        XCTAssertEqual(Occasion(label: "Date Night"), .dateNight)
        XCTAssertEqual(Occasion(label: "Business Formal"), .businessFormal)
        XCTAssertEqual(Occasion(label: "Wedding Guest"), .weddingGuest)
        XCTAssertEqual(Occasion(label: "Gym"), .gym)
        XCTAssertEqual(Occasion(label: "Loungewear"), .loungewear)
        XCTAssertTrue(Occasion.allCases.contains(.specialEvent))

        let legacyJSON = """
        {
          "id": "\(UUID().uuidString)",
          "userId": "\(userA)",
          "scanDate": 0,
          "detectedGarments": ["shirt"],
          "colors": ["white"],
          "detectedStyle": "Casual",
          "styleScore": 82,
          "isFavorite": false,
          "timesWorn": 0
        }
        """
        let memory = try JSONDecoder().decode(OutfitMemory.self, from: Data(legacyJSON.utf8))
        XCTAssertNil(memory.occasion)
    }

    func testPrePhase4OutfitMemoryWithPhase3FeedbackDecodesAndCanonicalizesOccasion() throws {
        let id = UUID(uuidString: "22222222-3333-4444-5555-666666666666")!
        let json = """
        {
          "id": "\(id.uuidString)",
          "userId": "\(userA)",
          "scanDate": 1720310400,
          "detectedGarments": ["robe", "slippers"],
          "colors": ["navy"],
          "detectedStyle": "Loungewear",
          "styleScore": 78,
          "occasion": "wedding",
          "feedback": {
            "verdict": "notForMe",
            "woreIt": true,
            "recordedAt": 1720396800
          },
          "isFavorite": false,
          "timesWorn": 1
        }
        """

        let decoded = try JSONDecoder().decode(OutfitMemory.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.occasion, .weddingGuest)
        XCTAssertEqual(decoded.feedback?.verdict, .notForMe)
        XCTAssertEqual(decoded.feedback?.woreIt, true)
    }

    func testOutfitMemoryStoresSelectedOccasion() {
        let store = OutfitMemoryStore(defaults: defaults, userId: userA, snapshotRoot: snapshotTestRoot)
        var memory = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "occasion-work"))
        memory.occasion = .work

        store.addScan(memory)

        let saved = OutfitMemoryStore(defaults: defaults, userId: userA, snapshotRoot: snapshotTestRoot).memories.first { $0.id == memory.id }
        XCTAssertEqual(saved?.occasion, .work)
    }

    func testOutfitMemoryStoreUpdatesOccasionThroughExistingSavePath() {
        let store = OutfitMemoryStore(defaults: defaults, userId: userA, snapshotRoot: snapshotTestRoot)
        let memory = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "occasion-update"))
        store.addScan(memory)

        store.updateOccasion(for: memory.id, occasion: .dateNight)

        let saved = OutfitMemoryStore(defaults: defaults, userId: userA, snapshotRoot: snapshotTestRoot).memories.first { $0.id == memory.id }
        XCTAssertEqual(saved?.occasion, .dateNight)
    }

    func testSavedScanHistoryHasEditableOccasionRowUsingExistingUpdatePath() throws {
        let scanSource = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(scanSource.contains("savedScanOccasionRow"))
        XCTAssertTrue(scanSource.contains("updateSavedScanOccasion"))
        XCTAssertTrue(scanSource.contains("updateOccasion(occasion, for: scan.analysis)"))
        XCTAssertTrue(scanSource.contains("store.updateOccasion(for: memory.id, occasion: occasion)"))
    }

    func testSavedScanOccasionFlowsFromStoredRecordToStylistWithoutReinference() throws {
        let scanSource = try projectSource("StyleMatchAI/ScanView.swift")

        // The open action restores the persisted canonical value before it
        // publishes the exact saved scan for Continue Styling / AI Stylist.
        XCTAssertTrue(scanSource.contains("selectedScanOccasion = scan.occasion?.canonical ?? .general"))
        XCTAssertTrue(scanSource.contains("publishCurrentStylistScanHandoff(source: \"saved_scan_open\")"))
        XCTAssertTrue(scanSource.contains("selectedOccasion: selectedScanOccasion.canonical?.displayName"))

        // Recent Scores is constructed from the same StoredOutfitScan field,
        // and its display resolver consumes that persisted value rather than
        // running a new occasion classifier.
        XCTAssertTrue(scanSource.contains("occasion: storedScan.occasion"))
        XCTAssertTrue(scanSource.contains("legacyCanonicalOccasion: occasion"))

        // A user correction updates the canonical stored field. There is no
        // historical bulk rewrite path in this source contract.
        XCTAssertTrue(scanSource.contains("stored.occasion = occasion?.canonical"))
    }

    func testFormalityMismatchEvaluatorRules() {
        XCTAssertNil(FormalityMismatchEvaluator.evaluate(detectedStyle: "Smart Casual", occasion: .work))
        XCTAssertNil(FormalityMismatchEvaluator.evaluate(detectedStyle: "Formal", occasion: .weddingGuest))
        XCTAssertNil(FormalityMismatchEvaluator.evaluate(detectedStyle: "Casual", occasion: nil))

        let workMismatch = FormalityMismatchEvaluator.evaluate(detectedStyle: "Casual", occasion: .work)
        XCTAssertEqual(workMismatch?.detectedFormality, .casual)
        XCTAssertEqual(workMismatch?.occasion, .work)

        let weddingMismatch = FormalityMismatchEvaluator.evaluate(detectedStyle: "Business Casual", occasion: .weddingGuest)
        XCTAssertEqual(weddingMismatch?.detectedFormality, .businessCasual)
        XCTAssertEqual(weddingMismatch?.occasion, .weddingGuest)
    }

    func testFormalityMismatchFlagsSleepwearForDressierOccasions() {
        let workMismatch = FormalityMismatchEvaluator.evaluate(detectedStyle: "Loungewear", occasion: .work)
        XCTAssertEqual(workMismatch?.detectedFormality, .sleepwear)

        let weddingMismatch = FormalityMismatchEvaluator.evaluate(detectedStyle: "Sleepwear", occasion: .weddingGuest)
        XCTAssertEqual(weddingMismatch?.detectedFormality, .sleepwear)

        let businessFormalMismatch = FormalityMismatchEvaluator.evaluate(detectedStyle: "Sleepwear", occasion: .businessFormal)
        XCTAssertEqual(businessFormalMismatch?.occasion, .businessFormal)

        XCTAssertNil(FormalityMismatchEvaluator.evaluate(detectedStyle: "Casual", occasion: .casualDay))
    }

    func testOccasionConflictTableIsExactAndDeterministic() {
        XCTAssertTrue(FormalityMismatchEvaluator.hasExplicitConflict(formality: .sleepwear, occasion: .work))
        XCTAssertTrue(FormalityMismatchEvaluator.hasExplicitConflict(formality: .sleepwear, occasion: .businessFormal))
        XCTAssertTrue(FormalityMismatchEvaluator.hasExplicitConflict(formality: .sleepwear, occasion: .weddingGuest))
        XCTAssertFalse(FormalityMismatchEvaluator.hasExplicitConflict(formality: .casual, occasion: .casualDay))
        XCTAssertFalse(FormalityMismatchEvaluator.hasExplicitConflict(formality: .sleepwear, occasion: .casualDay))
    }

    func testOccasionWarningDoesNotChangeScoreData() {
        let fixedScore = 82
        let mismatch = FormalityMismatchEvaluator.evaluate(detectedStyle: "Casual", occasion: .weddingGuest)

        XCTAssertNotNil(mismatch)
        XCTAssertEqual(fixedScore, 82, "Occasion mismatch is a parallel warning and must not mutate score data.")
    }

    func testPersonalizationContextOccasionSignalsAreAggregateAndPrivate() {
        var profile = makeStylistProfile(userId: userA)
        profile.favoriteColors = ["navy"]

        var workMemory = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "work-occasion"))
        workMemory.occasion = .work
        workMemory.wasLiked = true
        workMemory.scanDate = Date(timeIntervalSince1970: 0)

        var weddingMemory = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "wedding-occasion"))
        weddingMemory.occasion = .weddingGuest
        weddingMemory.wasLiked = false
        weddingMemory.dislikeReason = .tooCasual
        weddingMemory.scanDate = Date(timeIntervalSince1970: 86_400)

        let context = PersonalizationContextBuilder.buildContext(
            profile: profile,
            recentMemories: [workMemory, weddingMemory],
            maxMemories: 10
        )

        XCTAssertTrue(context.contains("Occasion patterns"))
        XCTAssertTrue(context.contains("work 1x"), context)
        XCTAssertTrue(context.contains("wedding guest disliked for too casual"))
        XCTAssertFalse(context.contains(userA), "Occasion context must not expose user IDs")
        XCTAssertFalse(context.contains(workMemory.id.uuidString), "Occasion context must not expose scan IDs")
        XCTAssertFalse(context.contains("1970"), "Occasion context must not expose scan dates")
    }

    func testOccasionContextDropOrderUnderTokenPressure() {
        var loved = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "occasion-loved"))
        loved.occasion = .dateNight
        loved.feedback = OutfitFeedback(verdict: .loved, woreIt: true, recordedAt: Date(timeIntervalSince1970: 4_500_000))

        var disliked = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "occasion-disliked"))
        disliked.occasion = .work
        disliked.feedback = OutfitFeedback(verdict: .notForMe, woreIt: true, recordedAt: Date(timeIntervalSince1970: 4_500_100))

        let full = PersonalizationContextBuilder.occasionContextLines(
            recentMemories: [loved, disliked],
            currentOccasion: .weddingGuest
        )
        XCTAssertTrue(full.contains { $0.contains("Feedback signals") })
        XCTAssertTrue(full.contains { $0.contains("Occasion patterns") })
        XCTAssertTrue(full.contains { $0.contains("Current scan occasion") })

        let constrained = PersonalizationContextBuilder.occasionContextLines(
            recentMemories: [loved, disliked],
            currentOccasion: .weddingGuest,
            maxCharacters: 95
        )
        XCTAssertFalse(constrained.contains { $0.contains("Occasion patterns") }, "Trend should drop first.")
        XCTAssertFalse(constrained.contains { $0.contains("Feedback signals") }, "Feedback should drop second when needed.")
        XCTAssertTrue(constrained.contains { $0.contains("Current scan occasion") }, "Per-scan occasion should drop last.")
    }

    func testPersonalizationContextAddsCurrentScanOccasionOnlyWhenTagged() {
        var profile = makeStylistProfile(userId: userA)
        profile.favoriteColors = ["black"]
        let memory = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "untagged-context"))

        let untagged = PersonalizationContextBuilder.buildContext(
            profile: profile,
            recentMemories: [memory],
            maxMemories: 10
        )
        let explicitNil = PersonalizationContextBuilder.buildContext(
            profile: profile,
            recentMemories: [memory],
            maxMemories: 10,
            currentOccasion: nil
        )
        let tagged = PersonalizationContextBuilder.buildContext(
            profile: profile,
            recentMemories: [memory],
            maxMemories: 10,
            currentOccasion: .dateNight
        )

        XCTAssertEqual(untagged, explicitNil, "Untagged scans should preserve the existing context output exactly.")
        XCTAssertTrue(tagged.contains("Current scan occasion"))
        XCTAssertTrue(tagged.contains("The user tagged this outfit for: Date Night."))
    }

    func testOccasionCannotEnterNumericScorePath() throws {
        let scanSource = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertFalse(scanSource.contains("scoreOccasion("))
        XCTAssertFalse(scanSource.contains("context.occasion"))
        XCTAssertFalse(scanSource.contains("occasionFit: plannedOccasionSummary"))
        XCTAssertTrue(scanSource.contains("Occasion is explanation-only; never a score input."))
        XCTAssertTrue(
            scanSource.contains("var total = normalizedScore(for: breakdown)"),
            "Removing the 20-point occasion component should use only the mechanical 80-to-100 normalization."
        )
        XCTAssertTrue(scanSource.contains("Occasion is informational and excluded from scoring."))
    }

    // MARK: - 7. Personal Stylist Intelligence

    func testPersonalStylistIntelligencePreservesScoreParity() {
        let input = makePersonalStylistInput(score: 87)
        let message = PersonalStylistIntelligenceBuilder.buildMessage(input: input)
        let phrasingContext = PersonalStylistIntelligenceBuilder.buildPhrasingContext(input: input)

        XCTAssertEqual(input.score, 87)
        XCTAssertEqual(phrasingContext.score, 87)
        XCTAssertTrue(message.plainText.contains("87/100"))
        XCTAssertFalse(message.plainText.contains("88/100"))
        XCTAssertFalse(message.plainText.contains("86/100"))
    }

    func testStylistMessageComposerScoreBandsAlwaysUseActualAttributes() {
        let samples: [(Int, StylistScoreBand)] = [
            (95, .enthusiastic),
            (82, .confidentPositive),
            (67, .encouragingImprovement),
            (48, .constructiveKind)
        ]

        for sample in samples {
            let input = StylistScoreMessageInput(
                score: sample.0,
                scoreTier: "Test",
                scoreBreakdown: OutfitScoreBreakdown(
                    colorHarmony: 12,
                    patternBalance: 18,
                    fitQuality: 20,
                    occasionMatch: 16,
                    accessoryUse: 4
                ),
                detectedGarments: ["shirt"],
                detectedItemConfidences: [
                    DetectedItemConfidence(item: "shirt", confidence: 96)
                ],
                colors: ["navy"]
            )
            let message = StylistMessageComposer.scoreEncouragement(input: input)

            XCTAssertEqual(StylistScoreBand(score: sample.0), sample.1)
            XCTAssertTrue(message.body.contains("\(sample.0)/100"))
            XCTAssertTrue(message.body.localizedCaseInsensitiveContains("detected navy palette"))
            XCTAssertFalse(message.body.localizedCaseInsensitiveContains("navy shirt"))
        }
    }

    func testStylistMessageComposerFallsBackToScoreWhenNoGarmentAttributeExists() {
        let message = StylistMessageComposer.scoreEncouragement(
            input: StylistScoreMessageInput(
                score: 58,
                scoreTier: "Needs Work",
                scoreBreakdown: nil,
                detectedGarments: [],
                colors: []
            )
        )

        XCTAssertTrue(message.body.contains("58/100"))
        XCTAssertTrue(message.body.localizedCaseInsensitiveContains("score itself"))
    }

    func testStylistMessageComposerStartsPaletteAttributeAsASentence() {
        let message = StylistMessageComposer.scoreEncouragement(
            input: StylistScoreMessageInput(
                score: 82,
                scoreTier: "Strong",
                scoreBreakdown: nil,
                detectedGarments: [],
                colors: ["charcoal"]
            )
        )

        XCTAssertTrue(message.body.contains("The detected charcoal palette is working well"))
        XCTAssertFalse(message.body.contains(". the detected charcoal palette"))
    }

    func testStylistNarrationUsesNeutralNounWhenGarmentIsUnreliableOrCompeting() {
        let lowConfidenceTie = StylistMessageComposer.scoreEncouragement(
            input: StylistScoreMessageInput(
                score: 82,
                scoreTier: "Strong",
                scoreBreakdown: nil,
                detectedGarments: ["tie"],
                detectedItemConfidences: [DetectedItemConfidence(item: "tie", confidence: 78)],
                colors: ["gray"]
            )
        )
        XCTAssertTrue(lowConfidenceTie.body.contains("The detected gray palette"))
        XCTAssertFalse(lowConfidenceTie.body.contains("gray outfit item"))
        XCTAssertFalse(lowConfidenceTie.body.contains("gray tie"))

        let competingNouns = StylistMessageComposer.scoreEncouragement(
            input: StylistScoreMessageInput(
                score: 82,
                scoreTier: "Strong",
                scoreBreakdown: nil,
                detectedGarments: ["jacket", "polo"],
                detectedItemConfidences: [
                    DetectedItemConfidence(item: "jacket", confidence: 95),
                    DetectedItemConfidence(item: "polo", confidence: 92)
                ],
                colors: ["navy"]
            )
        )
        XCTAssertTrue(competingNouns.body.contains("The detected navy palette"))
        XCTAssertFalse(competingNouns.body.contains("navy jacket"))

        let reliablePolo = StylistMessageComposer.scoreEncouragement(
            input: StylistScoreMessageInput(
                score: 82,
                scoreTier: "Strong",
                scoreBreakdown: nil,
                detectedGarments: ["polo"],
                detectedItemConfidences: [DetectedItemConfidence(item: "polo", confidence: 96)],
                colors: ["navy"]
            )
        )
        XCTAssertTrue(reliablePolo.body.contains("The detected navy palette"))
        XCTAssertFalse(reliablePolo.body.contains("navy polo shirt"))
    }

    func testScanNarrativePaletteDoesNotInventDominanceOrGarmentAssociation() {
        let facts = ScanNarrativeFacts(
            palette: ["gray", "brown"],
            detectedGarments: ["shirt"],
            detectedItemConfidences: [DetectedItemConfidence(item: "shirt", confidence: 96)]
        )

        XCTAssertEqual(ScanNarrativeConsistencyValidator.paletteAnchor(for: facts), "the detected gray-and-brown palette")
        XCTAssertFalse(ScanNarrativeConsistencyValidator.paletteAnchor(for: facts)?.contains("outfit item") == true)
        XCTAssertFalse(ScanNarrativeConsistencyValidator.paletteAnchor(for: facts)?.contains("gray shirt") == true)
    }

    func testScanNarrativeGarmentQualificationRejectsFallbackAndPreservesAuthoritativeEvidence() {
        let lowConfidence = ScanNarrativeFacts(
            palette: ["brown"],
            detectedGarments: ["jacket"],
            detectedItemConfidences: [DetectedItemConfidence(item: "jacket", confidence: 89)]
        )
        let authoritative = ScanNarrativeFacts(
            palette: ["brown"],
            detectedGarments: ["jacket"],
            detectedItemConfidences: [DetectedItemConfidence(item: "jacket", confidence: 90)]
        )
        let confidenceWithoutStructuredIdentity = ScanNarrativeFacts(
            palette: ["brown"],
            detectedGarments: [],
            detectedItemConfidences: [DetectedItemConfidence(item: "jacket", confidence: 95)]
        )

        XCTAssertTrue(lowConfidence.qualifiedGarments.isEmpty)
        XCTAssertEqual(authoritative.qualifiedGarments, ["jacket"])
        XCTAssertTrue(confidenceWithoutStructuredIdentity.qualifiedGarments.isEmpty)

        let genericAdvice = WeatherAdvisor.advice(for: WeatherAdvisorInput(
            feelsLikeTemperature: 90,
            humidityPercent: 60,
            rainChancePercent: nil,
            windMph: nil,
            uvIndex: nil,
            condition: "Hot",
            confidence: 95,
            detectedGarments: lowConfidence.qualifiedGarments
        ))
        let jacketAdvice = WeatherAdvisor.advice(for: WeatherAdvisorInput(
            feelsLikeTemperature: 90,
            humidityPercent: 60,
            rainChancePercent: nil,
            windMph: nil,
            uvIndex: nil,
            condition: "Hot",
            confidence: 95,
            detectedGarments: authoritative.qualifiedGarments
        ))
        XCTAssertFalse(genericAdvice?.reason.contains("scanned outfit includes jacket") == true)
        XCTAssertTrue(jacketAdvice?.reason.contains("scanned outfit includes jacket") == true)
    }

    func testScanNarrativeSoftensUnsupportedLeadInWithoutLosingValidAdvice() {
        let facts = ScanNarrativeFacts(palette: ["brown"], detectedGarments: [], detectedItemConfidences: [])
        let sections = [ChatGPTStylistSection(
            title: "Improvement Tips",
            body: "The scanned outfit includes a jacket, so choose breathable shoes. The detected gray palette is muted, so pair the brown pants with a cream top."
        )]

        let result = ScanNarrativeConsistencyValidator.validate(sections, facts: facts)
        XCTAssertEqual(result.map(\.title), ["Improvement Tips"])
        XCTAssertEqual(result.map(\.body), ["Choose breathable shoes. Pair the brown pants with a cream top."])
    }

    func testScanNarrativeRetainsDistinctHotWeatherAdviceAndDropsEmptySectionsCleanly() {
        let facts = ScanNarrativeFacts(palette: [], detectedGarments: [], detectedItemConfidences: [])
        let sections = [
            ChatGPTStylistSection(title: "Weather", body: "Keep fabrics breathable today."),
            ChatGPTStylistSection(title: "Improvement Tips", body: "Choose lightweight layers for easier cooling."),
            ChatGPTStylistSection(title: "Unsupported", body: "The scanned outfit includes a jacket."),
            ChatGPTStylistSection(title: "Duplicate", body: "  keep fabrics breathable today! ")
        ]

        let result = ScanNarrativeConsistencyValidator.validate(sections, facts: facts)
        XCTAssertEqual(result.map(\.title), ["Weather", "Improvement Tips"])
        XCTAssertEqual(result[0].body, "Keep fabrics breathable today.")
        XCTAssertEqual(result[1].body, "Choose lightweight layers for easier cooling.")
        XCTAssertFalse(result.map(\.body).joined(separator: " ").contains("jacket"))
    }

    func testScanNarrativeValidatorRemovesUnsupportedProviderColorsAndGarments() {
        let facts = ScanNarrativeFacts(
            palette: ["gray", "brown"],
            detectedGarments: ["shirt"],
            detectedItemConfidences: [DetectedItemConfidence(item: "shirt", confidence: 96)]
        )
        let sections = [ChatGPTStylistSection(
            title: "Outfit Summary",
            body: "The scanned outfit includes a jacket. The detected beige palette looks warm. The detected gray and brown palette is balanced."
        )]

        let result = ScanNarrativeConsistencyValidator.validate(sections, facts: facts)
        XCTAssertEqual(result.count, 1)
        XCTAssertFalse(result[0].body.contains("jacket"))
        XCTAssertFalse(result[0].body.contains("beige"))
        XCTAssertTrue(result[0].body.contains("gray and brown"))
    }

    func testScanNarrativeValidatorRejectsUnsupportedWeatherClaims() {
        let facts = ScanNarrativeFacts(
            palette: [],
            detectedGarments: [],
            detectedItemConfidences: [],
            weatherEvidence: ["Partly cloudy today at 92°F with 48% humidity."]
        )
        let sections = [ChatGPTStylistSection(
            title: "Weather",
            body: "It is raining today. It is cloudy today. Humidity is 80%. Humidity is 48%."
        )]

        let result = ScanNarrativeConsistencyValidator.validate(sections, facts: facts)
        let body = result.map(\.body).joined(separator: " ").lowercased()
        XCTAssertFalse(body.contains("raining"))
        XCTAssertFalse(body.contains("80%"))
        XCTAssertTrue(body.contains("cloudy"))
        XCTAssertTrue(body.contains("48%"))
    }

    func testScanNarrativeClosetAttributionRequiresVerifiedStableIdentifier() {
        let verifiedID = UUID()
        let unverifiedID = UUID()
        let facts = ScanNarrativeFacts(
            palette: [],
            detectedGarments: [],
            detectedItemConfidences: [],
            verifiedClosetRecordIDs: [verifiedID]
        )
        let sections = [ChatGPTStylistSection(
            title: "Suggestions",
            body: "Wear the loafers From your closet [[closet-item:\(verifiedID.uuidString)]]. Add the belt From your closet [[closet-item:\(unverifiedID.uuidString)]]."
        )]

        let result = ScanNarrativeConsistencyValidator.validate(sections, facts: facts)
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].body.contains("loafers From your closet"))
        XCTAssertFalse(result[0].body.contains("belt From your closet"))
        XCTAssertFalse(result[0].body.contains("closet-item"))
    }

    func testScanNarrativeDeduplicatesNormalizedAdviceAndPreservesDistinctAdvice() {
        let facts = ScanNarrativeFacts(palette: [], detectedGarments: [], detectedItemConfidences: [])
        let sections = [
            ChatGPTStylistSection(title: "Weather", body: "Keep this breathable today. Choose clean shoes."),
            ChatGPTStylistSection(title: "Tips", body: "  keep this breathable today! Add a simple belt.")
        ]

        let result = ScanNarrativeConsistencyValidator.validate(sections, facts: facts)
        let combined = result.map(\.body).joined(separator: " ").lowercased()
        XCTAssertEqual(combined.components(separatedBy: "keep this breathable today").count - 1, 1)
        XCTAssertTrue(combined.contains("choose clean shoes"))
        XCTAssertTrue(combined.contains("add a simple belt"))
    }

    func testScanNarrativeFreshAndSavedSectionsUseSameValidationResult() {
        let facts = ScanNarrativeFacts(
            palette: ["brown"],
            detectedGarments: ["shirt"],
            detectedItemConfidences: [DetectedItemConfidence(item: "shirt", confidence: 95)]
        )
        let storedSections = [ChatGPTStylistSection(
            title: "Personal Stylist Intelligence",
            body: "The detected brown palette works well. The scanned outfit includes a jacket."
        )]

        let fresh = ScanNarrativeConsistencyValidator.validate(storedSections, facts: facts)
        let restored = ScanNarrativeConsistencyValidator.validate(storedSections, facts: facts)
        XCTAssertEqual(fresh.map(\.body), restored.map(\.body))
        XCTAssertFalse(restored.map(\.body).joined().contains("jacket"))
    }

    func testScanNarrativeReplacementPreservesScoreAndBreakdown() throws {
        let scanSource = try projectSource("StyleMatchAI/ScanView.swift")
        let recommendationsStart = try XCTUnwrap(scanSource.range(of: "func replacingRecommendations"))
        let sectionsStart = try XCTUnwrap(scanSource.range(of: "func replacingChatGPTStylistSections"))
        let extensionEnd = try XCTUnwrap(scanSource.range(of: "#if DEBUG", range: sectionsStart.upperBound..<scanSource.endIndex))
        let recommendationsBody = scanSource[recommendationsStart.lowerBound..<sectionsStart.lowerBound]
        let sectionsBody = scanSource[sectionsStart.lowerBound..<extensionEnd.lowerBound]

        for body in [recommendationsBody, sectionsBody] {
            XCTAssertTrue(body.contains("score: score"))
            XCTAssertTrue(body.contains("scoreBreakdown: scoreBreakdown"))
        }
    }

    func testStylistMessageComposerScoreBandBoundaries() {
        let expected: [(Int, StylistScoreBand)] = [
            (59, .constructiveKind),
            (60, .encouragingImprovement),
            (74, .encouragingImprovement),
            (75, .confidentPositive),
            (89, .confidentPositive),
            (90, .enthusiastic)
        ]

        for pair in expected {
            XCTAssertEqual(StylistScoreBand(score: pair.0), pair.1)
        }
    }

    func testWeatherAdviceFlagOffOmitsWeatherSectionAndContext() {
        let input = makePersonalStylistInput(score: 91, weather: WeatherContextEngine.recommendation(
            for: makeWeatherSnapshot(air: 90, feelsLike: 94, humidity: 72, activity: .walking)
        ))

        let message = PersonalStylistIntelligenceBuilder.buildMessage(
            input: input,
            weatherAdviceEnabled: false,
            saleMatchingEnabled: false
        )
        let phrasingContext = PersonalStylistIntelligenceBuilder.buildPhrasingContext(
            input: input,
            weatherAdviceEnabled: false,
            saleMatchingEnabled: false
        )

        XCTAssertFalse(message.sections.contains { $0.source == .weather })
        XCTAssertTrue(phrasingContext.weatherFacts.isEmpty)
        XCTAssertFalse(message.plainText.localizedCaseInsensitiveContains("feels-like"))
    }

    func testWeatherAdviceUsesRealWeatherWhenEnabled() {
        let input = makePersonalStylistInput(score: 91, weather: WeatherContextEngine.recommendation(
            for: makeWeatherSnapshot(air: 90, feelsLike: 94, humidity: 72, activity: .walking)
        ))

        let message = PersonalStylistIntelligenceBuilder.buildMessage(
            input: input,
            weatherAdviceEnabled: true,
            saleMatchingEnabled: false
        )

        let weather = message.sections.first { $0.source == .weather }
        XCTAssertNotNil(weather)
        XCTAssertTrue(weather?.body.contains("94°F") == true)
        XCTAssertTrue(weather?.body.localizedCaseInsensitiveContains("humidity") == true)
    }

    func testSaleMatchingFlagOffOmitsDealSectionAndContext() {
        let deal = PersonalStylistDealMatch(
            productName: "White Oxford Shirt",
            retailerName: "Macy's",
            category: "Clothing",
            salePrice: "$69.99",
            reason: "Matches the scanned shirt category."
        )
        let input = makePersonalStylistInput(score: 89, dealMatches: [deal])

        let message = PersonalStylistIntelligenceBuilder.buildMessage(
            input: input,
            weatherAdviceEnabled: true,
            saleMatchingEnabled: false
        )
        let phrasingContext = PersonalStylistIntelligenceBuilder.buildPhrasingContext(
            input: input,
            weatherAdviceEnabled: true,
            saleMatchingEnabled: false
        )

        XCTAssertFalse(message.sections.contains { $0.source == .shoppingDeals })
        XCTAssertTrue(phrasingContext.dealFacts.isEmpty)
        XCTAssertFalse(message.plainText.contains("Macy's"))
    }

    // MARK: - 8. Affiliate shopping marketplace

    func testAffiliateCatalogDecodeSkipsSingleMalformedProduct() throws {
        let json = """
        [
          {
            "id": "valid-shirt",
            "name": "White Shirt",
            "category": "clothing",
            "subcategory": "shirt",
            "colors": ["white"],
            "imageURL": "https://www.macys.com/image.jpg",
            "retailer": {"name": "Macy's", "trackingID": "OLD", "trackingParamName": "old", "disclosureName": "Old Macy's"},
            "affiliateURL": "https://www.macys.com/shirt",
            "price": 80,
            "salePrice": null,
            "saleEndsAt": null,
            "tags": ["office"],
            "genderPresentation": null
          },
          {
            "id": "broken-product",
            "name": "Broken Product"
          }
        ]
        """
        let config = """
        {
          "retailers": [
            {"name": "Macy's", "trackingID": "APPROVED-ID", "trackingParamName": "aff", "disclosureName": "Macy's"}
          ]
        }
        """

        let products = try BundledCatalogProvider.decodeProducts(
            catalogData: Data(json.utf8),
            retailerConfigData: Data(config.utf8)
        )

        XCTAssertEqual(products.count, 1)
        XCTAssertEqual(products.first?.id, "valid-shirt")
        XCTAssertEqual(products.first?.retailer.trackingID, "APPROVED-ID")
    }

    func testShoppingImagesUseValidatedOptionalRequestsAndOneLocalFallback() throws {
        let payload = Data("""
        {
          "products": [
            {
              "id": "missing-image", "store_id": "amazon", "store_name": "Amazon",
              "name": "Missing", "image_url": null, "category": "tops", "brand": "Brand",
              "price_cents": 1000, "sale_price_cents": null, "sale_ends_at": null,
              "currency": "USD", "country_code": "US", "available_countries": ["*"],
              "availability": "in_stock", "tags": ["shirt"],
              "buy_url": "https://proxy.example.com/go/missing-image"
            },
            {
              "id": "blank-image", "store_id": "amazon", "store_name": "Amazon",
              "name": "Blank", "image_url": "   ", "category": "tops", "brand": "Brand",
              "price_cents": 1000, "sale_price_cents": null, "sale_ends_at": null,
              "currency": "USD", "country_code": "US", "available_countries": ["*"],
              "availability": "in_stock", "tags": ["shirt"],
              "buy_url": "https://proxy.example.com/go/blank-image"
            },
            {
              "id": "invalid-image", "store_id": "amazon", "store_name": "Amazon",
              "name": "Invalid", "image_url": "not-a-remote-image", "category": "tops", "brand": "Brand",
              "price_cents": 1000, "sale_price_cents": null, "sale_ends_at": null,
              "currency": "USD", "country_code": "US", "available_countries": ["*"],
              "availability": "in_stock", "tags": ["shirt"],
              "buy_url": "https://proxy.example.com/go/invalid-image"
            },
            {
              "id": "valid-image", "store_id": "amazon", "store_name": "Amazon",
              "name": "Valid", "image_url": "https://images.example.com/item.jpg", "category": "tops", "brand": "Brand",
              "price_cents": 1000, "sale_price_cents": null, "sale_ends_at": null,
              "currency": "USD", "country_code": "US", "available_countries": ["*"],
              "availability": "in_stock", "tags": ["shirt"],
              "buy_url": "https://proxy.example.com/go/valid-image"
            }
          ]
        }
        """.utf8)

        let products = try RemoteCatalogProvider.decodeRemoteProducts(
            payload,
            baseURL: URL(string: "https://proxy.example.com")!,
            regionCode: "US"
        )
        let byID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })

        XCTAssertNil(byID["missing-image"]?.remoteImageRequestURL)
        XCTAssertNil(byID["blank-image"]?.remoteImageRequestURL)
        XCTAssertNil(byID["invalid-image"]?.remoteImageRequestURL)
        XCTAssertEqual(byID["valid-image"]?.remoteImageRequestURL?.absoluteString, "https://images.example.com/item.jpg")

        let modelSource = try projectSource("StyleMatchAI/Shopping/AffiliateProduct.swift")
        let catalogSource = try projectSource("StyleMatchAI/Shopping/ProductCatalogProvider.swift")
        let shoppingSource = try projectSource("StyleMatchAI/Shopping/ShoppingView.swift")
        let searchSource = try projectSource("StyleMatchAI/Shopping/StoreSearchView.swift")

        XCTAssertFalse(catalogSource.contains("stylematch.local/product-placeholder.png"))
        XCTAssertTrue(modelSource.contains("var remoteImageRequestURL: URL?"))
        XCTAssertTrue(shoppingSource.contains("if let imageURL"))
        XCTAssertTrue(shoppingSource.contains("brandedFallback(reason: .missing)"))
        XCTAssertTrue(shoppingSource.contains("brandedFallback(reason: .loadFailure)"))
        XCTAssertTrue(shoppingSource.contains(".accessibilityHidden(true)"))
        XCTAssertFalse(shoppingSource.contains("No product image available"))
        XCTAssertFalse(shoppingSource.contains("title: \"No image\""))
        XCTAssertEqual(shoppingSource.components(separatedBy: "AsyncImage(url:").count - 1, 1)
        XCTAssertTrue(shoppingSource.contains("ShoppingProductImage(product: product)"))
        XCTAssertTrue(searchSource.contains("ShoppingProductImage(product: product)"))
        XCTAssertFalse(searchSource.contains("AsyncImage(url:"))
    }

    func testShoppingImageFallbackPresentationCoversCategoryFailureDarkModeAndAccessibility() throws {
        let missingClothing = ShoppingProductImageFallbackPresentation.make(
            category: .clothing,
            productName: "Classic Oxford",
            retailerName: "Macy's",
            reason: .missing
        )
        XCTAssertEqual(missingClothing.systemImage, "tshirt.fill")
        XCTAssertEqual(missingClothing.categoryLabel, "Clothing")
        XCTAssertEqual(missingClothing.identityText, "Macy's")
        XCTAssertEqual(missingClothing.statusText, "KigoStylist catalog preview")

        let failedShoes = ShoppingProductImageFallbackPresentation.make(
            category: .shoes,
            productName: "Walking Shoe",
            retailerName: "Foot Locker",
            reason: .loadFailure
        )
        XCTAssertEqual(failedShoes.systemImage, "figure.walk")
        XCTAssertEqual(failedShoes.statusText, "Retailer image unavailable")

        let unknownCategory = ShoppingProductImageFallbackPresentation.make(
            category: nil,
            productName: "",
            retailerName: "",
            reason: .missing
        )
        XCTAssertEqual(unknownCategory.systemImage, "shippingbox.fill")
        XCTAssertEqual(unknownCategory.categoryLabel, "Style pick")
        XCTAssertEqual(unknownCategory.identityText, "KigoStylist pick")

        XCTAssertGreaterThan(
            ShoppingProductImageFallbackPresentation.accentOpacity(isDarkMode: true),
            ShoppingProductImageFallbackPresentation.accentOpacity(isDarkMode: false)
        )

        let shoppingSource = try projectSource("StyleMatchAI/Shopping/ShoppingView.swift")
        XCTAssertTrue(shoppingSource.contains("@Environment(\\.colorScheme) private var colorScheme"))
        XCTAssertTrue(shoppingSource.contains("Color(.secondarySystemBackground)"))
        XCTAssertTrue(shoppingSource.contains(".accessibilityHidden(true)"))
        XCTAssertTrue(shoppingSource.contains(".accessibilityLabel(productAccessibilitySummary(product, action: viewModel.actionTitle))"))
        XCTAssertTrue(shoppingSource.contains(".accessibilityHint(\"Opens this product through the retailer link\")"))
    }

    func testAmazonPriceRuleIgnoresStoredPriceAtRenderTime() {
        let product = makeAffiliateProduct(
            id: "amazon-item",
            retailer: Retailer(name: "Amazon", trackingID: "amazon-20", trackingParamName: "tag", disclosureName: "Amazon"),
            price: Decimal(39.99),
            salePrice: Decimal(29.99)
        )

        let viewModel = AffiliateProductViewModel(product: product)

        XCTAssertEqual(viewModel.priceText, "See price at Amazon")
        XCTAssertNil(viewModel.originalPriceText)
        XCTAssertEqual(viewModel.actionTitle, "View on Amazon")
    }

    func testProductViewModelOmitsBrandWhenItDuplicatesRetailer() {
        let product = makeAffiliateProduct(
            id: "macys-brand-duplicate",
            retailer: Retailer(name: "Macy's", trackingID: "PENDING-APPROVAL", trackingParamName: "aff", disclosureName: "Macy's"),
            brand: "Macy's"
        )

        let viewModel = AffiliateProductViewModel(product: product)

        XCTAssertNil(viewModel.brandText)
        XCTAssertEqual(viewModel.retailerName, "Macy's")
        XCTAssertEqual(viewModel.soldAndShippedText, "Sold and shipped by Macy's")
        XCTAssertEqual(viewModel.actionTitle, "View Product")
    }

    func testProductViewModelOmitsEmptyBrandAndKeepsDistinctBrand() {
        let noBrand = makeAffiliateProduct(id: "no-brand", brand: nil)
        let nikeAtFootLocker = makeAffiliateProduct(
            id: "nike-footlocker",
            retailer: Retailer(name: "Foot Locker", trackingID: "PENDING-APPROVAL", trackingParamName: "aff", disclosureName: "Foot Locker"),
            brand: "Nike"
        )

        XCTAssertNil(AffiliateProductViewModel(product: noBrand).brandText)
        XCTAssertEqual(AffiliateProductViewModel(product: nikeAtFootLocker).brandText, "Nike")
    }

    func testAffiliateTrackingParamAppendsWithURLComponentsAndSkipsPendingApproval() {
        let approved = makeAffiliateProduct(
            id: "approved",
            retailer: Retailer(name: "Nike", trackingID: "real-id", trackingParamName: "aff", disclosureName: "Nike"),
            affiliateURL: URL(string: "https://www.nike.com/shoes?color=white")!
        )
        let pending = makeAffiliateProduct(
            id: "pending",
            retailer: Retailer(name: "Nike", trackingID: "PENDING-APPROVAL", trackingParamName: "aff", disclosureName: "Nike"),
            affiliateURL: URL(string: "https://www.nike.com/shoes?color=white")!
        )

        let approvedURL = AffiliateLinkBuilder.outboundURL(for: approved)
        let approvedItems = URLComponents(url: approvedURL, resolvingAgainstBaseURL: false)?.queryItems ?? []

        XCTAssertTrue(approvedItems.contains(URLQueryItem(name: "color", value: "white")))
        XCTAssertTrue(approvedItems.contains(URLQueryItem(name: "aff", value: "real-id")))
        XCTAssertEqual(AffiliateLinkBuilder.outboundURL(for: pending), pending.affiliateURL)
    }

    func testShoppingRecommendationComplementMatchUsesStoredBlackPantsOutfit() {
        var memory = makeBlackPantsAndShirtMemory()
        memory.scanDate = fixedDate(year: 2026, month: 7, day: 2)
        let whiteShirt = makeAffiliateProduct(
            id: "white-shirt",
            name: "White Shirt",
            category: .clothing,
            subcategory: "shirt",
            colors: ["white"]
        )

        let recommendations = ShoppingRecommendationEngine.recommendations(
            currentGarments: [],
            currentColors: [],
            memories: [memory],
            weather: nil,
            catalog: [whiteShirt],
            now: fixedDate(year: 2026, month: 7, day: 7)
        )

        XCTAssertEqual(recommendations.first?.product.id, "white-shirt")
        XCTAssertEqual(recommendations.first?.reasonFacts.rule, "complement")
        XCTAssertTrue(recommendations.first?.reasonFacts.oneLineReason.contains("black pants and black shirt") == true)
        XCTAssertTrue(recommendations.first?.reasonFacts.oneLineReason.contains("Recommended because") == true)
        XCTAssertTrue(recommendations.first?.reasonFacts.oneLineReason.contains("last Thursday") == true)
    }

    func testShoppingRecommendationReasonSanitizesInternalVisionLabels() {
        let facts = ProductRecommendationReasonFacts(
            rule: "complement",
            productName: "Brown Leather Loafer",
            productCategory: "Shoes",
            productColors: ["brown"],
            referencedOutfit: "gray Person Wearing Outfit and white Textile",
            referencedDate: "yesterday",
            referencedScore: 82,
            weatherFact: nil,
            saleFact: nil
        )
        let reason = facts.oneLineReason

        XCTAssertFalse(reason.localizedCaseInsensitiveContains("Person Wearing"))
        XCTAssertFalse(reason.localizedCaseInsensitiveContains("Textile"))
        XCTAssertTrue(reason.localizedCaseInsensitiveContains("outfit"))
        XCTAssertFalse(reason.localizedCaseInsensitiveContains("gray"))
        XCTAssertFalse(reason.localizedCaseInsensitiveContains("white Textile"))
    }

    func testDisplayLabelSanitizerBlocksInternalVisionLabels() {
        XCTAssertNil(DisplayLabelSanitizer.displayName(for: "Person Wearing Outfit"))
        XCTAssertNil(DisplayLabelSanitizer.displayName(for: "Textile"))
        XCTAssertNil(DisplayLabelSanitizer.displayName(for: "outfit item"))
        XCTAssertEqual(DisplayLabelSanitizer.displayName(for: "Loafer"), "loafers")
        XCTAssertEqual(DisplayLabelSanitizer.displayName(for: "polo shirt"), "polo shirt")
        XCTAssertEqual(DisplayLabelSanitizer.displayName(for: "tie"), "tie")

        let phrase = DisplayLabelSanitizer.wornItemPhrase(
            rawLabel: "Person Wearing Outfit",
            colorName: "gray",
            colorProvenance: .fullImage,
            recency: .yesterday
        )
        XCTAssertFalse(phrase.localizedCaseInsensitiveContains("gray"))
        XCTAssertFalse(phrase.localizedCaseInsensitiveContains("Person Wearing"))
        XCTAssertEqual(phrase, "what you wore yesterday")
    }

    func testShoppingLabelsRecoverRealGarmentFromConfidenceWithoutPlaceholder() {
        let analysis = OutfitAnalysisResult(
            score: 82,
            colorMatch: "Strong",
            occasionFit: "Everyday",
            styleBalance: "Casual",
            colorHarmony: "Balanced",
            styleCoordination: "Coordinated",
            formality: "Casual",
            seasonalMatch: "Mild",
            summary: "Synthetic summary",
            outfitDescription: "Synthetic outfit",
            detectedClothingItems: ["outfit item"],
            colorPalette: ["navy"],
            environment: "indoor",
            imageQuality: "clear",
            skinToneStyleNote: "No skin-tone recommendation needed.",
            detectedItemConfidences: [
                DetectedItemConfidence(item: "Textile", confidence: 92),
                DetectedItemConfidence(item: "polo", confidence: 90)
            ],
            suggestions: [],
            recommendations: []
        )

        XCTAssertEqual(analysis.safeDetectedClothingItems, ["polo shirt"])
        XCTAssertFalse(analysis.safeDetectedClothingItems.contains("outfit item"))
    }

    func testSavedScoreCopyUsesOneSourceAndUserFacingNarration() {
        let description = ScanMessageCopy.savedScoreDescription(
            confidenceLabel: "High",
            qualityDescription: "Source: local detection. Clothing detected: polo shirt.",
            guidance: "The outfit signal is strong.",
            savedResultMessage: "If you open this scan again, KigoStylist uses this saved result unless the outfit is new."
        )

        XCTAssertEqual(description.components(separatedBy: "Source:").count - 1, 1)
        XCTAssertTrue(description.hasPrefix("High confidence."))
        XCTAssertFalse(description.localizedCaseInsensitiveContains("the customer"))
    }

    func testConfidenceVocabularyUsesHighMediumLowLabels() throws {
        XCTAssertEqual(GarmentPaletteConfidence.confident.userFacingLabel, "High")
        XCTAssertEqual(GarmentPaletteConfidence.low.userFacingLabel, "Low")

        let scanSource = try projectSource("StyleMatchAI/ScanView.swift")
        XCTAssertTrue(scanSource.contains("return \"Medium\""))
        XCTAssertFalse(scanSource.contains("colorPaletteConfidence.rawValue"))
    }

    func testTargetDisplayNameDropsNumericSuffix() throws {
        let project = try projectSource("StyleMatchAI.xcodeproj/project.pbxproj")

        XCTAssertFalse(project.contains("KigoStylist 1"))
        XCTAssertEqual(project.components(separatedBy: "INFOPLIST_KEY_CFBundleDisplayName = \"KigoStylist\";").count - 1, 3)
    }

    func testRecommendationRationaleUsesCatalogFallbackForColdStart() {
        let product = makeAffiliateProduct(id: "trend", name: "White Shirt", subcategory: "shirt", colors: ["white"])
        let rationale = RecommendationRationaleBuilder.build(
            for: product,
            reasonFacts: nil,
            profile: nil,
            memories: [],
            savedFavorites: [],
            favoriteProductIDs: []
        )

        XCTAssertTrue(rationale.reasons.isEmpty)
        XCTAssertEqual(rationale.headline, "Available from Macy's.")
    }

    func testShoppingRecommendationPreferencesIncludeCustomerControls() {
        let preferences = ShoppingRecommendationPreferences.default
        XCTAssertTrue(preferences.usesWardrobeHistory)
        XCTAssertTrue(preferences.usesFavoriteBrands)
        XCTAssertTrue(preferences.usesFavoriteColors)
        XCTAssertTrue(preferences.usesBudgetRange)
        XCTAssertTrue(preferences.usesCurrentTrends)
        XCTAssertFalse(preferences.usesWeather)
        XCTAssertFalse(preferences.usesCalendarEvents)

        var profile = makeStylistProfile(userId: userA)
        RecommendationRationaleBuilder.apply(
            ShoppingRecommendationPreferences(
                usesWardrobeHistory: false,
                usesFavoriteBrands: false,
                usesFavoriteColors: true,
                usesBudgetRange: true,
                usesCurrentTrends: true,
                usesWeather: true,
                usesCalendarEvents: true
            ),
            to: &profile
        )

        let restored = RecommendationRationaleBuilder.preferences(from: profile)
        XCTAssertFalse(restored.usesWardrobeHistory)
        XCTAssertFalse(restored.usesFavoriteBrands)
        XCTAssertTrue(restored.usesFavoriteColors)
        XCTAssertTrue(restored.usesBudgetRange)
        XCTAssertTrue(restored.usesCurrentTrends)
        XCTAssertTrue(restored.usesWeather)
        XCTAssertTrue(restored.usesCalendarEvents)
    }

    func testUnsetShoppingBudgetDoesNotHideLoadedCatalogProducts() {
        let catalog = [
            makeAffiliateProduct(id: "shirt", name: "White Shirt", price: Decimal(89)),
            makeAffiliateProduct(id: "sneaker", name: "White Sneaker", category: .shoes, subcategory: "sneaker", price: Decimal(110))
        ]
        var neutralProfile = makeStylistProfile(userId: userA)
        neutralProfile.budgetRange = .neutral
        var defaultProfile = makeStylistProfile(userId: userA)
        defaultProfile.budgetRange = BudgetRange(minPrice: 50, maxPrice: 200, preferredTier: "Mid")

        let neutralFiltered = RecommendationRationaleBuilder.budgetFiltered(
            catalog,
            profile: neutralProfile,
            preferences: .default
        )
        let defaultFiltered = RecommendationRationaleBuilder.budgetFiltered(
            catalog,
            profile: defaultProfile,
            preferences: .default
        )

        XCTAssertEqual(neutralFiltered.map(\.id), catalog.map(\.id))
        XCTAssertEqual(defaultFiltered.map(\.id), catalog.map(\.id))
        XCTAssertFalse(ShoppingRecommendationEngine.popularFallbackRecommendations(catalog: neutralFiltered).isEmpty)
    }

    func testConfirmedShoppingBudgetStillFiltersCatalogProducts() {
        let catalog = [
            makeAffiliateProduct(id: "under-budget", price: Decimal(60)),
            makeAffiliateProduct(id: "over-budget", price: Decimal(180))
        ]
        var profile = makeStylistProfile(userId: userA)
        profile.budgetRange = BudgetRange(minPrice: 25, maxPrice: 75, preferredTier: "Value")

        let filtered = RecommendationRationaleBuilder.budgetFiltered(
            catalog,
            profile: profile,
            preferences: .default
        )

        XCTAssertEqual(filtered.map(\.id), ["under-budget"])
    }

    func testProfileBudgetFailsOpenWhenItWouldHideEveryLoadedCatalogProduct() {
        let catalog = [
            makeAffiliateProduct(id: "shirt", price: Decimal(89)),
            makeAffiliateProduct(id: "sneaker", category: .shoes, subcategory: "sneaker", price: Decimal(110))
        ]
        var profile = makeStylistProfile(userId: userA)
        profile.budgetRange = BudgetRange(minPrice: 1, maxPrice: 5, preferredTier: "Value")

        let filtered = RecommendationRationaleBuilder.budgetFiltered(
            catalog,
            profile: profile,
            preferences: .default
        )

        XCTAssertEqual(filtered.map(\.id), catalog.map(\.id))
        XCTAssertFalse(ShoppingRecommendationEngine.popularFallbackRecommendations(catalog: filtered).isEmpty)
    }

    func testShoppingDisplayInvariantLogsLoadedRemoteButZeroDisplayedState() throws {
        let viewSource = try projectSource("StyleMatchAI/Shopping/ShoppingView.swift")
        let observationSource = try projectSource("StyleMatchAI/Shopping/ShoppingCatalogObservation.swift")
        let diagnosticsSource = try projectSource("StyleMatchAI/Shopping/ShoppingDiagnostics.swift")

        XCTAssertTrue(viewSource.contains("ShoppingCatalogObservation.make("))
        XCTAssertTrue(viewSource.contains("catalogObservation.recordDisplay("))
        XCTAssertTrue(observationSource.contains("let displayedCount: Int"))
        XCTAssertTrue(diagnosticsSource.contains("case displayFinalized("))
        XCTAssertFalse(viewSource.contains("[KigoStylist Shopping Display Invariant Failure]"))
    }

    func testShoppingDisclosureDoesNotExposeTrackingIds() throws {
        let shopView = try projectSource("StyleMatchAI/ShopView.swift")
        let shoppingView = try projectSource("StyleMatchAI/Shopping/ShoppingView.swift")
        let storeSearchView = try projectSource("StyleMatchAI/Shopping/StoreSearchView.swift")
        let productCatalogProvider = try projectSource("StyleMatchAI/Shopping/ProductCatalogProvider.swift")

        for source in [shopView, shoppingView, storeSearchView] {
            XCTAssertFalse(source.contains("Tracking ID"))
            XCTAssertFalse(source.contains("affiliateTrackingID)."))
            XCTAssertTrue(source.contains("ShoppingCatalogDisclosure.fallback") || source.contains("catalogDisclosure"))
        }
        XCTAssertTrue(productCatalogProvider.contains("Retailer links open external websites."))
        XCTAssertTrue(productCatalogProvider.contains("Prices and availability are not live."))
        XCTAssertFalse(productCatalogProvider.contains("As an Amazon Associate I earn from qualifying purchases."))
    }

    func testShoppingViewLeadsWithConciergeBestPicksAndExploreBeforeDiscovery() throws {
        let source = try projectSource("StyleMatchAI/Shopping/ShoppingView.swift")
        let bodyStart = try XCTUnwrap(source.range(of: "var body: some View"))
        let loadingStart = try XCTUnwrap(source.range(of: "private var shoppingLoadingShell", range: bodyStart.upperBound..<source.endIndex))
        let root = String(source[bodyStart.lowerBound..<loadingStart.lowerBound])
        let bestPicksStart = try XCTUnwrap(source.range(of: "private var bestPicksSection"))
        let completeLookStart = try XCTUnwrap(source.range(of: "private var premiumCompleteTheLook", range: bestPicksStart.upperBound..<source.endIndex))
        let bestPicks = String(source[bestPicksStart.lowerBound..<completeLookStart.lowerBound])

        XCTAssertTrue(source.contains("Shopping for you"))
        XCTAssertTrue(source.contains("Best picks for you"))
        XCTAssertTrue(source.contains("DisclosureGroup(\"Why KigoStylist picked this\")"))
        XCTAssertTrue(source.contains("Shopping direction"))
        XCTAssertTrue(source.contains("Label(\"Explore\""))
        XCTAssertTrue(source.contains("UIAccessibility.isReduceMotionEnabled ? nil : .snappy"))
        XCTAssertTrue(source.contains("Search and filters are collapsed until you need them."))
        XCTAssertTrue(source.contains("Choose a direction for this shopping session."))
        XCTAssertTrue(bestPicks.contains("recommendations.prefix(3)"))
        XCTAssertFalse(bestPicks.contains("matchPercent"))
        XCTAssertFalse(bestPicks.contains("soldAndShippedText"))
        XCTAssertFalse(bestPicks.contains("saleBadgeText"))
        XCTAssertFalse(bestPicks.contains("Score-ready"))

        let conciergeIndex = try XCTUnwrap(root.range(of: "shoppingConcierge")?.lowerBound)
        let bestPicksIndex = try XCTUnwrap(root.range(of: "bestPicksSection")?.lowerBound)
        let directionIndex = try XCTUnwrap(root.range(of: "shopYourStyleSection")?.lowerBound)
        let exploreIndex = try XCTUnwrap(root.range(of: "exploreSection")?.lowerBound)
        let discoveryIndex = try XCTUnwrap(root.range(of: "productDiscoverySection")?.lowerBound)
        XCTAssertLessThan(conciergeIndex, bestPicksIndex)
        XCTAssertLessThan(bestPicksIndex, directionIndex)
        XCTAssertLessThan(directionIndex, exploreIndex)
        XCTAssertLessThan(exploreIndex, discoveryIndex)
        XCTAssertFalse(root.contains("stylistFeedCard"))
        XCTAssertFalse(root.contains("discoveryShortcutRail"))
        XCTAssertFalse(root.contains("styleProgressCard"))
        XCTAssertFalse(root.contains("feedbackRecommendedSection"))
    }

    func testShoppingPremiumCardsClearBottomNavigationAndLabelEveryPrimaryAction() throws {
        let shoppingSource = try projectSource("StyleMatchAI/Shopping/ShoppingView.swift")
        let contentSource = try projectSource("StyleMatchAI/ContentView.swift")

        XCTAssertTrue(shoppingSource.contains("private let bottomNavigationClearance: CGFloat"))
        XCTAssertTrue(shoppingSource.contains(".padding(.bottom, bottomNavigationClearance)"))
        XCTAssertTrue(shoppingSource.contains("viewport by its measured clearance"))
        XCTAssertTrue(contentSource.contains("bottomNavigationClearance: bottomNavigationClearance"))
        XCTAssertTrue(shoppingSource.contains("Text(\"Ask AI\")"))
        XCTAssertTrue(shoppingSource.contains("Text(isFavoriteProduct(product) ? \"Saved\" : \"Save\")"))
        XCTAssertTrue(shoppingSource.contains("let productActionTitle = product.isAmazonSourced ? \"View on Amazon\" : \"View Product\""))
        XCTAssertTrue(shoppingSource.contains("Label(productActionTitle, systemImage: \"arrow.up.forward.app\")"))
        XCTAssertTrue(shoppingSource.contains("DisclosureGroup(\"Why KigoStylist picked this\")"))
        XCTAssertTrue(shoppingSource.contains("let hasVerifiedPrice = product.salePrice != nil || product.price != nil"))
        XCTAssertTrue(shoppingSource.contains("Text(deckPriceText(for: product))"))
    }

    func testShoppingStyleDirectionIsEphemeralAccessibleAndUsesTypedTierPolicy() throws {
        let shoppingSource = try projectSource("StyleMatchAI/Shopping/ShoppingView.swift")
        let registrySource = try projectSource("StyleMatchAI/Shopping/RetailerCatalogRegistry.swift")
        let chatModels = try projectSource("StyleMatchAI/StylistChat/StylistChatModels.swift")

        for mapping in [
            "Designer Luxury", "Luxury Multi-Brand", "Premium", "Athletic and Streetwear", "Everyday and Value",
            ".designerLuxury", ".luxuryMultiBrand", ".premium", ".athleticStreetwear", ".value"
        ] {
            XCTAssertTrue(shoppingSource.contains(mapping), "Missing shopping style-direction mapping: \(mapping)")
        }
        XCTAssertTrue(shoppingSource.contains("@State private var selectedShopTierPreference"))
        XCTAssertTrue(shoppingSource.contains("RetailerCatalogRegistry(stores: supportedStores).filter"))
        XCTAssertTrue(shoppingSource.contains("I don't have a strong match in the current catalog for"))
        XCTAssertTrue(shoppingSource.contains("Applies to this shopping session only."))
        XCTAssertTrue(shoppingSource.contains(".frame(maxWidth: .infinity, minHeight: 44"))
        XCTAssertTrue(shoppingSource.contains(".accessibilityValue(isSelected ? \"Selected\" : \"Not selected\")"))
        XCTAssertTrue(shoppingSource.contains(".accessibilityHint(\"Filters this shopping session to this style direction.\")"))
        XCTAssertFalse(shoppingSource.contains("Similar for Less"))
        XCTAssertFalse(shoppingSource.contains("Budget Alternative"))
        XCTAssertTrue(registrySource.contains("case athleticStreetwear"))
        XCTAssertTrue(registrySource.contains("return tier == .athleticStreetwear"))
        XCTAssertFalse(chatModels.contains("ShoppingTierPreference"))
    }

    func testShoppingEngagementCardsNavigateToLocalDestinations() throws {
        let source = try projectSource("StyleMatchAI/Shopping/ShoppingView.swift")

        XCTAssertTrue(source.contains("ShoppingEngagementDestination"))
        XCTAssertTrue(source.contains("NavigationStack(path: $engagementPath)"))
        XCTAssertTrue(source.contains(".navigationDestination(for: ShoppingEngagementDestination.self)"))
        XCTAssertTrue(source.contains("exploreDestination(.todaysStyleBrief"))
        XCTAssertTrue(source.contains("exploreDestination(.recommendedForYou"))
        XCTAssertTrue(source.contains("exploreDestination(.popularPicks"))
        XCTAssertTrue(source.contains("exploreDestination(.deals"))
        XCTAssertTrue(source.contains("exploreDestination(.completeLooks"))
        XCTAssertTrue(source.contains("exploreDestination(.savedHub"))
        XCTAssertTrue(source.contains("exploreDestination(.styleDNA"))
        XCTAssertTrue(source.contains("exploreDestination(.priceAlerts"))
        XCTAssertTrue(source.contains("showEngagement(.disclosure)"))
        XCTAssertTrue(source.contains("KigoStylist uses approved catalog links and local shopping signals."))
        XCTAssertFalse(source.contains("viral"))
        XCTAssertFalse(source.contains("celebrity"))
    }

    func testShoppingFilteredEmptyStateKeepsDiscoveryAlive() throws {
        let source = try projectSource("StyleMatchAI/Shopping/ShoppingView.swift")

        XCTAssertFalse(source.contains("No products match those filters."))
        XCTAssertTrue(source.contains("Let's widen the styling lens"))
        XCTAssertTrue(source.contains("fallbackDiscoveryProducts"))
    }

    func testShoppingFeedbackRecommendedSectionUsesThreePositiveThreshold() throws {
        let source = try projectSource("StyleMatchAI/Shopping/ShoppingView.swift")

        XCTAssertTrue(source.contains("feedbackRecommendedSection"))
        XCTAssertTrue(source.contains("ShoppingFeedbackProductRanker.positiveRecommendations"))
        XCTAssertTrue(source.contains("minimumCount: 3"))
        XCTAssertTrue(source.contains("Ranked from outfits you wore, liked, and saved on this device."))
        XCTAssertFalse(source.contains("calculateStyleScore"))
    }

    func testShoppingFeedbackRankerUsesRichPositiveAndNegativeFeedback() {
        var likedRecord = makeGarmentRecord(fingerprint: "liked-shirt-navy")
        likedRecord.garmentCategory = "shirt"
        likedRecord.colors = ["navy"]
        likedRecord.styleTags = ["smart casual"]
        likedRecord.brand = "Macy's"
        var liked = makeOutfitMemory(userId: userA, record: likedRecord)
        liked.wasLiked = true
        liked.wasWorn = true
        liked.timesWorn = 2
        liked.detectedStyle = "Smart Casual"

        var dislikedRecord = makeGarmentRecord(fingerprint: "disliked-jacket-red")
        dislikedRecord.garmentCategory = "jacket"
        dislikedRecord.colors = ["red"]
        dislikedRecord.styleTags = ["edgy"]
        dislikedRecord.brand = "Problem Brand"
        var disliked = makeOutfitMemory(userId: userA, record: dislikedRecord)
        disliked.wasLiked = false
        disliked.dislikeReason = .notMyStyle
        disliked.detectedStyle = "Edgy"

        let strongMatch = makeAffiliateProduct(
            id: "strong",
            name: "Navy Smart Shirt",
            subcategory: "shirt",
            colors: ["navy"],
            tags: ["smart casual"],
            brand: "Macy's"
        )
        let negativeMatch = makeAffiliateProduct(
            id: "negative",
            name: "Red Edgy Jacket",
            subcategory: "jacket",
            colors: ["red"],
            tags: ["edgy"],
            brand: "Problem Brand"
        )
        let neutral = makeAffiliateProduct(
            id: "neutral",
            name: "White Sneaker",
            category: .shoes,
            subcategory: "sneakers",
            colors: ["white"],
            tags: ["athletic"]
        )

        let ranked = ShoppingFeedbackProductRanker.rankedProducts(
            from: [neutral, negativeMatch, strongMatch],
            memories: [liked, disliked]
        )
        let byID = Dictionary(uniqueKeysWithValues: ranked.map { ($0.product.id, $0.score) })

        XCTAssertEqual(ranked.first?.product.id, "strong")
        XCTAssertGreaterThan(byID["strong"] ?? 0, byID["neutral"] ?? 0)
        XCTAssertLessThan(byID["negative"] ?? 0, byID["neutral"] ?? 0)
    }

    func testShoppingFeedbackRankerNoOpsWithZeroFeedback() {
        let input = [
            makeAffiliateProduct(id: "first", name: "First"),
            makeAffiliateProduct(id: "second", name: "Second"),
            makeAffiliateProduct(id: "third", name: "Third")
        ]

        let ranked = ShoppingFeedbackProductRanker.rankedProducts(from: input, memories: [])

        XCTAssertEqual(ranked.map { $0.product.id }, input.map(\.id))
        XCTAssertEqual(ranked.map(\.score), [0, 0, 0])
    }

    func testShoppingFeedbackRankerHidesRecommendationsBelowThreePositiveProducts() {
        var record = makeGarmentRecord(fingerprint: "liked-shirt-black")
        record.garmentCategory = "shirt"
        record.colors = ["black"]
        var liked = makeOutfitMemory(userId: userA, record: record)
        liked.wasLiked = true

        let twoMatches = [
            makeAffiliateProduct(id: "match-1", subcategory: "shirt", colors: ["black"]),
            makeAffiliateProduct(id: "match-2", subcategory: "shirt", colors: ["black"])
        ]

        XCTAssertTrue(
            ShoppingFeedbackProductRanker.positiveRecommendations(
                from: twoMatches,
                memories: [liked],
                minimumCount: 3
            ).isEmpty
        )
    }

    func testShoppingFeedbackRankerColorsOffEmphasizesColorDownWeightOverStyle() {
        var record = makeGarmentRecord(fingerprint: "color-off-red-formal")
        record.garmentCategory = "shirt"
        record.colors = ["red"]
        record.styleTags = ["formal"]
        var disliked = makeOutfitMemory(userId: userA, record: record)
        disliked.wasLiked = false
        disliked.dislikeReason = .colorsOff
        disliked.detectedStyle = "Formal"

        let colorMatch = makeAffiliateProduct(id: "red-casual", colors: ["red"], tags: ["casual"])
        let styleMatch = makeAffiliateProduct(id: "blue-formal", colors: ["blue"], tags: ["formal"])
        let ranked = ShoppingFeedbackProductRanker.rankedProducts(from: [colorMatch, styleMatch], memories: [disliked])
        let byID = Dictionary(uniqueKeysWithValues: ranked.map { ($0.product.id, $0.score) })

        XCTAssertLessThan(byID["red-casual"] ?? 0, byID["blue-formal"] ?? 0)
    }

    func testShoppingFeedbackRankerNotMyStyleEmphasizesStyleDownWeightOverColor() {
        var record = makeGarmentRecord(fingerprint: "style-off-red-edgy")
        record.garmentCategory = "shirt"
        record.colors = ["red"]
        record.styleTags = ["edgy"]
        var disliked = makeOutfitMemory(userId: userA, record: record)
        disliked.wasLiked = false
        disliked.dislikeReason = .notMyStyle
        disliked.detectedStyle = "Edgy"

        let colorMatch = makeAffiliateProduct(id: "red-casual", colors: ["red"], tags: ["casual"])
        let styleMatch = makeAffiliateProduct(id: "blue-edgy", colors: ["blue"], tags: ["edgy"])
        let ranked = ShoppingFeedbackProductRanker.rankedProducts(from: [colorMatch, styleMatch], memories: [disliked])
        let byID = Dictionary(uniqueKeysWithValues: ranked.map { ($0.product.id, $0.score) })

        XCTAssertLessThan(byID["blue-edgy"] ?? 0, byID["red-casual"] ?? 0)
    }

    func testShoppingFeedbackRankerBrandBonusIsSmallAndOptional() {
        var brandedRecord = makeGarmentRecord(fingerprint: "liked-nike-shirt")
        brandedRecord.garmentCategory = "shirt"
        brandedRecord.colors = ["black"]
        brandedRecord.styleTags = ["casual"]
        brandedRecord.brand = "Nike"
        var brandedMemory = makeOutfitMemory(userId: userA, record: brandedRecord)
        brandedMemory.wasLiked = true

        let nike = makeAffiliateProduct(id: "nike", subcategory: "shirt", colors: ["black"], tags: ["casual"], brand: "Nike")
        let noBrand = makeAffiliateProduct(id: "no-brand", subcategory: "shirt", colors: ["black"], tags: ["casual"], brand: nil)
        let brandedRanked = ShoppingFeedbackProductRanker.rankedProducts(from: [noBrand, nike], memories: [brandedMemory])
        let brandedScores = Dictionary(uniqueKeysWithValues: brandedRanked.map { ($0.product.id, $0.score) })

        XCTAssertEqual((brandedScores["nike"] ?? 0) - (brandedScores["no-brand"] ?? 0), 3)

        var unbrandedRecord = brandedRecord
        unbrandedRecord.brand = nil
        var unbrandedMemory = makeOutfitMemory(userId: userA, record: unbrandedRecord)
        unbrandedMemory.wasLiked = true
        let unbrandedRanked = ShoppingFeedbackProductRanker.rankedProducts(from: [noBrand], memories: [unbrandedMemory])

        XCTAssertGreaterThan(unbrandedRanked.first?.score ?? 0, 0)
    }

    func testScanCompleteLookCardAppearsWhenAccessoriesAreWeakestAndCompatibleProductExists() throws {
        let analysis = makeCompleteLookAnalysis(
            colorHarmony: 22,
            patternBalance: 17,
            fitQuality: 21,
            accessoryUse: 4,
            palette: ["navy"],
            occasionFit: "Smart casual"
        )
        let navyWatch = makeAffiliateProduct(
            id: "navy-watch",
            name: "Navy Watch",
            category: .accessories,
            subcategory: "watch",
            colors: ["navy"],
            occasionTags: ["smart casual"]
        )
        let blackBelt = makeAffiliateProduct(
            id: "black-belt",
            name: "Black Belt",
            category: .accessories,
            subcategory: "belt",
            colors: ["black"],
            occasionTags: ["business"]
        )
        let shirt = makeAffiliateProduct(id: "shirt", category: .clothing, colors: ["navy"])

        let recommendations = ScanCompleteLookAccessoryRecommender.recommendations(
            for: analysis,
            catalog: [shirt, blackBelt, navyWatch]
        )
        let source = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(ScanCompleteLookAccessoryRecommender.shouldRecommendAccessories(for: analysis))
        XCTAssertEqual(recommendations.map(\.id), ["navy-watch"])
        XCTAssertTrue(source.contains("completeTheLookCard(for: result"))
        XCTAssertTrue(source.contains("SharedProductCatalogLoader.shared.products()"))
        XCTAssertTrue(source.contains("ScanCompleteLookAccessoryRecommender.recommendations"))
    }

    func testScanCompleteLookCardHiddenWhenAccessoryUseIsNotWeakestEvenIfLow() {
        let analysis = makeCompleteLookAnalysis(
            colorHarmony: 8,
            patternBalance: 15,
            fitQuality: 21,
            accessoryUse: 4,
            palette: ["navy"]
        )
        let accessory = makeAffiliateProduct(id: "navy-watch", category: .accessories, colors: ["navy"])

        XCTAssertFalse(ScanCompleteLookAccessoryRecommender.shouldRecommendAccessories(for: analysis))
        XCTAssertTrue(ScanCompleteLookAccessoryRecommender.recommendations(for: analysis, catalog: [accessory]).isEmpty)
    }

    func testScanCompleteLookCardHiddenWhenNoCompatibleAccessoryProductExists() {
        let analysis = makeCompleteLookAnalysis(
            colorHarmony: 22,
            patternBalance: 17,
            fitQuality: 21,
            accessoryUse: 4,
            palette: ["navy"],
            occasionFit: "Smart casual"
        )
        let redWatch = makeAffiliateProduct(
            id: "red-watch",
            category: .accessories,
            colors: ["red"],
            occasionTags: ["formal"]
        )
        let navyShirt = makeAffiliateProduct(id: "navy-shirt", category: .clothing, colors: ["navy"])

        XCTAssertTrue(ScanCompleteLookAccessoryRecommender.shouldRecommendAccessories(for: analysis))
        XCTAssertTrue(ScanCompleteLookAccessoryRecommender.recommendations(for: analysis, catalog: [redWatch, navyShirt]).isEmpty)
    }

    func testScanCompleteLookCardHiddenWhenAccessoryUseIsWeakButAboveThreshold() {
        let analysis = makeCompleteLookAnalysis(
            colorHarmony: 25,
            patternBalance: 20,
            fitQuality: 25,
            accessoryUse: 6,
            palette: ["navy"]
        )
        let accessory = makeAffiliateProduct(id: "navy-watch", category: .accessories, colors: ["navy"])

        XCTAssertFalse(ScanCompleteLookAccessoryRecommender.shouldRecommendAccessories(for: analysis))
        XCTAssertTrue(ScanCompleteLookAccessoryRecommender.recommendations(for: analysis, catalog: [accessory]).isEmpty)
    }

    func testScanCompleteLookCardAppearsWhenAccessoryUseIsExactlyFiveAndWeakest() {
        let analysis = makeCompleteLookAnalysis(
            colorHarmony: 25,
            patternBalance: 20,
            fitQuality: 25,
            accessoryUse: 5,
            palette: ["navy"],
            occasionFit: "Smart casual"
        )
        let accessory = makeAffiliateProduct(
            id: "navy-watch",
            name: "Navy Watch",
            category: .accessories,
            subcategory: "watch",
            colors: ["navy"],
            occasionTags: ["smart casual"]
        )

        XCTAssertTrue(ScanCompleteLookAccessoryRecommender.shouldRecommendAccessories(for: analysis))
        XCTAssertEqual(
            ScanCompleteLookAccessoryRecommender.recommendations(for: analysis, catalog: [accessory]).map(\.id),
            ["navy-watch"]
        )
    }

    func testScanCompleteLookFeatureDoesNotAddStyleScoreCallsOrChangeDisplayedScore() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        let cardStart = try XCTUnwrap(source.range(of: "private func completeTheLookCard"))
        let cardEnd = try XCTUnwrap(source.range(of: "private func quickResultCard", range: cardStart.upperBound..<source.endIndex))
        let cardAndLoader = String(source[cardStart.lowerBound..<cardEnd.lowerBound])

        XCTAssertFalse(cardAndLoader.contains("calculateStyleScore"))
        XCTAssertFalse(cardAndLoader.contains("styleScoreBreakdown(from:"))
        XCTAssertFalse(cardAndLoader.contains("displayedScore(for:"))
        XCTAssertTrue(source.contains("Text(\"\\(displayedScore(for: result))\")"))
        XCTAssertTrue(source.contains("ScanCompleteLookAccessoryRecommender.shouldRecommendAccessories(for: result)"))
    }

    func testShoppingSwipeDeckRightSwipeFavoritesNewProduct() {
        let store = ShoppingLocalStore(defaults: defaults, userID: userA)
        var deck = ShoppingSwipeDeckState(productIDs: ["new-product"])

        deck.swipeRight(using: store)

        XCTAssertEqual(store.savedFavorites, ["new-product"])
        XCTAssertEqual(deck.currentIndex, 1)
        XCTAssertNil(deck.currentProductID)
    }

    func testShoppingSwipeDeckRightSwipeAlreadyFavoritedIsNoOpForFavoriteState() {
        let store = ShoppingLocalStore(defaults: defaults, userID: userA)
        store.savedFavorites = ["already-liked"]
        var deck = ShoppingSwipeDeckState(productIDs: ["already-liked"])

        deck.swipeRight(using: store)

        XCTAssertEqual(store.savedFavorites, ["already-liked"])
        XCTAssertEqual(deck.currentIndex, 1)
    }

    func testShoppingSwipeDeckLeftSwipeNeverWritesShoppingSignals() {
        let store = ShoppingLocalStore(defaults: defaults, userID: userA)
        var deck = ShoppingSwipeDeckState(productIDs: ["skip-only"])

        deck.swipeLeft()

        XCTAssertTrue(store.savedFavorites.isEmpty)
        XCTAssertTrue(store.dismissedProductIDs.isEmpty)
        XCTAssertEqual(deck.currentIndex, 1)
    }

    func testShoppingSwipeDeckAdvancesOnBothSwipeDirections() {
        let store = ShoppingLocalStore(defaults: defaults, userID: userA)
        var deck = ShoppingSwipeDeckState(productIDs: ["first", "second", "third"])

        deck.swipeLeft()
        XCTAssertEqual(deck.currentProductID, "second")

        deck.swipeRight(using: store)
        XCTAssertEqual(deck.currentProductID, "third")
        XCTAssertEqual(store.savedFavorites, ["second"])
    }

    func testShoppingSwipeDeckEmptyCatalogIsSafeAndShowsEmptyState() throws {
        var deck = ShoppingSwipeDeckState(productIDs: [])
        deck.swipeLeft()
        XCTAssertTrue(deck.isEmpty)
        XCTAssertNil(deck.currentProductID)
        XCTAssertEqual(deck.currentIndex, 0)

        let source = try projectSource("StyleMatchAI/Shopping/ShoppingView.swift")
        XCTAssertTrue(source.contains("No products available"))
        XCTAssertTrue(source.contains("The catalog is empty right now. Check back shortly."))
        XCTAssertTrue(source.contains("ShoppingSwipeDeckState(productIDs: deckProductIDs"))
        XCTAssertFalse(source.contains("store.dismiss("))
        XCTAssertFalse(source.contains("calculateStyleScore"))
    }

    func testRecommendationRationaleUsesDominantProfileColor() {
        var profile = makeStylistProfile(userId: userA)
        profile.favoriteColors = ["white"]
        let product = makeAffiliateProduct(id: "white-shirt", name: "White Shirt", subcategory: "shirt", colors: ["white"])
        let rationale = RecommendationRationaleBuilder.build(
            for: product,
            reasonFacts: nil,
            profile: profile,
            memories: [],
            savedFavorites: [],
            favoriteProductIDs: []
        )

        XCTAssertTrue(rationale.reasons.contains(.matchesColors))
        XCTAssertFalse(rationale.headline.localizedCaseInsensitiveContains("Person Wearing"))
        XCTAssertFalse(rationale.headline.localizedCaseInsensitiveContains("Textile"))
    }

    func testShoppingRecommendationSaleAloneNeverProducesRecommendation() {
        let saleOnly = makeAffiliateProduct(
            id: "sale-only",
            name: "Random Sale Item",
            category: .electronics,
            subcategory: "speaker",
            colors: ["purple"],
            salePrice: Decimal(19.99),
            tags: ["sale"]
        )

        let recommendations = ShoppingRecommendationEngine.recommendations(
            currentGarments: [],
            currentColors: [],
            memories: [],
            weather: nil,
            catalog: [saleOnly]
        )

        XCTAssertTrue(recommendations.isEmpty)
    }

    func testShoppingRecommendationHotWeatherNeverRecommendsHeavyLayerTaggedItems() {
        let coat = makeAffiliateProduct(
            id: "coat",
            name: "Wool Topcoat",
            category: .clothing,
            subcategory: "coat",
            colors: ["camel"],
            tags: ["cold", "wool", "heavy"]
        )
        let recommendations = ShoppingRecommendationEngine.recommendations(
            currentGarments: ["black pants"],
            currentColors: ["black"],
            memories: [],
            weather: ShoppingWeatherContext(feelsLikeTemperature: 91, rainChancePercent: nil, uvIndex: nil, condition: "Hot"),
            catalog: [coat]
        )

        XCTAssertTrue(recommendations.isEmpty)
    }

    func testShoppingTabVisibilityFlagCanRemoveTab() {
        XCTAssertFalse(ShoppingTabVisibility.shouldShowShoppingTab(shoppingTabEnabled: false))
        XCTAssertTrue(ShoppingTabVisibility.shouldShowShoppingTab(shoppingTabEnabled: true))
    }

    func testShoppingReasonFactsContainNoURLsOrTrackingIDsForAIPhrasing() throws {
        var memory = makeBlackPantsAndShirtMemory()
        memory.scanDate = fixedDate(year: 2026, month: 7, day: 2)
        let product = makeAffiliateProduct(
            id: "tracked-shirt",
            name: "White Shirt",
            category: .clothing,
            subcategory: "shirt",
            colors: ["white"],
            retailer: Retailer(name: "Macy's", trackingID: "SECRET-ID", trackingParamName: "aff", disclosureName: "Macy's"),
            affiliateURL: URL(string: "https://www.macys.com/shirt")!
        )
        let recommendation = ShoppingRecommendationEngine.recommendations(
            currentGarments: [],
            currentColors: [],
            memories: [memory],
            weather: nil,
            catalog: [product],
            now: fixedDate(year: 2026, month: 7, day: 7)
        ).first

        let data = try JSONEncoder().encode(recommendation?.reasonFacts)
        let payload = String(data: data, encoding: .utf8) ?? ""

        XCTAssertFalse(payload.contains("https://"))
        XCTAssertFalse(payload.contains("SECRET-ID"))
        XCTAssertFalse(payload.localizedCaseInsensitiveContains("tracking"))
    }

    func testCatalogDealProviderUsesOnlyCurrentSaleCatalogItems() async throws {
        let provider = StaticProductCatalogProvider(products: [
            makeAffiliateProduct(id: "sale", name: "White Shirt", category: .clothing, subcategory: "shirt", colors: ["white"], price: Decimal(80), salePrice: Decimal(60), saleEndsAt: fixedDate(year: 2027, month: 1, day: 1)),
            makeAffiliateProduct(id: "expired", name: "Expired Shirt", category: .clothing, subcategory: "shirt", colors: ["white"], price: Decimal(80), salePrice: Decimal(60), saleEndsAt: fixedDate(year: 2025, month: 1, day: 1)),
            makeAffiliateProduct(id: "regular", name: "Regular Shirt", category: .clothing, subcategory: "shirt", colors: ["white"], price: Decimal(80), salePrice: nil)
        ])

        let deals = try await CatalogDealProvider(
            catalogProvider: provider,
            now: fixedDate(year: 2026, month: 7, day: 7)
        ).currentDeals()

        XCTAssertEqual(deals.map(\.itemName), ["White Shirt"])
    }

    func testSupportedStoreDirectoryIncludesRequestedStoresAndSkipsMalformedEntry() throws {
        let json = """
        [
          {"id": "nike", "name": "Nike", "domains": ["nike.com"], "categories": ["clothing", "shoes"], "affiliateNetwork": "TBD", "apiStatus": "affiliate-placeholder", "isEnabled": true},
          {"id": "broken", "name": "Broken Store"},
          {"id": "sephora", "name": "Sephora", "domains": ["sephora.com"], "categories": ["styleTools"], "affiliateNetwork": "TBD", "apiStatus": "needs-approved-feed", "isEnabled": true}
        ]
        """

        let stores = try BundledStoreDirectoryProvider.decodeStores(Data(json.utf8))

        XCTAssertEqual(stores.map(\.name), ["Nike", "Sephora"])
    }

    func testBundledSupportedStoresIncludesAmericanEagle() throws {
        let data = try Data(projectSource("StyleMatchAI/Shopping/SupportedStores.json").utf8)
        let stores = try BundledStoreDirectoryProvider.decodeStores(data)
        let americanEagle = try XCTUnwrap(stores.first { $0.id == "american-eagle" })

        XCTAssertEqual(americanEagle.name, "American Eagle")
        XCTAssertEqual(americanEagle.primaryDomain, "ae.com")
        XCTAssertTrue(americanEagle.isEnabled)
        XCTAssertTrue(americanEagle.categories.contains(.clothing))
        XCTAssertTrue(americanEagle.categories.contains(.accessories))
        XCTAssertEqual(americanEagle.websiteURL?.host, "www.ae.com")
        XCTAssertEqual(americanEagle.searchURLTemplate, "https://www.ae.com/us/en/s/search?keyword={QUERY}")
        XCTAssertEqual(americanEagle.affiliateTrackingActive, false)
    }

    func testShoppingSearchFiltersByStoreColorPriceOccasionAndStyle() {
        let products = [
            makeAffiliateProduct(
                id: "nike-white-gym",
                name: "White Training Sneaker",
                category: .shoes,
                subcategory: "sneakers",
                colors: ["white"],
                retailer: Retailer(name: "Nike", trackingID: "PENDING-APPROVAL", trackingParamName: "aff", disclosureName: "Nike"),
                price: Decimal(120),
                tags: ["gym", "casual", "size-12"]
            ),
            makeAffiliateProduct(
                id: "macys-black-formal",
                name: "Black Dress Shirt",
                category: .clothing,
                subcategory: "shirt",
                colors: ["black"],
                retailer: Retailer(name: "Macy's", trackingID: "PENDING-APPROVAL", trackingParamName: "aff", disclosureName: "Macy's"),
                price: Decimal(80),
                tags: ["formal", "office", "size-xl"]
            )
        ]
        let criteria = ShoppingSearchCriteria(
            query: "training",
            storeName: "Nike",
            category: .shoes,
            color: "white",
            size: "12",
            style: "casual",
            genderPresentation: nil,
            minimumPrice: Decimal(100),
            maximumPrice: Decimal(150),
            occasion: "gym"
        )

        let results = ShoppingSearchEngine.filter(products: products, criteria: criteria)

        XCTAssertEqual(results.map(\.id), ["nike-white-gym"])
    }

    func testAffiliateProductDecodesWhenSearchMetadataIsMissing() throws {
        let json = """
        {
          "id": "legacy-shirt",
          "name": "Legacy Shirt",
          "category": "clothing",
          "subcategory": "shirt",
          "colors": ["white"],
          "imageURL": "https://example.com/image.jpg",
          "retailer": {"name": "Macy's", "trackingID": "PENDING-APPROVAL", "trackingParamName": "aff", "disclosureName": "Macy's"},
          "affiliateURL": "https://www.macys.com/shirt",
          "price": 50,
          "salePrice": null,
          "saleEndsAt": null,
          "tags": ["office"],
          "genderPresentation": null
        }
        """

        let product = try JSONDecoder.catalog.decode(AffiliateProduct.self, from: Data(json.utf8))

        XCTAssertEqual(product.id, "legacy-shirt")
        XCTAssertNil(product.sizes)
        XCTAssertNil(product.priceRange)
        XCTAssertNil(product.occasionTags)
        XCTAssertNil(product.brand)
    }

    func testProductSearchQueryFiltersByBrandSizeOccasionTagsAndPriceRange() {
        let footLockerNike = makeAffiliateProduct(
            id: "footlocker-nike",
            name: "Nike Court Sneaker",
            category: .shoes,
            subcategory: "sneakers",
            colors: ["white"],
            retailer: Retailer(name: "Foot Locker", trackingID: "PENDING-APPROVAL", trackingParamName: "aff", disclosureName: "Foot Locker"),
            price: nil,
            tags: ["walking"],
            sizes: ["10", "11", "12"],
            priceRange: Decimal(90)...Decimal(130),
            occasionTags: [Occasion.casual.rawValue],
            brand: "Nike"
        )
        let retailerNike = makeAffiliateProduct(
            id: "nike-direct",
            name: "Nike Training Shirt",
            category: .clothing,
            subcategory: "shirt",
            colors: ["white"],
            retailer: Retailer(name: "Nike", trackingID: "PENDING-APPROVAL", trackingParamName: "aff", disclosureName: "Nike"),
            price: Decimal(45),
            tags: ["gym"],
            sizes: ["M"],
            occasionTags: [Occasion.work.rawValue],
            brand: "Nike"
        )

        let query = ProductSearchQuery(
            text: "sneaker",
            retailers: ["Foot Locker"],
            brands: ["Nike"],
            categories: [.shoes],
            colors: ["white"],
            sizes: ["12"],
            priceRange: Decimal(100)...Decimal(120),
            occasions: [Occasion.casual.rawValue],
            sort: .priceLowHigh
        )

        let results = ShoppingSearchEngine.filter(products: [footLockerNike, retailerNike], query: query)

        XCTAssertEqual(results.map(\.id), ["footlocker-nike"])
    }

    func testCriteriaRelaxationKeepsFullMatchUnchanged() {
        let product = makeAffiliateProduct(
            id: "exact",
            name: "Navy Office Shirt",
            colors: ["navy"],
            tags: ["polished"],
            sizes: ["M"],
            occasionTags: ["office"],
            brand: "Macy's"
        )
        var criteria = ShoppingSearchCriteria()
        criteria.color = "navy"
        criteria.size = "M"
        criteria.style = "polished"
        criteria.occasion = "office"

        let result = ShoppingSearchEngine.relaxedFilter(products: [product], criteria: criteria)

        XCTAssertNil(result.relaxedFilter)
        XCTAssertEqual(result.displayedResults.map(\.id), ["exact"])
        XCTAssertEqual(ShoppingSearchEngine.filter(products: [product], criteria: criteria).map(\.id), ["exact"])
    }

    func testQueryRelaxationKeepsFullMatchUnchanged() {
        let product = makeAffiliateProduct(
            id: "exact-query",
            name: "Nike Navy Sneaker",
            category: .shoes,
            subcategory: "sneakers",
            colors: ["navy"],
            retailer: Retailer(name: "Nike", trackingID: "PENDING-APPROVAL", trackingParamName: "aff", disclosureName: "Nike"),
            price: Decimal(90),
            tags: ["walking"],
            sizes: ["10"],
            occasionTags: ["casual"],
            brand: "Nike"
        )
        let query = ProductSearchQuery(
            retailers: ["Nike"],
            brands: ["Nike"],
            categories: [.shoes],
            colors: ["navy"],
            sizes: ["10"],
            priceRange: Decimal(50)...Decimal(100),
            occasions: ["casual"]
        )

        let result = ShoppingSearchEngine.relaxedFilter(products: [product], query: query)

        XCTAssertNil(result.relaxedFilter)
        XCTAssertEqual(result.displayedResults.map(\.id), ["exact-query"])
        XCTAssertEqual(ShoppingSearchEngine.filter(products: [product], query: query).map(\.id), ["exact-query"])
    }

    func testRelaxationDropsFirstUnblockingFilterByPriority() {
        let product = makeAffiliateProduct(
            id: "relaxed",
            name: "Navy Casual Sneaker",
            category: .shoes,
            subcategory: "sneakers",
            colors: ["navy"],
            retailer: Retailer(name: "Nike", trackingID: "PENDING-APPROVAL", trackingParamName: "aff", disclosureName: "Nike"),
            price: Decimal(90),
            tags: ["casual"],
            sizes: ["10"],
            occasionTags: ["weekend"],
            brand: "Nike"
        )
        var criteria = ShoppingSearchCriteria()
        criteria.storeName = "Nike"
        criteria.brand = "Nike"
        criteria.category = .shoes
        criteria.color = "navy"
        criteria.size = "10"
        criteria.style = "casual"
        criteria.maximumPrice = Decimal(100)
        criteria.occasion = "office"
        let query = ProductSearchQuery(
            retailers: ["Nike"],
            brands: ["Nike"],
            categories: [.shoes],
            colors: ["navy"],
            sizes: ["10"],
            priceRange: Decimal(0)...Decimal(100),
            occasions: ["office"]
        )

        let criteriaResult = ShoppingSearchEngine.relaxedFilter(products: [product], criteria: criteria)
        let queryResult = ShoppingSearchEngine.relaxedFilter(products: [product], query: query)

        XCTAssertEqual(criteriaResult.relaxedFilter, .occasion)
        XCTAssertEqual(criteriaResult.displayedResults.map(\.id), ["relaxed"])
        XCTAssertEqual(queryResult.relaxedFilter, .occasion)
        XCTAssertEqual(queryResult.displayedResults.map(\.id), ["relaxed"])
    }

    func testRelaxationFallsThroughToStyleBeforeMaxPrice() {
        let product = makeAffiliateProduct(
            id: "style-relaxed",
            name: "Navy Office Shirt",
            colors: ["navy"],
            price: Decimal(80),
            tags: ["polished"],
            occasionTags: ["office"]
        )
        var criteria = ShoppingSearchCriteria()
        criteria.color = "navy"
        criteria.style = "sporty"
        criteria.maximumPrice = Decimal(100)
        criteria.occasion = "office"

        let result = ShoppingSearchEngine.relaxedFilter(products: [product], criteria: criteria)

        XCTAssertEqual(result.relaxedFilter, .style)
        XCTAssertEqual(result.displayedResults.map(\.id), ["style-relaxed"])
    }

    func testSelectedAmazonStoreReturnsOnlyAmazonProducts() {
        let amazon = makeAffiliateProduct(
            id: "amazon-shirt",
            name: "Amazon Shirt",
            retailer: Retailer(name: "Amazon", trackingID: "amazon-20", trackingParamName: "tag", disclosureName: "Amazon")
        )
        let macys = makeAffiliateProduct(
            id: "macys-shirt",
            name: "Macy's Shirt",
            retailer: Retailer(name: "Macy's", trackingID: "PENDING-APPROVAL", trackingParamName: "aff", disclosureName: "Macy's")
        )
        var criteria = ShoppingSearchCriteria()
        criteria.storeName = "Amazon"

        let result = ShoppingSearchEngine.relaxedFilter(products: [amazon, macys], criteria: criteria)

        XCTAssertNil(result.relaxedFilter)
        XCTAssertEqual(result.displayedResults.map(\.id), ["amazon-shirt"])
    }

    func testSelectedZeroInventoryStoreDoesNotRelaxToUnrelatedProducts() {
        let amazon = makeAffiliateProduct(
            id: "amazon-shirt",
            name: "Amazon Shirt",
            retailer: Retailer(name: "Amazon", trackingID: "amazon-20", trackingParamName: "tag", disclosureName: "Amazon")
        )
        var criteria = ShoppingSearchCriteria()
        criteria.storeName = "Nike"
        let query = ProductSearchQuery(retailers: ["Nike"])

        let criteriaResult = ShoppingSearchEngine.relaxedFilter(products: [amazon], criteria: criteria)
        let queryResult = ShoppingSearchEngine.relaxedFilter(products: [amazon], query: query)

        XCTAssertTrue(criteriaResult.displayedResults.isEmpty)
        XCTAssertNil(criteriaResult.relaxedFilter)
        XCTAssertTrue(queryResult.displayedResults.isEmpty)
        XCTAssertNil(queryResult.relaxedFilter)
    }

    func testStoreFilterIsNeverIncludedInRelaxationRemoval() throws {
        let source = try projectSource("StyleMatchAI/Shopping/ShoppingSearchEngine.swift")
        let priorityRange = try XCTUnwrap(source.range(of: "private static let relaxationPriority"))
        let predicateRange = try XCTUnwrap(source.range(of: "private struct SearchPredicate"))
        let priority = String(source[priorityRange.lowerBound..<predicateRange.lowerBound])

        XCTAssertFalse(priority.contains(".store"))
        XCTAssertTrue(priority.contains(".occasion"))
        XCTAssertTrue(priority.contains(".style"))
        XCTAssertTrue(priority.contains(".maxPrice"))
        XCTAssertTrue(priority.contains(".color"))
        XCTAssertTrue(priority.contains(".size"))
        XCTAssertTrue(priority.contains(".brand"))
        XCTAssertTrue(priority.contains(".category"))
    }

    func testRetailerSpecificEmptyStateAndShowAllProductsActionArePresent() throws {
        let shoppingView = try projectSource("StyleMatchAI/Shopping/ShoppingView.swift")
        let storeSearchView = try projectSource("StyleMatchAI/Shopping/StoreSearchView.swift")

        XCTAssertTrue(shoppingView.contains("selectedStoreUnavailableState"))
        XCTAssertTrue(shoppingView.contains("products are coming soon"))
        XCTAssertTrue(shoppingView.contains("Show All Products"))
        XCTAssertTrue(shoppingView.contains("searchCriteria.storeName = nil"))
        XCTAssertTrue(storeSearchView.contains("selectedRetailerUnavailableState"))
        XCTAssertTrue(storeSearchView.contains("products are coming soon"))
        XCTAssertTrue(storeSearchView.contains("Show All Products"))
        XCTAssertTrue(storeSearchView.contains("selectedRetailers.removeAll()"))
    }

    func testStoreInventoryFixPreservesSafeOutboundRouting() throws {
        let shoppingView = try projectSource("StyleMatchAI/Shopping/ShoppingView.swift")
        let storeSearchView = try projectSource("StyleMatchAI/Shopping/StoreSearchView.swift")
        let scanView = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(shoppingView.contains("openProductExternally(product)"))
        XCTAssertTrue(storeSearchView.contains("onTap: { openProductExternally(ranked.product) }"))
        for source in [shoppingView, storeSearchView, scanView] {
            XCTAssertTrue(source.contains("ShoppingProductOpener"))
            XCTAssertFalse(source.contains("UIApplication.shared.open(AffiliateLinkBuilder.outboundURL(for: product)"))
        }
    }

    func testSoftFiltersStillRelaxWhenStoreMatches() {
        let product = makeAffiliateProduct(
            id: "nike-relaxed-color",
            name: "Nike Casual Shirt",
            colors: ["blue"],
            retailer: Retailer(name: "Nike", trackingID: "PENDING-APPROVAL", trackingParamName: "aff", disclosureName: "Nike")
        )
        var criteria = ShoppingSearchCriteria()
        criteria.storeName = "Nike"
        criteria.color = "red"

        let result = ShoppingSearchEngine.relaxedFilter(products: [product], criteria: criteria)

        XCTAssertEqual(result.relaxedFilter, .color)
        XCTAssertEqual(result.displayedResults.map(\.id), ["nike-relaxed-color"])
    }

    func testRelaxationTrueEmptyKeepsExistingViewEmptyMessages() throws {
        let product = makeAffiliateProduct(
            id: "product",
            name: "Navy Shirt",
            colors: ["navy"],
            tags: ["office"],
            occasionTags: ["office"]
        )
        var criteria = ShoppingSearchCriteria()
        criteria.query = "zzzz"
        criteria.occasion = "office"
        let query = ProductSearchQuery(text: "zzzz", occasions: ["office"])

        XCTAssertTrue(ShoppingSearchEngine.relaxedFilter(products: [product], criteria: criteria).displayedResults.isEmpty)
        XCTAssertNil(ShoppingSearchEngine.relaxedFilter(products: [product], criteria: criteria).relaxedFilter)
        XCTAssertTrue(ShoppingSearchEngine.relaxedFilter(products: [product], query: query).displayedResults.isEmpty)
        XCTAssertNil(ShoppingSearchEngine.relaxedFilter(products: [product], query: query).relaxedFilter)

        let shoppingView = try projectSource("StyleMatchAI/Shopping/ShoppingView.swift")
        let storeSearchView = try projectSource("StyleMatchAI/Shopping/StoreSearchView.swift")
        XCTAssertTrue(shoppingView.contains("Let's widen the styling lens"))
        XCTAssertTrue(storeSearchView.contains("No matches - try fewer filters"))
        XCTAssertTrue(shoppingView.contains("No exact matches — showing results without your"))
        XCTAssertTrue(storeSearchView.contains("No exact matches — showing results without your"))
    }

    func testRelaxationOnlyUsesValidatedSafeProducts() {
        let safe = makeAffiliateProduct(
            id: "safe",
            name: "Safe Navy Shirt",
            colors: ["navy"],
            affiliateURL: URL(string: "https://www.macys.com/safe-shirt")!,
            tags: ["casual"],
            occasionTags: ["weekend"]
        )
        let unsafe = makeAffiliateProduct(
            id: "unsafe",
            name: "Unsafe Navy Shirt",
            colors: ["navy"],
            affiliateURL: URL(string: "https://stylematch.local/placeholder")!,
            tags: ["casual"],
            occasionTags: ["weekend"]
        )
        let validated = CatalogProductSafetyValidator.validated([safe, unsafe], regionCode: "US")
        var criteria = ShoppingSearchCriteria()
        criteria.color = "navy"
        criteria.occasion = "office"

        let result = ShoppingSearchEngine.relaxedFilter(products: validated, criteria: criteria)

        XCTAssertEqual(validated.map(\.id), ["safe"])
        XCTAssertEqual(result.relaxedFilter, .occasion)
        XCTAssertEqual(result.displayedResults.map(\.id), ["safe"])
    }

    func testSharedRelaxationPriorityMatchesCriteriaAndQueryInputs() {
        let product = makeAffiliateProduct(
            id: "shared",
            name: "Blue Casual Shirt",
            colors: ["blue"],
            price: Decimal(75),
            tags: ["casual"],
            occasionTags: ["weekend"]
        )
        var criteria = ShoppingSearchCriteria()
        criteria.color = "blue"
        criteria.maximumPrice = Decimal(80)
        criteria.occasion = "office"
        let query = ProductSearchQuery(
            colors: ["blue"],
            priceRange: Decimal(0)...Decimal(80),
            occasions: ["office"]
        )

        XCTAssertEqual(ShoppingSearchEngine.relaxedFilter(products: [product], criteria: criteria).relaxedFilter, .occasion)
        XCTAssertEqual(ShoppingSearchEngine.relaxedFilter(products: [product], query: query).relaxedFilter, .occasion)
    }

    func testProductSearchQueryCanFilterSaleOnlyAndSortNewestSale() {
        let olderSale = makeAffiliateProduct(
            id: "older-sale",
            name: "Older Sale Shirt",
            salePrice: Decimal(40),
            saleEndsAt: fixedDate(year: 2026, month: 7, day: 10),
            tags: ["casual"],
            occasionTags: [Occasion.casual.rawValue],
            brand: "Macy's"
        )
        let newerSale = makeAffiliateProduct(
            id: "newer-sale",
            name: "Newer Sale Shirt",
            salePrice: Decimal(50),
            saleEndsAt: fixedDate(year: 2026, month: 8, day: 1),
            tags: ["casual"],
            occasionTags: [Occasion.casual.rawValue],
            brand: "Macy's"
        )
        let regular = makeAffiliateProduct(
            id: "regular",
            name: "Regular Shirt",
            tags: ["casual"],
            occasionTags: [Occasion.casual.rawValue],
            brand: "Macy's"
        )
        let query = ProductSearchQuery(
            brands: ["Macy's"],
            occasions: [Occasion.casual.rawValue],
            onSaleOnly: true,
            sort: .newestSale
        )

        let results = ShoppingSearchEngine.filter(
            products: [olderSale, regular, newerSale],
            query: query,
            now: fixedDate(year: 2026, month: 7, day: 7)
        )

        XCTAssertEqual(results.map(\.id), ["newer-sale", "older-sale"])
    }

    func testCatalogProductSearchProviderUsesProductSearchQuery() async throws {
        let provider = CatalogProductSearchProvider(
            sourceName: "Test Catalog",
            catalogProvider: StaticProductCatalogProvider(products: [
                makeAffiliateProduct(id: "nike", name: "Nike Sneaker", category: .shoes, subcategory: "sneakers", colors: ["white"], sizes: ["12"], brand: "Nike"),
                makeAffiliateProduct(id: "adidas", name: "Adidas Sneaker", category: .shoes, subcategory: "sneakers", colors: ["black"], sizes: ["10"], brand: "Adidas")
            ])
        )
        let query = ProductSearchQuery(brands: ["Nike"], colors: ["white"], sizes: ["12"])

        let results = try await provider.search(query)

        XCTAssertEqual(provider.sourceName, "Test Catalog")
        XCTAssertEqual(results.map(\.id), ["nike"])
    }

    func testCatalogSearchProviderTokenizedTextMatchesNameBrandSubcategoryAndTags() async throws {
        let provider = CatalogSearchProvider(
            sourceName: "Test Catalog",
            catalogProvider: StaticProductCatalogProvider(products: [
                makeAffiliateProduct(id: "nike-shoe", name: "Court Sneaker", category: .shoes, subcategory: "running shoe", colors: ["white"], tags: ["walking"], brand: "Nike"),
                makeAffiliateProduct(id: "macys-shirt", name: "Oxford Shirt", category: .clothing, subcategory: "dress shirt", colors: ["blue"], tags: ["office"], brand: "Macy's")
            ])
        )

        let results = try await provider.search(ProductSearchQuery(text: "nike walking"))

        XCTAssertEqual(results.map(\.id), ["nike-shoe"])
    }

    func testCatalogSearchProviderHandlesThousandProductCatalogUnderFiftyMillisecondsAfterIndexing() async throws {
        let products: [AffiliateProduct] = (0..<1_000).map { index in
            let isTarget = index == 777
            let productID = "product-\(index)"
            let name = isTarget ? "Performance White Sneaker" : "Catalog Product \(index)"
            let category: ProductCategory = isTarget ? .shoes : .clothing
            let subcategory = isTarget ? "sneakers" : "shirt"
            let colors = isTarget ? ["white"] : ["black"]
            let tags = isTarget ? ["walking", "travel"] : ["casual"]
            let sizes = isTarget ? ["12"] : ["M"]
            let brand = isTarget ? "Nike" : "Brand \(index)"
            return makeAffiliateProduct(
                id: productID,
                name: name,
                category: category,
                subcategory: subcategory,
                colors: colors,
                tags: tags,
                sizes: sizes,
                brand: brand
            )
        }
        let provider = CatalogSearchProvider(catalogProvider: StaticProductCatalogProvider(products: products))
        _ = try await provider.search(ProductSearchQuery(text: "product"))

        let start = Date()
        let results = try await provider.search(ProductSearchQuery(text: "nike walking", brands: ["Nike"], colors: ["white"], sizes: ["12"]))
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(results.map { $0.id }, ["product-777"])
        XCTAssertLessThan(elapsed, 0.05)
    }

    func testAggregatedSearchProviderMergesDedupesAndSkipsFailingAdapters() async throws {
        let duplicateA = makeAffiliateProduct(id: "nike-a", name: "Court Sneaker", retailer: Retailer(name: "Nike", trackingID: "PENDING-APPROVAL", trackingParamName: "aff", disclosureName: "Nike"), brand: "Nike")
        let duplicateB = makeAffiliateProduct(id: "nike-b", name: "Court Sneaker", retailer: Retailer(name: "Nike", trackingID: "PENDING-APPROVAL", trackingParamName: "aff", disclosureName: "Nike"), brand: "Nike")
        let unique = makeAffiliateProduct(id: "macys", name: "Oxford Shirt", retailer: Retailer(name: "Macy's", trackingID: "PENDING-APPROVAL", trackingParamName: "aff", disclosureName: "Macy's"), brand: "Macy's")
        let provider = AggregatedSearchProvider(
            adapters: [
                StaticRetailerSearchAdapter(retailerName: "Nike", products: [duplicateA]),
                FailingRetailerSearchAdapter(retailerName: "Broken"),
                StaticRetailerSearchAdapter(retailerName: "Macy's", products: [duplicateB, unique])
            ],
            adapterTimeoutNanoseconds: 100_000_000
        )

        let results = try await provider.search(ProductSearchQuery())

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results.filter { $0.name == "Court Sneaker" && $0.brand == "Nike" && $0.retailer.name == "Nike" }.count, 1)
        XCTAssertTrue(results.contains { $0.id == "macys" })
    }

    func testAggregatedSearchProviderTimesOutSlowAdapters() async throws {
        let fast = makeAffiliateProduct(id: "fast", name: "Fast Shirt", brand: "Macy's")
        let slow = makeAffiliateProduct(id: "slow", name: "Slow Shirt", brand: "Nike")
        let provider = AggregatedSearchProvider(
            adapters: [
                StaticRetailerSearchAdapter(retailerName: "Fast", products: [fast]),
                SlowRetailerSearchAdapter(retailerName: "Slow", products: [slow], delayNanoseconds: 200_000_000)
            ],
            adapterTimeoutNanoseconds: 20_000_000
        )

        let results = try await provider.search(ProductSearchQuery())

        XCTAssertEqual(results.map(\.id), ["fast"])
    }

    func testBestBuyAdapterMapsQueryToPublicProductsAPIWithoutPII() throws {
        let adapter = BestBuyAdapter(apiKey: "TEST-BESTBUY-KEY")
        let request = try adapter.makeRequest(for: ProductSearchQuery(
            text: "white smartwatch",
            brands: ["Fitbit"],
            categories: [.electronics],
            colors: ["white"],
            priceRange: Decimal(50)...Decimal(150),
            onSaleOnly: true,
            sort: .priceLowHigh
        ))

        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = components.queryItems ?? []
        let names = Set(queryItems.map(\.name))

        XCTAssertEqual(components.host, "api.bestbuy.com")
        XCTAssertEqual(components.path, "/v1/products")
        XCTAssertTrue(queryItems.contains(URLQueryItem(name: "apiKey", value: "TEST-BESTBUY-KEY")))
        XCTAssertTrue(queryItems.contains(URLQueryItem(name: "q", value: "white smartwatch")))
        XCTAssertTrue(queryItems.contains(URLQueryItem(name: "brand", value: "Fitbit")))
        XCTAssertTrue(queryItems.contains(URLQueryItem(name: "category", value: "electronics")))
        XCTAssertTrue(queryItems.contains(URLQueryItem(name: "onSaleOnly", value: "true")))
        XCTAssertFalse(names.contains("scanPhoto"))
        XCTAssertFalse(names.contains("outfitMemory"))
        XCTAssertFalse(names.contains("coordinates"))
        XCTAssertFalse(names.contains("userID"))
    }

    func testBestBuyAdapterFailsSafelyWhenBaseURLIsUnavailable() throws {
        let adapter = BestBuyAdapter(apiKey: "TEST-BESTBUY-KEY", baseURL: nil)

        XCTAssertThrowsError(try adapter.makeRequest(for: ProductSearchQuery())) { error in
            guard case RetailerAdapterConfigurationError.invalidRequestURL = error else {
                return XCTFail("Expected invalidRequestURL, received \(error).")
            }
        }
    }

    func testBestBuyAdapterDecodesProductFixture() throws {
        let json = """
        {
          "products": [
            {
              "sku": 12345,
              "name": "Fitness Smartwatch",
              "manufacturer": "Fitbit",
              "salePrice": 149.99,
              "regularPrice": 199.99,
              "image": "https://img.example.com/watch.jpg",
              "url": "https://www.bestbuy.com/site/watch",
              "type": "Smartwatch",
              "color": "Black"
            }
          ]
        }
        """

        let products = try BestBuyAdapter(apiKey: "TEST").decodeProducts(from: Data(json.utf8))

        XCTAssertEqual(products.first?.id, "bestbuy-12345")
        XCTAssertEqual(products.first?.retailer.name, "Best Buy")
        XCTAssertEqual(products.first?.brand, "Fitbit")
        XCTAssertEqual(products.first?.category, .electronics)
        XCTAssertEqual(products.first?.salePrice, Decimal(string: "149.99"))
    }

    func testProxyRetailerAdaptersMapToApprovedProxyEndpoints() throws {
        let proxyBaseURL = URL(string: "https://proxy.example.com/stylematch")!
        let query = ProductSearchQuery(text: "white shirt", retailers: ["Target"], brands: ["Nike"], categories: [.clothing], colors: ["white"], sizes: ["L"], genderPresentation: "men", priceRange: Decimal(20)...Decimal(80), occasions: [Occasion.casual.rawValue], sort: .newestSale)
        let adapters: [(String, URLRequest)] = [
            ("Amazon", try AmazonPAAPIAdapter(proxyBaseURL: proxyBaseURL).makeRequest(for: query)),
            ("Impact", try ImpactAdapter(proxyBaseURL: proxyBaseURL).makeRequest(for: query)),
            ("CJ", try CJAdapter(proxyBaseURL: proxyBaseURL).makeRequest(for: query)),
            ("Rakuten", try RakutenAdapter(proxyBaseURL: proxyBaseURL).makeRequest(for: query)),
            ("Sovrn", try SovrnAdapter(proxyBaseURL: proxyBaseURL).makeRequest(for: query))
        ]
        let expectedPaths = [
            "Amazon": "/stylematch/amazon/search",
            "Impact": "/stylematch/impact/search",
            "CJ": "/stylematch/cj/search",
            "Rakuten": "/stylematch/rakuten/search",
            "Sovrn": "/stylematch/sovrn/search"
        ]

        for (name, request) in adapters {
            let url = try XCTUnwrap(request.url)
            let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            let queryItems = components.queryItems ?? []
            let queryNames = Set(queryItems.map(\.name))

            XCTAssertEqual(components.path, expectedPaths[name])
            XCTAssertTrue(queryItems.contains(URLQueryItem(name: "q", value: "white shirt")))
            XCTAssertTrue(queryItems.contains(URLQueryItem(name: "retailer", value: "Target")))
            XCTAssertTrue(queryItems.contains(URLQueryItem(name: "brand", value: "Nike")))
            XCTAssertTrue(queryItems.contains(URLQueryItem(name: "sort", value: "newestSale")))
            XCTAssertFalse(queryNames.contains("scanPhoto"))
            XCTAssertFalse(queryNames.contains("outfitMemory"))
            XCTAssertFalse(queryNames.contains("coordinates"))
            XCTAssertFalse(queryNames.contains("userID"))
        }
    }

    func testRetailerConfigCarriesSearchAdapterRoutingStatus() throws {
        let config = try JSONDecoder.catalog.decode(RetailerConfig.self, from: Data(contentsOf: retailerConfigFixtureURL()))

        let bestBuy = try XCTUnwrap(config.retailer(named: "Best Buy"))
        let amazon = try XCTUnwrap(config.retailer(named: "Amazon"))
        let target = try XCTUnwrap(config.retailer(named: "Target"))
        let americanEagle = try XCTUnwrap(config.retailer(named: "American Eagle"))

        XCTAssertEqual(bestBuy.searchAdapter, "bestbuy")
        XCTAssertEqual(amazon.searchAdapter, "amazon")
        XCTAssertEqual(target.searchAdapter, "impact")
        XCTAssertEqual(americanEagle.searchAdapter, "none")
        XCTAssertEqual(bestBuy.searchStatus, "pending")
        XCTAssertEqual(amazon.searchStatus, "active")
        XCTAssertEqual(americanEagle.searchStatus, "pending")
    }

    func testEveryRetailerAdapterDecodesLocalFixtureResponses() throws {
        let proxy = URL(string: "https://proxy.example.com/stylematch")!
        let decoded = [
            try AmazonPAAPIAdapter(proxyBaseURL: proxy).decodeProducts(from: Data(contentsOf: fixtureURL("amazon_paapi_response.json"))),
            try ImpactAdapter(proxyBaseURL: proxy).decodeProducts(from: Data(contentsOf: fixtureURL("impact_response.json"))),
            try CJAdapter(proxyBaseURL: proxy).decodeProducts(from: Data(contentsOf: fixtureURL("cj_response.json"))),
            try RakutenAdapter(proxyBaseURL: proxy).decodeProducts(from: Data(contentsOf: fixtureURL("rakuten_response.json"))),
            try SovrnAdapter(proxyBaseURL: proxy).decodeProducts(from: Data(contentsOf: fixtureURL("sovrn_response.json")))
        ]

        XCTAssertEqual(decoded.map { $0.count }, [1, 1, 1, 1, 1])
        XCTAssertEqual(decoded[0].first?.retailer.name, "Amazon")
        XCTAssertEqual(decoded[1].first?.retailer.name, "Target")
        XCTAssertEqual(decoded[2].first?.retailer.name, "Macy's")
        XCTAssertEqual(decoded[3].first?.retailer.name, "Nordstrom")
        XCTAssertEqual(decoded[4].first?.retailer.name, "H&M")
    }

    func testNoPIIInOutboundAdapterRequestsForEveryAdapter() throws {
        let proxy = URL(string: "https://proxy.example.com/stylematch")!
        let query = ProductSearchQuery(text: "white shirt", retailers: ["Amazon"], brands: ["Nike"], categories: [.clothing], colors: ["white"], sizes: ["L"], genderPresentation: "men", priceRange: Decimal(20)...Decimal(100), occasions: ["casual"], onSaleOnly: true, sort: .relevance)
        let requests = [
            try BestBuyAdapter(apiKey: "TEST").makeRequest(for: query),
            try AmazonPAAPIAdapter(proxyBaseURL: proxy).makeRequest(for: query),
            try ImpactAdapter(proxyBaseURL: proxy).makeRequest(for: query),
            try CJAdapter(proxyBaseURL: proxy).makeRequest(for: query),
            try RakutenAdapter(proxyBaseURL: proxy).makeRequest(for: query),
            try SovrnAdapter(proxyBaseURL: proxy).makeRequest(for: query)
        ]

        for request in requests {
            let urlText = try XCTUnwrap(request.url?.absoluteString)
            XCTAssertFalse(urlText.localizedCaseInsensitiveContains("outfitMemory"))
            XCTAssertFalse(urlText.localizedCaseInsensitiveContains("scanPhoto"))
            XCTAssertFalse(urlText.localizedCaseInsensitiveContains("coordinates"))
            XCTAssertFalse(urlText.localizedCaseInsensitiveContains("userID"))
            XCTAssertFalse(urlText.localizedCaseInsensitiveContains("favorite"))
            XCTAssertFalse(urlText.localizedCaseInsensitiveContains("history"))
        }
    }

    func testLiveSearchDisabledDoesNotInvokeAdapters() async throws {
        let spy = SpyRetailerSearchAdapter(retailerName: "Spy", products: [makeAffiliateProduct(id: "spy")])
        let provider = ShoppingDataSourceResolver.aggregatedSearchProvider(liveSearchEnabled: false, adapters: [spy])

        XCTAssertNil(provider)
        XCTAssertEqual(spy.callCount, 0)
    }

    func testShoppingFavoritesAreCappedAndClearedByPrivacyDeletion() {
        let store = ShoppingLocalStore(defaults: defaults, userID: userA)
        store.savedFavorites = (0..<250).map { "product-\($0)" }
        store.wishlistProductIDs = (0..<250).map { "wishlist-\($0)" }
        store.cartProductIDs = (0..<150).map { "cart-\($0)" }
        store.shoppingCardProductIDs = (0..<250).map { "card-\($0)" }
        store.setPreferredRetailerIDs(["macys"], supportedStores: makeSupportedStores())
        store.saleNotificationsEnabled = true
        store.saleStateSnapshots = [
            "old": ShoppingSaleStateSnapshot(productID: "old", salePrice: Decimal(10), saleEndsAt: nil, isActiveSale: true)
        ]

        XCTAssertEqual(store.savedFavorites.count, 200)
        XCTAssertEqual(store.wishlistProductIDs.count, 200)
        XCTAssertEqual(store.cartProductIDs.count, 100)
        XCTAssertEqual(store.shoppingCardProductIDs.count, 200)

        PersonalStylistStorage.deletePersonalization(for: userA, defaults: defaults)
        ShoppingLocalStore(defaults: defaults, userID: userA).deleteAll()

        let cleared = ShoppingLocalStore(defaults: defaults, userID: userA)
        XCTAssertTrue(cleared.savedFavorites.isEmpty)
        XCTAssertTrue(cleared.wishlistProductIDs.isEmpty)
        XCTAssertTrue(cleared.cartProductIDs.isEmpty)
        XCTAssertTrue(cleared.shoppingCardProductIDs.isEmpty)
        XCTAssertTrue(cleared.preferredRetailerIDs.isEmpty)
        XCTAssertTrue(cleared.saleStateSnapshots.isEmpty)
        XCTAssertFalse(cleared.saleNotificationsEnabled)
    }

    func testShoppingProductFavoriteAndWishlistActionsPersistState() {
        let store = ShoppingLocalStore(defaults: defaults, userID: userA)

        store.toggleFavorite("product-1")
        store.toggleWishlist("product-1")

        let reloaded = ShoppingLocalStore(defaults: defaults, userID: userA)
        XCTAssertEqual(reloaded.savedFavorites, ["product-1"])
        XCTAssertEqual(reloaded.wishlistProductIDs, ["product-1"])

        reloaded.toggleFavorite("product-1")
        reloaded.toggleWishlist("product-1")

        let cleared = ShoppingLocalStore(defaults: defaults, userID: userA)
        XCTAssertTrue(cleared.savedFavorites.isEmpty)
        XCTAssertTrue(cleared.wishlistProductIDs.isEmpty)
    }

    func testShoppingObservableStorePublishesFavoriteAndWishlistChanges() {
        let store = ShoppingLocalStore(defaults: defaults, userID: userA)
        var changeCount = 0
        let cancellable = store.objectWillChange.sink {
            changeCount += 1
        }

        store.toggleFavorite(productID: "observable-favorite")
        store.toggleWishlist(productID: "observable-wishlist")

        XCTAssertEqual(store.savedFavorites, ["observable-favorite"])
        XCTAssertEqual(store.wishlistProductIDs, ["observable-wishlist"])
        XCTAssertGreaterThanOrEqual(changeCount, 2)
        cancellable.cancel()
    }

    func testShoppingObservableStoreMigratesExistingPersistedValues() {
        let favoriteKey = PersonalStylistStorage.scopedKey(ShoppingLocalStore.savedFavoritesBaseKey, userID: userA)
        let wishlistKey = PersonalStylistStorage.scopedKey(ShoppingLocalStore.wishlistBaseKey, userID: userA)
        let alertKey = PersonalStylistStorage.scopedKey(ShoppingLocalStore.saleAlertProductIDsBaseKey, userID: userA)
        let cardKey = PersonalStylistStorage.scopedKey(ShoppingLocalStore.shoppingCardsBaseKey, userID: userA)

        defaults.set(["old-favorite"], forKey: favoriteKey)
        defaults.set(["old-wishlist"], forKey: wishlistKey)
        defaults.set(["old-alert"], forKey: alertKey)
        defaults.set(["old-card"], forKey: cardKey)

        let store = ShoppingLocalStore(defaults: defaults, userID: userA)

        XCTAssertEqual(store.savedFavorites, ["old-favorite"])
        XCTAssertEqual(store.wishlistProductIDs, ["old-wishlist"])
        XCTAssertEqual(store.saleAlertProductIDs, Set(["old-alert"]))
        XCTAssertEqual(store.shoppingCardProductIDs, ["old-card"])
    }

    func testPreferredRetailerIDsPersistAcrossStoreRecreation() {
        let supportedStores = makeSupportedStores()
        let store = ShoppingLocalStore(defaults: defaults, userID: userA)

        store.setPreferredRetailerIDs(["amazon", "macys"], supportedStores: supportedStores)

        let reloaded = ShoppingLocalStore(defaults: defaults, userID: userA, supportedStores: supportedStores)
        XCTAssertEqual(reloaded.preferredRetailerIDs, ["amazon", "macys"])
    }

    func testPreferredRetailerIDsUseAccountScopedPresentationNamespaceByDefault() {
        let supportedStores = makeSupportedStores()
        defaults.set("guest", forKey: AccountScopedStorage.activeUserMarkerKey)
        defaults.set("guest", forKey: "customerAccountMode")
        defaults.set("stale@example.com", forKey: "customerAccountEmail")

        let store = ShoppingLocalStore(defaults: defaults, supportedStores: supportedStores)
        store.setPreferredRetailerIDs(["nike", "macys"], supportedStores: supportedStores)

        let guestKey = PersonalStylistStorage.scopedKey(ShoppingLocalStore.preferredRetailerIDsBaseKey, userID: "guest")
        let staleEmailKey = PersonalStylistStorage.scopedKey(ShoppingLocalStore.preferredRetailerIDsBaseKey, userID: "stale@example.com")
        XCTAssertEqual(defaults.stringArray(forKey: guestKey), ["nike", "macys"])
        XCTAssertNil(defaults.stringArray(forKey: staleEmailKey))
    }

    func testPreferredRetailerIDsSurviveLaunchRepairSimulation() {
        let supportedStores = makeSupportedStores()
        defaults.set("guest", forKey: AccountScopedStorage.activeUserMarkerKey)
        defaults.set("guest", forKey: "customerAccountMode")

        ShoppingLocalStore(defaults: defaults, supportedStores: supportedStores)
            .setPreferredRetailerIDs(["nike", "macys"], supportedStores: supportedStores)

        if AccountScopedStorage.prepareForLaunch(defaults: defaults, environment: .production) {
            AccountScopedStorage.restoreCapturedLaunchData(defaults: defaults, environment: .production)
        }

        let relaunched = ShoppingLocalStore(defaults: defaults, supportedStores: supportedStores)
        XCTAssertEqual(relaunched.preferredRetailerIDs, ["nike", "macys"])
    }

    func testPreferredRetailerInitializationDoesNotOverwriteNonemptySavedPreferences() {
        let supportedStores = makeSupportedStores()
        let key = PersonalStylistStorage.scopedKey(ShoppingLocalStore.preferredRetailerIDsBaseKey, userID: userA)
        defaults.set(["nike", "macys"], forKey: key)

        _ = ShoppingLocalStore(defaults: defaults, userID: userA, supportedStores: supportedStores)

        XCTAssertEqual(defaults.stringArray(forKey: key), ["nike", "macys"])
    }

    func testEmptyPreloadRegistryCannotEraseSavedSelectionAcrossAppearanceAndRelaunch() {
        let key = PersonalStylistStorage.scopedKey(ShoppingLocalStore.preferredRetailerIDsBaseKey, userID: userA)
        defaults.set(["nike"], forKey: key)

        let firstAppearance = ShoppingLocalStore(defaults: defaults, userID: userA)
        XCTAssertEqual(
            firstAppearance.normalizePreferredRetailerIDs(
                supportedStores: [],
                registryIsLoaded: false
            ),
            ["nike"]
        )
        XCTAssertEqual(defaults.stringArray(forKey: key), ["nike"])

        let relaunched = ShoppingLocalStore(defaults: defaults, userID: userA)
        XCTAssertEqual(
            relaunched.normalizePreferredRetailerIDs(
                supportedStores: [],
                registryIsLoaded: false
            ),
            ["nike"]
        )
        XCTAssertEqual(defaults.stringArray(forKey: key), ["nike"])
    }

    func testLoadedRegistryPrunesGenuinelyUnsupportedCanonicalID() {
        let key = PersonalStylistStorage.scopedKey(ShoppingLocalStore.preferredRetailerIDsBaseKey, userID: userA)
        defaults.set(["nike", "unsupported-retailer"], forKey: key)
        let store = ShoppingLocalStore(defaults: defaults, userID: userA)

        XCTAssertEqual(
            store.normalizePreferredRetailerIDs(
                supportedStores: makeSupportedStores(),
                registryIsLoaded: true
            ),
            ["nike"]
        )
        XCTAssertEqual(defaults.stringArray(forKey: key), ["nike"])
    }

    func testRowTogglePersistsAcrossSheetDismissAndShoppingReentry() {
        let supportedStores = makeSupportedStores()
        let firstShoppingEntry = ShoppingLocalStore(defaults: defaults, userID: userA)

        firstShoppingEntry.setPreferredRetailerIDs(["nike"], supportedStores: supportedStores)
        _ = firstShoppingEntry.normalizePreferredRetailerIDs(
            supportedStores: [],
            registryIsLoaded: false
        )

        let shoppingReentry = ShoppingLocalStore(defaults: defaults, userID: userA)
        XCTAssertEqual(
            shoppingReentry.preferredRetailerIDs(
                supportedStores: supportedStores,
                registryIsLoaded: true
            ),
            ["nike"]
        )
    }

    func testPreferredRetailerLegacyActiveUserNamespaceMigratesToPresentationNamespace() {
        let supportedStores = makeSupportedStores()
        defaults.set("guest", forKey: AccountScopedStorage.activeUserMarkerKey)
        defaults.set("guest", forKey: "customerAccountMode")
        defaults.set("stale@example.com", forKey: "customerAccountEmail")
        let legacyKey = PersonalStylistStorage.scopedKey(ShoppingLocalStore.preferredRetailerIDsBaseKey, userID: "stale@example.com")
        let presentationKey = PersonalStylistStorage.scopedKey(ShoppingLocalStore.preferredRetailerIDsBaseKey, userID: "guest")
        defaults.set(["nike", "macys"], forKey: legacyKey)

        let store = ShoppingLocalStore(defaults: defaults, supportedStores: supportedStores)

        XCTAssertEqual(store.preferredRetailerIDs, ["nike", "macys"])
        XCTAssertEqual(defaults.stringArray(forKey: presentationKey), ["nike", "macys"])
    }

    func testPreferredRetailerIDsNormalizeDuplicatesAndRemoveUnknownIDs() {
        let supportedStores = makeSupportedStores()
        let key = PersonalStylistStorage.scopedKey(ShoppingLocalStore.preferredRetailerIDsBaseKey, userID: userA)
        defaults.set(["macys", "unknown", "MACYS", " amazon ", "disabled"], forKey: key)

        let store = ShoppingLocalStore(defaults: defaults, userID: userA, supportedStores: supportedStores)

        XCTAssertEqual(store.preferredRetailerIDs, ["amazon", "macys"])
        XCTAssertEqual(defaults.stringArray(forKey: key), ["amazon", "macys"])
    }

    func testRetailerPreferencePolicyEmptyPreferencesShowAllApprovedProducts() {
        let products = [
            makeAffiliateProduct(id: "amazon", retailerID: "amazon"),
            makeAffiliateProduct(id: "macys", retailerID: "macys")
        ]

        let result = RetailerPreferencePolicy.apply(
            products: products,
            preferredRetailerIDs: [],
            supportedStores: makeSupportedStores()
        )

        XCTAssertEqual(result.products.map(\.id), ["amazon", "macys"])
        XCTAssertFalse(result.usedFallback)
        XCTAssertTrue(result.requestedRetailerIDs.isEmpty)
    }

    func testRetailerPreferencePolicyFiltersByCanonicalRetailerIDOnly() {
        let products = [
            makeAffiliateProduct(
                id: "canonical-match",
                retailer: Retailer(name: "Amazon", trackingID: "PENDING-APPROVAL", trackingParamName: "tag", disclosureName: "Amazon"),
                retailerID: "macys"
            ),
            makeAffiliateProduct(
                id: "display-name-only",
                retailer: Retailer(name: "Macy's", trackingID: "PENDING-APPROVAL", trackingParamName: "aff", disclosureName: "Macy's"),
                retailerID: nil
            ),
            makeAffiliateProduct(id: "other", retailerID: "amazon")
        ]

        let result = RetailerPreferencePolicy.apply(
            products: products,
            preferredRetailerIDs: ["macys"],
            supportedStores: makeSupportedStores()
        )

        XCTAssertEqual(result.products.map(\.id), ["canonical-match"])
        XCTAssertFalse(result.usedFallback)
    }

    func testRetailerPreferencePolicyMatchingCanonicalIDsReturnOnlyThoseRetailers() {
        let products = [
            makeAffiliateProduct(id: "nike-shoe", retailerID: "nike"),
            makeAffiliateProduct(id: "macys-shirt", retailerID: "macys"),
            makeAffiliateProduct(id: "amazon-shirt", retailerID: "amazon")
        ]

        let result = RetailerPreferencePolicy.apply(
            products: products,
            preferredRetailerIDs: ["nike", "macys"],
            supportedStores: makeSupportedStores()
        )

        XCTAssertEqual(result.products.map(\.id), ["nike-shoe", "macys-shirt"])
        XCTAssertEqual(result.requestedRetailerIDs, ["nike", "macys"])
        XCTAssertFalse(result.usedFallback)
    }

    func testRetailerPreferencePolicyZeroMatchesFailsOpen() {
        let products = [
            makeAffiliateProduct(id: "amazon", retailerID: "amazon"),
            makeAffiliateProduct(id: "legacy-without-id", retailerID: nil)
        ]

        let result = RetailerPreferencePolicy.apply(
            products: products,
            preferredRetailerIDs: ["macys"],
            supportedStores: makeSupportedStores()
        )

        XCTAssertEqual(result.products.map(\.id), ["amazon", "legacy-without-id"])
        XCTAssertTrue(result.usedFallback)
        XCTAssertEqual(result.requestedRetailerIDs, ["macys"])
    }

    func testRetailerPreferenceFallbackDoesNotAlterSavedPreferences() {
        let supportedStores = makeSupportedStores()
        let store = ShoppingLocalStore(defaults: defaults, userID: userA, supportedStores: supportedStores)
        store.setPreferredRetailerIDs(["nike", "macys"], supportedStores: supportedStores)

        let result = RetailerPreferencePolicy.apply(
            products: [makeAffiliateProduct(id: "amazon", retailerID: "amazon")],
            preferredRetailerIDs: store.preferredRetailerIDs,
            supportedStores: supportedStores
        )

        XCTAssertTrue(result.usedFallback)
        XCTAssertEqual(store.preferredRetailerIDs, ["nike", "macys"])
    }

    func testRetailerPreferenceFallbackCopyNamesSelectedStores() {
        XCTAssertEqual(
            RetailerPreferencePolicy.fallbackCopy(selectedStoreNames: ["Nike", "Macy's", "Best Buy", "Target", "Walmart"]),
            "No matching products are currently available from your selected stores. Showing recommendations from all approved retailers until more inventory becomes available. Selected stores: Nike, Macy's, Best Buy, Target, Walmart."
        )
    }

    func testZeroMatchSelectionUsesFallbackWithAlignedBanner() {
        let result = RetailerPreferencePolicy.apply(
            products: [makeAffiliateProduct(id: "amazon", retailerID: "amazon")],
            preferredRetailerIDs: ["nike"],
            supportedStores: makeSupportedStores()
        )

        XCTAssertTrue(result.usedFallback)
        XCTAssertEqual(result.products.map(\.id), ["amazon"])
        XCTAssertEqual(
            RetailerPreferencePolicy.fallbackCopy(selectedStoreNames: ["Nike"]),
            "No matching products are currently available from your selected stores. Showing recommendations from all approved retailers until more inventory becomes available. Selected stores: Nike."
        )
    }

    func testStoreCoverageStateCountsCanonicalRetailerIDsAndExcludesNil() {
        let coverage = StoreCoverageState.loaded(products: [
            makeAffiliateProduct(id: "nike-1", retailerID: "nike"),
            makeAffiliateProduct(id: "nike-2", retailerID: "NIKE"),
            makeAffiliateProduct(id: "macys", retailerID: " macys "),
            makeAffiliateProduct(id: "legacy", retailerID: nil)
        ], source: .remote)

        XCTAssertEqual(coverage.productCount(for: "nike"), 2)
        XCTAssertEqual(coverage.productCount(for: "macys"), 1)
        XCTAssertEqual(coverage.productCount(for: "amazon"), 0)
        XCTAssertEqual(coverage, .loaded(countsByRetailerID: ["nike": 2, "macys": 1], source: .remote))
    }

    func testMyStoresSelectionInvalidatesVisibleShoppingCollectionsImmediately() throws {
        let shoppingSource = try projectSource("StyleMatchAI/Shopping/ShoppingView.swift")

        XCTAssertTrue(shoppingSource.contains(".styleMatchOnChange(of: store.preferredRetailerIDs)"))
        XCTAssertTrue(shoppingSource.contains("reloadRecommendations()"))
        XCTAssertTrue(shoppingSource.contains("saleAlerts = makeSaleAlerts(from: policyCatalog)"))
        XCTAssertTrue(shoppingSource.contains("currentFavoriteSaleEvents(catalog: policyCatalog)"))
        XCTAssertTrue(shoppingSource.contains("retailerPreferenceResult.usedFallback"))
    }

    func testStoreCoverageStateDistinguishesUnavailableFromLoadedZero() {
        let unavailable = StoreCoverageState.unavailable
        let loadedEmpty = StoreCoverageState.loaded(products: [], source: .bundled)

        XCTAssertNil(unavailable.productCount(for: "nike"))
        XCTAssertEqual(loadedEmpty.productCount(for: "nike"), 0)
        XCTAssertEqual(loadedEmpty, .loaded(countsByRetailerID: [:], source: .bundled))
    }

    func testMyStoresRowsPresentCoverageLabelsWithoutBlockingSelection() throws {
        let shoppingSource = try projectSource("StyleMatchAI/Shopping/ShoppingView.swift")

        XCTAssertTrue(shoppingSource.contains("availabilityLine(for: supportedStore)"))
        XCTAssertTrue(shoppingSource.contains("Availability unknown"))
        XCTAssertTrue(shoppingSource.contains("No products available yet"))
        XCTAssertTrue(shoppingSource.contains("toggle(supportedStore)"))
        XCTAssertTrue(shoppingSource.contains("accessibilityLabel(\"\\(supportedStore.name),"))
    }

    func testShoppingObservableStoreIgnoresMalformedEncodedValuesWithoutClearingValidState() {
        let favoriteKey = PersonalStylistStorage.scopedKey(ShoppingLocalStore.savedFavoritesBaseKey, userID: userA)
        let pricesKey = PersonalStylistStorage.scopedKey(ShoppingLocalStore.latestKnownPricesBaseKey, userID: userA)

        defaults.set(["valid-favorite"], forKey: favoriteKey)
        defaults.set(Data("not-json".utf8), forKey: pricesKey)

        let store = ShoppingLocalStore(defaults: defaults, userID: userA)

        XCTAssertEqual(store.savedFavorites, ["valid-favorite"])
        XCTAssertTrue(store.latestKnownPrices.isEmpty)
    }

    func testTwoShoppingObserversCanShareOneObservableStoreInstance() {
        let sharedStore = ShoppingLocalStore(defaults: defaults, userID: userA)
        let observerA = sharedStore
        let observerB = sharedStore

        observerA.toggleFavorite(productID: "shared-product")

        XCTAssertEqual(observerB.savedFavorites, ["shared-product"])
        XCTAssertTrue(observerA === observerB)
    }

    func testShoppingProductActionRowUsesClearSupportedActionsOnly() throws {
        let source = try projectSource("StyleMatchAI/Shopping/ShoppingView.swift")

        XCTAssertTrue(source.contains("title: \"Favorite\""))
        XCTAssertTrue(source.contains("title: \"Wishlist\""))
        XCTAssertTrue(source.contains("title: \"Shop on \\(viewModel.retailerName)\""))
        XCTAssertTrue(source.contains("systemImage: \"arrow.up.forward.app\""))
        XCTAssertTrue(source.contains("openProductExternally(product)"))
        XCTAssertFalse(source.contains("title: \"Cart\""))
        XCTAssertFalse(source.contains("title: \"Card\""))
        XCTAssertFalse(source.contains("store.toggleCart(product.id)"))
        XCTAssertFalse(source.contains("store.toggleShoppingCard(product.id)"))
    }

    func testShoppingProductActionButtonsExposeHitTargetAndAccessibilityState() throws {
        let source = try projectSource("StyleMatchAI/Shopping/ShoppingView.swift")

        XCTAssertTrue(source.contains(".frame(width: 44, height: 44)"))
        XCTAssertTrue(source.contains(".contentShape(Rectangle())"))
        XCTAssertTrue(source.contains(".accessibilityLabel(title)"))
        XCTAssertTrue(source.contains(".accessibilityValue(isActive ? \"Selected\" : \"Not selected\")"))
        XCTAssertTrue(source.contains(".shoppingSelectedAccessibility(isActive)"))
    }

    func testShoppingViewUsesObservableStoreAndNoRevisionCounter() throws {
        let source = try projectSource("StyleMatchAI/Shopping/ShoppingView.swift")
        let searchSource = try projectSource("StyleMatchAI/Shopping/StoreSearchView.swift")

        XCTAssertTrue(source.contains("@StateObject private var runtime = ShoppingViewRuntime()"))
        XCTAssertTrue(source.contains("private var store: ShoppingLocalStore { runtime.store }"))
        XCTAssertTrue(source.contains("private var diagnosticContext: ShoppingDiagnosticContext { runtime.diagnosticContext }"))
        XCTAssertTrue(source.contains("diagnostics: ShoppingDiagnostics.live"))
        XCTAssertTrue(source.contains("diagnosticContext: context"))
        XCTAssertTrue(searchSource.contains("@StateObject private var localStore = ShoppingLocalStore()"))
        XCTAssertFalse(source.contains("shoppingActionRevision"))
    }

    func testShoppingPriceDropEvaluatorTriggersOnlyOnRealDecrease() {
        let store = ShoppingLocalStore(defaults: defaults, userID: userA)
        store.saleNotificationsEnabled = true
        store.setSaleAlert(enabled: true, for: "watched")
        store.updateLatestKnownPrice(Decimal(100), for: "watched")

        let product = makeAffiliateProduct(id: "watched", price: Decimal(80), salePrice: nil)
        let events = ShoppingPriceDropEvaluator(now: { self.fixedDate(year: 2026, month: 7, day: 14) }).evaluate(catalog: [product], store: store)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.productID, "watched")
        XCTAssertEqual(events.first?.previousPrice, Decimal(100))
        XCTAssertEqual(events.first?.currentPrice, Decimal(80))
    }

    func testShoppingPriceDropEvaluatorDoesNotTriggerOnEqualIncreasedOrDisabled() {
        let equalStore = ShoppingLocalStore(defaults: defaults, userID: userA)
        equalStore.saleNotificationsEnabled = true
        equalStore.setSaleAlert(enabled: true, for: "equal")
        equalStore.updateLatestKnownPrice(Decimal(80), for: "equal")
        XCTAssertTrue(
            ShoppingPriceDropEvaluator().evaluate(catalog: [makeAffiliateProduct(id: "equal", price: Decimal(80))], store: equalStore).isEmpty
        )

        let increasedStore = ShoppingLocalStore(defaults: defaults, userID: userB)
        increasedStore.saleNotificationsEnabled = true
        increasedStore.setSaleAlert(enabled: true, for: "increased")
        increasedStore.updateLatestKnownPrice(Decimal(80), for: "increased")
        XCTAssertTrue(
            ShoppingPriceDropEvaluator().evaluate(catalog: [makeAffiliateProduct(id: "increased", price: Decimal(90))], store: increasedStore).isEmpty
        )

        let disabledStore = ShoppingLocalStore(defaults: defaults, userID: "disabled")
        disabledStore.saleNotificationsEnabled = false
        disabledStore.setSaleAlert(enabled: true, for: "disabled")
        disabledStore.updateLatestKnownPrice(Decimal(100), for: "disabled")
        XCTAssertTrue(
            ShoppingPriceDropEvaluator().evaluate(catalog: [makeAffiliateProduct(id: "disabled", price: Decimal(80))], store: disabledStore).isEmpty
        )
    }

    func testShoppingPriceDropEvaluatorDoesNotNotifySamePriceDropTwice() {
        let store = ShoppingLocalStore(defaults: defaults, userID: userA)
        store.saleNotificationsEnabled = true
        store.setSaleAlert(enabled: true, for: "watched")
        store.updateLatestKnownPrice(Decimal(100), for: "watched")

        let product = makeAffiliateProduct(id: "watched", price: Decimal(80))
        let evaluator = ShoppingPriceDropEvaluator()

        XCTAssertEqual(evaluator.evaluate(catalog: [product], store: store).count, 1)
        store.updateLatestKnownPrice(Decimal(100), for: "watched")
        XCTAssertTrue(evaluator.evaluate(catalog: [product], store: store).isEmpty)
    }

    func testShoppingSaleAlertsExplainFavoriteWishlistCartAndShoppingCardDeals() {
        let saleEnds = fixedDate(year: 2026, month: 7, day: 10)
        let favorite = makeAffiliateProduct(id: "favorite", name: "Nike Jacket", subcategory: "jacket", colors: ["black"], price: Decimal(100), salePrice: Decimal(75), saleEndsAt: saleEnds, brand: "Nike")
        let wishlist = makeAffiliateProduct(id: "wishlist", name: "White Shirt", subcategory: "shirt", colors: ["white"], price: Decimal(80), salePrice: Decimal(60), saleEndsAt: saleEnds)
        let cart = makeAffiliateProduct(id: "cart", name: "Court Sneaker", category: .shoes, subcategory: "sneakers", colors: ["white"], price: Decimal(120), salePrice: Decimal(90), saleEndsAt: saleEnds)
        let card = makeAffiliateProduct(id: "card", name: "Leather Belt", category: .accessories, subcategory: "belt", colors: ["black"], price: Decimal(50), salePrice: Decimal(35), saleEndsAt: saleEnds)

        let alerts = ShoppingSaleAlertService.alerts(
            catalog: [favorite, wishlist, cart, card],
            context: ShoppingSaleAlertContext(
                favoriteProductIDs: ["favorite"],
                wishlistProductIDs: ["wishlist"],
                cartProductIDs: ["cart"],
                shoppingCardProductIDs: ["card"],
                now: fixedDate(year: 2026, month: 7, day: 7)
            )
        )

        XCTAssertEqual(alerts.first?.trigger, .cartPriceDrop)
        XCTAssertTrue(alerts.contains { $0.trigger == .favoriteSale && $0.message.contains("25% off") && $0.message.contains("Favorites") })
        XCTAssertTrue(alerts.contains { $0.trigger == .wishlistSale && $0.message.localizedCaseInsensitiveContains("wishlist") })
        XCTAssertTrue(alerts.contains { $0.trigger == .cartPriceDrop && $0.message.localizedCaseInsensitiveContains("cart") })
        XCTAssertTrue(alerts.contains { $0.trigger == .shoppingCardSale && $0.message.localizedCaseInsensitiveContains("shopping card") })
    }

    func testShoppingSaleAlertsMatchSavedStyleAndPastOutfitsWithoutFabrication() {
        var memory = makeBlackPantsAndShirtMemory()
        memory.scanDate = fixedDate(year: 2026, month: 7, day: 1)
        let savedBlueShirt = makeAffiliateProduct(id: "saved", name: "Blue Oxford", subcategory: "shirt", colors: ["blue"], brand: "Macy's")
        let blueSale = makeAffiliateProduct(id: "blue-sale", name: "Blue Shirt", subcategory: "shirt", colors: ["blue"], price: Decimal(90), salePrice: Decimal(70), saleEndsAt: fixedDate(year: 2026, month: 7, day: 12), brand: "Macy's")
        let whiteSale = makeAffiliateProduct(id: "white-sale", name: "White Shirt", subcategory: "shirt", colors: ["white"], price: Decimal(80), salePrice: Decimal(60), saleEndsAt: fixedDate(year: 2026, month: 7, day: 12))

        let alerts = ShoppingSaleAlertService.alerts(
            catalog: [blueSale, whiteSale],
            context: ShoppingSaleAlertContext(
                savedStyleProducts: [savedBlueShirt],
                memories: [memory],
                now: fixedDate(year: 2026, month: 7, day: 7)
            )
        )

        XCTAssertTrue(alerts.contains { $0.trigger == .savedStyleSale && $0.productID == "blue-sale" && $0.message.localizedCaseInsensitiveContains("saved style") })
        XCTAssertTrue(alerts.contains { $0.trigger == .pastOutfitMatchSale && $0.productID == "white-sale" && $0.message.contains("black pants and black shirt") })
    }

    func testShoppingSaleNotificationsRequireSaleStateChange() {
        let now = fixedDate(year: 2026, month: 7, day: 7)
        let becameSale = makeAffiliateProduct(id: "became-sale", name: "Favorite Shirt", price: Decimal(80), salePrice: Decimal(60), saleEndsAt: fixedDate(year: 2026, month: 7, day: 12))
        let unchangedSale = makeAffiliateProduct(id: "unchanged", name: "Unchanged Shirt", price: Decimal(80), salePrice: Decimal(50), saleEndsAt: fixedDate(year: 2026, month: 7, day: 12))

        let previous = [
            "became-sale": ShoppingSaleStateSnapshot(productID: "became-sale", salePrice: nil, saleEndsAt: nil, isActiveSale: false),
            "unchanged": ShoppingSaleStateSnapshot(productID: "unchanged", salePrice: Decimal(50), saleEndsAt: fixedDate(year: 2026, month: 7, day: 12), isActiveSale: true)
        ]

        let alerts = ShoppingSaleAlertService.notificationAlerts(
            catalog: [becameSale, unchangedSale],
            context: ShoppingSaleAlertContext(
                favoriteProductIDs: ["became-sale", "unchanged"],
                now: now
            ),
            previousSnapshots: previous
        )

        XCTAssertEqual(alerts.map(\.productID), ["became-sale"])
        XCTAssertTrue(alerts.first?.message.contains("Favorite Shirt") == true)
    }

    func testSaleWatcherDiffFiresForNewSaleAndPriceDropOnly() {
        let store = ShoppingLocalStore(defaults: defaults, userID: userA)
        store.saleNotificationsEnabled = true
        store.savedFavorites = ["new-sale", "same-sale", "drop-sale", "expired"]
        let now = fixedDate(year: 2026, month: 7, day: 7)
        store.lastKnownSaleState = [
            "new-sale": SaleSnapshot(salePrice: nil, saleEndsAt: nil, timestamp: now),
            "same-sale": SaleSnapshot(salePrice: Decimal(50), saleEndsAt: fixedDate(year: 2026, month: 7, day: 12), timestamp: now),
            "drop-sale": SaleSnapshot(salePrice: Decimal(70), saleEndsAt: fixedDate(year: 2026, month: 7, day: 12), timestamp: now),
            "expired": SaleSnapshot(salePrice: nil, saleEndsAt: nil, timestamp: now)
        ]

        let watcher = SaleWatcher(
            catalogProvider: StaticProductCatalogProvider(products: []),
            localStore: store,
            notificationScheduler: nil,
            now: { now }
        )
        let events = watcher.process(catalog: [
            makeAffiliateProduct(id: "new-sale", price: Decimal(80), salePrice: Decimal(60), saleEndsAt: fixedDate(year: 2026, month: 7, day: 12)),
            makeAffiliateProduct(id: "same-sale", price: Decimal(80), salePrice: Decimal(50), saleEndsAt: fixedDate(year: 2026, month: 7, day: 12)),
            makeAffiliateProduct(id: "drop-sale", price: Decimal(80), salePrice: Decimal(60), saleEndsAt: fixedDate(year: 2026, month: 7, day: 12)),
            makeAffiliateProduct(id: "expired", price: Decimal(80), salePrice: Decimal(40), saleEndsAt: fixedDate(year: 2026, month: 1, day: 1))
        ], now: now)

        XCTAssertEqual(Set(events.map(\.productID)), ["drop-sale", "new-sale"])
    }

    func testSaleWatcherDedupsSameProductAndSalePriceAcrossRuns() {
        let store = ShoppingLocalStore(defaults: defaults, userID: userA)
        store.saleNotificationsEnabled = true
        store.savedFavorites = ["shirt"]
        let now = fixedDate(year: 2026, month: 7, day: 7)
        store.lastKnownSaleState = ["shirt": SaleSnapshot(salePrice: nil, saleEndsAt: nil, timestamp: now)]
        let product = makeAffiliateProduct(id: "shirt", price: Decimal(80), salePrice: Decimal(60), saleEndsAt: fixedDate(year: 2026, month: 7, day: 12))
        let watcher = SaleWatcher(catalogProvider: StaticProductCatalogProvider(products: []), localStore: store, notificationScheduler: nil, now: { now })

        XCTAssertEqual(watcher.process(catalog: [product], now: now).count, 1)
        store.lastKnownSaleState = ["shirt": SaleSnapshot(salePrice: nil, saleEndsAt: nil, timestamp: now)]
        XCTAssertTrue(watcher.process(catalog: [product], now: now).isEmpty)
    }

    func testSaleWatcherKeepsSaleEventsInAppWithoutEnablingNotifications() {
        let store = ShoppingLocalStore(defaults: defaults, userID: userA)
        store.saleNotificationsEnabled = true
        store.savedFavorites = ["favorite-1", "favorite-2", "favorite-3"]
        let now = fixedDate(year: 2026, month: 7, day: 7)
        store.lastKnownSaleState = Dictionary(uniqueKeysWithValues: ["favorite-1", "favorite-2", "favorite-3", "similar"].map {
            ($0, SaleSnapshot(salePrice: nil, saleEndsAt: nil, timestamp: now))
        })
        let products = [
            makeAffiliateProduct(id: "favorite-1", name: "Favorite One", subcategory: "shirt", colors: ["blue"], price: Decimal(80), salePrice: Decimal(60), saleEndsAt: fixedDate(year: 2026, month: 7, day: 12)),
            makeAffiliateProduct(id: "favorite-2", name: "Favorite Two", subcategory: "shirt", colors: ["black"], price: Decimal(80), salePrice: Decimal(60), saleEndsAt: fixedDate(year: 2026, month: 7, day: 12)),
            makeAffiliateProduct(id: "favorite-3", name: "Favorite Three", subcategory: "shirt", colors: ["white"], price: Decimal(80), salePrice: Decimal(60), saleEndsAt: fixedDate(year: 2026, month: 7, day: 12)),
            makeAffiliateProduct(id: "similar", name: "Similar Shirt", subcategory: "shirt", colors: ["blue"], price: Decimal(80), salePrice: Decimal(55), saleEndsAt: fixedDate(year: 2026, month: 7, day: 12))
        ]

        let events = SaleWatcher(catalogProvider: StaticProductCatalogProvider(products: []), localStore: store, notificationScheduler: nil, now: { now }).process(catalog: products, now: now)

        XCTAssertFalse(SaleWatcher.notificationsAvailable)
        XCTAssertTrue(events.allSatisfy { !$0.shouldNotify })
        XCTAssertTrue(events.contains { $0.reason == .directFavorite })
        XCTAssertTrue(events.contains { $0.reason == .similarToFavorite })
    }

    func testSaleWatcherCapsWeeklyNotifications() {
        let store = ShoppingLocalStore(defaults: defaults, userID: userA)
        store.saleNotificationsEnabled = true
        store.savedFavorites = ["shirt"]
        let now = fixedDate(year: 2026, month: 7, day: 7)
        store.saleNotificationHistory = (1...5).map { now.addingTimeInterval(TimeInterval(-$0 * 24 * 60 * 60)) }
        store.lastKnownSaleState = ["shirt": SaleSnapshot(salePrice: nil, saleEndsAt: nil, timestamp: now)]

        let events = SaleWatcher(catalogProvider: StaticProductCatalogProvider(products: []), localStore: store, notificationScheduler: nil, now: { now }).process(
            catalog: [makeAffiliateProduct(id: "shirt", price: Decimal(80), salePrice: Decimal(60), saleEndsAt: fixedDate(year: 2026, month: 7, day: 12))],
            now: now
        )

        XCTAssertEqual(events.count, 1)
        XCTAssertFalse(events[0].shouldNotify)
    }

    func testSaleWatcherAmazonNotificationTemplateContainsNoPrices() {
        let event = SaleEvent(
            id: "amazon",
            productID: "amazon",
            productName: "Amazon Jacket",
            retailerName: "Amazon",
            subcategory: "jacket",
            salePrice: Decimal(40),
            originalPrice: Decimal(100),
            saleEndsAt: nil,
            reason: .directFavorite,
            occurredAt: Date(),
            shouldNotify: true,
            scheduledDeliveryDate: nil
        )

        let content = SaleWatcher.notificationTitleAndBody(for: event, retailerName: "Amazon")

        XCTAssertFalse(content.body.contains("$"))
        XCTAssertFalse(content.body.contains("40"))
        XCTAssertFalse(content.body.contains("100"))
        XCTAssertTrue(content.body.localizedCaseInsensitiveContains("Amazon"))
    }

    func testSaleWatcherNeverSchedulesWhenNotificationsAreUnavailable() async {
        let store = ShoppingLocalStore(defaults: defaults, userID: userA)
        store.saleNotificationsEnabled = true
        store.savedFavorites = ["shirt"]
        let now = fixedDate(year: 2026, month: 7, day: 7, hour: 23)
        store.lastKnownSaleState = ["shirt": SaleSnapshot(salePrice: nil, saleEndsAt: nil, timestamp: now)]
        let spy = SpySaleNotificationScheduler()

        _ = await SaleWatcher(
            catalogProvider: StaticProductCatalogProvider(products: [
                makeAffiliateProduct(id: "shirt", price: Decimal(80), salePrice: Decimal(60), saleEndsAt: fixedDate(year: 2026, month: 7, day: 12))
            ]),
            localStore: store,
            notificationScheduler: spy,
            now: { now }
        ).checkForNewSales()

        XCTAssertTrue(spy.requests.isEmpty)
    }

    func testSaleWatcherHasNoReleaseNotificationPermissionEntryPoint() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("StyleMatchAI/Shopping/SaleWatcher.swift")
        let source = try String(contentsOf: sourceURL)
        XCTAssertFalse(source.contains("UNUserNotificationCenter"))
        XCTAssertFalse(source.contains("requestAuthorization(options:"))
        XCTAssertFalse(source.contains("BGTaskScheduler"))
        XCTAssertFalse(source.contains("SaleWatcherBackgroundRefresh"))
    }

    func testSaleWatcherDisabledNotificationsProduceZeroNotificationRequests() async {
        let store = ShoppingLocalStore(defaults: defaults, userID: userA)
        store.saleNotificationsEnabled = false
        store.savedFavorites = ["shirt"]
        let now = fixedDate(year: 2026, month: 7, day: 7)
        store.lastKnownSaleState = ["shirt": SaleSnapshot(salePrice: nil, saleEndsAt: nil, timestamp: now)]
        let spy = SpySaleNotificationScheduler()

        let events = await SaleWatcher(
            catalogProvider: StaticProductCatalogProvider(products: [
                makeAffiliateProduct(id: "shirt", price: Decimal(80), salePrice: Decimal(60), saleEndsAt: fixedDate(year: 2026, month: 7, day: 12))
            ]),
            localStore: store,
            notificationScheduler: spy,
            now: { now }
        ).checkForNewSales()

        XCTAssertEqual(events.count, 1)
        XCTAssertFalse(events[0].shouldNotify)
        XCTAssertTrue(spy.requests.isEmpty)
    }

    func testSaleWatcherStoresAreClearedByPrivacyDeletion() {
        let store = ShoppingLocalStore(defaults: defaults, userID: userA)
        store.lastKnownSaleState = ["shirt": SaleSnapshot(salePrice: Decimal(60), saleEndsAt: nil, timestamp: Date())]
        store.notifiedSalePairs = ["shirt|60"]
        store.saleNotificationHistory = [Date()]
        store.recentSaleEvents = [
            SaleEvent(id: "event", productID: "shirt", productName: "Shirt", retailerName: "Macy's", subcategory: "shirt", salePrice: Decimal(60), originalPrice: Decimal(80), saleEndsAt: nil, reason: .directFavorite, occurredAt: Date(), shouldNotify: false, scheduledDeliveryDate: nil)
        ]
        store.viewedSaleEventIDs = ["event"]

        store.deleteAll()
        let cleared = ShoppingLocalStore(defaults: defaults, userID: userA)

        XCTAssertTrue(cleared.lastKnownSaleState.isEmpty)
        XCTAssertTrue(cleared.notifiedSalePairs.isEmpty)
        XCTAssertTrue(cleared.saleNotificationHistory.isEmpty)
        XCTAssertTrue(cleared.recentSaleEvents.isEmpty)
        XCTAssertTrue(cleared.viewedSaleEventIDs.isEmpty)
    }

    func testShoppingSaleNotificationsDoNotFireWithoutPriorSnapshot() {
        let sale = makeAffiliateProduct(id: "sale", name: "Favorite Shirt", price: Decimal(80), salePrice: Decimal(60), saleEndsAt: fixedDate(year: 2026, month: 7, day: 12))

        let alerts = ShoppingSaleAlertService.notificationAlerts(
            catalog: [sale],
            context: ShoppingSaleAlertContext(
                favoriteProductIDs: ["sale"],
                now: fixedDate(year: 2026, month: 7, day: 7)
            ),
            previousSnapshots: [:]
        )

        XCTAssertTrue(alerts.isEmpty)
    }

    func testShoppingSaleIndicatorsSkipExpiredAndRegularProducts() {
        let expired = makeAffiliateProduct(id: "expired", name: "Expired Shirt", price: Decimal(80), salePrice: Decimal(40), saleEndsAt: fixedDate(year: 2026, month: 1, day: 1))
        let regular = makeAffiliateProduct(id: "regular", name: "Regular Shirt", price: Decimal(80), salePrice: nil)

        let alerts = ShoppingSaleAlertService.alerts(
            catalog: [expired, regular],
            context: ShoppingSaleAlertContext(
                favoriteProductIDs: ["expired", "regular"],
                now: fixedDate(year: 2026, month: 7, day: 7)
            )
        )

        XCTAssertTrue(alerts.isEmpty)
    }

    func testShoppingSaleAlertsGroupMultipleUpdatesIntoSections() {
        let favorite = ShoppingSaleAlert(
            id: "favorite",
            productID: "favorite",
            productName: "Favorite Shirt",
            retailerName: "Macy's",
            trigger: .favoriteSale,
            title: "Shopping deal",
            message: "Favorite sale",
            discountPercent: 20,
            salePrice: Decimal(40),
            originalPrice: Decimal(50),
            saleEndsAt: nil
        )
        let style = ShoppingSaleAlert(
            id: "style",
            productID: "style",
            productName: "Style Shirt",
            retailerName: "Macy's",
            trigger: .pastOutfitMatchSale,
            title: "Matches a past outfit",
            message: "Style sale",
            discountPercent: 20,
            salePrice: Decimal(40),
            originalPrice: Decimal(50),
            saleEndsAt: nil
        )

        let sections = ShoppingSaleAlertService.groupedSections(from: [favorite, style])

        XCTAssertEqual(sections.map(\.title), ["Saved & Cart Deals", "Matches Your Style"])
    }

    func testShoppingRankingRecentOutfitComplementWeatherPenaltyAndDismissedSink() {
        var memory = makeBlackPantsAndShirtMemory()
        memory.scanDate = fixedDate(year: 2026, month: 7, day: 1)
        let whiteShirt = makeAffiliateProduct(id: "white-shirt", name: "White Shirt", category: .clothing, subcategory: "shirt", colors: ["white"])
        let coat = makeAffiliateProduct(id: "coat", name: "Wool Coat", category: .clothing, subcategory: "coat", colors: ["camel"], tags: ["heavy", "wool"])
        let dismissed = makeAffiliateProduct(id: "dismissed", name: "Black Belt", category: .accessories, subcategory: "belt", colors: ["black"])

        let ranked = ShoppingRecommendationEngine.rank(
            results: [coat, dismissed, whiteShirt],
            against: ShoppingRankingContext(
                memories: [memory],
                weather: ShoppingWeatherContext(feelsLikeTemperature: 91, rainChancePercent: nil, uvIndex: nil, condition: "Hot"),
                dismissedProductIDs: ["dismissed"],
                now: fixedDate(year: 2026, month: 7, day: 7)
            )
        )

        XCTAssertEqual(ranked.first?.product.id, "white-shirt")
        XCTAssertEqual(ranked.first?.reasonFacts?.rule, "complement")
        XCTAssertTrue(ranked.first?.reasonFacts?.oneLineReason.contains("black pants and black shirt") == true)
        XCTAssertTrue(ranked.first?.reasonFacts?.explanationBullets.contains("Matches your wardrobe") == true)
        XCTAssertEqual(ranked.last?.product.id, "dismissed")
        XCTAssertLessThan(ranked.first(where: { $0.product.id == "coat" })?.rank ?? 0, ranked.first?.rank ?? 0)
    }

    func testShoppingSearchExcludesAmazonWhenPriceFilterRequiresStoredPriceDisplay() {
        let amazon = makeAffiliateProduct(
            id: "amazon-priced",
            name: "Amazon Style Tool",
            category: .styleTools,
            subcategory: "steamer",
            colors: ["white"],
            retailer: Retailer(name: "Amazon", trackingID: "amazon-20", trackingParamName: "tag", disclosureName: "Amazon"),
            price: Decimal(30),
            tags: ["travel"]
        )
        var criteria = ShoppingSearchCriteria()
        criteria.maximumPrice = Decimal(40)

        let result = ShoppingSearchEngine.relaxedFilter(products: [amazon], criteria: criteria)

        XCTAssertTrue(result.exactResults.isEmpty)
        XCTAssertEqual(result.relaxedFilter, .maxPrice)
        XCTAssertEqual(result.displayedResults.map(\.id), ["amazon-priced"])
    }

    func testStoreSearchFindsSupportedStoresByNameDomainAndCategory() {
        let stores = [
            SupportedStore(id: "nike", name: "Nike", domains: ["nike.com"], categories: [.shoes], affiliateNetwork: "TBD", apiStatus: "affiliate-placeholder", isEnabled: true),
            SupportedStore(id: "ulta", name: "Ulta", domains: ["ulta.com"], categories: [.styleTools], affiliateNetwork: "TBD", apiStatus: "needs-approved-feed", isEnabled: true),
            SupportedStore(id: "disabled", name: "Disabled", domains: ["disabled.example"], categories: [.clothing], affiliateNetwork: nil, apiStatus: "disabled", isEnabled: false)
        ]

        XCTAssertEqual(ShoppingSearchEngine.filterStores(stores, query: "ulta").map(\.name), ["Ulta"])
        XCTAssertEqual(ShoppingSearchEngine.filterStores(stores, query: "shoes").map(\.name), ["Nike"])
        XCTAssertFalse(ShoppingSearchEngine.filterStores(stores, query: "").contains { $0.name == "Disabled" })
    }

    func testAllStoresDirectoryIncludesEnabledZeroProductRetailers() {
        let stores = makeSupportedStores()
        let catalog = (0..<12).map { directoryProduct(id: "amazon-\($0)", retailerID: "amazon", retailerName: "Amazon") }

        let directory = RetailerDirectoryPolicy.availabilities(
            supportedStores: stores,
            coverage: .loaded(products: catalog, source: .remote)
        )

        XCTAssertEqual(directory.map(\.id), ["amazon", "macys", "nike"])
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: directory.map { ($0.id, $0.productCount) }), ["nike": 0, "amazon": 12, "macys": 0])
        XCTAssertEqual(directory.first { $0.id == "amazon" }?.integrationStatus, .integratedCatalog)
        XCTAssertEqual(directory.first { $0.id == "nike" }?.integrationStatus, .directAccessOnly)
        XCTAssertFalse(directory.contains { $0.id == "disabled" })
    }

    func testRetailerDirectoryJoinsCountsByCanonicalIDNotDisplayName() {
        let stores = [
            SupportedStore(id: "amazon", name: "Renamed Store", domains: ["amazon.com"], categories: [.clothing], affiliateNetwork: nil, apiStatus: "approved", isEnabled: true)
        ]
        let catalog = [directoryProduct(id: "one", retailerID: "amazon", retailerName: "Different Display Name")]

        let directory = RetailerDirectoryPolicy.availabilities(
            supportedStores: stores,
            coverage: .loaded(products: catalog, source: .remote)
        )

        XCTAssertEqual(directory.first?.productCount, 1)
    }

    func testRetailerDirectorySearchFindsZeroProductStoreByNameAndDomain() {
        let stores = makeSupportedStores()

        XCTAssertEqual(
            RetailerDirectoryPolicy.availabilities(supportedStores: stores, coverage: .loaded(products: [], source: .remote), query: "Nike").map(\.id),
            ["nike"]
        )
        XCTAssertEqual(
            RetailerDirectoryPolicy.availabilities(supportedStores: stores, coverage: .loaded(products: [], source: .remote), query: "macys.com").map(\.id),
            ["macys"]
        )
    }

    func testMyStoresDirectoryScopeDoesNotMutateOrAutoSelectRetailers() {
        let stores = makeSupportedStores()
        let requested = ["nike", "macys"]

        let myStores = RetailerDirectoryPolicy.availabilities(
            supportedStores: stores,
            coverage: .loaded(products: [directoryProduct(id: "amazon", retailerID: "amazon", retailerName: "Amazon")], source: .remote),
            retailerIDs: requested
        )
        let allStores = RetailerDirectoryPolicy.availabilities(
            supportedStores: stores,
            coverage: .loaded(products: [], source: .remote)
        )

        XCTAssertEqual(myStores.map(\.id), ["macys", "nike"])
        XCTAssertEqual(allStores.map(\.id), ["amazon", "macys", "nike"])
        XCTAssertEqual(requested, ["nike", "macys"])
    }

    func testRetailerDirectoryCoverageVocabularyAndDeterministicOrdering() {
        let stores = makeSupportedStores()
        let amazonProducts = (0..<2).map { directoryProduct(id: "amazon-\($0)", retailerID: "amazon", retailerName: "Amazon") }
        let loaded = RetailerDirectoryPolicy.availabilities(
            supportedStores: stores,
            coverage: .loaded(products: amazonProducts, source: .remote)
        )
        let unavailable = RetailerDirectoryPolicy.availabilities(
            supportedStores: stores,
            coverage: .unavailable
        )

        XCTAssertEqual(loaded.map(\.id), ["amazon", "macys", "nike"])
        XCTAssertEqual(loaded.map(\.coverageLabel), ["2 products", "No products available yet", "No products available yet"])
        XCTAssertTrue(unavailable.allSatisfy { $0.coverageLabel == "Availability unknown" })
        XCTAssertEqual(unavailable.map(\.id), ["amazon", "macys", "nike"])
    }

    func testShoppingNavigationSeparatesProductsAndStoresWithoutCrossBleed() throws {
        let source = try projectSource("StyleMatchAI/Shopping/ShoppingView.swift")
        let bodyStart = try XCTUnwrap(source.range(of: "var body: some View"))
        let loadingStart = try XCTUnwrap(source.range(of: "private var shoppingLoadingShell", range: bodyStart.upperBound..<source.endIndex))
        let bodyBlock = String(source[bodyStart.lowerBound..<loadingStart.lowerBound])

        XCTAssertTrue(source.contains("private enum ShoppingPrimaryDestination"))
        XCTAssertTrue(source.contains("@State private var primaryDestination: ShoppingPrimaryDestination = .products"))
        XCTAssertFalse(source.contains("@AppStorage(\"shoppingPrimaryDestination\")"))
        XCTAssertTrue(bodyBlock.contains("if primaryDestination == .stores"))
        XCTAssertTrue(bodyBlock.contains("storesDestination"))
        XCTAssertTrue(bodyBlock.contains("shoppingConcierge"))
        XCTAssertFalse(bodyBlock.contains("retailerDirectorySection\n                        shoppingConcierge"))
        XCTAssertTrue(source.contains("case .browse: return \"Browse\""))
        XCTAssertTrue(source.contains("case .deck: return \"Swipe\""))
        XCTAssertFalse(source.contains("case .deck: return \"Deck\""))
        XCTAssertEqual(source.components(separatedBy: "Picker(\"Shopping destination\"").count - 1, 1)
    }

    func testStoreDirectoryHasOneDedicatedHomeAndNoProductFeedMount() throws {
        let searchSource = try projectSource("StyleMatchAI/Shopping/StoreSearchView.swift")
        let shoppingSource = try projectSource("StyleMatchAI/Shopping/ShoppingView.swift")
        let storesStart = try XCTUnwrap(shoppingSource.range(of: "private var storesDestination"))
        let storesEnd = try XCTUnwrap(shoppingSource.range(of: "private var shoppingLoadingShell", range: storesStart.upperBound..<shoppingSource.endIndex))
        let storesBlock = String(shoppingSource[storesStart.lowerBound..<storesEnd.lowerBound])

        XCTAssertFalse(searchSource.contains("retailerDirectorySection"))
        XCTAssertTrue(storesBlock.contains("retailerDirectorySection"))
        XCTAssertFalse(storesBlock.contains("stylistFeedCard"))
        XCTAssertFalse(storesBlock.contains("productCard("))
        XCTAssertFalse(storesBlock.contains("completeLookPreview"))
        XCTAssertFalse(storesBlock.contains("Catalog Picks"))
    }

    func testStoreDirectoryUsesCompactRowsAndOneSectionDisclosure() throws {
        let source = try projectSource("StyleMatchAI/Shopping/ShoppingView.swift")
        let disclosure = "Direct store access. KigoStylist does not claim catalog integrations or affiliate relationships for these stores."

        XCTAssertTrue(source.contains("private func retailerDirectoryRow"))
        XCTAssertTrue(source.contains(".frame(minHeight: 56)"))
        XCTAssertFalse(source.contains("private func retailerDirectoryCard"))
        XCTAssertEqual(source.components(separatedBy: disclosure).count - 1, 1)
        XCTAssertFalse(source.contains("Text(retailer.id)"))
        XCTAssertTrue(source.contains("ForEach(visibleRetailerDirectory)"))
        XCTAssertFalse(source.contains("collapsedDirectoryLimit"))
        XCTAssertFalse(source.contains("showsAllDirectoryStores"))
    }

    func testStoreDirectoryAccessibilityContractIsPresent() throws {
        let source = try projectSource("StyleMatchAI/Shopping/ShoppingView.swift")

        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"shopping.primary-destination\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"shopping.store-search\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"shopping.store-scope\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"shopping.manage-stores\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"shopping.store-row.\\(retailer.id)\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"shopping.store-action.\\(retailer.id)\")"))
        XCTAssertTrue(source.contains(".accessibilityValue(availability.coverageLabel)"))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"Open \\(retailer.name)\")"))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"View \\(retailer.name) products\")"))
    }

    func testStoresScopeAndDirectoryActionsDoNotMutatePreferences() throws {
        let source = try projectSource("StyleMatchAI/Shopping/ShoppingView.swift")
        let start = try XCTUnwrap(source.range(of: "private var storesDestination"))
        let end = try XCTUnwrap(source.range(of: "private var rawBaseSearchProducts", range: start.upperBound..<source.endIndex))
        let block = String(source[start.lowerBound..<end.lowerBound])

        XCTAssertTrue(block.contains("Picker(\"Store scope\", selection: $directoryStoreScope)"))
        XCTAssertTrue(block.contains("Label(\"Manage My Stores\", systemImage: \"storefront\")"))
        XCTAssertFalse(block.contains("setPreferredRetailerIDs"))
        XCTAssertFalse(block.contains("preferredRetailerIDs ="))
        XCTAssertTrue(block.contains("retailerIDs: directoryStoreScope == .myStores ? activeDirectoryRetailerIDs : nil"))
        XCTAssertTrue(block.contains("searchCriteria.storeName = retailer.name"))
        XCTAssertTrue(block.contains("primaryDestination = .products"))
    }

    func testNikeMacysAndBestBuySelectionsRemainDistinctFromAmazonSoftFallback() {
        let stores = [
            SupportedStore(id: "amazon", name: "Amazon", domains: ["amazon.com"], categories: [.clothing], affiliateNetwork: nil, apiStatus: "approved", isEnabled: true),
            SupportedStore(id: "nike", name: "Nike", domains: ["nike.com"], categories: [.shoes], affiliateNetwork: nil, apiStatus: "direct", isEnabled: true),
            SupportedStore(id: "macys", name: "Macy's", domains: ["macys.com"], categories: [.clothing], affiliateNetwork: nil, apiStatus: "direct", isEnabled: true),
            SupportedStore(id: "best-buy", name: "Best Buy", domains: ["bestbuy.com"], categories: [.electronics], affiliateNetwork: nil, apiStatus: "direct", isEnabled: true)
        ]
        let amazonCatalog = [directoryProduct(id: "amazon-one", retailerID: "amazon", retailerName: "Amazon")]

        for selectedID in ["nike", "macys", "best-buy"] {
            let result = RetailerPreferencePolicy.apply(
                products: amazonCatalog,
                preferredRetailerIDs: [selectedID],
                supportedStores: stores
            )

            XCTAssertEqual(result.requestedRetailerIDs, [selectedID])
            XCTAssertTrue(result.usedFallback)
            XCTAssertEqual(result.products.map(\.retailerID), ["amazon"])
            XCTAssertFalse(result.products.contains { $0.retailerID == selectedID })
        }
    }

    func testDestinationRoundTripKeepsBrowseSwipeAndFilterStateViewLocal() throws {
        let source = try projectSource("StyleMatchAI/Shopping/ShoppingView.swift")
        let pickerStart = try XCTUnwrap(source.range(of: "private var primaryDestinationPicker"))
        let storesStart = try XCTUnwrap(source.range(of: "private var storesDestination", range: pickerStart.upperBound..<source.endIndex))
        let destinationBlock = String(source[pickerStart.lowerBound..<storesStart.lowerBound])

        XCTAssertTrue(source.contains("@State private var browseMode: ShoppingBrowseMode = .browse"))
        XCTAssertTrue(source.contains("@State private var storeScope: ShoppingStoreScope = .myStores"))
        XCTAssertTrue(source.contains("@State private var searchCriteria = ShoppingSearchCriteria()"))
        XCTAssertTrue(source.contains("@State private var deckSelectionProductID: String?"))
        XCTAssertFalse(destinationBlock.contains("browseMode ="))
        XCTAssertFalse(destinationBlock.contains("storeScope ="))
        XCTAssertFalse(destinationBlock.contains("searchCriteria ="))
        XCTAssertFalse(destinationBlock.contains("deckIndex ="))
    }

    func testSwipeRestorationUsesStableProductIdentityAndRejectsStaleIdentity() throws {
        let source = try projectSource("StyleMatchAI/Shopping/ShoppingView.swift")
        let normalizeStart = try XCTUnwrap(source.range(of: "private func normalizeDeckIndex()"))
        let normalizeEnd = try XCTUnwrap(source.range(of: "private func deckPriceText", range: normalizeStart.upperBound..<source.endIndex))
        let normalizeBlock = String(source[normalizeStart.lowerBound..<normalizeEnd.lowerBound])

        XCTAssertTrue(normalizeBlock.contains("currentProductIDs.firstIndex(of: deckSelectionProductID)"))
        XCTAssertTrue(normalizeBlock.contains("deckIndex = restoredIndex"))
        XCTAssertTrue(normalizeBlock.contains("deckIndex = min(max(0, deckIndex), currentProductIDs.count)"))
        XCTAssertTrue(normalizeBlock.contains("deckSelectionProductID = deckIndex < currentProductIDs.count ? currentProductIDs[deckIndex] : nil"))
        XCTAssertTrue(source.contains("deckSelectionProductID = deck.currentProductID"))
        XCTAssertFalse(normalizeBlock.contains("products[deckIndex]"))
    }

    func testDirectoryOpenMountUsesValidatedOpenerAndNoRawUIApplicationOpen() throws {
        let source = try projectSource("StyleMatchAI/Shopping/ShoppingView.swift")
        let start = try XCTUnwrap(source.range(of: "private var retailerDirectorySection"))
        let end = try XCTUnwrap(source.range(of: "private var rawBaseSearchProducts", range: start.upperBound..<source.endIndex))
        let directoryBlock = String(source[start.lowerBound..<end.lowerBound])

        XCTAssertTrue(directoryBlock.contains("openStoreDirectly(url, retailer: retailer)"))
        XCTAssertFalse(directoryBlock.contains("UIApplication.shared.open"))
        XCTAssertFalse(directoryBlock.contains("setPreferredRetailerIDs"))
    }

    func testStoreSearchUsesSharedWorkerBackedCatalogProvider() throws {
        let source = try projectSource("StyleMatchAI/Shopping/StoreSearchView.swift")

        XCTAssertTrue(source.contains("SharedProductCatalogLoader.shared.loadResult()"))
        XCTAssertTrue(source.contains("catalogResult.source != .none"))
        XCTAssertTrue(source.contains("ShoppingSearchEngine.relaxedFilter(products: policyResult.products, query: currentQuery())"))
        XCTAssertTrue(source.contains("errorMessage = \"We could not search right now. Please try again.\""))
        XCTAssertFalse(source.contains("[KigoStylist Store Search] Search failed:"))
    }

    func testShoppingSurfacesConsumeSharedRetailerPreferencePolicy() throws {
        let shoppingSource = try projectSource("StyleMatchAI/Shopping/ShoppingView.swift")
        let storeSearchSource = try projectSource("StyleMatchAI/Shopping/StoreSearchView.swift")

        let baseCatalog = try XCTUnwrap(
            shoppingSource.range(of: "private var baseSearchProducts: [AffiliateProduct]")
        )
        let tierFilter = try XCTUnwrap(
            shoppingSource.range(of: "private var selectedTierFilterResult: RetailerTierFilterResult?")
        )
        let tierFilteredCatalog = try XCTUnwrap(
            shoppingSource.range(of: "private var tierFilteredBaseSearchProducts: [AffiliateProduct]")
        )
        let preferenceResult = try XCTUnwrap(
            shoppingSource.range(of: "private var retailerPreferenceResult: RetailerPreferenceResult")
        )
        let searchCatalog = try XCTUnwrap(
            shoppingSource.range(of: "private var searchCatalogProducts: [AffiliateProduct]")
        )
        let relaxedSearch = try XCTUnwrap(
            shoppingSource.range(of: "private var relaxedSearchResult: ShoppingSearchEngine.RelaxedFilterResult")
        )
        let loadPolicy = try XCTUnwrap(
            shoppingSource.range(of: "let retailerPolicyResult = RetailerPreferencePolicy.apply(")
        )
        let loadTierFilter = try XCTUnwrap(
            shoppingSource.range(of: "let tierFilterResult = selectedShopTierPreference.map", range: loadPolicy.upperBound..<shoppingSource.endIndex)
        )
        let scopedCatalog = try XCTUnwrap(
            shoppingSource.range(of: "let scopedCatalog = tierFilterResult?.products ?? retailerPolicyResult.products", range: loadTierFilter.upperBound..<shoppingSource.endIndex)
        )

        XCTAssertTrue(shoppingSource.contains("retailerPreferenceResult.products"))
        XCTAssertTrue(shoppingSource.contains("RetailerPreferencePolicy.apply("))
        XCTAssertTrue(shoppingSource[baseCatalog.lowerBound..<tierFilter.lowerBound].contains("retailerPreferenceResult.products"))
        XCTAssertTrue(shoppingSource[tierFilter.lowerBound..<tierFilteredCatalog.lowerBound].contains("products: baseSearchProducts"))
        XCTAssertTrue(shoppingSource[tierFilter.lowerBound..<tierFilteredCatalog.lowerBound].contains("RetailerCatalogRegistry(stores: supportedStores).filter"))
        XCTAssertTrue(shoppingSource[tierFilteredCatalog.lowerBound..<preferenceResult.lowerBound].contains("selectedTierFilterResult?.products ?? baseSearchProducts"))
        XCTAssertTrue(shoppingSource[searchCatalog.lowerBound..<relaxedSearch.lowerBound].contains("budgetFiltered(tierFilteredBaseSearchProducts)"))
        XCTAssertTrue(shoppingSource[loadTierFilter.lowerBound..<scopedCatalog.lowerBound].contains("products: retailerPolicyResult.products"))
        XCTAssertTrue(shoppingSource[scopedCatalog.lowerBound..<scopedCatalog.upperBound].contains("tierFilterResult?.products ?? retailerPolicyResult.products"))
        XCTAssertLessThan(loadPolicy.lowerBound, loadTierFilter.lowerBound)
        XCTAssertLessThan(loadTierFilter.lowerBound, scopedCatalog.lowerBound)
        XCTAssertFalse(shoppingSource[tierFilter.lowerBound..<tierFilteredCatalog.lowerBound].contains("retailerID =="))
        XCTAssertFalse(shoppingSource[tierFilter.lowerBound..<tierFilteredCatalog.lowerBound].contains("RetailerTier."))
        XCTAssertTrue(shoppingSource.contains("catalog: policyCatalog"))
        XCTAssertTrue(shoppingSource.contains("searchCatalogProducts.map(\\.id)"))
        XCTAssertTrue(shoppingSource.contains("companionRecommender.companions(for: product, catalog: searchCatalogProducts"))
        XCTAssertTrue(storeSearchSource.contains("RetailerPreferencePolicy.apply("))
        XCTAssertTrue(storeSearchSource.contains("preferredRetailerIDs: activePreferredRetailerIDs"))
        XCTAssertTrue(storeSearchSource.contains("retailerPreferenceFallbackUsed = policyResult.usedFallback"))
        XCTAssertTrue(shoppingSource.contains("RetailerPreferencePolicy.fallbackCopy"))
        XCTAssertTrue(storeSearchSource.contains("RetailerPreferencePolicy.fallbackCopy"))
    }

    func testMyStoresKeepsAffiliateRoutingUntouched() throws {
        let shoppingSource = try projectSource("StyleMatchAI/Shopping/ShoppingView.swift")
        let storeSearchSource = try projectSource("StyleMatchAI/Shopping/StoreSearchView.swift")

        XCTAssertTrue(shoppingSource.contains("ShoppingProductOpener"))
        XCTAssertTrue(storeSearchSource.contains("ShoppingProductOpener"))
        XCTAssertFalse(shoppingSource.contains("UIApplication.shared.open(AffiliateLinkBuilder.outboundURL(for: product)"))
        XCTAssertFalse(storeSearchSource.contains("UIApplication.shared.open(AffiliateLinkBuilder.outboundURL(for: product)"))
        XCTAssertFalse(shoppingSource.contains("retailerID") && shoppingSource.contains("trackingParamName ="))
        XCTAssertFalse(storeSearchSource.contains("retailerID") && storeSearchSource.contains("trackingParamName ="))
    }

    func testLiveSearchFlagDefaultsOffAndResolverStaysDormant() throws {
        XCTAssertFalse(FeatureFlags.liveSearchEnabled)
        XCTAssertFalse(FeatureFlags.pushNotificationsEnabled)
        XCTAssertFalse(FeatureFlags.saleNotificationsEnabled)

        let provider = try ShoppingDataSourceResolver.liveProvider(
            liveSearchEnabled: false,
            configProvider: StaticShoppingIntegrationConfigProvider(storedConfig: ShoppingIntegrationConfig(
                liveSearchProxyBaseURL: URL(string: "https://proxy.example.com"),
                allowedClientSideAPIKeyNames: []
            ))
        )

        XCTAssertNil(provider)
    }

    func testLiveSearchEnabledRequiresProxyConfig() {
        XCTAssertThrowsError(try ShoppingDataSourceResolver.liveProvider(
            liveSearchEnabled: true,
            configProvider: StaticShoppingIntegrationConfigProvider(storedConfig: .empty)
        ))
    }

    func testFounderToolingIsDebugOnlyInSource() throws {
        let featureGate = try projectSource("StyleMatchAI/FeatureGate.swift")
        let contentView = try projectSource("StyleMatchAI/ContentView.swift")

        XCTAssertTrue(featureGate.contains("#if DEBUG"))
        XCTAssertTrue(featureGate.contains("static let releaseChannel: StyleMatchReleaseChannel = .customerPublic"))
        XCTAssertTrue(featureGate.contains("static var allowsLocalFounderAPIKey: Bool"))
        XCTAssertTrue(featureGate.contains("#else\n        false\n        #endif"))
        XCTAssertTrue(contentView.contains("StyleMatchBuildSettings.allowsLocalFounderAPIKey"))
    }

    func testShoppingProductStylistIsFounderOnlyAndRootGated() throws {
        let featureGate = try projectSource("StyleMatchAI/FeatureGate.swift")
        let shoppingView = try projectSource("StyleMatchAI/Shopping/ShoppingView.swift")
        let contentView = try projectSource("StyleMatchAI/ContentView.swift")
        let gate = "FeatureGate.shared.isCustomerVisible(.aiPersonalShopper)"

        let customerVisibleRange = try XCTUnwrap(featureGate.range(of: "private let customerVisibleFeatures"))
        let apiReadyRange = try XCTUnwrap(featureGate.range(of: "private let apiReadyFeatures"))
        let visibilityRange = try XCTUnwrap(featureGate.range(of: "func isCustomerVisible("))
        let customerVisibleSource = String(featureGate[customerVisibleRange.lowerBound..<apiReadyRange.lowerBound])
        let apiReadySource = String(featureGate[apiReadyRange.lowerBound..<visibilityRange.lowerBound])
        let visibilitySource = String(featureGate[visibilityRange.lowerBound...])

        XCTAssertFalse(customerVisibleSource.contains(".aiPersonalShopper"))
        XCTAssertTrue(apiReadySource.contains(".aiPersonalShopper"))
        XCTAssertTrue(visibilitySource.contains("releaseChannel: StyleMatchReleaseChannel = StyleMatchBuildSettings.releaseChannel"))
        XCTAssertTrue(visibilitySource.contains("case .customerPublic:\n            return customerVisibleFeatures.contains(feature)"))
        XCTAssertTrue(visibilitySource.contains("case .founderBeta:\n            return customerVisibleFeatures.contains(feature) || apiReadyFeatures.contains(feature)"))

        XCTAssertTrue(shoppingView.contains("if \(gate)"))
        XCTAssertTrue(contentView.contains("guard \(gate) else {\n            return\n        }"))

        let rootGate = try XCTUnwrap(contentView.range(of: "guard \(gate) else {"))
        let productIDs = try XCTUnwrap(contentView.range(of: "availableShoppingProductIDs = availableProductIDs"))
        let publication = try XCTUnwrap(contentView.range(of: "stylistAwarenessCoordinator.publishShoppingProduct(product)"))
        XCTAssertLessThan(rootGate.lowerBound, productIDs.lowerBound)
        XCTAssertLessThan(rootGate.lowerBound, publication.lowerBound)
    }

    func testProxyLiveSearchSendsOnlyAllowedSearchFilters() async throws {
        CapturingURLProtocol.lastURL = nil
        CapturingURLProtocol.responseData = Data("[]".utf8)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CapturingURLProtocol.self]
        let session = URLSession(configuration: config)
        let provider = ProxyLiveRetailerSearchProvider(
            proxyBaseURL: URL(string: "https://proxy.example.com/stylematch")!,
            urlSession: session
        )
        var criteria = ShoppingSearchCriteria()
        criteria.query = "white shirt"
        criteria.storeName = "Macy's"
        criteria.brand = "Calvin Klein"
        criteria.category = .clothing
        criteria.color = "white"
        criteria.size = "XL"
        criteria.style = "formal"
        criteria.genderPresentation = "men"
        criteria.minimumPrice = Decimal(20)
        criteria.maximumPrice = Decimal(100)
        criteria.occasion = "office"

        _ = try await provider.search(criteria: criteria)

        let url = try XCTUnwrap(CapturingURLProtocol.lastURL)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryNames = Set((components.queryItems ?? []).map(\.name))
        XCTAssertEqual(components.path, "/stylematch/search")
        XCTAssertTrue(queryNames.isSuperset(of: ["q", "store", "brand", "category", "color", "size", "style", "gender", "minPrice", "maxPrice", "occasion"]))
        XCTAssertFalse(queryNames.contains("outfitMemory"))
        XCTAssertFalse(queryNames.contains("scanPhoto"))
        XCTAssertFalse(queryNames.contains("userID"))
        XCTAssertFalse(queryNames.contains("coordinates"))
    }

    func testAccountExchangeUsesNonceAppleCredentialsAndNoEmbeddedSharedSecret() async throws {
        CapturingURLProtocol.lastRequest = nil
        CapturingURLProtocol.lastRequestBody = nil
        CapturingURLProtocol.statusCode = 200
        CapturingURLProtocol.responseData = Data("""
        {"session_token":"abcdefghijklmnopqrstuvwxyz1234567890ABCDEFG","expires_at":"2026-08-11T18:00:00.000Z"}
        """.utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CapturingURLProtocol.self]
        let client = StyleMatchAccountClient(
            baseURL: URL(string: "https://account.example.com")!,
            session: URLSession(configuration: configuration)
        )

        let session = try await client.exchange(
            authorizationCode: Data("single-use-code".utf8),
            identityToken: Data("signed-identity-token".utf8),
            nonce: "raw-nonce-value",
            appleSubject: "apple-subject-one"
        )

        XCTAssertEqual(session.token, "abcdefghijklmnopqrstuvwxyz1234567890ABCDEFG")
        XCTAssertEqual(session.appleSubject, "apple-subject-one")
        XCTAssertEqual(session.endpointHost, "account.example.com")
        let request = try XCTUnwrap(CapturingURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/v1/auth/apple/exchange")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "X-Device-Hash"))
        XCTAssertNil(request.value(forHTTPHeaderField: "X-App-Auth"))
        let body = try XCTUnwrap(CapturingURLProtocol.lastRequestBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json["authorization_code"], "single-use-code")
        XCTAssertEqual(json["identity_token"], "signed-identity-token")
        XCTAssertEqual(json["nonce"], "raw-nonce-value")
    }

    func testAccountExchangeFailsSafelyWhenBaseURLIsUnavailable() async throws {
        let client = StyleMatchAccountClient(baseURL: nil)

        do {
            _ = try await client.exchange(
                authorizationCode: Data("single-use-code".utf8),
                identityToken: Data("signed-identity-token".utf8),
                nonce: "raw-nonce-value"
            )
            XCTFail("Expected unavailable account configuration to fail.")
        } catch StyleMatchAccountError.configurationUnavailable {
            // Expected: fail before attempting a network request.
        } catch {
            XCTFail("Expected configurationUnavailable, received \(error).")
        }
    }

    func testAccountExchangeMapsCredentialValidationFailureWithoutPersistingASession() async throws {
        CapturingURLProtocol.statusCode = 401
        CapturingURLProtocol.responseData = Data("{\"error\":\"apple_credential_invalid\"}".utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CapturingURLProtocol.self]
        let client = StyleMatchAccountClient(
            baseURL: URL(string: "https://account.example.com")!,
            session: URLSession(configuration: configuration)
        )

        do {
            _ = try await client.exchange(
                authorizationCode: Data("single-use-code".utf8),
                identityToken: Data("signed-identity-token".utf8),
                nonce: "raw-nonce-value",
                appleSubject: "apple-subject-one"
            )
            XCTFail("Expected credential verification failure")
        } catch let error as StyleMatchAccountError {
            XCTAssertEqual(error.localizedDescription, StyleMatchAccountError.credentialVerificationFailed.localizedDescription)
        }
    }

    func testAccountDeletionMapsFreshAuthorizationRequirementToSafeError() async throws {
        CapturingURLProtocol.lastRequest = nil
        CapturingURLProtocol.statusCode = 409
        CapturingURLProtocol.responseData = Data("{\"error\":\"apple_reauthentication_required\"}".utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CapturingURLProtocol.self]
        let client = StyleMatchAccountClient(
            baseURL: URL(string: "https://account.example.com")!,
            session: URLSession(configuration: configuration)
        )
        let session = StyleMatchAccountSession(token: String(repeating: "s", count: 48), expiresAt: Date().addingTimeInterval(300))

        do {
            try await client.deleteAccount(session: session)
            XCTFail("Expected fresh Apple authorization to be required.")
        } catch let error as StyleMatchAccountError {
            XCTAssertEqual(error.localizedDescription, StyleMatchAccountError.reauthenticationRequired.localizedDescription)
        }

        let request = try XCTUnwrap(CapturingURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/v1/account")
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(session.token)")
    }

    func testAccountExchangeMapsAppleCredentialInvalidToCredentialVerificationMessage() async throws {
        CapturingURLProtocol.statusCode = 401
        CapturingURLProtocol.responseData = Data("{\"error\":\"apple_credential_invalid\"}".utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CapturingURLProtocol.self]
        let client = StyleMatchAccountClient(baseURL: URL(string: "https://account.example.com")!, session: URLSession(configuration: configuration))
        do {
            _ = try await client.exchange(authorizationCode: Data("code".utf8), identityToken: Data("identity-token".utf8), nonce: "nonce-value-123456")
            XCTFail("Expected credential validation failure")
        } catch let error as StyleMatchAccountError {
            XCTAssertEqual(error.localizedDescription, StyleMatchAccountError.credentialVerificationFailed.localizedDescription)
        }
    }

    func testAppleNonceHashMatchesSHA256AndGeneratedNonceHasRequestedLength() throws {
        XCTAssertEqual(
            StyleMatchAppleNonce.hash("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        XCTAssertEqual(try StyleMatchAppleNonce.make(length: 48).count, 48)
    }

    func testAccountSessionAuthorityRequiresMatchingSubjectHostAndExpiry() {
        let valid = StyleMatchAccountSession(
            token: String(repeating: "s", count: 48),
            expiresAt: Date(timeIntervalSince1970: 2_000),
            appleSubject: "apple-subject-one",
            accountID: "sf_account_opaque",
            endpointHost: "stylematch-friends-staging.sabastine-7000.workers.dev"
        )
        XCTAssertEqual(
            StyleMatchAccountSessionAuthority.state(
                session: valid,
                expectedHost: "stylematch-friends-staging.sabastine-7000.workers.dev",
                now: Date(timeIntervalSince1970: 1_000)
            ),
            .active(valid)
        )
        XCTAssertEqual(
            StyleMatchAccountSessionAuthority.state(
                session: valid,
                expectedHost: "production.example.com",
                now: Date(timeIntervalSince1970: 1_000)
            ),
            .reauthenticationRequired
        )
        XCTAssertEqual(
            StyleMatchAccountSessionAuthority.state(
                session: valid,
                expectedHost: "stylematch-friends-staging.sabastine-7000.workers.dev",
                now: Date(timeIntervalSince1970: 2_001)
            ),
            .reauthenticationRequired
        )
    }

    func testRemoteCatalogProviderSendsOnlyCatalogFiltersAndMapsWorkerProducts() async throws {
        CapturingURLProtocol.lastURL = nil
        CapturingURLProtocol.responseData = Data("""
        {
          "products": [
            {
              "id": "macys-white-oxford",
              "store_id": "macys",
              "store_name": "Macy's",
              "name": "White Oxford Shirt",
              "image_url": "https://example.com/products/white-oxford.jpg",
              "category": "tops",
              "brand": "Macy's",
              "price_cents": 7950,
              "sale_price_cents": 4999,
              "sale_ends_at": "2027-01-01T00:00:00Z",
              "currency": "USD",
              "country_code": "US",
              "available_countries": ["US", "CA"],
              "availability": "in_stock",
              "tags": ["business", "white", "shirt"],
              "buy_url": "https://proxy.example.com/v1/go/macys-white-oxford"
            }
          ],
          "next_cursor": null,
          "disclosure": "As an Amazon Associate I earn from qualifying purchases. StyleMatch Pro may earn a commission at no extra cost to you."
        }
        """.utf8)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CapturingURLProtocol.self]
        let session = URLSession(configuration: config)
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let provider = RemoteCatalogProvider(
            baseURL: URL(string: "https://proxy.example.com")!,
            cacheDirectory: cacheDirectory,
            fallbackProvider: StaticProductCatalogProvider(products: []),
            urlSession: session
        )

        let result = await provider.loadResult()
        let products = result.products

        XCTAssertEqual(result.source, .remote)
        XCTAssertEqual(result.diagnostic.finalSource, .remote)
        XCTAssertEqual(result.diagnostic.httpStatus, 200)
        XCTAssertEqual(result.diagnostic.remoteProductCount, 1)
        XCTAssertEqual(products.map(\.id), ["macys-white-oxford"])
        XCTAssertEqual(products.first?.affiliateURL.absoluteString, "https://proxy.example.com/v1/go/macys-white-oxford")
        XCTAssertEqual(products.first?.retailerID, "macys")
        XCTAssertEqual(products.first?.retailer.trackingID, AffiliateLinkBuilder.pendingApprovalTrackingID)
        XCTAssertEqual(products.first?.currencyCode, "USD")
        XCTAssertEqual(products.first?.availableCountries, ["US", "CA"])
        XCTAssertEqual(try RemoteCatalogProvider.decodeRemoteDisclosure(CapturingURLProtocol.responseData), ShoppingCatalogDisclosure.fallback)

        let url = try XCTUnwrap(CapturingURLProtocol.lastURL)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/v1/products")
        let queryNames = Set((components.queryItems ?? []).map(\.name))
        XCTAssertEqual(queryNames, ["limit", "country"])
        XCTAssertFalse(url.absoluteString.contains("profile"))
        XCTAssertFalse(url.absoluteString.contains("outfit"))
        XCTAssertFalse(url.absoluteString.contains("user"))
        XCTAssertFalse(url.absoluteString.contains("wardrobe"))
    }

    func testRemoteCatalogDecodePreservesCanonicalStoreIDWithoutNameInference() throws {
        let data = Data("""
        {
          "products": [
            {
              "id": "unknown-store-shirt",
              "store_id": "unknown-approved-source",
              "store_name": "Macy's",
              "name": "White Oxford Shirt",
              "image_url": null,
              "category": "tops",
              "brand": "Macy's",
              "price_cents": 7950,
              "sale_price_cents": null,
              "sale_ends_at": null,
              "currency": "USD",
              "country_code": "US",
              "available_countries": ["US"],
              "availability": "in_stock",
              "tags": ["business", "white", "shirt"],
              "buy_url": "https://proxy.example.com/v1/go/unknown-store-shirt"
            }
          ]
        }
        """.utf8)

        let products = try RemoteCatalogProvider.decodeRemoteProducts(
            data,
            baseURL: URL(string: "https://proxy.example.com")!,
            regionCode: "US"
        )

        let product = try XCTUnwrap(products.first)
        XCTAssertEqual(product.retailerID, "unknown-approved-source")
        XCTAssertEqual(product.retailer.name, "Macy's")
    }

    func testBundledCatalogDecodePreservesRetailerIDAndLegacyMissingID() throws {
        let catalogData = Data("""
        [
          {
            "id": "macys-local-shirt",
            "name": "Local White Shirt",
            "category": "clothing",
            "subcategory": "shirt",
            "colors": ["white"],
            "retailer_id": "macys",
            "retailer": {
              "name": "Macy's",
              "trackingID": "PENDING-APPROVAL",
              "trackingParamName": "aff",
              "disclosureName": "Macy's"
            },
            "affiliateURL": "https://www.macys.com/local-shirt",
            "tags": ["shirt", "white"]
          },
          {
            "id": "legacy-local-shirt",
            "name": "Legacy Shirt",
            "category": "clothing",
            "subcategory": "shirt",
            "colors": ["blue"],
            "retailer": {
              "name": "Macy's",
              "trackingID": "PENDING-APPROVAL",
              "trackingParamName": "aff",
              "disclosureName": "Macy's"
            },
            "affiliateURL": "https://www.macys.com/legacy-shirt",
            "tags": ["shirt", "blue"]
          }
        ]
        """.utf8)

        let products = try BundledCatalogProvider.decodeProducts(catalogData: catalogData)

        XCTAssertEqual(products.first(where: { $0.id == "macys-local-shirt" })?.retailerID, "macys")
        XCTAssertNil(products.first(where: { $0.id == "legacy-local-shirt" })?.retailerID)
    }

    func testBundledCatalogEntriesUseApprovedCanonicalRetailerIDs() throws {
        let catalogData = try Data(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("StyleMatchAI/Shopping/ProductCatalog.json")
        )
        let supportedStoresData = try Data(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("StyleMatchAI/Shopping/SupportedStores.json")
        )

        let products = try BundledCatalogProvider.decodeProducts(catalogData: catalogData)
        let supportedStores = try JSONDecoder().decode([SupportedStore].self, from: supportedStoresData)
        let approvedStoreIDs = Set(
            supportedStores
                .filter(\.isEnabled)
                .map(\.id)
        )
        let registry = RetailerCatalogRegistry(stores: supportedStores)
        let legacyIDs: Set<String> = [
            "macys-white-oxford-001",
            "nike-white-sneaker-001",
            "footlocker-nike-airmax-001",
            "amazon-fabric-steamer-001",
            "bestbuy-smartwatch-001",
            "macys-black-belt-001",
            "target-umbrella-001",
            "nordstrom-navy-blazer-001",
            "levi-dark-denim-001",
            "amazon-sunglasses-001",
            "nike-gym-duffel-001",
            "macys-linen-shirt-001"
        ]
        let pilotIDs: Set<String> = [
            "gucci-840330aae801066-g75-sneaker",
            "prada-sc810-re-nylon-shirt",
            "ssense-hope-18999901-regular-fit-shirt",
            "ssense-hope-18998871-gray-short-sleeve-shirt",
            "nike-ah8050-005-air-max-270",
            "adidas-b75807-samba-og",
            "target-54190290-goodfellow-every-wear-tee",
            "levis-005010660-501-original-jeans"
        ]

        XCTAssertEqual(products.count, 20)
        XCTAssertEqual(Set(products.map(\.id)), legacyIDs.union(pilotIDs))
        XCTAssertFalse(approvedStoreIDs.isEmpty)
        for product in products {
            let retailerID = try XCTUnwrap(product.retailerID, "\(product.id) is missing retailer_id")
            XCTAssertTrue(
                approvedStoreIDs.contains(retailerID),
                "\(product.id) uses unsupported retailer_id \(retailerID)"
            )
            XCTAssertNotNil(registry.store(retailerID: retailerID), "\(product.id) did not resolve through the directory")
        }

        let legacyProducts = products.filter { legacyIDs.contains($0.id) }
        let pilotProducts = products.filter { pilotIDs.contains($0.id) }
        XCTAssertEqual(legacyProducts.count, 12)
        XCTAssertEqual(
            Set(legacyProducts.compactMap(\.retailerID)),
            ["amazon", "best-buy", "foot-locker", "levis", "macys", "nike", "nordstrom", "target"]
        )
        XCTAssertEqual(pilotProducts.count, 8)
        XCTAssertEqual(Set(pilotProducts.compactMap(\.retailerID)), ["gucci", "prada", "ssense", "nike", "adidas", "target", "levis"])
        XCTAssertEqual(pilotProducts.filter { registry.tier(retailerID: $0.retailerID) == .designerLuxury }.count, 2)
        XCTAssertEqual(pilotProducts.filter { registry.tier(retailerID: $0.retailerID) == .luxuryMultiBrand }.count, 2)
        XCTAssertEqual(pilotProducts.filter { registry.tier(retailerID: $0.retailerID) == .athleticStreetwear }.count, 2)
        XCTAssertEqual(pilotProducts.filter { registry.tier(retailerID: $0.retailerID) == .everydayValue }.count, 2)
    }

    func testBundledCatalogUnknownRetailerIDDoesNotSilentlyMapFromDisplayName() throws {
        let catalogData = Data("""
        [
          {
            "id": "unknown-local-shirt",
            "name": "Unknown Local Shirt",
            "category": "clothing",
            "subcategory": "shirt",
            "colors": ["white"],
            "retailer_id": "unknown-retailer",
            "retailer": {
              "name": "Macy's",
              "trackingID": "PENDING-APPROVAL",
              "trackingParamName": "aff",
              "disclosureName": "Macy's"
            },
            "affiliateURL": "https://www.macys.com/unknown-local-shirt",
            "tags": ["shirt", "white"]
          }
        ]
        """.utf8)
        let retailerConfigData = Data("""
        {
          "retailers": [
            {
              "name": "Macy's",
              "trackingID": "APPROVED-ID",
              "trackingParamName": "aff",
              "disclosureName": "Macy's"
            }
          ]
        }
        """.utf8)

        let products = try BundledCatalogProvider.decodeProducts(
            catalogData: catalogData,
            retailerConfigData: retailerConfigData
        )

        let product = try XCTUnwrap(products.first)
        XCTAssertEqual(product.retailerID, "unknown-retailer")
        XCTAssertEqual(product.retailer.trackingID, "APPROVED-ID")
    }

    func testAffiliateProductEqualityRemainsStableWhenRetailerIDIsBackfilled() {
        let legacy = makeAffiliateProduct(id: "stable-product", retailerID: nil)
        let backfilled = makeAffiliateProduct(id: "stable-product", retailerID: "macys")

        XCTAssertEqual(legacy, backfilled)
        XCTAssertEqual(legacy.id, backfilled.id)
        XCTAssertNil(legacy.retailerID)
        XCTAssertEqual(backfilled.retailerID, "macys")
    }

    func testRemoteCatalogReturningTwelveProductsSelectsRemoteSourceForBrowse() async throws {
        CatalogTestURLProtocol.mode = .response(remoteCatalogPayload(ids: (1...12).map { "remote-\($0)" }), 200)
        let provider = makeResilientCatalogProvider(
            cacheDirectory: temporaryCatalogDirectory(),
            fallback: StaticProductCatalogProvider(products: [catalogTestProduct(id: "bundled-product")])
        )

        let result = await provider.loadResult()

        XCTAssertEqual(result.source, .remote)
        XCTAssertEqual(result.products.count, 12)
        XCTAssertEqual(result.diagnostic.remoteProductCount, 12)
        XCTAssertEqual(result.diagnostic.finalSource, .remote)
    }

    func testRemoteCatalogProviderFiltersByCountryAndFormatsGBPPrices() throws {
        let data = Data("""
        {
          "products": [
            {
              "id": "gb-only-blazer",
              "store_id": "stylehub",
              "store_name": "StyleHub",
              "name": "Navy Blazer",
              "image_url": "https://example.com/products/navy-blazer.jpg",
              "category": "outerwear",
              "brand": "StyleHub",
              "price_cents": 8900,
              "sale_price_cents": null,
              "sale_ends_at": null,
              "currency": "GBP",
              "country_code": "GB",
              "available_countries": ["GB"],
              "availability": "in_stock",
              "tags": ["business", "navy", "jacket"],
              "buy_url": "https://proxy.example.com/v1/go/gb-only-blazer"
            },
            {
              "id": "us-only-shirt",
              "store_id": "macys",
              "store_name": "Macy's",
              "name": "White Oxford Shirt",
              "image_url": "https://example.com/products/white-oxford.jpg",
              "category": "tops",
              "brand": "Macy's",
              "price_cents": 7950,
              "sale_price_cents": null,
              "sale_ends_at": null,
              "currency": "USD",
              "country_code": "US",
              "available_countries": ["US"],
              "availability": "in_stock",
              "tags": ["business", "white", "shirt"],
              "buy_url": "https://proxy.example.com/v1/go/us-only-shirt"
            }
          ]
        }
        """.utf8)

        let products = try RemoteCatalogProvider.decodeRemoteProducts(
            data,
            baseURL: URL(string: "https://proxy.example.com")!,
            regionCode: "GB"
        )

        XCTAssertEqual(products.map(\.id), ["gb-only-blazer"])
        let product = try XCTUnwrap(products.first)
        XCTAssertEqual(product.currencyCode, "GBP")
        let viewModel = AffiliateProductViewModel(product: product)
        XCTAssertTrue(viewModel.priceText.contains("£"), "Expected GBP price, got \(viewModel.priceText)")
    }

    func testRemoteCatalogTimeoutUsesValidCachedCatalog() async throws {
        CatalogTestURLProtocol.mode = .failure(.timedOut)
        let cacheDirectory = temporaryCatalogDirectory()
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try remoteCatalogPayload(id: "cached-product").write(
            to: cacheDirectory.appendingPathComponent("ProductCatalog.worker.remote.json")
        )
        let provider = makeResilientCatalogProvider(
            cacheDirectory: cacheDirectory,
            fallback: StaticProductCatalogProvider(products: [catalogTestProduct(id: "bundled-product")])
        )

        let result = await provider.loadResult()
        let products = result.products

        XCTAssertEqual(result.source, .cache)
        XCTAssertEqual(result.diagnostic.finalSource, .cache)
        XCTAssertTrue(result.diagnostic.cacheHit)
        XCTAssertNotNil(result.diagnostic.cacheAge)
        XCTAssertEqual(products.map(\.id), ["cached-product"])
        XCTAssertEqual(CatalogTestURLProtocol.lastRequest?.timeoutInterval, RemoteCatalogProvider.defaultRequestTimeout)
        XCTAssertEqual(RemoteCatalogProvider.defaultRequestTimeout, 10)
    }

    func testRemoteCatalogTimeoutWithoutCacheUsesBundledCatalog() async throws {
        CatalogTestURLProtocol.mode = .failure(.timedOut)
        let cacheDirectory = temporaryCatalogDirectory()
        let provider = makeResilientCatalogProvider(
            cacheDirectory: cacheDirectory,
            fallback: StaticProductCatalogProvider(products: [catalogTestProduct(id: "bundled-product")])
        )

        let result = await provider.loadResult()
        let products = result.products

        XCTAssertEqual(result.source, .bundled)
        XCTAssertEqual(result.diagnostic.finalSource, .bundled)
        XCTAssertEqual(result.diagnostic.bundledFallbackCount, 1)
        XCTAssertEqual(products.map(\.id), ["bundled-product"])
    }

    func testRemoteCatalogOfflineFirstLaunchUsesBundledCatalog() async throws {
        CatalogTestURLProtocol.mode = .failure(.notConnectedToInternet)
        let cacheDirectory = temporaryCatalogDirectory()
        let provider = makeResilientCatalogProvider(
            cacheDirectory: cacheDirectory,
            fallback: StaticProductCatalogProvider(products: [catalogTestProduct(id: "offline-bundled")])
        )

        let result = await provider.loadResult()
        let products = result.products

        XCTAssertEqual(result.source, .bundled)
        XCTAssertEqual(result.diagnostic.finalSource, .bundled)
        XCTAssertEqual(result.diagnostic.classification, .connectivity)
        XCTAssertEqual(products.map(\.id), ["offline-bundled"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheDirectory.path))
    }

    func testRemoteCatalogCorruptCacheUsesBundledCatalog() async throws {
        CatalogTestURLProtocol.mode = .failure(.notConnectedToInternet)
        let cacheDirectory = temporaryCatalogDirectory()
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: cacheDirectory.appendingPathComponent("ProductCatalog.worker.remote.json"))
        let provider = makeResilientCatalogProvider(
            cacheDirectory: cacheDirectory,
            fallback: StaticProductCatalogProvider(products: [catalogTestProduct(id: "bundled-after-corrupt-cache")])
        )

        let result = await provider.loadResult()
        let products = result.products

        XCTAssertEqual(result.source, .bundled)
        XCTAssertEqual(result.diagnostic.finalSource, .bundled)
        XCTAssertEqual(products.map(\.id), ["bundled-after-corrupt-cache"])
    }

    func testRemoteCatalogCacheWriteFailureKeepsSuccessfulRemoteCatalog() async throws {
        CatalogTestURLProtocol.mode = .response(remoteCatalogPayload(id: "remote-product"), 200)
        let cacheDirectory = temporaryCatalogDirectory()
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        try Data("this path is a file".utf8).write(to: cacheDirectory)
        let provider = makeResilientCatalogProvider(
            cacheDirectory: cacheDirectory,
            fallback: StaticProductCatalogProvider(products: [catalogTestProduct(id: "bundled-product")])
        )

        let result = await provider.loadResult()
        let products = result.products

        XCTAssertEqual(result.source, .remote)
        XCTAssertEqual(result.diagnostic.finalSource, .remote)
        XCTAssertEqual(products.map(\.id), ["remote-product"])
    }

    func testRemoteCatalogCancellationDoesNotInvokeFallback() async throws {
        CatalogTestURLProtocol.mode = .failure(.cancelled)
        let fallback = CatalogFallbackSpy(result: .success([catalogTestProduct(id: "must-not-load")]))
        let provider = makeResilientCatalogProvider(
            cacheDirectory: temporaryCatalogDirectory(),
            fallback: fallback
        )

        do {
            _ = try await provider.products()
            XCTFail("Expected cancellation to propagate.")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .cancelled)
        } catch is CancellationError {
            // URLSession may normalize a cancelled load to task cancellation.
        }
        XCTAssertEqual(fallback.callCount, 0)
    }

    func testBundledFallbackRejectsUnsafeCountryAndUnavailableProducts() async throws {
        CatalogTestURLProtocol.mode = .failure(.notConnectedToInternet)
        let unsafeURL = catalogTestProduct(id: "unsafe-url", affiliateURL: URL(string: "https://stylematch.local/placeholder")!)
        let unavailable = catalogTestProduct(id: "unavailable", availability: "out_of_stock")
        let wrongCountry = catalogTestProduct(id: "wrong-country", availableCountries: ["GB"])
        let safe = catalogTestProduct(id: "safe")
        let provider = makeResilientCatalogProvider(
            cacheDirectory: temporaryCatalogDirectory(),
            fallback: StaticProductCatalogProvider(products: [unsafeURL, unavailable, wrongCountry, safe])
        )

        let result = await provider.loadResult()
        let products = result.products

        XCTAssertEqual(result.source, .bundled)
        XCTAssertEqual(result.diagnostic.finalSource, .bundled)
        XCTAssertEqual(products.map(\.id), ["safe"])
    }

    func testRemoteCatalogThrowsMissingCatalogOnlyAfterEverySourceFails() async throws {
        CatalogTestURLProtocol.mode = .failure(.timedOut)
        let cacheDirectory = temporaryCatalogDirectory()
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try Data("corrupt".utf8).write(to: cacheDirectory.appendingPathComponent("ProductCatalog.worker.remote.json"))
        let provider = makeResilientCatalogProvider(
            cacheDirectory: cacheDirectory,
            fallback: FailingProductCatalogProvider(error: ProductCatalogProviderError.missingCatalog)
        )

        let result = await provider.loadResult()
        XCTAssertEqual(result.source, .none)
        XCTAssertEqual(result.diagnostic.finalSource, .none)

        do {
            _ = try await provider.products()
            XCTFail("Expected every catalog source to fail.")
        } catch ProductCatalogProviderError.missingCatalog {
            // Expected controlled terminal failure.
        } catch {
            XCTFail("Expected missingCatalog, received \(error).")
        }
    }

    func testBundledStaticFallbackCatalogContainsApprovedSafeBrowseProductsAndNoDeals() throws {
        let catalogData = try Data(projectSource("StyleMatchAI/Shopping/ProductCatalog.json").utf8)
        let retailerConfigData = try Data(projectSource("StyleMatchAI/Shopping/RetailerConfig.json").utf8)
        let decoded = try BundledCatalogProvider.decodeProducts(
            catalogData: catalogData,
            retailerConfigData: retailerConfigData
        )
        let safe = CatalogProductSafetyValidator.validated(decoded, regionCode: "US")
        let pilotIDs: Set<String> = [
            "gucci-840330aae801066-g75-sneaker",
            "prada-sc810-re-nylon-shirt",
            "ssense-hope-18999901-regular-fit-shirt",
            "ssense-hope-18998871-gray-short-sleeve-shirt",
            "nike-ah8050-005-air-max-270",
            "adidas-b75807-samba-og",
            "target-54190290-goodfellow-every-wear-tee",
            "levis-005010660-501-original-jeans"
        ]
        let pilot = safe.filter { pilotIDs.contains($0.id) }

        XCTAssertEqual(safe.count, 20)
        XCTAssertEqual(Set(pilot.map(\.id)), pilotIDs)
        XCTAssertTrue(safe.contains { $0.imageURL == nil })
        XCTAssertTrue(safe.allSatisfy { $0.salePrice == nil && $0.saleEndsAt == nil })
        XCTAssertTrue(safe.allSatisfy { $0.tags.contains("fallback-static") })
        XCTAssertTrue(pilot.allSatisfy { product in
            product.imageURL == nil
                && product.price == nil
                && product.priceRange == nil
                && product.salePrice == nil
                && product.saleEndsAt == nil
                && product.availability == nil
                && product.sizes == nil
        })
        XCTAssertTrue(safe.allSatisfy { product in
            guard let host = URLComponents(url: AffiliateLinkBuilder.outboundURL(for: product), resolvingAgainstBaseURL: false)?.host else {
                return false
            }
            return !host.isEmpty && host != "stylematch.local"
        })
    }

    func testRemoteCatalogUSNGAndGBResponsesDecodeSuccessfully() throws {
        let payload = remoteCatalogPayload(
            ids: (1...13).map { "global-\($0)" },
            availableCountries: ["US", "NG", "GB"]
        )

        XCTAssertEqual(try RemoteCatalogProvider.decodeRemoteProducts(payload, baseURL: URL(string: "https://proxy.example.com")!, regionCode: "US").count, 13)
        XCTAssertEqual(try RemoteCatalogProvider.decodeRemoteProducts(payload, baseURL: URL(string: "https://proxy.example.com")!, regionCode: "NG").count, 13)
        XCTAssertEqual(try RemoteCatalogProvider.decodeRemoteProducts(payload, baseURL: URL(string: "https://proxy.example.com")!, regionCode: "GB").count, 13)
    }

    func testShoppingSourceStatesSeparateTransportFailureFromNarrowFilters() throws {
        let shoppingSource = try projectSource("StyleMatchAI/Shopping/ShoppingView.swift")

        XCTAssertTrue(shoppingSource.contains("SharedProductCatalogLoader.shared.loadResult("))
        XCTAssertTrue(shoppingSource.contains("diagnosticContext: loadContext"))
        XCTAssertTrue(shoppingSource.contains("catalogResult.source != .none"))
        XCTAssertTrue(shoppingSource.contains("live catalog, cache, or bundled fallback"))
        XCTAssertTrue(shoppingSource.contains("catalogSource == .bundled"))
        XCTAssertTrue(shoppingSource.contains("searchResults.isEmpty, !products.isEmpty"))
        XCTAssertTrue(shoppingSource.contains("Your current filters are narrow"))
    }

    func testShoppingEndpointIsCatalogConfigAndNotChatOrAccountStagingOverride() throws {
        let catalogSource = try projectSource("StyleMatchAI/Shopping/ProductCatalogProvider.swift")

        XCTAssertTrue(catalogSource.contains("ShoppingRuntimeConfig"))
        XCTAssertTrue(catalogSource.contains("catalogBaseURL"))
        XCTAssertTrue(catalogSource.contains("appendingPathComponent(\"v1/products\")"))
        XCTAssertFalse(catalogSource.contains("StyleMatchAccountClient"))
        XCTAssertFalse(catalogSource.contains("StylistChatService"))
    }

    func testPersonalStylistEngineFinalMessageOmitsDealsWhenSaleMatchingFlagIsFalse() {
        let input = PersonalStylistEngineInput(
            score: 89,
            scoreTier: "Good Match",
            scoreBreakdown: nil,
            detectedGarments: ["black pants", "white shirt"],
            colors: ["black", "white"],
            detectedStyle: "Casual",
            occasion: "Casual",
            memories: [],
            profile: makeStylistProfile(userId: userA),
            dealMatches: [
                PersonalStylistDealMatch(
                    productName: "White Oxford Shirt",
                    retailerName: "Macy's",
                    category: "shirt",
                    salePrice: "$59.99",
                    reason: "Matches a stored outfit."
                )
            ]
        )

        let message = PersonalStylistEngine.compose(
            input: input,
            weatherAdviceEnabled: false,
            saleMatchingEnabled: false
        )
        let context = PersonalStylistEngine.context(
            input: input,
            weatherAdviceEnabled: false,
            saleMatchingEnabled: false
        )

        XCTAssertFalse(message.plainText.contains("Macy's"))
        XCTAssertTrue(context.dealFacts.isEmpty)
    }

    func testPersonalStylistUsesCanonicalOutfitTypeInsteadOfAccessoryOnlyMemoryRecall() {
        let classification = OutfitClassificationEngine.classify(
            visualObservations: [
                OutfitVisualObservation(identifier: "visible person clothing region", confidence: 0.80),
                OutfitVisualObservation(identifier: "watch", confidence: 0.96)
            ],
            selectedOccasion: "Work"
        )
        let input = PersonalStylistEngineInput(
            score: 82,
            scoreTier: "Good",
            scoreBreakdown: nil,
            detectedGarments: ["watch"],
            detectedItemConfidences: [DetectedItemConfidence(item: "watch", confidence: 96)],
            colors: ["beige"],
            detectedStyle: "Casual",
            occasion: "Work",
            memories: [],
            profile: makeStylistProfile(userId: userA),
            outfitClassification: classification
        )

        let message = PersonalStylistEngine.compose(
            input: input,
            weatherAdviceEnabled: false,
            saleMatchingEnabled: false
        )

        XCTAssertTrue(message.plainText.localizedCaseInsensitiveContains("verified casual wear context"))
        XCTAssertFalse(message.plainText.localizedCaseInsensitiveContains("detected watch"))
        XCTAssertFalse(message.plainText.contains("Style Memory:"))
    }

    func testSaleMatchingServiceDoesNotCallProviderWhenDisabled() async throws {
        let provider = SpyDealProvider(deals: [
            Deal(
                itemName: "Clean Leather Sneaker",
                category: "Shoes",
                colors: ["white"],
                salePrice: Decimal(110),
                originalPrice: Decimal(120),
                url: URL(string: "https://www.nike.com")
            )
        ])

        let matches = try await SaleMatchingService.matches(
            for: SaleMatchScanContext(
                detectedGarments: ["white sneakers"],
                colors: ["white"],
                detectedStyle: "Casual",
                occasion: "Casual"
            ),
            provider: provider,
            saleMatchingEnabled: false
        )

        XCTAssertTrue(matches.isEmpty)
        XCTAssertEqual(provider.callCount, 0)
    }

    func testSaleMatchingServiceUsesProviderOnlyWhenEnabled() async throws {
        let provider = SpyDealProvider(deals: [
            Deal(
                itemName: "Clean Leather Sneaker",
                category: "Shoes",
                colors: ["white"],
                salePrice: Decimal(110),
                originalPrice: Decimal(120),
                url: URL(string: "https://www.nike.com")
            )
        ])

        let matches = try await SaleMatchingService.matches(
            for: SaleMatchScanContext(
                detectedGarments: ["white sneakers"],
                colors: ["white"],
                detectedStyle: "Casual",
                occasion: "Casual"
            ),
            provider: provider,
            saleMatchingEnabled: true
        )

        XCTAssertEqual(provider.callCount, 1)
        XCTAssertEqual(matches.first?.retailerName, "www.nike.com")
        XCTAssertEqual(matches.first?.productName, "Clean Leather Sneaker")
    }

    func testMockDealProviderLoadsLocalJSONFixture() async throws {
        let provider = MockDealProvider(fixtureURL: mockDealFixtureURL())
        let deals = try await provider.currentDeals()

        XCTAssertEqual(deals.count, 2)
        XCTAssertEqual(deals.first?.itemName, "Oxford Shirt")
        XCTAssertEqual(deals.first?.colors, ["white"])
    }

    func testDealMessagesComplementMatchReferencesRealOutfitMemory() async throws {
        let provider = MockDealProvider(fixtureURL: mockDealFixtureURL())
        let now = fixedDate(year: 2026, month: 7, day: 7)
        var memory = makeBlackPantsAndShirtMemory()
        memory.scanDate = fixedDate(year: 2026, month: 7, day: 2)
        memory.styleScore = 85

        let messages = try await SaleMatchingService.dealMessages(
            for: [memory],
            provider: provider,
            saleMatchingEnabled: true,
            now: now,
            limit: 1
        )

        XCTAssertEqual(
            messages.first,
            "A white shirt just went on sale at Macy's — it would pair well with the black pants and black shirt you wore last Thursday."
        )
    }

    func testDealMessagesUpgradeMatchUsesLowLikedOrLowScoreStoredItem() async throws {
        let provider = MockDealProvider(fixtureURL: mockDealFixtureURL())
        let now = fixedDate(year: 2026, month: 7, day: 7)
        var shirtRecord = makeGarmentRecord(fingerprint: "category:shirt|colors:black|pattern:solid|fabric:cotton|brand:unknown")
        shirtRecord.garmentCategory = "shirt"
        shirtRecord.colors = ["black"]
        var memory = makeOutfitMemory(userId: userA, record: shirtRecord)
        memory.detectedGarments = ["shirt"]
        memory.colors = ["black"]
        memory.scanDate = fixedDate(year: 2026, month: 7, day: 2)
        memory.styleScore = 62
        memory.wasLiked = false

        let messages = try await SaleMatchingService.dealMessages(
            for: [memory],
            provider: provider,
            saleMatchingEnabled: true,
            now: now,
            limit: 2
        )

        XCTAssertTrue(messages.contains { message in
            message.contains("A black shirt just went on sale")
                && message.contains("it could upgrade the black shirt you wore last Thursday.")
        })
    }

    func testDealMessagesFlagOffDoesNotCallProvider() async throws {
        let provider = SpyDealProvider(deals: [
            Deal(
                itemName: "Oxford Shirt",
                category: "shirt",
                colors: ["white"],
                salePrice: Decimal(59),
                originalPrice: Decimal(89),
                url: URL(string: "https://www.macys.com/white-shirt")
            )
        ])

        let messages = try await SaleMatchingService.dealMessages(
            for: [makeBlackPantsAndShirtMemory()],
            provider: provider,
            saleMatchingEnabled: false
        )

        XCTAssertTrue(messages.isEmpty)
        XCTAssertEqual(provider.callCount, 0)
    }

    func testWeatherAdvisorOmitsSpecificAdviceWhenConfidenceIsLow() {
        let advice = WeatherAdvisor.advice(for: WeatherAdvisorInput(
            feelsLikeTemperature: 91,
            humidityPercent: 70,
            rainChancePercent: nil,
            windMph: nil,
            uvIndex: nil,
            condition: "Humid",
            confidence: 82
        ))

        XCTAssertNil(advice)
    }

    func testWeatherAdvisorExplainsHotHumidRecommendation() {
        let advice = WeatherAdvisor.advice(for: WeatherAdvisorInput(
            feelsLikeTemperature: 91,
            humidityPercent: 72,
            rainChancePercent: nil,
            windMph: nil,
            uvIndex: nil,
            condition: "Humid",
            confidence: 95
        ))

        XCTAssertEqual(advice?.message, "Keep this breathable and avoid jackets, extra layers, or heavy fabrics today.")
        XCTAssertTrue(advice?.reason.contains("91°F") == true)
        XCTAssertTrue(advice?.reason.contains("72%") == true)
    }

    func testWeatherAdvisorHotWeatherWithJacketFlagsSkipJacketAndDoesNotRecommendOne() {
        let advice = WeatherAdvisor.advice(for: WeatherAdvisorInput(
            feelsLikeTemperature: 88,
            humidityPercent: 65,
            rainChancePercent: nil,
            windMph: nil,
            uvIndex: nil,
            condition: "Hot",
            confidence: 95,
            detectedGarments: ["linen shirt", "black pants", "jacket"],
            activity: .walking,
            citySummary: "Hot in Miami"
        ))

        XCTAssertTrue(advice?.message.localizedCaseInsensitiveContains("skip the jacket") == true)
        XCTAssertFalse(advice?.message.localizedCaseInsensitiveContains("recommend jacket") == true)
        XCTAssertTrue(advice?.reason.contains("88°F") == true)
    }

    func testWeatherAdvisorUmbrellaTriggersAtExactlyFiftyPercentRain() {
        let advice = WeatherAdvisor.advice(for: WeatherAdvisorInput(
            feelsLikeTemperature: 72,
            humidityPercent: 60,
            rainChancePercent: 50,
            windMph: nil,
            uvIndex: nil,
            condition: "Cloudy",
            confidence: 95,
            detectedGarments: ["cotton shirt", "black pants"]
        ))

        XCTAssertEqual(advice?.message, "There is a 50% chance of rain today. Grab an umbrella before going out.")
    }

    func testWeatherAdvisorPossibleShowersOnlyForRainVulnerableOutfit() {
        let safeAdvice = WeatherAdvisor.advice(for: WeatherAdvisorInput(
            feelsLikeTemperature: 72,
            humidityPercent: 60,
            rainChancePercent: 40,
            windMph: nil,
            uvIndex: nil,
            condition: "Cloudy",
            confidence: 95,
            detectedGarments: ["cotton shirt", "black pants"]
        ))
        let vulnerableAdvice = WeatherAdvisor.advice(for: WeatherAdvisorInput(
            feelsLikeTemperature: 72,
            humidityPercent: 60,
            rainChancePercent: 40,
            windMph: nil,
            uvIndex: nil,
            condition: "Cloudy",
            confidence: 95,
            detectedGarments: ["suede loafers", "black pants"]
        ))

        XCTAssertNil(safeAdvice)
        XCTAssertTrue(vulnerableAdvice?.message.localizedCaseInsensitiveContains("possible showers") == true)
    }

    func testWeatherAdvisorWindOnlyMentionsLooseGarments() {
        let fittedAdvice = WeatherAdvisor.advice(for: WeatherAdvisorInput(
            feelsLikeTemperature: 65,
            humidityPercent: nil,
            rainChancePercent: nil,
            windMph: 27,
            uvIndex: nil,
            condition: "Windy",
            confidence: 95,
            detectedGarments: ["fitted shirt", "straight pants"]
        ))
        let looseAdvice = WeatherAdvisor.advice(for: WeatherAdvisorInput(
            feelsLikeTemperature: 65,
            humidityPercent: nil,
            rainChancePercent: nil,
            windMph: 27,
            uvIndex: nil,
            condition: "Windy",
            confidence: 95,
            detectedGarments: ["flowy skirt", "linen shirt"]
        ))

        XCTAssertNil(fittedAdvice)
        XCTAssertTrue(looseAdvice?.message.contains("27 mph") == true)
    }

    func testWeatherAdvisorColdRecommendsLayerOnlyWhenOuterwearMissing() {
        let missingOuterwear = WeatherAdvisor.advice(for: WeatherAdvisorInput(
            feelsLikeTemperature: 41,
            humidityPercent: nil,
            rainChancePercent: nil,
            windMph: nil,
            uvIndex: nil,
            condition: "Cold",
            confidence: 95,
            detectedGarments: ["shirt", "pants"]
        ))
        let hasOuterwear = WeatherAdvisor.advice(for: WeatherAdvisorInput(
            feelsLikeTemperature: 41,
            humidityPercent: nil,
            rainChancePercent: nil,
            windMph: nil,
            uvIndex: nil,
            condition: "Cold",
            confidence: 95,
            detectedGarments: ["coat", "pants"]
        ))

        XCTAssertTrue(missingOuterwear?.message.localizedCaseInsensitiveContains("outer layer") == true)
        XCTAssertNil(hasOuterwear)
    }

    func testPersonalStylistEngineContextContainsGuardrailsAndNoPII() {
        let input = PersonalStylistEngineInput(
            score: 90,
            scoreTier: "Great Match",
            scoreBreakdown: nil,
            detectedGarments: ["navy shirt"],
            colors: ["navy"],
            detectedStyle: "Casual",
            occasion: "Casual",
            weather: WeatherAdvisorAdvice(
                message: "There is a 50% chance of rain today. Grab an umbrella before going out.",
                reason: "Rain probability is 50%."
            ),
            memories: [],
            profile: makeStylistProfile(userId: "real-user-name"),
            dealMatches: []
        )

        let context = PersonalStylistEngine.context(input: input, saleMatchingEnabled: false)
        let payload = PersonalizationContextBuilder.buildPersonalStylistEnginePromptContext(context)

        XCTAssertTrue(payload.contains("You may only reference facts explicitly provided in the context object."))
        XCTAssertTrue(payload.contains("Do not invent weather conditions, garments, colors, dates, prices, or deals."))
        XCTAssertFalse(payload.contains("real-user-name"))
        XCTAssertFalse(payload.localizedCaseInsensitiveContains("latitude"))
        XCTAssertFalse(payload.localizedCaseInsensitiveContains("longitude"))
    }

    func testPersonalStylistEngineDoesNotModifyFixedScoreFixture() {
        let fixedScore = 82
        let input = makePersonalStylistInput(score: fixedScore)
        let engineInput = PersonalStylistEngineInput(
            score: input.score,
            scoreTier: input.scoreTier,
            scoreBreakdown: input.scoreBreakdown,
            detectedGarments: input.detectedGarments,
            colors: input.colors,
            detectedStyle: input.detectedStyle,
            occasion: input.occasion,
            memories: input.memories,
            profile: input.profile,
            dealMatches: []
        )

        let context = PersonalStylistEngine.context(
            input: engineInput,
            weatherAdviceEnabled: false,
            saleMatchingEnabled: false
        )

        XCTAssertEqual(input.score, fixedScore)
        XCTAssertEqual(context.score, fixedScore)
        XCTAssertTrue(context.allowedMessages.joined(separator: " ").contains("82/100"))
    }

    func testWeatherAdvisorRainRecommendationUsesRealRainData() {
        let advice = WeatherAdvisor.advice(for: WeatherAdvisorInput(
            feelsLikeTemperature: 78,
            humidityPercent: 62,
            rainChancePercent: 70,
            windMph: nil,
            uvIndex: nil,
            condition: "Rain",
            confidence: 95
        ))

        XCTAssertEqual(advice?.message, "There is a 70% chance of rain today. Grab an umbrella before going out.")
        XCTAssertTrue(advice?.reason.contains("70%") == true)
    }

    func testSaleMatchingFlagOnUsesOnlyProvidedDeal() {
        let deal = PersonalStylistDealMatch(
            productName: "Clean Leather Sneaker",
            retailerName: "Nike",
            category: "Shoes",
            salePrice: "$110.00",
            reason: "Matches the scanned shoe category."
        )
        let input = makePersonalStylistInput(score: 89, dealMatches: [deal])

        let message = PersonalStylistIntelligenceBuilder.buildMessage(
            input: input,
            weatherAdviceEnabled: false,
            saleMatchingEnabled: true
        )

        let dealSection = message.sections.first { $0.source == .shoppingDeals }
        XCTAssertNotNil(dealSection)
        XCTAssertTrue(dealSection?.body.contains("Clean Leather Sneaker") == true)
        XCTAssertTrue(dealSection?.body.contains("Nike") == true)
        XCTAssertFalse(dealSection?.body.contains("Amazon") == true)
    }

    func testHistoryRecallOmitsWhenNoHistoryOrLearnedPreference() {
        var input = makePersonalStylistInput(score: 80)
        input = PersonalStylistIntelligenceInput(
            score: input.score,
            scoreTier: input.scoreTier,
            scoreBreakdown: input.scoreBreakdown,
            detectedGarments: input.detectedGarments,
            colors: input.colors,
            detectedStyle: input.detectedStyle,
            occasion: input.occasion,
            weather: nil,
            memories: [],
            profile: makeStylistProfile(userId: userA),
            dealMatches: []
        )

        let message = PersonalStylistIntelligenceBuilder.buildMessage(
            input: input,
            weatherAdviceEnabled: false,
            saleMatchingEnabled: false
        )

        XCTAssertFalse(message.sections.contains { $0.source == .history })
    }

    func testHistoryRecallUsesMatchingPastOutfitFacts() {
        var memory = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "shirt-navy-solid"))
        memory.detectedGarments = ["shirt", "pants"]
        memory.colors = ["navy", "black"]
        memory.detectedStyle = "Smart Casual"
        memory.styleScore = 93
        memory.wasLiked = true
        memory.wouldWearAgain = true
        memory.outfitFingerprint = "outfit-v4|same-outfit"
        memory.imageDigest = "same-image"

        let input = makePersonalStylistInput(
            score: 86,
            memories: [memory],
            outfitFingerprint: "outfit-v4|same-outfit",
            imageDigest: "same-image"
        )
        let message = PersonalStylistIntelligenceBuilder.buildMessage(
            input: input,
            weatherAdviceEnabled: false,
            saleMatchingEnabled: false
        )

        let history = message.sections.first { $0.source == .history }
        XCTAssertNotNil(history)
        XCTAssertTrue(history?.body.contains("score: 93") == true)
        XCTAssertTrue(history?.body.localizedCaseInsensitiveContains("navy shirt") == true)
    }

    func testOutfitRecallServiceFormatsRelativeDatesAndReturnsNilWithoutMatch() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 7))!
        var memory = makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "shirt-black-solid"))
        memory.scanDate = calendar.date(from: DateComponents(year: 2026, month: 7, day: 3))!
        memory.detectedGarments = ["shirt"]
        memory.colors = ["black"]
        memory.detectedStyle = "Smart Casual"
        memory.styleScore = 85
        memory.outfitFingerprint = "outfit-v4|black-shirt-outfit"
        memory.imageDigest = "black-shirt-image"

        let match = OutfitRecallService.recallFact(
            for: OutfitRecallScanContext(
                detectedGarments: ["shirt"],
                colors: ["black"],
                detectedStyle: "Smart Casual",
                outfitFingerprint: "outfit-v4|black-shirt-outfit",
                imageDigest: "black-shirt-image"
            ),
            memories: [memory],
            now: now
        )
        let noMatch = OutfitRecallService.recallFact(
            for: OutfitRecallScanContext(
                detectedGarments: ["shoe"],
                colors: ["white"],
                detectedStyle: "Athletic",
                outfitFingerprint: "outfit-v4|different-outfit",
                imageDigest: "different-image"
            ),
            memories: [memory],
            now: now
        )

        XCTAssertEqual(match?.text, "You wore black shirt last Thursday (score: 85).")
        XCTAssertNil(noMatch)
    }

    func testOutfitRecallServiceReturnsNilWithEmptyMemory() {
        let recall = OutfitRecallService.recallFact(
            for: OutfitRecallScanContext(
                detectedGarments: ["shirt"],
                colors: ["black"],
                detectedStyle: "Casual"
            ),
            memories: []
        )

        XCTAssertNil(recall)
    }

    func testOutfitRecallServiceCanIncrementSeenCountersThroughStoreMerge() {
        let store = OutfitMemoryStore(defaults: defaults, userId: userA)
        var record = makeGarmentRecord(fingerprint: "category:shirt|colors:black|pattern:solid|fabric:unknown|brand:unknown")
        record.garmentCategory = "shirt"
        record.colors = ["black"]
        var memory = makeOutfitMemory(userId: userA, record: record)
        memory.detectedGarments = ["shirt"]
        memory.colors = ["black"]
        memory.detectedStyle = "Casual"
        memory.outfitFingerprint = "outfit-v4|counter-outfit"
        memory.imageDigest = "counter-image"
        store.addOrMergeScan(memory)

        let incoming = GarmentRecord(
            garmentCategory: "shirt",
            itemFingerprint: "category:shirt|colors:black|pattern:solid|fabric:unknown|brand:unknown",
            colors: ["black"],
            styleTags: ["Casual"],
            colorConfidence: 80,
            sourceScanIds: ["scan-2"]
        )

        _ = OutfitRecallService.recallFact(
            for: OutfitRecallScanContext(
                detectedGarments: ["shirt"],
                colors: ["black"],
                detectedStyle: "Casual",
                garmentRecords: [incoming],
                outfitFingerprint: "outfit-v4|counter-outfit",
                imageDigest: "counter-image"
            ),
            store: store,
            incrementCounters: true
        )

        XCTAssertEqual(store.garmentRecords.first?.timesSeen, 2)
    }

    private func makePersonalStylistInput(
        score: Int,
        weather: WeatherContextRecommendation? = nil,
        memories: [OutfitMemory] = [],
        dealMatches: [PersonalStylistDealMatch] = [],
        outfitFingerprint: String? = nil,
        imageDigest: String? = nil
    ) -> PersonalStylistIntelligenceInput {
        PersonalStylistIntelligenceInput(
            score: score,
            scoreTier: "Good Match",
            scoreBreakdown: OutfitScoreBreakdown(
                colorHarmony: 23,
                patternBalance: 18,
                fitQuality: 21,
                occasionMatch: 17,
                accessoryUse: 8
            ),
            detectedGarments: ["navy shirt", "black pants", "white sneakers"],
            colors: ["navy", "black", "white"],
            detectedStyle: "Smart Casual",
            occasion: "Casual",
            weather: weather,
            memories: memories,
            profile: makeStylistProfile(userId: userA),
            dealMatches: dealMatches,
            outfitFingerprint: outfitFingerprint,
            imageDigest: imageDigest
        )
    }

    private func makeGarmentRecord(
        fingerprint: String,
        sourceScanIds: [String] = ["scan-1"]
    ) -> GarmentRecord {
        GarmentRecord(
            garmentCategory: "pants",
            itemFingerprint: fingerprint,
            brand: nil,
            fit: "regular",
            fabric: "cotton",
            pattern: "solid",
            colors: ["black"],
            styleTags: ["casual"],
            colorConfidence: 90,
            timesSeen: 1,
            timesWorn: 0,
            sourceScanIds: sourceScanIds
        )
    }

    private func makeOutfitMemory(userId: String, record: GarmentRecord) -> OutfitMemory {
        OutfitMemory(
            id: UUID(),
            userId: userId,
            scanDate: Date(),
            detectedGarments: [record.garmentCategory],
            colors: record.colors,
            detectedStyle: "Casual",
            styleScore: 82,
            occasion: .casual,
            wasWorn: nil,
            wasLiked: nil,
            feedbackTimestamp: nil,
            dislikeReason: nil,
            wouldWearAgain: nil,
            receivedCompliments: nil,
            isFavorite: false,
            timesWorn: 0,
            garmentRecords: [record]
        )
    }

    private func markFeedbackFirstSessionSeen(for userId: String) {
        let key = PersonalStylistStorage.scopedKey("personalStylistFeedbackFirstSessionSeen", userID: userId)
        defaults.set(true, forKey: key)
    }

    private func mockDealFixtureURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/mock_deals.json")
    }

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
    }

    private func retailerConfigFixtureURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("StyleMatchAI/Shopping/RetailerConfig.json")
    }

    private func fixedDate(year: Int, month: Int, day: Int) -> Date {
        fixedDate(year: year, month: month, day: day, hour: 12)
    }

    private func fixedDate(year: Int, month: Int, day: Int, hour: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func makeBlackPantsAndShirtMemory() -> OutfitMemory {
        var pants = makeGarmentRecord(fingerprint: "category:pants|colors:black|pattern:solid|fabric:cotton|brand:unknown")
        pants.garmentCategory = "pants"
        pants.colors = ["black"]

        var shirt = makeGarmentRecord(fingerprint: "category:shirt|colors:black|pattern:solid|fabric:cotton|brand:unknown")
        shirt.garmentCategory = "shirt"
        shirt.colors = ["black"]

        var memory = makeOutfitMemory(userId: userA, record: pants)
        memory.detectedGarments = ["pants", "shirt"]
        memory.colors = ["black", "black"]
        memory.garmentRecords = [pants, shirt]
        return memory
    }

    private func makeCompleteLookAnalysis(
        colorHarmony: Int,
        patternBalance: Int,
        fitQuality: Int,
        accessoryUse: Int,
        palette: [String],
        occasionFit: String = "Casual"
    ) -> OutfitAnalysisResult {
        OutfitAnalysisResult(
            score: 82,
            scoreBreakdown: OutfitScoreBreakdown(
                colorHarmony: colorHarmony,
                patternBalance: patternBalance,
                fitQuality: fitQuality,
                occasionMatch: 18,
                accessoryUse: accessoryUse
            ),
            colorMatch: "Palette match",
            occasionFit: occasionFit,
            styleBalance: "Balanced",
            colorHarmony: "Coordinated",
            styleCoordination: "Clean",
            formality: "casual",
            seasonalMatch: "Mild",
            summary: "Synthetic scan summary",
            outfitDescription: "Navy shirt and jeans",
            detectedClothingItems: ["shirt", "jeans"],
            colorPalette: palette,
            environment: "indoor",
            imageQuality: "clear",
            skinToneStyleNote: "No skin-tone recommendation needed.",
            suggestions: ["Add a finishing accessory."],
            recommendations: []
        )
    }

    private func makeAffiliateProduct(
        id: String,
        name: String = "Test Product",
        category: ProductCategory = .clothing,
        subcategory: String = "shirt",
        colors: [String] = ["white"],
        retailer: Retailer = Retailer(name: "Macy's", trackingID: "PENDING-APPROVAL", trackingParamName: "aff", disclosureName: "Macy's"),
        affiliateURL: URL = URL(string: "https://www.macys.com/test-product")!,
        price: Decimal? = Decimal(80),
        salePrice: Decimal? = nil,
        saleEndsAt: Date? = nil,
        tags: [String] = [],
        sizes: [String]? = nil,
        priceRange: ClosedRange<Decimal>? = nil,
        occasionTags: [String]? = nil,
        brand: String? = nil,
        retailerID: String? = nil
    ) -> AffiliateProduct {
        AffiliateProduct(
            id: id,
            name: name,
            category: category,
            subcategory: subcategory,
            colors: colors,
            sizes: sizes,
            priceRange: priceRange,
            occasionTags: occasionTags,
            brand: brand,
            imageURL: URL(string: "https://www.example.com/image.jpg")!,
            retailerID: retailerID,
            retailer: retailer,
            affiliateURL: affiliateURL,
            price: price,
            salePrice: salePrice,
            saleEndsAt: saleEndsAt,
            availableColors: nil,
            customerRating: nil,
            reviewCount: nil,
            estimatedShippingText: nil,
            tags: tags,
            genderPresentation: nil
        )
    }

    private func makeSupportedStores() -> [SupportedStore] {
        [
            SupportedStore(id: "nike", name: "Nike", domains: ["nike.com"], categories: [.clothing, .shoes, .accessories], affiliateNetwork: "TBD", apiStatus: "affiliate-placeholder", isEnabled: true),
            SupportedStore(id: "amazon", name: "Amazon", domains: ["amazon.com"], categories: ProductCategory.allCases, affiliateNetwork: "Amazon Associates", apiStatus: "approved", isEnabled: true),
            SupportedStore(id: "macys", name: "Macy's", domains: ["macys.com"], categories: [.clothing, .shoes, .accessories], affiliateNetwork: "Impact", apiStatus: "approved", isEnabled: true),
            SupportedStore(id: "disabled", name: "Disabled", domains: ["disabled.example"], categories: [.clothing], affiliateNetwork: nil, apiStatus: "disabled", isEnabled: false)
        ]
    }

    private func directoryProduct(id: String, retailerID: String, retailerName: String) -> AffiliateProduct {
        AffiliateProduct(
            id: id,
            name: "Directory Product",
            category: .clothing,
            subcategory: "tops",
            colors: ["navy"],
            retailerID: retailerID,
            retailer: Retailer(
                name: retailerName,
                trackingID: AffiliateLinkBuilder.pendingApprovalTrackingID,
                trackingParamName: "tag",
                disclosureName: retailerName
            ),
            affiliateURL: URL(string: "https://www.example.com/product")!,
            price: Decimal(20),
            salePrice: nil,
            saleEndsAt: nil,
            availableColors: nil,
            customerRating: nil,
            reviewCount: nil,
            estimatedShippingText: nil,
            tags: [],
            genderPresentation: nil
        )
    }

    private func makeResilientCatalogProvider(
        cacheDirectory: URL,
        fallback: ProductCatalogProvider
    ) -> RemoteCatalogProvider {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CatalogTestURLProtocol.self]
        return RemoteCatalogProvider(
            baseURL: URL(string: "https://proxy.example.com")!,
            cacheDirectory: cacheDirectory,
            fallbackProvider: fallback,
            urlSession: URLSession(configuration: configuration),
            requestTimeout: RemoteCatalogProvider.defaultRequestTimeout
        )
    }

    private func temporaryCatalogDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func catalogTestProduct(
        id: String,
        affiliateURL: URL = URL(string: "https://www.example.com/products/safe")!,
        availableCountries: [String]? = ["*"],
        availability: String? = "in_stock"
    ) -> AffiliateProduct {
        AffiliateProduct(
            id: id,
            name: "Catalog Product",
            category: .clothing,
            subcategory: "tops",
            colors: ["navy"],
            retailer: Retailer(
                name: "Example",
                trackingID: AffiliateLinkBuilder.pendingApprovalTrackingID,
                trackingParamName: "tag",
                disclosureName: "Example"
            ),
            affiliateURL: affiliateURL,
            price: Decimal(20),
            salePrice: nil,
            saleEndsAt: nil,
            availableCountries: availableCountries,
            availability: availability,
            availableColors: nil,
            customerRating: nil,
            reviewCount: nil,
            estimatedShippingText: nil,
            tags: ["navy", "shirt"],
            genderPresentation: nil
        )
    }

    private func remoteCatalogPayload(id: String) -> Data {
        remoteCatalogPayload(ids: [id])
    }

    private func remoteCatalogPayload(ids: [String], availableCountries: [String] = ["*"]) -> Data {
        let countries = availableCountries.map { "\"\($0)\"" }.joined(separator: ", ")
        let productObjects = ids.map { id in
            """
            {
              "id": "\(id)",
              "store_id": "example",
              "store_name": "Example",
              "name": "Remote Catalog Product \(id)",
              "image_url": null,
              "category": "tops",
              "brand": "Example",
              "price_cents": 2000,
              "sale_price_cents": null,
              "sale_ends_at": null,
              "currency": "USD",
              "country_code": "US",
              "available_countries": [\(countries)],
              "availability": "in_stock",
              "tags": ["navy", "shirt"],
              "buy_url": "https://proxy.example.com/go/\(id)"
            }
            """
        }.joined(separator: ",")
        return Data("""
        {
          "products": [
            \(productObjects)
          ],
          "next_cursor": null,
          "disclosure": "Test disclosure"
        }
        """.utf8)
    }

    private func makeStylistProfile(userId: String) -> StylistProfile {
        StylistProfile(
            id: UUID(),
            userId: userId,
            favoriteColors: [],
            dislikedColors: [],
            favoriteBrands: [],
            preferredFit: .unset,
            budgetRange: BudgetRange(minPrice: 50, maxPrice: 200, preferredTier: "Mid"),
            climate: "Mild",
            workDressCode: "Smart casual",
            bodyProportions: nil,
            clothingSizes: ClothingSizes(),
            stylePreferencesLearned: [:],
            createdAt: Date(),
            lastUpdatedAt: Date(),
            totalScansCompleted: 0,
            profileConfidenceScore: 20
        )
    }

    private func seedFounderSizeDefaults() {
        defaults.set("Men", forKey: "sizeCategory")
        defaults.set("L", forKey: "shirtSize")
        defaults.set("Men 36x36", forKey: "pantsSize")
        defaults.set("36", forKey: "waistSize")
        defaults.set("36", forKey: "inseamLength")
        defaults.set("10", forKey: "shoeSize")
        defaults.set("Regular", forKey: "fitPreference")
    }

    func testGreetingBuilderDoesNotUsePlaceholderNameForEmptyProfile() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let morning = Date(timeIntervalSince1970: 1_704_094_800) // 2024-01-01 09:00:00 UTC

        let emptyGreeting = StyleMatchGreetingBuilder.greetingLine(date: morning, calendar: calendar, storedName: "")
        let placeholderGreeting = StyleMatchGreetingBuilder.greetingLine(date: morning, calendar: calendar, storedName: "Style Match Pro User")
        let leakedNameGreeting = StyleMatchGreetingBuilder.greetingLine(date: morning, calendar: calendar, storedName: ["Saba", "stine"].joined())

        XCTAssertEqual(emptyGreeting, "Good Morning")
        XCTAssertEqual(placeholderGreeting, "Good Morning")
        XCTAssertEqual(leakedNameGreeting, "Good Morning")
        XCTAssertFalse(emptyGreeting.localizedCaseInsensitiveContains(["Saba", "stine"].joined()))
        XCTAssertFalse(placeholderGreeting.localizedCaseInsensitiveContains(["Saba", "stine"].joined()))
        XCTAssertFalse(leakedNameGreeting.localizedCaseInsensitiveContains(["Saba", "stine"].joined()))
    }

    func testDefaultProfileDoesNotInheritGlobalProfileName() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let morning = Date(timeIntervalSince1970: 1_704_094_800) // 2024-01-01 09:00:00 UTC
        defaults.set(["Saba", "stine"].joined(), forKey: "profileName")

        let newUserProfile = ProfileStore(defaults: defaults, userId: userB).currentProfile

        XCTAssertNil(newUserProfile.givenName)
        XCTAssertEqual(
            StyleMatchGreetingBuilder.greetingLine(date: morning, calendar: calendar, storedName: newUserProfile.givenName),
            "Good Morning"
        )
    }

    func testFounderDefaultsMigrationClearsExactFingerprintWithoutSaveMarker() {
        seedFounderSizeDefaults()
        defaults.set("Black, white, navy", forKey: "favoriteColors")
        defaults.set("Ralph Lauren, Nike, Levi's", forKey: "favoriteBrands")

        XCTAssertTrue(FounderProfileDefaultsMigration.matchesFounderFingerprint(defaults: defaults))
        XCTAssertTrue(FounderProfileDefaultsMigration.run(defaults: defaults, userID: userA))

        XCTAssertNil(defaults.object(forKey: "sizeCategory"))
        XCTAssertNil(defaults.object(forKey: "shirtSize"))
        XCTAssertNil(defaults.object(forKey: "pantsSize"))
        XCTAssertNil(defaults.object(forKey: "waistSize"))
        XCTAssertNil(defaults.object(forKey: "inseamLength"))
        XCTAssertNil(defaults.object(forKey: "shoeSize"))
        XCTAssertNil(defaults.object(forKey: "fitPreference"))
        XCTAssertNil(defaults.object(forKey: "favoriteColors"))
        XCTAssertNil(defaults.object(forKey: "favoriteBrands"))
        XCTAssertTrue(defaults.bool(forKey: FounderProfileDefaultsMigration.migrationFlag))
    }

    func testFounderDefaultsMigrationPreservesRealSavedProfile() {
        seedFounderSizeDefaults()
        defaults.set("2026-07-09T09:00:00Z", forKey: FounderProfileDefaultsMigration.profileLastSavedAtKey)
        defaults.set("Black, white, navy", forKey: "favoriteColors")
        defaults.set("Ralph Lauren, Nike, Levi's", forKey: "favoriteBrands")

        XCTAssertTrue(FounderProfileDefaultsMigration.matchesFounderFingerprint(defaults: defaults))
        XCTAssertFalse(FounderProfileDefaultsMigration.run(defaults: defaults, userID: userA))

        XCTAssertEqual(defaults.string(forKey: "sizeCategory"), "Men")
        XCTAssertEqual(defaults.string(forKey: "shirtSize"), "L")
        XCTAssertEqual(defaults.string(forKey: "pantsSize"), "Men 36x36")
        XCTAssertEqual(defaults.string(forKey: "waistSize"), "36")
        XCTAssertEqual(defaults.string(forKey: "inseamLength"), "36")
        XCTAssertEqual(defaults.string(forKey: "shoeSize"), "10")
        XCTAssertEqual(defaults.string(forKey: "fitPreference"), "Regular")
        XCTAssertEqual(defaults.string(forKey: "favoriteColors"), "Black, white, navy")
        XCTAssertEqual(defaults.string(forKey: "favoriteBrands"), "Ralph Lauren, Nike, Levi's")
        XCTAssertTrue(defaults.bool(forKey: FounderProfileDefaultsMigration.migrationFlag))
    }

    func testFounderDefaultsMigrationPreservesNonExactProfileValues() {
        seedFounderSizeDefaults()
        defaults.set("Men 36x32", forKey: "pantsSize")

        XCTAssertFalse(FounderProfileDefaultsMigration.matchesFounderFingerprint(defaults: defaults))
        XCTAssertFalse(FounderProfileDefaultsMigration.run(defaults: defaults, userID: userA))

        XCTAssertEqual(defaults.string(forKey: "pantsSize"), "Men 36x32")
        XCTAssertEqual(defaults.string(forKey: "waistSize"), "36")
        XCTAssertEqual(defaults.string(forKey: "inseamLength"), "36")
    }

    func testFounderDefaultsMigrationRunsOnlyOnce() {
        seedFounderSizeDefaults()

        XCTAssertTrue(FounderProfileDefaultsMigration.run(defaults: defaults, userID: userA))
        defaults.set("Men 36x36", forKey: "pantsSize")
        defaults.set("36", forKey: "waistSize")
        defaults.set("36", forKey: "inseamLength")

        XCTAssertFalse(FounderProfileDefaultsMigration.run(defaults: defaults, userID: userA))
        XCTAssertEqual(defaults.string(forKey: "pantsSize"), "Men 36x36")
    }

    func testProfileStoreFreshInstallUsesBlankProfileAndZeroCompleteness() {
        let profile = ProfileStore(defaults: defaults, userId: userA, snapshotRoot: snapshotTestRoot).currentProfile

        XCTAssertTrue(profile.favoriteColors.isEmpty)
        XCTAssertTrue(profile.favoriteBrands.isEmpty)
        XCTAssertNil(profile.clothingSizes.shirtSize)
        XCTAssertNil(profile.clothingSizes.pantSize)
        XCTAssertNil(profile.clothingSizes.shoeSize)
        XCTAssertNil(profile.clothingSizes.jacketSize)
        XCTAssertNil(profile.clothingSizes.dressSize)
        XCTAssertEqual(profile.preferredFit, .unset)
        XCTAssertEqual(profile.budgetRange.minPrice, BudgetRange.neutral.minPrice)
        XCTAssertEqual(profile.budgetRange.maxPrice, BudgetRange.neutral.maxPrice)
        XCTAssertEqual(profile.budgetRange.preferredTier, BudgetRange.neutral.preferredTier)
        XCTAssertTrue(profile.climate.isEmpty)
        XCTAssertTrue(profile.workDressCode.isEmpty)
        XCTAssertEqual(ProfileStore.profileCompletenessPercentage(profile), 0)
    }

    func testProfileStoreKeepsSavedProfileThroughFounderMigration() {
        seedFounderSizeDefaults()
        defaults.set("Navy, Olive", forKey: "favoriteColors")
        defaults.set("Nike, Levi's", forKey: "favoriteBrands")
        defaults.set("$50 - $200", forKey: "shoppingBudget")
        defaults.set("2026-07-09T09:00:00Z", forKey: FounderProfileDefaultsMigration.profileLastSavedAtKey)

        let profile = ProfileStore(defaults: defaults, userId: userA).currentProfile

        XCTAssertEqual(profile.clothingSizes.shirtSize, "L")
        XCTAssertEqual(profile.clothingSizes.pantSize, "Men 36x36")
        XCTAssertEqual(profile.clothingSizes.shoeSize, "10")
        XCTAssertEqual(profile.preferredFit, .regular)
        XCTAssertEqual(profile.favoriteColors, ["Navy", "Olive"])
        XCTAssertEqual(profile.favoriteBrands, ["Nike", "Levi's"])
        XCTAssertEqual(profile.budgetRange.minPrice, 50)
        XCTAssertEqual(profile.budgetRange.maxPrice, 200)
        XCTAssertEqual(defaults.string(forKey: "sizeCategory"), "Men")
        XCTAssertEqual(defaults.string(forKey: "waistSize"), "36")
        XCTAssertEqual(defaults.string(forKey: "inseamLength"), "36")
    }

    func testProfileStorePrefersActiveProfileOverStaleSnapshotDuringUpgrade() throws {
        let userID = "upgrade-profile-\(UUID().uuidString)"
        defer {
            PersonalStylistSnapshotStore.deleteData(
                store: "StylistProfile",
                userID: userID,
                rootDirectory: snapshotTestRoot
            )
        }

        var staleProfile = ProfileStore(defaults: defaults, userId: userID, snapshotRoot: snapshotTestRoot).currentProfile
        staleProfile.favoriteColors = ["Navy"]
        staleProfile.favoriteBrands = ["Nike"]
        let staleData = try JSONEncoder().encode(staleProfile)
        if case .failure(let error) = PersonalStylistSnapshotStore.saveData(
            staleData,
            store: "StylistProfile",
            userID: userID,
            rootDirectory: snapshotTestRoot
        ) {
            XCTFail("Could not create the stale profile snapshot: \(error)")
        }

        var activeProfile = staleProfile
        activeProfile.favoriteColors = ["Navy", "Olive"]
        activeProfile.favoriteBrands = ["Nike", "Levi's"]
        let activeKey = PersonalStylistStorage.scopedKey(PersonalStylistStorage.legacyProfileKey, userID: userID)
        defaults.set(try JSONEncoder().encode(activeProfile), forKey: activeKey)

        let reloaded = ProfileStore(defaults: defaults, userId: userID, snapshotRoot: snapshotTestRoot).currentProfile
        XCTAssertEqual(reloaded.favoriteColors, activeProfile.favoriteColors)
        XCTAssertEqual(reloaded.favoriteBrands, activeProfile.favoriteBrands)
    }

    func testProfileStoreSavedSizeMutationPersistsAcrossReload() {
        defaults.set("2026-07-09T09:00:00Z", forKey: FounderProfileDefaultsMigration.profileLastSavedAtKey)

        let store = ProfileStore(defaults: defaults, userId: userA, snapshotRoot: snapshotTestRoot)
        var profile = store.currentProfile
        profile.clothingSizes = ClothingSizes(shirtSize: "L", pantSize: "Men 36x36", shoeSize: "10")
        profile.preferredFit = .regular
        profile.declaredUndertone = .cool
        store.currentProfile = profile
        store.save()

        var reloaded = ProfileStore(defaults: defaults, userId: userA).currentProfile
        XCTAssertEqual(reloaded.clothingSizes.pantSize, "Men 36x36")
        XCTAssertEqual(reloaded.declaredUndertone, .cool)

        reloaded.clothingSizes = ClothingSizes(shirtSize: "L", pantSize: "Men 34x34", shoeSize: "10")
        reloaded.preferredFit = .tailored
        reloaded.declaredUndertone = nil
        let mutationStore = ProfileStore(defaults: defaults, userId: userA)
        mutationStore.currentProfile = reloaded
        mutationStore.save()

        let finalProfile = ProfileStore(defaults: defaults, userId: userA).currentProfile
        XCTAssertEqual(finalProfile.clothingSizes.pantSize, "Men 34x34")
        XCTAssertEqual(finalProfile.clothingSizes.shirtSize, "L")
        XCTAssertEqual(finalProfile.clothingSizes.shoeSize, "10")
        XCTAssertEqual(finalProfile.preferredFit, .tailored)
        XCTAssertNil(finalProfile.declaredUndertone)
        XCTAssertEqual(defaults.string(forKey: FounderProfileDefaultsMigration.profileLastSavedAtKey), "2026-07-09T09:00:00Z")
    }

    func testColorFitProfileIsManualClearableAndScoringIsUntouched() throws {
        let profileSource = try projectSource("StyleMatchAI/ProfileView.swift")
        let scanSource = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(profileSource.contains("DisclosureGroup(\"Color & Fit\""))
        XCTAssertTrue(profileSource.contains("clearColorAndFitProfile()"))
        XCTAssertTrue(profileSource.contains("profile.declaredUndertone = DeclaredUndertone.fromProfileInput(draft.declaredUndertone)"))
        XCTAssertFalse(profileSource.contains("@AppStorage(\"weight\")"))
        XCTAssertFalse(profileSource.contains("profileDraftField(\"Weight\""))
        XCTAssertFalse(profileSource.localizedCaseInsensitiveContains("body type"))
        guard let scoreStart = scanSource.range(of: "private func calculateStyleScore(\n        validation:"),
              let scoreEnd = scanSource.range(of: "private func scoreComponents", range: scoreStart.upperBound..<scanSource.endIndex) else {
            XCTFail("Expected to locate calculateStyleScore block")
            return
        }
        let scoreBlock = String(scanSource[scoreStart.lowerBound..<scoreEnd.lowerBound])
        XCTAssertFalse(scoreBlock.contains("declaredUndertone"))
        XCTAssertFalse(scoreBlock.contains("ProfileStore"))
    }

    func testProfileNavigationKeepsExistingSettingsInPlaceAndSupportsRequiredSearchTerms() throws {
        let profileSource = try projectSource("StyleMatchAI/ProfileView.swift")

        XCTAssertTrue(profileSource.contains("TextField(\"Search profile settings\""))
        XCTAssertTrue(profileSource.contains("case privacy"))
        XCTAssertTrue(profileSource.contains("return [\"privacy\", \"memory\", \"data\", \"delete\", \"shared links\"]"))
        XCTAssertTrue(profileSource.contains("private func select(_ section: ProfileNavigationSection"))
        XCTAssertTrue(profileSource.contains("isSearchFocused = false"))
        XCTAssertTrue(profileSource.contains("selectedSection = section"))
        XCTAssertTrue(profileSource.contains("ScrollViewReader"))
        XCTAssertTrue(profileSource.contains("ProfileNavigationControls"))
        XCTAssertTrue(profileSource.contains("ProfileNavigationSection"))
        for chip in ["Overview", "Account", "Style", "Sizes", "Voice", "Weather", "Occasion", "Style Friends", "Privacy"] {
            XCTAssertTrue(profileSource.contains("return \"\(chip)\""))
        }
        for term in ["apple", "cloud sync", "style dna", "consultation", "voice", "weather", "occasion", "shirt", "pants", "waist", "inseam", "shoe", "fit", "rise", "brands", "stores", "budget", "colors", "privacy"] {
            XCTAssertTrue(profileSource.localizedCaseInsensitiveContains("\"\(term)\""))
        }
        XCTAssertTrue(profileSource.contains("DisclosureGroup(\"Size Profile\""))
        XCTAssertTrue(profileSource.contains("DisclosureGroup(\"Weather Planning\""))
        XCTAssertTrue(profileSource.contains("DisclosureGroup(\"Occasion Styling\""))
        XCTAssertTrue(profileSource.contains("DisclosureGroup(\"Style Friends\""))
        XCTAssertTrue(profileSource.contains(".id(ProfileNavigationSection.styleFriends)"))
        XCTAssertTrue(profileSource.contains(".profileSectionActivationAnchor(.styleFriends)"))
        XCTAssertTrue(profileSource.contains("if section == .styleFriends"))
        XCTAssertTrue(profileSource.contains("styleFriendsHomeSearchRoute = .styleFriends"))
        XCTAssertTrue(profileSource.contains("isShowingStyleFriends = true"))
        XCTAssertTrue(profileSource.contains("Label(\"Style Friends\", systemImage: \"person.2.fill\")"), "The Privacy/Data Control entry must remain available.")
        XCTAssertTrue(profileSource.contains("Label(\"Save Profile\""))
    }

    func testProfileSectionSelectorKeepsTheSelectedChipVisibleAndAccessible() throws {
        let profileSource = try projectSource("StyleMatchAI/ProfileView.swift")
        guard let selectorStart = profileSource.range(of: "private struct ProfileNavigationControls: View"),
              let selectorEnd = profileSource.range(of: "private struct ProfileFormSections", range: selectorStart.upperBound..<profileSource.endIndex) else {
            XCTFail("Expected ProfileNavigationControls source block")
            return
        }
        let selector = String(profileSource[selectorStart.lowerBound..<selectorEnd.lowerBound])

        XCTAssertTrue(selector.contains("ScrollViewReader { navigationProxy in"))
        XCTAssertTrue(selector.contains("ScrollViewReader { navigationProxy in\n                VStack"))
        XCTAssertTrue(selector.contains("ScrollView(.horizontal, showsIndicators: false)"))
        XCTAssertEqual(selector.components(separatedBy: "select(section, using: navigationProxy)").count - 1, 2)
        XCTAssertTrue(selector.contains(".id(section)"))
        XCTAssertTrue(selector.contains("scrollToSelectedSection(navigationProxy, section: selectedSection, animated: false)"))
        XCTAssertTrue(selector.contains(".onChange(of: selectedSection) { section in"))
        XCTAssertTrue(selector.contains("proxy.scrollTo(section, anchor: .leading)"))
        XCTAssertTrue(selector.contains("Text(section.title)"))
        XCTAssertTrue(selector.contains(".fixedSize(horizontal: true, vertical: false)"))
        XCTAssertFalse(selector.contains(".lineLimit(1)"))
        XCTAssertFalse(selector.contains(".minimumScaleFactor"))
        XCTAssertTrue(selector.contains(".frame(minHeight: 44)"))
        XCTAssertTrue(selector.contains("Image(systemName: \"checkmark\")"))
        XCTAssertTrue(selector.contains(".accessibilityLabel(section.title)"))
        XCTAssertTrue(selector.contains(".accessibilityValue(isSelected ? \"Selected\" : \"Not selected\")"))
        XCTAssertTrue(selector.contains(".accessibilityAddTraits(isSelected ? .isSelected : [])"))
        XCTAssertFalse(selector.contains("offset(x:"))

        guard let sectionStart = profileSource.range(of: "private enum ProfileNavigationSection"),
              let sectionEnd = profileSource.range(of: "private struct ProfileNavigationControls", range: sectionStart.upperBound..<profileSource.endIndex) else {
            XCTFail("Expected ProfileNavigationSection source block")
            return
        }
        let sectionBlock = String(profileSource[sectionStart.lowerBound..<sectionEnd.lowerBound])
        let expectedOrder = ["case overview", "case account", "case style", "case aiMemory", "case sizes", "case voice", "case weather", "case occasion", "case styleFriends", "case privacy"]
        var previousOffset = sectionBlock.startIndex
        for sectionCase in expectedOrder {
            guard let range = sectionBlock.range(of: sectionCase, range: previousOffset..<sectionBlock.endIndex) else {
                XCTFail("Expected Profile section \(sectionCase)")
                return
            }
            previousOffset = range.upperBound
        }
        XCTAssertTrue(sectionBlock.contains("case .aiMemory: return \"AI Memory\""))
    }

    func testScanTabIsLandingNavigationAndExplicitScanActionsUseCanonicalCameraAuthority() throws {
        let contentSource = try projectSource("StyleMatchAI/ContentView.swift")
        let scanSource = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertFalse(contentSource.contains("scanCameraPresentationRequestID"))
        XCTAssertFalse(contentSource.contains("selectScanTabForCapture"))
        XCTAssertTrue(contentSource.contains("return Button {\n            selectTab(tab)"))
        XCTAssertTrue(contentSource.contains("openRecentScoresFromHomeHistory()"))
        XCTAssertTrue(contentSource.contains("selectTab(.scan)\n        scanHistoryScrollRequestID &+= 1"))

        XCTAssertFalse(scanSource.contains("cameraPresentationRequestID"))
        XCTAssertFalse(scanSource.contains("consumeCameraPresentationRequestIfNeeded"))
        XCTAssertTrue(scanSource.contains("private var premiumScanStartCard: ScanStartCard"))
        XCTAssertTrue(scanSource.contains("onStartCamera: startCameraCapture"))
        XCTAssertTrue(scanSource.contains("Button(action: onStartCamera)"))
        XCTAssertTrue(scanSource.contains("accessibilityLabel(\"Start a full-look scan\")"))
        XCTAssertTrue(scanSource.contains("accessibilityHint(\"Opens the camera.\")"))
        XCTAssertTrue(scanSource.contains("startCameraCapture()"))
        XCTAssertTrue(scanSource.contains("AVCaptureDevice.authorizationStatus(for: .video)"))
        XCTAssertTrue(scanSource.contains("AVCaptureDevice.requestAccess(for: .video)"))
        XCTAssertTrue(scanSource.contains("UIImagePickerController.isSourceTypeAvailable(.camera)"))
        XCTAssertTrue(scanSource.contains("PhotosPicker"))
    }

    func testStyleConsultationIsOptionalProfileOwnedAndResettable() throws {
        let profileSource = try projectSource("StyleMatchAI/ProfileView.swift")
        let contentSource = try projectSource("StyleMatchAI/ContentView.swift")

        XCTAssertTrue(profileSource.contains("DisclosureGroup(\"Personal Style Profile\""))
        XCTAssertTrue(profileSource.contains("StyleDNAScreen("))
        XCTAssertTrue(profileSource.contains("StyleConsultationSheet("))
        XCTAssertTrue(profileSource.contains("StyleProfilePromiseView()"))
        XCTAssertTrue(profileSource.contains("Start Style Consultation"))
        XCTAssertTrue(profileSource.contains("Edit Style Consultation"))
        XCTAssertTrue(profileSource.contains("Reset Style Consultation"))
        XCTAssertTrue(profileSource.contains("Button(\"Skip\")"))
        XCTAssertTrue(profileSource.contains("Button(\"Back\")"))
        XCTAssertTrue(profileSource.contains("Button(step.next == nil ? \"Save\" : \"Continue\")"))
        XCTAssertFalse(profileSource.contains("Button(\"Complete\")"))
        XCTAssertTrue(profileSource.contains("resetStyleConsultation()"))
        XCTAssertTrue(profileSource.contains("Reset Style Consultation?"))
        guard let completeStart = profileSource.range(of: "private func completeStyleConsultation()"),
              let completeEnd = profileSource.range(of: "private func resetStyleConsultation()", range: completeStart.upperBound..<profileSource.endIndex) else {
            XCTFail("Expected completeStyleConsultation block")
            return
        }
        let completeBlock = String(profileSource[completeStart.lowerBound..<completeEnd.lowerBound])
        XCTAssertTrue(completeBlock.contains("styleConsultationCompletedAt = ISO8601DateFormatter().string(from: Date())"))
        XCTAssertTrue(completeBlock.contains("saveProfileDraft()"))
        XCTAssertTrue(profileSource.contains("Waist and inseam determine pant sizing."))
        XCTAssertTrue(profileSource.contains("Self-selected only. KigoStylist does not estimate or infer undertone from images."))
        XCTAssertTrue(profileSource.contains("Color groups are optional and editable. If a color belongs in more than one group for you, keep both and adjust later."))
        XCTAssertTrue(profileSource.contains("This phase does not rewrite the AI assistant personality system."))
        guard let resetStart = profileSource.range(of: "private func resetStyleConsultation()"),
              let resetEnd = profileSource.range(of: "private func updateSizeProfileSummary()", range: resetStart.upperBound..<profileSource.endIndex) else {
            XCTFail("Expected resetStyleConsultation block")
            return
        }
        let resetBlock = String(profileSource[resetStart.lowerBound..<resetEnd.lowerBound])
        XCTAssertTrue(resetBlock.contains("profileDraft.styleGoals = \"\""))
        XCTAssertTrue(resetBlock.contains("profileDraft.declaredUndertone = \"\""))
        XCTAssertTrue(resetBlock.contains("profileDraft.preferredNeutrals = \"\""))
        XCTAssertTrue(resetBlock.contains("profileDraft.stylistVoice = \"\""))
        XCTAssertTrue(resetBlock.contains("saveProfileDraft()"))
        XCTAssertFalse(resetBlock.contains("profileDraft.favoriteColors = \"\""))
        XCTAssertFalse(resetBlock.contains("profileDraft.favoriteBrands = \"\""))
        XCTAssertFalse(resetBlock.contains("profileDraft.favoriteStores = \"\""))
        XCTAssertFalse(resetBlock.contains("profileDraft.budget = \"\""))
        XCTAssertFalse(resetBlock.contains("profileDraft.fitPreference = \"\""))
        XCTAssertFalse(resetBlock.contains("profileDraft.shirtSize = \"\""))
        XCTAssertFalse(resetBlock.contains("profileDraft.waistSize = \"\""))
        XCTAssertFalse(resetBlock.contains("profileDraft.inseamLength = \"\""))
        XCTAssertFalse(resetBlock.contains("profileDraft.shoeSize = \"\""))
        XCTAssertFalse(profileSource.contains("@AppStorage(\"weight\")"))
        XCTAssertFalse(profileSource.contains("profileDraftField(\"Weight\""))
        XCTAssertFalse(profileSource.localizedCaseInsensitiveContains("body type"))
        XCTAssertFalse(profileSource.localizedCaseInsensitiveContains("skin tone"))
        XCTAssertFalse(profileSource.localizedCaseInsensitiveContains("body shape"))
        XCTAssertFalse(profileSource.localizedCaseInsensitiveContains("camera-based"))
        XCTAssertFalse(contentSource.contains("StyleConsultationSheet("), "Consultation must not be forced from app launch")
    }

    func testStyleConsultationUsesProgressiveDisclosureAndAccessibleControls() throws {
        let profileSource = try projectSource("StyleMatchAI/ProfileView.swift")

        XCTAssertTrue(profileSource.contains("@State private var step: StyleConsultationStep = .welcome"))
        XCTAssertTrue(profileSource.contains("private enum StyleConsultationStep: Int, CaseIterable, Identifiable"))
        XCTAssertTrue(profileSource.contains("case styleIdentity"))
        XCTAssertTrue(profileSource.contains("case fitProfile"))
        XCTAssertTrue(profileSource.contains("case colorProfile"))
        XCTAssertTrue(profileSource.contains("case comfortProfile"))
        XCTAssertTrue(profileSource.contains("case shoppingProfile"))
        XCTAssertTrue(profileSource.contains("case lifestyleProfile"))
        XCTAssertTrue(profileSource.contains("case stylistVoice"))
        XCTAssertTrue(profileSource.contains("private var stepContent: some View"))
        XCTAssertTrue(profileSource.contains("private var stepNavigation: some View"))
        XCTAssertTrue(profileSource.contains("@Environment(\\.dynamicTypeSize) private var dynamicTypeSize"))
        XCTAssertTrue(profileSource.contains("@AccessibilityFocusState private var focusedStep: StyleConsultationStep?"))
        XCTAssertTrue(profileSource.contains("dynamicTypeSize.isAccessibilitySize"))
        XCTAssertTrue(profileSource.contains("private var navigationButtons: some View"))
        XCTAssertTrue(profileSource.contains("private var backButton: some View"))
        XCTAssertTrue(profileSource.contains("private var primaryNavigationButton: some View"))
        XCTAssertTrue(profileSource.contains("step.previous"))
        XCTAssertTrue(profileSource.contains("step.next"))
        XCTAssertTrue(profileSource.contains(".accessibilityFocused($focusedStep, equals: step)"))
        XCTAssertTrue(profileSource.contains(".accessibilityAddTraits(.isHeader)"))
        XCTAssertTrue(profileSource.contains("Button(\"Skip\")"))
        XCTAssertTrue(profileSource.contains("Button(\"Back\")"))
        XCTAssertTrue(profileSource.contains("\"Save\" : \"Continue\""))
        XCTAssertTrue(profileSource.contains(".frame(minHeight: 44"))
        XCTAssertTrue(profileSource.contains(".contentShape(Rectangle())"))
        XCTAssertTrue(profileSource.contains("Label(option, systemImage: selected.contains(option) ? \"checkmark.circle.fill\" : \"circle\")"))
        XCTAssertTrue(profileSource.contains(".accessibilityLabel(\"\\(option), \\(accessibilityGroup)\")"))
        XCTAssertTrue(profileSource.contains(".accessibilityValue(selected.contains(option) ? \"Selected\" : \"Not selected\")"))
        XCTAssertTrue(profileSource.contains(".accessibilityAddTraits(selected.contains(option) ? .isSelected : [])"))
        XCTAssertTrue(profileSource.contains("systemImage: selected.contains(option) ? \"checkmark.circle.fill\" : \"circle\""))
        XCTAssertTrue(profileSource.contains("Color undertone (optional)"))
        XCTAssertTrue(profileSource.contains("Optional self-selected undertone"))
        XCTAssertFalse(profileSource.contains("Skin tone"))
        XCTAssertFalse(profileSource.contains("Body shape"))
        XCTAssertFalse(profileSource.contains("\"Weight\""))
        XCTAssertFalse(profileSource.contains("Text(\"Weight"))
        XCTAssertFalse(profileSource.contains("Label(\"Weight"))
    }

    func testStyleDNASummarizesOnlyUserConfirmedOrEmptyProfileFields() throws {
        let profileSource = try projectSource("StyleMatchAI/ProfileView.swift")
        let contentSource = try projectSource("StyleMatchAI/ContentView.swift")

        XCTAssertTrue(profileSource.contains("private struct StyleDNAScreen"))
        XCTAssertTrue(profileSource.contains("private struct StyleProfilePromiseView"))
        XCTAssertEqual(profileSource.components(separatedBy: "StyleProfilePromiseView()").count - 1, 2)
        XCTAssertTrue(profileSource.contains("Your Style, Your Rules"))
        XCTAssertTrue(profileSource.contains("Your profile is optional. It personalizes advice, recommendations, and style coaching. It never changes how your outfits are objectively scored."))
        XCTAssertTrue(profileSource.contains(".font(.headline)"))
        XCTAssertTrue(profileSource.contains(".font(.subheadline)"))
        XCTAssertTrue(profileSource.contains("Style DNA summarizes only the preferences you have provided"))
        XCTAssertTrue(profileSource.contains("they do not change outfit scores"))
        XCTAssertTrue(profileSource.contains("Style Identity"))
        XCTAssertTrue(profileSource.contains("Primary goals"))
        XCTAssertTrue(profileSource.contains("Preferred Pant Fit"))
        XCTAssertTrue(profileSource.contains("Color Palette"))
        XCTAssertTrue(profileSource.contains("Comfort Preferences"))
        XCTAssertTrue(profileSource.contains("Favorite Brands"))
        XCTAssertTrue(profileSource.contains("Budget"))
        XCTAssertTrue(profileSource.contains("Lifestyle Preferences"))
        XCTAssertTrue(profileSource.contains("Stylist Voice"))
        XCTAssertTrue(profileSource.contains("Consultation Status"))
        XCTAssertTrue(profileSource.contains("Button(\"Edit\", action: edit)"))
        XCTAssertTrue(profileSource.contains("Opens the Style Consultation flow so you can update this section."))
        XCTAssertTrue(profileSource.contains("showResetConfirmation = true"))
        XCTAssertTrue(profileSource.contains("Reset Style DNA?"))
        XCTAssertTrue(profileSource.contains("Button(\"Reset Style DNA\", role: .destructive)"))
        XCTAssertTrue(profileSource.contains("Label(\"Reset Style DNA\", systemImage: \"arrow.counterclockwise\")"))
        XCTAssertTrue(profileSource.contains(".accessibilityHint(\"Clears optional Style DNA answers after confirmation.\")"))
        XCTAssertTrue(profileSource.contains("Reset clears only your optional consultation answers. Saved scans and outfit scores stay unchanged."))
        XCTAssertTrue(profileSource.contains("Image(systemName: \"circle.dashed\")"))
        XCTAssertTrue(profileSource.contains("Image(systemName: \"checkmark.circle.fill\")"))
        XCTAssertTrue(profileSource.contains(".accessibilityHidden(true)"))
        XCTAssertTrue(profileSource.contains("user confirmed"))
        XCTAssertFalse(profileSource.contains("inferred trait"))
        XCTAssertFalse(profileSource.contains("detected personality"))
        XCTAssertFalse(contentSource.contains("StyleDNAScreen("), "Style DNA must remain Profile-accessible rather than launch-gated")
    }

    func testProfileClosetItemsDashboardCardOpensExistingClosetTab() throws {
        let profileSource = try projectSource("StyleMatchAI/ProfileView.swift")
        let contentSource = try projectSource("StyleMatchAI/ContentView.swift")

        XCTAssertTrue(profileSource.contains("AnyView(profileHeaderSection)"))
        XCTAssertTrue(profileSource.contains("AnyView(accountSection)"))
        XCTAssertTrue(profileSource.contains("AnyView(personalInformationSection)"))
        XCTAssertTrue(profileSource.contains("AnyView(aiStylistSettingsSection)"))
        XCTAssertTrue(profileSource.contains("AnyView(personalStyleProfileSection)"))
        XCTAssertTrue(profileSource.contains("AnyView(voiceAssistantSection)"))
        XCTAssertTrue(profileSource.contains("\"Closet Items\","))
        XCTAssertTrue(profileSource.contains("accessibilityLabel: \"Open Virtual Closet, \\(closetItemCount) \\(closetItemCount == 1 ? \"item\" : \"items\")\""))
        XCTAssertTrue(profileSource.contains("selectedTab = .closet"))
        XCTAssertTrue(profileSource.contains("Button(action: action)"))
        XCTAssertTrue(profileSource.contains(".buttonStyle(.plain)"))
        XCTAssertTrue(profileSource.contains(".frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)"))
        XCTAssertTrue(profileSource.contains(".contentShape(Rectangle())"))
        XCTAssertTrue(profileSource.contains(".accessibilityAddTraits(.isButton)"))
        XCTAssertNotNil(contentSource.range(of: #"ClosetView\s*\(\s*selectedTab:\s*\$selectedTab"#, options: .regularExpression))
    }

    func testDashboardStatisticCardsUseOptionalNavigationActions() throws {
        let homeSource = try projectSource("StyleMatchAI/HomeView.swift")
        let scanSource = try projectSource("StyleMatchAI/ScanView.swift")
        let contentSource = try projectSource("StyleMatchAI/ContentView.swift")

        XCTAssertTrue(homeSource.contains("private func homeSignal("))
        XCTAssertTrue(homeSource.contains("action: (() -> Void)? = nil"))
        XCTAssertTrue(homeSource.contains("Button(action: action)"))
        XCTAssertTrue(homeSource.contains("StyleMatchHomeDisplay.closetItemLabel(closetItemCount)"))
        XCTAssertTrue(homeSource.contains("accessibilityLabel: \"Open Virtual Closet, \\(closetItemCount) \\(closetItemCount == 1 ? \"item\" : \"items\")\""))
        XCTAssertTrue(homeSource.contains("selectedTab = .closet"))

        XCTAssertTrue(scanSource.contains("private func progressOverTimeMetric("))
        XCTAssertTrue(scanSource.contains("action: (() -> Void)? = nil"))
        XCTAssertTrue(scanSource.contains("progressOverTimeMetric(\n                    title: \"Saved Scans\""))
        XCTAssertTrue(scanSource.contains("scrollProxy.scrollTo(\"recentOutfitScores\", anchor: .top)"))
        XCTAssertTrue(scanSource.contains("progressOverTimeMetric(\n                    title: \"Closet Items\""))
        XCTAssertTrue(scanSource.contains("accessibilityLabel: \"Open Virtual Closet, \\(scanClosetItemCountText) items\""))
        XCTAssertTrue(scanSource.contains("selectedTab = .closet"))
        XCTAssertTrue(scanSource.contains(".contentShape(Rectangle())"))
        XCTAssertTrue(scanSource.contains(".accessibilityAddTraits(.isButton)"))
        XCTAssertNotNil(contentSource.range(of: #"ClosetView\s*\(\s*selectedTab:\s*\$selectedTab"#, options: .regularExpression))
        XCTAssertFalse(scanSource.contains("NavigationLink {\n                ClosetView"))
    }

    func testDashboardClosetCountsUseActualVirtualClosetStorage() throws {
        let scanSource = try projectSource("StyleMatchAI/ScanView.swift")
        let homeSource = try projectSource("StyleMatchAI/HomeView.swift")
        let profileSource = try projectSource("StyleMatchAI/ProfileView.swift")
        let closetSource = try projectSource("StyleMatchAI/ClosetView.swift")

        XCTAssertTrue(scanSource.contains("@AppStorage(\"closetItemsData\") private var closetItemsData = Data()"))
        XCTAssertTrue(scanSource.contains("let items = try? JSONDecoder().decode([ClosetItem].self, from: closetItemsData)"))
        XCTAssertTrue(scanSource.contains("return \"0\""))
        XCTAssertFalse(scanSource.contains("return \"148\""))

        guard let helperStart = scanSource.range(of: "private var scanClosetItemCountText: String"),
              let helperEnd = scanSource.range(of: "private var scanHistoryFilterBar", range: helperStart.upperBound..<scanSource.endIndex) else {
            XCTFail("Expected Scan dashboard closet-count helper")
            return
        }

        let helper = String(scanSource[helperStart.lowerBound..<helperEnd.lowerBound])
        XCTAssertFalse(helper.contains("OutfitMemoryStore"))
        XCTAssertFalse(helper.contains("garmentRecords"))
        XCTAssertFalse(helper.contains("scanCount"))

        XCTAssertTrue(homeSource.contains("@AppStorage(\"closetItemsData\") private var closetItemsData = Data()"))
        XCTAssertTrue(homeSource.contains("private var closetItemCount: Int {\n        closetItems.count\n    }"))
        XCTAssertTrue(profileSource.contains("@AppStorage(\"closetItemsData\") private var closetItemsData = Data()"))
        XCTAssertTrue(profileSource.contains("let items = try? JSONDecoder().decode([ClosetItem].self, from: closetItemsData)"))
        XCTAssertTrue(closetSource.contains("@AppStorage(\"closetItemsData\") private var closetItemsData = Data()"))
        XCTAssertTrue(closetSource.contains("let decodedItems = try? JSONDecoder().decode([ClosetItem].self, from: closetItemsData)"))
        XCTAssertTrue(closetSource.contains("closetItemsData = (try? JSONEncoder().encode(items)) ?? Data()"))
    }

    func testIconLedActionSurfacesUseRealControlsAndAccessibleLabels() throws {
        let homeSource = try projectSource("StyleMatchAI/HomeView.swift")
        let shoppingSource = try projectSource("StyleMatchAI/Shopping/ShoppingView.swift")
        let advisorSource = try projectSource("StyleMatchAI/AIStyleAdvisor.swift")
        let contentSource = try projectSource("StyleMatchAI/ContentView.swift")
        let scanSource = try projectSource("StyleMatchAI/ScanView.swift")
        let assistantsSource = try projectSource("StyleMatchAI/AIAssistantsView.swift")

        XCTAssertFalse(homeSource.contains(".onTapGesture {"))
        XCTAssertFalse(shoppingSource.contains(".onTapGesture {"))

        XCTAssertTrue(homeSource.contains("showHomeEngagement(.todayRecommendation)"))
        XCTAssertTrue(homeSource.contains("showHomeEngagement(.aiStylistLearning)"))
        XCTAssertTrue(homeSource.contains("showHomeEngagement(.styleProgress)"))
        XCTAssertTrue(homeSource.contains(".accessibilityLabel(\"Open Today's Style Brief\")"))
        XCTAssertTrue(homeSource.contains(".accessibilityLabel(\"Open AI stylist learning details\")"))
        XCTAssertTrue(homeSource.contains(".accessibilityLabel(\"Open style progress\")"))

        XCTAssertTrue(shoppingSource.contains("exploreDestination(.todaysStyleBrief"))
        XCTAssertTrue(shoppingSource.contains("exploreDestination(.completeLooks"))
        XCTAssertTrue(shoppingSource.contains("exploreDestination(.styleDNA"))
        XCTAssertTrue(shoppingSource.contains("showEngagement(.disclosure)"))
        XCTAssertTrue(shoppingSource.contains(".accessibilityLabel(\"Open shopping disclosure\")"))

        XCTAssertTrue(advisorSource.contains(".accessibilityLabel(\"Send stylist message\")"))
        XCTAssertTrue(contentSource.contains(".accessibilityLabel(\"Send stylist message\")"))
        XCTAssertTrue(scanSource.contains(".accessibilityLabel(\"Send scan AI message\")"))
        XCTAssertTrue(scanSource.contains(".accessibilityLabel(\"Delete selected photo\")"))
        XCTAssertTrue(assistantsSource.contains(".accessibilityLabel(\"Dismiss insight\")"))
        XCTAssertTrue(assistantsSource.contains(".accessibilityLabel(\"Send AI message\")"))
        XCTAssertTrue(assistantsSource.contains(".accessibilityLabel(\"Clear chat\")"))
    }

    func testMajorVoiceOverSurfacesExposeHeadingsGroupsAndStateValues() throws {
        let homeSource = try projectSource("StyleMatchAI/HomeView.swift")
        let scanSource = try projectSource("StyleMatchAI/ScanView.swift")
        let closetSource = try projectSource("StyleMatchAI/ClosetView.swift")
        let shoppingSource = try projectSource("StyleMatchAI/Shopping/ShoppingView.swift")
        let chatSource = try projectSource("StyleMatchAI/StylistChat/StylistChatView.swift")

        XCTAssertTrue(homeSource.contains("Text(\"Quick Actions\")"))
        XCTAssertTrue(homeSource.contains("Label(\"Outfit History\", systemImage: \"clock.arrow.circlepath\")"))
        XCTAssertTrue(homeSource.contains(".accessibilityHint(accessibilityHint ?? \"Opens the \\(title) tab\")"))

        XCTAssertTrue(scanSource.contains("Label(\"Recent outfit scores\", systemImage: \"clock\")"))
        XCTAssertTrue(scanSource.contains("Label(\"Style Progress\", systemImage: \"chart.line.uptrend.xyaxis\")"))
        XCTAssertTrue(scanSource.contains("Text(\"Detected Details\")"))
        XCTAssertTrue(scanSource.contains(".frame(maxWidth: .infinity, minHeight: 44)"))
        XCTAssertTrue(scanSource.contains(".accessibilityLabel(title)"))

        XCTAssertTrue(closetSource.contains("private func dashboardMetric("))
        XCTAssertTrue(closetSource.contains(".accessibilityLabel(\"\\(title), \\(value)\")"))
        XCTAssertTrue(closetSource.contains(".accessibilityHint(\"Opens \\(title)\")"))
        XCTAssertTrue(closetSource.contains(".accessibilityLabel(\"\\(title), \\(detail)\")"))

        XCTAssertTrue(shoppingSource.contains("Text(\"Shopping for you\")"))
        XCTAssertTrue(shoppingSource.contains("DisclosureGroup(\"Why KigoStylist picked this\")"))
        XCTAssertTrue(shoppingSource.contains("Label(\"Explore\""))
        XCTAssertTrue(shoppingSource.contains("Text(\"Recommendations\")"))
        XCTAssertTrue(shoppingSource.contains(".accessibilityLabel(productAccessibilitySummary(product, action: viewModel.actionTitle))"))
        XCTAssertTrue(shoppingSource.contains("StyleMatchAccessibilityText.shoppingProductSummary("))
        XCTAssertTrue(shoppingSource.contains(".accessibilityHint(\"Opens this product through the retailer link\")"))

        XCTAssertTrue(chatSource.contains(".accessibilityValue(speechInput.state.userMessage ?? \"Voice input active\")"))
        XCTAssertTrue(chatSource.contains(".accessibilityValue(service.isStreaming ? \"Unavailable while response is generating\" : \"Ready\")"))
    }

    func testSavedScanRenameUsesExplicitSaveAndPreservesCustomTitle() throws {
        let scanSource = try projectSource("StyleMatchAI/ScanView.swift")
        guard let sheetStart = scanSource.range(of: ".sheet(isPresented: $isShowingRenameScanSheet"),
              let sheetEnd = scanSource.range(of: ".sheet(isPresented: $isShowingScanAIAssist)", range: sheetStart.upperBound..<scanSource.endIndex) else {
            XCTFail("Expected rename sheet block")
            return
        }
        let renameSheet = String(scanSource[sheetStart.lowerBound..<sheetEnd.lowerBound])

        XCTAssertTrue(renameSheet.contains("Button(\"Cancel\")"))
        XCTAssertTrue(renameSheet.contains(".accessibilityLabel(\"Cancel rename\")"))
        XCTAssertFalse(renameSheet.contains("Button(\"Done\")"))
        XCTAssertTrue(renameSheet.contains(".sheet(isPresented: $isShowingRenameScanSheet, onDismiss: clearRenameDraftState)"))
        XCTAssertTrue(renameSheet.contains("Button {\n                            renamePendingScan()\n                        } label: {\n                            Text(\"Save Name\")"))
        XCTAssertFalse(renameSheet.contains("Label(\"Save Name\", systemImage: \"checkmark.circle.fill\")"))
        XCTAssertTrue(renameSheet.contains(".buttonStyle(.borderedProminent)"))
        XCTAssertTrue(renameSheet.contains(".controlSize(.large)"))
        XCTAssertTrue(renameSheet.contains(".onSubmit {\n                                if canSaveRenameTitle {\n                                    renamePendingScan()\n                                }\n                            }"))
        XCTAssertTrue(scanSource.contains("private var canSaveRenameTitle: Bool"))
        XCTAssertTrue(scanSource.contains(".disabled(!canSaveRenameTitle)"))
        XCTAssertTrue(scanSource.contains("private var hasUnsavedRenameChanges: Bool"))
        XCTAssertTrue(scanSource.contains("private func requestCancelRename()"))
        XCTAssertTrue(scanSource.contains("private func cancelRenameScan()"))
        XCTAssertTrue(scanSource.contains("private func clearRenameDraftState()"))
        XCTAssertTrue(scanSource.contains("scanPendingRename = nil"))
        XCTAssertTrue(scanSource.contains("renameText = \"\""))
        XCTAssertTrue(scanSource.contains("isShowingRenameUnsavedConfirmation = false"))
        XCTAssertTrue(scanSource.contains("guard canSaveRenameTitle else { return }"))
        XCTAssertTrue(scanSource.contains("let trimmedTitle = StyleMatchInputBounds.scanTitle(renameText)"))
        XCTAssertTrue(scanSource.contains("stored.customTitle = trimmedTitle"))
        XCTAssertTrue(scanSource.contains("guard saveScanHistory(history) else"))
        XCTAssertTrue(scanSource.contains("try? JSONDecoder().decode([String: StoredOutfitScan].self, from: outfitScanHistoryData)"))
        XCTAssertTrue(scanSource.contains("verifiedHistory[scanPendingRename.id]?.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedTitle"))
        XCTAssertTrue(scanSource.contains("title: \"Rename not saved\""))
        XCTAssertTrue(scanSource.contains("@discardableResult\n    private func saveScanHistory"))
        XCTAssertTrue(scanSource.contains("return false"))
        XCTAssertTrue(scanSource.contains("return true"))
        XCTAssertTrue(scanSource.contains("customTitle: existing?.customTitle"))
        XCTAssertTrue(scanSource.contains("customTitle: storedScan.customTitle"))
        XCTAssertTrue(scanSource.contains("if let customTitle,\n           !customTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty"))
        XCTAssertTrue(scanSource.contains("return \"Date Night\""))
    }

    func testSavedScanRenameWarnsBeforeDiscardingUnsavedDrafts() throws {
        let scanSource = try projectSource("StyleMatchAI/ScanView.swift")
        guard let sheetStart = scanSource.range(of: ".sheet(isPresented: $isShowingRenameScanSheet"),
              let sheetEnd = scanSource.range(of: ".sheet(isPresented: $isShowingScanAIAssist)", range: sheetStart.upperBound..<scanSource.endIndex) else {
            XCTFail("Expected rename sheet block")
            return
        }
        let renameSheet = String(scanSource[sheetStart.lowerBound..<sheetEnd.lowerBound])

        XCTAssertTrue(scanSource.contains("@State private var isShowingRenameUnsavedConfirmation = false"))
        XCTAssertTrue(scanSource.contains("let originalTitle = scanPendingRename.title.trimmingCharacters(in: .whitespacesAndNewlines)"))
        XCTAssertTrue(scanSource.contains("let draftTitle = StyleMatchInputBounds.scanTitle(renameText)"))
        XCTAssertTrue(scanSource.contains("return draftTitle != originalTitle"))
        XCTAssertTrue(scanSource.contains("if hasUnsavedRenameChanges {\n            isShowingRenameUnsavedConfirmation = true\n        } else {\n            cancelRenameScan()\n        }"))
        XCTAssertTrue(renameSheet.contains("RenameSheetDismissGuard(hasUnsavedChanges: hasUnsavedRenameChanges)"))
        XCTAssertTrue(renameSheet.contains("isShowingRenameUnsavedConfirmation = true"))
        XCTAssertTrue(renameSheet.contains(".confirmationDialog(\n                \"Save rename changes?\""))
        XCTAssertTrue(renameSheet.contains("Button(\"Save\") {\n                    renamePendingScan()\n                }"))
        XCTAssertTrue(renameSheet.contains("Button(\"Discard Changes\", role: .destructive) {\n                    cancelRenameScan()\n                }"))
        XCTAssertTrue(renameSheet.contains("Button(\"Continue Editing\", role: .cancel) { }"))
        XCTAssertTrue(scanSource.contains("private struct RenameSheetDismissGuard: UIViewControllerRepresentable"))
        XCTAssertTrue(scanSource.contains("func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {\n            !parent.hasUnsavedChanges\n        }"))
        XCTAssertTrue(scanSource.contains("func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController)"))
    }

    func testHomeSavedScanCardsHonorPersistedCustomTitle() throws {
        let homeSource = try projectSource("StyleMatchAI/HomeView.swift")

        XCTAssertTrue(homeSource.contains("private struct HomeStoredScan: Codable"))
        XCTAssertTrue(homeSource.contains("let customTitle: String?"))
        XCTAssertTrue(homeSource.contains("case customTitle"))
        XCTAssertTrue(homeSource.contains("if let customTitle,\n           !customTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {\n            return customTitle\n        }"))
        XCTAssertTrue(homeSource.contains("scan.displayTitle.lowercased().contains(query)"))
        XCTAssertTrue(homeSource.contains("Text(scan.displayTitle)"))
    }

    func testProfileEditsStayLocalAndDoNotCauseBackendRequests() throws {
        let profileSource = try projectSource("StyleMatchAI/ProfileView.swift")
        guard let saveStart = profileSource.range(of: "private func saveProfileDraft()"),
              let saveEnd = profileSource.range(of: "private func logPantsSave", range: saveStart.upperBound..<profileSource.endIndex) else {
            XCTFail("Expected saveProfileDraft block")
            return
        }
        let saveBlock = String(profileSource[saveStart.lowerBound..<saveEnd.lowerBound])

        XCTAssertTrue(saveBlock.contains("syncPersonalStylistProfile(from: draft)"))
        XCTAssertTrue(saveBlock.contains("profileNeedsCloudSync = accountSyncEnabled"))
        XCTAssertFalse(saveBlock.contains("URLSession"))
        XCTAssertFalse(saveBlock.contains("AccountService"))
        XCTAssertFalse(saveBlock.contains("StylistChatTransport"))
        XCTAssertFalse(saveBlock.contains("ShareableScoreCard"))
        XCTAssertFalse(saveBlock.contains("Task {"))
        XCTAssertFalse(saveBlock.contains("await "))
    }

    func testStyleConsultationDataStaysOutOfShareCardsBackendRequestsAndAnalyticsSurfaces() throws {
        let profileModelSource = try projectSource("StyleMatchAI/PersonalStylist/StylistProfileModels.swift")
        let profileStoreSource = try projectSource("StyleMatchAI/PersonalStylist/ProfileStore.swift")
        let contextSource = try projectSource("StyleMatchAI/PersonalStylist/StylistContextBuilder.swift")
        let profileViewSource = try projectSource("StyleMatchAI/ProfileView.swift")
        let privacySensitiveFiles = [
            "StyleMatchAI/ShareableScoreCard.swift",
            "StyleMatchAI/ShareableScoreCardViews.swift",
            "StyleMatchAI/AccountService.swift",
            "StyleMatchAI/StylistChat/StylistChatTransport.swift",
            "StyleMatchAI/AppBackendConfiguration.swift"
        ]
        let localOnlyIdentifiers = [
            "styleGoals",
            "preferredNeutrals",
            "preferredAccentColors",
            "comfortPreferences",
            "preferredPantRise",
            "shoppingFocus",
            "preferredShoppingCategories",
            "workSetting",
            "travelFrequency",
            "hobbiesActivities",
            "stylistVoice",
            "styleConsultationCompletedAt",
            "declaredUndertone"
        ]

        XCTAssertTrue(profileModelSource.contains("struct StylistProfile"))
        XCTAssertTrue(profileModelSource.contains("decodeIfPresent([String].self, forKey: .styleGoals) ?? []"))
        XCTAssertTrue(profileModelSource.contains("decodeIfPresent(String.self, forKey: .stylistVoice) ?? \"\""))
        XCTAssertTrue(profileStoreSource.contains("styleGoals: splitList(defaults.string(forKey: \"styleGoals\") ?? \"\")"))
        XCTAssertTrue(profileViewSource.contains("resetStyleConsultation()"))
        XCTAssertFalse(profileViewSource.contains("print(\"[Style Consultation]"))
        XCTAssertFalse(profileViewSource.contains("print(\"[Style DNA]"))

        for identifier in localOnlyIdentifiers {
            XCTAssertFalse(contextSource.contains("appendLine(\"Style goals\""), "New consultation fields must not upload through AI prompt context")
            XCTAssertFalse(contextSource.contains("Declared color undertone"), "Self-selected undertone must stay local-only")
            for file in privacySensitiveFiles {
                let source = try projectSource(file)
                XCTAssertFalse(source.contains(identifier), "\(identifier) must not be exposed through \(file)")
            }
        }
    }

    func testStyleConsultationAndDNAPrivacySourceGuardsForScoringNetworkShareAnalyticsAndLogs() throws {
        let sensitiveIdentifiers = [
            "personalizationContext",
            "StyleProfilePersonalizationContext",
            "preferredNeutrals",
            "preferredAccentColors",
            "comfortPreferences",
            "preferredPantRise",
            "shoppingFocus",
            "preferredShoppingCategories",
            "workSetting",
            "travelFrequency",
            "hobbiesActivities",
            "stylistVoice",
            "styleConsultationCompletedAt"
        ]
        let scanSource = try projectSource("StyleMatchAI/ScanView.swift")
        let deterministicBlocks = [
            ("private func calculateStyleScore(\n        validation:", "private func detectGarmentAttributes"),
            ("private func calculateStyleScore(detectedAttributes attributes:", "private func scoreComponents"),
            ("private func scoreComponents", "private func scoreColorHarmony"),
            ("private func cachedScan(for image: UIImage)", "private func analysisWithPersonalStylistIntelligence"),
            ("private func fastOutfitFingerprint(for image: UIImage)", "private func normalizedOutfitFingerprint("),
            ("private func normalizedOutfitFingerprint(", "private func inferredStablePatternSignal"),
            ("private func scoreFingerprint(for image: UIImage", "private func outfitFingerprint(for image: UIImage"),
            ("private func outfitFingerprint(for image: UIImage", "private func calculateStyleScore(\n        validation:")
        ]

        for (startMarker, endMarker) in deterministicBlocks {
            let block = try sourceBlock(
                in: scanSource,
                startMarker: startMarker,
                endMarker: endMarker,
                blockName: startMarker
            )
            assertNoSensitiveIdentifiers(sensitiveIdentifiers, in: block, context: startMarker)
        }

        let promptBlocks = [
            ("let prompt = PersonalizationContextBuilder.buildScanUpgradePrompt", "let profile = StyleMatchStylistProfile("),
            ("private func makeShareableScoreCardPayload() -> ShareableScoreCardCreatePayload", "@MainActor\n    private func showShareError")
        ]
        for (startMarker, endMarker) in promptBlocks {
            let block = try sourceBlock(
                in: scanSource,
                startMarker: startMarker,
                endMarker: endMarker,
                blockName: startMarker
            )
            assertNoSensitiveIdentifiers(sensitiveIdentifiers, in: block, context: startMarker)
        }

        let prohibitedSurfaceFiles = [
            "StyleMatchAI/ShareableScoreCard.swift",
            "StyleMatchAI/ShareableScoreCardViews.swift",
            "StyleMatchAI/AccountService.swift",
            "StyleMatchAI/StylistChat/StylistChatTransport.swift",
            "StyleMatchAI/OpenAIStylistClient.swift",
            "StyleMatchAI/AppBackendConfiguration.swift",
            "StyleMatchAI/FeatureGate.swift"
        ]
        for file in prohibitedSurfaceFiles {
            let source = try projectSource(file)
            assertNoSensitiveIdentifiers(sensitiveIdentifiers, in: source, context: file)
            XCTAssertFalse(source.contains("styleGoals"), "styleGoals must not be exposed through \(file)")
        }

        let chatModelsSource = try projectSource("StyleMatchAI/StylistChat/StylistChatModels.swift")
        let profileProjection = try sourceBlock(
            in: chatModelsSource,
            startMarker: "struct StylistProfileContextProjection: Equatable",
            endMarker: "/// A local-only, request-scoped projection",
            blockName: "Profile contextual projection"
        )
        XCTAssertTrue(profileProjection.contains("styleGoals"))
        XCTAssertFalse(profileProjection.contains("profileDraft.name"))
        XCTAssertFalse(profileProjection.contains("customerAccountEmail"))
        XCTAssertFalse(profileProjection.contains("customerAppleUserID"))
        XCTAssertFalse(profileProjection.contains("waistSize"))
        XCTAssertFalse(profileProjection.contains("workSetting:"))

        let loggingFiles = [
            "StyleMatchAI/ProfileView.swift",
            "StyleMatchAI/ScanView.swift",
            "StyleMatchAI/PersonalStylist/ProfileStore.swift",
            "StyleMatchAI/PersonalStylist/StylistContextBuilder.swift",
            "StyleMatchAI/Shopping/ProductCatalogProvider.swift",
            "StyleMatchAI/StylistChat/StylistChatTransport.swift",
            "StyleMatchAI/StylistChat/ChatConversationStore.swift",
            "StyleMatchAI/Services/VoiceStylistService.swift"
        ]
        for file in loggingFiles {
            let source = try projectSource(file)
            let loggingLines = source
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { line in
                    line.contains("print(")
                        || line.contains("Logger(")
                        || line.contains(".debug(")
                        || line.contains(".info(")
                        || line.contains(".error(")
                }
                .joined(separator: "\n")
            assertNoSensitiveIdentifiers(sensitiveIdentifiers, in: loggingLines, context: "\(file) logging")
        }
    }

    func testStyleConsultationProfileDataDoesNotEnterScoringOrFingerprints() throws {
        let scanSource = try projectSource("StyleMatchAI/ScanView.swift")
        guard let scoreStart = scanSource.range(of: "private func calculateStyleScore(\n        validation:"),
              let scoreEnd = scanSource.range(of: "private func scoreComponents", range: scoreStart.upperBound..<scanSource.endIndex) else {
            XCTFail("Expected to locate calculateStyleScore block")
            return
        }
        let scoreBlock = String(scanSource[scoreStart.lowerBound..<scoreEnd.lowerBound])
        let blockedTerms = [
            "styleGoals",
            "preferredNeutrals",
            "preferredAccentColors",
            "comfortPreferences",
            "preferredPantRise",
            "shoppingFocus",
            "preferredShoppingCategories",
            "workSetting",
            "travelFrequency",
            "hobbiesActivities",
            "stylistVoice",
            "declaredUndertone",
            "ProfileStore"
        ]

        for term in blockedTerms {
            XCTAssertFalse(scoreBlock.contains(term), "\(term) must not influence deterministic scoring")
        }

        let guardedDeterministicBlocks = [
            ("private func cachedScan(for image: UIImage)", "private func analysisWithPersonalStylistIntelligence"),
            ("private func fastOutfitFingerprint(for image: UIImage)", "private func normalizedOutfitFingerprint("),
            ("private func normalizedOutfitFingerprint(", "private func inferredStablePatternSignal")
        ]
        for (blockStart, blockEnd) in guardedDeterministicBlocks {
            guard let startRange = scanSource.range(of: blockStart),
                  let endRange = scanSource.range(of: blockEnd, range: startRange.upperBound..<scanSource.endIndex) else {
                XCTFail("Expected deterministic block \(blockStart)")
                continue
            }
            let block = String(scanSource[startRange.lowerBound..<endRange.lowerBound])
            for term in blockedTerms {
                XCTAssertFalse(block.contains(term), "\(term) must not influence \(blockStart)")
            }
        }
    }

    private func sourceBlock(
        in source: String,
        startMarker: String,
        endMarker: String,
        blockName: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        guard let start = source.range(of: startMarker) else {
            XCTFail("Expected source block start: \(blockName)", file: file, line: line)
            return ""
        }
        guard let end = source.range(of: endMarker, range: start.upperBound..<source.endIndex) else {
            XCTFail("Expected source block end for: \(blockName)", file: file, line: line)
            return ""
        }
        return String(source[start.lowerBound..<end.lowerBound])
    }

    private func assertNoSensitiveIdentifiers(
        _ identifiers: [String],
        in source: String,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for identifier in identifiers {
            XCTAssertFalse(source.contains(identifier), "\(identifier) must not appear in \(context)", file: file, line: line)
        }
    }

    func testBuild17PrivacyIsolationRemovesAppearanceInferencePromptAndResultUI() throws {
        let scanSource = try projectSource("StyleMatchAI/ScanView.swift")
        let contentSource = try projectSource("StyleMatchAI/ContentView.swift")
        let advisorSource = try projectSource("StyleMatchAI/AIStyleAdvisor.swift")
        let clientSource = try projectSource("StyleMatchAI/OpenAIStylistClient.swift")

        XCTAssertFalse(scanSource.contains("skinToneStyleNote(declaredUndertone"))
        XCTAssertFalse(scanSource.contains("declaredUndertone: ProfileStore"))
        XCTAssertFalse(scanSource.contains("skinLikePixels"))
        XCTAssertFalse(scanSource.contains("This palette may lean"))
        XCTAssertFalse(scanSource.contains("You chose \\(selected) undertones in Profile"))
        XCTAssertFalse(scanSource.contains("result.skinToneStyleNote"))
        XCTAssertTrue(scanSource.contains("skinToneStyleNote: nil"))

        XCTAssertFalse(contentSource.contains("Skin tone style note"))
        XCTAssertFalse(contentSource.contains("analysis.skinToneStyleNote"))
        XCTAssertFalse(advisorSource.contains("Skin tone style note"))
        XCTAssertFalse(advisorSource.contains("skin tone style note"))
        XCTAssertFalse(advisorSource.contains("analysis.skinToneStyleNote"))
        XCTAssertFalse(clientSource.contains("skinToneStyleNote"))
        XCTAssertFalse(clientSource.localizedCaseInsensitiveContains("skin tone"))
    }

    func testOutfitAnalysisResultKeepsLegacySkinToneStyleNoteDecodeOnlyCompatibility() throws {
        let missingFieldJSON = Data("""
        {
          "score": 82,
          "colorMatch": "Strong",
          "occasionFit": "Everyday",
          "styleBalance": "Casual",
          "colorHarmony": "Balanced",
          "styleCoordination": "Coordinated",
          "formality": "Casual",
          "seasonalMatch": "Mild",
          "summary": "Synthetic summary",
          "outfitDescription": "Synthetic outfit",
          "detectedClothingItems": ["polo"],
          "colorPalette": ["navy"],
          "environment": "indoor",
          "imageQuality": "clear",
          "suggestions": [],
          "recommendations": []
        }
        """.utf8)
        let legacyFieldJSON = Data("""
        {
          "score": 82,
          "colorMatch": "Strong",
          "occasionFit": "Everyday",
          "styleBalance": "Casual",
          "colorHarmony": "Balanced",
          "styleCoordination": "Coordinated",
          "formality": "Casual",
          "seasonalMatch": "Mild",
          "summary": "Synthetic summary",
          "outfitDescription": "Synthetic outfit",
          "detectedClothingItems": ["polo"],
          "colorPalette": ["navy"],
          "environment": "indoor",
          "imageQuality": "clear",
          "skinToneStyleNote": "Legacy local note",
          "suggestions": [],
          "recommendations": []
        }
        """.utf8)

        let missing = try JSONDecoder().decode(OutfitAnalysisResult.self, from: missingFieldJSON)
        let legacy = try JSONDecoder().decode(OutfitAnalysisResult.self, from: legacyFieldJSON)

        XCTAssertNil(missing.skinToneStyleNote)
        XCTAssertEqual(legacy.skinToneStyleNote, "Legacy local note")
    }

    func testLegacyBodyProportionsStayOutOfActiveScoringTransportShareAndUIPaths() throws {
        let profileSource = try projectSource("StyleMatchAI/PersonalStylist/StylistProfileModels.swift")
        let guardedFiles = [
            "StyleMatchAI/ScanView.swift",
            "StyleMatchAI/ContentView.swift",
            "StyleMatchAI/AIStyleAdvisor.swift",
            "StyleMatchAI/OpenAIStylistClient.swift",
            "StyleMatchAI/StylistChat/StylistChatTransport.swift",
            "StyleMatchAI/ShareableScoreCard.swift",
            "StyleMatchAI/ShareableScoreCardViews.swift",
            "StyleMatchAI/ProfileView.swift"
        ]
        let legacyTerms = ["BodyProportions", "heightInches", "bodyType"]

        XCTAssertTrue(profileSource.contains("struct BodyProportions: Codable"))
        XCTAssertTrue(profileSource.contains("var heightInches: Double?"))
        XCTAssertTrue(profileSource.contains("var bodyType: String?"))

        for file in guardedFiles {
            let source = try projectSource(file)
            for term in legacyTerms {
                XCTAssertFalse(source.contains(term), "\(term) must remain decode-only legacy compatibility and stay out of \(file)")
            }
        }
    }

    func testClearProfilePreferenceDefaultsReturnsToBlankAfterRelaunch() {
        seedFounderSizeDefaults()
        defaults.set("2026-07-09T09:00:00Z", forKey: FounderProfileDefaultsMigration.profileLastSavedAtKey)

        let store = ProfileStore(defaults: defaults, userId: userA)
        var profile = store.currentProfile
        profile.clothingSizes = ClothingSizes(shirtSize: "L", pantSize: "Men 36x36", shoeSize: "10")
        profile.preferredFit = .regular
        profile.favoriteColors = ["black"]
        store.currentProfile = profile
        store.save()

        FounderProfileDefaultsMigration.clearProfilePreferenceDefaults(defaults: defaults, userID: userA)
        // The production reset owns its default snapshot location. This test
        // deliberately uses a temporary snapshot root, so clean that fixture
        // before simulating its isolated relaunch.
        PersonalStylistSnapshotStore.deleteData(
            store: "StylistProfile",
            userID: userA,
            rootDirectory: snapshotTestRoot
        )

        XCTAssertNil(defaults.object(forKey: FounderProfileDefaultsMigration.profileLastSavedAtKey))
        let reloaded = ProfileStore(defaults: defaults, userId: userA, snapshotRoot: snapshotTestRoot).currentProfile
        XCTAssertNil(reloaded.clothingSizes.shirtSize)
        XCTAssertNil(reloaded.clothingSizes.pantSize)
        XCTAssertNil(reloaded.clothingSizes.shoeSize)
        XCTAssertEqual(reloaded.preferredFit, .unset)
        XCTAssertTrue(reloaded.favoriteColors.isEmpty)
        XCTAssertEqual(ProfileStore.profileCompletenessPercentage(reloaded), 0)
    }

    func testScanFitCopyDoesNotClaimSavedSizesWithoutSavedProfile() throws {
        let scanSource = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(scanSource.contains("hasSavedSizeProfileForFitCopy"))
        XCTAssertTrue(scanSource.contains("no saved size profile is available"))
        XCTAssertTrue(scanSource.contains("does not verify exact measurements or unseen fit details"))
        XCTAssertTrue(scanSource.contains("The photo does not provide enough evidence for exact fit guidance."))
        XCTAssertFalse(scanSource.contains("result?.fitAssessment"))
        XCTAssertFalse(scanSource.contains("After a scan, this uses your saved sizes"))
        XCTAssertFalse(scanSource.contains("Fit check: using your saved sizes ("))
    }

    func testLoginWelcomeProfileDataRequiresIntentionalSaveMarker() {
        defaults.set("Navy blazer with dark denim", forKey: "favoriteOutfits")
        defaults.set("Classic, business casual, clean sneakers", forKey: "stylePreferences")
        defaults.set("Black, white, navy", forKey: "favoriteColors")

        XCTAssertFalse(
            LoginWelcomeProfileData.hasIntentionalProfileValues(
                favoriteOutfits: "Navy blazer with dark denim",
                stylePreferences: "Classic, business casual, clean sneakers",
                favoriteColors: "Black, white, navy",
                profileName: "",
                defaults: defaults
            )
        )

        defaults.set("2026-07-09T09:00:00Z", forKey: FounderProfileDefaultsMigration.profileLastSavedAtKey)

        XCTAssertTrue(
            LoginWelcomeProfileData.hasIntentionalProfileValues(
                favoriteOutfits: "Navy blazer with dark denim",
                stylePreferences: "",
                favoriteColors: "",
                profileName: "",
                defaults: defaults
            )
        )
    }

    func testProfileDisplaySourcesDoNotUseFakeScoreFallbacks() throws {
        let homeSource = try projectSource("StyleMatchAI/HomeView.swift")
        let contentSource = try projectSource("StyleMatchAI/ContentView.swift")

        XCTAssertFalse(homeSource.contains("return \"92\""))
        XCTAssertFalse(contentSource.contains("?? 92"))
        XCTAssertFalse(contentSource.contains("\"92-95 if the fit is clean\""))
        XCTAssertFalse(contentSource.contains("Only black loafers or clean sneakers appear to be missing."))
    }

    func testScanProgressSummaryUsesTruthfulEmptyState() {
        let summary = ScanProgressSummary(scores: [])

        XCTAssertNil(summary.averageScore)
        XCTAssertNil(summary.highestScore)
        XCTAssertEqual(summary.savedScanCount, 0)
        XCTAssertEqual(summary.averageScoreText, "—")
        XCTAssertEqual(summary.highestScoreText, "—")
        XCTAssertEqual(summary.savedScanCountText, "0")
    }

    func testScanProgressSummaryDerivesThreePersistedScores() {
        let summary = ScanProgressSummary(scores: [80, 90, 100])

        XCTAssertEqual(summary.averageScore, 90)
        XCTAssertEqual(summary.highestScore, 100)
        XCTAssertEqual(summary.savedScanCount, 3)
    }

    func testEmptyScanProgressOmitsUnavailableAIAggregates() {
        let aggregates = ScanProgressSummary(scores: []).visibleAggregates

        XCTAssertNil(aggregates.averageScore)
        XCTAssertNil(aggregates.highestScore)
        XCTAssertEqual(aggregates.totalScans, 0)
    }

    func testSavedScanCapacityIsPresentedAsSavedScansWithoutTruncatingHistory() throws {
        let summary = ScanProgressSummary(scores: Array(repeating: 80, count: 20))
        let scanSource = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertEqual(summary.savedScanCount, 20)
        XCTAssertTrue(scanSource.contains("title: \"Saved Scans\""))
        XCTAssertTrue(scanSource.contains("SavedScanHistoryCapacity.maximumRecords"))
        XCTAssertFalse(scanSource.contains(".prefix(20)"))
        XCTAssertFalse(scanSource.contains("title: \"Outfits Scanned\""))
    }

    func testScanProgressHasNoSampleEmptyFallbacks() throws {
        let scanSource = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertFalse(scanSource.contains("return \"88\""))
        XCTAssertFalse(scanSource.contains("return \"96\""))
        XCTAssertFalse(scanSource.contains("return \"347\""))
        XCTAssertFalse(scanSource.contains("Int(averageScoreText"))
        XCTAssertFalse(scanSource.contains("Int(highestScoreText"))
        XCTAssertFalse(scanSource.contains("Int(outfitsScannedText"))
    }

    func testPreferredPantFitOptionsMatchTheProfileContract() {
        XCTAssertEqual(
            PantFitPreference.options,
            ["Slim Fit", "Regular Fit", "Relaxed Fit", "Athletic Fit", "Loose Fit", "No Preference"]
        )
        XCTAssertEqual(PantFitPreference.fromProfileInput("Slim").displayName, "Slim Fit")
        XCTAssertEqual(PantFitPreference.fromProfileInput("Regular Fit").displayName, "Regular Fit")
        XCTAssertEqual(PantFitPreference.fromProfileInput("Relaxed").displayName, "Relaxed Fit")
        XCTAssertEqual(PantFitPreference.fromProfileInput("Athletic Fit").displayName, "Athletic Fit")
        XCTAssertEqual(PantFitPreference.fromProfileInput("Loose").displayName, "Loose Fit")
    }

    func testAmbiguousLegacyPantPreferencesMigrateToNoPreference() {
        for legacyValue in ["Low", "Mid", "High", "Oversized", "Tailored", "unknown"] {
            XCTAssertEqual(
                PantFitPreference.migratedValue(currentValue: legacyValue, legacyOverallFit: nil),
                "No Preference",
                "\(legacyValue) must not be guessed into a pant-fit preference"
            )
        }
    }

    func testPantFitMigrationPreservesWaistAndInseam() {
        defaults.set("36", forKey: "waistSize")
        defaults.set("32", forKey: "inseamLength")
        defaults.set("Mid", forKey: "preferredPantRise")
        defaults.set("Oversized", forKey: "fitPreference")

        PantFitPreference.migrateDefaultsIfNeeded(defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: "preferredPantFit"), "No Preference")
        XCTAssertEqual(defaults.string(forKey: "fitPreference"), "Oversized")
        XCTAssertEqual(defaults.string(forKey: "waistSize"), "36")
        XCTAssertEqual(defaults.string(forKey: "inseamLength"), "32")
        XCTAssertEqual(defaults.string(forKey: "preferredPantRise"), "Mid")
    }

    func testClearLegacyFitMappingsArePreserved() {
        let expected = [
            "Slim": "Slim Fit",
            "Regular": "Regular Fit",
            "Relaxed": "Relaxed Fit"
        ]

        for (legacy, canonical) in expected {
            XCTAssertEqual(PantFitPreference.migratedValue(currentValue: nil, legacyOverallFit: legacy), canonical)
        }

        for ambiguousLegacyValue in ["Oversized", "Tailored", "Athletic", "Loose", "unknown", ""] {
            XCTAssertEqual(
                PantFitPreference.migratedValue(currentValue: nil, legacyOverallFit: ambiguousLegacyValue),
                "No Preference"
            )
        }
    }

    func testPreferredPantFitIsDisplayedAndUsedConsistently() throws {
        let profileSource = try projectSource("StyleMatchAI/ProfileView.swift")
        let closetSource = try projectSource("StyleMatchAI/ClosetView.swift")
        let contextSource = try projectSource("StyleMatchAI/PersonalStylist/StylistContextBuilder.swift")
        let scanSource = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(profileSource.contains("Picker(\"Preferred Pant Fit\""))
        XCTAssertTrue(closetSource.contains("Picker(\"Preferred Pant Fit\""))
        XCTAssertTrue(profileSource.contains("Picker(\"Preferred Pant Rise\""))
        XCTAssertTrue(closetSource.contains("Picker(\"Preferred Pant Rise\""))
        XCTAssertEqual(PantRisePreference.options, ["Low Rise", "Mid Rise", "High Rise", "No Preference"])
        XCTAssertTrue(contextSource.contains("Preferred pant fit:"))
        XCTAssertTrue(contextSource.contains("Preferred pant fit"))
        XCTAssertTrue(scanSource.contains("preferred pant fit:"))
        XCTAssertFalse(scanSource.contains("parts.append(\"preferred fit:"))
    }

    func testFitProfileOnboardingMeasurementsAreInteractive() throws {
        let profileSource = try projectSource("StyleMatchAI/ProfileView.swift")

        XCTAssertTrue(profileSource.contains("Picker(\"Shirt Size\", selection: binding(\\.shirtSize))"))
        XCTAssertTrue(profileSource.contains("Picker(\"Shoe Size\", selection: binding(\\.shoeSize))"))
        XCTAssertTrue(profileSource.contains("measurementField(\"Waist\", keyPath: \\.waistSize"))
        XCTAssertTrue(profileSource.contains("measurementField(\"Inseam\", keyPath: \\.inseamLength"))
        XCTAssertTrue(profileSource.contains("measurementField(\"Sleeve Length\", keyPath: \\.sleeveLength"))
        XCTAssertTrue(profileSource.contains("measurementField(\"Neck Size\", keyPath: \\.neckSize"))
        XCTAssertTrue(profileSource.contains("Text(\"Choose size\").tag(\"\")"))
        XCTAssertTrue(profileSource.contains("prompt: \"Add measurement\""))
        XCTAssertFalse(profileSource.contains("profileValueRow(\"Shirt size\""))
        XCTAssertFalse(profileSource.contains("profileValueRow(\"Waist\""))
        XCTAssertTrue(profileSource.contains("Waist and inseam determine pant sizing."))
    }

    func testNoPreferenceIsOmittedFromPersonalStylistContext() {
        var profile = makeStylistProfile(userId: userA)
        profile.preferredPantFit = .unset

        let context = PersonalizationContextBuilder.buildContext(profile: profile, recentMemories: [])

        XCTAssertFalse(context.contains("Preferred pant fit:"))
    }

    func testPrivacyDeletionUsesActiveUserBeforeClearingSessionKeys() {
        defaults.set(userA, forKey: "customerAppleUserID")
        defaults.set(["Saba", "stine"].joined(), forKey: "profileName")

        let profileA = ProfileStore(defaults: defaults, userId: userA)
        profileA.currentProfile.favoriteColors = ["black"]
        profileA.save()

        let profileB = ProfileStore(defaults: defaults, userId: userB)
        profileB.currentProfile.favoriteColors = ["white"]
        profileB.save()

        ShoppingLocalStore(defaults: defaults, userID: userA).savedFavorites = ["sale-a"]
        ShoppingLocalStore(defaults: defaults, userID: userB).savedFavorites = ["sale-b"]

        let deletedUserID = PersonalStylistStorage.deleteActiveUserData(defaults: defaults)
        ShoppingLocalStore.deleteShoppingData(for: deletedUserID, defaults: defaults)
        defaults.removeObject(forKey: "profileName")

        XCTAssertEqual(deletedUserID, PersonalStylistStorage.normalizedUserID(userA))
        XCTAssertNil(defaults.object(forKey: "profileName"))
        XCTAssertNil(
            defaults.object(forKey: PersonalStylistStorage.scopedKey(PersonalStylistStorage.legacyProfileKey, userID: userA)),
            "The signed-in user's profile should be removed before the Apple user id is cleared."
        )
        XCTAssertTrue(ShoppingLocalStore(defaults: defaults, userID: userA).savedFavorites.isEmpty)
        XCTAssertNotNil(
            defaults.object(forKey: PersonalStylistStorage.scopedKey(PersonalStylistStorage.legacyProfileKey, userID: userB)),
            "Deleting user A should not remove user B's profile."
        )
        XCTAssertEqual(ShoppingLocalStore(defaults: defaults, userID: userB).savedFavorites, ["sale-b"])
    }

    func testAccountScopedStorageCapturesLegacySharedDataBeforeLaunchMigrations() {
        defaults.removeObject(forKey: AccountScopedStorage.activeUserMarkerKey)
        defaults.set("Sign in with Apple", forKey: "customerAccountMode")
        defaults.set(userA, forKey: "customerAppleUserID")
        defaults.set("Alex", forKey: "profileName")
        defaults.set(Data("scan-a".utf8), forKey: "outfitScanHistoryData")

        XCTAssertTrue(AccountScopedStorage.prepareForLaunch(defaults: defaults))

        defaults.removeObject(forKey: "profileName")
        defaults.removeObject(forKey: "outfitScanHistoryData")
        AccountScopedStorage.restoreCapturedLaunchData(defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: "profileName"), "Alex")
        XCTAssertEqual(defaults.data(forKey: "outfitScanHistoryData"), Data("scan-a".utf8))
        XCTAssertEqual(
            defaults.string(forKey: AccountScopedStorage.activeUserMarkerKey),
            PersonalStylistStorage.normalizedUserID(userA)
        )
    }

    func testAccountScopedStorageResolvesAppleModeWithoutCreatingAbsentScanHistory() {
        defaults.set("Sign in with Apple", forKey: "customerAccountMode")
        defaults.set(userA, forKey: "customerAppleUserID")
        XCTAssertEqual(AccountScopedStorage.sessionUserID(defaults: defaults), PersonalStylistStorage.normalizedUserID(userA))

        defaults.set("Guest", forKey: "customerAccountMode")
        XCTAssertEqual(AccountScopedStorage.sessionUserID(defaults: defaults), "guest")

        defaults.set("apple", forKey: "customerAccountMode")
        XCTAssertEqual(AccountScopedStorage.sessionUserID(defaults: defaults), PersonalStylistStorage.normalizedUserID(userA))

        defaults.set("malformed", forKey: "customerAccountMode")
        XCTAssertEqual(AccountScopedStorage.sessionUserID(defaults: defaults), "guest")

        defaults.set("Sign in with Apple", forKey: "customerAccountMode")
        defaults.removeObject(forKey: "customerAppleUserID")
        XCTAssertEqual(AccountScopedStorage.sessionUserID(defaults: defaults), "guest")

        defaults.set(userA, forKey: "customerAppleUserID")
        defaults.set("Sign in with Apple", forKey: "customerAccountMode")
        defaults.set("guest", forKey: AccountScopedStorage.activeUserMarkerKey)
        defaults.set(AccountStorageEnvironment.production.rawValue, forKey: AccountScopedStorage.activeEnvironmentMarkerKey)
        let profileStore = ProfileStore(defaults: defaults, userId: userA)
        profileStore.currentProfile.favoriteColors = ["navy"]
        profileStore.save()
        let outfitStore = OutfitMemoryStore(defaults: defaults, userId: userA, snapshotRoot: snapshotTestRoot)
        outfitStore.addScan(makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "identity-repair")))

        XCTAssertFalse(AccountScopedStorage.prepareForLaunch(defaults: defaults))
        XCTAssertNil(defaults.object(forKey: "outfitScanHistoryData"))
        XCTAssertNil(
            defaults.object(forKey: AccountScopedStorage.snapshotKey(
                "outfitScanHistoryData",
                userID: userA,
                environment: .production
            ))
        )
        XCTAssertEqual(ProfileStore(defaults: defaults, userId: userA).currentProfile.favoriteColors, ["navy"])
        XCTAssertEqual(
            OutfitMemoryStore(defaults: defaults, userId: userA, snapshotRoot: snapshotTestRoot).memories.count,
            1
        )
    }

    func testAccountSwitchRestoresOnlyDestinationSharedData() {
        defaults.set("apple", forKey: "customerAccountMode")
        defaults.set(userA, forKey: "customerAppleUserID")
        defaults.set(PersonalStylistStorage.normalizedUserID(userA), forKey: AccountScopedStorage.activeUserMarkerKey)
        defaults.set("User A", forKey: "profileName")
        defaults.set(Data("history-a".utf8), forKey: "outfitScanHistoryData")

        AccountScopedStorage.switchUser(
            from: userA,
            to: userB,
            transferSourceData: false,
            defaults: defaults
        )

        XCTAssertNil(defaults.object(forKey: "profileName"))
        XCTAssertNil(defaults.object(forKey: "outfitScanHistoryData"))

        defaults.set("User B", forKey: "profileName")
        defaults.set(Data("history-b".utf8), forKey: "outfitScanHistoryData")
        AccountScopedStorage.switchUser(
            from: userB,
            to: userA,
            transferSourceData: false,
            defaults: defaults
        )

        XCTAssertEqual(defaults.string(forKey: "profileName"), "User A")
        XCTAssertEqual(defaults.data(forKey: "outfitScanHistoryData"), Data("history-a".utf8))

        AccountScopedStorage.switchUser(
            from: userA,
            to: userB,
            transferSourceData: false,
            defaults: defaults
        )
        XCTAssertEqual(defaults.string(forKey: "profileName"), "User B")
        XCTAssertEqual(defaults.data(forKey: "outfitScanHistoryData"), Data("history-b".utf8))
    }

    func testGuestTransferCopiesSharedProfileMemoryAndShoppingIntoNewAppleScope() {
        defaults.set("guest", forKey: AccountScopedStorage.activeUserMarkerKey)
        defaults.set("Guest Name", forKey: "profileName")
        defaults.set(Data("guest-history".utf8), forKey: "outfitScanHistoryData")

        let guestProfile = ProfileStore(defaults: defaults, userId: "guest")
        guestProfile.currentProfile.favoriteColors = ["navy"]
        guestProfile.save()
        ShoppingLocalStore(defaults: defaults, userID: "guest").savedFavorites = ["guest-favorite"]

        AccountScopedStorage.switchUser(
            from: "guest",
            to: userA,
            transferSourceData: true,
            defaults: defaults
        )

        XCTAssertEqual(defaults.string(forKey: "profileName"), "Guest Name")
        XCTAssertEqual(defaults.data(forKey: "outfitScanHistoryData"), Data("guest-history".utf8))
        XCTAssertEqual(ProfileStore(defaults: defaults, userId: userA).currentProfile.favoriteColors, ["navy"])
        XCTAssertEqual(ShoppingLocalStore(defaults: defaults, userID: userA).savedFavorites, ["guest-favorite"])
    }

    func testAccountSnapshotsAreIsolatedByBackendEnvironment() {
        defaults.set("apple", forKey: "customerAccountMode")
        defaults.set(userA, forKey: "customerAppleUserID")
        defaults.set(PersonalStylistStorage.normalizedUserID(userA), forKey: AccountScopedStorage.activeUserMarkerKey)
        defaults.set(AccountStorageEnvironment.production.rawValue, forKey: AccountScopedStorage.activeEnvironmentMarkerKey)
        defaults.set(Data("production-history".utf8), forKey: "outfitScanHistoryData")

        XCTAssertFalse(AccountScopedStorage.prepareForLaunch(defaults: defaults, environment: .staging))
        XCTAssertNil(defaults.data(forKey: "outfitScanHistoryData"))
        defaults.set(Data("staging-history".utf8), forKey: "outfitScanHistoryData")

        XCTAssertFalse(AccountScopedStorage.prepareForLaunch(defaults: defaults, environment: .localAcceptance))
        XCTAssertNil(defaults.data(forKey: "outfitScanHistoryData"))
        defaults.set(Data("local-history".utf8), forKey: "outfitScanHistoryData")

        XCTAssertFalse(AccountScopedStorage.prepareForLaunch(defaults: defaults, environment: .production))
        XCTAssertEqual(defaults.data(forKey: "outfitScanHistoryData"), Data("production-history".utf8))
        XCTAssertFalse(AccountScopedStorage.prepareForLaunch(defaults: defaults, environment: .staging))
        XCTAssertEqual(defaults.data(forKey: "outfitScanHistoryData"), Data("staging-history".utf8))
        XCTAssertFalse(AccountScopedStorage.prepareForLaunch(defaults: defaults, environment: .localAcceptance))
        XCTAssertEqual(defaults.data(forKey: "outfitScanHistoryData"), Data("local-history".utf8))
    }

    func testLegacyAccountSnapshotMigratesToProductionOnlyWithoutDeletion() {
        defaults.set("apple", forKey: "customerAccountMode")
        defaults.set(userA, forKey: "customerAppleUserID")
        defaults.set(PersonalStylistStorage.normalizedUserID(userA), forKey: AccountScopedStorage.activeUserMarkerKey)
        let legacyKey = AccountScopedStorage.legacySnapshotKey("outfitScanHistoryData", userID: userA)
        let productionKey = AccountScopedStorage.snapshotKey(
            "outfitScanHistoryData",
            userID: userA,
            environment: .production
        )
        let stagingKey = AccountScopedStorage.snapshotKey(
            "outfitScanHistoryData",
            userID: userA,
            environment: .staging
        )
        defaults.set(Data("legitimate-history".utf8), forKey: legacyKey)

        XCTAssertFalse(AccountScopedStorage.prepareForLaunch(defaults: defaults, environment: .staging))
        XCTAssertNil(defaults.data(forKey: "outfitScanHistoryData"))
        XCTAssertEqual(defaults.data(forKey: productionKey), Data("legitimate-history".utf8))
        XCTAssertNil(defaults.data(forKey: stagingKey))
        XCTAssertEqual(defaults.data(forKey: legacyKey), Data("legitimate-history".utf8))

        XCTAssertFalse(AccountScopedStorage.prepareForLaunch(defaults: defaults, environment: .production))
        XCTAssertEqual(defaults.data(forKey: "outfitScanHistoryData"), Data("legitimate-history".utf8))
    }

    func testGuestTransferRemainsExplicitWithinCurrentEnvironment() {
        defaults.set("guest", forKey: AccountScopedStorage.activeUserMarkerKey)
        defaults.set(AccountStorageEnvironment.staging.rawValue, forKey: AccountScopedStorage.activeEnvironmentMarkerKey)
        defaults.set(Data("staging-guest-history".utf8), forKey: "outfitScanHistoryData")

        AccountScopedStorage.switchUser(
            from: "guest",
            to: userA,
            transferSourceData: false,
            defaults: defaults,
            environment: .staging
        )
        XCTAssertNil(defaults.data(forKey: "outfitScanHistoryData"))

        AccountScopedStorage.switchUser(
            from: userA,
            to: "guest",
            transferSourceData: false,
            defaults: defaults,
            environment: .staging
        )
        AccountScopedStorage.switchUser(
            from: "guest",
            to: userA,
            transferSourceData: true,
            defaults: defaults,
            environment: .staging
        )
        XCTAssertEqual(defaults.data(forKey: "outfitScanHistoryData"), Data("staging-guest-history".utf8))
        XCTAssertNil(
            defaults.data(forKey: AccountScopedStorage.snapshotKey(
                "outfitScanHistoryData",
                userID: userA,
                environment: .production
            ))
        )
    }

    func testDeletingOneAccountScopePreservesOtherAccountScope() {
        defaults.set(PersonalStylistStorage.normalizedUserID(userA), forKey: AccountScopedStorage.activeUserMarkerKey)
        defaults.set("User A", forKey: "profileName")
        AccountScopedStorage.switchUser(from: userA, to: userB, transferSourceData: false, defaults: defaults)
        defaults.set("User B", forKey: "profileName")
        AccountScopedStorage.switchUser(from: userB, to: userA, transferSourceData: false, defaults: defaults)

        AccountScopedStorage.deleteUserData(for: userA, defaults: defaults)

        XCTAssertNil(defaults.object(forKey: "profileName"))
        AccountScopedStorage.switchUser(from: userA, to: userB, transferSourceData: false, defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: "profileName"), "User B")
    }


    func testPrivacyDeletionContractClearsProfileAssistantClosetWishlistAndScanHistoryForActiveUser() throws {
        let profileSource = try projectSource("StyleMatchAI/ProfileView.swift")
        let privacySource = try projectSource("StyleMatchAI/PrivacyDataManager.swift")
        XCTAssertTrue(profileSource.contains("PrivacyDataManager.shared.deleteAllLocalCustomerData()"))
        XCTAssertTrue(privacySource.contains("let activeUserID = PersonalStylistStorage.activeUserID(defaults: defaults)"))
        XCTAssertTrue(privacySource.contains("AccountScopedStorage.deleteUserData(for: activeUserID, defaults: defaults)"))
        XCTAssertTrue(privacySource.contains("SavedScanImageAssetStore(userID: activeUserID).removeAllAccountAssets()"))
        XCTAssertTrue(privacySource.contains("AccountScopedStorage.deleteSensitiveDeviceState(defaults: defaults)"))
        XCTAssertTrue(privacySource.contains("defaults.set(\"guest\", forKey: AccountScopedStorage.activeUserMarkerKey)"))
        XCTAssertFalse(privacySource.contains("OpenAIKeychain"))

        defaults.set(userA, forKey: "customerAppleUserID")
        defaults.set("apple", forKey: "customerAccountMode")
        defaults.set("tester@example.com", forKey: "customerAccountEmail")
        defaults.set("2026-07-10T09:00:00Z", forKey: FounderProfileDefaultsMigration.profileLastSavedAtKey)

        let profileA = ProfileStore(defaults: defaults, userId: userA)
        profileA.currentProfile.favoriteColors = ["black"]
        profileA.save()

        let profileB = ProfileStore(defaults: defaults, userId: userB)
        profileB.currentProfile.favoriteColors = ["white"]
        profileB.save()

        let memoryA = OutfitMemoryStore(defaults: defaults, userId: userA)
        memoryA.addOrMergeScan(makeOutfitMemory(userId: userA, record: makeGarmentRecord(fingerprint: "privacy-user-a")))

        let memoryB = OutfitMemoryStore(defaults: defaults, userId: userB)
        memoryB.addOrMergeScan(makeOutfitMemory(userId: userB, record: makeGarmentRecord(fingerprint: "privacy-user-b")))

        let closetData = try JSONEncoder().encode([
            ClosetItem(
                name: "White Shirt",
                category: "Shirt",
                color: "White",
                brand: "Test Brand",
                size: "M",
                occasion: "Work",
                notes: "Seed item"
            )
        ])
        defaults.set(closetData, forKey: "closetItemsData")
        defaults.set("White Shirt", forKey: "closetInventory")
        defaults.set(["wishlist-name"], forKey: "wishlistProductNamesData")
        defaults.set(Data("scan-history".utf8), forKey: "outfitScanHistoryData")
        defaults.set("ChatGPT", forKey: "preferredAIAssistant")
        defaults.set("ChatGPT,Gemini", forKey: "connectedAIAssistants")
        defaults.set("gpt-test", forKey: "openAIModel")
        defaults.set(true, forKey: "shareAppContextWithChatGPT")

        let shoppingA = ShoppingLocalStore(defaults: defaults, userID: userA)
        shoppingA.savedFavorites = ["favorite-a"]
        shoppingA.wishlistProductIDs = ["wishlist-a"]
        shoppingA.cartProductIDs = ["cart-a"]

        let shoppingB = ShoppingLocalStore(defaults: defaults, userID: userB)
        shoppingB.savedFavorites = ["favorite-b"]
        shoppingB.wishlistProductIDs = ["wishlist-b"]

        let activeUserID = PersonalStylistStorage.activeUserID(defaults: defaults)
        for key in [
            "customerAppleUserID",
            "customerAccountMode",
            "customerAccountEmail",
            FounderProfileDefaultsMigration.profileLastSavedAtKey,
            "closetItemsData",
            "closetInventory",
            "wishlistProductNamesData",
            "outfitScanHistoryData",
            "preferredAIAssistant",
            "connectedAIAssistants",
            "openAIModel",
            "shareAppContextWithChatGPT"
        ] {
            defaults.removeObject(forKey: key)
        }
        PersonalStylistStorage.deletePersonalization(for: activeUserID, defaults: defaults)
        ShoppingLocalStore.deleteShoppingData(for: activeUserID, defaults: defaults)

        XCTAssertEqual(activeUserID, PersonalStylistStorage.normalizedUserID(userA))
        XCTAssertNil(defaults.object(forKey: "customerAppleUserID"))
        XCTAssertNil(defaults.object(forKey: "customerAccountMode"))
        XCTAssertNil(defaults.object(forKey: "customerAccountEmail"))
        XCTAssertNil(defaults.object(forKey: FounderProfileDefaultsMigration.profileLastSavedAtKey))
        XCTAssertNil(defaults.object(forKey: "closetItemsData"))
        XCTAssertNil(defaults.object(forKey: "closetInventory"))
        XCTAssertNil(defaults.object(forKey: "wishlistProductNamesData"))
        XCTAssertNil(defaults.object(forKey: "outfitScanHistoryData"))
        XCTAssertNil(defaults.object(forKey: "preferredAIAssistant"))
        XCTAssertNil(defaults.object(forKey: "connectedAIAssistants"))
        XCTAssertNil(defaults.object(forKey: "openAIModel"))
        XCTAssertNil(defaults.object(forKey: "shareAppContextWithChatGPT"))

        XCTAssertNil(defaults.object(forKey: PersonalStylistStorage.scopedKey(PersonalStylistStorage.legacyProfileKey, userID: userA)))
        XCTAssertNil(defaults.object(forKey: PersonalStylistStorage.scopedKey(PersonalStylistStorage.legacyMemoriesKey, userID: userA)))
        XCTAssertTrue(ShoppingLocalStore(defaults: defaults, userID: userA).savedFavorites.isEmpty)
        XCTAssertTrue(ShoppingLocalStore(defaults: defaults, userID: userA).wishlistProductIDs.isEmpty)
        XCTAssertTrue(ShoppingLocalStore(defaults: defaults, userID: userA).cartProductIDs.isEmpty)

        XCTAssertNotNil(defaults.object(forKey: PersonalStylistStorage.scopedKey(PersonalStylistStorage.legacyProfileKey, userID: userB)))
        XCTAssertNotNil(defaults.object(forKey: PersonalStylistStorage.scopedKey(PersonalStylistStorage.legacyMemoriesKey, userID: userB)))
        XCTAssertEqual(ShoppingLocalStore(defaults: defaults, userID: userB).savedFavorites, ["favorite-b"])
        XCTAssertEqual(ShoppingLocalStore(defaults: defaults, userID: userB).wishlistProductIDs, ["wishlist-b"])
    }

    func testDeprecatedAIAssistantPreferenceRepairClearsLegacyProviderState() {
        defaults.set("ChatGPT", forKey: DeprecatedAIAssistantPreferenceRepair.preferredKey)
        defaults.set("ChatGPT,Gemini", forKey: DeprecatedAIAssistantPreferenceRepair.connectedKey)
        defaults.set("tester@example.com", forKey: "customerAccountEmail")

        DeprecatedAIAssistantPreferenceRepair.run(defaults: defaults)

        XCTAssertNil(defaults.object(forKey: DeprecatedAIAssistantPreferenceRepair.preferredKey))
        XCTAssertNil(defaults.object(forKey: DeprecatedAIAssistantPreferenceRepair.connectedKey))
        XCTAssertEqual(defaults.string(forKey: "customerAccountEmail"), "tester@example.com")
    }

    func testThirdPartyAssistantProviderCopyIsRemovedFromPublicAISurfaces() throws {
        let surfaces = [
            "StyleMatchAI/ProfileView.swift",
            "StyleMatchAI/HomeView.swift",
            "StyleMatchAI/ContentView.swift",
            "StyleMatchAI/AIAssistantsView.swift"
        ]
        let forbiddenPhrases = [
            "Preferred AI Assistant",
            "Choose AI Assistant",
            "Choose Your AI Stylist",
            "Switch AI",
            "Powered by ChatGPT",
            "ChatGPT powers",
            "Sign in with ChatGPT",
            "ChatGPT Awareness",
            "ChatGPT App Awareness",
            "ChatGPT Live Assistant",
            "ChatGPT Subscription Access",
            "Open ChatGPT",
            "Message ChatGPT",
            "Ask ChatGPT Stylist",
            "Siri AI",
            "Gemini AI",
            "Claude AI",
            "Perplexity AI",
            "Preferred assistant:"
        ]

        for file in surfaces {
            let source = try projectSource(file)
            for phrase in forbiddenPhrases {
                XCTAssertFalse(source.contains(phrase), "\(file) still contains \(phrase)")
            }
        }
    }

    func testPromptContextDoesNotIncludePreferredAssistantLine() throws {
        for file in [
            "StyleMatchAI/ContentView.swift",
            "StyleMatchAI/PersonalStylist/StylistContextBuilder.swift",
            "StyleMatchAI/AIAssistantsView.swift"
        ] {
            XCTAssertFalse(try projectSource(file).contains("Preferred assistant:"))
        }
    }

    func testLegacyProfileKeyMigrationPurgesGlobalKeysOnlyOnce() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let morning = Date(timeIntervalSince1970: 1_704_094_800) // 2024-01-01 09:00:00 UTC

        for key in LegacyProfileKeyMigration.legacyGlobalProfileKeys {
            defaults.set("LeakedName", forKey: key)
        }

        let scopedProfileKey = PersonalStylistStorage.scopedKey(PersonalStylistStorage.legacyProfileKey, userID: userA)
        let scopedMemoryKey = PersonalStylistStorage.scopedKey(PersonalStylistStorage.legacyMemoriesKey, userID: userA)
        let scopedShoppingKey = PersonalStylistStorage.scopedKey(ShoppingLocalStore.savedFavoritesBaseKey, userID: userA)
        let profileData = Data("profile".utf8)
        let memoryData = Data("memory".utf8)
        defaults.set(profileData, forKey: scopedProfileKey)
        defaults.set(memoryData, forKey: scopedMemoryKey)
        defaults.set(["keep-favorite"], forKey: scopedShoppingKey)

        LegacyProfileKeyMigration.run(defaults: defaults)

        for key in LegacyProfileKeyMigration.legacyGlobalProfileKeys {
            XCTAssertNil(defaults.object(forKey: key), "Legacy global key \(key) should be purged.")
        }
        XCTAssertTrue(defaults.bool(forKey: LegacyProfileKeyMigration.migrationFlag))
        XCTAssertEqual(
            StyleMatchGreetingBuilder.greetingLine(date: morning, calendar: calendar, storedName: defaults.string(forKey: "profileName")),
            "Good Morning"
        )
        XCTAssertEqual(defaults.data(forKey: scopedProfileKey), profileData)
        XCTAssertEqual(defaults.data(forKey: scopedMemoryKey), memoryData)
        XCTAssertEqual(defaults.stringArray(forKey: scopedShoppingKey), ["keep-favorite"])

        defaults.set("ShouldRemainAfterCompletedMigration", forKey: "profileName")
        LegacyProfileKeyMigration.run(defaults: defaults)

        XCTAssertEqual(
            defaults.string(forKey: "profileName"),
            "ShouldRemainAfterCompletedMigration",
            "After the one-time flag is set, the migration should be a no-op."
        )
        XCTAssertEqual(defaults.data(forKey: scopedProfileKey), profileData)
        XCTAssertEqual(defaults.data(forKey: scopedMemoryKey), memoryData)
        XCTAssertEqual(defaults.stringArray(forKey: scopedShoppingKey), ["keep-favorite"])
    }

    func testStartupLaunchRepairPurgesStaleLegacyProfileKeys() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let morning = Date(timeIntervalSince1970: 1_704_094_800) // 2024-01-01 09:00:00 UTC

        defaults.removeObject(forKey: LegacyProfileKeyMigration.migrationFlag)
        defaults.set(["Saba", "stine"].joined(), forKey: "profileName")
        defaults.set("XL", forKey: "shirtSize")
        defaults.set("Nike, Levi's", forKey: "favoriteBrands")
        defaults.set("clean casual", forKey: "stylePreferences")

        let scopedProfileKey = PersonalStylistStorage.scopedKey(PersonalStylistStorage.legacyProfileKey, userID: userA)
        let scopedMemoryKey = PersonalStylistStorage.scopedKey(PersonalStylistStorage.legacyMemoriesKey, userID: userA)
        let scopedProfileData = Data("scoped-profile".utf8)
        let scopedMemoryData = Data("scoped-memory".utf8)
        defaults.set(scopedProfileData, forKey: scopedProfileKey)
        defaults.set(scopedMemoryData, forKey: scopedMemoryKey)

        StyleMatchAppLaunchMigrations.run(defaults: defaults)

        XCTAssertNil(defaults.object(forKey: "profileName"))
        XCTAssertNil(defaults.object(forKey: "shirtSize"))
        XCTAssertNil(defaults.object(forKey: "favoriteBrands"))
        XCTAssertNil(defaults.object(forKey: "stylePreferences"))
        XCTAssertTrue(defaults.bool(forKey: LegacyProfileKeyMigration.migrationFlag))
        XCTAssertEqual(
            StyleMatchGreetingBuilder.greetingLine(date: morning, calendar: calendar, storedName: defaults.string(forKey: "profileName")),
            "Good Morning"
        )
        XCTAssertEqual(defaults.data(forKey: scopedProfileKey), scopedProfileData)
        XCTAssertEqual(defaults.data(forKey: scopedMemoryKey), scopedMemoryData)
    }


    func testAppleSignInNameResolverUsesAppleNameWhenProvided() {
        let resolved = StyleMatchAccountNameResolver.resolve(
            appleGivenName: " Sabastine ",
            appleFamilyName: " Esisorigho ",
            localDisplayName: "Old Local Name",
            storedProfileGivenName: "OldStored"
        )

        XCTAssertEqual(resolved.displayName, "Sabastine Esisorigho")
        XCTAssertEqual(resolved.givenName, "Sabastine")
        XCTAssertEqual(resolved.source, .appleCredential)
    }

    func testAppleSignInNameResolverPreservesLocalNameWhenAppleReturnsNoName() {
        let resolved = StyleMatchAccountNameResolver.resolve(
            appleGivenName: nil,
            appleFamilyName: nil,
            localDisplayName: "Saved Local Name",
            storedProfileGivenName: nil
        )

        XCTAssertEqual(resolved.displayName, "Saved Local Name")
        XCTAssertEqual(resolved.givenName, "Saved")
        XCTAssertEqual(resolved.source, .localDisplayName)
    }

    func testAppleSignInNameResolverRestoresStoredProfileNameWhenLocalNameIsBlank() {
        let resolved = StyleMatchAccountNameResolver.resolve(
            appleGivenName: nil,
            appleFamilyName: nil,
            localDisplayName: "  ",
            storedProfileGivenName: "Sabastine"
        )

        XCTAssertEqual(resolved.displayName, "Sabastine")
        XCTAssertEqual(resolved.givenName, "Sabastine")
        XCTAssertEqual(resolved.source, .storedProfile)
    }

    func testAppleSignInNameResolverDoesNotInventNameWhenNothingExists() {
        let resolved = StyleMatchAccountNameResolver.resolve(
            appleGivenName: nil,
            appleFamilyName: nil,
            localDisplayName: "",
            storedProfileGivenName: nil
        )

        XCTAssertNil(resolved.displayName)
        XCTAssertNil(resolved.givenName)
        XCTAssertEqual(resolved.source, .unavailable)
    }

    func testBlankProfileDraftNameMergesStoredProfileNameWithoutClearingIt() {
        XCTAssertEqual(
            StyleMatchAccountNameResolver.mergeDraftName("", storedProfileGivenName: "Sabastine"),
            "Sabastine"
        )
        XCTAssertEqual(
            StyleMatchAccountNameResolver.mergeDraftName("Manually Entered", storedProfileGivenName: "Sabastine"),
            "Manually Entered"
        )
    }

    func testAppleCredentialApplierPersistsFirstAuthFullNameToPerUserProfile() {
        let result = StyleMatchAppleCredentialProfileApplier.applyAppleCredential(
            userID: userA,
            email: "tester@example.com",
            appleGivenName: "Sabastine",
            appleFamilyName: "Esisorigho",
            localDisplayName: nil,
            defaults: defaults
        )

        XCTAssertEqual(result.displayName, "Sabastine Esisorigho")
        XCTAssertEqual(result.givenName, "Sabastine")
        XCTAssertEqual(result.email, "tester@example.com")
        XCTAssertEqual(result.source, .appleCredential)
        XCTAssertEqual(ProfileStore(defaults: defaults, userId: userA).currentProfile.givenName, "Sabastine")
        XCTAssertEqual(
            defaults.string(forKey: StyleMatchAppleCredentialProfileApplier.scopedEmailKey(userID: userA)),
            "tester@example.com"
        )
    }

    func testAppleCredentialApplierNilFullNameDoesNotClobberSavedName() {
        ProfileStore(defaults: defaults, userId: userA).updateGivenName("Saved")

        let result = StyleMatchAppleCredentialProfileApplier.applyAppleCredential(
            userID: userA,
            email: nil,
            appleGivenName: nil,
            appleFamilyName: nil,
            localDisplayName: "Local Other",
            defaults: defaults
        )

        XCTAssertEqual(result.displayName, "Saved")
        XCTAssertEqual(result.givenName, "Saved")
        XCTAssertEqual(result.source, .storedProfile)
        XCTAssertEqual(ProfileStore(defaults: defaults, userId: userA).currentProfile.givenName, "Saved")
    }

    func testAppleCredentialApplierPersistsTrustedNameEvenWhenGreetingBlocksIt() {
        let trustedName = ["Saba", "stine"].joined()
        XCTAssertNil(StyleMatchGreetingBuilder.firstName(from: trustedName))

        let result = StyleMatchAppleCredentialProfileApplier.applyAppleCredential(
            userID: userA,
            email: nil,
            appleGivenName: trustedName,
            appleFamilyName: nil,
            localDisplayName: nil,
            defaults: defaults
        )

        XCTAssertEqual(result.displayName, trustedName)
        XCTAssertEqual(result.givenName, trustedName)
        XCTAssertEqual(result.source, .appleCredential)
        XCTAssertEqual(ProfileStore(defaults: defaults, userId: userA).currentProfile.givenName, trustedName)
    }

    func testAccountModeDisplayStatusTitleUsesShortValues() {
        XCTAssertEqual(StyleMatchAccountModeDisplay.accountStatusTitle(for: "Sign in with Apple"), "Signed in with Apple")
        XCTAssertEqual(StyleMatchAccountModeDisplay.accountStatusTitle(for: "Guest"), "Guest")
        XCTAssertEqual(StyleMatchAccountModeDisplay.accountStatusTitle(for: "Email and Password"), "Email account")
        XCTAssertNotEqual(
            StyleMatchAccountModeDisplay.accountStatusTitle(for: "Sign in with Apple"),
            "Recommended for customers who want private account sign-in, cloud sync, wishlist, and future order history."
        )
    }

    // MARK: - Garment-only color palette regression tests

    func testGarmentPaletteExcludesBackgroundAndSkin() {
        var samples: [GarmentPalettePixel] = []

        samples += repeatedPixels(count: 80, red: 248, green: 248, blue: 242, isInsidePersonMask: true)
        samples += repeatedPixels(count: 64, red: 90, green: 90, blue: 90, isInsidePersonMask: true)
        samples += repeatedPixels(count: 52, red: 145, green: 95, blue: 55, isInsidePersonMask: false)
        samples += repeatedPixels(count: 44, red: 171, green: 118, blue: 76, isInsidePersonMask: true, isLikelySkinZone: true)

        let result = GarmentColorPaletteEngine.extractPalette(from: samples)

        XCTAssertTrue(result.palette.contains("white"), "White shirt should remain in garment palette")
        XCTAssertTrue(result.palette.contains("gray") || result.palette.contains("charcoal"), "Gray/charcoal pants should remain in garment palette")
        XCTAssertFalse(result.palette.contains("brown"), "Wood/floor background must not enter garment palette")
        XCTAssertFalse(result.palette.contains("beige"), "Skin-like pixels must not enter garment palette")
        XCTAssertGreaterThanOrEqual(result.debug.personSamples, 180)
        XCTAssertGreaterThanOrEqual(result.debug.skinReferenceSamples, 40)
    }

    func testGarmentPaletteLowInformationDoesNotFallbackToFrameColors() {
        let samples = repeatedPixels(count: 30, red: 248, green: 248, blue: 242, isInsidePersonMask: true)
            + repeatedPixels(count: 80, red: 145, green: 95, blue: 55, isInsidePersonMask: false)

        let result = GarmentColorPaletteEngine.extractPalette(from: samples)

        XCTAssertEqual(result.palette, ["neutral"])
        XCTAssertLessThan(result.confidence, 40)
        XCTAssertTrue(result.debug.clusters.isEmpty)
    }

    private func repeatedPixels(
        count: Int,
        red: UInt8,
        green: UInt8,
        blue: UInt8,
        isInsidePersonMask: Bool,
        isLikelySkinZone: Bool = false
    ) -> [GarmentPalettePixel] {
        (0..<count).map { index in
            GarmentPalettePixel(
                red: red,
                green: green,
                blue: blue,
                x: Double(index % 10) / 10.0,
                y: Double(index / 10) / Double(max(1, count / 10)),
                isInsidePersonMask: isInsidePersonMask,
                isLikelySkinZone: isLikelySkinZone
            )
        }
    }
}

private final class SpyDealProvider: DealProvider {
    private let providedDeals: [Deal]
    private(set) var callCount = 0

    init(deals: [Deal]) {
        self.providedDeals = deals
    }

    func currentDeals() async throws -> [Deal] {
        callCount += 1
        return providedDeals
    }
}

private final class SpySaleNotificationScheduler: SaleNotificationScheduling {
    var authorizationGranted = true
    private(set) var authorizationRequests = 0
    private(set) var requests: [SaleNotificationRequest] = []

    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        return authorizationGranted
    }

    func schedule(_ request: SaleNotificationRequest) async {
        requests.append(request)
    }
}

private struct StaticProductCatalogProvider: ProductCatalogProvider {
    let products: [AffiliateProduct]

    func products() async throws -> [AffiliateProduct] {
        products
    }
}

private struct FailingProductCatalogProvider: ProductCatalogProvider {
    let error: Error

    func products() async throws -> [AffiliateProduct] {
        throw error
    }
}

private final class CatalogFallbackSpy: ProductCatalogProvider {
    let result: Result<[AffiliateProduct], Error>
    private(set) var callCount = 0

    init(result: Result<[AffiliateProduct], Error>) {
        self.result = result
    }

    func products() async throws -> [AffiliateProduct] {
        callCount += 1
        return try result.get()
    }
}

private final class CatalogTestURLProtocol: URLProtocol {
    enum Mode {
        case response(Data, Int)
        case failure(URLError.Code)
    }

    static var mode = Mode.failure(.notConnectedToInternet)
    static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        switch Self.mode {
        case .response(let data, let statusCode):
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://proxy.example.com")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        }
    }

    override func stopLoading() {}
}

private struct StaticShoppingIntegrationConfigProvider: ShoppingIntegrationConfigProvider {
    let storedConfig: ShoppingIntegrationConfig

    func config() throws -> ShoppingIntegrationConfig {
        storedConfig
    }
}

private struct StaticRetailerSearchAdapter: RetailerSearchAdapter {
    let retailerName: String
    let products: [AffiliateProduct]

    func search(_ query: ProductSearchQuery) async throws -> [AffiliateProduct] {
        products
    }
}

private struct FailingRetailerSearchAdapter: RetailerSearchAdapter {
    let retailerName: String

    func search(_ query: ProductSearchQuery) async throws -> [AffiliateProduct] {
        throw TestSearchError()
    }
}

private struct SlowRetailerSearchAdapter: RetailerSearchAdapter {
    let retailerName: String
    let products: [AffiliateProduct]
    let delayNanoseconds: UInt64

    func search(_ query: ProductSearchQuery) async throws -> [AffiliateProduct] {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return products
    }
}

private final class SpyRetailerSearchAdapter: RetailerSearchAdapter {
    let retailerName: String
    let products: [AffiliateProduct]
    private(set) var callCount = 0

    init(retailerName: String, products: [AffiliateProduct]) {
        self.retailerName = retailerName
        self.products = products
    }

    func search(_ query: ProductSearchQuery) async throws -> [AffiliateProduct] {
        callCount += 1
        return products
    }
}

private struct TestSearchError: Error {}

extension StyleMatchProPhase2Tests {
    func testUniversalSearchRanksPrefixAboveSubstring() {
        let provider = DefaultSearchIndexService()
        let context = StyleMatchSearchContext(
            closetItems: [
                ClosetItem(name: "Oxford Shoes", category: "Shoes", color: "Brown", brand: "Cole Haan", size: "12", occasion: "Work", notes: "Leather shoes"),
                ClosetItem(name: "Shoe Care Kit", category: "Accessory", color: "Neutral", brand: "KigoStylist", size: "One Size", occasion: "General", notes: "Cleaner")
            ],
            outfitMemories: [],
            appDestinations: []
        )

        let results = provider.search("shoe", in: context)

        XCTAssertEqual(results.first?.title, "Shoe Care Kit")
        XCTAssertTrue(results.contains(where: { $0.title == "Oxford Shoes" }))
    }

    func testUniversalSearchIsCaseAndDiacriticInsensitive() {
        let provider = DefaultSearchIndexService()
        let context = StyleMatchSearchContext(
            closetItems: [
                ClosetItem(name: "Café Sneaker", category: "Shoes", color: "White", brand: "Nike", size: "12", occasion: "Casual", notes: "")
            ],
            outfitMemories: [],
            appDestinations: []
        )

        let results = provider.search("CAFE", in: context)

        XCTAssertEqual(results.first?.title, "Café Sneaker")
    }

    func testUniversalSearchEmptyQueryReturnsRecentItemsBeforeDestinations() {
        let provider = DefaultSearchIndexService()
        let olderMemory = makeSearchMemory(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            date: Date(timeIntervalSince1970: 100),
            style: "Casual",
            colors: ["white"]
        )
        let newerMemory = makeSearchMemory(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            date: Date(timeIntervalSince1970: 200),
            style: "Smart Casual",
            colors: ["navy"]
        )
        let context = StyleMatchSearchContext(
            closetItems: [],
            outfitMemories: [olderMemory, newerMemory],
            appDestinations: StyleMatchAppDestination.defaults
        )

        let results = provider.search("", in: context)

        XCTAssertEqual(results.first?.title, "Smart Casual")
        XCTAssertNotEqual(results.first?.section, .appScreens)
    }

    func testUniversalSearchZeroResultReturnsEmptyArray() {
        let provider = DefaultSearchIndexService()
        let context = StyleMatchSearchContext(
            closetItems: [
                ClosetItem(name: "White Oxford", category: "Shirt", color: "White", brand: "Ralph Lauren", size: "XL", occasion: "Work", notes: "")
            ],
            outfitMemories: [],
            appDestinations: StyleMatchAppDestination.defaults
        )

        let results = provider.search("zzzxxyy", in: context)

        XCTAssertTrue(results.isEmpty)
    }

    func testUniversalSearchRanksClosetAboveAppDestinationsForSameMatchType() {
        let provider = DefaultSearchIndexService()
        let context = StyleMatchSearchContext(
            closetItems: [
                ClosetItem(name: "Closet Denim Jacket", category: "Jacket", color: "Blue", brand: "Levi's", size: "XL", occasion: "Casual", notes: "")
            ],
            outfitMemories: [],
            appDestinations: [
                StyleMatchAppDestination(id: "closet", title: "Closet", subtitle: "View saved clothing", keywords: ["closet"])
            ]
        )

        let results = provider.search("clos", in: context)

        XCTAssertEqual(results.first?.section, .closet)
        XCTAssertEqual(results.first?.title, "Closet Denim Jacket")
    }

    private func makeSearchMemory(id: UUID, date: Date, style: String, colors: [String]) -> OutfitMemory {
        OutfitMemory(
            id: id,
            userId: userA,
            scanDate: date,
            detectedGarments: ["shirt", "pants"],
            colors: colors,
            detectedStyle: style,
            styleScore: 88,
            occasion: .casual,
            wasWorn: nil,
            wasLiked: nil,
            feedbackTimestamp: nil,
            dislikeReason: nil,
            wouldWearAgain: nil,
            receivedCompliments: nil,
            isFavorite: false,
            timesWorn: 0
            , outfitFingerprint: "sanitized-outfit"
        )
    }
}

private final class CapturingURLProtocol: URLProtocol {
    static var lastURL: URL?
    static var lastRequest: URLRequest?
    static var lastRequestBody: Data?
    static var responseData = Data("[]".utf8)
    static var statusCode = 200

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lastURL = request.url
        Self.lastRequest = request
        Self.lastRequestBody = request.httpBody ?? Self.readBodyStream(request.httpBodyStream)
        let data = Self.responseData
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://proxy.example.com")!,
            statusCode: Self.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readBodyStream(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var body = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            body.append(buffer, count: count)
        }
        return body.isEmpty ? nil : body
    }
}

final class GarmentPaletteAndLabelSanitizationTests: XCTestCase {
    func testGarmentRegionMaskerUsesSecondTierAfterFirstFails() {
        let personMask = GarmentRegionMask(
            width: 2,
            height: 2,
            included: [true, true, false, false],
            tier: .personSegmentation
        )
        var attempted: [GarmentMaskTier] = []

        let mask = GarmentRegionMasker.tieredMask(
            width: 2,
            height: 2,
            minimumIncludedPixels: 1,
            foregroundSubject: {
                attempted.append(.foregroundSubject)
                return nil
            },
            personSegmentation: {
                attempted.append(.personSegmentation)
                return personMask
            },
            saliencyCrop: {
                attempted.append(.saliencyCrop)
                return nil
            }
        )

        XCTAssertEqual(mask.tier, .personSegmentation)
        XCTAssertEqual(mask.includedCount, 2)
        XCTAssertEqual(attempted, [.foregroundSubject, .personSegmentation])
    }

    func testGarmentRegionMaskerAllTierFailureReturnsTypedFailureWithoutPalette() {
        var attempted: [GarmentMaskTier] = []

        let mask = GarmentRegionMasker.tieredMask(
            width: 2,
            height: 2,
            minimumIncludedPixels: 1,
            foregroundSubject: {
                attempted.append(.foregroundSubject)
                return nil
            },
            personSegmentation: {
                attempted.append(.personSegmentation)
                return nil
            },
            saliencyCrop: {
                attempted.append(.saliencyCrop)
                return nil
            }
        )

        XCTAssertEqual(mask.tier, .couldNotIsolateGarment)
        XCTAssertEqual(mask.includedCount, 0)
        XCTAssertFalse(mask.maskingApplied)
        XCTAssertTrue(mask.included.allSatisfy { !$0 })
        XCTAssertEqual(attempted, [.foregroundSubject, .personSegmentation, .saliencyCrop])
    }

    func testPaletteExtractionSamplesOnlyIncludedGarmentPixels() {
        let garmentPixels = (0..<80).map { _ in
            GarmentPalettePixel(red: 245, green: 245, blue: 240, isInsidePersonMask: true, isLikelySkinZone: false)
        }
        let ignoredBackgroundPixels = (0..<120).map { _ in
            GarmentPalettePixel(red: 150, green: 105, blue: 70, isInsidePersonMask: false, isLikelySkinZone: false)
        }
        let ignoredSkinPixels = (0..<80).map { _ in
            GarmentPalettePixel(red: 175, green: 118, blue: 80, isInsidePersonMask: true, isLikelySkinZone: true)
        }

        let result = GarmentColorPaletteEngine.extractPalette(
            from: garmentPixels + ignoredBackgroundPixels + ignoredSkinPixels,
            minimumGarmentPixels: 20
        )

        XCTAssertTrue(result.palette.contains("white"), "Expected garment white to survive; got \(result.palette)")
        XCTAssertFalse(result.palette.contains("brown"), "Background brown must not enter the garment palette.")
        XCTAssertFalse(result.palette.contains("beige"), "Skin/background beige must not enter the garment palette.")
    }

    func testGarmentLabelMapperDropsInternalLabels() {
        let labels = [
            "Textile",
            "Person Wearing Outfit",
            "Apparel",
            "Clothing",
            "Fabric"
        ]

        XCTAssertTrue(GarmentLabelMapper.sanitizedTerms(from: labels).isEmpty)
    }

    func testGarmentLabelMapperMapsHumanGarmentTerms() {
        let labels = [
            "jersey, T-shirt",
            "polo",
            "blue jeans",
            "bathrobe",
            "slipper"
        ]

        XCTAssertEqual(
            GarmentLabelMapper.sanitizedTerms(from: labels),
            ["t-shirt", "polo shirt", "jeans", "robe", "slippers"]
        )
    }

    func testOutfitAnalysisResultSanitizesStoredDetectedItems() {
        let analysis = makeAnalysis(detectedItems: ["Textile", "Person Wearing Outfit", "polo"])

        XCTAssertEqual(analysis.detectedClothingItems, ["polo shirt"])
        XCTAssertEqual(analysis.safeDetectedClothingItems, ["polo shirt"])
    }

    func testOutfitShareInsightsComeFromStoredAnalysisAndSurviveRoundTrip() throws {
        let analysis = makeAnalysis(
            suggestions: [
                "Fit check: using your saved size profile, review the sleeves and waist.",
                "Weather check: New York. Add a breathable layer for the heat."
            ],
            recommendations: [
                ClothingRecommendation(
                    category: "Balance",
                    title: "Build a cleaner color bridge",
                    reason: "One stronger palette connection will improve the outfit.",
                    personalization: "Favorite colors saved: navy and gold."
                ),
                ClothingRecommendation(
                    category: "Shoes",
                    title: "Choose cleaner sneakers",
                    reason: "The footwear should anchor the lower half.",
                    personalization: "Saved shoe size: 11."
                )
            ]
        )

        let expected = ["Improve color balance", "Adjust footwear", "Improve fit or layering"]
        XCTAssertEqual(OutfitShareInsightBuilder.insights(from: analysis), expected)

        let storedAnalysis = try JSONDecoder().decode(
            OutfitAnalysisResult.self,
            from: JSONEncoder().encode(analysis)
        )
        let restoredInsights = OutfitShareInsightBuilder.insights(from: storedAnalysis)

        XCTAssertEqual(restoredInsights, expected)
        XCTAssertFalse(restoredInsights.joined().localizedCaseInsensitiveContains("New York"))
        XCTAssertFalse(restoredInsights.joined().localizedCaseInsensitiveContains("size"))
    }

    func testOutfitShareInsightsUseExactCoordinatedFallbackWhenAnalysisHasNone() {
        let analysis = makeAnalysis(suggestions: [], recommendations: [])

        XCTAssertEqual(
            OutfitShareInsightBuilder.insights(from: analysis),
            ["This outfit is already well coordinated. Small accessory or fit adjustments may improve the score further."]
        )
    }

    func testOutfitRecallDoesNotEchoRawGarmentLabelsFromOldMemories() {
        var memory = OutfitMemory(
            id: UUID(),
            userId: "test-user",
            scanDate: Date(timeIntervalSince1970: 1_000),
            detectedGarments: ["Textile", "Person Wearing Outfit", "polo"],
            colors: ["white"],
            detectedStyle: "Casual",
            styleScore: 82,
            occasion: .casual,
            wasWorn: nil,
            wasLiked: nil,
            feedbackTimestamp: nil,
            dislikeReason: nil,
            wouldWearAgain: nil,
            receivedCompliments: nil,
            isFavorite: false,
            timesWorn: 0
        )
        memory.outfitFingerprint = "outfit-v4|sanitized-outfit"
        memory.imageDigest = "sanitized-image"

        let fact = OutfitRecallService.recallFact(
            for: OutfitRecallScanContext(
                detectedGarments: ["polo shirt"],
                colors: ["white"],
                detectedStyle: "Casual",
                outfitFingerprint: "outfit-v4|sanitized-outfit",
                imageDigest: "sanitized-image"
            ),
            memories: [memory],
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(fact?.text, "You wore white polo shirt today (score: 82).")
    }

    func testVoiceScriptBuilderScanSummaryIsBriefAndScoreAnchored() {
        let analysis = makeAnalysis(
            score: 86,
            styleBalance: "Casual",
            summary: "The colors work well together, with clean proportions for everyday wear.",
            recommendations: [
                ClothingRecommendation(
                    category: "shoes",
                    title: "clean white sneakers",
                    reason: "They sharpen the lower half.",
                    personalization: "Matches your closet."
                )
            ]
        )

        let message = VoiceScriptBuilder.scanResult(from: analysis).text

        XCTAssertTrue(message.contains("Your outfit score is 86 out of 100, which is a strong casual look."))
        XCTAssertTrue(message.contains("The colors work well together"))
        XCTAssertTrue(message.contains("Next, consider clean white sneakers."))
        XCTAssertLessThanOrEqual(message.count, VoiceScriptBuilder.maximumSpokenCharacters)
    }

    func testVoiceScriptBuilderDoesNotGuessForUnrecognizedResult() {
        let analysis = makeAnalysis(
            score: 42,
            styleBalance: "Unrecognized item",
            summary: "",
            suggestions: [],
            recommendations: []
        )

        let message = VoiceScriptBuilder.scanResult(from: analysis).text

        XCTAssertTrue(message.contains("could not identify this outfit clearly"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("business casual"))
        XCTAssertLessThanOrEqual(message.count, VoiceScriptBuilder.maximumSpokenCharacters)
    }

    func testVoiceScriptBuilderUsesConfirmedTypedOutfitCategory() {
        var analysis = makeAnalysis(
            score: 80,
            styleBalance: "Casual",
            summary: "The uniform is clean and coordinated."
        )
        analysis = analysis.replacingOutfitClassification(
            OutfitClassificationResult.uncertain(selectedOccasion: "work")
                .confirming(.workUniform)
        )

        let message = VoiceScriptBuilder.scanResult(from: analysis).text

        XCTAssertTrue(message.contains("80 out of 100"))
        XCTAssertTrue(message.contains("work uniform look"))
        XCTAssertFalse(message.contains("casual look"))
    }

    func testVoiceScriptBuilderAppGuideUsesKnownDestinations() {
        XCTAssertEqual(
            VoiceScriptBuilder.appGuide(destination: "Closet").text,
            "Use Closet to save clothing you own, so I can help build outfits from your real wardrobe."
        )

        XCTAssertEqual(
            VoiceScriptBuilder.appGuide(destination: "Something Else").text,
            "I can help you scan outfits, review your closet, understand scores, and find better matching pieces."
        )
    }

    func testVoiceScriptBuilderBuildsKeyMomentScripts() {
        XCTAssertEqual(VoiceScriptBuilder.scanStarted().kind, .scanStarted)
        XCTAssertTrue(VoiceScriptBuilder.profileSaved().text.contains("Profile saved"))
        XCTAssertTrue(VoiceScriptBuilder.scanFailed(title: "No outfit detected", description: "No visible clothing.").text.contains("clearer"))
        XCTAssertLessThanOrEqual(VoiceScriptBuilder.preview().text.count, VoiceScriptBuilder.maximumSpokenCharacters)
    }

    func testVoicePlaybackUsesOneSilentModeSafeTruthfulDiagnosticPath() throws {
        let service = try projectSource("StyleMatchAI/Services/VoiceStylistService.swift")
        let legacy = try projectSource("StyleMatchAI/VoiceAssistant/VoiceAssistantService.swift")
        let profile = try projectSource("StyleMatchAI/ProfileView.swift")
        let scan = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(service.contains("setCategory(.playback, mode: .spokenAudio"))
        XCTAssertFalse(service.contains("setCategory(.ambient"))
        XCTAssertTrue(service.contains("func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart"))
        XCTAssertTrue(service.contains("@Published private(set) var playbackErrorMessage"))
        XCTAssertTrue(service.contains("Logger(subsystem:"))
        XCTAssertTrue(service.contains("\"session_category_begin\""))
        XCTAssertTrue(service.contains("\"session_active_begin\""))
        XCTAssertTrue(service.contains("\"utterance_create_begin\""))
        XCTAssertTrue(service.contains("\"speak_returned\""))
        XCTAssertTrue(service.contains("\"startup_timeout\""))
        XCTAssertTrue(service.contains("\"duplicate_start_ignored\""))
        XCTAssertFalse(service.contains("Task.detached"))
        XCTAssertTrue(service.contains("private var synthesizer: AVSpeechSynthesizer?"))
        XCTAssertTrue(service.contains("preparePlaybackResourcesIfNeeded()"))
        XCTAssertFalse(service.contains("refreshVoiceSelection(reason: \"init\")"))
        XCTAssertTrue(service.contains("let descriptor = Self.resolveVoiceDescriptorSynchronously()"))
        XCTAssertTrue(service.contains("private var isPreparingSpeech = false"))
        XCTAssertTrue(service.contains("private var activeSpeechRequestID: UUID?"))
        XCTAssertTrue(service.contains("speechStartupTimeoutNanoseconds"))
        XCTAssertFalse(service.contains("activateAudioSessionIfNeeded()"))
        XCTAssertFalse(service.contains("DispatchSemaphore"))
        XCTAssertFalse(service.contains("DispatchQueue.main.sync"))
        XCTAssertTrue(service.contains("AVAudioSession.routeChangeNotification"))
        XCTAssertTrue(service.contains("AVAudioSession.mediaServicesWereResetNotification"))
        XCTAssertTrue(legacy.contains("typealias VoiceAssistantService = VoiceStylistService"))
        XCTAssertTrue(profile.contains("voiceAssistant.previewVoice()"))
        XCTAssertTrue(profile.contains("voiceAssistant.playbackErrorMessage"))
        XCTAssertTrue(scan.contains("voiceAssistant.speak(VoiceScriptBuilder.scanResult(from: result))"))
        XCTAssertTrue(scan.contains("voiceAssistant.playbackErrorMessage"))
    }

    func testProfilePrivacyPolicyUsesInjectedExternalURLActionWithVisibleFailureState() throws {
        let expectedURLString = "https://stylematchpro.com/privacy"
        let url = try XCTUnwrap(URL(string: expectedURLString))
        let profileSource = try projectSource("StyleMatchAI/ProfileView.swift")

        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "stylematchpro.com")
        XCTAssertEqual(url.path, "/privacy")
        XCTAssertNil(url.query)
        XCTAssertNil(url.fragment)
        XCTAssertFalse(expectedURLString.hasSuffix("."))
        XCTAssertEqual(expectedURLString, expectedURLString.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertFalse(expectedURLString.contains("goodnessoflifeandfun.com"))

        XCTAssertTrue(profileSource.contains("@Environment(\\.openURL) private var openURL"))
        XCTAssertTrue(profileSource.contains("URL(string: \"https://stylematchpro.com/privacy\")"))
        XCTAssertTrue(profileSource.contains("openURL(privacyPolicyURL) { accepted in"))
        XCTAssertTrue(profileSource.contains("if !accepted"))
        XCTAssertTrue(profileSource.contains("Unable to open Privacy Policy in your browser. Please try again later."))
        XCTAssertTrue(profileSource.contains("Label(\"Privacy Policy\", systemImage: \"hand.raised.fill\")"))
        XCTAssertTrue(profileSource.contains(".accessibilityLabel(\"Privacy Policy, link, opens in browser\")"))
        XCTAssertTrue(profileSource.contains(".accessibilityAddTraits(.isLink)"))
        XCTAssertFalse(profileSource.contains("Privacy Policy will open here when the public release page is connected."))
        XCTAssertTrue(profileSource.contains("Label(\"AI Customer Service\", systemImage: \"questionmark.circle.fill\")"))
    }

    func testUnfinishedPrivacyPolicyDraftIsNotAnAppResource() throws {
        let packageSource = try projectSource("Package.swift")
        let pbxSource = try projectSource("StyleMatchAI.xcodeproj/project.pbxproj")
        let profileSource = try projectSource("StyleMatchAI/ProfileView.swift")
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        XCTAssertFalse(packageSource.contains("PrivacyPolicyDocument.swift"))
        XCTAssertFalse(packageSource.contains("Legal/PrivacyPolicy.md"))
        XCTAssertFalse(pbxSource.contains("PrivacyPolicyFallbackView.swift"))
        XCTAssertFalse(pbxSource.contains("PrivacyPolicy.md in Resources"))
        XCTAssertFalse(profileSource.contains("PrivacyPolicyFallbackView"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("StyleMatchAI/Legal/PrivacyPolicy.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Documentation/PrivacyPolicyAIMemoryDraft.md").path))
    }

    func testProfilePrivacyStatementsAreStaticAndDataControlsPreserveLocalExport() throws {
        let profileSource = try projectSource("StyleMatchAI/ProfileView.swift")
        let sharedLinksSource = try projectSource("StyleMatchAI/ShareableScoreCardViews.swift")

        XCTAssertTrue(profileSource.contains("These are KigoStylist privacy commitments. Manage your actual data controls below."))
        XCTAssertTrue(profileSource.contains("Image(systemName: \"checkmark.shield.fill\")"))
        XCTAssertTrue(profileSource.contains(".accessibilityHidden(true)"))
        XCTAssertTrue(profileSource.contains(".accessibilityLabel(\"Privacy commitment: \\(text)\")"))
        XCTAssertTrue(profileSource.contains(".accessibilityRemoveTraits(.isButton)"))
        XCTAssertTrue(profileSource.contains(".frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)"))
        XCTAssertFalse(profileSource.contains("Toggle(text"))

        XCTAssertTrue(profileSource.contains("isOn: personalStyleMemoryBinding"))
        XCTAssertTrue(profileSource.contains("struct StyleMatchToggleRow: View"))
        XCTAssertTrue(profileSource.contains(".accessibilityValue(isOn ? \"On\" : \"Off\")"))
        XCTAssertTrue(profileSource.contains("Personal Style Memory is on."))
        XCTAssertTrue(profileSource.contains("Personal Style Memory is off. Clear AI Memory removes existing saved Personal Style Memory."))
        XCTAssertTrue(profileSource.contains("shareAppContextWithChatGPT = newValue"))
        XCTAssertTrue(profileSource.contains("shareAppContextWithChatGPT = previousValue"))
        XCTAssertTrue(profileSource.contains("UIAccessibility.post(notification: .announcement"))
        XCTAssertFalse(profileSource.contains("Turn Off Personal Style Memory"))
        XCTAssertTrue(profileSource.contains("title: \"Speak outfit guidance\""))
        XCTAssertTrue(profileSource.contains("isOn: voiceAssistantEnabledBinding"))
        XCTAssertTrue(profileSource.contains("VoiceAssistantSettings.enabledKey"))
        XCTAssertTrue(profileSource.contains("Speak outfit guidance is on."))
        XCTAssertTrue(profileSource.contains("Speak outfit guidance is off."))
        XCTAssertTrue(profileSource.contains("title: \"Cloud Sync\""))
        XCTAssertFalse(profileSource.contains("title: \"Enable Cloud Sync When Available\""))
        XCTAssertTrue(profileSource.contains("CloudSyncProductContract.preActivationConsentDetail"))
        XCTAssertTrue(profileSource.contains("isOn: cloudSyncPreferenceBinding"))
        XCTAssertTrue(profileSource.contains("isDisabled: !CloudSyncProductContract.customerControlsEnabled"))
        XCTAssertTrue(profileSource.contains("CloudSyncProductContract.preActivationConsentDetail"))
        XCTAssertTrue(profileSource.contains("customerAccountSyncEnabled"))
        XCTAssertFalse(profileSource.contains("Cloud sync will be used only for account features"))
        XCTAssertTrue(profileSource.contains("showClearScanHistoryConfirmation = true"))
        XCTAssertTrue(profileSource.contains("showClearAIMemoryConfirmation = true"))
        XCTAssertTrue(profileSource.contains("\"Clear scan history?\""))
        XCTAssertTrue(profileSource.contains("\"Clear AI memory?\""))
        XCTAssertTrue(profileSource.contains("Shows a confirmation before removing saved scan history"))
        XCTAssertTrue(profileSource.contains("Shows a confirmation before removing local Personal Style Memory"))

        XCTAssertFalse(profileSource.contains("LocalDataExportService"))
        XCTAssertFalse(profileSource.contains("Export local KigoStylist data"))
        XCTAssertFalse(profileSource.contains("Export Data"))
        XCTAssertFalse(profileSource.contains("isShowingLocalExportShareSheet"))
        XCTAssertTrue(profileSource.contains("isShowingSharedLinks = true"))
        XCTAssertTrue(sharedLinksSource.contains("Create Your First Shared Link"))
        XCTAssertTrue(profileSource.contains("profileInfoRow(\"Notifications\", \"Coming Soon\", icon: \"bell.slash.fill\")"))
        XCTAssertTrue(profileSource.contains(".accessibilityValue(\"Coming Soon, unavailable\")"))
        XCTAssertFalse(profileSource.contains("isShowingNotificationSettings"))
        XCTAssertFalse(profileSource.contains("NotificationSettingsPreviewView"))
        XCTAssertTrue(profileSource.contains("https://stylematchpro.com/privacy"))
        XCTAssertTrue(profileSource.contains("https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"))
    }

    func testProfileCloudSyncDiagnosticHydratesBoundedFailureWithoutOutboundValidation() throws {
        let profileSource = try projectSource("StyleMatchAI/ProfileView.swift")
        let coordinatorSource = try projectSource("StyleMatchAI/CrossDeviceSync/CloudSyncOwnerValidationCoordinator.swift")

        XCTAssertTrue(profileSource.contains("allowsInboundDiagnosticReconciliation"))
        XCTAssertTrue(profileSource.contains("hydratePersistedInboundFailureIfPresent"))
        XCTAssertTrue(profileSource.contains("CloudSyncInboundDiagnosticPresentation.feedback"))
        XCTAssertTrue(profileSource.contains("inboundFailureCategory()"))
        XCTAssertTrue(profileSource.contains("guard CloudSyncOwnerValidationConfiguration.runtime.allowsInboundDiagnosticReconciliation else"))
        XCTAssertTrue(profileSource.contains("ownerValidationCloudSyncStatus = nil"))
        XCTAssertTrue(profileSource.contains("cloudSyncPreferenceFeedback = nil"))
        let lifecycleTask = try XCTUnwrap(
            profileSource.components(separatedBy: ".task(id: accountSyncEnabled) {").dropFirst().first?
                .components(separatedBy: "\n\n        if CloudSyncProductContract.customerControlsEnabled").first
        )
        XCTAssertTrue(lifecycleTask.contains("allowsInboundDiagnosticReconciliation"))
        XCTAssertFalse(lifecycleTask.contains("enableAndValidate()"))
        XCTAssertTrue(profileSource.contains("CloudSyncProductContract.customerControlsEnabled && accountSyncEnabled"))
        XCTAssertTrue(profileSource.contains("Label(isCloudSyncLifecycleInFlight ? \"Syncing…\" : \"Sync Now\""))
        XCTAssertTrue(coordinatorSource.contains("buildNumber == \"18036\" && isDebugBuild"))
        XCTAssertTrue(coordinatorSource.contains("[\"18036\", \"18037\", \"18038\"].contains(buildNumber)"))
    }

    func testNotificationsComingSoonStateHasNoActivationPath() throws {
        let profileSource = try projectSource("StyleMatchAI/ProfileView.swift")
        let shoppingSource = try projectSource("StyleMatchAI/Shopping/ShoppingView.swift")
        let appSource = try projectSource("StyleMatchAI/StyleMatchAIApp.swift")

        XCTAssertTrue(profileSource.contains("profileInfoRow(\"Notifications\", \"Coming Soon\""))
        XCTAssertFalse(profileSource.contains("Notifications settings"))
        XCTAssertFalse(shoppingSource.contains("Button(\"Turn On\")"))
        XCTAssertFalse(shoppingSource.contains("optInSaleNotifications"))
        XCTAssertFalse(appSource.contains("SaleWatcherBackgroundRefresh.register()"))
        XCTAssertFalse(appSource.contains("SaleWatcherBackgroundRefresh.scheduleNextRefresh()"))
    }

    func testProfileTermsOfUseUsesAppleStandardEULAWithInjectedExternalURLAction() throws {
        let expectedURLString = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
        let url = try XCTUnwrap(URL(string: expectedURLString))
        let profileSource = try projectSource("StyleMatchAI/ProfileView.swift")

        XCTAssertEqual(url.absoluteString, expectedURLString)
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "www.apple.com")
        XCTAssertEqual(url.path, "/legal/internet-services/itunes/dev/stdeula")
        XCTAssertNil(url.query)
        XCTAssertNil(url.fragment)
        XCTAssertFalse(expectedURLString.hasSuffix("."))
        XCTAssertEqual(expectedURLString, expectedURLString.trimmingCharacters(in: .whitespacesAndNewlines))

        XCTAssertTrue(profileSource.contains("URL(string: \"https://www.apple.com/legal/internet-services/itunes/dev/stdeula/\")"))
        XCTAssertTrue(profileSource.contains("openURL(termsOfUseURL) { accepted in"))
        XCTAssertTrue(profileSource.contains("Terms of Use is unavailable. Please try again later."))
        XCTAssertTrue(profileSource.contains("Unable to open Terms of Use in your browser. Please try again later."))
        XCTAssertTrue(profileSource.contains("Label(\"Terms of Use\", systemImage: \"doc.text\")"))
        XCTAssertTrue(profileSource.contains(".accessibilityLabel(\"Terms of Use, link, opens in browser\")"))
        XCTAssertTrue(profileSource.contains(".accessibilityAddTraits(.isLink)"))
        XCTAssertFalse(profileSource.contains("Terms of Use will open here when the public release page is connected."))
        XCTAssertTrue(profileSource.contains("URL(string: \"https://stylematchpro.com/privacy\")"))
        XCTAssertTrue(profileSource.contains("Label(\"AI Customer Service\", systemImage: \"questionmark.circle.fill\")"))
    }

    func testConversationalStylistVoiceInputUsesTypedMinimizedPathOnly() throws {
        let speech = try projectSource("StyleMatchAI/StylistChat/StylistSpeechInputService.swift")
        let chatView = try projectSource("StyleMatchAI/StylistChat/StylistChatView.swift")
        let context = try projectSource("StyleMatchAI/PersonalStylist/StylistContextBuilder.swift")

        XCTAssertTrue(speech.contains("SFSpeechRecognizer.requestAuthorization"))
        XCTAssertTrue(speech.contains("requestRecordPermission"))
        XCTAssertTrue(speech.contains("guard buffer.frameLength > 0 else { return }"))
        XCTAssertTrue(speech.contains("UIApplication.didEnterBackgroundNotification"))
        XCTAssertTrue(speech.contains("AVAudioSession.interruptionNotification"))

        XCTAssertTrue(chatView.contains("@StateObject private var speechInput: StylistSpeechInputService"))
        XCTAssertTrue(chatView.contains("_speechInput = StateObject(wrappedValue: speechInput ?? StylistSpeechInputService())"))
        XCTAssertTrue(chatView.contains("await speechInput.startListening(existingText: draft)"))
        XCTAssertTrue(chatView.contains("speechInput.stopListening()"))
        XCTAssertTrue(chatView.contains("speechInput.cancelListening()"))
        XCTAssertTrue(chatView.contains("guard submitQuestion(capturedDraft) else { return }"))
        XCTAssertTrue(chatView.contains("let assembly = currentConversationAssembly(including: question)"))
        XCTAssertTrue(chatView.contains("forcedContext: context"))
        XCTAssertTrue(chatView.contains("intelligenceSnapshot: assembly.snapshot"))
        XCTAssertFalse(chatView.contains("service.send(question, forcedContext: currentConversationContext(including: question))"))
        XCTAssertFalse(chatView.contains("OpenAIStylistClient"))
        XCTAssertFalse(chatView.contains("askStylist(profile:"))

        XCTAssertTrue(context.contains("static func conversationalStylistContext("))
        XCTAssertTrue(context.contains("screenContext: StylistScreenContext"))
        XCTAssertFalse(context.contains("declaredUndertone:"))
        XCTAssertFalse(context.contains("skinToneStyleNote:"))
    }

    func testStylistContextEncodingFailsClosedWithoutForcedCrash() throws {
        let context = try projectSource("StyleMatchAI/PersonalStylist/StylistContextBuilder.swift")

        XCTAssertFalse(context.contains("try! encoder.encode(payload)"))
        XCTAssertTrue(context.contains("Verified scan context could not be encoded."))
        XCTAssertTrue(context.contains("Do not infer a score, garment, occasion, or weather fact."))
    }

    func testScreenContextLifecycleUsesSendTimeStateAndInvalidatesCancelledOrDeletedScans() throws {
        let content = try projectSource("StyleMatchAI/ContentView.swift")
        let scan = try projectSource("StyleMatchAI/ScanView.swift")
        let chat = try projectSource("StyleMatchAI/StylistChat/StylistChatView.swift")

        XCTAssertTrue(content.contains("initialContext: activeStylistScanHandoff?.aiChatContext"))
        XCTAssertTrue(content.contains("activeStylistScanHandoff?.aiScreenContext"))
        XCTAssertTrue(content.contains("stylistEntryPointForAI(from:"))
        XCTAssertTrue(content.contains("case .shop:\n            return .shopping"))
        XCTAssertTrue(content.contains("scanStylistHandoff == nil ? .scanTab : .scanResult"))

        XCTAssertTrue(scan.contains("StylistActiveScanStateResolver.resolve("))
        XCTAssertTrue(scan.contains("savedScanIDs: Set(loadScanHistory().keys)"))
        XCTAssertTrue(scan.contains("let deletedActiveScan = activeScanFingerprint.map(selectedScanIDs.contains) ?? false"))
        XCTAssertTrue(scan.contains("if deletedActiveScan {\n            invalidateActiveScanSession()\n            result = nil\n            preparedAnalysis = nil"))
        XCTAssertTrue(scan.contains("private func prepareNewCameraSession() {\n        invalidateActiveScanSession()\n        _ = gallerySelectionCoordinator.beginSelection()\n        isAnalyzing = false\n        selectedItem = nil"))
        XCTAssertTrue(scan.contains("selectedItem = nil\n        previewImageSourceToken = nil\n        visionImageSourceToken = nil\n        displayedImageSourceToken = nil\n        result = nil"))
        XCTAssertTrue(scan.contains("private func loadImage(from item: PhotosPickerItem?, selectionToken: UUID) async {"))
        XCTAssertTrue(scan.contains("guard gallerySelectionCoordinator.accepts(selectionToken) else {"))
        XCTAssertTrue(scan.contains("onStylistScanHandoffChanged(currentStylistScanHandoff)"))
        XCTAssertTrue(scan.contains("onStylistScanHandoffChanged(handoff)"))
        XCTAssertTrue(scan.contains("publishCurrentStylistScanHandoff(source: \"saved_scan_open\")"))

        XCTAssertTrue(chat.contains("StylistConversationScreenContextResolver.resolve("))
        XCTAssertTrue(chat.contains("applyingCurrentScreenContext(currentScreenContext)"))
        XCTAssertTrue(chat.contains("applyCurrentScanHandoff()"))
        XCTAssertTrue(chat.contains("hasExplicitlySelectedGeneralStylist"))
        XCTAssertTrue(chat.contains("switchToGeneralStylist()"))
    }

    func testConversationalStylistVoiceInputHasPermissionCopyAndAccessibilityLabels() throws {
        let plist = try projectSource("StyleMatchAI/Info.plist")
        let chatView = try projectSource("StyleMatchAI/StylistChat/StylistChatView.swift")

        XCTAssertTrue(plist.contains("NSMicrophoneUsageDescription"))
        XCTAssertTrue(plist.contains("NSSpeechRecognitionUsageDescription"))
        XCTAssertTrue(plist.contains("only when you tap voice input"))
        XCTAssertTrue(chatView.contains(".accessibilityLabel(\"Ask stylist by voice\")"))
        XCTAssertTrue(chatView.contains("Stop listening"))
        XCTAssertTrue(chatView.contains("Cancel voice input"))
        XCTAssertTrue(chatView.contains(".accessibilityLabel(\"Clear transcript\")"))
    }

    func testAIManagerReadAloudUsesOnlyVisibleAssistantContentAndCoordinatesAudio() throws {
        let chatView = try projectSource("StyleMatchAI/StylistChat/StylistChatView.swift")

        XCTAssertTrue(chatView.contains("@StateObject private var voiceAssistant: VoiceStylistService"))
        XCTAssertTrue(chatView.contains("guard message.role == .assistant else { return }"))
        XCTAssertTrue(chatView.contains("let response = message.content.trimmingCharacters(in: .whitespacesAndNewlines)"))
        XCTAssertTrue(chatView.contains("voiceAssistant.speak(response)"))
        XCTAssertFalse(chatView.contains("voiceAssistant.speak(message.weatherAttribution"))
        XCTAssertFalse(chatView.contains("voiceAssistant.speak(currentConversationContext"))
        XCTAssertTrue(chatView.contains("if speechInput.state.isActive {\n            draft = speechInput.cancelListening()"))
        XCTAssertTrue(chatView.contains("stopReadingResponse()\n                        await speechInput.startListening(existingText: draft)"))
        XCTAssertTrue(chatView.contains(".styleMatchOnChange(of: service.activeConversation.id)"))
        XCTAssertTrue(chatView.contains(".onDisappear {\n                draft = speechInput.cancelListening()\n                stopReadingResponse()"))
        XCTAssertTrue(chatView.contains("!message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty"))
        XCTAssertTrue(chatView.contains("!isStreaming"))
        XCTAssertTrue(chatView.contains(".accessibilityLabel(\"Listen to Stylist response\")"))
        XCTAssertTrue(chatView.contains(".accessibilityHint(\"Reads this response aloud.\")"))
        XCTAssertTrue(chatView.contains(".accessibilityLabel(\"Stop reading response\")"))
        XCTAssertTrue(chatView.contains(".accessibilityHint(\"Stops the current Stylist response.\")"))
        XCTAssertTrue(chatView.contains(".frame(minWidth: 44, minHeight: 44)"))
    }

    func testOutfitCombinationGeneratorStaysInsideMinimizedChatBoundary() throws {
        let context = try projectSource("StyleMatchAI/PersonalStylist/StylistContextBuilder.swift")
        let chatView = try projectSource("StyleMatchAI/StylistChat/StylistChatView.swift")
        let transport = try projectSource("StyleMatchAI/StylistChat/StylistChatTransport.swift")
        let models = try projectSource("StyleMatchAI/StylistChat/StylistChatModels.swift")
        let scoring = try projectSource("StyleMatchAI/Models.swift")
        let share = try projectSource("StyleMatchAI/ShareableScoreCard.swift")

        XCTAssertTrue(context.contains("Conversational Personal Stylist Phase 3C"))
        XCTAssertTrue(context.contains("For outfit-combination requests"))
        XCTAssertTrue(context.contains("Keep any user-provided anchor item fixed"))
        XCTAssertTrue(context.contains("From this scan"))
        XCTAssertTrue(context.contains("Suggested addition"))
        XCTAssertTrue(context.contains("Common colors include black, white, cream, gray, charcoal, navy, light blue, olive"))
        XCTAssertTrue(chatView.contains("Build three outfits around this item."))
        XCTAssertTrue(chatView.contains("Give me a casual and an elevated version."))
        XCTAssertTrue(chatView.contains("guard submitQuestion(capturedDraft) else { return }"))
        XCTAssertTrue(chatView.contains("@State private var activeConversationContext: ChatContext?"))
        XCTAssertTrue(chatView.contains("activeConversationContext = initialContext"))
        XCTAssertTrue(chatView.contains("private func currentConversationContext(including question: String? = nil) -> ChatContext"))
        XCTAssertTrue(chatView.contains("activeConversationContext ?? PersonalizationContextBuilder.conversationalStylistContext("))
        XCTAssertTrue(chatView.contains("screenContext: screenContext"))
        XCTAssertTrue(chatView.contains("_ = submitQuestion(prompt)"))
        XCTAssertTrue(chatView.contains("private func currentConversationAssembly("))
        XCTAssertTrue(chatView.contains("let assembly = currentConversationAssembly(including: question)"))
        XCTAssertTrue(chatView.contains("forcedContext: context"))
        XCTAssertTrue(chatView.contains("intelligenceSnapshot: assembly.snapshot"))
        XCTAssertFalse(chatView.contains("service.send(question, forcedContext: currentConversationContext(including: question))"))
        XCTAssertTrue(chatView.contains("activeConversationContext = nil"))
        XCTAssertTrue(chatView.contains("speechInput.clearTranscript()"))
        XCTAssertTrue(chatView.contains("Using selected scan context"))

        XCTAssertFalse(context.contains("declaredUndertone:"))
        XCTAssertFalse(context.contains("skinToneStyleNote:"))
        XCTAssertFalse(context.contains("BodyProportions"))
        XCTAssertFalse(context.contains("heightInches"))
        XCTAssertFalse(context.contains("bodyType"))
        XCTAssertFalse(context.localizedCaseInsensitiveContains("favorite brands:"))
        XCTAssertFalse(context.localizedCaseInsensitiveContains("shopping budget"))
        XCTAssertFalse(transport.contains("OutfitCombination"))
        XCTAssertFalse(models.contains("OutfitCombination"))
        XCTAssertFalse(scoring.contains("OutfitCombination"))
        XCTAssertFalse(share.contains("OutfitCombination"))
    }

    func testVoiceAssistantDefaultsOffForFreshInstallAndPreservesPersistedOn() {
        let suiteName = "VoiceAssistantSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(VoiceAssistantSettings.defaultEnabled)
        XCTAssertFalse(VoiceAssistantSettings.isEnabled(defaults: defaults))

        defaults.set(true, forKey: VoiceAssistantSettings.enabledKey)

        XCTAssertTrue(VoiceAssistantSettings.isEnabled(defaults: defaults))
    }

    func testHomeScoreBandingKeepsStarsAndLabelsConsistent() {
        XCTAssertEqual(StyleMatchHomeDisplay.scoreBand(for: 82), StyleMatchHomeScoreBand(stars: 4, title: "Good Match"))
        XCTAssertEqual(StyleMatchHomeDisplay.scoreBand(for: 39).stars, 1)
        XCTAssertEqual(StyleMatchHomeDisplay.scoreBand(for: 40).stars, 2)
        XCTAssertEqual(StyleMatchHomeDisplay.scoreBand(for: 60).stars, 3)
        XCTAssertEqual(StyleMatchHomeDisplay.scoreBand(for: 75).stars, 4)
        XCTAssertEqual(StyleMatchHomeDisplay.scoreBand(for: 89).stars, 4)
        XCTAssertEqual(StyleMatchHomeDisplay.scoreBand(for: 90).stars, 5)
    }

    func testHomeCountPluralization() {
        XCTAssertEqual(StyleMatchHomeDisplay.itemCountText(0), "0 items")
        XCTAssertEqual(StyleMatchHomeDisplay.itemCountText(1), "1 item")
        XCTAssertEqual(StyleMatchHomeDisplay.itemCountText(2), "2 items")
        XCTAssertEqual(StyleMatchHomeDisplay.closetItemLabel(0), "0 Closet Items")
        XCTAssertEqual(StyleMatchHomeDisplay.closetItemLabel(1), "1 Closet Item")
        XCTAssertEqual(StyleMatchHomeDisplay.closetItemLabel(3), "3 Closet Items")
        XCTAssertEqual(StyleMatchHomeDisplay.countText(1, singular: "saved item"), "1 saved item")
        XCTAssertEqual(StyleMatchHomeDisplay.countText(2, singular: "saved item"), "2 saved items")
        XCTAssertEqual(StyleMatchHomeDisplay.countText(2, singular: "person", plural: "people"), "2 people")
        XCTAssertEqual(StyleMatchHomeDisplay.starSystemName(index: 4, for: 82), "star.fill")
        XCTAssertEqual(StyleMatchHomeDisplay.starSystemName(index: 5, for: 82), "star")
    }

    func testHomeRecommendationRoutesOnlyEmptyClosetToExistingClosetDestination() {
        XCTAssertEqual(
            StyleMatchHomeDisplay.recommendationDestination(closetItemCount: 0),
            .closet
        )
        XCTAssertNil(StyleMatchHomeDisplay.recommendationDestination(closetItemCount: 1))
        XCTAssertNil(StyleMatchHomeDisplay.recommendationDestination(closetItemCount: 3))
    }

    func testHomeEmptyClosetHeroUsesAccessibleFullCardButtonAndOccasionStaysStatusOnly() throws {
        let source = try projectSource("StyleMatchAI/HomeView.swift")

        XCTAssertTrue(source.contains("switch StyleMatchHomeDisplay.recommendationDestination(closetItemCount: closetItemCount)"))
        XCTAssertTrue(source.contains("Button {\n                selectTab(.closet)"))
        XCTAssertTrue(source.contains("recommendedOutfitHeroContent\n                    .frame(maxWidth: .infinity, alignment: .leading)\n                    .contentShape(Rectangle())"))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"Add a closet piece\")"))
        XCTAssertTrue(source.contains(".accessibilityHint(\"Opens Virtual Closet\")"))
        XCTAssertTrue(source.contains("case nil:\n            recommendedOutfitHeroContent"))
        XCTAssertTrue(source.contains("homeStatus(icon: \"person.fill.checkmark\", text: outfitMoodText"))
    }

    func testHomeClosetItemLabelRemovesProfileName() {
        let label = StyleMatchHomeDisplay.sanitizedClosetItemLabel(
            name: "Sabastine",
            color: "White",
            userName: "Sabastine"
        )

        XCTAssertEqual(label, "White")
        XCTAssertFalse(label?.localizedCaseInsensitiveContains("Sabastine") == true)
    }

    func testClosetItemDisplayFallsBackFromProfileNameToGarmentDescription() {
        let item = ClosetItem(
            name: "Sabastine",
            category: "Shirt",
            color: "White",
            brand: "",
            size: "M",
            occasion: "Everyday",
            notes: ""
        )

        XCTAssertEqual(
            ClosetItemDisplay.displayName(for: item, profileName: "Sabastine Esisorigho"),
            "White Shirt"
        )
        XCTAssertEqual(
            ClosetItemDisplay.displayName(name: "Sabastine", category: "Shoes", color: "Black", profileName: "Sabastine Esisorigho"),
            "Black Shoes"
        )
        XCTAssertEqual(
            ClosetItemDisplay.displayName(name: "Navy Blazer", category: "Jacket", color: "Navy", profileName: "Sabastine Esisorigho"),
            "Navy Blazer"
        )
    }

    func testClosetViewUsesReadOnlyGarmentRecordsForScanCategorySections() throws {
        let source = try projectSource("StyleMatchAI/ClosetView.swift")

        XCTAssertTrue(source.contains("@StateObject private var outfitMemoryStore = OutfitMemoryStore()"))
        XCTAssertTrue(source.contains("outfitMemoryStore.garmentRecords"))
        XCTAssertTrue(source.contains("Detected from Scans"))
        XCTAssertTrue(source.contains("not yet saved to your verified Closet"))
        XCTAssertTrue(source.contains("No scan categories yet"))
        XCTAssertFalse(source.contains("outfitMemoryStore.addScan"))
        XCTAssertFalse(source.contains("outfitMemoryStore.addOrMergeScan"))
        XCTAssertFalse(source.contains("outfitMemoryStore.mergeGarmentRecords"))
    }

    func testHomeViewKeepsDuplicatedFactsInOnePlace() throws {
        let source = try projectSource("StyleMatchAI/HomeView.swift")

        XCTAssertFalse(source.contains("AI Confidence: High"))
        XCTAssertEqual(source.components(separatedBy: "Continue your last outfit").count - 1, 1)
        XCTAssertFalse(source.contains("Weather & Calendar"))
        XCTAssertFalse(source.contains("weatherIntelligenceCard"))
        XCTAssertFalse(source.contains("Favorite Color"))
        XCTAssertFalse(source.contains("Closet Items"))
        XCTAssertFalse(source.contains("closetItemCountText"))
        XCTAssertFalse(source.contains("memoryClosetCountText"))
        XCTAssertFalse(source.contains("progressClosetCountText"))
        XCTAssertFalse(source.contains("weatherIntelligenceCard"))
        XCTAssertTrue(source.contains("DAILY STYLE BRIEF"))
        XCTAssertTrue(source.contains("StyleMatchPremiumPalette"))
        XCTAssertFalse(source.contains(".stroke(task.tint"))
        XCTAssertFalse(source.contains(".stroke(tint"))
        XCTAssertFalse(source.contains("saved item\\(wishlistCount"))
        XCTAssertFalse(source.contains("light or gym item\\(count"))
        XCTAssertFalse(source.contains("Projected: 95"))
        XCTAssertFalse(source.contains("Score +6 this month"))
        XCTAssertTrue(source.contains("Latest saved result"))
        XCTAssertTrue(source.contains("StyleMatchHomeDisplay.starSystemName"))
        XCTAssertTrue(source.contains("StyleMatchHomeDisplay.countText(wishlistCount"))
    }

    func testDailyStyleRecommendationRequiresACompleteVerifiedOutfit() {
        let shirt = ClosetItem(name: "White Shirt", category: "Shirt", color: "White", brand: "", size: "L", occasion: "Casual", notes: "")
        let pants = ClosetItem(name: "Navy Chinos", category: "Pants", color: "Navy", brand: "", size: "36x36", occasion: "Casual", notes: "")
        let shoes = ClosetItem(name: "Brown Shoes", category: "Shoes", color: "Brown", brand: "", size: "10", occasion: "Casual", notes: "")

        XCTAssertNil(DailyStyleRecommendationEngine.recommend(items: [shirt, pants], temperatureFahrenheit: 72, condition: "Clear", occasion: "Casual", dressCode: "", workSetting: ""))
        let result = DailyStyleRecommendationEngine.recommend(items: [shirt, pants, shoes], temperatureFahrenheit: 72, condition: "Clear", occasion: "Casual", dressCode: "", workSetting: "")
        XCTAssertEqual(result?.itemIDs.count, 3)
        XCTAssertEqual(Set(result?.itemIDs ?? []), Set([shirt.id, pants.id, shoes.id]))
    }

    func testDailyStyleRecommendationPreservesPPEFootwearPrecedence() {
        let shirt = ClosetItem(name: "Work Polo", category: "Shirt", color: "Navy", brand: "", size: "L", occasion: "Work", notes: "")
        let pants = ClosetItem(name: "Work Pants", category: "Pants", color: "Gray", brand: "", size: "36x36", occasion: "Work", notes: "")
        let sneakers = ClosetItem(name: "Running Sneakers", category: "Shoes", color: "White", brand: "", size: "10", occasion: "Casual", notes: "")
        let safety = ClosetItem(name: "Composite Toe Work Boot", category: "Shoes", color: "Black", brand: "", size: "10", occasion: "Work", notes: "Slip-resistant safety toe")

        XCTAssertNil(DailyStyleRecommendationEngine.recommend(items: [shirt, pants, sneakers], temperatureFahrenheit: 72, condition: "Clear", occasion: "Work", dressCode: "PPE", workSetting: "Factory floor"))
        let result = DailyStyleRecommendationEngine.recommend(items: [shirt, pants, sneakers, safety], temperatureFahrenheit: 72, condition: "Clear", occasion: "Work", dressCode: "PPE", workSetting: "Factory floor")
        XCTAssertTrue(result?.itemIDs.contains(safety.id) == true)
        XCTAssertFalse(result?.itemIDs.contains(sneakers.id) == true)
    }

    func testPremiumPassKeepsDailyBriefTruthfulAndInlineStylistUnobstructed() throws {
        let homeSource = try projectSource("StyleMatchAI/HomeView.swift")
        let contentSource = try projectSource("StyleMatchAI/ContentView.swift")
        let closetSource = try projectSource("StyleMatchAI/ClosetView.swift")

        XCTAssertTrue(homeSource.contains("Text(\"LAST SCAN\")"))
        XCTAssertTrue(homeSource.contains("DailyStyleRecommendationEngine.recommend"))
        XCTAssertTrue(homeSource.contains("\"Build Look\""))
        XCTAssertTrue(homeSource.contains("\"Add Pieces\""))
        XCTAssertTrue(contentSource.contains("no floating AI control may"))
        XCTAssertTrue(contentSource.contains("Scan exposes its score-specific"))
        XCTAssertFalse(contentSource.contains("selectedTab != .profile"))
        XCTAssertTrue(closetSource.contains(".navigationBarTitleDisplayMode(.inline)"))
        XCTAssertTrue(closetSource.contains("Saved pieces are your verified wardrobe"))
    }

    func testHomeQuickActionsUseSharedTabSelectionAndFullCardHitArea() throws {
        let homeSource = try projectSource("StyleMatchAI/HomeView.swift")
        let contentSource = try projectSource("StyleMatchAI/ContentView.swift")

        XCTAssertTrue(homeSource.contains("quickAction(icon: \"camera.viewfinder\", title: \"Analyze\", tab: .scan"))
        XCTAssertTrue(homeSource.contains("quickAction(icon: \"tshirt.fill\", title: \"Closet\", tab: .closet"))
        XCTAssertTrue(homeSource.contains("quickAction(icon: \"sparkles\", title: \"Ask AI\", tab: .ai"))
        XCTAssertTrue(homeSource.contains("quickAction(icon: \"bag.fill\", title: \"Shop\", tab: .shop"))
        XCTAssertTrue(homeSource.contains("quickAction(icon: \"heart.fill\", title: \"Favorites\", tab: .scan"))
        XCTAssertTrue(homeSource.contains("title: \"History\""))
        XCTAssertTrue(homeSource.contains("action: onOpenScanHistory"))
        XCTAssertTrue(homeSource.contains("let resolvedAction = action ?? { selectTab(tab) }"))
        XCTAssertTrue(homeSource.contains(".contentShape(Rectangle())"))
        XCTAssertTrue(contentSource.contains("onSelectTab: selectTab"))
        XCTAssertTrue(contentSource.contains("private func selectTab(_ tab: AppTab)"))
        XCTAssertTrue(contentSource.contains("mountedTabs.insert(tab)"))
        XCTAssertNotNil(contentSource.range(
            of: #"ShoppingView\s*\(\s*selectedTab:\s*\$selectedTab"#,
            options: .regularExpression
        ))
    }

    func testPremiumHomeClosetEntryPointsOpenAddItemInsteadOfDeadEnding() throws {
        let homeSource = try projectSource("StyleMatchAI/HomeView.swift")
        let contentSource = try projectSource("StyleMatchAI/ContentView.swift")
        let closetSource = try projectSource("StyleMatchAI/ClosetView.swift")

        XCTAssertTrue(homeSource.contains("var onOpenClosetAddItem: () -> Void = {}"))
        XCTAssertTrue(homeSource.contains("onOpenClosetAddItem()"))
        XCTAssertTrue(contentSource.contains("onOpenClosetAddItem: openClosetAddItemFromHome"))
        XCTAssertTrue(contentSource.contains("closetAddItemRequestID &+= 1"))
        XCTAssertTrue(contentSource.contains("addItemRequestID: closetAddItemRequestID"))
        XCTAssertTrue(closetSource.contains("handleAddItemRequestIfNeeded(addItemRequestID)"))
        XCTAssertTrue(closetSource.contains("presentAddItem()"))
    }

    func testScanPremiumPassUsesInlineActionsAndTappableProgressCards() throws {
        let scanSource = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(scanSource.contains("Text(\"STYLE INTELLIGENCE SCAN\")"))
        XCTAssertTrue(scanSource.contains("Text(\"PERSONAL STYLE SCAN\")"))
        XCTAssertTrue(scanSource.contains("private var premiumScanStartCard: ScanStartCard"))
        XCTAssertTrue(scanSource.contains("onStartCamera: startCameraCapture"))
        XCTAssertTrue(scanSource.contains("Button(action: onStartCamera)"))
        XCTAssertTrue(scanSource.contains("Text(\"WHAT STYLEMATCH SCORES\")"))
        XCTAssertTrue(scanSource.contains("accessibilityHint: \"Opens your highest-scoring saved scan.\""))
        XCTAssertTrue(scanSource.contains("openSavedScan(highest, scrollProxy: scrollProxy)"))
        XCTAssertTrue(scanSource.contains("scrollProxy.scrollTo(\"recentOutfitScores\", anchor: .top)"))
    }

    func testBuild18049VisibleScanAndStyleFriendsAffordancesAreActionable() throws {
        let scanSource = try projectSource("StyleMatchAI/ScanView.swift")
        let friendsSource = try projectSource("StyleMatchAI/StyleFriendsView.swift")
        let profileSource = try projectSource("StyleMatchAI/ProfileView.swift")

        XCTAssertTrue(scanSource.contains("selectedUIImage == nil ? \"Start Scan\""))
        XCTAssertTrue(scanSource.contains("Personal Style Scan. Start scan."))
        XCTAssertTrue(scanSource.contains("startCameraCapture()"))
        XCTAssertTrue(scanSource.contains("Tap here or use Camera below."))

        XCTAssertTrue(friendsSource.contains("private func beginShareLook()"))
        XCTAssertTrue(friendsSource.contains("Label(\"Post a Look\", systemImage: \"square.and.arrow.up.fill\")"))
        XCTAssertTrue(friendsSource.contains("reviewCard = card"))
        XCTAssertTrue(friendsSource.contains("onCreateShareCard()"))
        XCTAssertTrue(profileSource.contains("onCreateShareCard:"))
        XCTAssertTrue(profileSource.contains("selectedTab = .scan"))
    }

    func testGlobalStylistOverlayUsesRootPresentationWithoutCoveringTappableContent() throws {
        let contentSource = try projectSource("StyleMatchAI/ContentView.swift")
        let chatSource = try projectSource("StyleMatchAI/StylistChat/StylistChatView.swift")
        let scanSource = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(contentSource.contains("@StateObject private var stylistOverlaySession = StylistOverlaySessionCoordinator()"))
        XCTAssertTrue(contentSource.contains("private var shouldShowGlobalStylistControl: Bool"))
        XCTAssertTrue(contentSource.contains("no floating AI control may"))
        XCTAssertTrue(contentSource.contains("Scan exposes its score-specific"))
        XCTAssertTrue(scanSource.contains("Label(\"Ask the Stylist About This Score\", systemImage: \"sparkles\")"))
        XCTAssertTrue(scanSource.contains("onOpenStylistScanConversation(handoff)"))
        XCTAssertTrue(contentSource.contains("service: stylistOverlaySession.service"))
        XCTAssertTrue(contentSource.contains("stylistOverlaySession.presentScreenAwareness(snapshot)"))
        XCTAssertTrue(contentSource.contains("stylistOverlaySession.presentScan()"))

        XCTAssertTrue(chatSource.contains("showsBackControl: Bool = false"))
        XCTAssertTrue(chatSource.contains("Label(\"Back\", systemImage: \"chevron.left\")"))
        XCTAssertTrue(chatSource.contains("onBackRequested()"))
        XCTAssertTrue(contentSource.contains("showsBackControl: true"))
        XCTAssertTrue(contentSource.contains("selectTab(.home)"))
        XCTAssertTrue(chatSource.contains("showsDismissControl: Bool = false"))
        XCTAssertTrue(chatSource.contains("if showsDismissControl"))
        XCTAssertTrue(chatSource.contains("onDismissRequested()"))
    }

    func testShoppingRuntimeKeepsRouteAndStoreOwnershipStableAcrossViewValues() throws {
        let shoppingSource = try projectSource("StyleMatchAI/Shopping/ShoppingView.swift")
        let contentSource = try projectSource("StyleMatchAI/ContentView.swift")

        XCTAssertTrue(shoppingSource.contains("private final class ShoppingViewRuntime: ObservableObject"))
        XCTAssertTrue(shoppingSource.contains("@StateObject private var runtime = ShoppingViewRuntime()"))
        XCTAssertTrue(shoppingSource.contains("private var diagnosticContext: ShoppingDiagnosticContext { runtime.diagnosticContext }"))
        XCTAssertTrue(shoppingSource.contains("private var store: ShoppingLocalStore { runtime.store }"))
        XCTAssertFalse(shoppingSource.contains("let diagnosticContext = ShoppingDiagnosticContext()\n        self._selectedTab"))
        XCTAssertFalse(shoppingSource.contains("self._store = StateObject("))
        XCTAssertTrue(shoppingSource.contains("guard !isCatalogLoadInFlight else"))
        XCTAssertTrue(contentSource.contains("guard availableShoppingProductIDs != productIDs else { return }"))
    }

    func testBuildInformationUsesOnlyTheExplicitHomeGearAction() throws {
        let appSource = try projectSource("StyleMatchAI/StyleMatchAIApp.swift")
        let contentSource = try projectSource("StyleMatchAI/ContentView.swift")
        let homeSource = try projectSource("StyleMatchAI/HomeView.swift")

        XCTAssertFalse(appSource.contains("TapGesture(count: 5)"))
        XCTAssertFalse(appSource.contains(".simultaneousGesture("))
        XCTAssertTrue(appSource.contains("ContentView(\n                    onShowBuildInformation:"))
        XCTAssertTrue(appSource.contains(".sheet(isPresented: $isShowingBuildInformation)"))
        XCTAssertTrue(contentSource.contains("var onShowBuildInformation: (() -> Void)? = nil"))
        XCTAssertTrue(contentSource.contains("onOpenBuildInformation: onShowBuildInformation"))
        XCTAssertTrue(homeSource.contains("var onOpenBuildInformation: (() -> Void)?"))
        XCTAssertTrue(homeSource.contains("if let onOpenBuildInformation"))
        XCTAssertTrue(homeSource.contains(".frame(width: 44, height: 44)"))
        XCTAssertTrue(appSource.contains("#if DEBUG"))
        XCTAssertTrue(appSource.contains("STYLEMATCH_SOURCE_CHECKPOINT"))
        XCTAssertTrue(appSource.contains("STYLEMATCH_BACKEND_LANE"))
        XCTAssertTrue(appSource.contains("Owner Build Diagnostics"))
        XCTAssertFalse(appSource.contains("API base URL"))
        XCTAssertFalse(appSource.contains("Share domain"))
        XCTAssertTrue(homeSource.contains(".accessibilityLabel(\"Open owner build diagnostics\")"))

        let plist = try projectSource("StyleMatchAI/Info.plist")
        XCTAssertTrue(plist.contains("STYLEMATCH_SOURCE_CHECKPOINT"))
        XCTAssertTrue(plist.contains("STYLEMATCH_BACKEND_LANE"))
    }

    func testHomeHistoryUsesOneShotRecentScoresRoutingWithoutOpeningOrPersistingAScan() throws {
        let homeSource = try projectSource("StyleMatchAI/HomeView.swift")
        let contentSource = try projectSource("StyleMatchAI/ContentView.swift")
        let scanSource = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(homeSource.contains("var onOpenScanHistory: () -> Void = {}"))
        XCTAssertTrue(homeSource.contains("accessibilityHint: \"Opens recent outfit scores and saved scan history.\""))
        XCTAssertTrue(contentSource.contains("@State private var scanHistoryScrollRequestID = 0"))
        XCTAssertTrue(contentSource.contains("onOpenScanHistory: openRecentScoresFromHomeHistory"))
        XCTAssertTrue(contentSource.contains("private func openRecentScoresFromHomeHistory()"))
        XCTAssertTrue(contentSource.contains("selectTab(.scan)"))
        XCTAssertTrue(contentSource.contains("scanHistoryScrollRequestID &+= 1"))
        XCTAssertTrue(contentSource.contains("recentScoresScrollRequestID: scanHistoryScrollRequestID"))

        XCTAssertTrue(scanSource.contains("let recentScoresScrollRequestID: Int"))
        XCTAssertTrue(scanSource.contains("@State private var lastConsumedRecentScoresScrollRequestID = 0"))
        XCTAssertTrue(scanSource.contains("recentScoresScrollRequestID != lastConsumedRecentScoresScrollRequestID"))
        XCTAssertTrue(scanSource.contains("lastConsumedRecentScoresScrollRequestID = recentScoresScrollRequestID"))
        XCTAssertTrue(scanSource.contains("proxy.scrollTo(\"recentOutfitScores\", anchor: .top)"))

        let routingStart = try XCTUnwrap(scanSource.range(of: "private func consumeRecentScoresScrollRequestIfNeeded"))
        let routingEnd = try XCTUnwrap(scanSource.range(of: "private var hero", range: routingStart.upperBound..<scanSource.endIndex))
        let routingSource = String(scanSource[routingStart.lowerBound..<routingEnd.lowerBound])
        XCTAssertFalse(routingSource.contains("openSavedScan("))
        XCTAssertFalse(routingSource.contains("outfitScanHistoryData ="))
        XCTAssertFalse(routingSource.contains("result ="))
    }

    func testHomeEngagementCardsNavigateWithoutDuplicateTabs() throws {
        let homeSource = try projectSource("StyleMatchAI/HomeView.swift")
        let contentSource = try projectSource("StyleMatchAI/ContentView.swift")

        XCTAssertTrue(homeSource.contains("HomeEngagementDestination"))
        XCTAssertTrue(homeSource.contains("NavigationStack(path: $homeEngagementPath)"))
        XCTAssertTrue(homeSource.contains(".navigationDestination(for: HomeEngagementDestination.self)"))
        XCTAssertTrue(homeSource.contains("showHomeEngagement(.todayRecommendation)"))
        XCTAssertTrue(homeSource.contains("showHomeEngagement(.intelligence(focus))"))
        XCTAssertTrue(homeSource.contains("showHomeEngagement(.aiStylistLearning)"))
        XCTAssertTrue(homeSource.contains("showHomeEngagement(.styleProgress)"))
        XCTAssertTrue(homeSource.contains("selectedTab = .shop"))
        XCTAssertTrue(homeSource.contains("selectedTab = .scan"))
        XCTAssertTrue(homeSource.contains(".styleMatchOnChange(of: navigationResetID)"))
        XCTAssertTrue(homeSource.contains("homeEngagementPath.removeAll()"))
        XCTAssertTrue(contentSource.contains("@State private var homeNavigationResetID = 0"))
        XCTAssertTrue(contentSource.contains("navigationResetID: homeNavigationResetID"))
        XCTAssertTrue(contentSource.contains("if tab == .home"))
        XCTAssertTrue(contentSource.contains("homeNavigationResetID &+= 1"))
        XCTAssertFalse(homeSource.contains("ShoppingView(selectedTab:"))
        XCTAssertFalse(homeSource.contains("ScanView(selectedTab:"))
    }

    func testAccessibilityScanSummaryPreservesLogicalResultOrder() {
        let summary = StyleMatchAccessibilityText.scanResultSummary(
            score: 84,
            rating: "Strong",
            categoryScores: ["Color Harmony 22 out of 25", "Fit Quality 20 out of 25"],
            detectedItems: ["navy blazer", "white shirt"],
            recommendations: ["Try a lighter shoe."]
        )

        XCTAssertEqual(
            summary,
            "Overall KigoStylist score, 84 out of 100, Strong. Category scores: Color Harmony 22 out of 25, Fit Quality 20 out of 25. Detected items: navy blazer, white shirt. Recommendations: Try a lighter shoe."
        )
    }

    func testAccessibilityShoppingSummaryIncludesStateAndAction() {
        let summary = StyleMatchAccessibilityText.shoppingProductSummary(
            name: "Classic Oxford",
            retailer: "Macy's",
            price: "$59.99",
            saleStatus: "20 percent off",
            isFavorite: true,
            isWishlist: false,
            action: "View Product"
        )

        XCTAssertTrue(summary.contains("Classic Oxford"))
        XCTAssertTrue(summary.contains("Retailer: Macy's"))
        XCTAssertTrue(summary.contains("Price: $59.99"))
        XCTAssertTrue(summary.contains("Sale status: 20 percent off"))
        XCTAssertTrue(summary.contains("Favorite"))
        XCTAssertTrue(summary.contains("Not in wishlist"))
        XCTAssertTrue(summary.contains("Action: View Product"))
    }

    func testAccessibilityProfileAndChatTextExposeMeaningfulValues() {
        XCTAssertEqual(
            StyleMatchAccessibilityText.profileFieldLabel(title: "Favorite colors", isRequired: false),
            "Favorite colors, optional"
        )
        XCTAssertEqual(
            StyleMatchAccessibilityText.profileFieldValue(text: "  navy and white  "),
            "navy and white"
        )
        XCTAssertEqual(
            StyleMatchAccessibilityText.chatMessageLabel(role: "Stylist", content: "  Try loafers.  "),
            "Stylist: Try loafers."
        )
    }

    func testReleaseTabHierarchyDoesNotDisableVoiceControls() throws {
        let contentSource = try projectSource("StyleMatchAI/ContentView.swift")
        let profileSource = try projectSource("StyleMatchAI/ProfileView.swift")
        let stylistSource = try projectSource("StyleMatchAI/StylistChat/StylistChatView.swift")

        XCTAssertFalse(contentSource.contains("voiceControlsEnabled: false"))
        XCTAssertFalse(contentSource.contains("voiceInputEnabled: false"))
        XCTAssertTrue(profileSource.contains("private var effectiveVoiceControlsEnabled"))
        XCTAssertTrue(stylistSource.contains("private var effectiveVoiceInputEnabled"))
        XCTAssertTrue(profileSource.contains("#if DEBUG"))
        XCTAssertTrue(stylistSource.contains("#if DEBUG"))
    }

    // MARK: - BUILD18015 local date and Calendar Awareness foundation

    func testLocalDateContextWorksWithoutCalendarPermission() {
        let context = LocalDateContext(
            date: Date(timeIntervalSince1970: 1_704_094_800),
            calendar: utcCalendar,
            locale: Locale(identifier: "en_US"),
            timeZone: utcTimeZone
        )

        XCTAssertEqual(context.timeBucket, .morning)
        XCTAssertEqual(context.localizedWeekdayName, "Monday")
        XCTAssertEqual(context.timeZoneIdentifier, "GMT")
    }

    func testLocalDateContextReportsInjectedWeekdayAndWeekend() {
        let monday = LocalDateContext(date: Date(timeIntervalSince1970: 1_704_094_800), calendar: utcCalendar, locale: Locale(identifier: "en_US"), timeZone: utcTimeZone)
        let saturday = LocalDateContext(date: Date(timeIntervalSince1970: 1_704_499_200), calendar: utcCalendar, locale: Locale(identifier: "en_US"), timeZone: utcTimeZone)

        XCTAssertEqual(monday.weekday, 2)
        XCTAssertFalse(monday.isWeekend)
        XCTAssertEqual(saturday.weekday, 7)
        XCTAssertTrue(saturday.isWeekend)
    }

    func testLocalDateContextUsesStableTimeBucketBoundaries() {
        XCTAssertEqual(LocalDateContext.bucket(hour: 4), .night)
        XCTAssertEqual(LocalDateContext.bucket(hour: 5), .morning)
        XCTAssertEqual(LocalDateContext.bucket(hour: 11), .morning)
        XCTAssertEqual(LocalDateContext.bucket(hour: 12), .afternoon)
        XCTAssertEqual(LocalDateContext.bucket(hour: 16), .afternoon)
        XCTAssertEqual(LocalDateContext.bucket(hour: 17), .evening)
        XCTAssertEqual(LocalDateContext.bucket(hour: 21), .evening)
        XCTAssertEqual(LocalDateContext.bucket(hour: 22), .night)
    }

    func testLocalDateContextLocalizesWeekdayAndSeparatesTimeZones() {
        let date = Date(timeIntervalSince1970: 1_704_094_800)
        let madrid = LocalDateContext(date: date, calendar: utcCalendar, locale: Locale(identifier: "es_ES"), timeZone: TimeZone(identifier: "Europe/Madrid")!)
        let losAngeles = LocalDateContext(date: date, calendar: utcCalendar, locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "America/Los_Angeles")!)

        XCTAssertEqual(madrid.localizedWeekdayName.lowercased(), "lunes")
        XCTAssertEqual(madrid.dateComponents.hour, 8)
        XCTAssertEqual(losAngeles.dateComponents.hour, 23)
        XCTAssertNotEqual(madrid.utcOffsetSeconds, losAngeles.utcOffsetSeconds)
    }

    func testLocalDateContextHandlesDSTWithoutGlobalDateState() {
        let newYork = TimeZone(identifier: "America/New_York")!
        let before = LocalDateContext(date: Date(timeIntervalSince1970: 1_710_053_940), calendar: utcCalendar, locale: Locale(identifier: "en_US"), timeZone: newYork)
        let after = LocalDateContext(date: Date(timeIntervalSince1970: 1_710_054_060), calendar: utcCalendar, locale: Locale(identifier: "en_US"), timeZone: newYork)

        XCTAssertEqual(before.dateComponents.hour, 1)
        XCTAssertEqual(after.dateComponents.hour, 3)
        XCTAssertNotEqual(before.utcOffsetSeconds, after.utcOffsetSeconds)
    }

    func testCalendarAwarenessDefaultsOffAndLegacyDataIsSafe() {
        let (defaults, userID, suiteName) = makeCalendarAwarenessDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(CalendarAwarenessPreferenceStore.state(for: userID, defaults: defaults), .off)
        defaults.set("unknown-future-state", forKey: PersonalStylistStorage.scopedKey(CalendarAwarenessPreferenceStore.baseKey, userID: userID))
        XCTAssertEqual(CalendarAwarenessPreferenceStore.state(for: userID, defaults: defaults), .off)
    }

    func testCalendarAwarenessEnableStoresOnlyPermissionRequiredState() {
        let (defaults, userID, suiteName) = makeCalendarAwarenessDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        CalendarAwarenessPreferenceStore.setFoundationEnabled(true, for: userID, defaults: defaults)

        XCTAssertEqual(CalendarAwarenessPreferenceStore.state(for: userID, defaults: defaults), .permissionRequired)
        XCTAssertEqual(
            defaults.string(forKey: PersonalStylistStorage.scopedKey(CalendarAwarenessPreferenceStore.baseKey, userID: userID)),
            CalendarAwarenessState.permissionRequired.rawValue
        )
        XCTAssertEqual(
            CalendarAwarenessPreferenceStore.supportingText(for: .permissionRequired),
            "Enable Calendar Context to let KigoStylist request read access only when you choose."
        )
    }

    func testCalendarAwarenessStorageIsScopedAndClearedWithPersonalization() {
        let (defaults, userA, suiteName) = makeCalendarAwarenessDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let userB = "calendar-user-b-\(UUID().uuidString)"
        CalendarAwarenessPreferenceStore.setFoundationEnabled(true, for: userA, defaults: defaults)
        CalendarAwarenessPreferenceStore.setFoundationEnabled(false, for: userB, defaults: defaults)

        XCTAssertEqual(CalendarAwarenessPreferenceStore.state(for: userA, defaults: defaults), .permissionRequired)
        XCTAssertEqual(CalendarAwarenessPreferenceStore.state(for: userB, defaults: defaults), .off)

        PersonalStylistStorage.deletePersonalization(for: userA, defaults: defaults)
        XCTAssertEqual(CalendarAwarenessPreferenceStore.state(for: userA, defaults: defaults), .off)
        XCTAssertEqual(CalendarAwarenessPreferenceStore.state(for: userB, defaults: defaults), .off)
    }

    func testCalendarContextUsesAContainedEventKitBoundaryAndPrivacyDescription() throws {
        let localDateSource = try projectSource("StyleMatchAI/PersonalStylist/LocalDateContext.swift")
        let contextSource = try projectSource("StyleMatchAI/PersonalStylist/StylistContextBuilder.swift")
        let calendarSource = try projectSource("StyleMatchAI/PersonalStylist/CalendarContextService.swift")
        let infoPlistSource = try projectSource("StyleMatchAI/Info.plist")
        XCTAssertFalse(localDateSource.contains("import EventKit"))
        XCTAssertFalse(contextSource.contains("EventKit"))
        XCTAssertTrue(calendarSource.contains("import EventKit"))
        XCTAssertTrue(calendarSource.contains("requestFullAccessToEvents"))
        XCTAssertTrue(infoPlistSource.contains("NSCalendarsUsageDescription"))
        XCTAssertTrue(infoPlistSource.contains("NSCalendarsFullAccessUsageDescription"))
        XCTAssertTrue(infoPlistSource.contains("KigoStylist uses selected upcoming calendar context on this device to improve outfit recommendations when you enable Calendar Context."))
        XCTAssertFalse(calendarSource.contains("saveEvent"))
        XCTAssertFalse(calendarSource.contains("removeEvent"))
        XCTAssertFalse(calendarSource.contains("respond(to"))
        XCTAssertFalse(contextSource.contains("CalendarAwareness"))
    }

    func testCalendarAwarenessUnavailableStatesRemainTruthfulAndDoNotFabricateEvents() {
        for state in [CalendarAwarenessState.denied, .restricted, .unavailable, .noRelevantEvents] {
            let text = CalendarAwarenessPreferenceStore.supportingText(for: state)
            XCTAssertTrue(text.localizedCaseInsensitiveContains("unavailable"))
            XCTAssertFalse(text.localizedCaseInsensitiveContains("meeting"))
            XCTAssertFalse(text.localizedCaseInsensitiveContains("appointment"))
        }
    }

    func testCalendarAwarenessProfileRowSupportsAccessibilityAndReadingOrder() throws {
        let profileSource = try projectSource("StyleMatchAI/ProfileView.swift")
        let calendarIndex = try XCTUnwrap(profileSource.range(of: "calendarContextSettings")?.lowerBound)
        let notificationsIndex = try XCTUnwrap(profileSource.range(of: "profileInfoRow(\"Notifications\"")?.lowerBound)

        XCTAssertLessThan(calendarIndex, notificationsIndex)
        XCTAssertTrue(profileSource.contains("Enable Calendar Context"))
        XCTAssertTrue(profileSource.contains("Disconnect Calendar Context"))
        XCTAssertTrue(profileSource.contains("showCalendarConsentExplanation"))
    }

    func testExistingGreetingBehaviorUsesLocalDateContext() throws {
        let profileGreeting = StyleMatchGreetingBuilder.greetingLine(
            date: Date(timeIntervalSince1970: 1_704_094_800),
            calendar: utcCalendar,
            storedName: nil
        )
        let homeSource = try projectSource("StyleMatchAI/HomeView.swift")
        let contentSource = try projectSource("StyleMatchAI/ContentView.swift")

        XCTAssertEqual(profileGreeting, "Good Morning")
        XCTAssertTrue(homeSource.contains("LocalDateContext().timeBucket.greetingTitle"))
        XCTAssertTrue(contentSource.contains("LocalDateContext().timeBucket.greetingLowercase"))
    }

    private var utcTimeZone: TimeZone {
        TimeZone(secondsFromGMT: 0)!
    }

    // MARK: - Verified saved-scan recovery importer

    private struct RecoveryImportFixtureRecord: Codable, Equatable {
        let score: Int
        let firstScannedAt: Date
        let scanCount: Int
        let analysis: [String: String]
        let thumbnailData: Data?
    }

    func testVerifiedScanRecoveryImportsExactlySevenAppleScopedRecordsThroughUserDefaults() throws {
        let (defaults, appleUserID, suiteName) = makeRecoveryDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let records = makeVerifiedRecoveryRecords()
        let recoveryData = try JSONEncoder().encode(records)
        let sourceURL = try makeRecoveryPreferencesFile(containing: recoveryData)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        configureAppleIdentity(defaults: defaults, appleUserID: appleUserID)
        let importer = VerifiedScanHistoryRecoveryImporter(
            defaults: defaults,
            sourceURL: sourceURL,
            approvedCanonicalHistoryHash: try canonicalRecoveryDigest(recoveryData),
            expectedRecordCount: 7
        )

        XCTAssertEqual(importer.run(), .imported)
        XCTAssertEqual(
            try canonicalRecoveryDigest(try XCTUnwrap(defaults.data(forKey: VerifiedScanHistoryRecoveryImporter.historyKey))),
            try canonicalRecoveryDigest(recoveryData),
            "Recovery approval is semantic; raw JSON byte layout is evidence, not the equality gate."
        )
        XCTAssertTrue(defaults.bool(forKey: VerifiedScanHistoryRecoveryImporter.completionKey))
        XCTAssertEqual(try decodedRecoveryRecordIDs(defaults.data(forKey: VerifiedScanHistoryRecoveryImporter.historyKey)), Set(records.keys))
        XCTAssertNil(defaults.object(forKey: AccountScopedStorage.snapshotKey(
            VerifiedScanHistoryRecoveryImporter.historyKey,
            userID: "guest",
            environment: .production
        )))
    }

    func testVerifiedScanRecoveryFailsClosedForIdentityAndExistingHistory() throws {
        let (defaults, appleUserID, suiteName) = makeRecoveryDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let records = makeVerifiedRecoveryRecords()
        let recoveryData = try JSONEncoder().encode(records)
        let sourceURL = try makeRecoveryPreferencesFile(containing: recoveryData)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let importer = VerifiedScanHistoryRecoveryImporter(
            defaults: defaults,
            sourceURL: sourceURL,
            approvedCanonicalHistoryHash: try canonicalRecoveryDigest(recoveryData),
            expectedRecordCount: 7
        )
        XCTAssertEqual(importer.run(), .ineligible, "Guest scope must never import Apple recovery data.")
        XCTAssertNil(defaults.object(forKey: VerifiedScanHistoryRecoveryImporter.historyKey))

        defaults.set("Sign in with Apple", forKey: "customerAccountMode")
        XCTAssertEqual(importer.run(), .ineligible, "An Apple user ID is mandatory.")
        XCTAssertNil(defaults.object(forKey: VerifiedScanHistoryRecoveryImporter.historyKey))

        configureAppleIdentity(defaults: defaults, appleUserID: appleUserID)
        defaults.set(Data("existing".utf8), forKey: VerifiedScanHistoryRecoveryImporter.historyKey)
        XCTAssertEqual(importer.run(), .invalidActiveHistory, "Malformed active history must block recovery without replacing it.")
        XCTAssertEqual(defaults.data(forKey: VerifiedScanHistoryRecoveryImporter.historyKey), Data("existing".utf8))
    }

    func testVerifiedScanRecoveryFailsClosedForScopedHistoryAndInvalidPayloads() throws {
        let (defaults, appleUserID, suiteName) = makeRecoveryDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let records = makeVerifiedRecoveryRecords()
        let recoveryData = try JSONEncoder().encode(records)
        let sourceURL = try makeRecoveryPreferencesFile(containing: recoveryData)
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        configureAppleIdentity(defaults: defaults, appleUserID: appleUserID)

        let scopedKey = AccountScopedStorage.snapshotKey(
            VerifiedScanHistoryRecoveryImporter.historyKey,
            userID: AccountScopedStorage.sessionUserID(defaults: defaults),
            environment: .production
        )
        defaults.set(Data("scoped".utf8), forKey: scopedKey)
        XCTAssertEqual(
            VerifiedScanHistoryRecoveryImporter(defaults: defaults, sourceURL: sourceURL, approvedCanonicalHistoryHash: try canonicalRecoveryDigest(recoveryData)).run(),
            .ineligible
        )
        defaults.removeObject(forKey: scopedKey)

        XCTAssertEqual(
            VerifiedScanHistoryRecoveryImporter(defaults: defaults, sourceURL: sourceURL, approvedCanonicalHistoryHash: "mismatch").run(),
            .invalidPayload
        )
        XCTAssertNil(defaults.object(forKey: VerifiedScanHistoryRecoveryImporter.historyKey))

        let malformedURL = try makeRecoveryPreferencesFile(containing: Data("not-json".utf8))
        defer { try? FileManager.default.removeItem(at: malformedURL) }
        XCTAssertEqual(
            VerifiedScanHistoryRecoveryImporter(defaults: defaults, sourceURL: malformedURL, approvedCanonicalHistoryHash: "mismatch").run(),
            .invalidPayload
        )

        let shortData = try JSONEncoder().encode(Dictionary(uniqueKeysWithValues: Array(records.prefix(6))))
        let shortURL = try makeRecoveryPreferencesFile(containing: shortData)
        defer { try? FileManager.default.removeItem(at: shortURL) }
        XCTAssertEqual(
            VerifiedScanHistoryRecoveryImporter(defaults: defaults, sourceURL: shortURL, approvedCanonicalHistoryHash: try canonicalRecoveryDigest(shortData)).run(),
            .invalidPayload
        )
        XCTAssertNil(defaults.object(forKey: VerifiedScanHistoryRecoveryImporter.historyKey))
    }

    func testVerifiedScanRecoveryCompletionPreventsSecondWriteAndPreservesRecordFields() throws {
        let (defaults, appleUserID, suiteName) = makeRecoveryDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let records = makeVerifiedRecoveryRecords()
        let recoveryData = try JSONEncoder().encode(records)
        let sourceURL = try makeRecoveryPreferencesFile(containing: recoveryData)
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        configureAppleIdentity(defaults: defaults, appleUserID: appleUserID)

        let importer = VerifiedScanHistoryRecoveryImporter(
            defaults: defaults,
            sourceURL: sourceURL,
            approvedCanonicalHistoryHash: try canonicalRecoveryDigest(recoveryData)
        )
        XCTAssertEqual(importer.run(), .imported)
        XCTAssertEqual(importer.run(), .alreadyCompleted)

        let decoded = try XCTUnwrap(defaults.data(forKey: VerifiedScanHistoryRecoveryImporter.historyKey))
        XCTAssertEqual(try canonicalRecoveryDigest(decoded), try canonicalRecoveryDigest(recoveryData))
        XCTAssertEqual(try decodedRecoveryRecordIDs(decoded), Set(records.keys), "Dictionary keys are the stable record IDs and must remain unique.")
    }

    func testVerifiedScanRecoveryMergesIndependentCurrentRecordWithoutChangingEitherAuthority() throws {
        let (defaults, appleUserID, suiteName) = makeRecoveryDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        configureAppleIdentity(defaults: defaults, appleUserID: appleUserID)

        let recovered = makeVerifiedRecoveryRecords()
        let recoveryData = try JSONEncoder().encode(recovered)
        let packageURL = try makeRecoveryPreferencesFile(containing: recoveryData)
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let ownerRecord = RecoveryImportFixtureRecord(
            score: 80,
            firstScannedAt: Date(timeIntervalSinceReferenceDate: 900_000),
            scanCount: 1,
            analysis: ["summary": "Owner-created scan"],
            thumbnailData: Data("owner-thumbnail".utf8)
        )
        let ownerID = "owner-created-scan"
        let secondOwnerRecord = RecoveryImportFixtureRecord(
            score: 74,
            firstScannedAt: Date(timeIntervalSinceReferenceDate: 899_000),
            scanCount: 2,
            analysis: ["summary": "Second owner-created scan"],
            thumbnailData: nil
        )
        let secondOwnerID = "owner-created-scan-two"
        defaults.set(
            try JSONEncoder().encode([
                ownerID: ownerRecord,
                secondOwnerID: secondOwnerRecord
            ]),
            forKey: VerifiedScanHistoryRecoveryImporter.historyKey
        )

        let importer = VerifiedScanHistoryRecoveryImporter(
            defaults: defaults,
            sourceURL: packageURL,
            approvedRawPayloadHash: sha256(recoveryData),
            approvedCanonicalHistoryHash: try canonicalRecoveryDigest(recoveryData)
        )
        XCTAssertEqual(importer.run(), .imported)

        let readback = try XCTUnwrap(defaults.data(forKey: VerifiedScanHistoryRecoveryImporter.historyKey))
        let decoded = try JSONDecoder().decode([String: RecoveryImportFixtureRecord].self, from: readback)
        XCTAssertEqual(decoded.count, 9)
        XCTAssertEqual(decoded[ownerID], ownerRecord, "The owner-created record must remain field-identical.")
        XCTAssertEqual(decoded[secondOwnerID], secondOwnerRecord, "The second owner-created record must remain field-identical.")
        for (stableID, record) in recovered {
            XCTAssertEqual(decoded[stableID], record, "Recovery record \(stableID) must remain field-identical.")
        }
        XCTAssertEqual(Set(decoded.keys).count, 9)
        XCTAssertEqual(
            defaults.string(forKey: VerifiedScanHistoryRecoveryImporter.mergedHistoryDigestKey),
            try canonicalRecoveryDigest(readback)
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: packageURL.path), "The immutable recovery package remains available inside the signed app.")
    }

    func testVerifiedScanRecoveryTreatsEquivalentStableIDAsAlreadyPresentWithoutMutation() throws {
        let (defaults, appleUserID, suiteName) = makeRecoveryDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        configureAppleIdentity(defaults: defaults, appleUserID: appleUserID)

        let recovered = makeVerifiedRecoveryRecords()
        let recoveryData = try JSONEncoder().encode(recovered)
        let packageURL = try makeRecoveryPreferencesFile(containing: recoveryData)
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let overlappingID = "verified-scan-0"
        let current = try XCTUnwrap(recovered[overlappingID])
        defaults.set(try JSONEncoder().encode([overlappingID: current]), forKey: VerifiedScanHistoryRecoveryImporter.historyKey)

        XCTAssertEqual(
            VerifiedScanHistoryRecoveryImporter(
                defaults: defaults,
                sourceURL: packageURL,
                approvedRawPayloadHash: sha256(recoveryData),
                approvedCanonicalHistoryHash: try canonicalRecoveryDigest(recoveryData)
            ).run(),
            .imported
        )
        let decoded = try JSONDecoder().decode(
            [String: RecoveryImportFixtureRecord].self,
            from: try XCTUnwrap(defaults.data(forKey: VerifiedScanHistoryRecoveryImporter.historyKey))
        )
        XCTAssertEqual(decoded.count, 7)
        XCTAssertEqual(decoded[overlappingID], current)
    }

    func testVerifiedScanRecoveryRejectsConflictingStableIDWithoutWritingOrCompleting() throws {
        let (defaults, appleUserID, suiteName) = makeRecoveryDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        configureAppleIdentity(defaults: defaults, appleUserID: appleUserID)

        let recovered = makeVerifiedRecoveryRecords()
        let recoveryData = try JSONEncoder().encode(recovered)
        let packageURL = try makeRecoveryPreferencesFile(containing: recoveryData)
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let stableID = "verified-scan-0"
        let conflicting = RecoveryImportFixtureRecord(
            score: 80,
            firstScannedAt: Date(timeIntervalSinceReferenceDate: 950_000),
            scanCount: 1,
            analysis: ["summary": "Different record with the same stable ID"],
            thumbnailData: nil
        )
        let original = try JSONEncoder().encode([stableID: conflicting])
        defaults.set(original, forKey: VerifiedScanHistoryRecoveryImporter.historyKey)

        XCTAssertEqual(
            VerifiedScanHistoryRecoveryImporter(
                defaults: defaults,
                sourceURL: packageURL,
                approvedRawPayloadHash: sha256(recoveryData),
                approvedCanonicalHistoryHash: try canonicalRecoveryDigest(recoveryData)
            ).run(),
            .stableIDConflict
        )
        XCTAssertEqual(defaults.data(forKey: VerifiedScanHistoryRecoveryImporter.historyKey), original)
        XCTAssertFalse(defaults.bool(forKey: VerifiedScanHistoryRecoveryImporter.completionKey))
    }

    func testVerifiedScanRecoveryRejectsBadRawPackageAndRetainsItForDiagnosis() throws {
        let (defaults, appleUserID, suiteName) = makeRecoveryDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        configureAppleIdentity(defaults: defaults, appleUserID: appleUserID)

        let recoveryData = try JSONEncoder().encode(makeVerifiedRecoveryRecords())
        let packageURL = try makeRecoveryPreferencesFile(containing: recoveryData)
        defer { try? FileManager.default.removeItem(at: packageURL) }
        XCTAssertEqual(
            VerifiedScanHistoryRecoveryImporter(
                defaults: defaults,
                sourceURL: packageURL,
                approvedRawPayloadHash: "wrong-raw-hash",
                approvedCanonicalHistoryHash: try canonicalRecoveryDigest(recoveryData)
            ).run(),
            .invalidPayload
        )
        XCTAssertNil(defaults.data(forKey: VerifiedScanHistoryRecoveryImporter.historyKey))
        XCTAssertFalse(defaults.bool(forKey: VerifiedScanHistoryRecoveryImporter.completionKey))
        XCTAssertTrue(FileManager.default.fileExists(atPath: packageURL.path))
    }

    func testVerifiedScanRecoveryMissingPackageDoesNotWriteCurrentHistory() throws {
        let (defaults, appleUserID, suiteName) = makeRecoveryDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        configureAppleIdentity(defaults: defaults, appleUserID: appleUserID)

        let current = try JSONEncoder().encode(["owner-record": RecoveryImportFixtureRecord(
            score: 80,
            firstScannedAt: Date(timeIntervalSinceReferenceDate: 900_000),
            scanCount: 1,
            analysis: ["summary": "Owner record"],
            thumbnailData: nil
        )])
        defaults.set(current, forKey: VerifiedScanHistoryRecoveryImporter.historyKey)

        XCTAssertEqual(
            VerifiedScanHistoryRecoveryImporter(defaults: defaults, sourceURL: nil).run(),
            .sourceUnavailable
        )
        XCTAssertEqual(defaults.data(forKey: VerifiedScanHistoryRecoveryImporter.historyKey), current)
        XCTAssertFalse(defaults.bool(forKey: VerifiedScanHistoryRecoveryImporter.completionKey))
    }

    func testProductionLaunchNeverImportsBundledPrivateScanHistory() throws {
        let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        for relative in ["Package.swift", "StyleMatchAI.xcodeproj/project.pbxproj"] {
            let source = try String(contentsOf: projectRoot.appendingPathComponent(relative))
            XCTAssertFalse(source.contains("verified-seven-scans.json"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: projectRoot.appendingPathComponent("StyleMatchAI/verified-seven-scans.json").path))
        let startup = try String(contentsOf: projectRoot.appendingPathComponent("StyleMatchAI/StyleMatchAIApp.swift"))
        XCTAssertFalse(startup.contains("VerifiedScanHistoryRecoveryImporter(defaults: defaults).run()"))
        let identity = try XCTUnwrap(startup.range(of: "AccountAccessRestoration.restore("))
        let storage = try XCTUnwrap(startup.range(of: "composition.retainedData.prepareForLaunch()"))
        XCTAssertLessThan(identity.lowerBound, storage.lowerBound)
    }

    func testVerifiedScanRecoveryCompletionPreventsRerunAndLeavesImmutablePackageUntouched() throws {
        let (defaults, appleUserID, suiteName) = makeRecoveryDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        configureAppleIdentity(defaults: defaults, appleUserID: appleUserID)

        let recoveryData = try JSONEncoder().encode(makeVerifiedRecoveryRecords())
        let packageURL = try makeRecoveryPreferencesFile(containing: recoveryData)
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let importer = VerifiedScanHistoryRecoveryImporter(
            defaults: defaults,
            sourceURL: packageURL,
            approvedRawPayloadHash: sha256(recoveryData),
            approvedCanonicalHistoryHash: try canonicalRecoveryDigest(recoveryData)
        )
        XCTAssertEqual(importer.run(), .imported)
        XCTAssertTrue(defaults.bool(forKey: VerifiedScanHistoryRecoveryImporter.completionKey))
        XCTAssertTrue(FileManager.default.fileExists(atPath: packageURL.path))
        XCTAssertEqual(importer.run(), .alreadyCompleted)
    }

    func testVerifiedScanRecoveryRestoresOriginalHistoryWhenReadbackFails() throws {
        let (defaults, appleUserID, suiteName) = makeRecoveryDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        configureAppleIdentity(defaults: defaults, appleUserID: appleUserID)

        let recoveryData = try JSONEncoder().encode(makeVerifiedRecoveryRecords())
        let packageURL = try makeRecoveryPreferencesFile(containing: recoveryData)
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let owner = RecoveryImportFixtureRecord(
            score: 80,
            firstScannedAt: Date(timeIntervalSinceReferenceDate: 900_000),
            scanCount: 1,
            analysis: ["summary": "Owner record"],
            thumbnailData: nil
        )
        let original = try JSONEncoder().encode(["owner-record": owner])
        var simulatedStore: Data? = original
        var readCount = 0
        let importer = VerifiedScanHistoryRecoveryImporter(
            defaults: defaults,
            sourceURL: packageURL,
            approvedRawPayloadHash: sha256(recoveryData),
            approvedCanonicalHistoryHash: try canonicalRecoveryDigest(recoveryData),
            loadHistory: {
                readCount += 1
                return readCount <= 2 ? original : Data("corrupt-readback".utf8)
            },
            saveHistory: { simulatedStore = $0 }
        )

        XCTAssertEqual(importer.run(), .readbackFailed)
        XCTAssertEqual(simulatedStore, original)
        XCTAssertFalse(defaults.bool(forKey: VerifiedScanHistoryRecoveryImporter.completionKey))
    }

    func testVerifiedScanRecoveryCanonicalDigestIsStableAcrossEquivalentJSONSerializations() throws {
        let records = makeVerifiedRecoveryRecords()
        let sourceData = try JSONEncoder().encode(records)
        let object = try JSONSerialization.jsonObject(with: sourceData)
        let differentlyFormattedData = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted]
        )

        let canonicalDigest = try canonicalRecoveryDigest(sourceData)
        XCTAssertEqual(canonicalDigest, try canonicalRecoveryDigest(sourceData))
        XCTAssertEqual(canonicalDigest, try canonicalRecoveryDigest(differentlyFormattedData))
        XCTAssertNotEqual(sha256(sourceData), sha256(differentlyFormattedData))
        XCTAssertNotEqual(sha256(sourceData), canonicalDigest)
    }

    func testVerifiedScanRecoveryCanonicalDigestPinsRecordLevelAuthorityInsteadOfRawPayloadEvidence() throws {
        XCTAssertEqual(
            VerifiedScanHistoryRecoveryImporter.approvedCanonicalHistorySHA256,
            "bd53b88141065e3a5ab2cca4474e77eacfea12a66b22f602019fc20bd7bb4d84"
        )
        XCTAssertEqual(
            VerifiedScanHistoryRecoveryImporter.approvedRawPayloadSHA256,
            "3f58016983c0e0c262f5ffb24c49d61c841f560bcee7e82733f5a47acaa30641"
        )
        XCTAssertNotEqual(
            VerifiedScanHistoryRecoveryImporter.approvedRawPayloadSHA256,
            VerifiedScanHistoryRecoveryImporter.approvedCanonicalHistorySHA256
        )

        let (defaults, appleUserID, suiteName) = makeRecoveryDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        configureAppleIdentity(defaults: defaults, appleUserID: appleUserID)
        let recoveryData = try JSONEncoder().encode(makeVerifiedRecoveryRecords())
        let sourceURL = try makeRecoveryPreferencesFile(containing: recoveryData)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        XCTAssertEqual(
            VerifiedScanHistoryRecoveryImporter(
                defaults: defaults,
                sourceURL: sourceURL,
                approvedCanonicalHistoryHash: sha256(recoveryData)
            ).run(),
            .invalidPayload,
            "Raw payload bytes must not substitute for the semantic record-level digest."
        )
        XCTAssertNil(defaults.data(forKey: VerifiedScanHistoryRecoveryImporter.historyKey))
    }

    func testVerifiedScanRecoveryCanonicalContractPreservesArrayOrderAndNullSemantics() throws {
        let base = Data(#"{"record":{"flag":true,"number":1.0,"emoji":"é","optional":null,"items":[1,2]}}"#.utf8)
        let reorderedObjectKeys = Data(#"{"record":{"items":[1,2],"optional":null,"emoji":"é","number":1.0,"flag":true}}"#.utf8)
        let reorderedArray = Data(#"{"record":{"flag":true,"number":1.0,"emoji":"é","optional":null,"items":[2,1]}}"#.utf8)
        let omittedNull = Data(#"{"record":{"flag":true,"number":1.0,"emoji":"é","items":[1,2]}}"#.utf8)

        let canonical = try XCTUnwrap(VerifiedScanHistoryRecoveryImporter.canonicalData(for: base))
        XCTAssertEqual(canonical, try XCTUnwrap(VerifiedScanHistoryRecoveryImporter.canonicalData(for: reorderedObjectKeys)))
        XCTAssertNotEqual(canonical, try XCTUnwrap(VerifiedScanHistoryRecoveryImporter.canonicalData(for: reorderedArray)))
        XCTAssertNotEqual(canonical, try XCTUnwrap(VerifiedScanHistoryRecoveryImporter.canonicalData(for: omittedNull)))

        let canonicalText = String(decoding: canonical, as: UTF8.self)
        XCTAssertFalse(canonicalText.contains("\n"))
        XCTAssertTrue(canonicalText.contains("\"emoji\":\"é\""))
        XCTAssertTrue(canonicalText.contains("\"flag\":true"))
        XCTAssertTrue(canonicalText.contains("\"optional\":null"))
    }

    func testVerifiedScanRecoveryCanonicalContractHandlesReorderedMissingAndDuplicateRecordKeys() throws {
        let records = makeVerifiedRecoveryRecords()
        let sourceData = try JSONEncoder().encode(records)
        let approvedDigest = try canonicalRecoveryDigest(sourceData)
        let reorderedData = try recoveryJSONData(records: records, keyOrder: records.keys.sorted().reversed())
        XCTAssertEqual(try canonicalRecoveryDigest(reorderedData), approvedDigest)

        let (reorderedDefaults, reorderedAppleUserID, reorderedSuiteName) = makeRecoveryDefaults()
        defer { reorderedDefaults.removePersistentDomain(forName: reorderedSuiteName) }
        configureAppleIdentity(defaults: reorderedDefaults, appleUserID: reorderedAppleUserID)
        let reorderedURL = try makeRecoveryPreferencesFile(containing: reorderedData)
        defer { try? FileManager.default.removeItem(at: reorderedURL) }
        XCTAssertEqual(
            VerifiedScanHistoryRecoveryImporter(
                defaults: reorderedDefaults,
                sourceURL: reorderedURL,
                approvedCanonicalHistoryHash: approvedDigest
            ).run(),
            .imported,
            "The persisted history is a keyed record object; object-member order is not record meaning."
        )

        var missingRecords = records
        missingRecords.removeValue(forKey: "verified-scan-0")
        let missingURL = try makeRecoveryPreferencesFile(containing: try JSONEncoder().encode(missingRecords))
        defer { try? FileManager.default.removeItem(at: missingURL) }
        let (missingDefaults, missingAppleUserID, missingSuiteName) = makeRecoveryDefaults()
        defer { missingDefaults.removePersistentDomain(forName: missingSuiteName) }
        configureAppleIdentity(defaults: missingDefaults, appleUserID: missingAppleUserID)
        XCTAssertEqual(
            VerifiedScanHistoryRecoveryImporter(
                defaults: missingDefaults,
                sourceURL: missingURL,
                approvedCanonicalHistoryHash: approvedDigest
            ).run(),
            .invalidPayload
        )

        let duplicateData = try recoveryJSONData(
            records: records,
            keyOrder: records.keys.sorted(),
            duplicateKey: "verified-scan-0"
        )
        let duplicateURL = try makeRecoveryPreferencesFile(containing: duplicateData)
        defer { try? FileManager.default.removeItem(at: duplicateURL) }
        let (duplicateDefaults, duplicateAppleUserID, duplicateSuiteName) = makeRecoveryDefaults()
        defer { duplicateDefaults.removePersistentDomain(forName: duplicateSuiteName) }
        configureAppleIdentity(defaults: duplicateDefaults, appleUserID: duplicateAppleUserID)
        XCTAssertEqual(
            VerifiedScanHistoryRecoveryImporter(
                defaults: duplicateDefaults,
                sourceURL: duplicateURL,
                approvedCanonicalHistoryHash: approvedDigest
            ).run(),
            .invalidPayload
        )
        XCTAssertNil(duplicateDefaults.data(forKey: VerifiedScanHistoryRecoveryImporter.historyKey))
    }

    func testVerifiedScanRecoveryRejectsSemanticMutationsWithoutWritingHistory() throws {
        let (defaults, appleUserID, suiteName) = makeRecoveryDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        configureAppleIdentity(defaults: defaults, appleUserID: appleUserID)

        let records = makeVerifiedRecoveryRecords()
        let sourceData = try JSONEncoder().encode(records)
        let approvedDigest = try canonicalRecoveryDigest(sourceData)
        let original = try XCTUnwrap(records["verified-scan-0"])
        var changedScore = records
        changedScore["verified-scan-0"] = RecoveryImportFixtureRecord(
            score: original.score + 1,
            firstScannedAt: original.firstScannedAt,
            scanCount: original.scanCount,
            analysis: original.analysis,
            thumbnailData: original.thumbnailData
        )
        var changedTimestamp = records
        changedTimestamp["verified-scan-0"] = RecoveryImportFixtureRecord(
            score: original.score,
            firstScannedAt: original.firstScannedAt.addingTimeInterval(1),
            scanCount: original.scanCount,
            analysis: original.analysis,
            thumbnailData: original.thumbnailData
        )
        var changedID = records
        changedID.removeValue(forKey: "verified-scan-0")
        changedID["different-stable-id"] = original

        for mutatedRecords in [changedScore, changedTimestamp, changedID] {
            let mutatedData = try JSONEncoder().encode(mutatedRecords)
            let sourceURL = try makeRecoveryPreferencesFile(containing: mutatedData)
            defer { try? FileManager.default.removeItem(at: sourceURL) }

            XCTAssertEqual(
                VerifiedScanHistoryRecoveryImporter(
                    defaults: defaults,
                    sourceURL: sourceURL,
                    approvedCanonicalHistoryHash: approvedDigest
                ).run(),
                .invalidPayload
            )
            XCTAssertNil(defaults.data(forKey: VerifiedScanHistoryRecoveryImporter.historyKey))
            XCTAssertFalse(defaults.bool(forKey: VerifiedScanHistoryRecoveryImporter.completionKey))
        }
    }

    private func makeRecoveryDefaults() -> (UserDefaults, String, String) {
        let suiteName = "VerifiedScanRecoveryTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create isolated recovery defaults")
        }
        return (defaults, "verified-apple-user", suiteName)
    }

    private func configureAppleIdentity(defaults: UserDefaults, appleUserID: String) {
        defaults.set("Sign in with Apple", forKey: "customerAccountMode")
        defaults.set(appleUserID, forKey: "customerAppleUserID")
        defaults.set(PersonalStylistStorage.normalizedUserID(appleUserID), forKey: AccountScopedStorage.activeUserMarkerKey)
        defaults.set(AccountStorageEnvironment.production.rawValue, forKey: AccountScopedStorage.activeEnvironmentMarkerKey)
    }

    private func makeVerifiedRecoveryRecords() -> [String: RecoveryImportFixtureRecord] {
        Dictionary(uniqueKeysWithValues: (0..<7).map { index in
            (
                "verified-scan-\(index)",
                RecoveryImportFixtureRecord(
                    score: 74 + (index % 2) * 6,
                    firstScannedAt: Date(timeIntervalSinceReferenceDate: TimeInterval(800_000 + index)),
                    scanCount: 1,
                    analysis: ["summary": "Verified fixture \(index)"],
                    thumbnailData: index.isMultiple(of: 2) ? Data("thumb-\(index)".utf8) : nil
                )
            )
        })
    }

    private func makeRecoveryPreferencesFile(containing recoveryData: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VerifiedScanRecovery-\(UUID().uuidString).json")
        try recoveryData.write(to: url)
        return url
    }

    private func recoveryJSONData(
        records: [String: RecoveryImportFixtureRecord],
        keyOrder: some Sequence<String>,
        duplicateKey: String? = nil
    ) throws -> Data {
        let sourceData = try JSONEncoder().encode(records)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: sourceData) as? [String: Any])
        var members = try keyOrder.map { key -> String in
            let keyData = try JSONSerialization.data(withJSONObject: [key])
            let quotedKey = String(decoding: keyData.dropFirst().dropLast(), as: UTF8.self)
            let value = try XCTUnwrap(object[key])
            let valueData = try JSONSerialization.data(withJSONObject: value)
            return "\(quotedKey):\(String(decoding: valueData, as: UTF8.self))"
        }
        if let duplicateKey {
            let keyData = try JSONSerialization.data(withJSONObject: [duplicateKey])
            let quotedKey = String(decoding: keyData.dropFirst().dropLast(), as: UTF8.self)
            let value = try XCTUnwrap(object[duplicateKey])
            let valueData = try JSONSerialization.data(withJSONObject: value)
            members.append("\(quotedKey):\(String(decoding: valueData, as: UTF8.self))")
        }
        return Data("{\(members.joined(separator: ","))}".utf8)
    }

    private func decodedRecoveryRecordIDs(_ data: Data?) throws -> Set<String> {
        let payload = try XCTUnwrap(data)
        let records = try JSONDecoder().decode([String: RecoveryImportFixtureRecord].self, from: payload)
        return Set(records.keys)
    }

    private func canonicalRecoveryDigest(_ data: Data) throws -> String {
        try XCTUnwrap(VerifiedScanHistoryRecoveryImporter.canonicalDigest(for: data))
    }

    func testClosetScanHistoryAffordancesUseLocalDetailAndListActions() throws {
        let source = try projectSource("StyleMatchAI/ClosetView.swift")

        XCTAssertTrue(source.contains("case scannedGarments"))
        XCTAssertTrue(source.contains("case scannedGarmentDetail(UUID)"))
        XCTAssertTrue(source.contains("activeSheet = .scannedGarments"))
        XCTAssertTrue(source.contains("activeSheet = .scannedGarmentDetail(record.id)"))
        XCTAssertTrue(source.contains("scannedGarmentDetailSheet(record)"))
        XCTAssertTrue(source.contains("Label(\"From scan history\", systemImage: \"camera.viewfinder\")"))
        XCTAssertTrue(source.contains("record.timesSeen"))
        XCTAssertTrue(source.contains("availableGarmentDetail(record.fit)"))
        XCTAssertFalse(source.contains("URLSession"))
    }

    func testClosetScannedCategoryAndAddItemAffordancesAreConsistent() throws {
        let source = try projectSource("StyleMatchAI/ClosetView.swift")

        XCTAssertTrue(source.contains("toggleScannedCategory(group.category)"))
        XCTAssertTrue(source.contains("visibleScannedRecords(for: group)"))
        XCTAssertTrue(source.contains("+\\(group.records.count - 4) more from scan history"))
        XCTAssertEqual(source.components(separatedBy: "isShowingAddItemSheet = true").count - 1, 1)
        XCTAssertTrue(source.contains("private func presentAddItem()"))

        let start = try XCTUnwrap(source.range(of: "private func foundationStep"))
        let end = try XCTUnwrap(source.range(of: "private var mergedClosetDesignerCard", range: start.upperBound..<source.endIndex))
        let foundationStepSource = String(source[start.lowerBound..<end.lowerBound])
        XCTAssertFalse(foundationStepSource.contains("Button"))
    }

    func testScanHistoryUsesOneCardActionAndAccessibleOverflowMenu() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        let start = try XCTUnwrap(source.range(of: "private func recentScoreRow"))
        let end = try XCTUnwrap(source.range(of: "private func savedScanOccasionRow", range: start.upperBound..<source.endIndex))
        let cardSource = String(source[start.lowerBound..<end.lowerBound])

        XCTAssertTrue(cardSource.contains("scanHistoryOverflowMenu(scan, scrollProxy: scrollProxy)"))
        XCTAssertFalse(cardSource.contains("LazyVGrid(columns:"))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"More actions for \\(scan.title)\")"))
        XCTAssertTrue(source.contains("Label(\"Open\", systemImage: \"folder\")"))
        XCTAssertTrue(source.contains("Label(\"Compare\", systemImage: \"arrow.left.arrow.right\")"))
        XCTAssertTrue(source.contains("Label(\"Rescan\", systemImage: \"camera.viewfinder\")"))
        XCTAssertTrue(source.contains("Label(\"Share\", systemImage: \"square.and.arrow.up\")"))
        XCTAssertTrue(source.contains("Label(\"Delete\", systemImage: \"trash\")"))
    }

    func testScanDiscoveryAndSafeAreaUseExistingLocalRecords() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(source.contains("scanDiscoveryRails(scans, scrollProxy: scrollProxy)"))
        XCTAssertTrue(source.contains("title: \"Continue Styling\""))
        XCTAssertTrue(source.contains("title: \"Favorites\""))
        XCTAssertTrue(source.contains("scans.filter { $0.isFavorite(in: favoriteOutfits) }"))
        XCTAssertTrue(source.contains(".safeAreaInset(edge: .bottom, spacing: 0)"))
        XCTAssertTrue(source.contains("Text(\"\\(scans.count) saved\")"))
        XCTAssertFalse(source.contains("Text(\"\\(scans.count)/20\")"))
    }

    func testSavedScanOpenIsReadOnlyForProfileAndOutfitMemory() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        let start = try XCTUnwrap(source.range(of: "private func openSavedScan("))
        let end = try XCTUnwrap(source.range(of: "private func publishCurrentStylistScanHandoff", range: start.upperBound..<source.endIndex))
        let openPath = String(source[start.lowerBound..<end.lowerBound])

        XCTAssertTrue(openPath.contains("result = scan.analysis"))
        XCTAssertTrue(openPath.contains("activeScanFingerprint = scan.id"))
        XCTAssertFalse(openPath.contains("analyze("))
        XCTAssertFalse(openPath.contains("calculateStyleScore"))
        XCTAssertFalse(openPath.contains("saveScanHistory("))
        XCTAssertFalse(openPath.contains("ensureOutfitMemory("))
        XCTAssertFalse(openPath.contains("OutfitMemoryStore"))
        XCTAssertFalse(openPath.contains("ProfileStore"))
        XCTAssertFalse(openPath.contains("Date()"))
        XCTAssertFalse(openPath.contains("UserDefaults"))
    }

    func testSavedScanStylistAuthorityFailsClosedBeforeSyntheticTimestampFallback() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        let start = try XCTUnwrap(source.range(of: "private func authoritativeStylistScanContext("))
        let end = try XCTUnwrap(source.range(of: "private var scanHistoryFilterBar", range: start.upperBound..<source.endIndex))
        let authorityPath = String(source[start.lowerBound..<end.lowerBound])
        let guardRange = try XCTUnwrap(authorityPath.range(of: "guard source != .savedSelection || stored != nil else"))
        let dateRange = try XCTUnwrap(authorityPath.range(of: "completedAt: stored?.firstScannedAt ?? Date()"))

        XCTAssertLessThan(guardRange.lowerBound, dateRange.lowerBound)
        XCTAssertTrue(authorityPath.contains("If its exact record disappeared, it has no Stylist authority."))
    }

    func testSavedScanCompareWithoutCurrentResultIsReadOnlyForProfileAndOutfitMemory() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        let start = try XCTUnwrap(source.range(of: "private func compareSavedScan("))
        let end = try XCTUnwrap(source.range(of: "private func presentComparison", range: start.upperBound..<source.endIndex))
        let comparePath = String(source[start.lowerBound..<end.lowerBound])

        XCTAssertTrue(comparePath.contains("compareSourceScan = scan"))
        XCTAssertFalse(comparePath.contains("analyze("))
        XCTAssertFalse(comparePath.contains("calculateStyleScore"))
        XCTAssertFalse(comparePath.contains("saveScanHistory("))
        XCTAssertFalse(comparePath.contains("ensureOutfitMemory("))
        XCTAssertFalse(comparePath.contains("OutfitMemoryStore"))
        XCTAssertFalse(comparePath.contains("ProfileStore"))
        XCTAssertFalse(comparePath.contains("Date()"))
        XCTAssertFalse(comparePath.contains("UserDefaults"))
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utcTimeZone
        return calendar
    }

    private func makeCalendarAwarenessDefaults() -> (UserDefaults, String, String) {
        let suiteName = "CalendarAwarenessTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create isolated Calendar Awareness test defaults")
        }
        return (defaults, "calendar-user-a-\(UUID().uuidString)", suiteName)
    }

    func testHomeIntelligenceTurnsWeatherCalendarClosetAndShoppingFactsIntoTypedActions() throws {
        let attribution = try XCTUnwrap(WeatherAttributionMetadata(
            serviceName: "Apple Weather",
            combinedMarkLightURL: URL(string: "https://example.com/light")!,
            combinedMarkDarkURL: URL(string: "https://example.com/dark")!,
            legalPageURL: URL(string: "https://example.com/legal")!
        ))
        let weather = try XCTUnwrap(WeatherSnapshot(
            observedAt: Date(),
            locationName: "Miami, Florida",
            temperatureFahrenheit: 88,
            feelsLikeFahrenheit: 94,
            condition: "Rain showers",
            rainChancePercent: 70,
            humidityPercent: 84,
            windMph: 10,
            uvIndex: 8,
            hourlySummary: nil,
            dailySummary: nil,
            attribution: attribution
        ))
        let input = HomeIntelligenceInput(
            weather: weather,
            calendar: nil,
            calendarAuthorized: false,
            plannedOccasion: "Work",
            dressCode: "",
            workplace: "Office",
            closetItems: [
                .init(category: "Shirt", name: "Blue shirt"),
                .init(category: "Pants", name: "Navy trousers"),
                .init(category: "Shoes", name: "Black shoes")
            ],
            savedScanCount: 2,
            savedShoppingCount: 1
        )
        let plan = HomeIntelligenceAuthority.make(input: input)
        let weatherDetail = try XCTUnwrap(plan[HomeIntelligenceFocus.weather])
        XCTAssertTrue(weatherDetail.facts.contains { $0.text.contains("70%") })
        XCTAssertTrue(weatherDetail.actionKinds.contains(.askStylist))
        XCTAssertTrue(weatherDetail.actionKinds.contains(.viewForecast))

        let calendarDetail = try XCTUnwrap(plan[HomeIntelligenceFocus.calendar])
        XCTAssertTrue(calendarDetail.actionKinds.contains(.enableCalendar))
        XCTAssertTrue(calendarDetail.summary.contains("Connect Calendar"))

        let checklistDetail = try XCTUnwrap(plan[HomeIntelligenceFocus.outfitChecklist])
        XCTAssertTrue(checklistDetail.checklist.contains { $0.role == "Top" && $0.state == .ready })
        XCTAssertTrue(checklistDetail.checklist.contains { $0.role == "Rain plan" && $0.state == .weatherRequired })

        let shoppingDetail = try XCTUnwrap(plan[HomeIntelligenceFocus.shopping])
        XCTAssertTrue(shoppingDetail.actionKinds.contains(.openShop))
        XCTAssertEqual(shoppingDetail.actions.first(where: { $0.action == .openShop })?.priority, .recommendedNow)
        XCTAssertTrue(shoppingDetail.facts.contains { $0.text.contains("saved shopping") })
    }

    func testHomeIntelligenceDoesNotTurnMissingClosetOrWearHistoryIntoFalseFacts() throws {
        let input = HomeIntelligenceInput(
            weather: nil,
            calendar: nil,
            calendarAuthorized: true,
            plannedOccasion: "",
            dressCode: "",
            workplace: "",
            closetItems: [],
            savedScanCount: 0,
            savedShoppingCount: 0
        )
        let plan = HomeIntelligenceAuthority.make(input: input)
        let laundry = try XCTUnwrap(plan[HomeIntelligenceFocus.laundry])
        XCTAssertTrue(laundry.facts.contains { $0.evidence == .unknown })
        XCTAssertTrue(laundry.summary.localizedCaseInsensitiveContains("without actual wear or care evidence"))

        let gaps = try XCTUnwrap(plan[HomeIntelligenceFocus.missingPieces])
        XCTAssertTrue(gaps.summary.contains("does not mean you do not own"))
        XCTAssertTrue(gaps.actionKinds.contains(.openScan))
        XCTAssertTrue(gaps.actionKinds.contains(.askStylist))
    }

    func testHomeIntelligenceUnknownStatesPrioritizeRecoveryBeforeShopping() throws {
        let input = HomeIntelligenceInput(
            weather: nil,
            calendar: nil,
            calendarAuthorized: false,
            plannedOccasion: "",
            dressCode: "",
            workplace: "",
            closetItems: [],
            savedScanCount: 0,
            savedShoppingCount: 0
        )
        let plan = HomeIntelligenceAuthority.make(input: input)
        let checklist = try XCTUnwrap(plan[.outfitChecklist])
        XCTAssertTrue(checklist.checklist.allSatisfy { $0.state == .unknown })
        XCTAssertEqual(checklist.actions.first(where: { $0.action == .openCloset })?.priority, .recommendedNow)
        XCTAssertEqual(checklist.actions.first(where: { $0.action == .openScan })?.priority, .needsInput)

        let shopping = try XCTUnwrap(plan[.shopping])
        XCTAssertEqual(shopping.actions.first(where: { $0.action == .openCloset })?.priority, .recommendedNow)
        XCTAssertEqual(shopping.actions.first(where: { $0.action == .openShop })?.priority, .recommendedNow)
        XCTAssertTrue(shopping.actions.contains { $0.action == .openShop && $0.rationale.contains("today’s plan") })
    }

    func testHomeIntelligenceUsesOnlySanitizedCalendarAndConfirmedPPEContext() throws {
        let calendar = CalendarContextProjection(
            category: .formalEvent,
            timeWindow: .evening,
            approximateDurationMinutes: 120,
            isAllDay: false,
            isRecurring: false,
            expiresAt: Date().addingTimeInterval(3_600)
        )
        let input = HomeIntelligenceInput(
            weather: nil,
            calendar: calendar,
            calendarAuthorized: true,
            plannedOccasion: "",
            dressCode: "",
            workplace: "PPE required",
            closetItems: [.init(category: "Shirt", name: "White shirt")],
            savedScanCount: 0,
            savedShoppingCount: 0
        )
        let plan = HomeIntelligenceAuthority.make(input: input)
        let calendarDetail = try XCTUnwrap(plan[.calendar])
        XCTAssertEqual(calendarDetail.headline, "Prepare for Formal Event")
        XCTAssertTrue(calendarDetail.actionKinds.contains(.askStylist))
        XCTAssertFalse(calendarDetail.facts.contains { $0.text.localizedCaseInsensitiveContains("event title") && !$0.text.localizedCaseInsensitiveContains("rather than") })

        let checklist = try XCTUnwrap(plan[.outfitChecklist])
        XCTAssertTrue(checklist.checklist.contains { $0.role == "Work/PPE" && $0.state == .ppeRequired })
    }

    func testHomeIntelligencePrioritizesAndSummarizesMultipleMinimizedCalendarEvents() throws {
        let now = Date()
        let birthday = CalendarContextProjection(category: .birthday, timeWindow: .evening, approximateDurationMinutes: 120, isAllDay: false, isRecurring: false, expiresAt: now.addingTimeInterval(3_600))
        let wedding = CalendarContextProjection(category: .wedding, timeWindow: .morning, approximateDurationMinutes: 240, isAllDay: false, isRecurring: false, expiresAt: now.addingTimeInterval(86_400))
        let input = HomeIntelligenceInput(
            weather: nil,
            calendar: birthday,
            calendarEvents: [birthday, wedding],
            calendarAuthorized: true,
            plannedOccasion: "",
            dressCode: "",
            workplace: "",
            closetItems: [],
            savedScanCount: 0,
            savedShoppingCount: 0
        )
        let calendar = try XCTUnwrap(HomeIntelligenceAuthority.make(input: input)[.calendar])
        XCTAssertEqual(calendar.headline, "Prepare for Birthday")
        XCTAssertTrue(calendar.facts.contains { $0.text.contains("Also coming up: Wedding") })
        XCTAssertTrue(calendar.stylistFacts.contains { $0.contains("Birthday") })
        XCTAssertFalse(calendar.stylistFacts.joined(separator: " ").contains("Alice’s"))
    }

    func testHomeIntelligenceTreatsAnUnrecognizedEventAsAnEventInsteadOfNoEvent() throws {
        let event = CalendarContextProjection(
            category: .otherSignificantEvent,
            timeWindow: .afternoon,
            approximateDurationMinutes: 60,
            isAllDay: false,
            isRecurring: false,
            expiresAt: Date().addingTimeInterval(86_400)
        )
        let input = HomeIntelligenceInput(
            weather: nil,
            calendar: event,
            calendarEvents: [event],
            calendarAuthorized: true,
            plannedOccasion: "",
            dressCode: "",
            workplace: "",
            closetItems: [],
            savedScanCount: 0,
            savedShoppingCount: 0
        )
        let detail = try XCTUnwrap(HomeIntelligenceAuthority.make(input: input)[.calendar])
        XCTAssertEqual(detail.headline, "Prepare for Upcoming Event")
        XCTAssertFalse(detail.summary.contains("No recognized event"))
        XCTAssertTrue(detail.actionKinds.contains(.buildOutfit))
    }

    func testHomeIntelligenceSourceUsesOneAuthorityAndTypedStylistHandoff() throws {
        let home = try projectSource("StyleMatchAI/HomeView.swift")
        let content = try projectSource("StyleMatchAI/ContentView.swift")
        let models = try projectSource("StyleMatchAI/StylistChat/StylistChatModels.swift")
        let presentation = try projectSource("StyleMatchAI/WeatherStylingPresentation.swift")

        XCTAssertTrue(home.contains("HomeIntelligenceAuthority.make(input: homeIntelligenceInput)"))
        XCTAssertTrue(home.contains("What you can do now"))
        XCTAssertTrue(home.contains("floatingStylistClearance"))
        XCTAssertTrue(home.contains("showHomeEngagement(.intelligence(focus))"))
        XCTAssertTrue(home.contains("onOpenHomeIntelligenceStylist(detail)"))
        XCTAssertTrue(home.contains("onPrepareHomeIntelligenceShopping(detail)"))
        XCTAssertFalse(home.contains("This uses local profile, closet, weather, saved scans, or shopping data already available on this device."))
        XCTAssertTrue(content.contains("onOpenHomeIntelligenceStylist: openHomeIntelligenceStylistConversation"))
        XCTAssertTrue(content.contains("onPrepareHomeIntelligenceShopping: prepareHomeIntelligenceShopping"))
        XCTAssertTrue(content.contains("homeFloatingStylistClearance"))
        XCTAssertTrue(content.contains("publishHomeIntelligence(detail)"))
        XCTAssertTrue(models.contains("static func homeIntelligence("))
        XCTAssertTrue(models.contains("mutating func publishHomeIntelligence("))
        XCTAssertTrue(presentation.contains("enum HomeIntelligenceEvidenceState"))
        XCTAssertTrue(presentation.contains("case confirmed"))
        XCTAssertTrue(presentation.contains("case inferred"))
        XCTAssertTrue(presentation.contains("case unknown"))
        XCTAssertTrue(presentation.contains("enum HomeIntelligenceActionPriority"))
        XCTAssertTrue(presentation.contains("Shop AI receives today’s plan"))
    }

    func testHomeIntelligenceActionsUseRootTabAuthorityAndAccessibleTargets() throws {
        let home = try projectSource("StyleMatchAI/HomeView.swift")

        XCTAssertTrue(home.contains("selectTab(.closet)"))
        XCTAssertTrue(home.contains("selectTab(.scan)"))
        XCTAssertTrue(home.contains("selectTab(.shop)"))
        XCTAssertTrue(home.contains("selectTab(.profile)"))
        XCTAssertTrue(home.contains("minHeight: 52"))
        XCTAssertTrue(home.contains("home-intelligence-action-"))
        XCTAssertTrue(home.contains("contentShape(RoundedRectangle(cornerRadius: 14))"))
    }

    private func recursiveSwiftSources(in url: URL) throws -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }
        if !isDirectory.boolValue {
            return url.pathExtension == "swift" ? [url] : []
        }
        let children = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        return try children.flatMap { try recursiveSwiftSources(in: $0) }
    }

    private func projectSource(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func makeAnalysis(
        score: Int = 82,
        styleBalance: String = "Casual",
        summary: String = "Synthetic summary",
        detectedItems: [String] = ["polo"],
        suggestions: [String] = ["Keep proportions balanced."],
        recommendations: [ClothingRecommendation] = [
            ClothingRecommendation(
                category: "shirt",
                title: "Synthetic",
                reason: "Synthetic reason",
                personalization: "Synthetic personalization"
            )
        ]
    ) -> OutfitAnalysisResult {
        OutfitAnalysisResult(
            score: score,
            colorMatch: "White and gray",
            occasionFit: "Everyday",
            styleBalance: styleBalance,
            colorHarmony: "Balanced",
            styleCoordination: "Coordinated",
            formality: "casual",
            seasonalMatch: "Mild",
            summary: summary,
            outfitDescription: "Synthetic outfit",
            detectedClothingItems: detectedItems,
            colorPalette: ["white", "gray"],
            colorPaletteMaskingApplied: true,
            colorPaletteMaskTier: GarmentMaskTier.foregroundSubject.rawValue,
            environment: "indoor",
            imageQuality: "clear",
            skinToneStyleNote: "No skin-tone recommendation needed.",
            detectedItemConfidences: [
                DetectedItemConfidence(item: "Textile", confidence: 92),
                DetectedItemConfidence(item: "polo", confidence: 90)
            ],
            suggestions: suggestions,
            recommendations: recommendations
        )
    }
}
