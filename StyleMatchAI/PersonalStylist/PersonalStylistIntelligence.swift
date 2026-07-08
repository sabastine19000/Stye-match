import Foundation

struct PersonalStylistIntelligenceInput {
    let score: Int
    let scoreTier: String
    let scoreBreakdown: OutfitScoreBreakdown?
    let detectedGarments: [String]
    let colors: [String]
    let detectedStyle: String
    let occasion: String
    let weather: WeatherContextRecommendation?
    let memories: [OutfitMemory]
    let profile: StylistProfile
    let dealMatches: [PersonalStylistDealMatch]

    init(
        score: Int,
        scoreTier: String,
        scoreBreakdown: OutfitScoreBreakdown?,
        detectedGarments: [String],
        colors: [String],
        detectedStyle: String,
        occasion: String,
        weather: WeatherContextRecommendation?,
        memories: [OutfitMemory],
        profile: StylistProfile,
        dealMatches: [PersonalStylistDealMatch] = []
    ) {
        self.score = min(100, max(0, score))
        self.scoreTier = scoreTier
        self.scoreBreakdown = scoreBreakdown
        self.detectedGarments = detectedGarments
        self.colors = colors
        self.detectedStyle = detectedStyle
        self.occasion = occasion
        self.weather = weather
        self.memories = memories
        self.profile = profile
        self.dealMatches = dealMatches
    }
}

struct PersonalStylistMessage: Equatable {
    let sections: [PersonalStylistMessageSection]

    var isEmpty: Bool {
        sections.isEmpty
    }

    var plainText: String {
        sections
            .map { "\($0.title): \($0.body)" }
            .joined(separator: "\n")
    }
}

struct PersonalStylistMessageSection: Equatable {
    let title: String
    let body: String
    let source: PersonalStylistMessageSource
}

enum PersonalStylistMessageSource: String, Equatable {
    case score
    case history
    case weather
    case shoppingDeals
}

struct PersonalStylistPhrasingContext: Encodable, Equatable {
    let score: Int
    let scoreTier: String
    let scoreFacts: [String]
    let historyFacts: [String]
    let weatherFacts: [String]
    let dealFacts: [String]
    let allowedMessages: [String]
}

enum PersonalStylistIntelligenceBuilder {
    static func buildMessage(
        input: PersonalStylistIntelligenceInput,
        weatherAdviceEnabled: Bool = FeatureFlags.weatherAdviceEnabled,
        saleMatchingEnabled: Bool = FeatureFlags.saleMatchingEnabled
    ) -> PersonalStylistMessage {
        PersonalStylistMessage(
            sections: buildSections(
                input: input,
                weatherAdviceEnabled: weatherAdviceEnabled,
                saleMatchingEnabled: saleMatchingEnabled
            )
        )
    }

    static func buildPhrasingContext(
        input: PersonalStylistIntelligenceInput,
        weatherAdviceEnabled: Bool = FeatureFlags.weatherAdviceEnabled,
        saleMatchingEnabled: Bool = FeatureFlags.saleMatchingEnabled
    ) -> PersonalStylistPhrasingContext {
        let message = buildMessage(
            input: input,
            weatherAdviceEnabled: weatherAdviceEnabled,
            saleMatchingEnabled: saleMatchingEnabled
        )
        let sections = message.sections

        return PersonalStylistPhrasingContext(
            score: input.score,
            scoreTier: clean(input.scoreTier),
            scoreFacts: sourceBodies(in: sections, source: .score),
            historyFacts: sourceBodies(in: sections, source: .history),
            weatherFacts: sourceBodies(in: sections, source: .weather),
            dealFacts: sourceBodies(in: sections, source: .shoppingDeals),
            allowedMessages: sections.map { "\($0.title): \($0.body)" }
        )
    }

    private static func buildSections(
        input: PersonalStylistIntelligenceInput,
        weatherAdviceEnabled: Bool,
        saleMatchingEnabled: Bool
    ) -> [PersonalStylistMessageSection] {
        var sections: [PersonalStylistMessageSection] = []

        if let scoreSection = scoreEncouragementSection(input) {
            sections.append(scoreSection)
        }

        if let historySection = historyRecallSection(input) {
            sections.append(historySection)
        }

        if weatherAdviceEnabled, let weatherSection = weatherSection(input) {
            sections.append(weatherSection)
        }

        if saleMatchingEnabled, let dealSection = dealSection(input) {
            sections.append(dealSection)
        }

        return sections
    }

    private static func scoreEncouragementSection(_ input: PersonalStylistIntelligenceInput) -> PersonalStylistMessageSection? {
        StylistMessageComposer.scoreEncouragement(
            input: StylistScoreMessageInput(
                score: input.score,
                scoreTier: input.scoreTier,
                scoreBreakdown: input.scoreBreakdown,
                detectedGarments: input.detectedGarments,
                colors: input.colors
            )
        )
    }

    private static func historyRecallSection(_ input: PersonalStylistIntelligenceInput) -> PersonalStylistMessageSection? {
        let currentRecords = currentGarmentRecords(input)
        if let recall = OutfitRecallService.recallFact(
            for: OutfitRecallScanContext(
                detectedGarments: input.detectedGarments,
                colors: input.colors,
                detectedStyle: input.detectedStyle,
                garmentRecords: currentRecords
            ),
            memories: input.memories
        ) {
            return PersonalStylistMessageSection(
                title: "Style Memory",
                body: recall.text,
                source: .history
            )
        }
        return nil
    }

    private static func weatherSection(_ input: PersonalStylistIntelligenceInput) -> PersonalStylistMessageSection? {
        guard let weather = input.weather,
              weather.canGiveSpecificWeatherClothingAdvice,
              let effectiveTemperature = weather.effectiveTemperature else {
            return nil
        }

        let recommendation = clean(weather.recommendation)
        guard !recommendation.isEmpty else { return nil }

        let body = "Because the current feels-like temperature is \(effectiveTemperature)°F and severity is \(weather.severity.rawValue), \(recommendation.lowercased()) Why: \(clean(weather.rationale))"
        return PersonalStylistMessageSection(
            title: "Weather-Aware Advice",
            body: body,
            source: .weather
        )
    }

    private static func dealSection(_ input: PersonalStylistIntelligenceInput) -> PersonalStylistMessageSection? {
        guard let deal = input.dealMatches.first else {
            return nil
        }

        let fields = [
            clean(deal.productName),
            clean(deal.retailerName),
            clean(deal.salePrice),
            clean(deal.reason)
        ]
        guard fields.allSatisfy({ !$0.isEmpty }) else {
            return nil
        }

        return PersonalStylistMessageSection(
            title: "Deal Match",
            body: "\(deal.productName) at \(deal.retailerName) is \(deal.salePrice). \(deal.reason)",
            source: .shoppingDeals
        )
    }

    private static func currentGarmentRecords(_ input: PersonalStylistIntelligenceInput) -> [GarmentRecord] {
        let styleTags = [input.detectedStyle]
            .map(clean)
            .filter { !$0.isEmpty }
        return input.detectedGarments.enumerated().map { index, garment in
            let color = index < input.colors.count ? [input.colors[index]] : []
            return GarmentRecord(
                garmentCategory: GarmentRecordHelpers.category(from: garment),
                itemFingerprint: GarmentRecordHelpers.fingerprint(
                    category: garment,
                    colors: color,
                    pattern: nil,
                    fabric: nil,
                    brand: nil,
                    styleTags: styleTags
                ),
                colors: color,
                styleTags: styleTags,
                colorConfidence: color.isEmpty ? 35 : 70,
                sourceScanIds: []
            )
        }
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
