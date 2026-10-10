import Foundation
import ImageIO

/// Presentation-only normalization for provider text. Conversation persistence
/// retains the sanitized transport text; rendering must not expose raw Markdown
/// markers or HTML-like tags as visible chat content.
enum StylistChatPresentation {
    static func displayText(_ source: String) -> String {
        source
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
    }
}

enum StylistChatRole: String, Codable, Equatable {
    case user
    case assistant
    case system
}

struct ChatMessage: Identifiable, Codable, Equatable {
    var id: UUID
    var role: StylistChatRole
    var content: String
    var timestamp: Date
    /// The authoritative scan used when this turn was created. Optional for
    /// backward-compatible decoding of conversations saved by older builds.
    var scanContextID: String?
    /// Present only when the request supplied canonical WeatherKit context.
    /// It lets the rendered assistant turn retain Apple attribution provenance.
    var weatherAttribution: WeatherAttributionMetadata?
    /// Local-only identity for a deterministic reply produced before transport.
    /// It is retained with the current conversation solely to reconstruct
    /// thread-local clarification state; request encoding never reads it.
    var localSemanticResponseID: StylistSemanticResponseID?

    init(
        id: UUID = UUID(),
        role: StylistChatRole,
        content: String,
        timestamp: Date = Date(),
        scanContextID: String? = nil,
        weatherAttribution: WeatherAttributionMetadata? = nil,
        localSemanticResponseID: StylistSemanticResponseID? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.scanContextID = scanContextID
        self.weatherAttribution = weatherAttribution
        self.localSemanticResponseID = localSemanticResponseID
    }
}

/// A conversation has one authority boundary for its lifetime. Associated scan
/// identifiers are opaque local record identifiers, never image references.
enum StylistConversationScope: Equatable, Codable {
    case generalStylist
    /// A request-scoped Home, Closet, Profile, or Product conversation. It
    /// intentionally carries no entity or route metadata and is never durable.
    case contextualStylist
    case activeScan(scanID: String)
    case savedScan(scanID: String)

    private enum CodingKeys: String, CodingKey { case kind, scanID }
    private enum Kind: String, Codable { case generalStylist, contextualStylist, activeScan, savedScan }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .generalStylist {
        case .generalStylist:
            self = .generalStylist
        case .contextualStylist:
            self = .contextualStylist
        case .activeScan:
            guard let scanID = try container.decodeIfPresent(String.self, forKey: .scanID), !scanID.isEmpty else {
                self = .generalStylist
                return
            }
            self = .activeScan(scanID: scanID)
        case .savedScan:
            guard let scanID = try container.decodeIfPresent(String.self, forKey: .scanID), !scanID.isEmpty else {
                self = .generalStylist
                return
            }
            self = .savedScan(scanID: scanID)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .generalStylist:
            try container.encode(Kind.generalStylist, forKey: .kind)
        case .contextualStylist:
            try container.encode(Kind.contextualStylist, forKey: .kind)
        case let .activeScan(scanID):
            try container.encode(Kind.activeScan, forKey: .kind)
            try container.encode(scanID, forKey: .scanID)
        case let .savedScan(scanID):
            try container.encode(Kind.savedScan, forKey: .kind)
            try container.encode(scanID, forKey: .scanID)
        }
    }

    var scanID: String? {
        switch self {
        case .generalStylist, .contextualStylist: nil
        case let .activeScan(scanID), let .savedScan(scanID): scanID
        }
    }

    var isScanBound: Bool { scanID != nil }
    var isContextual: Bool {
        if case .contextualStylist = self { return true }
        return false
    }
}

/// Local-only persistence classification. It is deliberately separate from
/// request context and must never be serialized to the chat transport.
enum StylistConversationClassification: String, Codable, Equatable {
    case verifiedGeneral
    case contextualEphemeral
    case legacyUnverified
    case scanBound
}

/// Privacy-safe, immutable facts copied from an explicitly selected completed
/// scan. Raw images, OCR, names, logos, and inferred garment-color mappings
/// are deliberately absent.
struct StylistConversationScanContext: Codable, Equatable {
    let scanID: String
    let score: Int
    let scoreBand: String
    let detectedStyle: String?
    let topStyleMatches: [String]
    let palette: [String]
    let outfitType: String?
    let selectedOccasion: String?
    let reliableWeatherSummary: String?
    let evidenceLimitations: [String]
    let analyzedAt: Date?

    init(authoritativeScan: StylistAuthoritativeScanContext) {
        scanID = authoritativeScan.scanID
        score = authoritativeScan.overallScore
        scoreBand = StyleMatchHomeDisplay.scoreBand(for: authoritativeScan.overallScore).title
        detectedStyle = authoritativeScan.detectedStyle
        topStyleMatches = Array((authoritativeScan.topStyleMatches ?? []).prefix(3))
        palette = Array((authoritativeScan.palette ?? []).prefix(5))
        outfitType = authoritativeScan.outfitType ?? authoritativeScan.outfitClassification?.effectiveCategory.displayName
        selectedOccasion = authoritativeScan.selectedOccasion
        reliableWeatherSummary = authoritativeScan.reliableWeatherSummary
        evidenceLimitations = Array((authoritativeScan.evidenceLimitations ?? []).prefix(3))
        analyzedAt = authoritativeScan.completedAt
    }

    var authoritativeScan: StylistAuthoritativeScanContext {
        StylistAuthoritativeScanContext(
            scanID: scanID,
            completedAt: analyzedAt ?? .distantPast,
            overallScore: score,
            scoreBreakdown: nil,
            detectedStyle: detectedStyle,
            selectedOccasion: selectedOccasion,
            weatherContext: reliableWeatherSummary,
            source: .savedSelection,
            palette: palette,
            topStyleMatches: topStyleMatches,
            evidenceLimitations: evidenceLimitations,
            reliableWeatherSummary: reliableWeatherSummary,
            outfitType: outfitType
        )
    }
}

struct ChatConversation: Identifiable, Codable, Equatable {
    var id: UUID
    var messages: [ChatMessage]
    var createdAt: Date
    var updatedAt: Date
    var scope: StylistConversationScope
    var scanContext: StylistConversationScanContext?
    var classification: StylistConversationClassification

    init(
        id: UUID = UUID(),
        messages: [ChatMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        scope: StylistConversationScope = .generalStylist,
        scanContext: StylistConversationScanContext? = nil,
        classification: StylistConversationClassification? = nil
    ) {
        self.id = id
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.scope = scope
        self.scanContext = scope.isScanBound ? scanContext : nil
        self.classification = classification ?? Self.defaultClassification(for: scope)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        messages = try container.decodeIfPresent([ChatMessage].self, forKey: .messages) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        scope = try container.decodeIfPresent(StylistConversationScope.self, forKey: .scope) ?? .generalStylist
        scanContext = try container.decodeIfPresent(StylistConversationScanContext.self, forKey: .scanContext)
        let decodedClassification = try container.decodeIfPresent(
            StylistConversationClassification.self,
            forKey: .classification
        )
        if scope.isScanBound == false {
            scanContext = nil
        }
        if scope.isScanBound {
            classification = .scanBound
        } else if scope.isContextual {
            classification = .contextualEphemeral
        } else {
            // Older persisted general conversations did not record whether
            // they originated from a contextual route. Keep them locally but
            // do not treat them as safe General authority.
            classification = decodedClassification == .verifiedGeneral
                ? .verifiedGeneral
                : .legacyUnverified
        }
    }

    var isVerifiedGeneral: Bool {
        scope == .generalStylist && classification == .verifiedGeneral
    }

    var isPersistable: Bool {
        isVerifiedGeneral || scope.isScanBound
    }

    var isEligibleForAutomaticResume: Bool {
        isVerifiedGeneral || scope.isScanBound
    }

    var isSelectableFromHistory: Bool {
        isVerifiedGeneral || scope.isScanBound
    }

    private static func defaultClassification(for scope: StylistConversationScope) -> StylistConversationClassification {
        if scope.isScanBound { return .scanBound }
        if scope.isContextual { return .contextualEphemeral }
        return .verifiedGeneral
    }
}

enum StylistScreenTab: String, Codable, Equatable {
    case home
    case scan
    case closet
    case shop
    case ai
    case profile
    case weather
}

/// A deliberately small, app-owned description of the visible surface that
/// initiated a context-aware Stylist request. It is navigation-scoped rather
/// than a record of everything a person has viewed.
enum StylistScreenSurfaceKind: String, Codable, Equatable, Sendable {
    case home
    case liveScan = "live_scan"
    case savedScan = "saved_scan"
    case scanComparison = "scan_comparison"
    case closet
    case shopping
    case aiStylist = "ai_stylist"
    case profile
    case settings
    case scoreDetails = "score_details"
    case sharedOutfit = "shared_outfit"
    case calendar
    case weather
    case favorites
    case unsupported
}

enum StylistScreenResultState: String, Codable, Equatable, Sendable {
    case live
    case saved
    case historical
}

enum StylistNavigationOrigin: String, Codable, Equatable, Sendable {
    case direct
    case tab
    case scanResult = "scan_result"
    case savedHistory = "saved_history"
    case detail
    case sheet
    case sharedLink = "shared_link"
    case unknown
}

/// This descriptor contains identifiers and labels only. It must never carry
/// pixels, image data, raw OCR, keyboard content, hidden-view state, calendar
/// events, or data from another app.
struct StylistScreenSurfaceDescriptor: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let screenKind: StylistScreenSurfaceKind
    let visibleSheetKind: String?
    let navigationOrigin: StylistNavigationOrigin
    let selectedLocalRecordID: String?
    let selectedItemID: String?
    let selectedProductID: String?
    let selectedActionID: String?
    let resultState: StylistScreenResultState?
    let contextGeneration: UInt64
    let createdAt: Date

    init(
        screenKind: StylistScreenSurfaceKind,
        visibleSheetKind: String? = nil,
        navigationOrigin: StylistNavigationOrigin = .unknown,
        selectedLocalRecordID: String? = nil,
        selectedItemID: String? = nil,
        selectedProductID: String? = nil,
        selectedActionID: String? = nil,
        resultState: StylistScreenResultState? = nil,
        contextGeneration: UInt64 = 0,
        createdAt: Date = Date(),
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = max(1, schemaVersion)
        self.screenKind = screenKind
        self.visibleSheetKind = Self.bounded(visibleSheetKind)
        self.navigationOrigin = navigationOrigin
        self.selectedLocalRecordID = Self.bounded(selectedLocalRecordID)
        self.selectedItemID = Self.bounded(selectedItemID)
        self.selectedProductID = Self.bounded(selectedProductID)
        self.selectedActionID = Self.bounded(selectedActionID)
        self.resultState = resultState
        self.contextGeneration = contextGeneration
        self.createdAt = createdAt
    }

    private static func bounded(_ value: String?) -> String? {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.isEmpty ? nil : String(normalized.prefix(128))
    }
}

/// Explicit, stateless constructors for app-owned surfaces. They deliberately
/// accept only IDs, a visible label, and navigation state; adapters never
/// receive a complete store, image, OCR payload, or raw Calendar event.
enum StylistScreenSurfaceAdapters {
    static func home(cardID: String?, generation: UInt64, now: Date = Date()) -> StylistScreenSurfaceDescriptor {
        surface(.home, recordID: cardID, actionID: cardID, origin: .tab, generation: generation, now: now)
    }

    static func liveScan(scanID: String?, generation: UInt64, now: Date = Date()) -> StylistScreenSurfaceDescriptor {
        surface(.liveScan, recordID: scanID, origin: .scanResult, resultState: .live, generation: generation, now: now)
    }

    static func savedScan(scanID: String, generation: UInt64, now: Date = Date()) -> StylistScreenSurfaceDescriptor {
        surface(.savedScan, recordID: scanID, origin: .savedHistory, resultState: .saved, generation: generation, now: now)
    }
    static func scanComparison(newerScanID: String, generation: UInt64, now: Date = Date()) -> StylistScreenSurfaceDescriptor {
        surface(.scanComparison, recordID: newerScanID, origin: .detail, resultState: .saved, generation: generation, now: now)
    }

    static func closet(itemID: String, generation: UInt64, now: Date = Date()) -> StylistScreenSurfaceDescriptor {
        surface(.closet, itemID: itemID, origin: .detail, generation: generation, now: now)
    }

    static func shopping(productID: String, generation: UInt64, now: Date = Date()) -> StylistScreenSurfaceDescriptor {
        surface(.shopping, productID: productID, origin: .detail, generation: generation, now: now)
    }

    static func profile(sectionID: String, generation: UInt64, now: Date = Date()) -> StylistScreenSurfaceDescriptor {
        surface(.profile, actionID: sectionID, origin: .detail, generation: generation, now: now)
    }

    static func settings(sectionID: String, generation: UInt64, now: Date = Date()) -> StylistScreenSurfaceDescriptor {
        surface(.settings, actionID: sectionID, origin: .detail, generation: generation, now: now)
    }

    static func scoreDetails(scanID: String, componentID: String?, generation: UInt64, now: Date = Date()) -> StylistScreenSurfaceDescriptor {
        surface(.scoreDetails, recordID: scanID, actionID: componentID, origin: .detail, generation: generation, now: now)
    }

    static func sharedOutfit(sharedID: String?, generation: UInt64, now: Date = Date()) -> StylistScreenSurfaceDescriptor {
        surface(.sharedOutfit, recordID: sharedID, origin: .sharedLink, generation: generation, now: now)
    }

    static func calendar(generation: UInt64, now: Date = Date()) -> StylistScreenSurfaceDescriptor {
        surface(.calendar, origin: .detail, generation: generation, now: now)
    }

    static func weather(generation: UInt64, now: Date = Date()) -> StylistScreenSurfaceDescriptor {
        surface(.weather, origin: .detail, generation: generation, now: now)
    }

    static func favorites(itemID: String, generation: UInt64, now: Date = Date()) -> StylistScreenSurfaceDescriptor {
        surface(.favorites, itemID: itemID, origin: .detail, generation: generation, now: now)
    }

    static func aiStylist(generation: UInt64, now: Date = Date()) -> StylistScreenSurfaceDescriptor {
        surface(.aiStylist, origin: .tab, generation: generation, now: now)
    }

    static func unsupported(generation: UInt64, now: Date = Date()) -> StylistScreenSurfaceDescriptor {
        surface(.unsupported, origin: .unknown, generation: generation, now: now)
    }

    private static func surface(
        _ kind: StylistScreenSurfaceKind,
        recordID: String? = nil,
        itemID: String? = nil,
        productID: String? = nil,
        actionID: String? = nil,
        origin: StylistNavigationOrigin,
        resultState: StylistScreenResultState? = nil,
        generation: UInt64,
        now: Date
    ) -> StylistScreenSurfaceDescriptor {
        StylistScreenSurfaceDescriptor(
            screenKind: kind,
            navigationOrigin: origin,
            selectedLocalRecordID: recordID,
            selectedItemID: itemID,
            selectedProductID: productID,
            selectedActionID: actionID,
            resultState: resultState,
            contextGeneration: generation,
            createdAt: now
        )
    }
}

/// A route is valid only for its current navigation generation. This makes a
/// context-aware action explicit and ensures rapid A → B navigation cannot
/// accidentally send A after B has become visible.
struct StylistContextAwareRoute: Equatable {
    let screenContext: StylistScreenContext
    let reference: StyleMemoryReference?
    let generation: UInt64

    init?(screenContext: StylistScreenContext, reference: StyleMemoryReference? = nil) {
        guard let surface = screenContext.surface,
              surface.screenKind != .unsupported else { return nil }
        self.screenContext = screenContext
        self.reference = reference
        generation = surface.contextGeneration
    }

    func isCurrent(generation currentGeneration: UInt64, availableReferences: Set<StyleMemoryReference>) -> Bool {
        guard generation == currentGeneration else { return false }
        return reference.map(availableReferences.contains) ?? true
    }
}

/// An explicit, short-lived entry into AI Stylist from a supported app surface.
/// The local reference exists only to reject stale selections; it is never
/// rendered or copied into the outbound chat context.
enum ScreenAwarenessSemanticEntityType: Equatable {
    case closetItem
    case shoppingProduct
    case profile
}

/// The sole network-safe representation of a product the customer explicitly
/// chose to discuss. It intentionally contains no catalog identity, retailer,
/// affiliate, inventory, sizing, sale, image, or tracking metadata.
struct StylistProductContext: Codable, Equatable {
    enum Relationship: String, Codable, Equatable {
        case considering
    }

    static let schemaVersion = 1

    let version: Int
    let relationship: Relationship
    let name: String
    let category: ProductCategory
    let brand: String?
    let displayedColor: String?
    let displayedPrice: String?
    let currency: String?

