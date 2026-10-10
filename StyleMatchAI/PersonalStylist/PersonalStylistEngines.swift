import Foundation

struct FeatureFlags {
    static var saleMatchingEnabled = false
    static var weatherAdviceEnabled = true
    static var shoppingTabEnabled = true
    static var remoteCatalogEnabled = true
    static var liveSearchEnabled = false
    static var saleNotificationsEnabled = false
    static var pushNotificationsEnabled = false
    static var remoteSyncEnabled = false
    static var conversationalStylist = true
    static var alternateAIProvidersEnabled = false
}

enum DeprecatedAIAssistantPreferenceRepair {
    static let preferredKey = "preferredAIAssistant"
    static let connectedKey = "connectedAIAssistants"

    static func run(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: preferredKey)
        defaults.removeObject(forKey: connectedKey)
    }
}

extension StylistProfile {
    var topPreferences: TopStylePreferences {
        let positive = stylePreferencesLearned
            .filter { $0.value > 0 }
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }

        func values(prefix: String) -> [String] {
            positive
                .compactMap { key, _ in
                    key.hasPrefix(prefix) ? String(key.dropFirst(prefix.count)) : nil
                }
                .prefix(5)
                .map { $0 }
        }

        return TopStylePreferences(
            colors: values(prefix: "color:"),
            categories: values(prefix: "category:"),
            styleTags: values(prefix: "style:")
        )
    }
}

enum GarmentRecordHelpers {
    static func category(from text: String) -> String {
        let lower = text.lowercased()
        if containsAny(lower, ["pant", "jean", "trouser", "chino"]) { return "pants" }
        if containsAny(lower, ["shirt", "top", "tee", "polo", "blouse", "hoodie", "sweater"]) { return "shirt" }
        if containsAny(lower, ["shoe", "sneaker", "loafer", "boot", "slipper"]) { return "shoes" }
        if containsAny(lower, ["jacket", "coat", "blazer", "shacket", "flannel"]) { return "jacket" }
        if containsAny(lower, ["belt", "watch", "hat", "bag", "accessory"]) { return "accessory" }
        if containsAny(lower, ["dress", "gown"]) { return "dress" }
        return "item"
    }

    static func fingerprint(
        category: String,
        colors: [String],
        pattern: String?,
        fabric: String?,
        brand: String?,
        styleTags: [String]
    ) -> String {
        [
            "category:\(normalized(category))",
            "colors:\(colors.map(normalized).sorted().prefix(3).joined(separator: "."))",
            "pattern:\(normalized(pattern ?? "solid"))",
            "fabric:\(normalized(fabric ?? "unknown"))",
            "brand:\(normalized(brand ?? "unknown"))"
        ].joined(separator: "|")
    }

    static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    static func containsAny(_ value: String, _ terms: [String]) -> Bool {
        terms.contains { value.contains($0) }
    }
}

struct ItemFingerprintMatcher {
    static func records(
        from analysis: OutfitAnalysisResult,
        scanID: String,
        scanDate: Date = Date()
    ) -> [GarmentRecord] {
        let garments = analysis.safeDetectedClothingItems
        guard !garments.isEmpty else { return [] }
        let colors = analysis.colorPalette
        let styleTags = [analysis.styleBalance, analysis.formality]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return garments.enumerated().map { index, garment in
            let category = GarmentRecordHelpers.category(from: garment)
            let itemColors = colorsForGarment(colors: colors, index: index)
            let pattern = inferredPattern(from: analysis, garment: garment)
            let fabric = inferredFabric(from: analysis, garment: garment)
            let fingerprint = GarmentRecordHelpers.fingerprint(
                category: category,
                colors: itemColors,
                pattern: pattern,
                fabric: fabric,
                brand: nil,
                styleTags: styleTags
            )

            return GarmentRecord(
                garmentCategory: category,
                itemFingerprint: fingerprint,
                fit: analysis.suggestions.first { $0.localizedCaseInsensitiveContains("fit") },
                fabric: fabric,
                pattern: pattern,
                colors: itemColors,
                styleTags: styleTags,
                colorConfidence: itemColors.isEmpty ? 40 : 78,
                timesSeen: 1,
                timesWorn: 0,
                sourceScanIds: [scanID],
                firstSeenAt: scanDate,
                lastSeenAt: scanDate
            )
        }
    }

    static func match(_ candidate: GarmentRecord, in existing: [GarmentRecord]) -> GarmentRecord? {
        existing.first { $0.itemFingerprint == candidate.itemFingerprint }
    }

