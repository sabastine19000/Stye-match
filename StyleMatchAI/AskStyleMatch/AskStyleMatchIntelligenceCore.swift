import Foundation

/// The three deliberately separated Ask StyleMatch specialties.  A route is
/// chosen for each request and its permission set is never inherited by the
/// other specialties.
enum AskStyleMatchMode: String, CaseIterable, Codable, Equatable, Sendable {
    case fashionStylist = "fashion_stylist"
    case appSupport = "app_support"
    case writingAssist = "writing_assist"
}

enum AskStyleMatchModeSelection: Codable, Equatable, Sendable {
    case automatic
    case manual(AskStyleMatchMode)
}

/// Each scope describes a narrow, user-consented category of information.
/// It deliberately has no raw-image, account credential, thread-history, or
/// private-message scope.
enum AskStyleMatchScope: String, CaseIterable, Codable, Hashable, Sendable {
    case publicFashionKnowledge = "public_fashion_knowledge"
    case publicSupportKnowledge = "public_support_knowledge"
    case currentResearch = "current_research"
    case basicAccountStatus = "basic_account_status"
    case profilePreferences = "profile_preferences"
    case closetSummary = "closet_summary"
    case scanSummary = "scan_summary"
    case weatherOccasion = "weather_occasion"
    case budgetBrand = "budget_brand"
    case selectedWritingText = "selected_writing_text"
}

/// A facts-only scan envelope.  Score and classification must be copied from
/// the completed scan authority by the caller; this type cannot calculate or
/// mutate either value and intentionally excludes the scan image.
struct AskStyleMatchScanFacts: Codable, Equatable, Sendable {
    let score: Int
    let classification: String
    let summary: String

    init(score: Int, classification: String, summary: String) {
        self.score = score
        self.classification = classification
        self.summary = summary
    }
}

struct AskStyleMatchRequest: Codable, Equatable, Sendable {
    static let maximumQuestionCharacters = 2_000

    let clientRequestReference: UUID
    let modeSelection: AskStyleMatchModeSelection
    /// The exact user-authored text. Validation never trims, translates, or
    /// otherwise rewrites it.
    let question: String
    let localeIdentifier: String
    let grantedScopes: Set<AskStyleMatchScope>
    let scanFacts: AskStyleMatchScanFacts?
    let selectedWritingText: String?

    init(
        clientRequestReference: UUID = UUID(),
        modeSelection: AskStyleMatchModeSelection = .automatic,
        question: String,
        localeIdentifier: String,
        grantedScopes: Set<AskStyleMatchScope> = [],
        scanFacts: AskStyleMatchScanFacts? = nil,
        selectedWritingText: String? = nil
    ) {
        self.clientRequestReference = clientRequestReference
        self.modeSelection = modeSelection
        self.question = question
        self.localeIdentifier = localeIdentifier
        self.grantedScopes = grantedScopes
        self.scanFacts = scanFacts
        self.selectedWritingText = selectedWritingText
    }

    func validate() throws {
        guard !question.isEmpty, question.count <= Self.maximumQuestionCharacters else {
            throw AskStyleMatchValidationError.invalidQuestionLength
        }
    }
}

enum AskStyleMatchValidationError: Error, Equatable {
    case invalidQuestionLength
    case missingScanFacts
    case missingSelectedWritingText
}

struct AskStyleMatchRoute: Equatable, Sendable {
    let mode: AskStyleMatchMode
    let permittedScopes: Set<AskStyleMatchScope>
    let requiresClarification: Bool
    let unavailableCapabilityNotice: String?
}

