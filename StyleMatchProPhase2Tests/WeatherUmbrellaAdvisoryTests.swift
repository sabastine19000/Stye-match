import XCTest
@testable import StyleMatchPro

final class WeatherUmbrellaAdvisoryTests: XCTestCase {
    func testCurrentRainWithLowProbabilityIsRainingNow() throws {
        let snapshot = try snapshot(condition: "Rain", chance: 3, currentPrecipitationIntensityKilometersPerHour: 0.2)
        XCTAssertEqual(advisory(snapshot), .rainingNow)
        XCTAssertEqual(snapshot.currentPrecipitationDisplayText, "Rain 0.20 km/h")
        XCTAssertEqual(advisory(snapshot).guidance(for: snapshot.condition), "It’s raining now — grab an umbrella before you head out.")
    }

    func testThunderstormRiskWithoutCurrentPrecipitationNeverClaimsRainNow() throws {
        let snapshot = try snapshot(condition: "Isolated Thunderstorms", chance: 25)
        XCTAssertEqual(advisory(snapshot), .hazardousPrecipitation)
        XCTAssertEqual(advisory(snapshot).guidance(for: snapshot.condition), "Thunderstorms are possible nearby. Consider rain protection and follow local safety guidance.")
        XCTAssertEqual(WeatherCurrentConditionVisualState.make(snapshot: snapshot, hasLiveWeather: true), .thunderstormRisk)
        XCTAssertFalse(WeatherConditionAnimationPolicy.continuousMotionEnabled(for: .thunderstormRisk, reduceMotion: false))
    }

    func testDailyOrAggregateChanceWithoutHourlyWindowDoesNotCreateUmbrellaAlert() throws {
        XCTAssertEqual(advisory(try snapshot(condition: "Mostly Clear", chance: 60)), .none)
    }

    func testNearHourlyWeatherKitRainIsImminent() throws {
        let observedAt = Date(timeIntervalSince1970: 1_723_139_200)
        let hourly = try XCTUnwrap(WeatherHourlyForecastEntry(date: observedAt.addingTimeInterval(30 * 60), temperatureFahrenheit: 70, condition: "Drizzle"))
        XCTAssertEqual(WeatherUmbrellaAdvisory.make(snapshot: try snapshot(condition: "Cloudy", chance: 3, observedAt: observedAt, hourly: [hourly]), now: observedAt), .imminent)
    }

    func testHourlyRainLaterUsesItsWeatherKitTimeInsteadOfVagueDailyCopy() throws {
        let observedAt = Date(timeIntervalSince1970: 1_723_139_200)
        let hourly = try XCTUnwrap(WeatherHourlyForecastEntry(date: observedAt.addingTimeInterval(2 * 60 * 60), temperatureFahrenheit: 70, condition: "Rain", precipitationProbabilityPercent: 55))
        let snapshot = try snapshot(condition: "Mostly Clear", chance: 90, observedAt: observedAt, hourly: [hourly])
        let advisory = WeatherUmbrellaAdvisory.make(snapshot: snapshot, now: observedAt)
        XCTAssertEqual(advisory, .possibleLater)
        XCTAssertTrue(advisory.guidance(for: snapshot)?.contains("around") == true)
    }

    func testStaleSnapshotSuppressesWeatherAlert() throws {
        let observedAt = Date().addingTimeInterval(-91 * 60)
        XCTAssertEqual(WeatherUmbrellaAdvisory.make(snapshot: try snapshot(condition: "Rain", chance: 100, observedAt: observedAt)), .none)
    }

    func testDryCurrentWeatherWithLowProbabilityHasNoUmbrellaAdvice() throws {
        XCTAssertEqual(advisory(try snapshot(condition: "Partly Cloudy", chance: 3)), .none)
    }

    func testPositiveCurrentIntensityWithoutSpecificConditionUsesGenericObservedPrecipitation() throws {
        let now = Date()
        let weather = try snapshot(
            condition: "Mostly Cloudy",
            chance: 5,
            currentPrecipitationIntensityKilometersPerHour: 0.01,
            observedAt: now
        )

        XCTAssertEqual(weather.currentPrecipitationState(at: now), .precipitation)
        XCTAssertTrue(weather.currentPrecipitationDisplayText.hasPrefix("Precipitation "))
        XCTAssertEqual(WeatherUmbrellaAdvisory.make(snapshot: weather, now: now), .none)
        XCTAssertNil(GlobalWeatherAlert.make(snapshot: weather).message)
        XCTAssertNil(WeatherStylingRecommendation.make(snapshot: weather, occasion: "Work", favoriteColors: "navy").umbrellaGuidance)
    }

    func testCurrentIntensityZeroIsNoneEvenWhenMinuteForecastIsUnavailableAndChanceIsFutureOnly() throws {
        let now = Date()
        let weather = try snapshot(
            condition: "Mostly Cloudy",
            chance: 17,
            currentPrecipitationIntensityKilometersPerHour: 0,
            observedAt: now
        )

        XCTAssertEqual(weather.currentPrecipitationState(at: now), .none)
        XCTAssertEqual(weather.currentPrecipitationDisplayText, "None")
        XCTAssertEqual(WeatherUmbrellaAdvisory.make(snapshot: weather, now: now), .none)
    }

