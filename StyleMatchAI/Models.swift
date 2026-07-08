import Foundation

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
    let environment: String
    let imageQuality: String
    let skinToneStyleNote: String
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
        environment: String,
        imageQuality: String,
        skinToneStyleNote: String,
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
        self.detectedClothingItems = GarmentLabelMapper.sanitizedTerms(from: detectedClothingItems, fallback: "outfit item")
        self.colorPalette = colorPalette
        self.colorPaletteMaskingApplied = colorPaletteMaskingApplied
        self.colorPaletteMaskTier = colorPaletteMaskTier
        self.environment = environment
        self.imageQuality = imageQuality
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
            from: try container.decode([String].self, forKey: .detectedClothingItems),
            fallback: "outfit item"
        )
        colorPalette = try container.decode([String].self, forKey: .colorPalette)
        colorPaletteMaskingApplied = try container.decodeIfPresent(Bool.self, forKey: .colorPaletteMaskingApplied) ?? true
        colorPaletteMaskTier = try container.decodeIfPresent(String.self, forKey: .colorPaletteMaskTier)
        environment = try container.decode(String.self, forKey: .environment)
        imageQuality = try container.decode(String.self, forKey: .imageQuality)
        skinToneStyleNote = try container.decode(String.self, forKey: .skinToneStyleNote)
        detectedItemConfidences = try container.decodeIfPresent([DetectedItemConfidence].self, forKey: .detectedItemConfidences) ?? []
        chatGPTStylistSections = try container.decodeIfPresent([ChatGPTStylistSection].self, forKey: .chatGPTStylistSections) ?? []
        suggestions = try container.decode([String].self, forKey: .suggestions)
        recommendations = try container.decode([ClothingRecommendation].self, forKey: .recommendations)
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
        GarmentLabelMapper.sanitizedTerms(from: detectedClothingItems, fallback: "outfit item")
    }
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

struct OutfitScoreBreakdown: Codable {
    let colorHarmony: Int
    let patternBalance: Int
    let fitQuality: Int
    let occasionMatch: Int
    let accessoryUse: Int
}

extension OutfitScoreBreakdown {
    var stylistChatSummary: String {
        [
            "color harmony \(colorHarmony)/25",
            "pattern balance \(patternBalance)/20",
            "fit quality \(fitQuality)/25",
            "occasion match \(occasionMatch)/20",
            "accessories \(accessoryUse)/10"
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

private extension String {
    var styleMatchSearchNormalized: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