    init?(
        product: AffiliateProduct,
        now: Date = Date()
    ) {
        let name = Self.bounded(product.name, max: 160)
        guard !name.isEmpty else { return nil }

        self.version = Self.schemaVersion
        self.relationship = .considering
        self.name = name
        self.category = product.category
        self.brand = Self.optionalBounded(product.brand, max: 120)
        self.displayedColor = Self.unambiguousCatalogColor(product.colors)

        // This mirrors the numeric price currently shown by the product card,
        // while deliberately omitting any sale state or retailer metadata.
        let numericPrice: Decimal?
        if product.isAmazonSourced {
            numericPrice = nil
        } else if let salePrice = product.salePrice,
                  (product.saleEndsAt ?? .distantFuture) > now {
            numericPrice = salePrice
        } else {
            numericPrice = product.price
        }
        if let numericPrice,
           let currency = Self.currencyCode(product.currencyCode) {
            self.displayedPrice = Self.displayedPrice(numericPrice)
            self.currency = self.displayedPrice == nil ? nil : currency
        } else {
            self.displayedPrice = nil
            self.currency = nil
        }
    }

    private static func bounded(_ value: String, max: Int) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(max))
    }

    private static func optionalBounded(_ value: String?, max: Int) -> String? {
        let bounded = bounded(value ?? "", max: max)
        return bounded.isEmpty ? nil : bounded
    }

    private static func unambiguousCatalogColor(_ values: [String]) -> String? {
        let colors = Array(Set(values.map { bounded($0, max: 80) }.filter { !$0.isEmpty }))
        guard colors.count == 1 else { return nil }
        return colors[0]
    }

    private static func currencyCode(_ value: String?) -> String? {
        let code = bounded(value ?? "", max: 3).uppercased()
        guard code.count == 3, code.allSatisfy(\.isLetter) else { return nil }
        return code
    }

    private static func displayedPrice(_ value: Decimal) -> String? {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber)
    }
}

/// An immutable, customer-visible projection captured by Profile at the
/// moment the customer explicitly opens AI Stylist. It deliberately accepts
/// no identity, measurement, storage, or consent data.
struct StylistProfileContextProjection: Equatable {
    let stylePreferences: String?
    let styleGoals: String?
    let preferredFit: String?
    let sizeCategory: String?
    let workplaceCategory: WorkplaceEnvironment?

    init(
        stylePreferences: String? = nil,
        styleGoals: String? = nil,
        preferredFit: String? = nil,
        sizeCategory: String? = nil,
        workplaceCategory: WorkplaceEnvironment? = nil
    ) {
        self.stylePreferences = Self.clean(stylePreferences)
        self.styleGoals = Self.clean(styleGoals)
        self.preferredFit = Self.clean(preferredFit)
        self.sizeCategory = Self.clean(sizeCategory)
        self.workplaceCategory = workplaceCategory == .unknown ? nil : workplaceCategory
    }

    private static func clean(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : String(trimmed.prefix(160))
    }
}

/// A local-only, request-scoped projection of an explicitly selected app
/// surface. It is intentionally not Codable: identifiers and generations stay
/// inside the app while `requestContext` projects only customer-visible facts.
struct ScreenAwarenessSnapshot: Equatable {
    enum Kind: Equatable {
        case home
        case closetItem
        case shoppingProduct
        case profile
        case weatherStyling
        case scanComparison
    }

    let kind: Kind
    let screenContext: StylistScreenContext
    let displayTitle: String
    let detail: String
    let requestSummary: String
    let selectedSemanticEntityType: ScreenAwarenessSemanticEntityType?
    let selectedOccasion: String?
    let customerVisibleFacts: [String]
    let capturedAt: Date
    let localReference: StyleMemoryReference?
    private let productContext: StylistProductContext?

    private init(
        kind: Kind,
        screenContext: StylistScreenContext,
        displayTitle: String,
        detail: String,
        requestSummary: String,
        selectedSemanticEntityType: ScreenAwarenessSemanticEntityType? = nil,
        selectedOccasion: String? = nil,
        customerVisibleFacts: [String],
        capturedAt: Date,
        localReference: StyleMemoryReference?,
        productContext: StylistProductContext? = nil
    ) {
        self.kind = kind
        self.screenContext = screenContext
        self.displayTitle = String(displayTitle.prefix(80))
        self.detail = String(detail.prefix(320))
        self.requestSummary = String(requestSummary.prefix(500))
        self.selectedSemanticEntityType = selectedSemanticEntityType
        self.selectedOccasion = selectedOccasion.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)) }
        self.customerVisibleFacts = customerVisibleFacts
            .map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)) }
            .filter { !$0.isEmpty }
            .prefix(8)
            .map { $0 }
        self.capturedAt = capturedAt
        self.localReference = localReference
        self.productContext = productContext
    }

    static func home(generation: UInt64, capturedAt: Date = Date()) -> Self {
        let facts = ["Customer explicitly opened AI Stylist from Home."]
        return Self(
            kind: .home,
            screenContext: StylistScreenContext(
                currentTab: .home,
                activeScanState: .none,
                entryPoint: .homeMorningBrief,
                closetState: .unavailable,
                surface: StylistScreenSurfaceAdapters.home(cardID: nil, generation: generation)
            ),
            displayTitle: "From Home",
            detail: "Using the Home screen context you chose for this request.",
            requestSummary: "Customer explicitly opened AI Stylist from Home. Use only current request facts and confirmed StyleMatch preferences.",
            customerVisibleFacts: facts,
            capturedAt: capturedAt,
            localReference: nil
        )
    }

    /// A bounded, local-only Home Intelligence handoff. Detail facts are
    /// customer-visible and carry their evidence state; no raw Calendar event,
    /// Closet record ID, product identifier, or hidden view state crosses this
    /// boundary.
    static func homeIntelligence(
        _ detail: HomeIntelligenceDetail,
        generation: UInt64,
        capturedAt: Date = Date()
    ) -> Self {
        let facts = detail.stylistFacts
        return Self(
            kind: .home,
            screenContext: StylistScreenContext(
                currentTab: .home,
                activeScanState: .none,
                entryPoint: .homeMorningBrief,
                closetState: .unavailable,
                surface: StylistScreenSurfaceAdapters.home(cardID: "home-intelligence-\(detail.focus.rawValue)", generation: generation, now: capturedAt)
            ),
            displayTitle: "From \(detail.focus.title)",
            detail: detail.headline,
            requestSummary: facts.joined(separator: " "),
            customerVisibleFacts: facts,
            capturedAt: capturedAt,
            localReference: nil
        )
    }

    static func closetItem(_ item: ClosetItem, generation: UInt64, capturedAt: Date = Date()) -> Self? {
        guard let reference = StyleMemoryReference(domain: .wardrobeItem, stableID: item.id.uuidString) else {
            return nil
        }
        let name = ClosetItemDisplay.displayName(for: item)
        let category = item.category.trimmingCharacters(in: .whitespacesAndNewlines)
        let color = item.color.trimmingCharacters(in: .whitespacesAndNewlines)
        let facts = [
            "Selected closet item: \(name)",
            category.isEmpty ? nil : "Category: \(category)",
            color.isEmpty ? nil : "Color: \(color)",
            "Use this only as a saved closet item, not as the customer's current outfit."
        ]
        .compactMap { $0 }
        let visibleFacts = facts
        .joined(separator: ". ")
        return Self(
            kind: .closetItem,
            screenContext: StylistScreenContext(
                currentTab: .closet,
                activeScanState: .none,
                entryPoint: .closetDesigner,
                closetState: .loadedWithItems,
                surface: StylistScreenSurfaceAdapters.closet(itemID: item.id.uuidString, generation: generation)
            ),
            displayTitle: "Discussing closet item",
            detail: name,
            requestSummary: visibleFacts,
            selectedSemanticEntityType: .closetItem,
            selectedOccasion: item.occasion,
            customerVisibleFacts: facts,
            capturedAt: capturedAt,
            localReference: reference
        )
    }

    static func profile(_ profile: StylistProfileContextProjection, generation: UInt64, capturedAt: Date = Date()) -> Self {
        let facts = [
            profile.stylePreferences.map { "Style preferences: \($0)" },
            profile.styleGoals.map { "Style goals: \($0)" },
            profile.preferredFit.map { "Preferred fit: \($0)" },
            profile.sizeCategory.map { "Size category: \($0)" },
            profile.workplaceCategory.map { "Workplace category: \(workplaceDisplayName($0))" }
        ].compactMap { $0 }
        let summary = facts.isEmpty
            ? "Customer explicitly opened AI Stylist from Profile. Use only current request facts."
            : facts.joined(separator: ". ")
        return Self(
            kind: .profile,
            screenContext: StylistScreenContext(
                currentTab: .profile,
                activeScanState: .none,
                entryPoint: .profile,
                closetState: .unavailable,
                surface: StylistScreenSurfaceAdapters.profile(sectionID: "stylist", generation: generation)
            ),
            displayTitle: "From Profile",
            detail: "Using the Profile preferences you chose for this request.",
            requestSummary: summary,
            selectedSemanticEntityType: .profile,
            customerVisibleFacts: facts,
            capturedAt: capturedAt,
            localReference: nil
        )
    }

    static func weatherStyling(
        _ request: WeatherStylistRouteRequest,
        generation: UInt64,
        capturedAt: Date = Date()
    ) -> Self {
        var facts = ["Customer explicitly opened AI Stylist from Weather Styling."]
        if let location = request.snapshot?.locationName {
            facts.append("Weather location: \(location)")
        }
        if let snapshot = request.snapshot {
            var weatherFacts = [
                "Current weather: \(snapshot.temperatureFahrenheit)°F",
                "Feels like: \(snapshot.feelsLikeFahrenheit)°F",
                "Condition: \(snapshot.condition)"
            ]
            if let rain = snapshot.rainChancePercent { weatherFacts.append("Precipitation chance: \(rain)%") }
            if let humidity = snapshot.humidityPercent { weatherFacts.append("Humidity: \(humidity)%") }
            if let wind = snapshot.windMph {
                let direction = snapshot.windDirection.map { " \($0)" } ?? ""
                weatherFacts.append("Wind: \(wind) mph\(direction)")
            }
            if let uv = snapshot.uvIndex { weatherFacts.append("UV: \(uv)") }
            facts.append(weatherFacts.joined(separator: "; "))
        } else {
            facts.append("Current WeatherKit conditions are unavailable.")
        }
        if let occasion = request.occasion { facts.append("Occasion: \(occasion)") }
        if let workplace = request.workplace { facts.append("Work context: \(workplace)") }
        let recommendationFacts = request.recommendation.items
            .map { "\($0.role): \($0.title)" }
            .joined(separator: "; ")
        if !recommendationFacts.isEmpty {
            facts.append("Current Weather Styling recommendation: \(recommendationFacts)")
        }
        if let score = request.recommendation.weatherMatchScore {
            facts.append("Weather Match: \(score)/100, \(request.recommendation.weatherMatchLabel)")
        } else {
            facts.append("Weather Match: \(request.recommendation.weatherMatchLabel)")
        }

        let summary = facts.joined(separator: " ")
        return Self(
            kind: .weatherStyling,
            screenContext: StylistScreenContext(
                currentTab: .weather,
                activeScanState: .none,
                selectedOccasion: request.occasion,
                entryPoint: .weatherStyling,
                closetState: .unavailable,
                surface: StylistScreenSurfaceAdapters.weather(generation: generation, now: capturedAt)
            ),
            displayTitle: "From Weather Styling",
            detail: request.recommendation.contextTitle,
            requestSummary: summary,
            selectedOccasion: request.occasion,
            customerVisibleFacts: facts,
            capturedAt: capturedAt,
            localReference: nil
        )
    }

    static func scanComparison(_ request: CompareStylistRouteRequest, generation: UInt64, capturedAt: Date = Date()) -> Self {
        let comparison = request.comparison
        let facts = request.customerVisibleFacts
        return Self(kind: .scanComparison, screenContext: StylistScreenContext(currentTab: .scan, activeScanState: .saved, activeScanID: comparison.newerID, entryPoint: .scanComparison, closetState: .unavailable, surface: StylistScreenSurfaceAdapters.scanComparison(newerScanID: comparison.newerID, generation: generation, now: capturedAt)), displayTitle: "From Compare", detail: "\(comparison.olderScore)/100 to \(comparison.newerScore)/100", requestSummary: facts.joined(separator: " "), customerVisibleFacts: facts, capturedAt: capturedAt, localReference: nil)
    }

    static func shoppingProduct(_ product: AffiliateProduct, generation: UInt64, capturedAt: Date = Date()) -> Self? {
        guard let reference = StyleMemoryReference(domain: .shoppingItem, stableID: product.id),
              let productContext = StylistProductContext(product: product, now: capturedAt) else {
            return nil
        }
        return Self(
            kind: .shoppingProduct,
            screenContext: StylistScreenContext(
                currentTab: .shop,
                activeScanState: .none,
                entryPoint: .shopping,
                closetState: .unavailable,
                surface: StylistScreenSurfaceAdapters.shopping(productID: product.id, generation: generation, now: capturedAt)
            ),
            displayTitle: "Considering product",
            detail: productContext.name,
            requestSummary: "Customer explicitly chose to discuss a product they are considering.",
            selectedSemanticEntityType: .shoppingProduct,
            customerVisibleFacts: ["Considering product: \(productContext.name)"],
            capturedAt: capturedAt,
            localReference: reference,
            productContext: productContext
        )
    }

    var generation: UInt64 { screenContext.surface?.contextGeneration ?? 0 }

    /// The chat request receives only the customer-visible description. The
    /// local stable reference, screen identifiers, and generation are
    /// intentionally absent.
    var requestContext: ChatContext {
        switch kind {
        case .profile:
            return ChatContext(profileSummary: requestSummary)
        case .home, .closetItem:
            return ChatContext(recentOutfits: requestSummary)
        case .shoppingProduct:
            guard let product = productContext else { return ChatContext() }
            return ChatContext(productContext: product)
        case .weatherStyling:
            let recommendation = customerVisibleFacts.first {
                $0.hasPrefix("Current Weather Styling recommendation:")
            } ?? ""
            let weatherFacts = customerVisibleFacts
                .filter { !$0.hasPrefix("Current Weather Styling recommendation:") }
                .joined(separator: " ")
            return ChatContext(
                recentOutfits: recommendation,
                weatherConstraint: weatherFacts
            )
        case .scanComparison:
            return ChatContext(recentOutfits: requestSummary)
        }
    }

    var contextIconName: String {
        switch kind {
        case .home: "house.fill"
        case .closetItem: "tshirt.fill"
        case .shoppingProduct: "bag.fill"
        case .profile: "person.crop.circle"
        case .weatherStyling: "cloud.sun.fill"
        case .scanComparison: "arrow.left.arrow.right"
        }
    }

    private static func workplaceDisplayName(_ environment: WorkplaceEnvironment) -> String {
        switch environment {
        case .factoryOrManufacturing: "Factory or manufacturing"
        case .warehouseOrDistribution: "Warehouse or distribution"
        case .office: "Office"
        case .healthcare: "Healthcare"
        case .retail: "Retail"
        case .hospitality: "Hospitality"
        case .outdoorOrConstruction: "Outdoor or construction"
        case .mixedFloorAndOffice: "Mixed floor and office"
        case .remote: "Remote"
        case .other: "Other"
        case .unknown: "Unknown"
        }
    }

    func isCurrent(
        generation currentGeneration: UInt64,
        defaults: UserDefaults = .standard,
        availableShoppingProductIDs: Set<String> = [],
        now: Date = Date(),
        maximumAge: TimeInterval = 15 * 60
    ) -> Bool {
        validity(
            generation: currentGeneration,
            defaults: defaults,
            availableShoppingProductIDs: availableShoppingProductIDs,
            now: now,
            maximumAge: maximumAge
        ).isCurrent
    }

    /// The existing local validity authority, expressed with a typed outcome
    /// so the intelligence ledger can explain why a screen candidate was not
    /// admitted without duplicating generation, age, or reference checks.
    func validity(
        generation currentGeneration: UInt64,
        defaults: UserDefaults = .standard,
        availableShoppingProductIDs: Set<String> = [],
        now: Date = Date(),
        maximumAge: TimeInterval = 15 * 60
    ) -> StylistScreenAwarenessValidity {
        guard generation == currentGeneration else {
            return .staleGeneration
        }
        guard capturedAt <= now else { return .staleCapture }
        guard now.timeIntervalSince(capturedAt) <= maximumAge else {
            return .staleCapture
        }
        guard let localReference else { return .current }
        switch localReference.domain {
        case .wardrobeItem:
            guard let data = defaults.data(forKey: "closetItemsData"),
                  let items = try? JSONDecoder().decode([ClosetItem].self, from: data) else {
                return .closetItemUnavailable
            }
            return items.contains { $0.id.uuidString == localReference.stableID }
                ? .current
                : .closetItemUnavailable
        case .shoppingItem:
            return availableShoppingProductIDs.contains(localReference.stableID)
                ? .current
                : .productNoLongerAvailable
        default:
            return .invalidReference
        }
    }
}

/// Local-only detail from the existing ScreenAwarenessSnapshot validity
/// predicate. It carries no reference, product ID, or route generation.
enum StylistScreenAwarenessValidity: Equatable {
    case current
    case staleGeneration
    case staleCapture
    case closetItemUnavailable
    case productNoLongerAvailable
    case invalidReference

    var isCurrent: Bool {
        if case .current = self { return true }
        return false
    }
}

/// Root-owned, ephemeral awareness authority. Publishing always replaces the
/// prior snapshot; it owns no store and performs no transport work.
struct StylistAwarenessCoordinator: Equatable {
    private(set) var generation: UInt64 = 0
    private(set) var snapshot: ScreenAwarenessSnapshot?

