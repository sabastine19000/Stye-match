import Foundation
#if canImport(CoreLocation)
import CoreLocation
#endif
#if canImport(WeatherKit)
import WeatherKit
#endif

struct WeatherAdvisorInput: Equatable {
    let feelsLikeTemperature: Int?
    let humidityPercent: Int?
    let rainChancePercent: Int?
    let windMph: Int?
    let uvIndex: Int?
    let condition: String
    let confidence: Int
    let detectedGarments: [String]
    let activity: WeatherActivity?
    let citySummary: String?

    init(
        feelsLikeTemperature: Int?,
        humidityPercent: Int?,
        rainChancePercent: Int?,
        windMph: Int?,
        uvIndex: Int?,
        condition: String,
        confidence: Int,
        detectedGarments: [String] = [],
        activity: WeatherActivity? = nil,
        citySummary: String? = nil
    ) {
        self.feelsLikeTemperature = feelsLikeTemperature
        self.humidityPercent = humidityPercent
        self.rainChancePercent = rainChancePercent
        self.windMph = windMph
        self.uvIndex = uvIndex
        self.condition = condition
        self.confidence = confidence
        self.detectedGarments = detectedGarments
        self.activity = activity
        self.citySummary = citySummary
    }
}

struct WeatherAdvisorAdvice: Equatable {
    let message: String
    let reason: String
}

struct WeatherAdvisorRule {
    let name: String
    let matches: (WeatherAdvisorInput) -> Bool
    let advice: (WeatherAdvisorInput) -> WeatherAdvisorAdvice
}

enum WeatherAdvisor {
    static let rules: [WeatherAdvisorRule] = [
        WeatherAdvisorRule(
            name: "low confidence",
            matches: { $0.confidence < 90 },
            advice: { _ in WeatherAdvisorAdvice(message: "", reason: "Weather confidence below 90%; omit weather advice.") }
        ),
        WeatherAdvisorRule(
            name: "hot with heavy layer",
            matches: { input in (input.feelsLikeTemperature ?? -100) >= 80 && containsHeavyLayer(input.detectedGarments) },
            advice: { input in
                WeatherAdvisorAdvice(
                    message: "It'll feel like \(input.feelsLikeTemperature ?? 0)°F today, so you may want to skip the jacket or heavy layer.",
                    reason: "The feels-like temperature is \(input.feelsLikeTemperature ?? 0)°F and the scanned outfit includes \(heavyLayerDescription(input.detectedGarments))."
                )
            }
        ),
        WeatherAdvisorRule(
            name: "hot",
            matches: { input in (input.feelsLikeTemperature ?? -100) >= 80 },
            advice: { input in
                WeatherAdvisorAdvice(
                    message: "Keep this breathable and avoid jackets, extra layers, or heavy fabrics today.",
                    reason: hotReason(input)
                )
            }
        ),
        WeatherAdvisorRule(
            name: "rain likely",
            matches: { ($0.rainChancePercent ?? 0) >= 50 },
            advice: { input in
                let vulnerable = vulnerableMaterialDescription(input.detectedGarments)
                return WeatherAdvisorAdvice(
                    message: vulnerable == nil
                        ? "There is a \(input.rainChancePercent ?? 0)% chance of rain today. Grab an umbrella before going out."
                        : "There is a \(input.rainChancePercent ?? 0)% chance of rain today. Grab an umbrella, and be careful with \(vulnerable ?? "rain-sensitive items").",
                    reason: vulnerable == nil
                        ? "Rain probability is \(input.rainChancePercent ?? 0)%."
                        : "Rain probability is \(input.rainChancePercent ?? 0)% and the scanned outfit includes \(vulnerable ?? "rain-sensitive items")."
                )
            }
        ),
        WeatherAdvisorRule(
            name: "possible showers rain vulnerable",
            matches: { input in
                let rain = input.rainChancePercent ?? 0
                return (30...49).contains(rain) && vulnerableMaterialDescription(input.detectedGarments) != nil
            },
            advice: { input in
                WeatherAdvisorAdvice(
                    message: "Possible showers are in the forecast at \(input.rainChancePercent ?? 0)%, so protect \(vulnerableMaterialDescription(input.detectedGarments) ?? "rain-sensitive items").",
                    reason: "Rain probability is \(input.rainChancePercent ?? 0)% and the scanned outfit includes \(vulnerableMaterialDescription(input.detectedGarments) ?? "rain-sensitive items")."
                )
            }
        ),
        WeatherAdvisorRule(
            name: "cold lacks outerwear",
            matches: { input in (input.feelsLikeTemperature ?? 100) <= 41 && !containsOuterwear(input.detectedGarments) },
            advice: { input in
                WeatherAdvisorAdvice(
                    message: "It'll feel like \(input.feelsLikeTemperature ?? 0)°F today, so add a warm outer layer.",
                    reason: "Feels-like temperature is \(input.feelsLikeTemperature ?? 0)°F and no outerwear was detected in the scanned outfit."
                )
            }
        ),
        WeatherAdvisorRule(
            name: "neutral heavy mismatch",
            matches: { input in
                guard let temp = input.feelsLikeTemperature else { return false }
                return (59...79).contains(temp) && containsHeavyCoat(input.detectedGarments)
            },
            advice: { input in
                WeatherAdvisorAdvice(
                    message: "It'll feel like \(input.feelsLikeTemperature ?? 0)°F today, so the heavy coat may feel too warm.",
                    reason: "Feels-like temperature is \(input.feelsLikeTemperature ?? 0)°F and the scanned outfit includes \(heavyLayerDescription(input.detectedGarments))."
                )
            }
        ),
        WeatherAdvisorRule(
            name: "wind loose garments",
            matches: { input in
                guard let wind = input.windMph else { return false }
                return wind >= 25 && containsLooseOrFlowyGarment(input.detectedGarments)
            },
            advice: { input in
                WeatherAdvisorAdvice(
                    message: "Wind is \(input.windMph ?? 0) mph today, so secure loose or flowy pieces.",
                    reason: "Wind is \(input.windMph ?? 0) mph and the scanned outfit includes \(looseGarmentDescription(input.detectedGarments))."
                )
            }
        ),
        WeatherAdvisorRule(
            name: "high uv outdoor casual",
            matches: { input in
                (input.uvIndex ?? 0) >= 8 && isOutdoorLookingCasual(input)
            },
            advice: { input in
                WeatherAdvisorAdvice(
                    message: "UV index is \(input.uvIndex ?? 0), so add brief sun protection like sunglasses or a hat.",
                    reason: "UV index is \(input.uvIndex ?? 0) and the outfit context looks casual or outdoor."
                )
            }
        )
    ]