    private static func colorsForGarment(colors: [String], index: Int) -> [String] {
        guard !colors.isEmpty else { return [] }
        return [colors[min(index, colors.count - 1)]]
    }

    private static func inferredPattern(from analysis: OutfitAnalysisResult, garment: String) -> String? {
        let evidence = ([garment, analysis.summary, analysis.outfitDescription] + analysis.suggestions).joined(separator: " ").lowercased()
        if GarmentRecordHelpers.containsAny(evidence, ["plaid", "checkered", "flannel"]) { return "plaid" }
        if evidence.contains("stripe") { return "striped" }
        if GarmentRecordHelpers.containsAny(evidence, ["graphic", "logo", "print"]) { return "graphic" }
        if evidence.contains("pattern") { return "patterned" }
        return "solid"
    }

    private static func inferredFabric(from analysis: OutfitAnalysisResult, garment: String) -> String? {
        let evidence = ([garment, analysis.summary, analysis.outfitDescription] + analysis.suggestions).joined(separator: " ").lowercased()
        if evidence.contains("denim") { return "denim" }
        if GarmentRecordHelpers.containsAny(evidence, ["fleece", "plush"]) { return "fleece" }
        if evidence.contains("leather") { return "leather" }
        if evidence.contains("cotton") { return "cotton" }
        if evidence.contains("flannel") { return "flannel" }
        return nil
    }
}

struct StyleFrequencyAnalyzer {
    static func topPreferences(from records: [GarmentRecord]) -> TopStylePreferences {
        TopStylePreferences(
            colors: ranked(records.flatMap(\.colors), weights: records.flatMap { record in
                Array(repeating: max(record.timesWorn, record.timesSeen), count: record.colors.count)
            }),
            categories: ranked(records.map(\.garmentCategory), weights: records.map { max($0.timesWorn, $0.timesSeen) }),
            styleTags: ranked(records.flatMap(\.styleTags), weights: records.flatMap { record in
                Array(repeating: max(record.timesWorn, record.timesSeen), count: record.styleTags.count)
            })
        )
    }

    private static func ranked(_ values: [String], weights: [Int]) -> [String] {
        var counts: [String: Int] = [:]
        for (index, value) in values.enumerated() {
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }
            counts[cleaned, default: 0] += max(1, index < weights.count ? weights[index] : 1)
        }
        return counts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .prefix(5)
            .map(\.key)
    }
}

struct HistorySuggestion: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let detail: String
    let relatedPieces: [String]
}

enum ColorPairingRules {
    static func complementaryColors(for color: String?) -> Set<String> {
        let base = color?.lowercased() ?? "neutral"
        if ["black", "charcoal", "navy"].contains(base) {
            return ["white", "cream", "gray", "grey", "tan", "beige", "blue"]
        }
        if ["tan", "beige", "khaki", "brown"].contains(base) {
            return ["white", "navy", "black", "olive", "blue"]
        }
        if ["white", "cream"].contains(base) {
            return ["black", "navy", "denim", "brown", "gray", "grey"]
        }
        return ["black", "white", "navy", "gray", "grey", "tan"]
    }
}

enum CategoryPairingRules {
    static func complementaryCategories(for category: String) -> [String] {
        switch category {
        case "pants": return ["shirt", "shoes", "belt", "jacket"]
        case "shirt": return ["pants", "shoes", "jacket"]
        case "jacket": return ["shirt", "pants", "shoes"]
        case "shoes": return ["pants", "shirt"]
        default: return ["shirt", "pants", "shoes"]
        }
    }
}

struct HistorySuggestionEngine {
    static func suggestions(from records: [GarmentRecord], topPreferences: TopStylePreferences, limit: Int = 4) -> [HistorySuggestion] {
        let sortedRecords = records.sorted { lhs, rhs in
            if lhs.timesWorn == rhs.timesWorn {
                return lhs.lastSeenAt > rhs.lastSeenAt
            }
            return lhs.timesWorn > rhs.timesWorn
        }

        let pants = sortedRecords.first { $0.garmentCategory == "pants" }
        let shirt = sortedRecords.first { $0.garmentCategory == "shirt" }
        let shoes = sortedRecords.first { $0.garmentCategory == "shoes" }
        var suggestions: [HistorySuggestion] = []

        if let shirt, let pants {
            suggestions.append(HistorySuggestion(
                title: "Wear \(display(shirt)) with \(display(pants)) again",
                detail: "This is based on pieces KigoStylist has seen in your history.",
                relatedPieces: [display(shirt), display(pants)] + [shoes.map(display)].compactMap { $0 }
            ))
        }

        if let favoriteColor = topPreferences.colors.first {
            let pieces = sortedRecords
                .filter { $0.colors.contains(where: { $0.caseInsensitiveCompare(favoriteColor) == .orderedSame }) }
                .prefix(3)
                .map(display)
            if !pieces.isEmpty {
                suggestions.append(HistorySuggestion(
                    title: "Build around \(favoriteColor)",
                    detail: "You wear \(favoriteColor.lowercased()) and similar tones most often.",
                    relatedPieces: Array(pieces)
                ))
            }
        }

        return Array(suggestions.prefix(limit))
    }

