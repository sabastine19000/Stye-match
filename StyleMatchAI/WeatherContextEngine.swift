import Foundation

enum WeatherSeverity: String, Codable, CaseIterable {
    case extremeHeat = "Extreme Heat"
    case hot = "Hot"
    case warm = "Warm"
    case mild = "Mild"
    case cool = "Cool"
    case cold = "Cold"
    case freezing = "Freezing"
    case unknown = "Unknown"

    static func level(for temperature: Int?) -> WeatherSeverity {
        guard let temperature else { return .unknown }
        switch temperature {
        case 95...:
            return .extremeHeat
        case 80...94:
            return .hot
        case 70...79:
            return .warm
        case 60...69:
            return .mild
        case 50...59:
            return .cool
        case 35...49:
            return .cold
        default:
            return .freezing
        }
    }

    var isWarmOrHot: Bool {
        self == .warm || self == .hot || self == .extremeHeat
    }

    var isColdOrFreezing: Bool {
        self == .cold || self == .freezing
    }
}

enum WeatherActivity: String, Codable, CaseIterable {
    case walking = "Walking"
    case office = "Office"
    case gym = "Gym"
    case formalEvent = "Formal event"
    case outdoorEvent = "Outdoor event"
    case hiking = "Hiking"
    case beach = "Beach"
    case travel = "Travel"
    case general = "General"
}

enum WeatherRegionProfile: String, Codable {
    case hotHumid = "Hot humid"
    case coldWinter = "Cold winter"
    case dryHeat = "Dry heat"
    case coastal = "Coastal"
    case variable = "Variable"
}

struct WeatherContextSnapshot: Codable {
    let airTemperature: Int?
    let feelsLikeTemperature: Int?
    let humidityPercent: Int?
    let rainChancePercent: Int?
    let windMph: Int?
    let uvIndex: Int?
    let condition: String
    let locationText: String
    let activity: WeatherActivity
    let region: WeatherRegionProfile
    let season: String
    let timeOfDay: String
    let confidence: Int

    var effectiveTemperature: Int? {
        feelsLikeTemperature ?? airTemperature
    }

    var severity: WeatherSeverity {
        WeatherSeverity.level(for: effectiveTemperature)
    }

    var isNight: Bool {
        timeOfDay.localizedCaseInsensitiveContains("night")
            || timeOfDay.localizedCaseInsensitiveContains("evening")
    }

    var isIndoorActivity: Bool {
        activity == .office || activity == .gym || activity == .formalEvent
    }
}

struct WeatherContextRecommendation: Codable {
    let severity: WeatherSeverity
    let effectiveTemperature: Int?
    let canGiveSpecificWeatherClothingAdvice: Bool
    let recommendation: String
    let rationale: String
    let guardrail: String
    let regionalNote: String
}