/// Deterministic local routing. It does not infer private context and does
/// not call a provider. Manual mode always wins; automatic multi-intent input
/// asks the person to choose a specialty rather than leaking data between
/// specialties.
enum AskStyleMatchPolicyRouter {
    static func route(_ request: AskStyleMatchRequest) throws -> AskStyleMatchRoute {
        try request.validate()

        let selectedMode: AskStyleMatchMode
        let ambiguous: Bool
        switch request.modeSelection {
        case let .manual(mode):
            selectedMode = mode
            ambiguous = false
        case .automatic:
            let candidates = automaticCandidates(for: request.question)
            selectedMode = candidates.first ?? .fashionStylist
            ambiguous = candidates.count > 1
        }

        if selectedMode == .fashionStylist,
           request.grantedScopes.contains(.scanSummary),
           request.scanFacts == nil {
            throw AskStyleMatchValidationError.missingScanFacts
        }
        if selectedMode == .writingAssist,
           request.grantedScopes.contains(.selectedWritingText),
           request.selectedWritingText == nil || request.selectedWritingText?.isEmpty == true {
            throw AskStyleMatchValidationError.missingSelectedWritingText
        }

        var permitted = permittedScopes(for: selectedMode).intersection(request.grantedScopes)
        // Public knowledge is permitted by the specialty itself and does not
        // constitute personal context transmission.
        permitted.formUnion(permittedScopes(for: selectedMode).intersection([.publicFashionKnowledge, .publicSupportKnowledge]))

        if selectedMode != .writingAssist {
            permitted.remove(.selectedWritingText)
        }
        if selectedMode == .writingAssist {
            // Writing Assist only sees text explicitly supplied for this
            // request; it cannot acquire chat history or personal context.
            permitted = request.grantedScopes.contains(.selectedWritingText) ? [.selectedWritingText] : []
        }

        let researchNotice = permitted.contains(.currentResearch)
            ? "Current research is unavailable in this local-only build."
            : nil
        // Research is a future explicit capability and never runs locally.
        permitted.remove(.currentResearch)

        return AskStyleMatchRoute(
            mode: selectedMode,
            permittedScopes: permitted,
            requiresClarification: ambiguous,
            unavailableCapabilityNotice: researchNotice
        )
    }

    private static func permittedScopes(for mode: AskStyleMatchMode) -> Set<AskStyleMatchScope> {
        switch mode {
        case .fashionStylist:
            return [.publicFashionKnowledge, .profilePreferences, .closetSummary, .scanSummary, .weatherOccasion, .budgetBrand, .currentResearch]
        case .appSupport:
            return [.publicSupportKnowledge, .basicAccountStatus]
        case .writingAssist:
            return [.selectedWritingText]
        }
    }

    private static func automaticCandidates(for question: String) -> [AskStyleMatchMode] {
        let text = question.lowercased()
        var candidates: [AskStyleMatchMode] = []
        if ["app", "sign in", "login", "notification", "settings", "support"].contains(where: text.contains) {
            candidates.append(.appSupport)
        }
        if ["rewrite", "draft", "caption", "message", "write"].contains(where: text.contains) {
            candidates.append(.writingAssist)
        }
        if ["wear", "outfit", "style", "fashion", "closet", "scan"].contains(where: text.contains) || candidates.isEmpty {
            candidates.append(.fashionStylist)
        }
        return candidates
    }
}

struct AskStyleMatchProviderRequestDescriptor: Equatable, Sendable {
    let clientRequestReference: UUID
    let route: AskStyleMatchRoute
    let store: Bool
    let background: Bool
    let conversationReference: String?
}

enum AskStyleMatchProviderError: Error, Equatable {
    case unavailableInLocalBuild
}

protocol AskStyleMatchProvider {
    func respond(to descriptor: AskStyleMatchProviderRequestDescriptor) async throws -> String
}

/// The local phase uses a provider seam only. Its descriptor freezes the
/// future Responses API privacy settings (`store: false`, no conversation and
/// no background work), but it never sends a network request or embeds a key.
struct AskStyleMatchLocalOnlyProvider: AskStyleMatchProvider {
    func respond(to descriptor: AskStyleMatchProviderRequestDescriptor) async throws -> String {
        throw AskStyleMatchProviderError.unavailableInLocalBuild
    }
}

enum AskStyleMatchIntelligenceCore {
    static func providerDescriptor(for request: AskStyleMatchRequest) throws -> AskStyleMatchProviderRequestDescriptor {
        let route = try AskStyleMatchPolicyRouter.route(request)
        return AskStyleMatchProviderRequestDescriptor(
            clientRequestReference: request.clientRequestReference,
            route: route,
            store: false,
            background: false,
            conversationReference: nil
        )
    }
}