    static func display(_ record: GarmentRecord) -> String {
        let color = record.colors.first.map { "\($0) " } ?? ""
        return "\(color)\(record.garmentCategory)"
    }
}

struct ComplementaryPieceRecommender {
    static func recommendations(for garment: GarmentRecord, ownedRecords: [GarmentRecord], limit: Int = 4) -> [HistorySuggestion] {
        let targetCategories = complementaryCategories(for: garment.garmentCategory)
        let targetColors = ColorPairingRules.complementaryColors(for: garment.colors.first)
        let ownedMatches = ownedRecords.filter { record in
            targetCategories.contains(record.garmentCategory)
                && (record.colors.isEmpty || !Set(record.colors.map { $0.lowercased() }).isDisjoint(with: targetColors))
        }

        if !ownedMatches.isEmpty {
            return ownedMatches.prefix(limit).map { match in
                let date = DateFormatter.localizedString(from: match.lastSeenAt, dateStyle: .medium, timeStyle: .none)
                return HistorySuggestion(
                    title: "\(HistorySuggestionEngine.display(garment)) pairs with \(HistorySuggestionEngine.display(match))",
                    detail: "You scanned this \(match.garmentCategory) on \(date).",
                    relatedPieces: [HistorySuggestionEngine.display(garment), HistorySuggestionEngine.display(match)]
                )
            }
        }

        return targetCategories.prefix(limit).map { category in
            HistorySuggestion(
                title: "Add a \(targetColors.first ?? "neutral") \(category)",
                detail: "This would complement \(HistorySuggestionEngine.display(garment)) based on KigoStylist's color rules.",
                relatedPieces: [HistorySuggestionEngine.display(garment), "\(targetColors.first ?? "neutral") \(category)"]
            )
        }
    }

    private static func complementaryCategories(for category: String) -> [String] {
        CategoryPairingRules.complementaryCategories(for: category)
    }

}

struct SaleMatchInput: Identifiable {
    let id: String
    let name: String
    let category: String
    let colors: [String]
    let brand: String
    let salePrice: Double
    let originalPrice: Double
}

struct SaleMatchResult: Identifiable {
    let id = UUID()
    let saleItem: SaleMatchInput
    let matchScore: Int
    let reason: String
    let complementaryMatches: [HistorySuggestion]
    let shouldNotify: Bool
}

struct SaleMatchService {
    static func match(saleItems: [SaleMatchInput], records: [GarmentRecord], profile: StylistProfile) -> [SaleMatchResult] {
        saleItems.compactMap { item in
            guard item.salePrice >= profile.budgetRange.minPrice,
                  item.salePrice <= profile.budgetRange.maxPrice else {
                return nil
            }

            let itemRecord = GarmentRecord(
                garmentCategory: GarmentRecordHelpers.category(from: item.category),
                itemFingerprint: GarmentRecordHelpers.fingerprint(
                    category: item.category,
                    colors: item.colors,
                    pattern: nil,
                    fabric: nil,
                    brand: item.brand,
                    styleTags: []
                ),
                brand: item.brand,
                colors: item.colors,
                styleTags: [],
                colorConfidence: 80,
                sourceScanIds: []
            )
            let pairings = ComplementaryPieceRecommender.recommendations(for: itemRecord, ownedRecords: records, limit: 3)
            let preferredBrand = profile.favoriteBrands.contains { $0.caseInsensitiveCompare(item.brand) == .orderedSame }
            let preferredColor = !Set(profile.favoriteColors.map { $0.lowercased() }).isDisjoint(with: item.colors.map { $0.lowercased() })
            let savings = max(0, item.originalPrice - item.salePrice)
            let score = min(99, 70 + (preferredBrand ? 8 : 0) + (preferredColor ? 6 : 0) + min(10, pairings.count * 3) + min(5, Int(savings / 10)))

            return SaleMatchResult(
                saleItem: item,
                matchScore: score,
                reason: "Matches your \(profile.preferredFit.rawValue) profile, \(item.colors.joined(separator: "/")) palette, and \(pairings.count) saved closet pairing\(pairings.count == 1 ? "" : "s").",
                complementaryMatches: pairings,
                shouldNotify: score >= 86 && savings > 0
            )
        }
        .sorted { $0.matchScore > $1.matchScore }
    }
}

