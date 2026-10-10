import XCTest
@testable import StyleMatchPro

final class WeatherConditionAnimationTests: XCTestCase {
    func testRainAndDrizzleMapToDistinctPrecipitationStates() throws {
        XCTAssertEqual(WeatherCurrentConditionVisualState.make(snapshot: try snapshot(condition: "Rain", intensity: 0.2), hasLiveWeather: true), .rain)
        XCTAssertEqual(WeatherCurrentConditionVisualState.make(snapshot: try snapshot(condition: "Drizzle", intensity: 0.05), hasLiveWeather: true), .drizzle)
    }

    func testThunderstormWithoutCurrentIntensityIsRiskNotRainAnimation() throws {
        let weather = try snapshot(condition: "Thunderstorms", chance: 3)
        XCTAssertEqual(WeatherCurrentConditionVisualState.make(snapshot: weather, hasLiveWeather: true), .thunderstormRisk)
        XCTAssertFalse(WeatherConditionAnimationPolicy.continuousMotionEnabled(for: .thunderstormRisk, reduceMotion: false))
        XCTAssertEqual(WeatherCurrentConditionVisualState.make(snapshot: try snapshot(condition: "Thunderstorms", chance: 3, intensity: 0.2), hasLiveWeather: true), .thunderstorm)
    }

    func testSnowAndDryConditionsDoNotProduceRainParticles() throws {
        XCTAssertEqual(WeatherCurrentConditionVisualState.make(snapshot: try snapshot(condition: "Snow"), hasLiveWeather: true), .snow)
        XCTAssertEqual(WeatherCurrentConditionVisualState.make(snapshot: try snapshot(condition: "Clear"), hasLiveWeather: true), .clear)
        XCTAssertEqual(WeatherCurrentConditionVisualState.make(snapshot: try snapshot(condition: "Cloudy"), hasLiveWeather: true), .cloudy)
    }

    func testReducedMotionDisablesContinuousAnimation() {
        XCTAssertFalse(WeatherConditionAnimationPolicy.continuousMotionEnabled(for: .thunderstorm, reduceMotion: true))
        XCTAssertTrue(WeatherConditionAnimationPolicy.continuousMotionEnabled(for: .rain, reduceMotion: false))
        XCTAssertFalse(WeatherConditionAnimationPolicy.continuousMotionEnabled(for: .clear, reduceMotion: false))
    }

    func testUnavailableOrSavedWeatherDoesNotAnimateAsCurrent() throws {
        XCTAssertEqual(WeatherCurrentConditionVisualState.make(snapshot: nil, hasLiveWeather: false), .none)
        XCTAssertEqual(WeatherCurrentConditionVisualState.make(snapshot: try snapshot(condition: "Rain"), hasLiveWeather: false), .none)
    }

    func testVisualStateAndUmbrellaAdvisoryShareCurrentWeatherAuthority() throws {
        let weather = try snapshot(condition: "Thunderstorms", chance: 3)
        XCTAssertEqual(WeatherUmbrellaAdvisory.make(snapshot: weather), .hazardousPrecipitation)
        XCTAssertEqual(WeatherCurrentConditionVisualState.make(snapshot: weather, hasLiveWeather: true), .thunderstormRisk)
    }

    private func snapshot(condition: String, chance: Int = 3, intensity: Double? = nil) throws -> WeatherSnapshot {
        let attribution = try XCTUnwrap(WeatherAttributionMetadata(
            serviceName: "Apple Weather",
            combinedMarkLightURL: try XCTUnwrap(URL(string: "https://example.com/light")),
            combinedMarkDarkURL: try XCTUnwrap(URL(string: "https://example.com/dark")),
            legalPageURL: try XCTUnwrap(URL(string: "https://example.com/legal"))
        ))
        return try XCTUnwrap(WeatherSnapshot(
            observedAt: Date(),
            locationName: "Fortson",
            temperatureFahrenheit: 70,
            feelsLikeFahrenheit: 70,
            condition: condition,
            currentPrecipitationIntensityKilometersPerHour: intensity,
            rainChancePercent: chance,
            humidityPercent: 60,
            windMph: 4,
            uvIndex: 2,
            hourlySummary: nil,
            dailySummary: nil,
            attribution: attribution
        ))
    }
}