    static func advice(for input: WeatherAdvisorInput) -> WeatherAdvisorAdvice? {
        for rule in rules where rule.matches(input) {
            let advice = rule.advice(input)
            return advice.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : advice
        }
        return nil
    }

    #if canImport(CoreLocation)
    static func requestWhenInUseLocationPermission() {
        WeatherAdvisorLocationPermission.shared.requestWhenInUse()
    }
    #endif

    #if canImport(WeatherKit) && canImport(CoreLocation)
    @available(iOS 16.0, macOS 13.0, *)
    static func fetchAdvice(for location: CLLocation) async -> WeatherAdvisorAdvice? {
        do {
            let weather = try await WeatherService.shared.weather(for: location)
            let current = weather.currentWeather
            let input = WeatherAdvisorInput(
                feelsLikeTemperature: Int(current.apparentTemperature.converted(to: .fahrenheit).value.rounded()),
                humidityPercent: Int((current.humidity * 100).rounded()),
                rainChancePercent: nil,
                windMph: Int(current.wind.speed.converted(to: .milesPerHour).value.rounded()),
                uvIndex: current.uvIndex.value,
                condition: current.condition.description,
                confidence: 95
            )
            return advice(for: input)
        } catch {
            return nil
        }
    }
    #endif
}

#if canImport(CoreLocation)
private final class WeatherAdvisorLocationPermission: NSObject, CLLocationManagerDelegate {
    static let shared = WeatherAdvisorLocationPermission()
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
    }

    func requestWhenInUse() {
        manager.requestWhenInUseAuthorization()
    }
}
#endif

private extension WeatherAdvisor {
    static func containsHeavyLayer(_ garments: [String]) -> Bool {
        garments.contains { garment in
            let value = garment.lowercased()
            return ["jacket", "blazer", "coat", "sweater", "hoodie", "wool", "fleece", "heavy layer", "shacket"].contains { value.contains($0) }
        }
    }

    static func containsHeavyCoat(_ garments: [String]) -> Bool {
        garments.contains { garment in
            let value = garment.lowercased()
            return ["heavy coat", "winter coat", "parka", "puffer", "wool coat"].contains { value.contains($0) }
        }
    }

    static func containsOuterwear(_ garments: [String]) -> Bool {
        garments.contains { garment in
            let value = garment.lowercased()
            return ["jacket", "coat", "parka", "puffer", "outerwear", "blazer"].contains { value.contains($0) }
        }
    }

    static func containsLooseOrFlowyGarment(_ garments: [String]) -> Bool {
        garments.contains { garment in
            let value = garment.lowercased()
            return ["loose", "flowy", "wide-leg", "wide leg", "skirt", "dress", "scarf", "kimono", "oversized"].contains { value.contains($0) }
        }
    }

    static func vulnerableMaterialDescription(_ garments: [String]) -> String? {
        let vulnerable = garments.first { garment in
            let value = garment.lowercased()
            return ["suede", "leather", "canvas"].contains { value.contains($0) }
        }
        return vulnerable?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func heavyLayerDescription(_ garments: [String]) -> String {
        garments.first { garment in
            let value = garment.lowercased()
            return ["jacket", "blazer", "coat", "sweater", "hoodie", "wool", "fleece", "heavy layer", "shacket"].contains { value.contains($0) }
        } ?? "a heavy layer"
    }

    static func looseGarmentDescription(_ garments: [String]) -> String {
        garments.first { garment in
            let value = garment.lowercased()
            return ["loose", "flowy", "wide-leg", "wide leg", "skirt", "dress", "scarf", "kimono", "oversized"].contains { value.contains($0) }
        } ?? "loose or flowy pieces"
    }

    static func isOutdoorLookingCasual(_ input: WeatherAdvisorInput) -> Bool {
        if let activity = input.activity {
            return [.walking, .outdoorEvent, .hiking, .beach, .travel, .general].contains(activity)
        }

        let text = input.detectedGarments.joined(separator: " ").lowercased()
        return ["t-shirt", "tee", "shorts", "sneaker", "sandals", "casual", "polo"].contains { text.contains($0) }
    }

    static func hotReason(_ input: WeatherAdvisorInput) -> String {
        var parts = ["Feels-like temperature is \(input.feelsLikeTemperature ?? 0)°F."]
        if let humidity = input.humidityPercent {
            parts.append("Humidity is \(humidity)%.")
        }
        return parts.joined(separator: " ")
    }
}