    mutating func publishHome(capturedAt: Date = Date()) -> ScreenAwarenessSnapshot {
        generation &+= 1
        let snapshot = ScreenAwarenessSnapshot.home(generation: generation, capturedAt: capturedAt)
        self.snapshot = snapshot
        return snapshot
    }

    mutating func publishHomeIntelligence(
        _ detail: HomeIntelligenceDetail,
        capturedAt: Date = Date()
    ) -> ScreenAwarenessSnapshot {
        generation &+= 1
        let snapshot = ScreenAwarenessSnapshot.homeIntelligence(detail, generation: generation, capturedAt: capturedAt)
        self.snapshot = snapshot
        return snapshot
    }

    mutating func publishClosetItem(_ item: ClosetItem, capturedAt: Date = Date()) -> ScreenAwarenessSnapshot? {
        generation &+= 1
        guard let snapshot = ScreenAwarenessSnapshot.closetItem(item, generation: generation, capturedAt: capturedAt) else {
            self.snapshot = nil
            return nil
        }
        self.snapshot = snapshot
        return snapshot
    }

    mutating func publishProfile(_ profile: StylistProfileContextProjection, capturedAt: Date = Date()) -> ScreenAwarenessSnapshot {
        generation &+= 1
        let snapshot = ScreenAwarenessSnapshot.profile(profile, generation: generation, capturedAt: capturedAt)
        self.snapshot = snapshot
        return snapshot
    }

    mutating func publishWeatherStyling(
        _ request: WeatherStylistRouteRequest,
        capturedAt: Date = Date()
    ) -> ScreenAwarenessSnapshot {
        generation &+= 1
        let snapshot = ScreenAwarenessSnapshot.weatherStyling(request, generation: generation, capturedAt: capturedAt)
        self.snapshot = snapshot
        return snapshot
    }
    mutating func publishScanComparison(_ request: CompareStylistRouteRequest, capturedAt: Date = Date()) -> ScreenAwarenessSnapshot {
        generation &+= 1
        let snapshot = ScreenAwarenessSnapshot.scanComparison(request, generation: generation, capturedAt: capturedAt)
        self.snapshot = snapshot
        return snapshot
    }

    mutating func publishShoppingProduct(_ product: AffiliateProduct, capturedAt: Date = Date()) -> ScreenAwarenessSnapshot? {
        generation &+= 1
        guard let newSnapshot = ScreenAwarenessSnapshot.shoppingProduct(product, generation: generation, capturedAt: capturedAt) else {
            self.snapshot = nil
            return nil
        }
        self.snapshot = newSnapshot
        return newSnapshot
    }

    mutating func clear() {
        generation &+= 1
        snapshot = nil
    }
}

/// Local grounding metadata for the canonical intelligence snapshot. This is
/// deliberately not Codable: provenance remains inside the app unless a
/// separate, bounded customer-visible fact is projected into `ChatContext`.
enum StylistIntelligenceEvidence: Equatable {
    case observed
    case userConfirmed
    case savedProfile
    case contextual
    case suggested
    case unavailable
}

/// Local-only provenance classifications used by the Global AI Intelligence
/// Hub. These classifications deliberately carry no fact value, record ID,
/// route generation, or persistence reference. The existing explicit
/// `networkSafeContext` projection remains the only Worker-facing bridge.
enum StylistIntelligenceFactDomain: String, Equatable, CaseIterable {
    case scan
    case scanScore
    case screenAwareness
    case productConsideration
    case workplace
    case threadCorrection
    case profile
    case weather
}

enum StylistIntelligenceSourceCategory: String, Equatable {
    case exactScanAuthority
    case explicitScreenAwareness
    case productContextV1
    case currentThread
    case confirmedProfile
    case weatherKit
    case unavailable
}

enum StylistIntelligenceProvenanceClass: String, Equatable {
    case authoritativeFact
    case customerConfirmedFact
    case derivedLocalJudgment
    case modelGeneralKnowledge
    case currentExternalInformation
    case inferredFact
    case unavailableOrUnverified
}

enum StylistIntelligenceFreshness: Equatable {
    case notApplicable
    case current(expiresAt: Date)
    case unavailable
}

enum StylistIntelligenceInvalidationStatus: String, Equatable {
    case valid
    case unavailable
}

enum StylistIntelligencePrivacyClass: String, Equatable {
    case customerVisibleBounded
    case localOnly
}

enum StylistIntelligenceNetworkEligibility: String, Equatable {
    case eligibleThroughExistingProjection
    case ineligible
}

enum StylistIntelligencePersistenceEligibility: String, Equatable {
    case neverPersist
}

/// The local Hub decision for one candidate source. This is intentionally not
/// Codable and must never be projected into ChatContext or Worker JSON.
enum StylistIntelligenceAdmissionDecision: String, Equatable {
    case admitted
    case unavailable
    case rejected
    case stale
    case invalidated
    case privacyBlocked
    case networkIneligible
    case persistenceIneligible
}

/// Bounded local reasons for a decision. Domain authorities continue to own
/// the actual validation; the Hub records their result without taking over
/// Scan, WeatherKit, memory, consent, or release-gate authority.
enum StylistIntelligenceAdmissionReason: String, Equatable {
    case missingAuthoritativeScan
    case incompleteAuthoritativeScan
    case scanScopeMismatch
    case savedScanUnavailable
    case staleScreenGeneration
    case staleScreenCapture
    case closetItemUnavailable
    case productNoLongerAvailable
    case noActiveProductContext
    case screenAuthorityPreemptedByScan
    case unconfirmedWorkplace
    case staleWeather
    case missingWeatherAttribution
    case weatherObservedInFuture
    case memoryNotApproved
    case generalStylistContextCleared
    case releaseFeatureUnavailable
}

/// A metadata-only admission record. It is intentionally not Codable and is
/// rebuilt for each local intelligence snapshot; it cannot create a new
/// persistence or network contract.
struct StylistIntelligenceAdmission: Equatable {
    let domain: StylistIntelligenceFactDomain
    let decision: StylistIntelligenceAdmissionDecision
    let reason: StylistIntelligenceAdmissionReason?
    let sourceCategory: StylistIntelligenceSourceCategory
    let provenance: StylistIntelligenceProvenanceClass
    let freshness: StylistIntelligenceFreshness
    let invalidationStatus: StylistIntelligenceInvalidationStatus
    let privacy: StylistIntelligencePrivacyClass
    let networkEligibility: StylistIntelligenceNetworkEligibility
    let persistenceEligibility: StylistIntelligencePersistenceEligibility
    let customerConfirmed: Bool
    let confidence: Double?
}

/// A builder-internal, local-only resolution. It deliberately carries only a
/// value already supplied by the owning authority plus a typed decision; it
/// never performs persistence or transport work.
private struct StylistIntelligenceResolution<Value> {
    let value: Value?
    let decision: StylistIntelligenceAdmissionDecision
    let reason: StylistIntelligenceAdmissionReason?

    static func admitted(_ value: Value) -> Self {
        Self(value: value, decision: .admitted, reason: nil)
    }

    static func unavailable(_ reason: StylistIntelligenceAdmissionReason?) -> Self {
        Self(value: nil, decision: .unavailable, reason: reason)
    }

    static func rejected(_ reason: StylistIntelligenceAdmissionReason) -> Self {
        Self(value: nil, decision: .rejected, reason: reason)
    }

    static func stale(_ reason: StylistIntelligenceAdmissionReason) -> Self {
        Self(value: nil, decision: .stale, reason: reason)
    }

    static func invalidated(_ reason: StylistIntelligenceAdmissionReason) -> Self {
        Self(value: nil, decision: .invalidated, reason: reason)
    }
}

/// A typed, explicit correction for the current request or thread. Future
/// correction controls can construct this directly; Phase 1C does not infer it
/// from free-form conversation text.
struct StylistIntelligenceThreadCorrection: Equatable {
    let workplace: WorkplaceContext?
    let customerVisibleFact: String?

    init(workplace: WorkplaceContext? = nil, customerVisibleFact: String? = nil) {
        self.workplace = workplace
        let trimmed = customerVisibleFact?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.customerVisibleFact = trimmed.isEmpty ? nil : String(trimmed.prefix(240))
    }
}

/// Inputs are already-resolved by their owning authorities. The builder does
/// not create stores, refresh WeatherKit, or read fallback scan history.
struct StylistIntelligenceSnapshotInput {
    let conversationScope: StylistConversationScope
    let screenAwareness: ScreenAwarenessSnapshot?
    let screenAwarenessGeneration: UInt64
    let exactScan: StylistAuthoritativeScanContext?
    let threadCorrection: StylistIntelligenceThreadCorrection?
    /// Existing local catalog availability authority for Product Context V1.
    /// It is used only to fail closed during local screen-awareness validation.
    let availableShoppingProductIDs: Set<String>
    let persistentWorkplace: WorkplaceContext?
    let weather: WeatherSnapshot?
    let styleProfileSummary: String?
    let conversation: StylistConversationSnapshot
    let defaults: UserDefaults
    let generatedAt: Date

    init(
        conversationScope: StylistConversationScope,
        screenAwareness: ScreenAwarenessSnapshot? = nil,
        screenAwarenessGeneration: UInt64 = 0,
        exactScan: StylistAuthoritativeScanContext? = nil,
        threadCorrection: StylistIntelligenceThreadCorrection? = nil,
        availableShoppingProductIDs: Set<String> = [],
        persistentWorkplace: WorkplaceContext? = nil,
        weather: WeatherSnapshot? = nil,
        styleProfileSummary: String? = nil,
        conversation: StylistConversationSnapshot = .empty,
        defaults: UserDefaults = .standard,
        generatedAt: Date = Date()
    ) {
        self.conversationScope = conversationScope
        self.screenAwareness = screenAwareness
        self.screenAwarenessGeneration = screenAwarenessGeneration
        self.exactScan = exactScan
        self.threadCorrection = threadCorrection
        self.availableShoppingProductIDs = availableShoppingProductIDs
        self.persistentWorkplace = persistentWorkplace
        self.weather = weather
        self.styleProfileSummary = styleProfileSummary
        self.conversation = conversation
        self.defaults = defaults
        self.generatedAt = generatedAt
    }
}

/// Canonical, local-only assembly of the authority available to a Stylist
/// request. It intentionally has no Codable conformance; callers must opt in
/// to the explicit network-safe ChatContext projection below.
struct StylistIntelligenceSnapshot: Equatable {
    let screen: ScreenAwarenessSnapshot?
    let activeScan: StylistAuthoritativeScanContext?
    let latestScore: StylistScoreBreakdownSnapshot?
    let workplace: WorkplaceContext
    let workplaceEvidence: StylistIntelligenceEvidence
    let weather: WeatherSnapshot?
    let weatherEvidence: StylistIntelligenceEvidence
    let styleProfileSummary: String?
    let styleProfileEvidence: StylistIntelligenceEvidence
    let conversation: StylistConversationSnapshot
    let threadCorrection: StylistIntelligenceThreadCorrection?
    /// Local-only, metadata-only admission ledger for the facts resolved by
    /// this snapshot. It is neither persisted nor encoded into ChatContext.
    let admissions: [StylistIntelligenceAdmission]
    let generatedAt: Date

    /// The only bridge from the local snapshot to the established Worker
    /// contract. It never serializes routes, generations, local references,
    /// evidence metadata, or the full local snapshot.
    func networkSafeContext(applying base: ChatContext) -> ChatContext {
        var projected = base

        if let screen, activeScan == nil {
            projected = screen.requestContext
        }

        if let activeScan {
            projected = projected.applyingAuthoritativeScan(activeScan)
            // Exact Scan authority never carries an unrelated product the
            // customer was considering on a previous screen.
            projected.productContext = nil
        } else {
            // A non-scan snapshot is never allowed to carry a historical or
            // implicit latest-scan fallback into the transport projection.
            projected.activeScan = ""
            projected.scoreBreakdown = nil
            projected.authoritativeScan = nil
            if var screenContext = projected.screenContext {
                screenContext.activeScanState = .none
                screenContext.activeScanID = nil
                screenContext.selectedAnalysisSection = nil
                screenContext.visibleOverallScore = nil
                screenContext.surface = nil
                projected.screenContext = screenContext
            }
        }

        if let correctionFact = threadCorrection?.customerVisibleFact {
            let existing = projected.profileSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            projected.profileSummary = String(
                "Current request correction: \(correctionFact)\n\(existing)".prefix(600)
            )
        }

        return projected
    }
}

enum StylistIntelligenceSnapshotBuilder {
    /// Match the established Weather Styling stale threshold without triggering
    /// a refresh. A persisted, unattributed, future-dated, or stale snapshot
    /// fails closed for the local intelligence layer.
    static let maximumWeatherAge: TimeInterval = 60 * 60

    static func build(_ input: StylistIntelligenceSnapshotInput) -> StylistIntelligenceSnapshot {
        let scanResolution = resolvedExactScan(from: input)
        let scan = scanResolution.value
        let screenResolution = resolvedScreenAwareness(from: input, hasScanAuthority: scan != nil)
        let screen = screenResolution.value
        let correction = input.threadCorrection
        let workplace = correction?.workplace ?? input.persistentWorkplace ?? .unknown
        let workplaceEvidence: StylistIntelligenceEvidence
        if correction?.workplace != nil {
            workplaceEvidence = .userConfirmed
        } else if input.persistentWorkplace != nil, workplace != .unknown {
            workplaceEvidence = .savedProfile
        } else {
            workplaceEvidence = .unavailable
        }

        let weatherResolution = canonicalWeather(from: input)
        let validWeather = weatherResolution.value
        let profileSummary = nonEmpty(input.styleProfileSummary)
        let profileEvidence: StylistIntelligenceEvidence = profileSummary == nil ? .unavailable : .savedProfile

        return StylistIntelligenceSnapshot(
            screen: screen,
            activeScan: scan,
            latestScore: scan.flatMap(scoreSnapshot(from:)),
            workplace: workplace,
            workplaceEvidence: workplaceEvidence,
            weather: validWeather,
            weatherEvidence: validWeather == nil ? .unavailable : .observed,
            styleProfileSummary: profileSummary,
            styleProfileEvidence: profileEvidence,
            conversation: input.conversation,
            threadCorrection: correction,
            admissions: admissions(
                scan: scanResolution,
                screen: screenResolution,
                screenCandidate: input.screenAwareness,
                workplace: workplace,
                workplaceEvidence: workplaceEvidence,
                weather: weatherResolution,
                profileSummary: profileSummary,
                correction: correction
            ),
            generatedAt: input.generatedAt
        )
    }

    private static func resolvedExactScan(
        from input: StylistIntelligenceSnapshotInput
    ) -> StylistIntelligenceResolution<StylistAuthoritativeScanContext> {
        guard input.conversationScope.isScanBound else {
            return .unavailable(.missingAuthoritativeScan)
        }
        guard let scan = input.exactScan else {
            if case .savedScan = input.conversationScope {
                return .rejected(.savedScanUnavailable)
            }
            return .unavailable(.missingAuthoritativeScan)
        }
        guard scan.scanID == input.conversationScope.scanID else {
            return .rejected(.scanScopeMismatch)
        }
        guard scan.isComplete else {
            return .unavailable(.incompleteAuthoritativeScan)
        }
        return .admitted(scan)
    }

    private static func resolvedScreenAwareness(
        from input: StylistIntelligenceSnapshotInput,
        hasScanAuthority: Bool
    ) -> StylistIntelligenceResolution<ScreenAwarenessSnapshot> {
        guard !hasScanAuthority else {
            return .rejected(.screenAuthorityPreemptedByScan)
        }
        guard !input.conversationScope.isScanBound else {
            return .unavailable(.generalStylistContextCleared)
        }
        guard let screen = input.screenAwareness else {
            return .unavailable(.generalStylistContextCleared)
        }
        switch screen.validity(
            generation: input.screenAwarenessGeneration,
            defaults: input.defaults,
            availableShoppingProductIDs: input.availableShoppingProductIDs,
            now: input.generatedAt
        ) {
        case .current:
            return .admitted(screen)
        case .staleGeneration:
            return .stale(.staleScreenGeneration)
        case .staleCapture:
            return .stale(.staleScreenCapture)
        case .closetItemUnavailable:
            return .invalidated(.closetItemUnavailable)
        case .productNoLongerAvailable:
            return .invalidated(.productNoLongerAvailable)
        case .invalidReference:
            return .invalidated(.closetItemUnavailable)
        }
    }

    private static func canonicalWeather(
        from input: StylistIntelligenceSnapshotInput
    ) -> StylistIntelligenceResolution<WeatherSnapshot> {
        guard let weather = input.weather else {
            return .unavailable(nil)
        }
        guard weather.attribution.isUsable else {
            return .rejected(.missingWeatherAttribution)
        }
        guard weather.observedAt <= input.generatedAt else {
            return .rejected(.weatherObservedInFuture)
        }
        guard input.generatedAt.timeIntervalSince(weather.observedAt) <= maximumWeatherAge else {
            return .stale(.staleWeather)
        }
        return .admitted(weather)
    }