enum WeatherContextEngine {
    static func recommendation(for snapshot: WeatherContextSnapshot) -> WeatherContextRecommendation {
        let severity = snapshot.severity
        let canGiveSpecificAdvice = snapshot.confidence >= 90 && severity != .unknown
        let regionalNote = regionalAdaptationNote(for: snapshot)

        guard canGiveSpecificAdvice else {
            return WeatherContextRecommendation(
                severity: severity,
                effectiveTemperature: snapshot.effectiveTemperature,
                canGiveSpecificWeatherClothingAdvice: false,
                recommendation: "Keep weather advice general until the current conditions are confirmed.",
                rationale: "Weather confidence is \(snapshot.confidence)%, so specific weather clothing recommendations should be avoided.",
                guardrail: "Do not recommend specific weather clothing because weather confidence is below 90%.",
                regionalNote: regionalNote
            )
        }

        let condition = snapshot.condition.lowercased()
        let rainActive = condition.contains("rain") || condition.contains("storm") || (snapshot.rainChancePercent ?? 0) >= 45
        let snowActive = condition.contains("snow") || condition.contains("sleet") || condition.contains("ice")
        let windy = condition.contains("wind") || (snapshot.windMph ?? 0) >= 18
        let highUV = (snapshot.uvIndex ?? 0) >= 7
        let activityNote = activityGuidance(for: snapshot)
        let rationale = rationaleText(for: snapshot, rainActive: rainActive, snowActive: snowActive, windy: windy, highUV: highUV)

        if snapshot.isNight && severity.isWarmOrHot {
            return WeatherContextRecommendation(
                severity: severity,
                effectiveTemperature: snapshot.effectiveTemperature,
                canGiveSpecificWeatherClothingAdvice: true,
                recommendation: warmWeatherRecommendation(snapshot: snapshot, rainActive: rainActive, highUV: highUV, activityNote: activityNote),
                rationale: "\(rationale) Nighttime alone is not enough reason to add a jacket while the feels-like temperature remains warm.",
                guardrail: "Do not recommend jackets solely because it is evening or nighttime.",
                regionalNote: regionalNote
            )
        }

        if snowActive || severity == .freezing {
            return WeatherContextRecommendation(
                severity: severity,
                effectiveTemperature: snapshot.effectiveTemperature,
                canGiveSpecificWeatherClothingAdvice: true,
                recommendation: "Use a warm coat, insulating layer, closed boots, and cold-weather accessories such as a scarf, gloves, or hat.",
                rationale: rationale,
                guardrail: "Cold-weather layers are appropriate because the effective temperature or snow risk supports them.",
                regionalNote: regionalNote
            )
        }

        if severity == .cold {
            return WeatherContextRecommendation(
                severity: severity,
                effectiveTemperature: snapshot.effectiveTemperature,
                canGiveSpecificWeatherClothingAdvice: true,
                recommendation: "Use a jacket or coat, closed shoes or boots, and a practical layer that can handle the activity.",
                rationale: rationale,
                guardrail: "Jackets are appropriate at this severity when balanced with activity and occasion.",
                regionalNote: regionalNote
            )
        }

        if severity.isWarmOrHot {
            return WeatherContextRecommendation(
                severity: severity,
                effectiveTemperature: snapshot.effectiveTemperature,
                canGiveSpecificWeatherClothingAdvice: true,
                recommendation: warmWeatherRecommendation(snapshot: snapshot, rainActive: rainActive, highUV: highUV, activityNote: activityNote),
                rationale: rationale,
                guardrail: "Avoid jackets, blazers, coats, sweaters, shackets, structured layers, and heavy layers unless the user explicitly asks.",
                regionalNote: regionalNote
            )
        }

        if severity == .cool || windy {
            return WeatherContextRecommendation(
                severity: severity,
                effectiveTemperature: snapshot.effectiveTemperature,
                canGiveSpecificWeatherClothingAdvice: true,
                recommendation: windy
                    ? "Use a breathable wind-resistant layer or closed shoes if you will be outside, while keeping the outfit easy to remove indoors."
                    : "Use light layers only if the activity keeps you outside for a while; keep indoor outfits breathable and removable.",
                rationale: rationale,
                guardrail: "Layering is optional and should be removable, especially for indoor events.",
                regionalNote: regionalNote
            )
        }

        return WeatherContextRecommendation(
            severity: severity,
            effectiveTemperature: snapshot.effectiveTemperature,
            canGiveSpecificWeatherClothingAdvice: true,
            recommendation: rainActive
                ? "Use water-friendly shoes and an umbrella or compact rain shell if you will be outside."
                : "Keep the outfit comfortable and occasion-appropriate; weather does not require a major clothing change.",
            rationale: rationale,
            guardrail: "Avoid adding layers solely because of time of day.",
            regionalNote: regionalNote
        )
    }

    static func inferActivity(occasion: String, environment: String) -> WeatherActivity {
        let text = "\(occasion) \(environment)".lowercased()
        if text.contains("hiking") || text.contains("trail") { return .hiking }
        if text.contains("beach") || text.contains("swim") { return .beach }
        if text.contains("gym") || text.contains("fitness") || text.contains("workout") { return .gym }
        if text.contains("travel") || text.contains("airport") || text.contains("flight") { return .travel }
        if text.contains("office") || text.contains("work") || text.contains("business") { return .office }
        if text.contains("wedding") || text.contains("formal") || text.contains("funeral") || text.contains("interview") { return .formalEvent }
        if text.contains("outdoor") || text.contains("park") || text.contains("street") { return .outdoorEvent }
        if text.contains("walking") || text.contains("walk") { return .walking }
        return .general
    }