struct NotificationDecision {
    let shouldDeliverPush: Bool
    let localFeedMessage: String
}

struct NotificationService {
    static func decision(for match: SaleMatchResult) -> NotificationDecision {
        if FeatureFlags.pushNotificationsEnabled && match.shouldNotify {
            return NotificationDecision(
                shouldDeliverPush: true,
                localFeedMessage: "\(match.saleItem.name) is a \(match.matchScore)% match and is ready for push delivery."
            )
        }

        return NotificationDecision(
            shouldDeliverPush: false,
            localFeedMessage: "\(match.saleItem.name) is a \(match.matchScore)% local match. Push notifications are off, so it stays in the in-app matches feed."
        )
    }
}

enum StyleRankingProvenance: String, Encodable, Equatable {
    case calibratedModelConfidence = "calibrated_model_confidence"
    case uncalibratedModelScore = "uncalibrated_model_score"
    case deterministicHeuristic = "deterministic_heuristic"
    case keywordOrCategoryRule = "keyword_or_category_rule"
    case normalizedRankingScore = "normalized_ranking_score"
    case unknownProvenance = "unknown_provenance"

    var mayRenderAsConfidence: Bool {
        self == .calibratedModelConfidence
    }
}

/// A ranked style label. `rankingScore` is ordering-only and must never be
/// rendered, persisted, or sent to AI consumers as measured confidence.
struct StyleClassificationRanking: Identifiable, Encodable, Equatable {
    var id: String { name }
    let name: String
    let rankingScore: Int
    let reason: String
    let provenance: StyleRankingProvenance

    var customerVisibleConfidence: Int? {
        provenance.mayRenderAsConfidence ? rankingScore : nil
    }

    enum CodingKeys: String, CodingKey {
        case name
        case reason
        case provenance
    }

    static func heuristic(_ name: String, _ rankingScore: Int, reason: String) -> Self {
        Self(
            name: name,
            rankingScore: rankingScore,
            reason: reason,
            provenance: .deterministicHeuristic
        )
    }
}