    private static func scoreSnapshot(
        from scan: StylistAuthoritativeScanContext
    ) -> StylistScoreBreakdownSnapshot? {
        scan.scoreBreakdown.map {
            StylistScoreBreakdownSnapshot(
                colorHarmony: $0.colorHarmony,
                patternBalance: $0.patternBalance,
                fitQuality: $0.fitQuality,
                occasionMatch: $0.occasionMatch,
                accessoryUse: $0.accessoryUse
            )
        }
    }

    private static func admissions(
        scan: StylistIntelligenceResolution<StylistAuthoritativeScanContext>,
        screen: StylistIntelligenceResolution<ScreenAwarenessSnapshot>,
        screenCandidate: ScreenAwarenessSnapshot?,
        workplace: WorkplaceContext,
        workplaceEvidence: StylistIntelligenceEvidence,
        weather: StylistIntelligenceResolution<WeatherSnapshot>,
        profileSummary: String?,
        correction: StylistIntelligenceThreadCorrection?
    ) -> [StylistIntelligenceAdmission] {
        var records: [StylistIntelligenceAdmission] = []

        records.append(admission(
            domain: .scan,
            source: scan.value == nil ? .unavailable : .exactScanAuthority,
            provenance: scan.value == nil ? .unavailableOrUnverified : .authoritativeFact,
            resolution: scan
        ))
        records.append(admission(
            domain: .scanScore,
            source: scan.value?.scoreBreakdown == nil ? .unavailable : .exactScanAuthority,
            provenance: scan.value?.scoreBreakdown == nil ? .unavailableOrUnverified : .authoritativeFact,
            decision: scan.value?.scoreBreakdown == nil ? scan.decision : .admitted,
            reason: scan.value?.scoreBreakdown == nil ? scan.reason : nil
        ))
        records.append(admission(
            domain: .screenAwareness,
            source: screen.value == nil ? .unavailable : .explicitScreenAwareness,
            provenance: screen.value == nil ? .unavailableOrUnverified : .customerConfirmedFact,
            resolution: screen,
            customerConfirmed: screen.value != nil
        ))

        let productCandidate = screenCandidate?.kind == .shoppingProduct
        let productIsConsidering = productCandidate && screen.value?.kind == .shoppingProduct
        records.append(admission(
            domain: .productConsideration,
            source: productIsConsidering ? .productContextV1 : .unavailable,
            provenance: productIsConsidering ? .customerConfirmedFact : .unavailableOrUnverified,
            decision: productIsConsidering ? .admitted : (productCandidate ? screen.decision : .unavailable),
            reason: productIsConsidering ? nil : (productCandidate ? screen.reason : .noActiveProductContext),
            customerConfirmed: productIsConsidering
        ))

        let isThreadCorrection = correction?.workplace != nil
        records.append(admission(
            domain: .threadCorrection,
            source: isThreadCorrection ? .currentThread : .unavailable,
            provenance: isThreadCorrection ? .customerConfirmedFact : .unavailableOrUnverified,
            decision: isThreadCorrection ? .admitted : .unavailable,
            customerConfirmed: isThreadCorrection
        ))
        let hasWorkplace = workplace != .unknown
        records.append(admission(
            domain: .workplace,
            source: workplaceSource(for: workplaceEvidence),
            provenance: workplaceProvenance(for: workplaceEvidence),
            decision: hasWorkplace ? .admitted : .unavailable,
            reason: hasWorkplace ? nil : .unconfirmedWorkplace,
            customerConfirmed: workplaceEvidence == .userConfirmed || workplaceEvidence == .savedProfile
        ))
        records.append(admission(
            domain: .profile,
            source: profileSummary == nil ? .unavailable : .confirmedProfile,
            provenance: profileSummary == nil ? .unavailableOrUnverified : .customerConfirmedFact,
            decision: profileSummary == nil ? .unavailable : .admitted,
            customerConfirmed: profileSummary != nil
        ))
        records.append(admission(
            domain: .weather,
            source: weather.value == nil ? .unavailable : .weatherKit,
            provenance: weather.value == nil ? .unavailableOrUnverified : .currentExternalInformation,
            resolution: weather,
            freshness: weather.value.map { .current(expiresAt: $0.observedAt.addingTimeInterval(maximumWeatherAge)) } ?? .unavailable,
            customerConfirmed: false
        ))

        return records
    }

    private static func admission(
        domain: StylistIntelligenceFactDomain,
        source: StylistIntelligenceSourceCategory,
        provenance: StylistIntelligenceProvenanceClass,
        decision: StylistIntelligenceAdmissionDecision,
        reason: StylistIntelligenceAdmissionReason? = nil,
        freshness: StylistIntelligenceFreshness = .notApplicable,
        customerConfirmed: Bool = false
    ) -> StylistIntelligenceAdmission {
        StylistIntelligenceAdmission(
            domain: domain,
            decision: decision,
            reason: reason,
            sourceCategory: source,
            provenance: provenance,
            freshness: freshness,
            invalidationStatus: decision == .admitted ? .valid : .unavailable,
            privacy: decision == .admitted ? .customerVisibleBounded : .localOnly,
            networkEligibility: decision == .admitted ? .eligibleThroughExistingProjection : .ineligible,
            persistenceEligibility: .neverPersist,
            customerConfirmed: customerConfirmed,
            confidence: nil
        )
    }

    private static func admission<Value>(
        domain: StylistIntelligenceFactDomain,
        source: StylistIntelligenceSourceCategory,
        provenance: StylistIntelligenceProvenanceClass,
        resolution: StylistIntelligenceResolution<Value>,
        freshness: StylistIntelligenceFreshness = .notApplicable,
        customerConfirmed: Bool = false
    ) -> StylistIntelligenceAdmission {
        admission(
            domain: domain,
            source: source,
            provenance: provenance,
            decision: resolution.decision,
            reason: resolution.reason,
            freshness: freshness,
            customerConfirmed: customerConfirmed
        )
    }

    private static func workplaceSource(
        for evidence: StylistIntelligenceEvidence
    ) -> StylistIntelligenceSourceCategory {
        switch evidence {
        case .userConfirmed: .currentThread
        case .savedProfile: .confirmedProfile
        case .observed, .contextual, .suggested, .unavailable: .unavailable
        }
    }

    private static func workplaceProvenance(
        for evidence: StylistIntelligenceEvidence
    ) -> StylistIntelligenceProvenanceClass {
        switch evidence {
        case .userConfirmed, .savedProfile: .customerConfirmedFact
        case .observed, .contextual, .suggested, .unavailable: .unavailableOrUnverified
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : String(trimmed.prefix(600))
    }
}

enum StylistActiveScanState: String, Codable, Equatable {
    case none
    case live
    case saved
}

enum StylistClosetState: String, Codable, Equatable {
    case loadedEmpty
    case loadedWithItems
    case unavailable

    static func fromSerializedClosetData(_ data: Data) -> StylistClosetState {
        guard !data.isEmpty else { return .loadedEmpty }
        guard let items = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            return .unavailable
        }
        return items.isEmpty ? .loadedEmpty : .loadedWithItems
    }
}

enum StylistEntryPoint: String, Codable, Equatable {
    case homeMorningBrief = "home_morning_brief"
    case scanTab = "scan_tab"
    case scanResult = "scan_result"
    case closetDesigner = "closet_designer"
    case shopping
    case aiTab = "ai_tab"
    case profile = "profile"
    case weatherStyling = "weather_styling"
    case scanComparison = "scan_comparison"
    case other
}

struct StylistVisibleAggregateStatistics: Codable, Equatable {
    var averageScore: Int?
    var highestScore: Int?
    var totalScans: Int?

    init(averageScore: Int? = nil, highestScore: Int? = nil, totalScans: Int? = nil) {
        self.averageScore = averageScore.map { min(100, max(0, $0)) }
        self.highestScore = highestScore.map { min(100, max(0, $0)) }
        self.totalScans = totalScans.map { max(0, $0) }
    }
}

struct ScanProgressSummary: Equatable {
    let averageScore: Int?
    let highestScore: Int?
    let savedScanCount: Int

    init(scores: [Int]) {
        let boundedScores = scores.map { min(100, max(0, $0)) }
        savedScanCount = boundedScores.count
        guard !boundedScores.isEmpty else {
            averageScore = nil
            highestScore = nil
            return
        }

        let total = boundedScores.reduce(0, +)
        averageScore = Int((Double(total) / Double(boundedScores.count)).rounded())
        highestScore = boundedScores.max()
    }

    var averageScoreText: String { averageScore.map(String.init) ?? "—" }
    var highestScoreText: String { highestScore.map(String.init) ?? "—" }
    var savedScanCountText: String { String(savedScanCount) }

    var visibleAggregates: StylistVisibleAggregateStatistics {
        StylistVisibleAggregateStatistics(
            averageScore: averageScore,
            highestScore: highestScore,
            totalScans: savedScanCount
        )
    }
}

struct StylistScreenContext: Codable, Equatable {
    var currentTab: StylistScreenTab
    var activeScanState: StylistActiveScanState
    var activeScanID: String?
    var selectedOccasion: String?
    var selectedAnalysisSection: String?
    var visibleOverallScore: Int?
    var entryPoint: StylistEntryPoint
    var visibleAggregates: StylistVisibleAggregateStatistics?
    var closetState: StylistClosetState
    /// Optional so persisted pre-18035 contexts continue to decode unchanged.
    var surface: StylistScreenSurfaceDescriptor?

    init(
        currentTab: StylistScreenTab,
        activeScanState: StylistActiveScanState,
        activeScanID: String? = nil,
        selectedOccasion: String? = nil,
        selectedAnalysisSection: String? = nil,
        visibleOverallScore: Int? = nil,
        entryPoint: StylistEntryPoint,
        visibleAggregates: StylistVisibleAggregateStatistics? = nil,
        closetState: StylistClosetState,
        surface: StylistScreenSurfaceDescriptor? = nil
    ) {
        self.currentTab = currentTab
        self.activeScanState = activeScanState
        self.activeScanID = activeScanState == .none ? nil : Self.nonEmpty(activeScanID)
        self.selectedOccasion = Self.nonEmpty(selectedOccasion)
        self.selectedAnalysisSection = Self.nonEmpty(selectedAnalysisSection)
        self.visibleOverallScore = visibleOverallScore.map { min(100, max(0, $0)) }
        self.entryPoint = entryPoint
        self.visibleAggregates = visibleAggregates
        self.closetState = closetState
        self.surface = surface
    }

    static func aiTab(
        entryPoint: StylistEntryPoint = .aiTab,
        closetState: StylistClosetState = .unavailable
    ) -> Self {
        Self(
            currentTab: .ai,
            activeScanState: .none,
            entryPoint: entryPoint,
            closetState: closetState
        )
    }

    static func morningBrief() -> Self {
        Self(
            currentTab: .home,
            activeScanState: .none,
            entryPoint: .homeMorningBrief,
            closetState: .unavailable
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : String(trimmed.prefix(128))
    }
}

enum StylistScanContextSource: String, Codable, Equatable {
    case liveCompleted = "live_completed"
    case savedSelection = "saved_selection"
    case latestCompleted = "latest_completed"
}

enum StylistScanImageReference: String, Codable, Equatable {
    // This is deliberately a presence marker, never an image, path, URL, or identifier.
    case onDeviceOnly = "on_device_only"
}

struct StylistAuthoritativeScanContext: Codable, Equatable {
    let scanID: String
    let completedAt: Date
    let overallScore: Int
    let scoreBreakdown: OutfitScoreBreakdown?
    let detectedStyle: String?
    let styleConfidence: Int?
    let selectedOccasion: String?
    let occasionAssessment: String?
    let weatherContext: String?
    let outfitClassification: OutfitClassificationResult?
    let imageReference: StylistScanImageReference?
    let groundedRecommendations: [GroundedRecommendation]?
    let source: StylistScanContextSource
    /// Compact visual facts supplied by the Scan authority. These are never
    /// interpreted as garment-to-color mappings.
    let palette: [String]?
    let topStyleMatches: [String]?
    let evidenceLimitations: [String]?
    let reliableWeatherSummary: String?
    let outfitType: String?

    init(
        scanID: String,
        completedAt: Date,
        overallScore: Int,
        scoreBreakdown: OutfitScoreBreakdown?,
        detectedStyle: String? = nil,
        styleConfidence: Int? = nil,
        selectedOccasion: String? = nil,
        occasionAssessment: String? = nil,
        weatherContext: String? = nil,
        outfitClassification: OutfitClassificationResult? = nil,
        imageReference: StylistScanImageReference? = nil,
        groundedRecommendations: [GroundedRecommendation]? = nil,
        source: StylistScanContextSource,
        palette: [String]? = nil,
        topStyleMatches: [String]? = nil,
        evidenceLimitations: [String]? = nil,
        reliableWeatherSummary: String? = nil,
        outfitType: String? = nil
    ) {
        self.scanID = Self.nonEmpty(scanID) ?? ""
        self.completedAt = completedAt
        self.overallScore = min(100, max(0, overallScore))
        self.scoreBreakdown = scoreBreakdown
        self.detectedStyle = Self.nonEmpty(detectedStyle)
        self.styleConfidence = styleConfidence.map { min(100, max(0, $0)) }
        self.selectedOccasion = Self.nonEmpty(selectedOccasion)
        self.occasionAssessment = Self.nonEmpty(occasionAssessment)
        self.weatherContext = Self.nonEmpty(weatherContext)
        self.outfitClassification = outfitClassification
        self.imageReference = imageReference
        self.groundedRecommendations = groundedRecommendations.map {
            Array($0.prefix(RecommendationGroundingValidator.maximumRecommendations))
        }
        self.source = source
        self.palette = Self.compactList(palette, maximumCount: 5)
        self.topStyleMatches = Self.compactList(topStyleMatches, maximumCount: 3)
        self.evidenceLimitations = Self.compactList(evidenceLimitations, maximumCount: 3)
        self.reliableWeatherSummary = Self.nonEmpty(reliableWeatherSummary)
        self.outfitType = Self.nonEmpty(outfitType)
    }

    var isComplete: Bool {
        !scanID.isEmpty && (0...100).contains(overallScore)
    }

    func matches(_ screenContext: StylistScreenContext?) -> Bool {
        guard let screenContext,
              screenContext.activeScanState != .none else {
            return true
        }
        guard screenContext.activeScanID == scanID else { return false }
        return screenContext.visibleOverallScore.map { $0 == overallScore } ?? true
    }

    var activeScanPrompt: String {
        var facts = ["scan ID \(scanID)", "completed \(completedAt.ISO8601Format())", "score \(overallScore)/100"]
        facts.append("score band \(StyleMatchHomeDisplay.scoreBand(for: overallScore).title)")
        if let detectedStyle { facts.append("detected style \(detectedStyle)") }
        if let styleConfidence { facts.append("style confidence \(styleConfidence)%") }
        if let palette, !palette.isEmpty {
            facts.append("observed palette \(palette.joined(separator: ", "))")
        }
        if let topStyleMatches, !topStyleMatches.isEmpty {
            facts.append("top style matches \(topStyleMatches.joined(separator: ", "))")
        }
        if let selectedOccasion { facts.append("selected occasion \(selectedOccasion)") }
        if let outfitType { facts.append("outfit type \(outfitType)") }
        if let occasionAssessment { facts.append("occasion assessment \(occasionAssessment)") }
        if let weatherContext { facts.append("weather context \(weatherContext)") }
        if let outfitClassification {
            facts.append("outfit category \(outfitClassification.effectiveCategory.displayName)")
            facts.append("category confidence \(Int((outfitClassification.confidence * 100).rounded()))%")
            facts.append("category source \(outfitClassification.userConfirmedCategory == nil ? "scan evidence" : "user confirmed")")
            facts.append("evaluation profile \(outfitClassification.scoringProfile.rawValue): \(outfitClassification.scoringProfile.evaluationCriteria.joined(separator: ", "))")
            if !outfitClassification.detectedBranding.isEmpty {
                facts.append("visible-brand evidence \(outfitClassification.detectedBranding.joined(separator: ", "))")
            }
        }
        if let groundedRecommendations, !groundedRecommendations.isEmpty {
            facts.append(
                AIRecommendationContextFormatter.promptFragment(
                    for: groundedRecommendations
                )
            )
        } else {
            facts.append("grounded suggestions unavailable; do not invent specific garments, fit details, or improvements")
        }
        if imageReference != nil { facts.append("scan image remains on device") }
        if let reliableWeatherSummary {
            facts.append("reliable weather summary \(reliableWeatherSummary)")
        }
        if let evidenceLimitations, !evidenceLimitations.isEmpty {
            facts.append("evidence limitations \(evidenceLimitations.joined(separator: "; "))")
        }
        return "Authoritative completed scan: \(facts.joined(separator: "; ")). All facts in this block belong to this one scan ID."
    }

    var scoreBreakdownPrompt: String {
        guard let scoreBreakdown else {
            return "Overall score from authoritative scan: \(overallScore)/100. Category breakdown unavailable for this scan. Do not invent category scores."
        }
        return "Existing score only for scan ID \(scanID): \(scoreBreakdown.stylistChatSummary)"
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : String(trimmed.prefix(500))
    }