/// Plain-language, request-scoped disclosure shown before transmission. It is
/// derived only from the selected scopes and deliberately contains no raw
/// scan image or local private-message capability.
struct AskStyleMatchPrivacyDisclosure: Equatable, Sendable {
    let selectedScopeLabels: [String]
    static let processorStatement = "OpenAI processes the supplied context to generate your requested answer."
    static let imageStatement = "Raw scan images are not included."
    static let revocationStatement = "Withdrawing AI Processing Consent stops future transmissions; it does not retroactively control third-party safety or abuse-monitoring retention."

    static func make(for scopes: Set<AskStyleMatchScope>) -> AskStyleMatchPrivacyDisclosure {
        let labels = scopes.map { scope in
            switch scope {
            case .profilePreferences: "Profile preferences"
            case .closetSummary: "Closet summary"
            case .scanSummary: "Completed scan facts"
            case .weatherOccasion: "Weather and occasion"
            case .budgetBrand: "Budget and brands"
            case .basicAccountStatus: "Basic account status"
            case .selectedWritingText: "Selected writing text"
            case .publicFashionKnowledge, .publicSupportKnowledge, .currentResearch: "No personal context"
            }
        }.sorted()
        return .init(selectedScopeLabels: labels)
    }
}

/// Versioned, explicit JSON projection for the only permitted Ask StyleMatch
/// network request. Synthesized Codable output is deliberately not used for
/// the associated-value mode enum.
struct AskStyleMatchV2WireRequest: Encodable, Equatable {
    static let contractVersion = 2

    struct ModeSelection: Encodable, Equatable {
        let kind: String
        let mode: String?

        enum CodingKeys: String, CodingKey { case kind, mode }
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(kind, forKey: .kind)
            try container.encodeIfPresent(mode, forKey: .mode)
        }
    }

    struct ScanFacts: Encodable, Equatable {
        let score: Int
        let classification: String
        let summary: String
    }

    struct Message: Encodable, Equatable {
        let role: String
        let content: String
    }

    let contractVersion: Int
    let clientRequestReference: String
    let consentVersion: String
    let modeSelection: ModeSelection
    let grantedScopes: [String]
    let messages: [Message]
    let scanFacts: ScanFacts?
    let selectedWritingText: String?

    enum CodingKeys: String, CodingKey {
        case contractVersion = "contract_version"
        case clientRequestReference = "client_request_reference"
        case consentVersion = "consent_version"
        case modeSelection = "mode_selection"
        case grantedScopes = "granted_scopes"
        case messages
        case scanFacts = "scan_facts"
        case selectedWritingText = "selected_writing_text"
    }

    init(request: AskStyleMatchRequest, consentVersion: String = AITransmissionConsentStore.disclosureVersion) throws {
        // The local policy is the client-side minimization boundary.  The
        // server independently revalidates the resulting explicit scopes.
        let route = try AskStyleMatchPolicyRouter.route(request)
        let selection: ModeSelection
        switch request.modeSelection {
        case .automatic:
            selection = .init(kind: "automatic", mode: nil)
        case let .manual(mode):
            selection = .init(kind: "manual", mode: mode.rawValue)
        }

        // Public knowledge is a local routing capability, not a personal
        // context grant. Only scopes the person explicitly selected are sent.
        let scopes = request.grantedScopes.intersection(route.permittedScopes).map(\.rawValue).sorted()
        let writingText: String?
        if scopes.contains(AskStyleMatchScope.selectedWritingText.rawValue) {
            guard let supplied = request.selectedWritingText, !supplied.isEmpty, supplied.count <= AskStyleMatchRequest.maximumQuestionCharacters else {
                throw AskStyleMatchValidationError.missingSelectedWritingText
            }
            writingText = supplied
        } else {
            writingText = nil
        }

        let facts: ScanFacts?
        if scopes.contains(AskStyleMatchScope.scanSummary.rawValue) {
            guard let scan = request.scanFacts else { throw AskStyleMatchValidationError.missingScanFacts }
            facts = .init(score: scan.score, classification: scan.classification, summary: scan.summary)
        } else {
            facts = nil
        }

        contractVersion = Self.contractVersion
        clientRequestReference = request.clientRequestReference.uuidString.lowercased()
        self.consentVersion = consentVersion
        modeSelection = selection
        grantedScopes = scopes
        messages = [.init(role: "user", content: request.question)]
        scanFacts = facts
        selectedWritingText = writingText
    }
}