/// The single production authority for ordering detected-style labels.
///
/// Current inputs are rules, keywords, and deterministic score-derived values;
/// none is a calibrated probability. Consequently this authority intentionally
/// exposes no customer-visible confidence.
struct StyleClassificationAuthority {
    static func rankedStyles(
        for evidence: String,
        baseScore: Int = 82,
        preferredTraditionalName: String? = nil
    ) -> [StyleClassificationRanking] {
        let lower = evidence.lowercased()
        if isUnrecognizedEvidence(lower) {
            return sorted([
                .heuristic("Unrecognized Item", 35, reason: "The scan did not contain enough reliable clothing evidence for a specific style category."),
                .heuristic("Casual", 18, reason: "Casual is possible, but clothing evidence is not reliable enough."),
                .heuristic("Business Casual", 0, reason: "Unknown or low-confidence items must not default to business casual.")
            ])
        }

        if hasSleepwearEvidence(lower) {
            return sorted([
                .heuristic("Sleepwear", min(96, max(88, baseScore)), reason: "Sleepwear, robe, slipper, or indoor comfort signals were detected."),
                .heuristic("Loungewear", min(91, max(78, baseScore - 5)), reason: "Comfort-focused home clothing is stronger than business styling."),
                .heuristic("Casual", 42, reason: "Casual is possible, but sleepwear/loungewear signals are stronger."),
                .heuristic("Business Casual", 12, reason: "Sleepwear and slippers block business casual classification.")
            ])
        }

        if hasTraditionalEvidence(lower) {
            return sorted([
                .heuristic(preferredTraditionalName ?? "Traditional Wear", min(98, max(90, baseScore + 1)), reason: "Traditional garment features are present."),
                .heuristic("Cultural Wear", min(95, max(86, baseScore - 2)), reason: "Cultural attire signals are stronger than Western office categories."),
                .heuristic("Ceremonial Wear", min(88, max(74, baseScore - 8)), reason: "The clothing may fit a cultural event depending on occasion."),
                .heuristic("Business Casual", 18, reason: "Traditional clothing should not default to business casual.")
            ])
        }

        if hasRuggedEvidence(lower) {
            let businessCap = businessConfidenceCap(lower)
            return sorted([
                .heuristic("Casual", min(98, max(92, baseScore + 3)), reason: "Jeans plus hooded, plaid, flannel, or casual top signals point to everyday casual."),
                .heuristic("Rugged Casual", min(96, max(88, baseScore - 1)), reason: "Plaid/flannel, denim, and boots or casual shoes create a rugged workwear/outdoor feel."),
                .heuristic("Outdoor Casual", min(90, max(82, baseScore - 6)), reason: "The outfit reads practical and relaxed rather than office-ready."),
                .heuristic("Smart Casual", min(35, businessCap + 10), reason: "The look can be cleaned up, but hoodie/flannel plus jeans keeps it casual."),
                .heuristic("Business Casual", businessCap, reason: "Business casual is capped low because hoodie/flannel plus jeans lacks business-style anchors.")
            ])
        }

        if hasYouthGraphicCasualEvidence(lower) {
            return sorted([
                .heuristic("Casual", min(96, max(88, baseScore)), reason: "Graphic, youth, home, relaxed, or everyday clothing signals are stronger than business styling."),
                .heuristic("Everyday Casual", min(92, max(80, baseScore - 4)), reason: "The visible outfit reads relaxed and practical for normal daily wear."),
                .heuristic("Loungewear", min(76, max(45, baseScore - 22)), reason: "Home or comfort signals may be present, but visible clothing is not confirmed as sleepwear."),
                .heuristic("Business Casual", businessConfidenceCap(lower), reason: "Business casual is capped because no strong business-style anchors were detected.")
            ])
        }

        if hasBusinessEvidence(lower) && !hasStrongCasualBlocker(lower) {
            let confidence = businessConfidenceCap(lower) == 70
                ? min(70, max(50, baseScore - 18))
                : min(96, max(74, baseScore + 1))
            return sorted([
                .heuristic("Business Casual", confidence, reason: "Multiple business-style items are present."),
                .heuristic("Smart Casual", min(88, max(68, confidence - 8)), reason: "The outfit may also work as a polished casual look."),
                .heuristic("Casual", min(62, max(35, 100 - confidence)), reason: "Casual ranking stays lower when business anchors are visible.")
            ])
        }

        if hasStreetwearEvidence(lower) {
            return sorted([
                .heuristic("Streetwear", min(94, max(82, baseScore - 2)), reason: "Hoodie, sneakers, oversized, or streetwear signals are present."),
                .heuristic("Casual", min(92, max(78, baseScore - 5)), reason: "The outfit is relaxed and everyday."),
                .heuristic("Business Casual", businessConfidenceCap(lower), reason: "Business anchors are not strong enough for a high business casual ranking.")
            ])
        }

        return sorted([
            .heuristic("Casual", min(94, max(78, baseScore - 2)), reason: "Visible evidence supports a general everyday style."),
            .heuristic("Smart Casual", min(72, max(42, baseScore - 22)), reason: "Some polish may be possible depending on shoes and accessories."),
            .heuristic("Business Casual", businessConfidenceCap(lower), reason: "Business casual requires stronger business-style clothing evidence.")
        ])
    }

    private static func sorted(_ styles: [StyleClassificationRanking]) -> [StyleClassificationRanking] {
        styles.sorted { first, second in
            if first.rankingScore == second.rankingScore {
                return first.name < second.name
            }
            return first.rankingScore > second.rankingScore
        }
    }

    private static func hasBusinessEvidence(_ text: String) -> Bool {
        let businessAnchors = [
            "button-down", "button down", "oxford", "dress shirt", "polo", "chino",
            "chinos", "dress pants", "slacks", "blazer", "cardigan", "loafer", "loafers", "dress shoes"
        ]
        return businessAnchors.filter { text.contains($0) }.count >= 2
    }

    private static func isUnrecognizedEvidence(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            || trimmed.contains("unrecognized")
            || trimmed.contains("category uncertain")
            || trimmed.contains("unknown item")
            || trimmed.contains("could not identify enough")
    }

    private static func businessConfidenceCap(_ text: String) -> Int {
        if hasStrongCasualBlocker(text) { return 25 }
        return hasBusinessEvidence(text) ? 96 : 40
    }

