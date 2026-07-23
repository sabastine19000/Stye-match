import Foundation

enum ScanMessageCopy {
    static func savedScoreDescription(
        confidenceLabel: String,
        qualityDescription: String,
        guidance: String,
        savedResultMessage: String
    ) -> String {
        "\(confidenceLabel) confidence. \(qualityDescription) \(guidance) \(savedResultMessage)"
    }
}

struct RoadmapVersion: Identifiable {
    let id = UUID()
    let title: String
    let version: String
    let goal: String
    let features: [String]
    let prompt: String
    let acceptanceTests: [String]
}

struct BuildPhase: Identifiable {
    let id = UUID()
    let title: String
    let description: String
}

struct OutfitAnalysisResult: Codable {
    let score: Int
    let scoreBreakdown: OutfitScoreBreakdown?
    let colorMatch: String
    let occasionFit: String
    let styleBalance: String
    let colorHarmony: String
    let styleCoordination: String
    let formality: String
    let seasonalMatch: String
    let summary: String
    let outfitDescription: String
    let detectedClothingItems: [String]
    let colorPalette: [String]
    let colorPaletteMaskingApplied: Bool
    let colorPaletteMaskTier: String?
    let colorPaletteConfidence: GarmentPaletteConfidence
    let colorPaletteDetectionConfidence: Int
    let colorPaletteNotes: String
    let environment: String
    let imageQuality: String
    let outfitClassification: OutfitClassificationResult
    // Legacy decode-only compatibility for saved scans created before Build 1.7 privacy isolation.
    let skinToneStyleNote: String?
    let detectedItemConfidences: [DetectedItemConfidence]
    let chatGPTStylistSections: [ChatGPTStylistSection]
    let suggestions: [String]
    let recommendations: [ClothingRecommendation]

    init(
        score: Int,
        scoreBreakdown: OutfitScoreBreakdown? = nil,
        colorMatch: String,
        occasionFit: String,
        styleBalance: String,
        colorHarmony: String,
        styleCoordination: String,
        formality: String,
        seasonalMatch: String,
        summary: String,
        outfitDescription: String,
        detectedClothingItems: [String],
        colorPalette: [String],
        colorPaletteMaskingApplied: Bool = true,
        colorPaletteMaskTier: String? = nil,
        colorPaletteConfidence: GarmentPaletteConfidence = .confident,
        colorPaletteDetectionConfidence: Int? = nil,
        colorPaletteNotes: String? = nil,
        environment: String,
        imageQuality: String,
        outfitClassification: OutfitClassificationResult = .uncertain(),
        skinToneStyleNote: String? = nil,
        detectedItemConfidences: [DetectedItemConfidence] = [],
        chatGPTStylistSections: [ChatGPTStylistSection] = [],
        suggestions: [String],
        recommendations: [ClothingRecommendation]
    ) {
        self.score = score
        self.scoreBreakdown = scoreBreakdown
        self.colorMatch = colorMatch
        self.occasionFit = occasionFit
        self.styleBalance = styleBalance
        self.colorHarmony = colorHarmony
        self.styleCoordination = styleCoordination
        self.formality = formality
        self.seasonalMatch = seasonalMatch
        self.summary = summary
        self.outfitDescription = outfitDescription
        self.detectedClothingItems = GarmentLabelMapper.sanitizedTerms(from: detectedClothingItems)
        self.colorPalette = colorPalette
        self.colorPaletteMaskingApplied = colorPaletteMaskingApplied
        self.colorPaletteMaskTier = colorPaletteMaskTier
        self.colorPaletteConfidence = colorPaletteConfidence
        self.colorPaletteDetectionConfidence = colorPaletteDetectionConfidence
            ?? (colorPaletteConfidence == .confident ? 80 : 40)
        self.colorPaletteNotes = colorPaletteNotes
            ?? (colorPaletteConfidence == .confident
                ? "High confidence: garment colors came from the completed scan palette."
                : "Low confidence: colors were hard to read in this photo.")
        self.environment = environment
        self.imageQuality = imageQuality
        self.outfitClassification = outfitClassification
        self.skinToneStyleNote = skinToneStyleNote
        self.detectedItemConfidences = detectedItemConfidences
        self.chatGPTStylistSections = chatGPTStylistSections
        self.suggestions = suggestions
        self.recommendations = recommendations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        score = try container.decode(Int.self, forKey: .score)
        scoreBreakdown = try container.decodeIfPresent(OutfitScoreBreakdown.self, forKey: .scoreBreakdown)
        colorMatch = try container.decode(String.self, forKey: .colorMatch)
        occasionFit = try container.decode(String.self, forKey: .occasionFit)
        styleBalance = try container.decode(String.self, forKey: .styleBalance)
        colorHarmony = try container.decode(String.self, forKey: .colorHarmony)
        styleCoordination = try container.decode(String.self, forKey: .styleCoordination)
        formality = try container.decode(String.self, forKey: .formality)
        seasonalMatch = try container.decode(String.self, forKey: .seasonalMatch)
        summary = try container.decode(String.self, forKey: .summary)
        outfitDescription = try container.decode(String.self, forKey: .outfitDescription)
        detectedClothingItems = GarmentLabelMapper.sanitizedTerms(
            from: try container.decode([String].self, forKey: .detectedClothingItems)
        )
        colorPalette = try container.decode([String].self, forKey: .colorPalette)
        colorPaletteMaskingApplied = try container.decodeIfPresent(Bool.self, forKey: .colorPaletteMaskingApplied) ?? true
        colorPaletteMaskTier = try container.decodeIfPresent(String.self, forKey: .colorPaletteMaskTier)
        colorPaletteConfidence = try container.decodeIfPresent(GarmentPaletteConfidence.self, forKey: .colorPaletteConfidence) ?? .confident
        colorPaletteDetectionConfidence = try container.decodeIfPresent(Int.self, forKey: .colorPaletteDetectionConfidence)
            ?? (colorPaletteConfidence == .confident ? 80 : 40)
        colorPaletteNotes = try container.decodeIfPresent(String.self, forKey: .colorPaletteNotes)
            ?? (colorPaletteConfidence == .confident
                ? "High confidence: garment colors came from the completed scan palette."
                : "Low confidence: colors were hard to read in this photo.")
        environment = try container.decode(String.self, forKey: .environment)
        imageQuality = try container.decode(String.self, forKey: .imageQuality)
        outfitClassification = try container.decodeIfPresent(OutfitClassificationResult.self, forKey: .outfitClassification) ?? .uncertain()
        skinToneStyleNote = try container.decodeIfPresent(String.self, forKey: .skinToneStyleNote)
        detectedItemConfidences = try container.decodeIfPresent([DetectedItemConfidence].self, forKey: .detectedItemConfidences) ?? []
        chatGPTStylistSections = try container.decodeIfPresent([ChatGPTStylistSection].self, forKey: .chatGPTStylistSections) ?? []
        suggestions = try container.decode([String].self, forKey: .suggestions)
        recommendations = try container.decode([ClothingRecommendation].self, forKey: .recommendations)
    }
}

