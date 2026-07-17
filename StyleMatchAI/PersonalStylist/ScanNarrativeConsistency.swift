import Foundation

struct ScanNarrativeFacts: Equatable {
    // Garment-specific narrative claims require the same high-confidence evidence
    // already used by the stylist composer; lower-confidence labels stay generic.
    static let authoritativeGarmentConfidence = 90

    let palette: [String]
    let qualifiedGarments: [String]
    let verifiedClosetRecordIDs: Set<UUID>
    let weatherEvidence: [String]

    init(
        palette: [String],
        detectedGarments: [String],
        detectedItemConfidences: [DetectedItemConfidence],
        verifiedClosetRecordIDs: Set<UUID> = [],
        weatherEvidence: [String] = []
    ) {
        self.palette = Self.stableTerms(palette)
        self.qualifiedGarments = Self.qualifiedGarments(
            detectedGarments: detectedGarments,
            confidences: detectedItemConfidences
        )
        self.verifiedClosetRecordIDs = verifiedClosetRecordIDs
        self.weatherEvidence = weatherEvidence
    }

    var paletteDescription: String? {
        guard !palette.isEmpty else { return nil }
        if palette.count == 1 { return palette[0] }
        if palette.count == 2 { return "\(palette[0])-and-\(palette[1])" }
        return palette.dropLast().joined(separator: ", ") + ", and " + (palette.last ?? "")
    }

    private static func qualifiedGarments(
        detectedGarments: [String],
        confidences: [DetectedItemConfidence]
    ) -> [String] {
        let stored = Set(detectedGarments.compactMap(GarmentLabelMapper.humanReadableTerm))
        let qualified = confidences
            .filter { $0.confidence >= authoritativeGarmentConfidence }
            .compactMap { GarmentLabelMapper.humanReadableTerm(for: $0.item) }
            .filter(stored.contains)
        return stableTerms(qualified)
    }

    private static func stableTerms(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !cleaned.isEmpty, seen.insert(cleaned).inserted else { return nil }
            return cleaned
        }
    }
}

enum ScanNarrativeConsistencyValidator {
    private static let knownColors: Set<String> = [
        "black", "white", "gray", "grey", "charcoal", "silver", "cream", "ivory",
        "beige", "tan", "camel", "brown", "chocolate", "navy", "blue", "teal",
        "cyan", "green", "olive", "yellow", "gold", "orange", "red", "burgundy",
        "maroon", "pink", "purple", "lavender", "violet"
    ]
    private static let knownGarments: Set<String> = [
        "t-shirt", "shirt", "polo", "blouse", "sweater", "hoodie", "jacket", "blazer",
        "coat", "shacket", "top", "bottom", "bottoms", "pants", "trousers", "jeans", "shorts", "skirt", "dress",
        "suit", "robe", "sleepwear", "shoes", "sneakers", "loafers", "heels", "boots",
        "hat", "scarf", "belt", "bag"
    ]
    private static let factualGarmentMarkers = [
        "detected", "scanned outfit", "outfit includes", "outfit contains", "outfit has",
        "you are wearing", "you're wearing", "from this scan"
    ]
    private static let factualColorMarkers = factualGarmentMarkers + ["detected palette", "palette is", "palette includes"]
    private static let weatherTermGroups = [
        ["rain", "rainy", "raining", "showers"],
        ["snow", "snowy", "snowing"],
        ["cloudy", "overcast"],
        ["sunny", "clear"],
        ["wind", "windy"],
        ["humid", "humidity"]
    ]
    private static let factualWeatherMarkers = [
        "today", "currently", "forecast", "weather is", "condition is",
        "temperature", "humidity", "rain chance", "wind is"
    ]
    private static let closetMarkerPattern = #"(?i)\[\[closet-item:([0-9a-f-]{36})\]\]"#
    private static let actionableAdviceVerbs: Set<String> = [
        "add", "choose", "consider", "keep", "layer", "opt", "pair", "skip", "swap", "try", "use", "wear"
    ]

    static func validate(
        _ sections: [ChatGPTStylistSection],
        facts: ScanNarrativeFacts
    ) -> [ChatGPTStylistSection] {
        var seenSentences = Set<String>()
        return sections.compactMap { section in
            let retained = sentences(in: section.body).compactMap { sentence -> String? in
                guard let validated = validateSentence(sentence, facts: facts) else { return nil }
                let key = normalizedSentenceKey(validated)
                guard !key.isEmpty, seenSentences.insert(key).inserted else { return nil }
                return validated
            }
            guard !retained.isEmpty else { return nil }
            return ChatGPTStylistSection(id: section.id, title: section.title, body: retained.joined(separator: " "))
        }
    }

    static func paletteAnchor(for facts: ScanNarrativeFacts) -> String? {
        facts.paletteDescription.map { "the detected \($0) palette" }
    }

