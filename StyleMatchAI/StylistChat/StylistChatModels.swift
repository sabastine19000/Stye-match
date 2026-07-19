import Foundation

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

    init(
        id: UUID = UUID(),
        role: StylistChatRole,
        content: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

struct ChatConversation: Identifiable, Codable, Equatable {
    var id: UUID
    var messages: [ChatMessage]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        messages: [ChatMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        messages = try container.decodeIfPresent([ChatMessage].self, forKey: .messages) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}

enum StylistScreenTab: String, Codable, Equatable {
    case home
    case scan
    case closet
    case shop
    case ai
    case profile
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

    init(
        currentTab: StylistScreenTab,
        activeScanState: StylistActiveScanState,
        activeScanID: String? = nil,
        selectedOccasion: String? = nil,
        selectedAnalysisSection: String? = nil,
        visibleOverallScore: Int? = nil,
        entryPoint: StylistEntryPoint,
        visibleAggregates: StylistVisibleAggregateStatistics? = nil,
        closetState: StylistClosetState
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

    init(
        profileSummary: String = "",
        recentOutfits: String = "",
        activeScan: String = "",
        historicalOutfits: String = "",
        weatherConstraint: String = "",
        scoreBreakdown: String? = nil,
        screenContext: StylistScreenContext? = nil
    ) {
        self.profileSummary = Self.clamp(profileSummary, max: 600)
        self.recentOutfits = Self.clamp(recentOutfits, max: 800)
        self.activeScan = Self.clamp(activeScan, max: 800)
        self.historicalOutfits = Self.clamp(historicalOutfits, max: 800)
        self.weatherConstraint = Self.clamp(weatherConstraint, max: 300)
        self.scoreBreakdown = scoreBreakdown.map { Self.clamp($0, max: 500) }
        self.screenContext = screenContext
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
            screenContext: try container.decodeIfPresent(StylistScreenContext.self, forKey: .screenContext)
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
    }

    private static func clamp(_ text: String, max: Int) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(max))
    }
}

struct StylistScanHandoff: Equatable {
    let context: ChatContext
    let screenContext: StylistScreenContext

    init(context: ChatContext, screenContext: StylistScreenContext) {
        self.screenContext = screenContext
        var resolvedContext = context
        resolvedContext.screenContext = screenContext
        self.context = resolvedContext
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
            closetState: screenContext.closetState
        )
    }

    var aiChatContext: ChatContext {
        var resolvedContext = context
        resolvedContext.screenContext = aiScreenContext
        return resolvedContext
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
        }
        return resolved
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
        let feelsLike = defaults.string(forKey: "weatherFeelsLike") ?? ""
        let temperature = defaults.string(forKey: "weather") ?? ""
        let condition = defaults.string(forKey: "weatherCondition")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let fahrenheit = fahrenheitTemperature(from: feelsLike)
                ?? fahrenheitTemperature(from: temperature) else {
            return ""
        }
        return weatherConstraint(fahrenheit: fahrenheit, condition: condition)
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

struct AIInsightChatCardFacts: Equatable {
    let screen: String
    let title: String
    let featurePrompt: String
    let extraContext: String
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
        let prefix = """
        Newest customer question:
        \(latestQuestion)

        Essential card facts:
        """
        let suffix = """

        Guardrails:
        1. \(StyleMatchAIGuardrails.scoreIntegrityInstruction)
        2. Use only supplied facts; never invent closet ownership, scan facts, profile details, or weather.
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

        let contextFacts = contextFacts(from: cardFacts.extraContext)
        let sourcePriority = ["closet_context", "score_context", "scan_context", "weather_context", "profile_context", "system_generated"]
        let firstPerSource = sourcePriority.compactMap { source in
            contextFacts.first { $0.source == source }
        }
        let firstTexts = Set(firstPerSource.map(\.text))
        return fixedFacts + firstPerSource + contextFacts.filter { !firstTexts.contains($0.text) }
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
        }
    }
}

struct StylistChatDiagnosticError: LocalizedError, Equatable, CustomDebugStringConvertible {
    let category: StylistChatError
    let statusCode: Int?
    let responseBody: String?
    let requestID: String?
    let endpoint: URL
    let underlyingErrorDescription: String?

    var errorDescription: String? { category.errorDescription }

    var debugDescription: String {
        [
            "category=\(category)",
            statusCode.map { "status=\($0)" },
            responseBody.map { "body=\($0)" },
            requestID.map { "request_id=\($0)" },
            "endpoint=\(endpoint.absoluteString)",
            underlyingErrorDescription.map { "underlying=\($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }
}