extension OutfitAnalysisResult {
    func replacingOutfitClassification(_ classification: OutfitClassificationResult) -> OutfitAnalysisResult {
        OutfitAnalysisResult(
            score: score,
            scoreBreakdown: scoreBreakdown,
            colorMatch: colorMatch,
            occasionFit: occasionFit,
            // A user correction changes the outfit category authority, not the
            // independently detected style evidence stored on the scan.
            styleBalance: styleBalance,
            colorHarmony: colorHarmony,
            styleCoordination: styleCoordination,
            formality: formality,
            seasonalMatch: seasonalMatch,
            summary: summary,
            outfitDescription: outfitDescription,
            detectedClothingItems: detectedClothingItems,
            colorPalette: colorPalette,
            colorPaletteMaskingApplied: colorPaletteMaskingApplied,
            colorPaletteMaskTier: colorPaletteMaskTier,
            colorPaletteConfidence: colorPaletteConfidence,
            colorPaletteDetectionConfidence: colorPaletteDetectionConfidence,
            colorPaletteNotes: colorPaletteNotes,
            environment: environment,
            imageQuality: imageQuality,
            outfitClassification: classification,
            skinToneStyleNote: nil,
            detectedItemConfidences: detectedItemConfidences,
            chatGPTStylistSections: chatGPTStylistSections,
            suggestions: suggestions,
            recommendations: recommendations
        )
    }
}

enum GarmentLabelMapper {
    private static let droppedTerms: Set<String> = [
        "textile",
        "fabric",
        "apparel",
        "clothing",
        "person wearing outfit",
        "person",
        "human",
        "man",
        "woman",
        "boy",
        "girl"
    ]

    private static let table: [(terms: [String], value: String)] = [
        (["t-shirt", "tee shirt", "tee", "jersey"], "t-shirt"),
        (["polo shirt", "polo"], "polo shirt"),
        (["dress shirt", "button-down", "button down", "oxford shirt"], "button-down shirt"),
        (["shirt", "top", "blouse"], "shirt"),
        (["sweater", "sweatshirt", "hoodie", "pullover"], "sweater"),
        (["jacket", "coat", "blazer", "shacket", "parka"], "jacket"),
        (["pants", "trousers", "slacks", "chinos"], "pants"),
        (["jeans", "denim"], "jeans"),
        (["shorts"], "shorts"),
        (["dress", "gown"], "dress"),
        (["skirt"], "skirt"),
        (["suit"], "suit"),
        (["robe", "bathrobe"], "robe"),
        (["pajama", "pyjama", "sleepwear", "nightwear"], "sleepwear"),
        (["slipper", "house shoe"], "slippers"),
        (["sneaker", "shoe", "loafer", "boot", "sandal"], "shoes"),
        (["hat", "cap", "headwear"], "hat"),
        (["bag", "purse", "handbag", "backpack"], "bag"),
        (["belt"], "belt"),
        (["watch"], "watch"),
        (["scarf"], "scarf"),
        (["tie", "necktie"], "tie"),
        (["accessory", "jewelry", "jewellery", "necklace", "bracelet", "earring"], "accessory")
    ]

    static var debugMappingTable: [(terms: [String], value: String)] {
        table
    }

    static func humanReadableTerm(for rawValue: String) -> String? {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        guard !normalized.isEmpty else {
            return nil
        }
        if droppedTerms.contains(normalized) {
            return nil
        }
        if droppedTerms.contains(where: { normalized == $0 || normalized.hasSuffix(" \($0)") }) {
            return nil
        }

        return table.first { entry in
            entry.terms.contains { term in
                normalized == term || normalized.contains(term)
            }
        }?.value
    }

    static func sanitizedTerms(from rawValues: [String], fallback: String? = nil) -> [String] {
        let mapped = rawValues
            .compactMap(humanReadableTerm)
            .removingDuplicates()

        if mapped.isEmpty, let fallback {
            return [fallback]
        }
        return mapped
    }
}

extension OutfitAnalysisResult {
    var safeDetectedClothingItems: [String] {
        let storedItems = GarmentLabelMapper.sanitizedTerms(from: detectedClothingItems)
        if !storedItems.isEmpty {
            return storedItems
        }

        return detectedItemConfidences
            .sorted { $0.confidence > $1.confidence }
            .compactMap { GarmentLabelMapper.humanReadableTerm(for: $0.item) }
            .removingDuplicates()
    }
}

enum OutfitCategory: String, Codable, CaseIterable, Equatable, Identifiable {
    case workUniform
    case brandedWorkwear
    case schoolUniform
    case medicalScrubs
    case businessCasual
    case businessFormal
    case mensSuit
    case tuxedo
    case femaleBusinessDress
    case cocktailDress
    case eveningGown
    case weddingDress
    case bridesmaidDress
    case casualDress
    case casualWear
    case traditionalCulturalAttire
    case sportswear
    case activewear
    case outerwear
    case swimwear
    case footwear
    case accessories
    case otherUncertain

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .workUniform: return "Work Uniform"
        case .brandedWorkwear: return "Branded Workwear"
        case .schoolUniform: return "School Uniform"
        case .medicalScrubs: return "Medical Scrubs"
        case .businessCasual: return "Business Casual"
        case .businessFormal: return "Business Formal"
        case .mensSuit: return "Men's Suit"
        case .tuxedo: return "Tuxedo"
        case .femaleBusinessDress: return "Women's Business Attire"
        case .cocktailDress: return "Cocktail Dress"
        case .eveningGown: return "Evening Gown"
        case .weddingDress: return "Wedding Dress"
        case .bridesmaidDress: return "Bridesmaid Dress"
        case .casualDress: return "Casual Dress"
        case .casualWear: return "Casual Wear"
        case .traditionalCulturalAttire: return "Traditional or Cultural Attire"
        case .sportswear: return "Sportswear"
        case .activewear: return "Activewear"
        case .outerwear: return "Outerwear"
        case .swimwear: return "Swimwear"
        case .footwear: return "Footwear"
        case .accessories: return "Accessories"
        case .otherUncertain: return "Other / Uncertain"
        }
    }
}