    private static func validateSentence(_ rawSentence: String, facts: ScanNarrativeFacts) -> String? {
        var sentence = rawSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else { return nil }

        if containsUnsupportedColor(in: sentence, facts: facts)
            || containsUnsupportedFactualGarment(in: sentence, facts: facts) {
            guard let safeAdvice = actionableAdviceSuffix(in: sentence) else { return nil }
            sentence = safeAdvice
        }

        guard !containsUnsupportedColor(in: sentence, facts: facts),
              !containsUnsupportedFactualGarment(in: sentence, facts: facts) else { return nil }

        if sentence.lowercased().contains("from your closet") {
            guard let recordID = closetRecordID(in: sentence),
                  facts.verifiedClosetRecordIDs.contains(recordID) else {
                return nil
            }
            sentence = sentence.replacingOccurrences(
                of: "[[closet-item:\(recordID.uuidString)]]",
                with: "",
                options: [.caseInsensitive]
            )
            sentence = sentence.replacingOccurrences(of: "  ", with: " ")
        }

        guard weatherClaimIsSupported(sentence, by: facts.weatherEvidence) else { return nil }
        return sentence.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containsUnsupportedColor(in sentence: String, facts: ScanNarrativeFacts) -> Bool {
        let lower = sentence.lowercased()
        guard factualColorMarkers.contains(where: lower.contains) else { return false }
        let mentioned = tokens(in: lower).filter(knownColors.contains)
        let allowed = Set(facts.palette.flatMap { paletteAliases(for: $0) })
        return !mentioned.allSatisfy(allowed.contains)
    }

    private static func containsUnsupportedFactualGarment(in sentence: String, facts: ScanNarrativeFacts) -> Bool {
        let lower = sentence.lowercased()
        guard factualGarmentMarkers.contains(where: lower.contains) else { return false }
        let mentioned = tokens(in: lower).filter(knownGarments.contains)
        let allowed = Set(facts.qualifiedGarments.flatMap(garmentAliases(for:)))
        return !mentioned.allSatisfy(allowed.contains)
    }

    private static func actionableAdviceSuffix(in sentence: String) -> String? {
        for separator in [", so ", "; so ", "; "] {
            guard let range = sentence.range(of: separator, options: [.caseInsensitive]) else { continue }
            let suffix = sentence[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let first = tokens(in: suffix.lowercased()).first,
                  actionableAdviceVerbs.contains(first) else { continue }
            return suffix.prefix(1).uppercased() + suffix.dropFirst()
        }
        return nil
    }

    private static func weatherClaimIsSupported(_ sentence: String, by evidence: [String]) -> Bool {
        let lower = sentence.lowercased()
        let evidenceText = evidence.joined(separator: " ").lowercased()
        let compactEvidence = evidenceText.replacingOccurrences(of: " ", with: "")
        guard measuredClaims(in: lower).allSatisfy({ compactEvidence.contains($0) }) else { return false }

        guard factualWeatherMarkers.contains(where: lower.contains) else { return true }
        let sentenceTokens = Set(tokens(in: lower))
        let evidenceTokens = Set(tokens(in: evidenceText))
        return weatherTermGroups.allSatisfy { aliases in
            sentenceTokens.isDisjoint(with: aliases) || !evidenceTokens.isDisjoint(with: aliases)
        }
    }

    private static func measuredClaims(in text: String) -> [String] {
        let pattern = #"\b\d{1,3}\s*(?:°\s*[fc]?|%|mph)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]).replacingOccurrences(of: " ", with: "") }
        }
    }

    private static func closetRecordID(in text: String) -> UUID? {
        guard let regex = try? NSRegularExpression(pattern: closetMarkerPattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              match.numberOfRanges == 2,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return UUID(uuidString: String(text[range]))
    }

    private static func sentences(in text: String) -> [String] {
        var values: [String] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.bySentences, .substringNotRequired]) { _, range, _, _ in
            values.append(String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return values.isEmpty ? [text] : values
    }

    private static func normalizedSentenceKey(_ sentence: String) -> String {
        sentence
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))
    }

    private static func tokens(in text: String) -> [String] {
        text.split { !$0.isLetter }.map(String.init)
    }

    private static func paletteAliases(for color: String) -> [String] {
        switch color {
        case "gray", "grey": return ["gray", "grey"]
        default: return [color]
        }
    }

    private static func garmentAliases(for garment: String) -> [String] {
        var aliases = tokens(in: garment)
        if garment == "polo shirt" { aliases.append("polo") }
        if garment == "button-down shirt" { aliases.append("shirt") }
        if ["t-shirt", "polo shirt", "button-down shirt", "shirt", "blouse", "sweater", "hoodie", "jacket", "blazer", "coat", "shacket"].contains(garment) {
            aliases.append("top")
        }
        if ["pants", "trousers", "jeans", "shorts", "skirt"].contains(garment) {
            aliases.append(contentsOf: ["bottom", "bottoms"])
        }
        return aliases
    }
}