    private static func compactList(_ values: [String]?, maximumCount: Int) -> [String]? {
        guard let values else { return nil }
        let compacted = values.compactMap { nonEmpty($0) }
        return compacted.isEmpty ? nil : Array(compacted.prefix(maximumCount))
    }
}

enum StylistActiveScanStateResolver {
    static func resolve(
        hasResult: Bool,
        hasSelectedImage: Bool,
        activeScanID: String?,
        savedScanIDs: Set<String>
    ) -> StylistActiveScanState {
        guard hasResult else { return .none }
        if hasSelectedImage { return .live }
        guard let activeScanID, savedScanIDs.contains(activeScanID) else { return .none }
        return .saved
    }
}

extension StylistScreenContext {
    func resolvingSavedScanAvailability(_ savedScanIDs: Set<String>) -> Self {
        guard activeScanState == .saved,
              let activeScanID,
              savedScanIDs.contains(activeScanID) else {
            if activeScanState != .saved { return self }
            return Self(
                currentTab: currentTab,
                activeScanState: .none,
                selectedOccasion: selectedOccasion,
                selectedAnalysisSection: selectedAnalysisSection,
                entryPoint: currentTab == .scan ? .scanTab : entryPoint,
                visibleAggregates: visibleAggregates,
                closetState: closetState
            )
        }
        return self
    }
}

struct ChatContext: Codable, Equatable {
    var profileSummary: String
    var recentOutfits: String
    var activeScan: String
    var historicalOutfits: String
    var weatherConstraint: String
    var scoreBreakdown: String?
    var screenContext: StylistScreenContext?
    var authoritativeScan: StylistAuthoritativeScanContext?
    var stylistContextSnapshot: StylistRouteContextAttachment
    /// Optional additive V1 projection of an explicitly selected product. It
    /// is request-scoped and cannot establish ownership or current wear.
    var productContext: StylistProductContext?
    /// Optional for backward-compatible request decoding. This is a bounded,
    /// request-time projection, never a persisted memory authority.
    var aiMemoryResolution: AIMemoryResolution?
    /// Explicit fact-only attachments are request-scoped. They are never
    /// copied into conversation persistence or reused by follow-up turns.
    var stylistFactContext: PersonalizationContextBuilder.StylistFactContextV1?
    var stylePreferences: PersonalizationContextBuilder.ChatV2StylePreferences?

    init(
        profileSummary: String = "",
        recentOutfits: String = "",
        activeScan: String = "",
        historicalOutfits: String = "",
        weatherConstraint: String = "",
        scoreBreakdown: String? = nil,
        screenContext: StylistScreenContext? = nil,
        authoritativeScan: StylistAuthoritativeScanContext? = nil,
        stylistContextSnapshot: StylistRouteContextAttachment = .unavailable,
        productContext: StylistProductContext? = nil,
        aiMemoryResolution: AIMemoryResolution? = nil,
        stylistFactContext: PersonalizationContextBuilder.StylistFactContextV1? = nil,
        stylePreferences: PersonalizationContextBuilder.ChatV2StylePreferences? = nil
    ) {
        self.profileSummary = Self.clamp(profileSummary, max: 600)
        self.recentOutfits = Self.clamp(recentOutfits, max: 800)
        self.activeScan = Self.clamp(activeScan, max: 800)
        self.historicalOutfits = Self.clamp(historicalOutfits, max: 800)
        self.weatherConstraint = Self.clamp(weatherConstraint, max: 300)
        self.scoreBreakdown = scoreBreakdown.map { Self.clamp($0, max: 500) }
        self.screenContext = screenContext
        self.authoritativeScan = authoritativeScan
        self.stylistContextSnapshot = stylistContextSnapshot
        self.productContext = productContext
        self.aiMemoryResolution = aiMemoryResolution
        self.stylistFactContext = stylistFactContext
        self.stylePreferences = stylePreferences
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            profileSummary: try container.decodeIfPresent(String.self, forKey: .profileSummary) ?? "",
            recentOutfits: try container.decodeIfPresent(String.self, forKey: .recentOutfits) ?? "",
            activeScan: try container.decodeIfPresent(String.self, forKey: .activeScan) ?? "",
            historicalOutfits: try container.decodeIfPresent(String.self, forKey: .historicalOutfits) ?? "",
            weatherConstraint: try container.decodeIfPresent(String.self, forKey: .weatherConstraint) ?? "",
            scoreBreakdown: try container.decodeIfPresent(String.self, forKey: .scoreBreakdown),
            screenContext: try container.decodeIfPresent(StylistScreenContext.self, forKey: .screenContext),
            authoritativeScan: try container.decodeIfPresent(StylistAuthoritativeScanContext.self, forKey: .authoritativeScan),
            stylistContextSnapshot: try container.decodeIfPresent(
                StylistRouteContextAttachment.self,
                forKey: .stylistContextSnapshot
            ) ?? .unavailable,
            productContext: try container.decodeIfPresent(StylistProductContext.self, forKey: .productContext),
            aiMemoryResolution: try container.decodeIfPresent(AIMemoryResolution.self, forKey: .aiMemoryResolution),
            stylistFactContext: try container.decodeIfPresent(PersonalizationContextBuilder.StylistFactContextV1.self, forKey: .stylistFactContext),
            stylePreferences: try container.decodeIfPresent(PersonalizationContextBuilder.ChatV2StylePreferences.self, forKey: .stylePreferences)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case profileSummary
        case recentOutfits
        case activeScan
        case historicalOutfits
        case weatherConstraint
        case scoreBreakdown
        case screenContext
        case authoritativeScan
        case stylistContextSnapshot
        case productContext
        case aiMemoryResolution
        case stylistFactContext = "stylist_context"
        case stylePreferences
    }

    private static func clamp(_ text: String, max: Int) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(max))
    }

    /// WeatherKit attribution belongs only to an explicit Weather Styling
    /// handoff. A generic Stylist session may share the same process and a
    /// current weather cache, but it must not present that cache as part of a
    /// general fashion conversation.
    var hasExplicitWeatherStylingContext: Bool {
        screenContext?.entryPoint == .weatherStyling
            && !weatherConstraint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum StylistRouteContextPipeline {
    static func resolving(
        _ context: ChatContext,
        requestTime: Date = Date()
    ) -> ChatContext {
        var resolved = context
        if resolved.screenContext?.activeScanState == StylistActiveScanState.none {
            resolved.authoritativeScan = nil
            resolved.activeScan = ""
            resolved.scoreBreakdown = nil
        } else {
            resolved = resolved.validatingAuthoritativeScan()
        }
        // Legacy presentation surfaces can carry a bounded conversation
        // attachment. Preserve it instead of replacing confirmed thread context
        // with an empty attachment; active scan authority above remains
        // independently fail-closed.
        if resolved.stylistContextSnapshot == .unavailable {
            resolved.stylistContextSnapshot = StylistRouteContextAttachment.resolving(
                authoritativeScan: resolved.authoritativeScan,
                weatherConstraint: resolved.weatherConstraint,
                requestTime: requestTime
            )
        }
        return resolved
    }

    static func applying(
        _ routeContext: ChatContext,
        to supplementalContext: ChatContext,
        requestTime: Date = Date()
    ) -> ChatContext {
        let resolved = resolving(routeContext, requestTime: requestTime)
        return ChatContext(
            profileSummary: supplementalContext.profileSummary,
            recentOutfits: supplementalContext.recentOutfits,
            activeScan: resolved.activeScan,
            historicalOutfits: supplementalContext.historicalOutfits,
            weatherConstraint: resolved.weatherConstraint,
            scoreBreakdown: resolved.scoreBreakdown,
            screenContext: resolved.screenContext,
            authoritativeScan: resolved.authoritativeScan,
            stylistContextSnapshot: resolved.stylistContextSnapshot,
            productContext: supplementalContext.productContext,
            stylistFactContext: supplementalContext.stylistFactContext
        )
    }
}

struct StylistScanHandoff: Equatable {
    let context: ChatContext
    let screenContext: StylistScreenContext
    /// Set only for an explicit Scan-to-Stylist user action. Routine Scan
    /// presentation updates deliberately carry no token.
    let routeToken: UUID?
    let selectedConversationID: UUID?

    init(
        context: ChatContext,
        screenContext: StylistScreenContext,
        routeToken: UUID? = nil,
        selectedConversationID: UUID? = nil
    ) {
        self.screenContext = screenContext
        var resolvedContext = context
        resolvedContext.screenContext = screenContext
        self.context = resolvedContext
        self.routeToken = routeToken
        self.selectedConversationID = selectedConversationID
    }

    var aiScreenContext: StylistScreenContext {
        StylistScreenContext(
            currentTab: .ai,
            activeScanState: screenContext.activeScanState,
            activeScanID: screenContext.activeScanID,
            selectedOccasion: screenContext.selectedOccasion,
            selectedAnalysisSection: screenContext.selectedAnalysisSection,
            visibleOverallScore: screenContext.visibleOverallScore,
            entryPoint: .scanResult,
            visibleAggregates: screenContext.visibleAggregates,
            closetState: screenContext.closetState,
            surface: screenContext.surface
        )
    }

    var aiChatContext: ChatContext {
        var resolvedContext = context
        resolvedContext.screenContext = aiScreenContext
        return resolvedContext
    }

    func issuingRouteToken() -> Self {
        Self(
            context: context,
            screenContext: screenContext,
            routeToken: UUID(),
            selectedConversationID: selectedConversationID
        )
    }

    func selectingConversation(_ conversationID: UUID?) -> Self {
        Self(
            context: context,
            screenContext: screenContext,
            routeToken: routeToken,
            selectedConversationID: conversationID
        )
    }
}

struct StylistAIRouteAuthority: Equatable {
    let generation: UInt64
    let screenContext: StylistScreenContext
    let acceptsScanHandoff: Bool

    init(
        generation: UInt64 = 0,
        screenContext: StylistScreenContext = .aiTab(),
        acceptsScanHandoff: Bool = false
    ) {
        self.generation = generation
        self.screenContext = screenContext
        self.acceptsScanHandoff = acceptsScanHandoff
    }

    func publishingGlobalAI() -> Self {
        Self(
            generation: generation &+ 1,
            screenContext: .aiTab(entryPoint: .aiTab),
            acceptsScanHandoff: false
        )
    }

    func publishingCarriedEntry(_ entryPoint: StylistEntryPoint) -> Self {
        Self(
            generation: generation &+ 1,
            screenContext: .aiTab(entryPoint: entryPoint),
            acceptsScanHandoff: entryPoint == .scanResult
        )
    }
}

extension ChatContext {
    func applyingCurrentScreenContext(_ currentScreenContext: StylistScreenContext) -> Self {
        var resolved = self
        let previouslyHadActiveScan = screenContext.map {
            $0.activeScanState != StylistActiveScanState.none
        } ?? false
        resolved.screenContext = currentScreenContext
        if previouslyHadActiveScan && currentScreenContext.activeScanState == .none {
            resolved.activeScan = ""
            resolved.scoreBreakdown = nil
            resolved.authoritativeScan = nil
        }
        return resolved
    }
}

extension ChatContext {
    func validatingAuthoritativeScan() -> Self {
        guard let authoritativeScan else { return self }
        return applyingAuthoritativeScan(authoritativeScan)
    }

    func applyingAuthoritativeScan(_ scan: StylistAuthoritativeScanContext?) -> Self {
        var resolved = self
        guard let scan, scan.isComplete, scan.matches(screenContext) else {
            resolved.authoritativeScan = nil
            resolved.activeScan = ""
            resolved.scoreBreakdown = nil
            return resolved
        }
        resolved.authoritativeScan = scan
        resolved.activeScan = scan.activeScanPrompt
        resolved.scoreBreakdown = scan.scoreBreakdownPrompt
        resolved.productContext = nil
        if var screenContext = resolved.screenContext {
            if screenContext.activeScanState == .none {
                screenContext.activeScanState = .saved
            }
            screenContext.activeScanID = scan.scanID
            screenContext.visibleOverallScore = scan.overallScore
            screenContext.selectedOccasion = scan.selectedOccasion ?? screenContext.selectedOccasion
            resolved.screenContext = screenContext
        }
        return resolved
    }
}

/// The sole constructor and resolver for scan facts consumed by conversational features.
/// Callers provide observed UI/persistence facts; this provider decides which completed
/// scan is authoritative and returns one immutable, typed context.
enum CurrentScanContextProvider {
    private struct StoredScan: Decodable {
        let score: Int
        let analysis: OutfitAnalysisResult?
        let firstScannedAt: Date
        let occasion: Occasion?
        let hasThumbnailData: Bool

        private enum CodingKeys: String, CodingKey {
            case score
            case analysis
            case firstScannedAt
            case occasion
            case thumbnailData
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            score = try container.decode(Int.self, forKey: .score)
            analysis = try container.decodeIfPresent(OutfitAnalysisResult.self, forKey: .analysis)
            firstScannedAt = try container.decode(Date.self, forKey: .firstScannedAt)
            occasion = try container.decodeIfPresent(Occasion.self, forKey: .occasion)
            if container.contains(.thumbnailData) {
                hasThumbnailData = try !container.decodeNil(forKey: .thumbnailData)
            } else {
                hasThumbnailData = false
            }
        }
    }

    static func latestCompleted(defaults: UserDefaults = .standard) -> StylistAuthoritativeScanContext? {
        guard let data = defaults.data(forKey: "outfitScanHistoryData"), !data.isEmpty,
              let scans = try? JSONDecoder().decode([String: StoredScan].self, from: data) else {
            return nil
        }
        return scans.compactMap { scanID, stored -> StylistAuthoritativeScanContext? in
            guard let analysis = stored.analysis,
                  (0...100).contains(stored.score),
                  analysis.score == stored.score else {
                return nil
            }
            return StylistAuthoritativeScanContext(
                scanID: scanID,
                completedAt: stored.firstScannedAt,
                overallScore: stored.score,
                scoreBreakdown: analysis.scoreBreakdown,
                detectedStyle: analysis.styleBalance,
                selectedOccasion: stored.occasion?.rawValue,
                occasionAssessment: analysis.occasionFit,
                weatherContext: analysis.environment,
                outfitClassification: analysis.outfitClassification,
                imageReference: stored.hasThumbnailData ? .onDeviceOnly : nil,
                source: .latestCompleted
            )
        }.sorted { left, right in
            if left.completedAt == right.completedAt { return left.scanID > right.scanID }
            return left.completedAt > right.completedAt
        }.first
    }

    static func make(
        scanID: String,
        completedAt: Date,
        analysis: OutfitAnalysisResult,
        detectedStyle: String?,
        styleConfidence: Int?,
        selectedOccasion: String?,
        occasionAssessment: String?,
        weatherContext: String?,
        imageReference: StylistScanImageReference?,
        groundedRecommendations: [GroundedRecommendation] = [],
        source: StylistScanContextSource,
        palette: [String] = [],
        topStyleMatches: [String] = [],
        evidenceLimitations: [String] = [],
        reliableWeatherSummary: String? = nil,
        outfitType: String? = nil
    ) -> StylistAuthoritativeScanContext {
        StylistAuthoritativeScanContext(
            scanID: scanID,
            completedAt: completedAt,
            overallScore: analysis.score,
            scoreBreakdown: analysis.scoreBreakdown,
            detectedStyle: detectedStyle,
            styleConfidence: styleConfidence,
            selectedOccasion: selectedOccasion,
            occasionAssessment: occasionAssessment,
            weatherContext: weatherContext,
            outfitClassification: analysis.outfitClassification,
            imageReference: imageReference,
            groundedRecommendations: groundedRecommendations,
            source: source,
            palette: palette,
            topStyleMatches: topStyleMatches,
            evidenceLimitations: evidenceLimitations,
            reliableWeatherSummary: reliableWeatherSummary,
            outfitType: outfitType
        )
    }

    static func resolve(
        preferred: StylistAuthoritativeScanContext?,
        screenContext: StylistScreenContext?,
        defaults: UserDefaults = .standard
    ) -> StylistAuthoritativeScanContext? {
        if let preferred, preferred.isComplete, preferred.matches(screenContext) {
            // An explicit live or saved selection is authoritative. A newer
            // history record is never allowed to silently replace it.
            return preferred
        }
        return latestCompleted(defaults: defaults)
    }
}

enum StylistSavedScanAvailability {
    static func savedScanIDs(defaults: UserDefaults = .standard) -> Set<String> {
        guard let data = defaults.data(forKey: "outfitScanHistoryData"),
              !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data),
              let history = object as? [String: Any] else {
            return []
        }
        return Set(history.keys)
    }
}

enum StylistConversationScreenContextResolver {
    static func resolve(
        _ screenContext: StylistScreenContext,
        hasAuthoritativeScanHandoff: Bool,
        savedScanIDs: Set<String>
    ) -> StylistScreenContext {
        // An explicit handoff is created by ScanView from the decoded scan the
        // user just opened. Do not downgrade it through a second raw-defaults
        // lookup that can lag account/environment snapshot restoration.
        if hasAuthoritativeScanHandoff,
           screenContext.activeScanState != .none {
            return screenContext
        }
        return screenContext.resolvingSavedScanAvailability(savedScanIDs)
    }
}

