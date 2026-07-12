import Foundation

struct PersonalStylistEngineInput {
    let score: Int
    let scoreTier: String
    let scoreBreakdown: OutfitScoreBreakdown?
    let detectedGarments: [String]
    let detectedItemConfidences: [DetectedItemConfidence]
    let colors: [String]
    let detectedStyle: String
    let occasion: String
    let weather: WeatherAdvisorAdvice?
    let legacyWeather: WeatherContextRecommendation?
    let memories: [OutfitMemory]
    let profile: StylistProfile
    let dealMatches: [PersonalStylistDealMatch]
    let outfitFingerprint: String?
    let imageDigest: String?

    init(
        score: Int,
        scoreTier: String,
        scoreBreakdown: OutfitScoreBreakdown?,
        detectedGarments: [String],
        detectedItemConfidences: [DetectedItemConfidence] = [],
        colors: [String],
        detectedStyle: String,
        occasion: String,
        weather: WeatherAdvisorAdvice? = nil,
        legacyWeather: WeatherContextRecommendation? = nil,
        memories: [OutfitMemory],
        profile: StylistProfile,
        dealMatches: [PersonalStylistDealMatch] = [],
        outfitFingerprint: String? = nil,
        imageDigest: String? = nil
    ) {
        self.score = score
        self.scoreTier = scoreTier
        self.scoreBreakdown = scoreBreakdown
        self.detectedGarments = detectedGarments
        self.detectedItemConfidences = detectedItemConfidences
        self.colors = colors
        self.detectedStyle = detectedStyle
        self.occasion = occasion
        self.weather = weather
        self.legacyWeather = legacyWeather
        self.memories = memories
        self.profile = profile
        self.dealMatches = dealMatches
        self.outfitFingerprint = outfitFingerprint
        self.imageDigest = imageDigest
    }
}

struct PersonalStylistEngineContext: Encodable, Equatable {
    let score: Int
    let scoreTier: String
    let scoreFacts: [String]
    let historyFacts: [String]
    let weatherFacts: [String]
    let dealFacts: [String]
    let allowedMessages: [String]
    let systemGuardrails: [String]
}

enum PersonalStylistEngine {
    static let systemGuardrails = [
        "You may only reference facts explicitly provided in the context object.",
        "Do not invent weather conditions, garments, colors, dates, prices, or deals.",
        "Do not modify or reinterpret the score.",
        "Keep the message under 4 sentences, warm and specific."
    ]

    static func compose(
        input: PersonalStylistEngineInput,
        weatherAdviceEnabled: Bool = FeatureFlags.weatherAdviceEnabled,
        saleMatchingEnabled: Bool = FeatureFlags.saleMatchingEnabled
    ) -> PersonalStylistMessage {
        PersonalStylistMessage(sections: sections(
            input: input,
            weatherAdviceEnabled: weatherAdviceEnabled,
            saleMatchingEnabled: saleMatchingEnabled
        ))
    }

    static func context(
        input: PersonalStylistEngineInput,
        weatherAdviceEnabled: Bool = FeatureFlags.weatherAdviceEnabled,
        saleMatchingEnabled: Bool = FeatureFlags.saleMatchingEnabled
    ) -> PersonalStylistEngineContext {
        let message = compose(
            input: input,
            weatherAdviceEnabled: weatherAdviceEnabled,
            saleMatchingEnabled: saleMatchingEnabled
        )

        return PersonalStylistEngineContext(
            score: min(100, max(0, input.score)),
            scoreTier: clean(input.scoreTier),
            scoreFacts: sourceBodies(in: message.sections, source: .score),
            historyFacts: sourceBodies(in: message.sections, source: .history),
            weatherFacts: sourceBodies(in: message.sections, source: .weather),
            dealFacts: sourceBodies(in: message.sections, source: .shoppingDeals),
            allowedMessages: message.sections.map { "\($0.title): \($0.body)" },
            systemGuardrails: systemGuardrails
        )
    }

    static func deterministicFallbackText(
        input: PersonalStylistEngineInput,
        weatherAdviceEnabled: Bool = FeatureFlags.weatherAdviceEnabled,
        saleMatchingEnabled: Bool = FeatureFlags.saleMatchingEnabled
    ) -> String {
        compose(
            input: input,
            weatherAdviceEnabled: weatherAdviceEnabled,
            saleMatchingEnabled: saleMatchingEnabled
        )
        .sections
        .map(\.body)
        .joined(separator: " ")
    }

    private static func sections(
        input: PersonalStylistEngineInput,
        weatherAdviceEnabled: Bool,
        saleMatchingEnabled: Bool
    ) -> [PersonalStylistMessageSection] {
        let intelligenceInput = PersonalStylistIntelligenceInput(
            score: input.score,
            scoreTier: input.scoreTier,
            scoreBreakdown: input.scoreBreakdown,
            detectedGarments: input.detectedGarments,
            detectedItemConfidences: input.detectedItemConfidences,
            colors: input.colors,
            detectedStyle: input.detectedStyle,
            occasion: input.occasion,
            weather: input.legacyWeather,
            memories: input.memories,
            profile: input.profile,
            dealMatches: input.dealMatches,
            outfitFingerprint: input.outfitFingerprint,
            imageDigest: input.imageDigest
        )

        var sections = PersonalStylistIntelligenceBuilder.buildMessage(
            input: intelligenceInput,
            weatherAdviceEnabled: false,
            saleMatchingEnabled: saleMatchingEnabled
        ).sections

        if weatherAdviceEnabled, let weather = input.weather {
            sections.append(PersonalStylistMessageSection(
                title: "Weather-Aware Advice",
                body: "\(weather.message) Why: \(weather.reason)",
                source: .weather
            ))
        } else if weatherAdviceEnabled, input.weather == nil, input.legacyWeather != nil {
            let legacySection = PersonalStylistIntelligenceBuilder.buildMessage(
                input: intelligenceInput,
                weatherAdviceEnabled: true,
                saleMatchingEnabled: false
            ).sections.first { $0.source == .weather }
            if let legacySection {
                sections.append(legacySection)
            }
        }

        return sections
    }

    private static func sourceBodies(
        in sections: [PersonalStylistMessageSection],
        source: PersonalStylistMessageSource
    ) -> [String] {
        sections
            .filter { $0.source == source }
            .map(\.body)
    }

    private static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
