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
    static var conversationalStylist = false
    static var alternateAIProvidersEnabled = false
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
        let garments = analysis.safeDetectedClothingItems.isEmpty ? ["outfit item"] : analysis.safeDetectedClothingItems
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
                detail: "This is based on pieces StyleMatch Pro has seen in your history.",
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
                detail: "This would complement \(HistorySuggestionEngine.display(garment)) based on StyleMatch Pro's color rules.",
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

struct StyleClassificationGuardrails {
    static func rankedStyles(for evidence: String, baseScore: Int = 82) -> [(name: String, confidence: Int)] {
        let lower = evidence.lowercased()
        if isUnrecognizedEvidence(lower) {
            return sorted([
                ("Unrecognized Item", 35),
                ("Casual", 18),
                ("Business Casual", 0),
                ("Traditional Wear", 0)
            ])
        }

        if hasSleepwearEvidence(lower) {
            return sorted([
                ("Sleepwear", min(96, max(86, baseScore + 4))),
                ("Loungewear", min(90, max(78, baseScore - 2))),
                ("Casual", 42),
                ("Business Casual", 12),
                ("Traditional Wear", 8)
            ])
        }

        if hasTraditionalEvidence(lower) {
            return sorted([
                ("Traditional Wear", min(98, max(90, baseScore + 3))),
                ("Cultural Wear", min(95, max(86, baseScore))),
                ("Business Casual", 18)
            ])
        }

        if hasBusinessEvidence(lower) && !hasStrongCasualBlocker(lower) {
            let confidence = businessConfidenceCap(lower) == 70
                ? min(70, max(50, baseScore - 18))
                : min(96, max(74, baseScore + 1))
            return sorted([
                ("Business Casual", confidence),
                ("Smart Casual", min(88, max(68, confidence - 8))),
                ("Casual", min(62, max(35, 100 - confidence)))
            ])
        }

        if hasRuggedEvidence(lower) {
            return sorted([
                ("Casual", min(98, max(92, baseScore + 3))),
                ("Rugged Casual", min(96, max(88, baseScore - 1))),
                ("Outdoor Casual", min(90, max(82, baseScore - 6))),
                ("Business Casual", businessConfidenceCap(lower)),
                ("Traditional Wear", 8)
            ])
        }

        return sorted([
            ("Casual", min(94, max(78, baseScore - 2))),
            ("Smart Casual", min(72, max(42, baseScore - 22))),
            ("Business Casual", businessConfidenceCap(lower)),
            ("Traditional Wear", 8)
        ])
    }

    private static func sorted(_ styles: [(name: String, confidence: Int)]) -> [(name: String, confidence: Int)] {
        styles.sorted { first, second in
            if first.confidence == second.confidence {
                return first.name < second.name
            }
            return first.confidence > second.confidence
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