enum AIStylistContextSelection {
    static func activeScanContext(_ analysis: OutfitAnalysisResult) -> String {
        let garments = authoritativeGarments(in: analysis)
        return """
        Active scan (authoritative for the current outfit): overall score \(analysis.score)/100. \(garmentEvidence(garments)) \(paletteEvidence(analysis.colorPalette)) Do not bind a scan-level palette color to a specific garment unless that relationship is explicitly supplied.
        """
    }

    static func historicalScanContext(
        score: Int,
        analysis: OutfitAnalysisResult?,
        weatherConstraint: String = ""
    ) -> String {
        guard let analysis else {
            return "Historical saved scan (optional reference; not the current outfit): overall score \(score)/100; analysis details unavailable."
        }
        let authoritative = authoritativeGarments(in: analysis)
        let garments = historicalGarments(authoritative, weatherConstraint: weatherConstraint)
        let garmentSummary = authoritative.isEmpty
            ? garmentEvidence([])
            : garments.isEmpty
                ? "Historical outerwear was withheld because it conflicts with the supplied warm/hot weather."
                : garmentEvidence(garments)
        return """
        Historical saved scan (optional reference; not the current outfit): overall score \(score)/100. \(garmentSummary) \(paletteEvidence(analysis.colorPalette)) Treat every historical item as an optional reference, never as the user's current outfit or a closet-owned item.
        """
    }

    static func scoreContext(score: Int, analysis: OutfitAnalysisResult?, source: String) -> String {
        guard let breakdown = analysis?.scoreBreakdown else {
            return "Overall score from \(source): \(score)/100. Category breakdown unavailable for this saved scan. Do not identify a weakest category or give category-specific score reasoning."
        }

        let components: [(name: String, value: Int, maximum: Int)] = [
            ("color harmony", breakdown.colorHarmony, 25),
            ("pattern balance", breakdown.patternBalance, 20),
            ("fit quality", breakdown.fitQuality, 25),
            ("accessories", breakdown.accessoryUse, 10)
        ]
        let weakest = components.min { left, right in
            Double(left.value) / Double(left.maximum) < Double(right.value) / Double(right.maximum)
        }
        let componentSummary = components.map { "\($0.name) \($0.value)/\($0.maximum)" }.joined(separator: "; ")
        let weakestSummary = weakest.map {
            "Weakest persisted category: \($0.name), because its saved component is \($0.value)/\($0.maximum)."
        } ?? ""
        return "Overall score from \(source): \(score)/100. Persisted category scores: \(componentSummary). \(weakestSummary)"
    }

    static func weatherConstraint(defaults: UserDefaults) -> String {
        guard let snapshot = WeatherKitAuthority.loadSnapshot(defaults: defaults) else {
            return ""
        }
        return weatherConstraint(
            fahrenheit: snapshot.feelsLikeFahrenheit,
            condition: snapshot.condition
        )
    }

    static func weatherConstraint(fahrenheit: Int, condition: String = "") -> String {
        let evidence = condition.isEmpty ? "\(fahrenheit)°F" : "\(fahrenheit)°F and \(condition)"
        switch fahrenheit {
        case 80...:
            return "Weather suitability: hot at \(evidence). Do not recommend jackets, blazers, coats, sweaters, heavy fabrics, or layering unless a supplied environmental reason specifically justifies them."
        case 70...79:
            return "Weather suitability: warm at \(evidence). Do not recommend jackets, blazers, coats, sweaters, heavy fabrics, or layering unless a supplied environmental reason specifically justifies them."
        case ...50:
            return "Weather suitability: cold at \(evidence). Do not recommend shorts or sandals-only outfits without a supplied indoor or warm-environment reason."
        default:
            return "Weather suitability: moderate at \(evidence). Keep recommendations consistent with this supplied weather."
        }
    }

    static func authoritativeGarments(in analysis: OutfitAnalysisResult) -> [String] {
        let structured = Set(analysis.detectedClothingItems.compactMap(GarmentLabelMapper.humanReadableTerm))
        var seen = Set<String>()
        return analysis.detectedItemConfidences.compactMap { confidence in
            guard confidence.confidence >= ScanNarrativeFacts.authoritativeGarmentConfidence,
                  let garment = GarmentLabelMapper.humanReadableTerm(for: confidence.item),
                  structured.contains(garment),
                  seen.insert(garment).inserted else {
                return nil
            }
            return garment
        }
    }

    private static func historicalGarments(_ garments: [String], weatherConstraint: String) -> [String] {
        guard weatherConstraint.localizedCaseInsensitiveContains("warm")
                || weatherConstraint.localizedCaseInsensitiveContains("hot") else {
            return garments
        }
        let outerwear = Set(["jacket", "blazer", "coat", "sweater", "hoodie", "shacket"])
        return garments.filter { !outerwear.contains($0.lowercased()) }
    }

    private static func garmentEvidence(_ garments: [String]) -> String {
        garments.isEmpty
            ? "No garment type meets the authoritative 90% confidence threshold."
            : "Authoritative detected garments (90% or higher): \(garments.joined(separator: ", "))."
    }

    private static func paletteEvidence(_ palette: [String]) -> String {
        let colors = palette.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        return colors.isEmpty
            ? "No confident scan-level palette is available."
            : "Scan-level palette (not garment-specific): \(colors.joined(separator: ", "))."
    }

    private static func fahrenheitTemperature(from text: String) -> Int? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = cleaned.range(of: #"-?\d+(?:\.\d+)?"#, options: .regularExpression),
              let value = Double(cleaned[match]) else {
            return nil
        }
        if cleaned.lowercased().contains("°c") || cleaned.lowercased().contains(" c") {
            return Int((value * 9 / 5 + 32).rounded())
        }
        return Int(value.rounded())
    }
}

struct ChatRequest: Codable, Equatable {
    struct RequestMessage: Codable, Equatable {
        let role: String
        let content: String
    }

    let messages: [RequestMessage]
    let context: ChatContext
    let stream: Bool
    let contractVersion: Int?

    init(messages: [RequestMessage], context: ChatContext, stream: Bool) {
        self.messages = messages
        self.context = context
        self.stream = stream
        self.contractVersion = context.stylePreferences == nil ? nil : 2
    }

    enum CodingKeys: String, CodingKey {
        case messages, context, stream
        case contractVersion = "contract_version"
    }

    // The Worker v2 route is strict about context keys. Keep the richer local
    // ChatContext model for presentation/persistence, but emit only the
    // accepted wire projection so ordinary Stylist sends are not rejected with
    // HTTP 400 for unrelated local fields.
    private struct WireContext: Encodable {
        let stylePreferences: PersonalizationContextBuilder.ChatV2StylePreferences?
        let stylistContext: PersonalizationContextBuilder.StylistFactContextV1?
        let authoritativeScan: StylistAuthoritativeScanContext?
        let profileSummary: String
        let recentOutfits: String
        let scoreBreakdown: String?
        let activeScan: String
        let historicalOutfits: String
        enum CodingKeys: String, CodingKey { case stylePreferences; case stylistContext = "stylist_context"; case authoritativeScan; case profileSummary; case recentOutfits; case scoreBreakdown; case activeScan; case historicalOutfits }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(messages, forKey: .messages)
        try container.encode(WireContext(stylePreferences: context.stylePreferences, stylistContext: context.stylistFactContext, authoritativeScan: context.authoritativeScan, profileSummary: context.profileSummary, recentOutfits: context.recentOutfits, scoreBreakdown: context.scoreBreakdown, activeScan: context.activeScan, historicalOutfits: context.historicalOutfits), forKey: .context)
        try container.encode(stream, forKey: .stream)
        try container.encodeIfPresent(contractVersion, forKey: .contractVersion)
    }
}

/// The complete client-side representation of the accepted Worker Vision V1
/// wire contract. It deliberately has no consent, account, persistence key,
/// image-metadata, or client-supplied scope fields.
struct VisionChatRequestV1: Codable, Equatable {
    struct SelectedImage: Codable, Equatable {
        let mediaType: String
        let dataBase64: String

        enum CodingKeys: String, CodingKey {
            case mediaType = "media_type"
            case dataBase64 = "data_base64"
        }
    }

    struct Attachments: Codable, Equatable {
        let selectedImage: SelectedImage?
        let selectedScanFacts: StylistContextBuilder.VisionV1Attachments.SelectedScanFacts?
        let stylePreferences: StylistContextBuilder.VisionV1StylePreferences?
        let selectedClosetItems: [StylistContextBuilder.VisionV1Attachments.SelectedClosetItem]?

        enum CodingKeys: String, CodingKey {
            case selectedImage = "selected_image"
            case selectedScanFacts = "selected_scan_facts"
            case stylePreferences = "style_preferences"
            case selectedClosetItems = "selected_closet_items"
        }

        var isEmpty: Bool {
            selectedImage == nil && selectedScanFacts == nil && stylePreferences == nil && selectedClosetItems == nil
        }
    }

    let contractVersion: Int
    let requestID: String
    let prompt: String
    let attachments: Attachments

    enum CodingKeys: String, CodingKey {
        case contractVersion = "contract_version"
        case requestID = "request_id"
        case prompt, attachments
    }
}

struct VisionChatResponseV1: Codable, Equatable {
    struct Observation: Codable, Equatable {
        let kind: String
        let text: String
        let source: String
        let confidence: Double?
    }

    let contractVersion: Int
    let requestID: String
    let advice: String
    let observations: [Observation]
    let replayed: Bool

    enum CodingKeys: String, CodingKey {
        case contractVersion = "contract_version"
        case requestID = "request_id"
        case advice, observations, replayed
    }
}

enum StylistVisionRequestError: LocalizedError, Equatable {
    case invalidSelection
    case imageTooLarge
    case invalidResponse
    case consentRequired
    case requestMismatch
    case requestInProgress
    case outcomeUnknown
    case imageNotAllowed
    case providerRefused
    case providerUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidSelection: "That selected attachment could not be prepared safely."
        case .imageTooLarge: "Choose a photo under the supported size limit."
        case .invalidResponse: "The stylist returned an unavailable response. Try a new request."
        case .consentRequired: "Review the selected sharing permissions before sending."
        case .requestMismatch: "That request changed. Review your attachments and send again."
        case .requestInProgress: "That request is still being processed. Wait before trying again."
        case .outcomeUnknown: "We could not confirm the result. Select the attachment again before retrying."
        case .imageNotAllowed: "That image cannot be used for AI Stylist advice."
        case .providerRefused: "The stylist could not answer from that selection."
        case .providerUnavailable: "The stylist is temporarily unavailable. Try again later."
        }
    }
}

/// Request-only ImageIO normalization. It never writes an image, filename, or
/// source metadata to local storage; the resulting bytes live only in view
/// state until the single request is sent or discarded.
enum StylistVisionImageNormalizer {
    static let maximumPixels = 16_000_000
    static let maximumJPEGBytes = 5 * 1024 * 1024