enum OutfitClassificationConfidence: String, Codable, Equatable {
    case high
    case medium
    case low
}

enum OutfitOccasionCompatibility: String, Codable, Equatable {
    case compatible
    case possible
    case conflict
    case uncertain
}

enum OutfitScoringProfile: String, Codable, Equatable {
    case uniformWorkwear
    case businessProfessional
    case formalEvent
    case weddingParty
    case culturalTraditional
    case athleticPerformance
    case casualEveryday
    case protectiveOuterwear
    case swimwear
    case accessoriesFootwear
    case uncertain

    var displayName: String {
        switch self {
        case .uniformWorkwear: return "Uniform and Workwear"
        case .businessProfessional: return "Business and Professional"
        case .formalEvent: return "Formal Event"
        case .weddingParty: return "Wedding Party"
        case .culturalTraditional: return "Traditional and Cultural"
        case .athleticPerformance: return "Athletic Performance"
        case .casualEveryday: return "Casual Everyday"
        case .protectiveOuterwear: return "Protective Outerwear"
        case .swimwear: return "Swimwear"
        case .accessoriesFootwear: return "Accessories and Footwear"
        case .uncertain: return "General Evidence"
        }
    }

    var evaluationCriteria: [String] {
        switch self {
        case .uniformWorkwear:
            return ["cleanliness", "fit", "coordination", "condition", "safety", "dress-code appropriateness", "weather suitability"]
        case .businessProfessional:
            return ["professional appropriateness", "fit", "length", "color coordination", "workplace context", "condition"]
        case .formalEvent:
            return ["silhouette", "fit", "fabric harmony", "event formality", "accessories", "venue appropriateness"]
        case .weddingParty:
            return ["silhouette", "fit", "fabric harmony", "ceremony formality", "accessories", "venue appropriateness"]
        case .culturalTraditional:
            return ["fit", "fabric presentation", "color harmony", "layering", "occasion context", "respectful accessories"]
        case .athleticPerformance:
            return ["movement", "comfort", "activity suitability", "fit", "footwear coordination", "weather suitability"]
        case .casualEveryday:
            return ["fit", "color harmony", "pattern balance", "condition", "occasion suitability", "weather suitability"]
        case .protectiveOuterwear:
            return ["condition", "fit", "layering", "weather protection", "safety", "occasion suitability"]
        case .swimwear:
            return ["fit", "condition", "activity suitability", "coverage preference", "weather suitability", "accessories"]
        case .accessoriesFootwear:
            return ["condition", "fit", "coordination", "function", "occasion suitability", "weather suitability"]
        case .uncertain:
            return ["visible condition", "fit where observable", "color coordination", "occasion context", "weather suitability"]
        }
    }
}

struct OutfitClassificationEvidence: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case silhouette
        case construction
        case visibleText
        case branding
        case occasion
        case accessory
        case uncertainty
    }

    let kind: Kind
    let summary: String
    let confidence: Double

    var id: String { "\(kind.rawValue)|\(summary)" }

    init(kind: Kind, summary: String, confidence: Double) {
        self.kind = kind
        self.summary = String(summary.trimmingCharacters(in: .whitespacesAndNewlines).prefix(180))
        self.confidence = min(1, max(0, confidence))
    }
}

struct OutfitVisualObservation: Codable, Equatable {
    let identifier: String
    let confidence: Double

    init(identifier: String, confidence: Double) {
        self.identifier = identifier
        self.confidence = min(1, max(0, confidence))
    }
}

struct OutfitTextObservation: Codable, Equatable {
    let text: String
    let confidence: Double

    init(text: String, confidence: Double) {
        self.text = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        self.confidence = min(1, max(0, confidence))
    }
}

struct OutfitClassificationResult: Codable, Equatable {
    let primaryCategory: OutfitCategory
    let secondaryCategories: [OutfitCategory]
    let confidence: Double
    let confidenceLevel: OutfitClassificationConfidence
    let evidence: [OutfitClassificationEvidence]
    /// Privacy-safe context tokens only. Raw OCR and probable names are never persisted here.
    let detectedText: [String]
    /// Generic evidence descriptions only; this is not a brand-identification result.
    let detectedBranding: [String]
    let selectedOccasion: String?
    let occasionCompatibility: OutfitOccasionCompatibility
    let userConfirmedCategory: OutfitCategory?
    let scoringProfile: OutfitScoringProfile

    var effectiveCategory: OutfitCategory { userConfirmedCategory ?? primaryCategory }
    var requiresConfirmation: Bool {
        guard userConfirmedCategory == nil, !isUncertain else { return false }
        let confirmationRequiredCategories: Set<OutfitCategory> = [
            .workUniform, .brandedWorkwear, .schoolUniform, .medicalScrubs
        ]
        return confidenceLevel == .medium || confirmationRequiredCategories.contains(primaryCategory)
    }
    var isUncertain: Bool {
        effectiveCategory == .otherUncertain
            || (userConfirmedCategory == nil && confidenceLevel == .low)
    }

    static func uncertain(selectedOccasion: String? = nil) -> Self {
        Self(
            primaryCategory: .otherUncertain,
            secondaryCategories: [],
            confidence: 0,
            confidenceLevel: .low,
            evidence: [.init(kind: .uncertainty, summary: "Not enough reliable garment evidence was available.", confidence: 1)],
            detectedText: [],
            detectedBranding: [],
            selectedOccasion: selectedOccasion,
            occasionCompatibility: .uncertain,
            userConfirmedCategory: nil,
            scoringProfile: .uncertain
        )
    }

