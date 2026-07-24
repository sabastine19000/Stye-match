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
    /// The authoritative scan used when this turn was created. Optional for
    /// backward-compatible decoding of conversations saved by older builds.
    var scanContextID: String?

    init(
        id: UUID = UUID(),
        role: StylistChatRole,
        content: String,
        timestamp: Date = Date(),
        scanContextID: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.scanContextID = scanContextID
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
        source: StylistScanContextSource
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
        if let detectedStyle { facts.append("detected style \(detectedStyle)") }
        if let styleConfidence { facts.append("style confidence \(styleConfidence)%") }
        if let selectedOccasion { facts.append("selected occasion \(selectedOccasion)") }
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

    init(
        profileSummary: String = "",
        recentOutfits: String = "",
        activeScan: String = "",
        historicalOutfits: String = "",
        weatherConstraint: String = "",
        scoreBreakdown: String? = nil,
        screenContext: StylistScreenContext? = nil,
        authoritativeScan: StylistAuthoritativeScanContext? = nil
    ) {
        self.profileSummary = Self.clamp(profileSummary, max: 600)
        self.recentOutfits = Self.clamp(recentOutfits, max: 800)
        self.activeScan = Self.clamp(activeScan, max: 800)
        self.historicalOutfits = Self.clamp(historicalOutfits, max: 800)
        self.weatherConstraint = Self.clamp(weatherConstraint, max: 300)
        self.scoreBreakdown = scoreBreakdown.map { Self.clamp($0, max: 500) }
        self.screenContext = screenContext
        self.authoritativeScan = authoritativeScan
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
            authoritativeScan: try container.decodeIfPresent(StylistAuthoritativeScanContext.self, forKey: .authoritativeScan)
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
        source: StylistScanContextSource
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
            source: source
        )
    }

    static func resolve(
        preferred: StylistAuthoritativeScanContext?,
        screenContext: StylistScreenContext?,
        defaults: UserDefaults = .standard
    ) -> StylistAuthoritativeScanContext? {
        if let preferred, preferred.isComplete, preferred.matches(screenContext) {
            if preferred.source == .savedSelection { return preferred }
            if let latest = latestCompleted(defaults: defaults), latest.completedAt > preferred.completedAt {
                return latest
            }
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
}

struct StylistConversationPreflight: Equatable, Sendable {
    let intent: StylistQueryIntent
    let localReply: String?
    let semanticResponseID: StylistSemanticResponseID?
}

enum StylistConversationRouter {
    static func classify(_ message: String) -> StylistQueryIntent {
        let text = normalized(message)
        if containsAny(text, ["last score", "latest score", "score now", "what was my score"]) {
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
            let reply = snapshot.score.map { "Your latest completed StyleMatch scan scored \($0)/100." }
                ?? "I do not have a completed scan score in the current context."
            return StylistConversationPreflight(
                intent: intent,
                localReply: reply,
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