    private static func hasStrongCasualBlocker(_ text: String) -> Bool {
        let hasDenim = ["jean", "jeans", "denim", "jogger", "joggers"].contains { text.contains($0) }
        let hasCasualTop = ["hoodie", "hooded", "flannel", "plaid", "t-shirt", "tee", "graphic"].contains { text.contains($0) }
        let hasCasualShoe = ["sneaker", "sneakers", "boot", "boots"].contains { text.contains($0) }
        return (hasDenim && hasCasualTop) || (hasCasualTop && hasCasualShoe)
    }

    private static func hasRuggedEvidence(_ text: String) -> Bool {
        let hasDenim = ["jean", "jeans", "denim"].contains { text.contains($0) }
        let hasCasualTop = ["hoodie", "hooded", "flannel", "plaid", "shacket", "workwear"].contains { text.contains($0) }
        let hasBoot = ["boot", "boots", "hiking"].contains { text.contains($0) }
        return (hasDenim && hasCasualTop) || (hasDenim && hasBoot) || (hasCasualTop && hasBoot)
    }

    private static func hasYouthGraphicCasualEvidence(_ text: String) -> Bool {
        let youthOrHome = [
            "child", "kid", "girl", "boy", "youth", "home", "house", "bedroom",
            "graphic", "character", "cartoon", "play", "everyday"
        ].contains { text.contains($0) }
        let casualGarment = [
            "t-shirt", "tee", "shirt", "jeans", "jogger", "joggers", "leggings",
            "shorts", "sneaker", "sneakers"
        ].contains { text.contains($0) }
        return youthOrHome && casualGarment
    }

    private static func hasStreetwearEvidence(_ text: String) -> Bool {
        ["hoodie", "sneaker", "street", "oversized"].contains { text.contains($0) }
    }

    private static func hasSleepwearEvidence(_ text: String) -> Bool {
        if [
            "pajama", "pyjama", "sleepwear", "nightwear", "nightgown",
            "robe", "bathrobe", "fleece robe", "plush robe", "housecoat",
            "slipper", "slippers", "bedroom slipper", "house shoe",
            "onesie", "loungewear", "lounge set", "homewear", "house clothes",
            "indoor wear", "sleep set", "matching sleep"
        ].contains(where: { text.contains($0) }) {
            return true
        }

        return hasContextualSleepwearSetEvidence(text)
    }

    private static func hasContextualSleepwearSetEvidence(_ text: String) -> Bool {
        let homeOrYouthSignals = [
            "bedroom", "bed", "blanket", "pillow", "home", "house", "indoor",
            "child", "kid", "girl", "boy", "children", "youth", "toy"
        ].filter { text.contains($0) }.count
        let matchingSetSignals = [
            "matching set", "coordinated set", "two-piece", "two piece",
            "matching top and bottom", "top and bottom", "matching outfit",
            "shirt and pants set", "pants set"
        ].filter { text.contains($0) }.count
        let comfortPatternSignals = [
            "stripe", "striped", "red and white", "pink and white", "pink red",
            "pastel", "soft", "loose", "barefoot"
        ].filter { text.contains($0) }.count

        return homeOrYouthSignals > 0 && matchingSetSignals > 0 && comfortPatternSignals > 0
    }

    private static func hasTraditionalEvidence(_ text: String) -> Bool {
        guard !hasStrongCasualBlocker(text), !hasSleepwearEvidence(text) else { return false }
        let explicit = [
            "agbada", "dashiki", "kaftan", "kente", "kimono", "hanbok", "saree",
            "sari", "thobe", "abaya", "kilt", "dirndl", "huipil", "shuka"
        ].filter { text.contains($0) }.count
        let support = ["embroidery", "headwrap", "gele", "ceremonial", "traditional", "woven", "heritage"].filter { text.contains($0) }.count
        return explicit >= 1 && support >= 1
    }
}

struct DailyStyleRecommendation: Equatable {
    let itemIDs: [UUID]
    let title: String
    let evidenceLabel: String
    let rationale: String
}

enum DailyStyleRecommendationEngine {
    private enum Role: Hashable { case top, bottom, dress, shoes, layer, accessory, other }
    private struct Candidate { let items: [ClosetItem]; let score: Int }