    func confirming(_ category: OutfitCategory) -> Self {
        Self(
            primaryCategory: primaryCategory,
            secondaryCategories: secondaryCategories,
            confidence: confidence,
            confidenceLevel: confidenceLevel,
            evidence: evidence + [.init(kind: .occasion, summary: "The user confirmed \(category.displayName) for this scan.", confidence: 1)],
            detectedText: detectedText,
            detectedBranding: detectedBranding,
            selectedOccasion: selectedOccasion,
            occasionCompatibility: OutfitClassificationEngine.occasionCompatibility(category: category, selectedOccasion: selectedOccasion),
            userConfirmedCategory: category,
            scoringProfile: OutfitClassificationEngine.scoringProfile(for: category)
        )
    }
}

enum OutfitClassificationEngine {
    private struct Candidate {
        let category: OutfitCategory
        var score: Double
        var evidence: [OutfitClassificationEvidence]
    }

    static func classify(
        visualObservations: [OutfitVisualObservation],
        textObservations: [OutfitTextObservation] = [],
        selectedOccasion: String? = nil
    ) -> OutfitClassificationResult {
        let visual = visualObservations
            .filter { $0.confidence >= 0.12 }
            .map { (text: normalized($0.identifier), confidence: $0.confidence) }
        let readableText = textObservations.filter { $0.confidence >= 0.35 && !$0.text.isEmpty }
        let ocrText = readableText.map { normalized($0.text) }.joined(separator: " ")
        let visualText = visual.map(\.text).joined(separator: " ")
        let combined = "\(visualText) \(ocrText)"
        let occasion = normalized(selectedOccasion ?? "")
        let hasReadableText = !readableText.isEmpty
        let brandingTerms = ["logo", "brand mark", "embroider", "monogram", "patch", "name badge"]
        let constructionTerms = ["uniform", "scrub", "workwear", "coverall", "utility shirt", "name badge", "service shirt"]
        let workSupportedTerms = ["work shirt", "polo", "polo shirt", "button down", "patch"]
        let hasBrandingCue = containsAny(combined, brandingTerms)
        let hasExplicitUniformConstruction = containsAny(combined, constructionTerms)
        let hasWorkSupportedConstruction = occasion.contains("work")
            && containsAny(combined, workSupportedTerms)
        let hasUniformConstruction = hasExplicitUniformConstruction || hasWorkSupportedConstruction
        let brandingConfidence = visual
            .filter { observation in
                brandingTerms.contains { containsTerm(observation.text, $0) }
            }
            .map(\.confidence)
            .max() ?? 0
        let constructionConfidence = visual
            .filter { observation in
                (constructionTerms + workSupportedTerms).contains {
                    containsTerm(observation.text, $0)
                }
            }
            .map(\.confidence)
            .max() ?? 0
        let textConfidence = readableText.map(\.confidence).max() ?? 0

        var candidates: [Candidate] = []
        func add(_ category: OutfitCategory, terms: [String], base: Double = 0) {
            let matches = terms.filter { containsTerm(combined, $0) }
            guard !matches.isEmpty || base > 0 else { return }
            let strongest = visual.filter { observation in
                terms.contains { containsTerm(observation.text, $0) }
            }.map(\.confidence).max() ?? 0
            var evidence: [OutfitClassificationEvidence] = []
            if !matches.isEmpty {
                evidence.append(.init(kind: .silhouette, summary: "Visible garment cues support \(category.displayName).", confidence: max(strongest, 0.55)))
            }
            candidates.append(Candidate(category: category, score: min(0.96, base + strongest + Double(matches.count - 1) * 0.08), evidence: evidence))
        }

        add(.medicalScrubs, terms: ["medical scrub", "scrubs", "scrub top", "scrub pants", "hospital uniform"])
        add(.schoolUniform, terms: ["school uniform", "school blazer", "school crest", "student uniform"])
        add(.tuxedo, terms: ["tuxedo", "dinner jacket", "bow tie", "black tie"])
        add(.weddingDress, terms: ["wedding dress", "bridal gown", "bridal dress", "wedding gown"])
        add(.bridesmaidDress, terms: ["bridesmaid", "bridesmaid dress"])
        add(.eveningGown, terms: ["evening gown", "formal gown", "floor length gown", "gown"])
        add(.cocktailDress, terms: ["cocktail dress", "party dress", "semi formal dress"])
        add(.femaleBusinessDress, terms: ["business dress", "professional dress", "office dress", "sheath dress"])
        add(.mensSuit, terms: ["business suit", "three piece suit", "two piece suit", "suit jacket", "suit", "necktie"])
        add(.businessFormal, terms: ["business formal", "formal business", "tailored blazer", "dress shirt"])
        add(.businessCasual, terms: ["business casual", "smart casual", "chino", "loafer", "polo shirt"])
        add(.casualDress, terms: ["casual dress", "sundress", "day dress"])
        add(.traditionalCulturalAttire, terms: ["traditional attire", "cultural attire", "ceremonial", "sari", "saree", "kimono", "hanbok", "kente", "ankara", "agbada", "dashiki", "thobe", "abaya", "kilt"])
        add(.activewear, terms: ["activewear", "workout", "gym wear", "training wear", "running tights", "sports bra", "yoga pants"])
        add(.sportswear, terms: ["sportswear", "sports jersey", "team jersey", "athletic uniform", "football uniform", "basketball uniform"])
        add(.outerwear, terms: ["outerwear", "overcoat", "parka", "raincoat", "winter coat", "jacket"])
        add(.swimwear, terms: ["swimwear", "swimsuit", "bikini", "swim trunks", "bathing suit"])
        add(.footwear, terms: ["shoe", "sneaker", "loafer", "boot", "sandal", "heel"])
        add(.accessories, terms: ["accessory", "handbag", "purse", "watch", "belt", "scarf", "jewelry", "necklace"])

        if hasUniformConstruction {
            var score = 0.32 + (0.25 * constructionConfidence)
            var evidence: [OutfitClassificationEvidence] = [
                .init(kind: .construction, summary: "Uniform or workwear construction cues are visible.", confidence: 0.65)
            ]
            if hasBrandingCue {
                score += 0.16 * brandingConfidence
                evidence.append(.init(kind: .branding, summary: "A visible logo, patch, badge, or embroidered branding cue is present; no brand or wearer identity was inferred.", confidence: brandingConfidence))
            }
            if hasReadableText {
                score += 0.12 * textConfidence
                evidence.append(.init(kind: .visibleText, summary: "Readable garment text is present; raw text and probable names are not retained.", confidence: textConfidence))
            }
            if occasion.contains("work") {
                score += 0.10
                evidence.append(.init(kind: .occasion, summary: "The selected Work occasion supports, but does not independently prove, a uniform context.", confidence: 1))
            }
            candidates.append(Candidate(category: hasBrandingCue ? .brandedWorkwear : .workUniform, score: min(score, 0.94), evidence: evidence))
        }

        if candidates.isEmpty, containsAny(combined, ["shirt", "t shirt", "jeans", "pants", "shorts", "casual"]) {
            add(.casualWear, terms: ["shirt", "t shirt", "jeans", "pants", "shorts", "casual"])
        }

        let ranked = candidates
            .sorted { left, right in left.score == right.score ? left.category.rawValue < right.category.rawValue : left.score > right.score }
        guard let best = ranked.first, best.score >= 0.42 else {
            return .uncertain(selectedOccasion: selectedOccasion)
        }

        let confidenceLevel: OutfitClassificationConfidence = best.score >= 0.82 ? .high : best.score >= 0.55 ? .medium : .low
        let primary = confidenceLevel == .low ? OutfitCategory.otherUncertain : best.category
        let secondary: [OutfitCategory]
        if confidenceLevel == .low {
            secondary = Array(ranked.prefix(3).map(\.category))
        } else {
            secondary = Array(ranked.dropFirst().filter { $0.score >= max(0.42, best.score - 0.20) }.prefix(3).map(\.category))
        }
        let privacySafeText = hasReadableText ? ["readable garment text present"] : []
        let branding = hasBrandingCue ? ["visible logo, patch, badge, or embroidered branding cue"] : []
        let evidence = confidenceLevel == .low
            ? best.evidence + [.init(kind: .uncertainty, summary: "The strongest category evidence is below the confirmation threshold.", confidence: 1 - best.score)]
            : best.evidence

        return OutfitClassificationResult(
            primaryCategory: primary,
            secondaryCategories: secondary,
            confidence: best.score,
            confidenceLevel: confidenceLevel,
            evidence: evidence,
            detectedText: privacySafeText,
            detectedBranding: branding,
            selectedOccasion: selectedOccasion,
            occasionCompatibility: occasionCompatibility(category: primary, selectedOccasion: selectedOccasion),
            userConfirmedCategory: nil,
            scoringProfile: scoringProfile(for: primary)
        )
    }