    static func normalizeToJPEG(_ input: Data) throws -> VisionChatRequestV1.SelectedImage {
        guard let source = CGImageSourceCreateWithData(input as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0,
              width <= 20_000, height <= 20_000,
              width <= maximumPixels / height else {
            throw StylistVisionRequestError.imageTooLarge
        }
        let decodeOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, decodeOptions as CFDictionary),
              decoded.width > 0, decoded.height > 0,
              decoded.width <= maximumPixels / decoded.height,
              let context = CGContext(
                data: nil,
                width: decoded.width,
                height: decoded.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else {
            throw StylistVisionRequestError.invalidSelection
        }
        context.interpolationQuality = .high
        context.draw(decoded, in: CGRect(x: 0, y: 0, width: decoded.width, height: decoded.height))
        guard let image = context.makeImage() else { throw StylistVisionRequestError.invalidSelection }
        let destination = NSMutableData()
        guard let writer = CGImageDestinationCreateWithData(destination, "public.jpeg" as CFString, 1, nil) else {
            throw StylistVisionRequestError.invalidSelection
        }
        // Re-encoding a decoded CGImage writes no source container metadata.
        CGImageDestinationAddImage(writer, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(writer), destination.length <= maximumJPEGBytes else {
            throw StylistVisionRequestError.imageTooLarge
        }
        return .init(mediaType: "image/jpeg", dataBase64: (destination as Data).base64EncodedString())
    }
}

enum StylistChatMessageLimit {
    static let maximumUTF16Length = 2_000
    static let maximumPayloadMessages = 20
    static let retainedConversationMessages = 12
    static let limitMessage = "Messages are limited to 2,000 characters. Shorten your message before sending."

    static func utf16Length(of text: String) -> Int {
        text.utf16.count
    }

    static func trimmedForSending(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isWithinLimit(_ text: String) -> Bool {
        utf16Length(of: text) <= maximumUTF16Length
    }

    static func validationError(for messages: [ChatRequest.RequestMessage]) -> StylistChatError? {
        guard messages.count <= maximumPayloadMessages else { return .payloadTooLarge }
        for message in messages {
            let trimmed = trimmedForSending(message.content)
            guard !trimmed.isEmpty else { return .invalidRequest }
            guard isWithinLimit(message.content) else { return .payloadTooLarge }
        }
        return nil
    }
}

enum AIInsightConversationRole: Equatable {
    case user
    case assistant
}

struct AIInsightConversationEntry: Equatable {
    let role: AIInsightConversationRole
    let content: String
}

struct AIInsightStructuredRequest: Equatable {
    let history: [AIInsightConversationEntry]
    let primaryMessage: String
    let debugMessageSources: [String]
}

enum StylistQueryIntent: String, Codable, CaseIterable, Equatable, Sendable {
    case latestScore
    case explainScore
    case improveScore
    case weakestArea
    case footwear
    case shirtOrColor
    case completeOutfit
    case workplace
    case futureOrTomorrow
    case closet
    case accessory
    case general
    case clarification
}

enum WorkplaceEnvironment: String, Codable, CaseIterable, Equatable, Sendable {
    case factoryOrManufacturing
    case warehouseOrDistribution
    case office
    case healthcare
    case retail
    case hospitality
    case outdoorOrConstruction
    case mixedFloorAndOffice
    case remote
    case other
    case unknown
}

enum WorkplaceDressCode: String, Codable, CaseIterable, Equatable, Sendable {
    case uniform
    case safetyWorkwear
    case casual
    case businessCasual
    case businessFormal
    case other
    case unknown
}

enum WorkplaceFootwearConstraint: String, Codable, CaseIterable, Hashable, Sendable {
    case closedToe
    case slipResistant
    case safetyToe
    case protectiveBoot
    case noOpenHeel
    case other
    case unknown
}

enum WorkplaceActivityLevel: String, Codable, CaseIterable, Equatable, Sendable {
    case mostlySeated
    case mixed
    case mostlyStandingOrWalking
    case strenuous
    case unknown
}

enum WorkplaceExposure: String, Codable, CaseIterable, Equatable, Sendable {
    case indoorClimateControlled
    case indoorVariableTemperature
    case outdoor
    case mixed
    case unknown
}

enum WorkplaceContextSource: String, Codable, CaseIterable, Equatable, Sendable {
    case explicitCurrentMessage
    case explicitThreadCorrection
    case confirmedScanContext
    case savedProfile
    case unknown
}

enum WorkplaceConfirmation: String, Codable, CaseIterable, Equatable, Sendable {
    case userConfirmed
    case scanConfirmed
    case unconfirmed
}

struct WorkplaceContext: Codable, Equatable, Sendable {
    var environment: WorkplaceEnvironment
    var dressCode: WorkplaceDressCode
    var footwearConstraints: Set<WorkplaceFootwearConstraint>
    var ppeRequirements: Set<String>
    var activityLevel: WorkplaceActivityLevel
    var exposure: WorkplaceExposure
    var floorAndOfficeMix: Bool?
    var source: WorkplaceContextSource
    var confirmation: WorkplaceConfirmation
    var lastConfirmedAt: Date?

    static let unknown = WorkplaceContext(
        environment: .unknown,
        dressCode: .unknown,
        footwearConstraints: [.unknown],
        ppeRequirements: [],
        activityLevel: .unknown,
        exposure: .unknown,
        floorAndOfficeMix: nil,
        source: .unknown,
        confirmation: .unconfirmed,
        lastConfirmedAt: nil
    )

    var needsSafetyClarification: Bool {
        environment == .unknown
            || footwearConstraints.isEmpty
            || footwearConstraints.contains(.unknown)
    }
}

enum StylistWeatherTarget: String, Codable, CaseIterable, Equatable, Sendable {
    case current
    case tomorrow
    case specifiedDate
    case unknown
}

struct StylistWeatherContext: Codable, Equatable, Sendable {
    let target: StylistWeatherTarget
    let condition: String?
    let temperatureFahrenheit: Int?
    let observedAt: Date?
    let validUntil: Date?

    func isValid(at requestTime: Date = Date()) -> Bool {
        guard let validUntil else { return false }
        return validUntil >= requestTime
    }
}

struct StylistScoreBreakdownSnapshot: Codable, Equatable, Sendable {
    let colorHarmony: Int
    let patternBalance: Int
    let fitQuality: Int
    let occasionMatch: Int
    let accessoryUse: Int

    var weakestArea: (name: String, score: Int, maximum: Int)? {
        [
            ("color harmony", colorHarmony, 25),
            ("pattern balance", patternBalance, 20),
            ("fit", fitQuality, 25),
            ("accessories", accessoryUse, 10)
        ].min { lhs, rhs in
            let leftRatio = Double(lhs.1) / Double(lhs.2)
            let rightRatio = Double(rhs.1) / Double(rhs.2)
            return leftRatio == rightRatio ? lhs.0 < rhs.0 : leftRatio < rightRatio
        }
    }
}

struct StylistConversationSnapshot: Codable, Equatable, Sendable {
    let scanID: String?
    let score: Int?
    let breakdown: StylistScoreBreakdownSnapshot?
    let detectedStyle: String?
    let selectedOccasion: String?
    let observedGarments: [String]
    let observedColors: [String]
    let weather: StylistWeatherContext?
    var workplace: WorkplaceContext

    static let empty = StylistConversationSnapshot(
        scanID: nil,
        score: nil,
        breakdown: nil,
        detectedStyle: nil,
        selectedOccasion: nil,
        observedGarments: [],
        observedColors: [],
        weather: nil,
        workplace: .unknown
    )

    static func latestCompleted(defaults: UserDefaults = .standard) -> Self {
        from(CurrentScanContextProvider.latestCompleted(defaults: defaults))
    }

    static func from(_ scan: StylistAuthoritativeScanContext?) -> Self {
        guard let scan else { return .empty }

        let observedReferences = scan.groundedRecommendations?
            .flatMap(\.references)
            .filter { reference in
                switch reference {
                case let .garment(_, role), let .color(_, role):
                    return role == .observed
                }
            } ?? []
        let garments = Set(observedReferences.compactMap { reference -> String? in
            guard case let .garment(garment, _) = reference else { return nil }
            return garment.displayName
        }).sorted()
        let colors = Set(observedReferences.compactMap { reference -> String? in
            guard case let .color(color, _) = reference else { return nil }
            return color.displayName
        }).sorted()

        let breakdown = scan.scoreBreakdown.map {
            StylistScoreBreakdownSnapshot(
                colorHarmony: $0.colorHarmony,
                patternBalance: $0.patternBalance,
                fitQuality: $0.fitQuality,
                occasionMatch: $0.occasionMatch,
                accessoryUse: $0.accessoryUse
            )
        }

        return Self(
            scanID: scan.scanID,
            score: scan.overallScore,
            breakdown: breakdown,
            detectedStyle: scan.detectedStyle,
            selectedOccasion: scan.selectedOccasion,
            observedGarments: garments,
            observedColors: colors,
            weather: privacySafeWeather(from: scan),
            workplace: workplaceContext(from: scan)
        )
    }

    private static func workplaceContext(
        from scan: StylistAuthoritativeScanContext
    ) -> WorkplaceContext {
        guard let classification = scan.outfitClassification,
              classification.userConfirmedCategory != nil else {
            return .unknown
        }

        let dressCode: WorkplaceDressCode
        switch classification.effectiveCategory {
        case .workUniform, .brandedWorkwear, .schoolUniform, .medicalScrubs:
            dressCode = .uniform
        default:
            return .unknown
        }

        return WorkplaceContext(
            environment: .unknown,
            dressCode: dressCode,
            footwearConstraints: [.unknown],
            ppeRequirements: [],
            activityLevel: .unknown,
            exposure: .unknown,
            floorAndOfficeMix: nil,
            source: .confirmedScanContext,
            confirmation: .scanConfirmed,
            lastConfirmedAt: scan.completedAt
        )
    }

    private static func privacySafeWeather(
        from scan: StylistAuthoritativeScanContext
    ) -> StylistWeatherContext? {
        guard let raw = scan.weatherContext?.lowercased(), !raw.isEmpty else {
            return nil
        }
        let conditionTerms = [
            "partly cloudy", "mostly cloudy", "cloudy", "clear", "sunny",
            "rain", "snow", "windy", "fog", "storm"
        ]
        let condition = conditionTerms.first { raw.contains($0) }
        let temperature = firstFahrenheitTemperature(in: raw)
        guard condition != nil || temperature != nil else { return nil }
        return StylistWeatherContext(
            target: .current,
            condition: condition,
            temperatureFahrenheit: temperature,
            observedAt: scan.completedAt,
            validUntil: scan.completedAt.addingTimeInterval(3 * 60 * 60)
        )
    }

    private static func firstFahrenheitTemperature(in text: String) -> Int? {
        let characters = Array(text)
        for index in characters.indices where characters[index] == "f" {
            var cursor = index
            var digits = ""
            while cursor > characters.startIndex {
                let previous = characters.index(before: cursor)
                let character = characters[previous]
                if character.isNumber || (character == "-" && digits.count < 3) {
                    digits.insert(character, at: digits.startIndex)
                    cursor = previous
                    continue
                }
                if character == "°" || character.isWhitespace {
                    cursor = previous
                    continue
                }
                break
            }
            if let value = Int(digits), (-50...150).contains(value) {
                return value
            }
        }
        return nil
    }
}

/// Supplies compact, context-sensitive starting questions without pretending
/// that a recommendation has already been made. The same snapshot is later
/// sent through the typed request envelope at send time.
enum StylistConversationStarterPrompts {
    static func prompts(
        snapshot: StylistConversationSnapshot,
        workplaceOverride: WorkplaceContext? = nil
    ) -> [String] {
        let workplace = workplaceOverride ?? snapshot.workplace
        var prompts: [String] = []

        if snapshot.scanID != nil {
            prompts += [
                "Make this outfit more professional.",
                "What shoes work with this outfit?",
                "Give me a warmer-weather version."
            ]
        }

        if workplace.environment == .factoryOrManufacturing
            || workplace.environment == .mixedFloorAndOffice {
            prompts.append("Build an outfit for a factory-and-office day.")
        }

        if snapshot.weather?.isValid() != true {
            prompts.append("What should I wear today?")
        }

        prompts += ["Build from my closet.", "What am I missing?", "Dress me for work."]
        return Array(NSOrderedSet(array: prompts)) as? [String] ?? prompts
    }
}

enum StylistContextAvailability: String, Codable, Equatable, Sendable {
    case available
    case unavailable
}

struct StylistWeatherRequestContext: Codable, Equatable, Sendable {
    let availability: StylistContextAvailability
    let value: StylistWeatherContext?
    let constraint: String

    static let unavailable = Self(
        availability: .unavailable,
        value: nil,
        constraint: ""
    )
}

struct StylistWorkplaceRequestContext: Codable, Equatable, Sendable {
    let availability: StylistContextAvailability
    let value: WorkplaceContext

    static let unavailable = Self(
        availability: .unavailable,
        value: .unknown
    )
}

struct StylistUniformRequestContext: Codable, Equatable, Sendable {
    let availability: StylistContextAvailability
    let dressCode: WorkplaceDressCode
    let confirmation: WorkplaceConfirmation

    static let unavailable = Self(
        availability: .unavailable,
        dressCode: .unknown,
        confirmation: .unconfirmed
    )
}

struct StylistSafetyRequestContext: Codable, Equatable, Sendable {
    let availability: StylistContextAvailability
    let footwearConstraints: Set<WorkplaceFootwearConstraint>
    let ppeRequirements: Set<String>

    static let unavailable = Self(
        availability: .unavailable,
        footwearConstraints: [.unknown],
        ppeRequirements: []
    )
}

struct StylistRouteContextAttachment: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let snapshot: StylistConversationSnapshot
    let weather: StylistWeatherRequestContext
    let workplace: StylistWorkplaceRequestContext
    let uniform: StylistUniformRequestContext
    let safety: StylistSafetyRequestContext

    static let unavailable = Self(
        schemaVersion: 1,
        snapshot: .empty,
        weather: .unavailable,
        workplace: .unavailable,
        uniform: .unavailable,
        safety: .unavailable
    )

    static func resolving(
        authoritativeScan: StylistAuthoritativeScanContext?,
        weatherConstraint: String,
        requestTime: Date = Date()
    ) -> Self {
        resolving(
            snapshot: StylistConversationSnapshot.from(authoritativeScan),
            weatherConstraint: weatherConstraint,
            requestTime: requestTime
        )
    }

    /// Builds the existing V1 envelope from a bounded conversation snapshot.
    /// It does not rewrite a saved scan or promote a user correction to scan
    /// authority; the snapshot remains conversation evidence.
    static func resolving(
        snapshot: StylistConversationSnapshot,
        weatherConstraint: String,
        requestTime: Date = Date()
    ) -> Self {
        let normalizedWeatherConstraint = weatherConstraint
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let validWeather = snapshot.weather.flatMap {
            $0.isValid(at: requestTime) ? $0 : nil
        }
        let weather: StylistWeatherRequestContext
        if validWeather != nil || !normalizedWeatherConstraint.isEmpty {
            weather = StylistWeatherRequestContext(
                availability: .available,
                value: validWeather,
                constraint: normalizedWeatherConstraint
            )
        } else {
            weather = .unavailable
        }

        let workplaceValue = snapshot.workplace
        let hasWorkplaceEvidence = workplaceValue.environment != .unknown
            || workplaceValue.dressCode != .unknown
            || workplaceValue.footwearConstraints.contains { $0 != .unknown }
            || !workplaceValue.ppeRequirements.isEmpty
            || workplaceValue.activityLevel != .unknown
            || workplaceValue.exposure != .unknown
            || workplaceValue.floorAndOfficeMix != nil
            || workplaceValue.source != .unknown
            || workplaceValue.confirmation != .unconfirmed
        let workplace = hasWorkplaceEvidence
            ? StylistWorkplaceRequestContext(
                availability: .available,
                value: workplaceValue
            )
            : .unavailable

        let isUniform = workplaceValue.dressCode == .uniform
            || workplaceValue.dressCode == .safetyWorkwear
        let uniform = isUniform
            ? StylistUniformRequestContext(
                availability: .available,
                dressCode: workplaceValue.dressCode,
                confirmation: workplaceValue.confirmation
            )
            : .unavailable

        let safetyFootwear = workplaceValue.footwearConstraints.filter { $0 != .unknown }
        let hasSafetyEvidence = !safetyFootwear.isEmpty || !workplaceValue.ppeRequirements.isEmpty
        let safety = hasSafetyEvidence
            ? StylistSafetyRequestContext(
                availability: .available,
                footwearConstraints: safetyFootwear,
                ppeRequirements: workplaceValue.ppeRequirements
            )
            : .unavailable

        return Self(
            schemaVersion: 1,
            snapshot: snapshot,
            weather: weather,
            workplace: workplace,
            uniform: uniform,
            safety: safety
        )
    }
}

enum StylistSemanticResponseID: String, Codable, CaseIterable, Hashable, Sendable {
    case workplaceSafetyClarification
    case latestScore
    case weakestArea
    case tomorrowWeatherUnavailable
}

struct StylistConversationState: Equatable, Sendable {
    var workplaceOverride: WorkplaceContext?
    var emittedSemanticResponses: Set<StylistSemanticResponseID> = []

    mutating func applyExplicitWorkplaceDetails(from message: String, now: Date = Date()) {
        guard let environment = StylistConversationRouter.explicitWorkplaceEnvironment(in: message) else {
            return
        }
        let normalized = message.lowercased()
        var constraints = Set<WorkplaceFootwearConstraint>()
        if normalized.contains("steel toe") || normalized.contains("safety toe") {
            constraints.insert(.safetyToe)
        }
        if normalized.contains("slip resistant") || normalized.contains("non-slip") {
            constraints.insert(.slipResistant)
        }
        if normalized.contains("closed toe") {
            constraints.insert(.closedToe)
        }
        if normalized.contains("boot") {
            constraints.insert(.protectiveBoot)
        }
        if constraints.isEmpty {
            constraints.insert(.unknown)
        }
        workplaceOverride = WorkplaceContext(
            environment: environment,
            dressCode: .unknown,
            footwearConstraints: constraints,
            ppeRequirements: normalized.contains("ppe") ? ["user-confirmed PPE requirement"] : [],
            activityLevel: .unknown,
            exposure: .unknown,
            floorAndOfficeMix: environment == .mixedFloorAndOffice ? true : nil,
            source: .explicitThreadCorrection,
            confirmation: .userConfirmed,
            lastConfirmedAt: now
        )
    }

    /// Reconstructs only customer-confirmed workplace corrections from this
    /// conversation. Incidental or hypothetical workplace references are not
    /// authority and deliberately remain ordinary chat text.
    static func reconstructing(
        messages: [ChatMessage],
        including message: String? = nil,
        now: Date = Date()
    ) -> Self {
        var state = Self()
        for message in messages {
            switch message.role {
            case .user:
                state.applyExplicitCurrentThreadWorkplaceCorrection(from: message.content, now: now)
            case .assistant:
                if let semanticID = message.localSemanticResponseID {
                    state.emittedSemanticResponses.insert(semanticID)
                }
            case .system:
                break
            }
        }
        if let message {
            state.applyExplicitCurrentThreadWorkplaceCorrection(from: message, now: now)
        }
        return state
    }

    var intelligenceThreadCorrection: StylistIntelligenceThreadCorrection? {
        guard let workplaceOverride else { return nil }
        return StylistIntelligenceThreadCorrection(
            workplace: workplaceOverride,
            customerVisibleFact: Self.customerVisibleFact(for: workplaceOverride)
        )
    }

    private mutating func applyExplicitCurrentThreadWorkplaceCorrection(
        from message: String,
        now: Date
    ) {
        guard Self.isExplicitCurrentThreadCorrection(message),
              StylistConversationRouter.explicitWorkplaceEnvironment(in: message) != nil else {
            return
        }
        applyExplicitWorkplaceDetails(from: message, now: now)
    }

    private static func isExplicitCurrentThreadCorrection(_ message: String) -> Bool {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("\"") && !trimmed.hasPrefix("“") && !trimmed.hasPrefix("'") else {
            return false
        }
        let normalized = trimmed.lowercased().replacingOccurrences(of: "’", with: "'")
        let hypotheticalPrefixes = [
            "if i work", "if i'm working", "if i were", "would this work",
            "could this work", "what works in", "do you work"
        ]
        guard !hypotheticalPrefixes.contains(where: { normalized.hasPrefix($0) }) else {
            return false
        }
        let confirmationMarkers = [
            "i work in", "i work at", "i am working in", "i'm working in",
            "my workplace is", "for my job,", "actually, i work", "i'm on the", "i am on the"
        ]
        return confirmationMarkers.contains(where: { normalized.hasPrefix($0) })
    }

    private static func customerVisibleFact(for workplace: WorkplaceContext) -> String {
        let environment: String
        switch workplace.environment {
        case .factoryOrManufacturing: environment = "factory or manufacturing"
        case .warehouseOrDistribution: environment = "warehouse or distribution"
        case .office: environment = "office"
        case .healthcare: environment = "healthcare"
        case .retail: environment = "retail"
        case .hospitality: environment = "hospitality"
        case .outdoorOrConstruction: environment = "outdoor or construction"
        case .mixedFloorAndOffice: environment = "mixed floor and office"
        case .remote: environment = "remote work"
        case .other: environment = "another workplace"
        case .unknown: environment = "an unknown workplace"
        }
        var details = ["Workplace: \(environment)"]
        if workplace.footwearConstraints.contains(.safetyToe) {
            details.append("safety-toe footwear required")
        }
        if workplace.footwearConstraints.contains(.slipResistant) {
            details.append("slip-resistant footwear required")
        }
        if !workplace.ppeRequirements.isEmpty {
            details.append("PPE requirements confirmed")
        }
        return details.joined(separator: "; ")
    }
}

struct StylistConversationPreflight: Equatable, Sendable {
    let intent: StylistQueryIntent
    let localReply: String?
    let semanticResponseID: StylistSemanticResponseID?
}

enum StylistConversationRouter {
    static func latestScoreReply(for score: Int?) -> String {
        guard let score else {
            return "I do not have a completed scan score in the current context."
        }
        return "Your latest completed KigoStylist scan scored \(score)/100 — \(StyleMatchHomeDisplay.scoreBand(for: score).title)."
    }

    static func classify(_ message: String) -> StylistQueryIntent {
        let text = normalized(message)
        if containsAny(text, [
            "last score", "latest score", "score now", "what was my score",
            "what is my score", "can you see my score", "how did i do",
            "what did i score", "tell me my score"
        ]) {
            return .latestScore
        }
        if containsAny(text, ["why did i get", "explain my score", "why this score"]) {
            return .explainScore
        }
        if containsAny(text, ["weakest", "lowest category", "lowest area"]) {
            return .weakestArea
        }
        if containsAny(text, ["improve", "raise my score", "better score"]) {
            return .improveScore
        }
        if containsAny(text, ["shoe", "footwear", "sneaker", "loafer", "heel"]) {
            return .footwear
        }
        if containsAny(text, ["tomorrow", "future", "next week", "later this week"]) {
            return .futureOrTomorrow
        }
        if containsAny(text, ["dress me for work", "work outfit", "wear to work", "workplace"]) {
            return .workplace
        }
        if containsAny(text, ["shirt", "what color", "colour"]) {
            return .shirtOrColor
        }
        if containsAny(text, ["complete outfit", "full outfit", "whole look"]) {
            return .completeOutfit
        }
        if containsAny(text, ["closet", "wardrobe", "saved clothes"]) {
            return .closet
        }
        if containsAny(text, ["accessory", "accessories", "watch", "belt", "bag"]) {
            return .accessory
        }
        return .general
    }

    static func preflight(
        message: String,
        snapshot: StylistConversationSnapshot,
        state: StylistConversationState
    ) -> StylistConversationPreflight {
        let intent = classify(message)
        let workplace = state.workplaceOverride ?? snapshot.workplace
        let workRequested = intent == .workplace
            || intent == .footwear && snapshot.selectedOccasion?.localizedCaseInsensitiveContains("work") == true

        if workRequested, workplace.needsSafetyClarification {
            let repeated = state.emittedSemanticResponses.contains(.workplaceSafetyClarification)
            let reply = repeated
                ? "I still need your workplace type and any safety-shoe or PPE requirements before I can recommend footwear or a work outfit."
                : "What kind of workplace is this for—factory or manufacturing, warehouse or distribution, office, healthcare, retail or hospitality, outdoor or construction, mixed floor and office, remote, or something else? Are safety shoes or PPE required?"
            return StylistConversationPreflight(
                intent: intent,
                localReply: reply,
                semanticResponseID: .workplaceSafetyClarification
            )
        }

        if intent == .latestScore {
            return StylistConversationPreflight(
                intent: intent,
                localReply: latestScoreReply(for: snapshot.score),
                semanticResponseID: .latestScore
            )
        }

        if intent == .weakestArea {
            let reply = snapshot.breakdown?.weakestArea.map {
                "Your lowest scored area in this scan is \($0.name) at \($0.score)/\($0.maximum)."
            } ?? "I cannot identify a weakest area because this scan has no complete score breakdown."
            return StylistConversationPreflight(
                intent: intent,
                localReply: reply,
                semanticResponseID: .weakestArea
            )
        }

        if intent == .futureOrTomorrow,
           snapshot.weather?.target != .tomorrow {
            return StylistConversationPreflight(
                intent: intent,
                localReply: "I do not have a valid forecast for tomorrow in this conversation yet, so I will not reuse today’s weather.",
                semanticResponseID: .tomorrowWeatherUnavailable
            )
        }

        return StylistConversationPreflight(intent: intent, localReply: nil, semanticResponseID: nil)
    }

    static func explicitWorkplaceEnvironment(in message: String) -> WorkplaceEnvironment? {
        let text = normalized(message)
        if containsAny(text, ["factory", "manufacturing", "plant floor"]) { return .factoryOrManufacturing }
        if containsAny(text, ["warehouse", "distribution center"]) { return .warehouseOrDistribution }
        if containsAny(text, ["healthcare", "hospital", "clinic"]) { return .healthcare }
        if containsAny(text, ["construction", "outdoor site", "jobsite"]) { return .outdoorOrConstruction }
        if containsAny(text, ["retail", "store floor"]) { return .retail }
        if containsAny(text, ["hospitality", "hotel", "restaurant"]) { return .hospitality }
        if containsAny(text, ["mixed floor", "floor and office", "office and floor"]) { return .mixedFloorAndOffice }
        if containsAny(text, ["remote", "work from home", "home office"]) { return .remote }
        if containsAny(text, ["office", "corporate"]) { return .office }
        return nil
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containsAny(_ text: String, _ terms: [String]) -> Bool {
        terms.contains { text.contains($0) }
    }
}

struct AIInsightChatCardFacts: Equatable {
    let screen: String
    let title: String
    let featurePrompt: String
    let extraContext: String
    let snapshot: StylistConversationSnapshot

    init(
        screen: String,
        title: String,
        featurePrompt: String,
        extraContext: String,
        snapshot: StylistConversationSnapshot = .empty
    ) {
        self.screen = screen
        self.title = title
        self.featurePrompt = featurePrompt
        self.extraContext = extraContext
        self.snapshot = snapshot
    }
}

enum AIInsightChatPromptBuilder {
    static let maximumMessageUTF16Length = 1_800
    static let maximumPayloadMessages = 20

    private static let localFailureReplies: Set<String> = [
        "AI Stylist is having trouble connecting right now. Please try again.",
        "The stylist is having trouble replying right now.",
        StylistChatMessageLimit.limitMessage
    ]

    static func build(
        displayedMessages: [AIInsightConversationEntry],
        latestQuestion: String,
        cardFacts: AIInsightChatCardFacts
    ) throws -> AIInsightStructuredRequest {
        let preparedQuestion = StylistChatMessageLimit.trimmedForSending(latestQuestion)
        guard !preparedQuestion.isEmpty else {
            throw StylistChatError.invalidRequest
        }

        let primary = try makePrimaryMessage(
            latestQuestion: preparedQuestion,
            cardFacts: cardFacts
        )

        let eligibleHistory = displayedMessages.compactMap { entry -> AIInsightConversationEntry? in
            let content = StylistChatMessageLimit.trimmedForSending(entry.content)
            guard !content.isEmpty else {
                return nil
            }
            if entry.role == .assistant, isLocalFailureReply(content) {
                return nil
            }
            return AIInsightConversationEntry(
                role: entry.role,
                content: truncatedToUTF16Limit(content, limit: maximumMessageUTF16Length)
            )
        }

        let maximumHistoryMessages = maximumPayloadMessages - 1
        let retainedHistory = Array(eligibleHistory.suffix(maximumHistoryMessages))
        return AIInsightStructuredRequest(
            history: retainedHistory,
            primaryMessage: primary.message,
            debugMessageSources: retainedHistory.map {
                $0.role == .user ? "history_user" : "history_assistant"
            } + [primary.sources.sorted().joined(separator: ",")]
        )
    }

    private struct PrimaryMessage {
        let message: String
        let sources: Set<String>
    }

    private struct ContextFact {
        let text: String
        let source: String
    }

    private static func makePrimaryMessage(
        latestQuestion: String,
        cardFacts: AIInsightChatCardFacts
    ) throws -> PrimaryMessage {
        let intent = StylistConversationRouter.classify(latestQuestion)
        let prefix = """
        Newest customer question:
        \(latestQuestion)

        Essential card facts:
        - Typed query intent: \(intent.rawValue)
        """
        let suffix = """

        Guardrails:
        1. \(StyleMatchAIGuardrails.scoreIntegrityInstruction)
        2. Use only supplied facts; never invent closet ownership, scan facts, profile details, or weather.
        3. Follow the typed query intent. Answer footwear questions with footwear guidance only.
        4. Hard workplace safety constraints override style. If workplace or footwear safety is unknown, ask for clarification before recommending shoes.
        5. Never infer an employer, wearer identity, occupation, workplace, or precise location.
        6. Never reuse current weather for a future or tomorrow request.
        7. Give one or two concrete suggestions and do not repeat a prior semantic recommendation.
        """
        let fixedLength = utf16Length(prefix) + utf16Length(suffix)
        guard fixedLength <= maximumMessageUTF16Length else {
            throw StylistChatError.payloadTooLarge
        }

        let candidates = compactFactCandidates(cardFacts)
        var selected: [ContextFact] = []
        var remaining = maximumMessageUTF16Length - fixedLength
        for candidate in candidates {
            let separatorLength = selected.isEmpty ? 0 : 1
            let candidateLength = utf16Length(candidate.text) + separatorLength
            guard candidateLength <= remaining else { continue }
            selected.append(candidate)
            remaining -= candidateLength
        }

        if selected.isEmpty {
            let fallback = ContextFact(
                text: "- No additional card facts were supplied.",
                source: "system_generated"
            )
            guard utf16Length(fallback.text) <= remaining else {
                throw StylistChatError.payloadTooLarge
            }
            selected = [fallback]
        }

        let message = prefix + selected.map(\.text).joined(separator: "\n") + suffix
        return PrimaryMessage(
            message: message,
            sources: Set(selected.map(\.source)).union(["latest_user", "system_generated"])
        )
    }

    private static func compactFactCandidates(_ cardFacts: AIInsightChatCardFacts) -> [ContextFact] {
        var fixedFacts: [ContextFact] = []
        if let line = factLine(label: "Screen", value: cardFacts.screen) {
            fixedFacts.append(ContextFact(text: line, source: "system_generated"))
        }
        if let line = factLine(label: "Card", value: cardFacts.title) {
            fixedFacts.append(ContextFact(text: line, source: "system_generated"))
        }
        if let line = factLine(label: "Feature", value: cardFacts.featurePrompt) {
            fixedFacts.append(ContextFact(text: line, source: "system_generated"))
        }

        let typedFacts = typedContextFacts(cardFacts.snapshot)
        let contextFacts = contextFacts(from: cardFacts.extraContext)
        let sourcePriority = ["closet_context", "score_context", "scan_context", "workplace_context", "weather_context", "profile_context", "system_generated"]
        let firstPerSource = sourcePriority.compactMap { source in
            contextFacts.first { $0.source == source }
        }
        let firstTexts = Set(firstPerSource.map(\.text))
        return fixedFacts + typedFacts + firstPerSource + contextFacts.filter { !firstTexts.contains($0.text) }
    }

    private static func typedContextFacts(_ snapshot: StylistConversationSnapshot) -> [ContextFact] {
        var facts: [ContextFact] = []
        if let scanID = snapshot.scanID {
            facts.append(ContextFact(text: "- Authoritative scan ID: \(scanID)", source: "scan_context"))
        }
        if let score = snapshot.score {
            facts.append(ContextFact(text: "- Authoritative score: \(score)/100", source: "score_context"))
        }
        if let style = snapshot.detectedStyle {
            facts.append(ContextFact(text: "- Detected visual style: \(style)", source: "scan_context"))
        }
        if let occasion = snapshot.selectedOccasion {
            facts.append(ContextFact(text: "- Selected occasion: \(occasion)", source: "scan_context"))
        }
        if !snapshot.observedGarments.isEmpty {
            facts.append(ContextFact(
                text: "- Observed garments only: \(snapshot.observedGarments.joined(separator: ", "))",
                source: "scan_context"
            ))
        }
        if !snapshot.observedColors.isEmpty {
            facts.append(ContextFact(
                text: "- Observed palette only: \(snapshot.observedColors.joined(separator: ", "))",
                source: "scan_context"
            ))
        }
        let workplace = snapshot.workplace
        let hasWorkplaceEvidence = workplace.environment != .unknown
            || workplace.dressCode != .unknown
            || workplace.footwearConstraints.contains { $0 != .unknown }
            || !workplace.ppeRequirements.isEmpty
            || workplace.activityLevel != .unknown
            || workplace.confirmation != .unconfirmed
        if hasWorkplaceEvidence {
            facts.append(ContextFact(
                text: "- Workplace context: environment=\(workplace.environment.rawValue), dressCode=\(workplace.dressCode.rawValue), footwear=\(workplace.footwearConstraints.map(\.rawValue).sorted().joined(separator: ",")), confirmation=\(workplace.confirmation.rawValue)",
                source: "workplace_context"
            ))
        }
        if let weather = snapshot.weather {
            let temperature = weather.temperatureFahrenheit.map { "\($0)F" } ?? "unknown"
            facts.append(ContextFact(
                text: "- Weather target: \(weather.target.rawValue), condition=\(weather.condition ?? "unknown"), temperature=\(temperature), valid=\(weather.isValid())",
                source: "weather_context"
            ))
        }
        return facts
    }

    private static func contextFacts(from value: String) -> [ContextFact] {
        value
            .split(whereSeparator: \.isNewline)
            .flatMap { rawLine -> [ContextFact] in
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { return [] }
                let source = contextSource(for: line)
                if line.lowercased().hasPrefix("saved items:") {
                    let entries = line.dropFirst("saved items:".count).split(separator: ";")
                    return entries.compactMap { entry in
                        let item = entry.trimmingCharacters(in: .whitespacesAndNewlines)
                        return item.isEmpty ? nil : ContextFact(text: "- Saved closet item: \(item)", source: source)
                    }
                }
                return [ContextFact(text: "- Context: \(line)", source: source)]
            }
    }

    private static func contextSource(for line: String) -> String {
        let normalized = line.lowercased()
        if normalized.contains("saved item") || normalized.contains("closet") || normalized.contains("favorite outfit") || normalized.contains("most worn") {
            return "closet_context"
        }
        if normalized.contains("score") || normalized.contains("rating") {
            return "score_context"
        }
        if normalized.contains("scan") || normalized.contains("detected") || normalized.contains("palette") {
            return "scan_context"
        }
        if normalized.contains("weather") || normalized.contains("temperature") || normalized.contains("forecast") {
            return "weather_context"
        }
        if normalized.contains("profile") || normalized.contains("size") || normalized.contains("budget") || normalized.contains("preference") || normalized.contains("brand") {
            return "profile_context"
        }
        return "system_generated"
    }

    private static func factLine(label: String, value: String) -> String? {
        let prepared = StylistChatMessageLimit.trimmedForSending(value)
        return prepared.isEmpty ? nil : "- \(label): \(prepared)"
    }

    private static func isLocalFailureReply(_ content: String) -> Bool {
        if localFailureReplies.contains(content) {
            return true
        }
        let normalized = content.lowercased()
        return normalized.contains("stylist is having trouble connecting")
            || normalized.contains("stylist is having trouble replying")
    }

    private static func utf16Length(_ text: String) -> Int {
        text.utf16.count
    }

    private static func truncatedToUTF16Limit(_ text: String, limit: Int) -> String {
        guard utf16Length(text) > limit else { return text }

        var result = ""
        var usedUnits = 0
        for character in text {
            let units = String(character).utf16.count
            guard usedUnits + units <= limit else { break }
            result.append(character)
            usedUnits += units
        }
        return result
    }
}

enum AIInsightChatErrorPresentation {
    static let connectivityMessage = "AI Stylist is having trouble connecting right now. Please try again."

    static func shouldAppendFailureReply(_ message: String, after lastReply: String?) -> Bool {
        lastReply != message
    }

    static func message(for error: Error) -> String {
        if let diagnostic = error as? StylistChatDiagnosticError,
           diagnostic.category == .payloadTooLarge {
            return StylistChatMessageLimit.limitMessage
        }
        if let chatError = error as? StylistChatError,
           chatError == .payloadTooLarge {
            return StylistChatMessageLimit.limitMessage
        }
        return connectivityMessage
    }
}

enum StylistChatError: LocalizedError, Equatable {
    case missingConfiguration
    case unauthorized
    case payloadTooLarge
    case rateLimited
    case providerError
    case invalidRequest
    case network
    case aiTransmissionConsentRequired

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "Chat is not configured yet."
        case .unauthorized:
            return "Sign in with Apple to use the live AI Stylist."
        case .payloadTooLarge:
            return StylistChatMessageLimit.limitMessage
        case .rateLimited:
            return "You have hit the hourly limit. Try again soon."
        case .providerError:
            return "The stylist is having trouble replying right now."
        case .invalidRequest:
            return "That message could not be sent."
        case .network:
            return "Could not connect to the stylist. Check your connection and try again."
        case .aiTransmissionConsentRequired:
            return "Review AI transmission privacy before sending a request."
        }
    }
}

enum StylistChatRequestPhase: String, Equatable {
    case response
    case transport
}

struct StylistChatDiagnosticError: LocalizedError, Equatable, CustomDebugStringConvertible {
    let category: StylistChatError
    let statusCode: Int?
    let requestPhase: StylistChatRequestPhase