    static func recommend(
        items: [ClosetItem],
        temperatureFahrenheit: Int?,
        condition: String?,
        occasion: String,
        dressCode: String,
        workSetting: String
    ) -> DailyStyleRecommendation? {
        let requiresSafety = requiresSafetyFootwear(dressCode: dressCode, workSetting: workSetting)
        let tops = items.filter { role(for: $0) == .top }
        let bottoms = items.filter { role(for: $0) == .bottom }
        let dresses = items.filter { role(for: $0) == .dress }
        let allShoes = items.filter { role(for: $0) == .shoes }
        let shoes = requiresSafety ? allShoes.filter(isSafetyFootwear) : allShoes
        guard !shoes.isEmpty else { return nil }

        var candidates: [Candidate] = []
        if let top = best(tops, temperatureFahrenheit, condition, occasion, dressCode, workSetting),
           let bottom = best(bottoms, temperatureFahrenheit, condition, occasion, dressCode, workSetting, pairedWith: top),
           let shoe = best(shoes, temperatureFahrenheit, condition, occasion, dressCode, workSetting, pairedWith: bottom) {
            let score = itemScore(top, temperatureFahrenheit, condition, occasion, dressCode, workSetting)
                + itemScore(bottom, temperatureFahrenheit, condition, occasion, dressCode, workSetting)
                + itemScore(shoe, temperatureFahrenheit, condition, occasion, dressCode, workSetting)
                + colorCompatibility(top.color, bottom.color) + colorCompatibility(bottom.color, shoe.color)
            candidates.append(Candidate(items: [top, bottom, shoe], score: score))
        }
        if let dress = best(dresses, temperatureFahrenheit, condition, occasion, dressCode, workSetting),
           let shoe = best(shoes, temperatureFahrenheit, condition, occasion, dressCode, workSetting, pairedWith: dress) {
            candidates.append(Candidate(
                items: [dress, shoe],
                score: itemScore(dress, temperatureFahrenheit, condition, occasion, dressCode, workSetting)
                    + itemScore(shoe, temperatureFahrenheit, condition, occasion, dressCode, workSetting)
                    + colorCompatibility(dress.color, shoe.color)
            ))
        }
        guard var winner = candidates.sorted(by: candidateOrder).first else { return nil }

        if shouldAddLayer(temperatureFahrenheit: temperatureFahrenheit, condition: condition),
           let layer = best(items.filter { role(for: $0) == .layer }, temperatureFahrenheit, condition, occasion, dressCode, workSetting, pairedWith: winner.items.first) {
            winner = Candidate(items: winner.items + [layer], score: winner.score + 3)
        }
        if winner.items.count < 4,
           let accessory = best(items.filter { role(for: $0) == .accessory }, temperatureFahrenheit, condition, occasion, dressCode, workSetting, pairedWith: winner.items.first) {
            winner = Candidate(items: winner.items + [accessory], score: winner.score + 1)
        }

        let context = [occasion, dressCode, workSetting]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        let title = context.map { "Best Match • \($0)" } ?? "Best Match from your Closet"
        let evidence = context == nil && temperatureFahrenheit == nil
            ? "Verified Closet • \(winner.items.count) pieces"
            : "Strong Match • \(winner.items.count) verified pieces"
        let rationale = requiresSafety
            ? "Uses only verified Closet pieces and keeps safety footwear required for the saved work context."
            : "Uses only verified Closet pieces, then ranks occasion, weather, and color compatibility when those facts are available."
        return DailyStyleRecommendation(itemIDs: winner.items.map(\.id), title: title, evidenceLabel: evidence, rationale: rationale)
    }

    static func missingRequirements(items: [ClosetItem], dressCode: String, workSetting: String) -> [String] {
        let roles = Set(items.map(role(for:)))
        var missing: [String] = []
        let hasBase = roles.contains(.dress) || (roles.contains(.top) && roles.contains(.bottom))
        if !hasBase {
            if !roles.contains(.top) { missing.append("a top") }
            if !roles.contains(.bottom) { missing.append("pants or another bottom") }
        }
        if requiresSafetyFootwear(dressCode: dressCode, workSetting: workSetting) {
            if !items.contains(where: isSafetyFootwear) { missing.append("safety footwear") }
        } else if !roles.contains(.shoes) {
            missing.append("shoes")
        }
        return missing
    }

    private static func best(
        _ items: [ClosetItem], _ temperature: Int?, _ condition: String?, _ occasion: String,
        _ dressCode: String, _ workSetting: String, pairedWith paired: ClosetItem? = nil
    ) -> ClosetItem? {
        items.sorted { lhs, rhs in
            let left = itemScore(lhs, temperature, condition, occasion, dressCode, workSetting) + (paired.map { colorCompatibility(lhs.color, $0.color) } ?? 0)
            let right = itemScore(rhs, temperature, condition, occasion, dressCode, workSetting) + (paired.map { colorCompatibility(rhs.color, $0.color) } ?? 0)
            return left == right ? lhs.id.uuidString < rhs.id.uuidString : left > right
        }.first
    }