    static func scoringProfile(for category: OutfitCategory) -> OutfitScoringProfile {
        switch category {
        case .workUniform, .brandedWorkwear, .schoolUniform, .medicalScrubs: return .uniformWorkwear
        case .businessCasual, .businessFormal, .mensSuit, .femaleBusinessDress: return .businessProfessional
        case .tuxedo, .cocktailDress, .eveningGown: return .formalEvent
        case .weddingDress, .bridesmaidDress: return .weddingParty
        case .traditionalCulturalAttire: return .culturalTraditional
        case .sportswear, .activewear: return .athleticPerformance
        case .casualWear, .casualDress: return .casualEveryday
        case .outerwear: return .protectiveOuterwear
        case .swimwear: return .swimwear
        case .footwear, .accessories: return .accessoriesFootwear
        case .otherUncertain: return .uncertain
        }
    }

    static func occasionCompatibility(category: OutfitCategory, selectedOccasion: String?) -> OutfitOccasionCompatibility {
        let occasion = normalized(selectedOccasion ?? "")
        guard !occasion.isEmpty, occasion != "general" else { return .uncertain }
        if occasion.contains("work") {
            switch category {
            case .workUniform, .brandedWorkwear, .medicalScrubs, .businessCasual, .businessFormal, .mensSuit, .femaleBusinessDress:
                return .compatible
            case .schoolUniform, .swimwear, .weddingDress, .bridesmaidDress, .eveningGown:
                return .conflict
            default:
                return .possible
            }
        }
        if occasion.contains("wedding") || occasion.contains("formal") {
            switch category {
            case .weddingDress, .bridesmaidDress, .eveningGown, .cocktailDress, .tuxedo, .mensSuit, .businessFormal, .traditionalCulturalAttire:
                return .compatible
            case .swimwear, .activewear, .sportswear, .schoolUniform, .medicalScrubs:
                return .conflict
            default:
                return .possible
            }
        }
        return .possible
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containsAny(_ text: String, _ terms: [String]) -> Bool {
        terms.contains { containsTerm(text, $0) }
    }

    private static func containsTerm(_ text: String, _ term: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: normalized(term))
        let pattern = #"(?<![\p{L}\p{N}])"# + escaped + #"(?![\p{L}\p{N}])"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

struct OutfitScoreBreakdown: Codable, Equatable {
    let colorHarmony: Int
    let patternBalance: Int
    let fitQuality: Int
    let occasionMatch: Int
    let accessoryUse: Int
}

enum StyleScoreCalibration {
    static let maximumRawScore = 80

    static func rawTotal(
        colorHarmony: Int,
        patternBalance: Int,
        fitQuality: Int,
        accessoryUse: Int
    ) -> Int {
        colorHarmony + patternBalance + fitQuality + accessoryUse
    }

    static func normalizedScore(rawTotal: Int) -> Int {
        let clampedRawTotal = min(maximumRawScore, max(0, rawTotal))
        return Int(round(Double(clampedRawTotal) / Double(maximumRawScore) * 100.0))
    }

    static func fitScore(for assessment: String) -> Int {
        let text = assessment.lowercased()
        let excellentEvidence = [
            "verified excellent fit",
            "excellent fit",
            "exceptional fit",
            "perfect fit"
        ]
        let strongEvidence = [
            "tailored fit evidence",
            "well-fitted",
            "proper fit",
            "clean fit",
            "structured fit",
            "tailored"
        ]
        let partialEvidence = [
            "partial fit evidence",
            "fit partially visible",
            "mostly fitted",
            "visible fit evidence"
        ]
        let poorEvidence = [
            "too tight",
            "too loose",
            "oversized",
            "bunching",
            "dragging",
            "unclear",
            "poor"
        ]

        if excellentEvidence.contains(where: text.contains) { return 25 }
        if strongEvidence.contains(where: text.contains) { return 23 }
        if text.contains("not evaluated") || text.contains("unverified") { return 13 }
        if partialEvidence.contains(where: text.contains) { return 19 }
        if poorEvidence.contains(where: text.contains) { return 8 }
        return 13
    }
}

extension OutfitScoreBreakdown {
    var scoredRawTotal: Int {
        StyleScoreCalibration.rawTotal(
            colorHarmony: colorHarmony,
            patternBalance: patternBalance,
            fitQuality: fitQuality,
            accessoryUse: accessoryUse
        )
    }

    var normalizedScore: Int {
        StyleScoreCalibration.normalizedScore(rawTotal: scoredRawTotal)
    }

    var stylistChatSummary: String {
        [
            "color harmony \(colorHarmony)/25",
            "pattern balance \(patternBalance)/20",
            "fit quality \(fitQuality)/25",
            "accessories \(accessoryUse)/10",
            "raw score \(scoredRawTotal)/80 normalized to \(normalizedScore)/100",
            "occasion is informational and excluded from scoring"
        ].joined(separator: "; ")
    }
}

struct DetectedItemConfidence: Identifiable, Codable {
    let id: UUID
    let item: String
    let confidence: Int

    init(id: UUID = UUID(), item: String, confidence: Int) {
        self.id = id
        self.item = item
        self.confidence = confidence
    }
}

struct ChatGPTStylistSection: Identifiable, Codable {
    let id: UUID
    let title: String
    let body: String

    init(id: UUID = UUID(), title: String, body: String) {
        self.id = id
        self.title = title
        self.body = body
    }
}

struct ClothingRecommendation: Identifiable, Codable {
    let id: UUID
    let category: String
    let title: String
    let reason: String
    let personalization: String

    init(
        id: UUID = UUID(),
        category: String,
        title: String,
        reason: String,
        personalization: String
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.reason = reason
        self.personalization = personalization
    }
}

enum OutfitShareInsightBuilder {
    static let coordinatedFallback = "This outfit is already well coordinated. Small accessory or fit adjustments may improve the score further."

    static func insights(from analysis: OutfitAnalysisResult) -> [String] {
        var insights: [String] = []
        var seen = Set<String>()

        func append(_ insight: String?) {
            guard let insight else { return }
            let normalized = insight.lowercased()
            guard seen.insert(normalized).inserted else { return }
            insights.append(insight)
        }

        for recommendation in analysis.recommendations where insights.count < 3 {
            let evidence = [recommendation.category, recommendation.title, recommendation.reason]
                .joined(separator: " ")
            append(normalizedInsight(from: evidence))
        }

        for suggestion in analysis.suggestions where insights.count < 3 {
            append(normalizedInsight(from: suggestion))
        }

        if insights.count < 2 {
            for recommendation in analysis.recommendations where insights.count < 3 {
                append(safeProducedTitle(recommendation.title))
            }
        }

        return insights.isEmpty ? [coordinatedFallback] : Array(insights.prefix(3))
    }

    private static func normalizedInsight(from evidence: String) -> String? {
        let text = evidence.lowercased()

        if containsAny(text, terms: ["color", "palette", "contrast", "tone", "harmony"]) {
            return "Improve color balance"
        }

        if containsAny(text, terms: ["shoe", "footwear", "sneaker", "loafer", "boot", "sandal", "slipper"]) {
            return "Adjust footwear"
        }

        if containsAny(text, terms: ["accessor", "watch", "belt", "jewelry", "sunglasses", "finishing piece", "premium detail"]) {
            return "Add a matching accessory"
        }

        if containsAny(text, terms: ["formal", "dressier", "polished", "professional", "office", "business"]) {
            return "Replace one item with a more formal option"
        }

        if containsAny(text, terms: ["weather", "season", "temperature", "rain", "warm", "cold", "heat", "breathable", "umbrella", "wind"]) {
            return "Improve seasonal suitability"
        }

        if containsAny(text, terms: ["fit", "tailor", "silhouette", "layer", "sleeve", "waist", "bunch", "hem", "pant", "shirt", "structure", "shape", "proportion"]) {
            return "Improve fit or layering"
        }

        return nil
    }

    private static func safeProducedTitle(_ title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        let sensitiveTerms = [
            "saved size", "size profile", "shirt size", "pants size", "shoe size",
            "waist", "inseam", "profile", "weather:", "city:", "http://", "https://"
        ]

        guard (4...80).contains(trimmed.count),
              !trimmed.contains("\n"),
              !containsAny(lowercased, terms: sensitiveTerms) else {
            return nil
        }

        return trimmed
    }

    private static func containsAny(_ text: String, terms: [String]) -> Bool {
        terms.contains { text.contains($0) }
    }
}

struct RetailProduct: Identifiable {
    let id = UUID()
    let recommendation: String
    let productName: String
    let storeName: String
    let marketplaceCategory: String
    let imageURL: String
    let price: String
    let originalPrice: String
    let salePrice: String
    let saleAlert: String
    let shippingCost: String
    let estimatedDelivery: String
    let bestValueNote: String
    let sizes: String
    let colors: String
    let officialURL: String
    let affiliateURL: String
    let affiliateTrackingID: String
    let matchReason: String

    var soldAndShippedByText: String {
        "Sold and shipped by \(storeName)"
    }

    var retailerResponsibilityText: String {
        "\(storeName) handles checkout, payment, fulfillment, shipping, returns, refunds, and customer service."
    }
}

struct ClosetItem: Identifiable, Codable {
    let id: UUID
    var name: String
    var category: String
    var color: String
    var brand: String
    var size: String
    var occasion: String
    var notes: String

    init(
        id: UUID = UUID(),
        name: String,
        category: String,
        color: String,
        brand: String,
        size: String,
        occasion: String,
        notes: String
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.color = color
        self.brand = brand
        self.size = size
        self.occasion = occasion
        self.notes = notes
    }
}

enum ClosetItemDisplay {
    static func displayName(for item: ClosetItem, profileName: String = UserDefaults.standard.string(forKey: "profileName") ?? "") -> String {
        displayName(name: item.name, category: item.category, color: item.color, profileName: profileName)
    }

    static func displayName(name: String, category: String, color: String, profileName: String = UserDefaults.standard.string(forKey: "profileName") ?? "") -> String {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedColor = color.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedProfileName = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let profileTokens = cleanedProfileName
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
            .filter { $0.count >= 2 }
        let nameMatchesProfile = !cleanedProfileName.isEmpty
            && (
                cleanedName.range(of: cleanedProfileName, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || profileTokens.contains { cleanedName.compare($0, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
            )

        if !cleanedName.isEmpty, !nameMatchesProfile {
            return cleanedName
        }

        if !cleanedColor.isEmpty, !cleanedCategory.isEmpty {
            return "\(cleanedColor) \(cleanedCategory)"
        }

        if !cleanedCategory.isEmpty {
            return cleanedCategory
        }

        return cleanedColor.isEmpty ? "Closet Item" : cleanedColor
    }
}

enum StyleMatchSearchSection: String, CaseIterable, Codable {
    case closet
    case outfitHistory
    case favorites
    case appScreens

    var title: String {
        switch self {
        case .closet:
            return "Closet"
        case .outfitHistory:
            return "Outfit History"
        case .favorites:
            return "Favorites"
        case .appScreens:
            return "App Screens"
        }
    }

    var rank: Int {
        switch self {
        case .closet:
            return 0
        case .outfitHistory:
            return 1
        case .favorites:
            return 2
        case .appScreens:
            return 3
        }
    }
}

struct StyleMatchAppDestination: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let subtitle: String
    let keywords: [String]

    static let defaults: [StyleMatchAppDestination] = [
        StyleMatchAppDestination(id: "scan", title: "Scan Outfit", subtitle: "Open the outfit scanner", keywords: ["camera", "analyze", "score", "photo", "outfit"]),
        StyleMatchAppDestination(id: "closet", title: "Closet", subtitle: "View saved clothing and outfits", keywords: ["wardrobe", "clothes", "shirts", "pants", "items"]),
        StyleMatchAppDestination(id: "shop", title: "Shopping", subtitle: "Find matching clothes and sale items", keywords: ["store", "marketplace", "deals", "sale", "shopping"]),
        StyleMatchAppDestination(id: "ai", title: "AI Stylist", subtitle: "Ask your personal stylist", keywords: ["chat", "assistant", "ask", "style advice", "stylist"]),
        StyleMatchAppDestination(id: "profile", title: "Profile", subtitle: "Account, privacy, sizes, and settings", keywords: ["settings", "privacy", "sizes", "account", "theme"]),
        StyleMatchAppDestination(id: "weather", title: "Weather Styling", subtitle: "Open weather-based outfit advice", keywords: ["weather", "temperature", "rain", "forecast", "live"]),
        StyleMatchAppDestination(id: "favorites", title: "Favorites", subtitle: "Review favorite outfits and saved items", keywords: ["saved", "liked", "heart", "favorite"]),
        StyleMatchAppDestination(id: "settings", title: "Settings", subtitle: "Open app settings and controls", keywords: ["theme", "support", "privacy", "account", "profile"])
    ]
}

struct StyleMatchSearchDocument: Identifiable, Equatable {
    let id: String
    let section: StyleMatchSearchSection
    let title: String
    let subtitle: String
    let keywords: [String]
    let routeID: String
    let recencyDate: Date?
}

struct StyleMatchSearchContext {
    var closetItems: [ClosetItem]
    var outfitMemories: [OutfitMemory]
    var appDestinations: [StyleMatchAppDestination]

    init(
        closetItems: [ClosetItem] = [],
        outfitMemories: [OutfitMemory] = [],
        appDestinations: [StyleMatchAppDestination] = StyleMatchAppDestination.defaults
    ) {
        self.closetItems = closetItems
        self.outfitMemories = outfitMemories
        self.appDestinations = appDestinations
    }
}

protocol SearchIndexService {
    func buildIndex(from context: StyleMatchSearchContext) -> [StyleMatchSearchDocument]
    func search(_ query: String, in context: StyleMatchSearchContext) -> [StyleMatchSearchDocument]
    func recent(in context: StyleMatchSearchContext, limit: Int) -> [StyleMatchSearchDocument]
}

struct DefaultSearchIndexService: SearchIndexService {
    func buildIndex(from context: StyleMatchSearchContext) -> [StyleMatchSearchDocument] {
        let closetDocuments = context.closetItems.map { item in
            StyleMatchSearchDocument(
                id: "closet-\(item.id.uuidString)",
                section: .closet,
                title: item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? item.category : item.name,
                subtitle: [item.color, item.category, item.brand, item.size]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " • "),
                keywords: [item.name, item.category, item.color, item.brand, item.size, item.occasion, item.notes],
                routeID: "closet",
                recencyDate: nil
            )
        }

        let historyDocuments = context.outfitMemories.map { memory in
            StyleMatchSearchDocument(
                id: "outfit-\(memory.id.uuidString)",
                section: .outfitHistory,
                title: memory.detectedStyle.isEmpty ? "Saved Outfit" : memory.detectedStyle,
                subtitle: historySubtitle(for: memory),
                keywords: memory.detectedGarments + memory.colors + [
                    memory.detectedStyle,
                    memory.occasion?.rawValue ?? "",
                    "\(memory.styleScore)",
                    memory.isFavorite ? "favorite" : ""
                ],
                routeID: "scan",
                recencyDate: memory.scanDate
            )
        }

        let favoriteDocuments = context.outfitMemories.filter(\.isFavorite).map { memory in
            StyleMatchSearchDocument(
                id: "favorite-\(memory.id.uuidString)",
                section: .favorites,
                title: memory.detectedStyle.isEmpty ? "Favorite Outfit" : memory.detectedStyle,
                subtitle: historySubtitle(for: memory),
                keywords: memory.detectedGarments + memory.colors + [memory.detectedStyle, "favorite", memory.occasion?.rawValue ?? ""],
                routeID: "scan",
                recencyDate: memory.scanDate
            )
        }

        let appDocuments = context.appDestinations.map { destination in
            StyleMatchSearchDocument(
                id: "app-\(destination.id)",
                section: .appScreens,
                title: destination.title,
                subtitle: destination.subtitle,
                keywords: [destination.title, destination.subtitle] + destination.keywords,
                routeID: destination.id,
                recencyDate: nil
            )
        }

        return closetDocuments + historyDocuments + favoriteDocuments + appDocuments
    }

    func search(_ query: String, in context: StyleMatchSearchContext) -> [StyleMatchSearchDocument] {
        let normalizedQuery = query.styleMatchSearchNormalized
        guard !normalizedQuery.isEmpty else {
            return recent(in: context, limit: 8)
        }

        return buildIndex(from: context)
            .compactMap { document -> (StyleMatchSearchDocument, Int)? in
                guard let matchRank = matchRank(for: document, query: normalizedQuery) else {
                    return nil
                }

                return (document, matchRank)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                if lhs.0.section.rank != rhs.0.section.rank { return lhs.0.section.rank < rhs.0.section.rank }
                let lhsDate = lhs.0.recencyDate ?? .distantPast
                let rhsDate = rhs.0.recencyDate ?? .distantPast
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                return lhs.0.title.localizedCaseInsensitiveCompare(rhs.0.title) == .orderedAscending
            }
            .map(\.0)
    }

    func recent(in context: StyleMatchSearchContext, limit: Int) -> [StyleMatchSearchDocument] {
        let index = buildIndex(from: context)
        let recents = index
            .filter { $0.section != .appScreens }
            .sorted { ($0.recencyDate ?? .distantPast) > ($1.recencyDate ?? .distantPast) }
            .prefix(limit)

        if recents.isEmpty {
            return Array(index.filter { $0.section == .appScreens }.prefix(limit))
        }

        return Array(recents)
    }

    private func matchRank(for document: StyleMatchSearchDocument, query: String) -> Int? {
        let normalizedTitle = document.title.styleMatchSearchNormalized
        let searchableText = ([document.subtitle] + document.keywords)
            .map(\.styleMatchSearchNormalized)
            .filter { !$0.isEmpty }

        if normalizedTitle == query {
            return 0
        }

        if normalizedTitle.hasPrefix(query) {
            return 1
        }

        if searchableText.contains(where: { $0 == query || $0.hasPrefix(query) }) {
            return 2
        }

        return ([normalizedTitle] + searchableText).contains(where: { $0.contains(query) }) ? 3 : nil
    }

    private func historySubtitle(for memory: OutfitMemory) -> String {
        var parts = [String]()
        if !memory.colors.isEmpty {
            parts.append(memory.colors.prefix(3).joined(separator: ", "))
        }
        if let occasion = memory.occasion {
            parts.append(occasion.rawValue)
        }
        parts.append("\(memory.styleScore)/100")
        return parts.joined(separator: " • ")
    }
}

struct StyleMatchHomeScoreBand: Equatable {
    let stars: Int
    let title: String
}

enum StyleMatchHomeRecommendationDestination: Equatable {
    case closet
}

enum StyleMatchHomeDisplay {
    static func recommendationDestination(closetItemCount: Int) -> StyleMatchHomeRecommendationDestination? {
        closetItemCount == 0 ? .closet : nil
    }

    static func scoreBand(for score: Int) -> StyleMatchHomeScoreBand {
        switch min(100, max(0, score)) {
        case 90...100:
            return StyleMatchHomeScoreBand(stars: 5, title: "Excellent Match")
        case 75...89:
            return StyleMatchHomeScoreBand(stars: 4, title: "Good Match")
        case 60...74:
            return StyleMatchHomeScoreBand(stars: 3, title: "Fair Match")
        case 40...59:
            return StyleMatchHomeScoreBand(stars: 2, title: "Needs Styling")
        default:
            return StyleMatchHomeScoreBand(stars: 1, title: "Low Match")
        }
    }

    static func itemCountText(_ count: Int) -> String {
        countText(count, singular: "item")
    }

    static func closetItemLabel(_ count: Int) -> String {
        countText(count, singular: "Closet Item")
    }

    static func countText(_ count: Int, singular: String, plural: String? = nil) -> String {
        "\(count) \(count == 1 ? singular : (plural ?? "\(singular)s"))"
    }

    static func starSystemName(index: Int, for score: Int) -> String {
        index <= scoreBand(for: score).stars ? "star.fill" : "star"
    }

    static func sanitizedClosetItemLabel(name: String, color: String, userName: String?) -> String? {
        let sanitizedName = removeUserName(from: name, userName: userName)
        let sanitizedColor = removeUserName(from: color, userName: userName)

        let parts = [sanitizedColor, sanitizedName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " ")
    }

    static func removeUserName(from value: String, userName: String?) -> String {
        var cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawName = userName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawName.isEmpty else {
            return cleaned
        }

        let nameTokens = rawName
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: CharacterSet.alphanumerics.inverted) }
            .filter { $0.count >= 2 }

        for token in Set(nameTokens + [rawName]) {
            let escaped = NSRegularExpression.escapedPattern(for: token)
            cleaned = cleaned.replacingOccurrences(
                of: "\\b\(escaped)\\b",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        return cleaned
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "-_,•")))
    }
}