    func testFutureChanceDoesNotOverrideCurrentIntensityZero() throws {
        let now = Date()
        let future = try XCTUnwrap(WeatherHourlyForecastEntry(
            date: now.addingTimeInterval(90 * 60),
            temperatureFahrenheit: 70,
            condition: "Rain",
            precipitationProbabilityPercent: 17
        ))
        let weather = try snapshot(
            condition: "Cloudy",
            chance: 17,
            currentPrecipitationIntensityKilometersPerHour: 0,
            observedAt: now,
            hourly: [future]
        )

        XCTAssertEqual(weather.currentPrecipitationState(at: now), .none)
        XCTAssertEqual(weather.currentPrecipitationDisplayText, "None")
        // A 17% future chance is not a current observation and remains below
        // the near-term advisory threshold.
        XCTAssertEqual(WeatherUmbrellaAdvisory.make(snapshot: weather, now: now), .none)
    }

    func testCurrentObservationMissingIntensityIsUnavailableRatherThanForecastInferred() throws {
        let now = Date()
        let weather = try snapshot(condition: "Cloudy", chance: 17, observedAt: now)

        XCTAssertEqual(weather.currentPrecipitationState(at: now), .unknown)
        XCTAssertEqual(weather.currentPrecipitationDisplayText, "Unavailable")
    }

    func testFutureRainUsesFutureWordingWithoutClaimingRainNow() throws {
        let now = Date()
        let hourly = try XCTUnwrap(WeatherHourlyForecastEntry(date: now.addingTimeInterval(90 * 60), temperatureFahrenheit: 80, condition: "Rain", precipitationProbabilityPercent: 65))
        let weather = try snapshot(
            condition: "Mostly Cloudy",
            chance: 65,
            currentPrecipitationIntensityKilometersPerHour: 0,
            observedAt: now,
            hourly: [hourly]
        )
        let advisory = WeatherUmbrellaAdvisory.make(snapshot: weather, now: now)

        XCTAssertEqual(weather.currentPrecipitationState(at: now), .none)
        XCTAssertEqual(advisory, .possibleLater)
        XCTAssertFalse(advisory.guidance(for: weather)?.contains("raining now") == true)
    }

    func testStaleOrNonRainObservedPrecipitationFailsClosed() throws {
        let stale = try snapshot(condition: "Rain", chance: 90, currentPrecipitationIntensityKilometersPerHour: 0.2, observedAt: Date().addingTimeInterval(-91 * 60))
        XCTAssertEqual(stale.currentPrecipitationState(), .unknown)
        XCTAssertEqual(WeatherUmbrellaAdvisory.make(snapshot: stale), .none)
    }

    func testSnowAndMixedPrecipitationAreNeverLabeledAsRain() throws {
        let snow = try snapshot(condition: "Snow", chance: 80, currentPrecipitationIntensityKilometersPerHour: 0.2)
        let mixed = try snapshot(condition: "Sleet", chance: 80, currentPrecipitationIntensityKilometersPerHour: 0.2)
        XCTAssertEqual(advisory(snow), .snowingNow)
        XCTAssertEqual(advisory(mixed), .mixedPrecipitationNow)
        XCTAssertFalse(advisory(snow).guidance(for: snow)?.contains("raining now") == true)
        XCTAssertFalse(advisory(mixed).guidance(for: mixed)?.contains("raining now") == true)
    }

    func testRainToDryClearsTheCanonicalAdvisory() throws {
        XCTAssertEqual(advisory(try snapshot(condition: "Rain", chance: 3, currentPrecipitationIntensityKilometersPerHour: 0.2)), .rainingNow)
        XCTAssertEqual(advisory(try snapshot(condition: "Clear", chance: 3)), .none)
    }

    func testActiveDrizzleAllowsCurrentPrecipitationPresentation() throws {
        let snapshot = try snapshot(condition: "Drizzle", chance: 25, currentPrecipitationIntensityKilometersPerHour: 0.05)
        XCTAssertTrue(snapshot.hasCurrentPrecipitation)
        XCTAssertEqual(advisory(snapshot), .rainingNow)
        XCTAssertEqual(WeatherCurrentConditionVisualState.make(snapshot: snapshot, hasLiveWeather: true), .drizzle)
    }

    func testFutureRainOnlyDoesNotCreateCurrentRainState() throws {
        let observedAt = Date(timeIntervalSince1970: 1_723_139_200)
        let hourly = try XCTUnwrap(WeatherHourlyForecastEntry(date: observedAt.addingTimeInterval(90 * 60), temperatureFahrenheit: 77, condition: "Rain", precipitationProbabilityPercent: 65))
        let snapshot = try snapshot(condition: "Mostly Cloudy", chance: 25, observedAt: observedAt, hourly: [hourly])
        XCTAssertEqual(advisory(snapshot), .possibleLater)
        XCTAssertEqual(WeatherCurrentConditionVisualState.make(snapshot: snapshot, hasLiveWeather: true), .cloudy)
    }