    var errorDescription: String? { category.errorDescription }

    var debugDescription: String {
        [
            "category=\(category)",
            statusCode.map { "status=\($0)" },
            "phase=\(requestPhase.rawValue)"
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }
}

/// Bounded developer-only delivery evidence retained by the chat service.
/// It is intentionally separate from the user-facing error copy.
struct StylistChatDeliveryDiagnostic: Equatable {
    let category: StylistChatError
    let statusCode: Int?
    let requestPhase: StylistChatRequestPhase?
    let conversationScope: StylistConversationScope
    let outboundMessageCount: Int
    let isLocalValidation: Bool

    init(
        error: Error?,
        scope: StylistConversationScope,
        outboundMessageCount: Int
    ) {
        let diagnostic = error as? StylistChatDiagnosticError
        category = diagnostic?.category ?? (error as? StylistChatError) ?? .providerError
        statusCode = diagnostic?.statusCode
        requestPhase = diagnostic?.requestPhase
        conversationScope = scope
        self.outboundMessageCount = max(0, outboundMessageCount)
        isLocalValidation = false
    }

    static func localValidation(
        scope: StylistConversationScope,
        outboundMessageCount: Int,
        detail _: String
    ) -> Self {
        Self(
            category: .invalidRequest,
            statusCode: nil,
            requestPhase: nil,
            conversationScope: scope,
            outboundMessageCount: max(0, outboundMessageCount),
            isLocalValidation: true
        )
    }

    private init(
        category: StylistChatError,
        statusCode: Int?,
        requestPhase: StylistChatRequestPhase?,
        conversationScope: StylistConversationScope,
        outboundMessageCount: Int,
        isLocalValidation: Bool
    ) {
        self.category = category
        self.statusCode = statusCode
        self.requestPhase = requestPhase
        self.conversationScope = conversationScope
        self.outboundMessageCount = outboundMessageCount
        self.isLocalValidation = isLocalValidation
    }

}