    static func inferRegion(locationText: String) -> WeatherRegionProfile {
        let text = locationText.lowercased()
        if text.contains("florida") || text.contains(" miami") || text.contains("orlando") || text.contains("tampa") || text.contains("jacksonville") {
            return .hotHumid
        }
        if text.contains("minnesota") || text.contains(" minneapolis") || text.contains("saint paul") || text.contains("st. paul") {
            return .coldWinter
        }
        if text.contains("arizona") || text.contains("phoenix") || text.contains("nevada") || text.contains("las vegas") {
            return .dryHeat
        }
        if text.contains("california") || text.contains("los angeles") || text.contains("san diego") || text.contains("bay area") {
            return .coastal
        }
        return .variable
    }

    private static func warmWeatherRecommendation(
        snapshot: WeatherContextSnapshot,
        rainActive: Bool,
        highUV: Bool,
        activityNote: String
    ) -> String {
        var parts = [
            snapshot.severity == .extremeHeat
                ? "Prioritize moisture-wicking or linen/cotton pieces, short sleeves, breathable shoes, and minimal layers."
                : "Use lightweight cotton, linen, breathable shoes, and minimal layers."
        ]
        if rainActive {
            parts.append("For rain, use water-friendly shoes and an umbrella instead of outerwear when it still feels warm.")
        }
        if highUV {
            parts.append("Add sunglasses, a hat, or UPF-friendly coverage for high UV.")
        }
        if !activityNote.isEmpty {
            parts.append(activityNote)
        }
        return parts.joined(separator: " ")
    }

    private static func activityGuidance(for snapshot: WeatherContextSnapshot) -> String {
        switch snapshot.activity {
        case .walking:
            return "For walking, prioritize breathable shoes and sweat-friendly fabrics."
        case .office:
            return "For office wear, use lightweight polish such as a crisp shirt, belt, watch, and breathable trousers."
        case .gym:
            return "For gym activity, prioritize performance fabric and supportive footwear."
        case .formalEvent:
            return "For a formal event, keep polish through fabric quality, fit, shoes, and accessories rather than extra coverage in heat."
        case .outdoorEvent:
            return "For an outdoor event, add sun or rain accessories based on exposure."
        case .hiking:
            return "For hiking, prioritize traction, moisture management, sun protection, and packable weather protection."
        case .beach:
            return "For beach plans, prioritize breathable fabrics, sandals or water-friendly shoes, hat, and sunglasses."
        case .travel:
            return "For travel, use breathable layers only if they are easy to remove and repeat."
        case .general:
            return ""
        }
    }

    private static func rationaleText(
        for snapshot: WeatherContextSnapshot,
        rainActive: Bool,
        snowActive: Bool,
        windy: Bool,
        highUV: Bool
    ) -> String {
        var facts: [String] = []
        if let feelsLike = snapshot.feelsLikeTemperature {
            facts.append("feels-like temperature is \(feelsLike)°F")
        } else if let airTemperature = snapshot.airTemperature {
            facts.append("temperature is \(airTemperature)°F")
        }
        if let humidity = snapshot.humidityPercent {
            facts.append("humidity is \(humidity)%")
        }
        if rainActive {
            facts.append("rain risk is present")
        }
        if snowActive {
            facts.append("snow or ice risk is present")
        }
        if windy, let wind = snapshot.windMph {
            facts.append("wind is \(wind) mph")
        }
        if highUV, let uvIndex = snapshot.uvIndex {
            facts.append("UV index is \(uvIndex)")
        }
        facts.append("activity is \(snapshot.activity.rawValue.lowercased())")
        facts.append("region profile is \(snapshot.region.rawValue.lowercased())")
        return "Recommendation is based on \(facts.joined(separator: ", "))."
    }

    private static func regionalAdaptationNote(for snapshot: WeatherContextSnapshot) -> String {
        switch snapshot.region {
        case .hotHumid:
            return "Regional adaptation: hot-humid regions need airflow and sweat management earlier than dry or northern regions."
        case .coldWinter:
            return "Regional adaptation: cold-winter regions may tolerate cool weather better, but freezing conditions still need serious insulation."
        case .dryHeat:
            return "Regional adaptation: dry-heat regions need sun protection, hydration-friendly fabrics, and breathable coverage."
        case .coastal:
            return "Regional adaptation: coastal weather can shift with wind, fog, or evening marine air, so removable layers may help when it is not warm."
        case .variable:
            return "Regional adaptation: use the current feels-like temperature and activity as the strongest signals."
        }
    }
}
