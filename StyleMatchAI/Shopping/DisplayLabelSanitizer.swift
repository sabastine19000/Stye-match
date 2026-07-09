import Foundation

enum WornRecency: Equatable {
    case today
    case yesterday
    case recent
    case text(String)

    var phrase: String {
        switch self {
        case .today:
            return "today"
        case .yesterday:
            return "yesterday"
        case .recent:
            return "recently"
        case .text(let value):
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return clean.isEmpty ? "recently" : clean
        }
    }
}

enum DisplayColorProvenance {
    case garmentRegion
    case fullPerson
    case fullImage
    case unknown
}

enum DisplayLabelSanitizer {
    private static var reportedLabels = Set<String>()

    private static let blocklistedTerms: [String] = [
        "person wearing outfit",
        "person wearing",
        "person",
        "textile",
        "clothing",
        "apparel",
        "garment",
        "fabric"
    ]

    private static let displayTerms: [String: String] = [
        "bag": "bag",
        "belt": "belt",
        "blazer": "blazer",
        "boot": "boots",
        "boots": "boots",
        "button down": "button-down shirt",
        "button-down": "button-down shirt",
        "cardigan": "cardigan",
        "chino": "chinos",
        "chinos": "chinos",
        "coat": "coat",
        "dress": "dress",
        "dress shirt": "dress shirt",
        "denim trousers": "jeans",
        "handbag": "handbag",
        "hat": "hat",
        "hoodie": "hoodie",
        "jacket": "jacket",
        "jean": "jeans",
        "jeans": "jeans",
        "loafer": "loafers",
        "loafers": "loafers",
        "oxford": "oxford shirt",
        "oxford shirt": "oxford shirt",
        "pant": "pants",
        "pants": "pants",
        "polo": "polo shirt",
        "polo shirt": "polo shirt",
        "shirt": "shirt",
        "shoe": "shoes",
        "shoes": "shoes",
        "shorts": "shorts",
        "skirt": "skirt",
        "slacks": "slacks",
        "sneaker": "sneakers",
        "sneakers": "sneakers",
        "sweater": "sweater",
        "tee": "t-shirt",
        "t-shirt": "t-shirt",
        "t shirt": "t-shirt",
        "tank": "tank top",
        "trouser": "trousers",
        "trousers": "trousers",
        "watch": "watch"
    ]

    static func displayName(for rawLabel: String) -> String? {
        let normalized = normalize(rawLabel)
        guard !normalized.isEmpty else { return nil }

        if isBlocked(normalized) {
            report(normalized, reason: "blocked")
            return nil
        }

        if let exact = displayTerms[normalized] {
            return exact
        }

        let tokenMatch = displayTerms
            .filter { normalized.contains($0.key) }
            .sorted { $0.key.count > $1.key.count }
            .first?.value

        if let tokenMatch {
            return tokenMatch
        }

        report(normalized, reason: "allowlist_miss")
        return nil
    }

    static func wornItemPhrase(rawLabel: String, colorName: String?, recency: WornRecency) -> String {
        wornItemPhrase(
            rawLabel: rawLabel,
            colorName: colorName,
            colorProvenance: .garmentRegion,
            recency: recency
        )
    }

    static func wornItemPhrase(
        rawLabel: String,
        colorName: String?,
        colorProvenance: DisplayColorProvenance,
        recency: WornRecency
    ) -> String {
        guard let displayName = displayName(for: rawLabel) else {
            switch recency {
            case .today:
                return "what you wore today"
            case .yesterday:
                return "what you wore yesterday"
            case .recent:
                return "a recent outfit"
            case .text(let text):
                return text.localizedCaseInsensitiveContains("yesterday") ? "what you wore yesterday" : "a recent outfit"
            }
        }

        let color = sanitizedColor(colorName, provenance: colorProvenance)
        let descriptor = color.map { "\($0) \(displayName)" } ?? displayName
        return "the \(descriptor) you wore \(recency.phrase)"
    }

    static func safeColorName(_ colorName: String?, provenance: DisplayColorProvenance = .garmentRegion) -> String? {
        sanitizedColor(colorName, provenance: provenance)
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
    }

    private static func isBlocked(_ normalized: String) -> Bool {
        let tokens = Set(normalized.split(separator: " ").map(String.init))
        return normalized.contains("wearing")
            || blocklistedTerms.contains(normalized)
            || blocklistedTerms.contains(where: { tokens.contains($0) })
    }

    private static func sanitizedColor(_ value: String?, provenance: DisplayColorProvenance) -> String? {
        guard provenance == .garmentRegion else { return nil }
        let clean = (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !clean.isEmpty else { return nil }
        guard !isBlocked(clean), clean.count <= 20 else { return nil }
        return clean
    }

    private static func report(_ label: String, reason: String) {
        #if DEBUG
        guard reportedLabels.insert("\(reason):\(label)").inserted else { return }
        print("[StyleMatch Shopping LabelSanitizer] \(reason): \(label)")
        #endif
    }
}