enum StyleMatchAccessibilityText {
    static func scanResultSummary(
        score: Int,
        rating: String,
        categoryScores: [String],
        detectedItems: [String],
        recommendations: [String]
    ) -> String {
        var parts = ["Overall StyleMatch score, \(score) out of 100, \(rating)"]
        if !categoryScores.isEmpty {
            parts.append("Category scores: \(categoryScores.joined(separator: ", "))")
        }
        if !detectedItems.isEmpty {
            parts.append("Detected items: \(detectedItems.joined(separator: ", "))")
        }
        if !recommendations.isEmpty {
            parts.append("Recommendations: \(recommendations.joined(separator: "; "))")
        }
        return parts.joined(separator: ". ")
    }

    static func shoppingProductSummary(
        name: String,
        retailer: String,
        price: String,
        saleStatus: String?,
        isFavorite: Bool,
        isWishlist: Bool,
        action: String
    ) -> String {
        [
            name,
            "Retailer: \(retailer)",
            "Price: \(price)",
            saleStatus.map { "Sale status: \($0)" } ?? "Not marked on sale",
            isFavorite ? "Favorite" : "Not favorite",
            isWishlist ? "In wishlist" : "Not in wishlist",
            "Action: \(action)"
        ].joined(separator: ". ")
    }

    static func chatMessageLabel(role: String, content: String) -> String {
        "\(role): \(content.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    static func profileFieldLabel(title: String, isRequired: Bool) -> String {
        "\(title), \(isRequired ? "required" : "optional")"
    }

    static func profileFieldValue(text: String, validationMessage: String? = nil) -> String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = value.isEmpty ? "Not provided" : value
        guard let validationMessage,
              !validationMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return current
        }
        return "\(current). \(validationMessage)"
    }
}

private extension String {
    var styleMatchSearchNormalized: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