    func testFutureRainGuidanceDoesNotApplyCurrentWetOutfitTreatment() throws {
        let observedAt = Date()
        let hourly = try XCTUnwrap(WeatherHourlyForecastEntry(date: observedAt.addingTimeInterval(90 * 60), temperatureFahrenheit: 77, condition: "Rain", precipitationProbabilityPercent: 65))
        let snapshot = try snapshot(condition: "Partly Cloudy", chance: 65, observedAt: observedAt, hourly: [hourly])
        let presentation = WeatherStylingRecommendation.make(snapshot: snapshot, occasion: "Work", favoriteColors: "navy")
        XCTAssertTrue(presentation.umbrellaGuidance?.contains("Rain is possible") == true)
        XCTAssertFalse(presentation.items.contains { $0.title.contains("Water-friendly") || $0.title.contains("Light rain layer") })
    }

    func testSameActiveEventDoesNotRepeatAcrossRefreshOrRelaunch() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "WeatherUmbrellaDedup-\(UUID().uuidString)"))
        let key = "event"
        let store = WeatherUmbrellaAlertEventStore(defaults: defaults, key: key)
        XCTAssertTrue(store.shouldPresent(for: .rainingNow))
        XCTAssertFalse(store.shouldPresent(for: .rainingNow))
        XCTAssertFalse(WeatherUmbrellaAlertEventStore(defaults: defaults, key: key).shouldPresent(for: .rainingNow))
    }

    func testNewRainEventCanAlertAfterDryWeather() throws {
        let store = WeatherUmbrellaAlertEventStore(defaults: try XCTUnwrap(UserDefaults(suiteName: "WeatherUmbrellaNewEvent-\(UUID().uuidString)")))
        XCTAssertTrue(store.shouldPresent(for: .rainingNow))
        XCTAssertFalse(store.shouldPresent(for: .none))
        XCTAssertTrue(store.shouldPresent(for: .rainingNow))
    }

    func testUnavailableWeatherFailsTruthfully() {
        XCTAssertEqual(WeatherUmbrellaAdvisory.make(snapshot: nil), .none)
        XCTAssertNil(WeatherUmbrellaAdvisory.make(snapshot: nil).guidance)
    }

    func testWeatherStylingAndStylistUseTheSameCanonicalAdvisory() throws {
        let weather = try snapshot(condition: "Thunderstorms", chance: 3)
        let advisory = self.advisory(weather)
        let styling = WeatherStylingRecommendation.make(snapshot: weather, occasion: "Work", favoriteColors: "navy")
        let stylist = WeatherAdvisor.advice(for: WeatherAdvisorInput(
            feelsLikeTemperature: weather.feelsLikeFahrenheit,
            humidityPercent: weather.humidityPercent,
            rainChancePercent: weather.rainChancePercent,
            windMph: weather.windMph,
            uvIndex: weather.uvIndex,
            condition: weather.condition,
            umbrellaAdvisory: advisory,
            confidence: 95
        ))
        XCTAssertEqual(styling.umbrellaGuidance, advisory.guidance(for: weather.condition))
        XCTAssertEqual(stylist?.message, advisory.guidance(for: weather.condition))
    }

    private func snapshot(
        condition: String,
        chance: Int,
        currentPrecipitationIntensityKilometersPerHour: Double? = nil,
        observedAt: Date = Date(),
        hourly: [WeatherHourlyForecastEntry] = []
    ) throws -> WeatherSnapshot {
        let attribution = try XCTUnwrap(WeatherAttributionMetadata(
            serviceName: "Apple Weather",
            combinedMarkLightURL: try XCTUnwrap(URL(string: "https://example.com/light")),
            combinedMarkDarkURL: try XCTUnwrap(URL(string: "https://example.com/dark")),
            legalPageURL: try XCTUnwrap(URL(string: "https://example.com/legal"))
        ))
        return try XCTUnwrap(WeatherSnapshot(
            observedAt: observedAt,
            locationName: "Fortson",
            temperatureFahrenheit: 85,
            feelsLikeFahrenheit: 85,
            condition: condition,
            currentPrecipitationIntensityKilometersPerHour: currentPrecipitationIntensityKilometersPerHour,
            rainChancePercent: chance,
            humidityPercent: 60,
            windMph: 5,
            uvIndex: 2,
            hourlySummary: nil,
            dailySummary: nil,
            hourlyForecast: hourly,
            attribution: attribution
        ))
    }

    private func advisory(_ snapshot: WeatherSnapshot) -> WeatherUmbrellaAdvisory {
        WeatherUmbrellaAdvisory.make(snapshot: snapshot, now: snapshot.observedAt)
    }
}