    private static func candidateOrder(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        return lhs.items.map(\.id.uuidString).joined() < rhs.items.map(\.id.uuidString).joined()
    }

    private static func itemScore(_ item: ClosetItem, _ temperature: Int?, _ condition: String?, _ occasion: String, _ dressCode: String, _ workSetting: String) -> Int {
        let text = searchableText(item)
        let context = "\(occasion) \(dressCode) \(workSetting)".lowercased()
        var score = 0
        if !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !item.occasion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           context.contains(item.occasion.lowercased()) { score += 6 }
        if let temperature {
            if temperature >= 80 {
                if containsAny(text, ["short", "linen", "lightweight", "breathable", "summer"]) { score += 3 }
                if role(for: item) == .layer { score -= 5 }
            } else if temperature <= 60,
                      containsAny(text, ["sweater", "hoodie", "jacket", "coat", "warm", "winter"]) { score += 3 }
        }
        if containsAny((condition ?? "").lowercased(), ["rain", "snow", "storm", "wind"]),
           containsAny(text, ["waterproof", "weather", "boot", "coat", "jacket"]) { score += 2 }
        if requiresSafetyFootwear(dressCode: dressCode, workSetting: workSetting), role(for: item) == .shoes {
            score += isSafetyFootwear(item) ? 20 : -40
        }
        return score
    }

    private static func role(for item: ClosetItem) -> Role {
        let text = "\(item.category) \(item.name)".lowercased()
        if containsAny(text, ["shoe", "sneaker", "boot", "loafer", "heel", "sandal"]) { return .shoes }
        if containsAny(text, ["dress", "jumpsuit", "romper"]) { return .dress }
        if containsAny(text, ["pant", "jean", "chino", "trouser", "short", "skirt"]) { return .bottom }
        if containsAny(text, ["jacket", "coat", "blazer", "cardigan", "outerwear"]) { return .layer }
        if containsAny(text, ["accessor", "belt", "watch", "hat", "scarf", "jewelry", "bag"]) { return .accessory }
        if containsAny(text, ["shirt", "tee", "t-shirt", "polo", "blouse", "sweater", "hoodie", "top"]) { return .top }
        return .other
    }

    private static func requiresSafetyFootwear(dressCode: String, workSetting: String) -> Bool {
        containsAny("\(dressCode) \(workSetting)".lowercased(), ["ppe", "factory", "plant", "manufactur", "warehouse", "production", "safety", "steel toe", "safety toe"])
    }

    private static func isSafetyFootwear(_ item: ClosetItem) -> Bool {
        containsAny(searchableText(item), ["safety toe", "safety-toe", "steel toe", "steel-toe", "composite toe", "slip resistant", "slip-resistant", "work boot"])
    }

    private static func shouldAddLayer(temperatureFahrenheit: Int?, condition: String?) -> Bool {
        if let temperatureFahrenheit, temperatureFahrenheit <= 65 { return true }
        return containsAny((condition ?? "").lowercased(), ["rain", "snow", "wind", "cold"])
    }

    private static func colorCompatibility(_ lhs: String, _ rhs: String) -> Int {
        let left = lhs.lowercased(), right = rhs.lowercased()
        if left.isEmpty || right.isEmpty { return 0 }
        if left == right { return 2 }
        let neutrals = ["black", "white", "gray", "grey", "navy", "beige", "tan", "brown", "charcoal", "cream", "khaki", "denim"]
        if neutrals.contains(where: left.contains) || neutrals.contains(where: right.contains) { return 3 }
        return 0
    }

    private static func searchableText(_ item: ClosetItem) -> String {
        "\(item.name) \(item.category) \(item.color) \(item.brand) \(item.occasion) \(item.notes)".lowercased()
    }

    private static func containsAny(_ text: String, _ terms: [String]) -> Bool {
        terms.contains(where: text.contains)
    }
}

/// Compatibility facade for existing callers. It deliberately contains no
/// legacy style-classification inference logic; that ranking remains owned by
/// `StyleClassificationAuthority`.
struct StyleClassificationGuardrails {
    static func rankedStyles(for evidence: String, baseScore: Int = 82) -> [StyleClassificationRanking] {
        StyleClassificationAuthority.rankedStyles(for: evidence, baseScore: baseScore)
    }
}
