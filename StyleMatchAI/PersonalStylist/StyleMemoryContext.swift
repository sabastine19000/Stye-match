import Combine
import Foundation

/// A privacy-safe identity boundary for all future StyleMatch memory.
/// The context itself is an ephemeral read model; its source domains retain
/// their own durable records and remain their own authorities.
enum StyleMemoryIdentityScope: String, Codable, Equatable, Sendable {
    case guest
    case apple

    static func resolve(defaults: UserDefaults = .standard) -> Self {
        AccountScopedStorage.sessionUserID(defaults: defaults) == "guest" ? .guest : .apple
    }
}

enum StyleMemoryScopeKind: String, Codable, Equatable, Hashable, Sendable {
    case generalStylist
    case activeScan
    case savedScan
    case wardrobeItem
    case outfitPlan
    case shoppingItem
}

/// A reference domain is deliberately separate from presentation scope. A Scan
/// selected from saved history is not interchangeable with an active Scan just
/// because an identifier happens to match.
enum StyleMemoryReferenceDomain: String, Codable, Equatable, Hashable, Sendable {
    case activeScan
    case savedScan
    case wardrobeItem
    case outfitPlan
    case shoppingItem
}

struct StyleMemoryScope: Codable, Equatable, Sendable {
    let kind: StyleMemoryScopeKind
    let stableID: String?

    init(kind: StyleMemoryScopeKind, stableID: String? = nil) {
        let normalized = stableID?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.kind = kind
        self.stableID = normalized?.isEmpty == false ? normalized : nil
    }

    static let generalStylist = Self(kind: .generalStylist)

    var requiresStableID: Bool {
        switch kind {
        case .generalStylist: false
        case .activeScan, .savedScan, .wardrobeItem, .outfitPlan, .shoppingItem: true
        }
    }

    var isValid: Bool { requiresStableID == false || stableID != nil }

    var expectedReferenceDomain: StyleMemoryReferenceDomain? {
        switch kind {
        case .generalStylist: nil
        case .activeScan: .activeScan
        case .savedScan: .savedScan
        case .wardrobeItem: .wardrobeItem
        case .outfitPlan: .outfitPlan
        case .shoppingItem: .shoppingItem
        }
    }
}

enum StyleMemoryProvenance: String, Codable, CaseIterable, Equatable, Sendable {
    case explicitCorrection
    case explicitSelection
    case openedSavedScan
    case completedActiveScan
    case manualOccasion
    case authorizedCalendarEvent
    case freshWeather
    case profile
    case wardrobe
    case localDateDefault
    case unavailable

    var authorityPriority: Int {
        switch self {
        case .explicitCorrection: 100
        case .explicitSelection: 90
        case .openedSavedScan: 80
        case .completedActiveScan: 70
        case .manualOccasion: 60
        case .authorizedCalendarEvent: 50
        case .freshWeather: 40
        case .profile: 30
        case .wardrobe: 20
        case .localDateDefault: 10
        case .unavailable: 0
        }
    }
}

enum StyleMemoryConfidence: String, Codable, Equatable, Sendable {
    case confirmed
    case detected
    case inferred
    case limited
    case unavailable
}

enum StyleMemoryPermissionState: String, Codable, Equatable, Sendable {
    case notRequired
    case notDetermined
    case authorized
    case denied
    case restricted
    case unavailable
}

/// Persistent facts have no expiry. Expiring facts must carry a future
/// `expiresAt`; session facts are valid only for their originating session.
enum StyleMemoryFactLifetime: String, Codable, Equatable, Sendable {
    case persistent
    case expiresAt
    case session
}

struct StyleMemoryFact<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    let value: Value?
    let provenance: StyleMemoryProvenance
    let observedAt: Date?
    let expiresAt: Date?
    let confidence: StyleMemoryConfidence
    let permission: StyleMemoryPermissionState
    let identityScope: StyleMemoryIdentityScope?
    let lifetime: StyleMemoryFactLifetime
    let sessionID: String?

    init(
        value: Value?,
        provenance: StyleMemoryProvenance,
        observedAt: Date? = nil,
        expiresAt: Date? = nil,
        confidence: StyleMemoryConfidence,
        permission: StyleMemoryPermissionState = .notRequired,
        identityScope: StyleMemoryIdentityScope? = nil,
        lifetime: StyleMemoryFactLifetime = .persistent,
        sessionID: String? = nil
    ) {
        self.value = value
        self.provenance = value == nil ? .unavailable : provenance
        self.observedAt = observedAt
        self.expiresAt = expiresAt
        self.confidence = value == nil ? .unavailable : confidence
        self.permission = permission
        self.identityScope = identityScope
        self.lifetime = lifetime
        self.sessionID = sessionID
    }

    var isAvailable: Bool { value != nil && provenance != .unavailable }

    func isFresh(at date: Date, sessionID currentSessionID: String? = nil) -> Bool {
        guard isAvailable else { return false }
        switch lifetime {
        case .persistent:
            return true
        case .expiresAt:
            return expiresAt.map { date < $0 } ?? false
        case .session:
            return sessionID != nil && sessionID == currentSessionID
        }
    }

    func isAvailable(for identity: StyleMemoryIdentityScope) -> Bool {
        isAvailable && (identityScope == nil || identityScope == identity)
    }

    static var unavailable: Self {
        Self(value: nil, provenance: .unavailable, confidence: .unavailable, permission: .unavailable)
    }
}

struct StyleMemoryReference: Codable, Equatable, Sendable, Hashable {
    let domain: StyleMemoryReferenceDomain
    let stableID: String

    init?(domain: StyleMemoryReferenceDomain, stableID: String) {
        let normalized = stableID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= 256 else { return nil }
        self.domain = domain
        self.stableID = normalized
    }
}

struct StyleMemoryScanSummary: Codable, Equatable, Sendable {
    let reference: StyleMemoryReference
    let summary: String
}

struct StyleMemoryAuthority: Codable, Equatable, Sendable {
    let scope: StyleMemoryScope
    let selectedReference: StyleMemoryReference?
    let provenance: StyleMemoryProvenance

    var isResolved: Bool { scope.isValid && (scope.requiresStableID == false || selectedReference != nil) }
}

struct StyleMemoryContextInput: Equatable, Sendable {
    let identityScope: StyleMemoryIdentityScope
    let scope: StyleMemoryScope
    let explicitSelection: StyleMemoryFact<StyleMemoryReference>
    let openedSavedScan: StyleMemoryFact<StyleMemoryReference>
    let completedActiveScan: StyleMemoryFact<StyleMemoryReference>
    let selectedScanSummary: StyleMemoryFact<StyleMemoryScanSummary>
    let manualOccasion: StyleMemoryFact<String>
    let calendarOccasion: StyleMemoryFact<String>
    let weatherSummary: StyleMemoryFact<String>
    let profileSummary: StyleMemoryFact<String>
    let workplaceSummary: StyleMemoryFact<String>
    let wardrobeReferences: StyleMemoryFact<[StyleMemoryReference]>
    let shoppingReference: StyleMemoryFact<StyleMemoryReference>

    init(
        identityScope: StyleMemoryIdentityScope,
        scope: StyleMemoryScope,
        explicitSelection: StyleMemoryFact<StyleMemoryReference> = .unavailable,
        openedSavedScan: StyleMemoryFact<StyleMemoryReference> = .unavailable,
        completedActiveScan: StyleMemoryFact<StyleMemoryReference> = .unavailable,
        selectedScanSummary: StyleMemoryFact<StyleMemoryScanSummary> = .unavailable,
        manualOccasion: StyleMemoryFact<String> = .unavailable,
        calendarOccasion: StyleMemoryFact<String> = .unavailable,
        weatherSummary: StyleMemoryFact<String> = .unavailable,
        profileSummary: StyleMemoryFact<String> = .unavailable,
        workplaceSummary: StyleMemoryFact<String> = .unavailable,
        wardrobeReferences: StyleMemoryFact<[StyleMemoryReference]> = .unavailable,
        shoppingReference: StyleMemoryFact<StyleMemoryReference> = .unavailable
    ) {
        self.identityScope = identityScope
        self.scope = scope
        self.explicitSelection = explicitSelection
        self.openedSavedScan = openedSavedScan
        self.completedActiveScan = completedActiveScan
        self.selectedScanSummary = selectedScanSummary
        self.manualOccasion = manualOccasion
        self.calendarOccasion = calendarOccasion
        self.weatherSummary = weatherSummary
        self.profileSummary = profileSummary
        self.workplaceSummary = workplaceSummary
        self.wardrobeReferences = wardrobeReferences
        self.shoppingReference = shoppingReference
    }
}

struct StyleMemoryContext: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let identityScope: StyleMemoryIdentityScope
    let authority: StyleMemoryAuthority
    let selectedScan: StyleMemoryFact<StyleMemoryReference>
    let selectedScanSummary: StyleMemoryFact<StyleMemoryScanSummary>
    let occasion: StyleMemoryFact<String>
    let weather: StyleMemoryFact<String>
    let profile: StyleMemoryFact<String>
    let workplace: StyleMemoryFact<String>
    let wardrobe: StyleMemoryFact<[StyleMemoryReference]>
    let shopping: StyleMemoryFact<StyleMemoryReference>

    var isWorkerProjectable: Bool { authority.isResolved }
}

enum StyleMemoryAuthorityResolver {
    /// Stable authority order after an exact domain-and-ID match is: explicit
    /// selection, opened saved Scan, then completed active Scan.
    static func resolve(
        _ input: StyleMemoryContextInput,
        now: Date = Date(),
        sessionID: String? = nil
    ) -> StyleMemoryContext {
        let authority = resolveAuthority(input)
        let selectedScanSummary = resolvedSelectedScanSummary(
            input.selectedScanSummary,
            authority: authority,
            identity: input.identityScope
        )
        return StyleMemoryContext(
            schemaVersion: StyleMemoryContext.currentSchemaVersion,
            identityScope: input.identityScope,
            authority: authority,
            selectedScan: selectedScanFact(for: authority, input: input),
            selectedScanSummary: selectedScanSummary,
            occasion: preferred(
                available(input.manualOccasion, for: input.identityScope),
                over: authorizedCalendar(input.calendarOccasion, identity: input.identityScope, now: now, sessionID: sessionID)
            ),
            weather: freshWeather(input.weatherSummary, identity: input.identityScope, now: now, sessionID: sessionID),
            profile: available(input.profileSummary, for: input.identityScope),
            workplace: available(input.workplaceSummary, for: input.identityScope),
            wardrobe: available(input.wardrobeReferences, for: input.identityScope),
            shopping: available(input.shoppingReference, for: input.identityScope)
        )
    }

    private static func resolveAuthority(_ input: StyleMemoryContextInput) -> StyleMemoryAuthority {
        let candidates = [input.explicitSelection, input.openedSavedScan, input.completedActiveScan]
            .map { available($0, for: input.identityScope) }

        switch input.scope.kind {
        case .generalStylist:
            return StyleMemoryAuthority(scope: input.scope, selectedReference: nil, provenance: .unavailable)
        case .activeScan, .savedScan:
            guard let expectedID = input.scope.stableID,
                  let expectedDomain = input.scope.expectedReferenceDomain else {
                return StyleMemoryAuthority(scope: input.scope, selectedReference: nil, provenance: .unavailable)
            }
            guard let expected = StyleMemoryReference(domain: expectedDomain, stableID: expectedID) else {
                return StyleMemoryAuthority(scope: input.scope, selectedReference: nil, provenance: .unavailable)
            }

            // An explicit request is a hard authority boundary: if it misses,
            // an older candidate must not silently substitute another Scan.
            if input.explicitSelection.isAvailable(for: input.identityScope) {
                return authority(for: expected, candidate: available(input.explicitSelection, for: input.identityScope), scope: input.scope)
            }
            let matched = candidates.first { $0.value == expected }
            return StyleMemoryAuthority(
                scope: input.scope,
                selectedReference: matched?.value,
                provenance: matched?.provenance ?? .unavailable
            )
        case .wardrobeItem, .outfitPlan, .shoppingItem:
            let reference = input.scope.expectedReferenceDomain.flatMap {
                StyleMemoryReference(domain: $0, stableID: input.scope.stableID ?? "")
            }
            return StyleMemoryAuthority(scope: input.scope, selectedReference: reference, provenance: reference == nil ? .unavailable : .explicitSelection)
        }
    }

    private static func authority(
        for expected: StyleMemoryReference,
        candidate: StyleMemoryFact<StyleMemoryReference>,
        scope: StyleMemoryScope
    ) -> StyleMemoryAuthority {
        guard candidate.value == expected else {
            return StyleMemoryAuthority(scope: scope, selectedReference: nil, provenance: .unavailable)
        }
        return StyleMemoryAuthority(scope: scope, selectedReference: expected, provenance: candidate.provenance)
    }

    private static func selectedScanFact(
        for authority: StyleMemoryAuthority,
        input: StyleMemoryContextInput
    ) -> StyleMemoryFact<StyleMemoryReference> {
        guard authority.scope.kind == .activeScan || authority.scope.kind == .savedScan,
              let selected = authority.selectedReference else {
            return .unavailable
        }
        return StyleMemoryFact(
            value: selected,
            provenance: authority.provenance,
            confidence: .confirmed
        )
    }

    private static func resolvedSelectedScanSummary(
        _ summary: StyleMemoryFact<StyleMemoryScanSummary>,
        authority: StyleMemoryAuthority,
        identity: StyleMemoryIdentityScope
    ) -> StyleMemoryFact<StyleMemoryScanSummary> {
        guard let selectedReference = authority.selectedReference,
              let value = available(summary, for: identity).value,
              value.reference == selectedReference else {
            return .unavailable
        }
        return available(summary, for: identity)
    }

    private static func preferred<Value: Codable & Equatable & Sendable>(
        _ primary: StyleMemoryFact<Value>,
        over fallback: StyleMemoryFact<Value>
    ) -> StyleMemoryFact<Value> {
        primary.isAvailable ? primary : fallback
    }

    private static func available<Value: Codable & Equatable & Sendable>(
        _ fact: StyleMemoryFact<Value>,
        for identity: StyleMemoryIdentityScope
    ) -> StyleMemoryFact<Value> {
        fact.isAvailable(for: identity) ? fact : .unavailable
    }

    private static func freshWeather(
        _ weather: StyleMemoryFact<String>,
        identity: StyleMemoryIdentityScope,
        now: Date,
        sessionID: String?
    ) -> StyleMemoryFact<String> {
        let scoped = available(weather, for: identity)
        guard scoped.provenance == .freshWeather,
              scoped.lifetime == .expiresAt,
              scoped.isFresh(at: now, sessionID: sessionID) else {
            return .unavailable
        }
        return scoped
    }

    private static func authorizedCalendar(
        _ calendar: StyleMemoryFact<String>,
        identity: StyleMemoryIdentityScope,
        now: Date,
        sessionID: String?
    ) -> StyleMemoryFact<String> {
        let scoped = available(calendar, for: identity)
        guard scoped.provenance == .authorizedCalendarEvent,
              scoped.permission == .authorized,
              scoped.lifetime == .expiresAt,
              scoped.isFresh(at: now, sessionID: sessionID) else {
            return .unavailable
        }
        return scoped
    }
}

/// Explicit boundary: context snapshots are derived at request time and are not
/// a second persistence authority. Durable data remains in its source store.
enum StyleMemoryPersistenceBoundary {
    static let contextSchemaVersion = StyleMemoryContext.currentSchemaVersion

    static func scopedAuditKey(for identity: StyleMemoryIdentityScope) -> String {
        "styleMemoryContext.audit.\(identity.rawValue)"
    }

    static func canPersist(_ context: StyleMemoryContext) -> Bool {
        false
    }

    static func deletionKeys(for identity: StyleMemoryIdentityScope) -> [String] {
        [scopedAuditKey(for: identity)]
    }
}

// MARK: - Explicit persistent AI memory

/// Deliberately small, user-facing categories. These are not copies of the
/// Profile, scan history, Closet, Shopping, Calendar, Weather, or chat stores.
enum AIPersistentMemoryCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case stylePreferences
    case sizesAndFit
    case workAndUniform
    case ppeSafety
    case shoppingPreferences
    case corrections
    case referencedOutfits

    var displayName: String {
        switch self {
        case .stylePreferences: "Style Preferences"
        case .sizesAndFit: "Sizes & Fit"
        case .workAndUniform: "Work & Uniform"
        case .ppeSafety: "PPE / Safety"
        case .shoppingPreferences: "Shopping Preferences"
        case .corrections: "Corrections"
        case .referencedOutfits: "Referenced Outfits"
        }
    }
}

/// Typed values prevent this store from becoming an unrestricted JSON bucket.
/// Values are bounded at construction and exclude images, OCR, calendar events,
/// credentials, identifiers, and chat transcripts by design.
enum AIPersistentMemoryValue: Codable, Equatable, Sendable {
    case preference(String)
    case sizeOrFit(String)
    case workConstraint(String)
    case safetyConstraint(String)
    case shoppingPreference(String)
    case correction(String)
    case authoritativeReference(StyleMemoryReference)

    private enum Kind: String, Codable { case preference, sizeOrFit, workConstraint, safetyConstraint, shoppingPreference, correction, authoritativeReference }
    private enum CodingKeys: String, CodingKey { case kind, text, reference }

    init?(category: AIPersistentMemoryCategory, text: String) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= 280 else { return nil }
        switch category {
        case .stylePreferences: self = .preference(normalized)
        case .sizesAndFit: self = .sizeOrFit(normalized)
        case .workAndUniform: self = .workConstraint(normalized)
        case .ppeSafety: self = .safetyConstraint(normalized)
        case .shoppingPreferences: self = .shoppingPreference(normalized)
        case .corrections: self = .correction(normalized)
        case .referencedOutfits: return nil
        }
    }

    var displayValue: String {
        switch self {
        case .preference(let text), .sizeOrFit(let text), .workConstraint(let text), .safetyConstraint(let text), .shoppingPreference(let text), .correction(let text): text
        case .authoritativeReference: "Saved outfit reference"
        }
    }

    var canonicalKey: String {
        switch self {
        case .authoritativeReference(let reference): return "reference:\(reference.domain.rawValue):\(reference.stableID)"
        default: return displayValue.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .preference: self = .preference(try container.decode(String.self, forKey: .text))
        case .sizeOrFit: self = .sizeOrFit(try container.decode(String.self, forKey: .text))
        case .workConstraint: self = .workConstraint(try container.decode(String.self, forKey: .text))
        case .safetyConstraint: self = .safetyConstraint(try container.decode(String.self, forKey: .text))
        case .shoppingPreference: self = .shoppingPreference(try container.decode(String.self, forKey: .text))
        case .correction: self = .correction(try container.decode(String.self, forKey: .text))
        case .authoritativeReference: self = .authoritativeReference(try container.decode(StyleMemoryReference.self, forKey: .reference))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .preference(let text): try container.encode(Kind.preference, forKey: .kind); try container.encode(text, forKey: .text)
        case .sizeOrFit(let text): try container.encode(Kind.sizeOrFit, forKey: .kind); try container.encode(text, forKey: .text)
        case .workConstraint(let text): try container.encode(Kind.workConstraint, forKey: .kind); try container.encode(text, forKey: .text)
        case .safetyConstraint(let text): try container.encode(Kind.safetyConstraint, forKey: .kind); try container.encode(text, forKey: .text)
        case .shoppingPreference(let text): try container.encode(Kind.shoppingPreference, forKey: .kind); try container.encode(text, forKey: .text)
        case .correction(let text): try container.encode(Kind.correction, forKey: .kind); try container.encode(text, forKey: .text)
        case .authoritativeReference(let reference): try container.encode(Kind.authoritativeReference, forKey: .kind); try container.encode(reference, forKey: .reference)
        }
    }
}

enum AIPersistentMemoryConfirmationState: String, Codable, Equatable, Sendable { case confirmed, proposed }
enum AIPersistentMemoryInvalidationState: String, Codable, Equatable, Sendable { case active, invalidated, superseded, expired }
enum AIPersistentMemorySource: String, Codable, Equatable, Sendable {
    case explicitUserRequest
    case userConfirmedSuggestion
    case userCorrection
    case confirmedProfile
    case authoritativeReference

    var explanation: String {
        switch self {
        case .explicitUserRequest: "You asked KigoStylist to remember this."
        case .userConfirmedSuggestion: "This preference was suggested and you confirmed it."
        case .userCorrection: "You corrected this preference."
        case .confirmedProfile: "This comes from your confirmed profile."
        case .authoritativeReference: "This references an outfit you saved."
        }
    }
}

struct AIPersistentMemory: Codable, Equatable, Identifiable, Sendable {
    static let currentSchemaVersion = 1
    let id: UUID
    let schemaVersion: Int
    let accountID: String
    let identityScope: StyleMemoryIdentityScope
    let category: AIPersistentMemoryCategory
    let value: AIPersistentMemoryValue
    let source: AIPersistentMemorySource
    let confidence: StyleMemoryConfidence
    let confirmationState: AIPersistentMemoryConfirmationState
    let createdAt: Date
    var updatedAt: Date
    let expiresAt: Date?
    let authoritativeReference: StyleMemoryReference?
    var supersedesMemoryID: UUID?
    var invalidationState: AIPersistentMemoryInvalidationState

    var isActive: Bool {
        invalidationState == .active && confirmationState == .confirmed && (expiresAt.map { $0 > Date() } ?? true)
    }

    var explainWhy: String { source.explanation }

    var explainHowItHelps: String {
        switch category {
        case .stylePreferences, .sizesAndFit, .shoppingPreferences, .corrections:
            return "KigoStylist may use this preference when it is relevant to your styling advice."
        case .workAndUniform:
            return "KigoStylist may use this when it is relevant to work outfit guidance."
        case .ppeSafety:
            return "KigoStylist may use this when it is relevant to safety-aware outfit guidance. Employer and safety requirements still come first."
        case .referencedOutfits:
            return "KigoStylist may use this saved outfit reference when you ask about that outfit."
        }
    }
}

private struct AIPersistentMemoryDocument: Codable {
    let schemaVersion: Int
    let records: [AIPersistentMemory]
}

/// Explicit local-save outcome so UI can distinguish a full memory collection
/// from invalid input or a failed local write. This is intentionally internal:
/// it is not a serialized or network compatibility contract.
enum AIPersistentMemorySaveResult: Equatable {
    case saved(AIPersistentMemory)
    case capacityReached
    case failed
}

/// Internal product policy for local, confirmed AI Memory storage. This does
/// not change the bounded context sent with any one AI request.
enum AIMemoryPolicy {
    static let maximumActiveMemories = 1_000
}

/// Local, snapshot-backed store for only explicitly remembered facts. No view,
/// scan, product, chat, Calendar, or Weather observation calls this store's
/// mutation APIs automatically.
final class AIPersistentMemoryStore: ObservableObject {
    static let storeName = "AIPersistentMemoryStore"

    @Published private(set) var memories: [AIPersistentMemory]
    private let defaults: UserDefaults
    private let userID: String
    private let identityScope: StyleMemoryIdentityScope
    private let snapshotRoot: URL?
    private let now: () -> Date
    private let lock = NSRecursiveLock()

    init(defaults: UserDefaults = .standard, userID: String? = nil, snapshotRoot: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.userID = PersonalStylistStorage.normalizedUserID(userID ?? PersonalStylistStorage.activeUserID(defaults: defaults))
        self.identityScope = StyleMemoryIdentityScope.resolve(defaults: defaults)
        self.snapshotRoot = snapshotRoot
        self.now = now
        memories = Self.load(userID: self.userID, root: snapshotRoot)
        cleanupExpiredAndInvalidated()
    }

    @discardableResult
    func remember(category: AIPersistentMemoryCategory, text: String, source: AIPersistentMemorySource = .explicitUserRequest, reference: StyleMemoryReference? = nil, expiresAt: Date? = nil) -> AIPersistentMemory? {
        guard case let .saved(memory) = rememberResult(category: category, text: text, source: source, reference: reference, expiresAt: expiresAt) else { return nil }
        return memory
    }

    @discardableResult
    func rememberResult(category: AIPersistentMemoryCategory, text: String, source: AIPersistentMemorySource = .explicitUserRequest, reference: StyleMemoryReference? = nil, expiresAt: Date? = nil) -> AIPersistentMemorySaveResult {
        guard category != .referencedOutfits, let value = AIPersistentMemoryValue(category: category, text: text) else { return .failed }
        return persist(category: category, value: value, source: source, confirmation: .confirmed, reference: reference, expiresAt: expiresAt)
    }

    @discardableResult
    func remember(reference: StyleMemoryReference) -> AIPersistentMemory? {
        guard case let .saved(memory) = persist(category: .referencedOutfits, value: .authoritativeReference(reference), source: .authoritativeReference, confirmation: .confirmed, reference: reference, expiresAt: nil) else { return nil }
        return memory
    }

    /// A proposed fact is intentionally non-persistent; only `confirm` writes.
    func proposal(category: AIPersistentMemoryCategory, text: String, expiresAt: Date) -> AIPersistentMemory? {
        guard let value = AIPersistentMemoryValue(category: category, text: text), expiresAt > now() else { return nil }
        return AIPersistentMemory(id: UUID(), schemaVersion: AIPersistentMemory.currentSchemaVersion, accountID: userID, identityScope: identityScope, category: category, value: value, source: .userConfirmedSuggestion, confidence: .inferred, confirmationState: .proposed, createdAt: now(), updatedAt: now(), expiresAt: expiresAt, authoritativeReference: nil, supersedesMemoryID: nil, invalidationState: .active)
    }

    @discardableResult
    func confirm(_ proposal: AIPersistentMemory) -> AIPersistentMemory? {
        guard proposal.confirmationState == .proposed, proposal.expiresAt.map({ $0 > now() }) ?? false else { return nil }
        guard case let .saved(memory) = persist(category: proposal.category, value: proposal.value, source: .userConfirmedSuggestion, confirmation: .confirmed, reference: proposal.authoritativeReference, expiresAt: proposal.expiresAt) else { return nil }
        return memory
    }

    @discardableResult
    func edit(_ memory: AIPersistentMemory, text: String) -> AIPersistentMemory? {
        guard case let .saved(replacement) = editResult(memory, text: text) else { return nil }
        return replacement
    }

    @discardableResult
    func editResult(_ memory: AIPersistentMemory, text: String) -> AIPersistentMemorySaveResult {
        guard let replacement = AIPersistentMemoryValue(category: memory.category, text: text) else { return .failed }
        return persist(category: memory.category, value: replacement, source: .userCorrection, confirmation: .confirmed, reference: memory.authoritativeReference, expiresAt: memory.expiresAt, superseding: memory.id)
    }

    /// User-directed forget removes the requested memory's correction lineage
    /// from the main snapshot and every recovery copy. It never falls back to
    /// an inactive marker that could be revived from an older backup.
    @discardableResult
    func forget(_ id: UUID) -> Bool {
        remove(where: correctionLineage(containing: id))
    }

    @discardableResult
    func forget(category: AIPersistentMemoryCategory) -> Bool {
        remove(where: { $0.category == category })
    }

    /// Clear All affects only this local AI Memory store. Profile, saved scans,
    /// Closet, Shopping, favorites, and account data remain in their existing
    /// authoritative stores.
    @discardableResult
    func clearAll() -> Bool {
        remove(where: { _ in true })
    }

    @discardableResult
    func invalidate(reference: StyleMemoryReference) -> Bool {
        remove(where: { $0.authoritativeReference == reference })
    }

    func activeMemories(relevantTo prompt: String? = nil) -> [AIPersistentMemory] {
        cleanupExpiredAndInvalidated()
        let terms = Set((prompt ?? "").lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 3 })
        let active = memories.filter(\.isActive)
        guard !terms.isEmpty else { return active.sorted { $0.updatedAt > $1.updatedAt } }
        return active.sorted { lhs, rhs in
            let l = terms.filter { lhs.value.displayValue.lowercased().contains($0) }.count
            let r = terms.filter { rhs.value.displayValue.lowercased().contains($0) }.count
            return l == r ? lhs.updatedAt > rhs.updatedAt : l > r
        }
    }

    func exportRecords() -> [AIPersistentMemory] { activeMemories() }

    /// Only already-confirmed, active local memories can cross the persistence
    /// boundary. This has no relationship to AI transmission consent or chat.
    func syncSafeRecords() throws -> [PersistenceAuthorityRecord] {
        try exportRecords().map { memory in
            PersistenceAuthorityRecord(id: memory.id.uuidString, kind: .aiMemory, payload: try JSONEncoder().encode(memory), version: "\(memory.updatedAt.timeIntervalSince1970)", updatedAt: memory.updatedAt, isDeleted: false, persistenceOrigin: .explicitlySavedAIMemory)
        }
    }

    func applySyncSafeRecord(_ record: PersistenceAuthorityRecord) throws {
        guard record.kind == .aiMemory, record.persistenceOrigin == .explicitlySavedAIMemory, !record.isDeleted else { throw PersistenceAuthorityError.invalidRecord }
        let remote = try JSONDecoder().decode(AIPersistentMemory.self, from: record.payload)
        guard remote.id.uuidString == record.id, remote.confirmationState == .confirmed, remote.invalidationState == .active else { throw PersistenceAuthorityError.invalidRecord }
        lock.lock(); defer { lock.unlock() }
        if let local = memories.first(where: { $0.id == remote.id }) {
            guard local.updatedAt <= remote.updatedAt else { throw PersistenceAuthorityError.stale }
            if local.updatedAt == remote.updatedAt { return }
            throw PersistenceAuthorityError.conflict
        }
        memories.append(remote)
        guard save() else { memories.removeAll { $0.id == remote.id }; throw PersistenceAuthorityError.invalidRecord }
    }

    /// V2 reconciliation enters through this narrow, explicit-memory-only
    /// boundary. It never accepts proposal, inferred, expired, or hidden
    /// memory as a sync payload.
    func applyV2Live(_ memory: AIPersistentMemory) throws {
        guard memory.schemaVersion == AIPersistentMemory.currentSchemaVersion,
              memory.confirmationState == .confirmed,
              memory.invalidationState == .active else { throw PersistenceAuthorityError.invalidRecord }
        lock.lock(); defer { lock.unlock() }
        if let index = memories.firstIndex(where: { $0.id == memory.id }) {
            memories[index] = memory
        } else {
            memories.append(memory)
        }
        guard save() else { throw PersistenceAuthorityError.invalidRecord }
    }

    func applyV2Tombstone(id: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        memories.removeAll { $0.id == id }
        guard save(replacingRecoverySnapshots: true) else { throw PersistenceAuthorityError.invalidRecord }
    }

    static func deleteAll(for userID: String, root: URL? = nil) {
        PersonalStylistSnapshotStore.deleteData(store: storeName, userID: userID, rootDirectory: root)
    }

    private func persist(category: AIPersistentMemoryCategory, value: AIPersistentMemoryValue, source: AIPersistentMemorySource, confirmation: AIPersistentMemoryConfirmationState, reference: StyleMemoryReference?, expiresAt: Date?, superseding: UUID? = nil) -> AIPersistentMemorySaveResult {
        lock.lock(); defer { lock.unlock() }
        cleanupExpiredAndInvalidated()
        if let superseding {
            guard memories.contains(where: { $0.id == superseding && $0.isActive }) else { return .failed }
        } else if memories.filter(\.isActive).count >= AIMemoryPolicy.maximumActiveMemories {
            return .capacityReached
        }

        let originalMemories = memories
        let date = now()
        let replacement = AIPersistentMemory(id: UUID(), schemaVersion: AIPersistentMemory.currentSchemaVersion, accountID: userID, identityScope: identityScope, category: category, value: value, source: source, confidence: .confirmed, confirmationState: confirmation, createdAt: date, updatedAt: date, expiresAt: expiresAt, authoritativeReference: reference, supersedesMemoryID: superseding, invalidationState: .active)
        let canonical = value.canonicalKey
        for index in memories.indices where memories[index].isActive && memories[index].category == category && (memories[index].value.canonicalKey == canonical || memories[index].id == superseding) {
            memories[index].invalidationState = .superseded
            memories[index].updatedAt = date
        }
        memories.append(replacement)
        guard save() else {
            memories = originalMemories
            return .failed
        }
        return .saved(replacement)
    }

    private func correctionLineage(containing id: UUID) -> (AIPersistentMemory) -> Bool {
        var relatedIDs: Set<UUID> = [id]
        var changed = true
        while changed {
            changed = false
            for memory in memories where relatedIDs.contains(memory.id)
                || memory.supersedesMemoryID.map(relatedIDs.contains) == true
                || memories.contains(where: { relatedIDs.contains($0.id) && $0.supersedesMemoryID == memory.id }) {
                changed = relatedIDs.insert(memory.id).inserted || changed
            }
        }
        return { relatedIDs.contains($0.id) }
    }

    /// This path is intentionally physical rather than an invalidation flag.
    /// A user who forgets a fact must not have it retained in recovery files.
    private func remove(where predicate: (AIPersistentMemory) -> Bool) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let originalMemories = memories
        memories.removeAll(where: predicate)
        guard save(replacingRecoverySnapshots: true) else {
            memories = originalMemories
            return false
        }
        return true
    }

    private func cleanupExpiredAndInvalidated() {
        lock.lock(); defer { lock.unlock() }
        let date = now()
        var changed = false
        for index in memories.indices where memories[index].invalidationState == .active && (memories[index].expiresAt.map { $0 <= date } ?? false) {
            memories[index].invalidationState = .expired
            memories[index].updatedAt = date
            changed = true
        }
        if changed {
            _ = save()
        }
    }

    @discardableResult
    private func save(replacingRecoverySnapshots: Bool = false) -> Bool {
        let document = AIPersistentMemoryDocument(schemaVersion: AIPersistentMemory.currentSchemaVersion, records: memories)
        guard let data = try? JSONEncoder().encode(document) else { return false }
        if replacingRecoverySnapshots,
           case .success = PersonalStylistSnapshotStore.replaceDataAndRecoverySnapshots(
            data,
            store: Self.storeName,
            userID: userID,
            rootDirectory: snapshotRoot
           ) {
            return true
        }
        if case .success = PersonalStylistSnapshotStore.saveData(data, store: Self.storeName, userID: userID, rootDirectory: snapshotRoot) {
            return true
        }
        return false
    }

    private static func load(userID: String, root: URL?) -> [AIPersistentMemory] {
        func decode(_ data: Data) -> [AIPersistentMemory]? { try? JSONDecoder().decode(AIPersistentMemoryDocument.self, from: data).records }
        // A corrupt current document fails closed rather than restoring an
        // older snapshot that could resurrect an explicitly forgotten fact.
        // Atomic writes already protect normal interrupted-write recovery.
        if let data = PersonalStylistSnapshotStore.loadData(store: storeName, userID: userID, rootDirectory: root), let decoded = decode(data) { return decoded.filter { $0.schemaVersion <= AIPersistentMemory.currentSchemaVersion && $0.accountID == PersonalStylistStorage.normalizedUserID(userID) } }
        return []
    }
}

/// Phase 2 screen context is request-scoped and never persisted. This narrow
/// marker lets management UI acknowledge a clear action without retaining any
/// screen, conversation, or record data.
enum AIMemoryTemporaryContext {
    static func clear() {}
}

// MARK: - Read-only AI memory resolution

/// Categories are intentionally coarse. They let callers account for a
/// bounded payload without copying a Profile, calendar event, OCR result,
/// image, chat history, secret, token, or device identifier into a request.
enum AIMemoryFactCategory: String, Codable, CaseIterable, Equatable, Sendable {
    case userMessage
    case screen
    case authoritativeReference
    case scanSummary
    case occasion
    case calendar
    case weather
    case profile
    case workplace
    case wardrobe
    case shopping
    case persistentMemory
}

struct AIMemoryResolvedFact: Codable, Equatable, Sendable {
    let category: AIMemoryFactCategory
    let value: String
    let provenance: StyleMemoryProvenance
    let confidence: StyleMemoryConfidence
    let expiresAt: Date?

    init?(
        category: AIMemoryFactCategory,
        value: String?,
        provenance: StyleMemoryProvenance,
        confidence: StyleMemoryConfidence,
        expiresAt: Date? = nil
    ) {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !normalized.isEmpty else { return nil }
        self.category = category
        self.value = String(normalized.prefix(400))
        self.provenance = provenance
        self.confidence = confidence
        self.expiresAt = expiresAt
    }
}

struct AIMemoryResolverBudget: Equatable {
    /// Small request bounds make the resolver safe for chat and voice while
    /// keeping the currently visible authority ahead of lower-priority facts.
    let maximumFactCount: Int
    let maximumSerializedCharacters: Int

    static let chatAndVoice = Self(maximumFactCount: 8, maximumSerializedCharacters: 1_600)

    init(maximumFactCount: Int, maximumSerializedCharacters: Int) {
        self.maximumFactCount = max(1, maximumFactCount)
        self.maximumSerializedCharacters = max(256, maximumSerializedCharacters)
    }
}

struct AIMemoryResolutionInput: Equatable {
    let userMessage: String
    let screenContext: StylistScreenContext?
    let expectedContextGeneration: UInt64?
    let conversationScope: StyleMemoryScope
    let styleMemoryInput: StyleMemoryContextInput
    let availableReferences: Set<StyleMemoryReference>

    init(
        userMessage: String,
        screenContext: StylistScreenContext? = nil,
        expectedContextGeneration: UInt64? = nil,
        conversationScope: StyleMemoryScope,
        styleMemoryInput: StyleMemoryContextInput,
        availableReferences: Set<StyleMemoryReference> = []
    ) {
        self.userMessage = String(userMessage.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1_000))
        self.screenContext = screenContext
        self.expectedContextGeneration = expectedContextGeneration
        self.conversationScope = conversationScope
        self.styleMemoryInput = styleMemoryInput
        self.availableReferences = availableReferences
    }
}

struct AIMemoryResolution: Codable, Equatable {
    let facts: [AIMemoryResolvedFact]
    let omittedCategories: [AIMemoryFactCategory]
    let authoritativeReference: StyleMemoryReference?
    let contextGeneration: UInt64?
    let rejectedStaleContext: Bool
    let unavailableReference: Bool
    let serializedCharacterCount: Int

    var hasRecordAuthority: Bool { authoritativeReference != nil }
}

/// Dependency-injected, read-only resolver. Durable authorities remain
/// ProfileStore, OutfitMemoryStore, saved Scan history, closet, Shopping, and
/// the sanitized Calendar/Weather projections. This type does not write any
/// store and does not become a global screen-context or memory database.
struct AIMemoryManager {
    let budget: AIMemoryResolverBudget
    let now: () -> Date

    init(
        budget: AIMemoryResolverBudget = .chatAndVoice,
        now: @escaping () -> Date = Date.init
    ) {
        self.budget = budget
        self.now = now
    }

    func resolve(_ input: AIMemoryResolutionInput) -> AIMemoryResolution {
        let staleContext = input.expectedContextGeneration.map {
            input.screenContext?.surface?.contextGeneration != $0
        } ?? false
        let screen = staleContext ? nil : input.screenContext
        let resolved = StyleMemoryAuthorityResolver.resolve(input.styleMemoryInput, now: now())

        // General Stylist is never granted an authority merely because a
        // screen happened to be visible. A context-aware route must provide a
        // non-general scope and a matching, currently available reference.
        let authority = input.conversationScope.kind == .generalStylist ? nil : resolved.authority.selectedReference
        // The injected source snapshot is authoritative. Absence is
        // fail-closed: a deleted or unavailable record must never be replaced
        // by a nearby record or guessed from stale screen state.
        let unavailableReference = authority.map { !input.availableReferences.contains($0) } ?? false
        let usableAuthority = unavailableReference ? nil : authority

        var candidates: [AIMemoryResolvedFact] = []
        append(&candidates, category: .userMessage, value: input.userMessage, provenance: .explicitCorrection, confidence: .confirmed)
        if let surface = screen?.surface {
            append(&candidates, category: .screen, value: screenValue(surface), provenance: .explicitSelection, confidence: .confirmed)
        }
        if let reference = usableAuthority {
            append(&candidates, category: .authoritativeReference, value: referenceValue(reference), provenance: resolved.authority.provenance, confidence: .confirmed)
        }
        if usableAuthority != nil,
           let summary = resolved.selectedScanSummary.value,
           summary.reference == usableAuthority {
            append(&candidates, category: .scanSummary, value: summary.summary, provenance: resolved.selectedScanSummary.provenance, confidence: resolved.selectedScanSummary.confidence)
        }
        appendFact(&candidates, category: .occasion, fact: resolved.occasion)
        appendFact(&candidates, category: .weather, fact: resolved.weather)
        appendFact(&candidates, category: .profile, fact: resolved.profile)
        appendFact(&candidates, category: .workplace, fact: resolved.workplace)
        if let wardrobe = resolved.wardrobe.value {
            append(&candidates, category: .wardrobe, value: wardrobe.map(referenceValue).joined(separator: ","), provenance: resolved.wardrobe.provenance, confidence: resolved.wardrobe.confidence)
        }
        if let shopping = resolved.shopping.value {
            append(&candidates, category: .shopping, value: referenceValue(shopping), provenance: resolved.shopping.provenance, confidence: resolved.shopping.confidence)
        }

        let accepted = bounded(candidates)
        let omitted = AIMemoryFactCategory.allCases.filter { category in
            candidates.contains(where: { $0.category == category }) && !accepted.facts.contains(where: { $0.category == category })
        }
        return AIMemoryResolution(
            facts: accepted.facts,
            omittedCategories: omitted,
            authoritativeReference: usableAuthority,
            contextGeneration: screen?.surface?.contextGeneration,
            rejectedStaleContext: staleContext,
            unavailableReference: unavailableReference,
            serializedCharacterCount: accepted.characterCount
        )
    }

    /// Persistent facts are appended only after current request, route, and
    /// authoritative record facts. They are bounded by the same central budget
    /// and are never a substitute for current-screen authority.
    func mergingPersistentMemories(_ resolution: AIMemoryResolution, memories: [AIPersistentMemory]) -> AIMemoryResolution {
        var candidates = resolution.facts
        for memory in memories where memory.isActive {
            append(
                &candidates,
                category: .persistentMemory,
                value: memory.value.displayValue,
                provenance: memory.source == .userCorrection ? .explicitCorrection : .explicitSelection,
                confidence: memory.confidence,
                expiresAt: memory.expiresAt
            )
        }
        let accepted = bounded(candidates)
        let omitted = AIMemoryFactCategory.allCases.filter { category in
            candidates.contains(where: { $0.category == category }) && !accepted.facts.contains(where: { $0.category == category })
        }
        return AIMemoryResolution(
            facts: accepted.facts,
            omittedCategories: omitted,
            authoritativeReference: resolution.authoritativeReference,
            contextGeneration: resolution.contextGeneration,
            rejectedStaleContext: resolution.rejectedStaleContext,
            unavailableReference: resolution.unavailableReference,
            serializedCharacterCount: accepted.characterCount
        )
    }

    private func bounded(_ candidates: [AIMemoryResolvedFact]) -> (facts: [AIMemoryResolvedFact], characterCount: Int) {
        var facts: [AIMemoryResolvedFact] = []
        var count = 0
        for fact in candidates where facts.count < budget.maximumFactCount {
            let nextCount = count + fact.category.rawValue.count + fact.value.count
            guard nextCount <= budget.maximumSerializedCharacters else { continue }
            facts.append(fact)
            count = nextCount
        }
        return (facts, count)
    }

    private func append(
        _ facts: inout [AIMemoryResolvedFact],
        category: AIMemoryFactCategory,
        value: String?,
        provenance: StyleMemoryProvenance,
        confidence: StyleMemoryConfidence,
        expiresAt: Date? = nil
    ) {
        if let fact = AIMemoryResolvedFact(category: category, value: value, provenance: provenance, confidence: confidence, expiresAt: expiresAt) {
            facts.append(fact)
        }
    }

    private func appendFact(
        _ facts: inout [AIMemoryResolvedFact],
        category: AIMemoryFactCategory,
        fact: StyleMemoryFact<String>
    ) {
        append(&facts, category: category, value: fact.value, provenance: fact.provenance, confidence: fact.confidence, expiresAt: fact.expiresAt)
    }

    private func screenValue(_ surface: StylistScreenSurfaceDescriptor) -> String {
        [surface.screenKind.rawValue, surface.resultState?.rawValue, surface.visibleSheetKind, surface.selectedActionID]
            .compactMap { $0 }
            .joined(separator: ":")
    }

    private func referenceValue(_ reference: StyleMemoryReference) -> String {
        "\(reference.domain.rawValue):\(reference.stableID)"
    }
}

enum StyleMemoryWorkerProjectionClassification: String, Codable, Equatable, Sendable {
    case projectable
    case notProjectable
}

/// Produces the *ephemeral* memory addition to the existing chat contract.
/// It reads the established profile and outfit-memory stores but never writes
/// them, and deliberately does not add a second serialized memory store.
enum StyleMemoryContextBuilder {
    private static let consentKey = "shareAppContextWithChatGPT"

    static func applying(
        to proposedContext: ChatContext,
        conversationScope: StylistConversationScope,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) -> ChatContext {
        var context = proposedContext

        // General Stylist is an authority boundary even when a caller hands us
        // a stale Scan-shaped context.
        guard conversationScope.isScanBound else {
            context.activeScan = ""
            context.scoreBreakdown = nil
            context.authoritativeScan = nil
            return applyingConsentedGeneralMemory(to: context, defaults: defaults, now: now)
        }

        guard explicitlyConsented(defaults: defaults),
              let scanID = conversationScope.scanID,
              let authoritativeScan = context.authoritativeScan,
              authoritativeScan.isComplete,
              authoritativeScan.scanID == scanID,
              let scope = memoryScope(for: conversationScope) else {
            return context
        }

        let referenceDomain: StyleMemoryReferenceDomain = scope.kind == .savedScan ? .savedScan : .activeScan
        guard let reference = StyleMemoryReference(domain: referenceDomain, stableID: scanID) else {
            return context
        }

        let resolved = StyleMemoryAuthorityResolver.resolve(
            memoryInput(
                scope: scope,
                selectedReference: reference,
                selectedScanSummary: context.activeScan,
                defaults: defaults
            ),
            now: now
        )
        let projection = StyleMemoryWorkerProjection.project(context: resolved, now: now)
        guard projection.classification == .projectable,
              projection.selectedScanID == scanID else {
            return context
        }
        return applying(projection: projection, to: context, includesSelectedScan: true)
    }

    private static func applyingConsentedGeneralMemory(
        to context: ChatContext,
        defaults: UserDefaults,
        now: Date
    ) -> ChatContext {
        guard explicitlyConsented(defaults: defaults) else { return context }
        let resolved = StyleMemoryAuthorityResolver.resolve(
            memoryInput(
                scope: .generalStylist,
                selectedReference: nil,
                selectedScanSummary: "",
                defaults: defaults
            ),
            now: now
        )
        let projection = StyleMemoryWorkerProjection.project(context: resolved, now: now)
        guard projection.classification == .projectable else { return context }
        return applying(projection: projection, to: context, includesSelectedScan: false)
    }

    private static func explicitlyConsented(defaults: UserDefaults) -> Bool {
        // An absent historical default is not consent. The established Profile
        // control must have persisted an explicit true value.
        defaults.object(forKey: consentKey) as? Bool == true
    }

    private static func memoryScope(for conversationScope: StylistConversationScope) -> StyleMemoryScope? {
        switch conversationScope {
        case .generalStylist, .contextualStylist:
            return .generalStylist
        case let .activeScan(scanID):
            return StyleMemoryScope(kind: .activeScan, stableID: scanID)
        case let .savedScan(scanID):
            return StyleMemoryScope(kind: .savedScan, stableID: scanID)
        }
    }

    private static func memoryInput(
        scope: StyleMemoryScope,
        selectedReference: StyleMemoryReference?,
        selectedScanSummary: String,
        defaults: UserDefaults
    ) -> StyleMemoryContextInput {
        let profile = ProfileStore(defaults: defaults).currentProfile
        let memories = OutfitMemoryStore(defaults: defaults).memories
        let profileSummary = PersonalizationContextBuilder.buildContext(
            profile: profile,
            recentMemories: memories,
            maxMemories: 4
        )
        let workplace = [profile.workSetting, profile.workDressCode]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "; ")
        let identity = StyleMemoryIdentityScope.resolve(defaults: defaults)
        let calendarFact = CalendarContextProvider.occasionFact(
            access: EventKitCalendarContextAccess(),
            defaults: defaults
        )
        let referenceFact = StyleMemoryFact(
            value: selectedReference,
            provenance: .explicitSelection,
            confidence: selectedReference == nil ? .unavailable : .confirmed,
            identityScope: identity
        )
        let summaryFact = StyleMemoryFact(
            value: selectedReference.flatMap { reference in
                let summary = selectedScanSummary.trimmingCharacters(in: .whitespacesAndNewlines)
                return summary.isEmpty ? nil : StyleMemoryScanSummary(reference: reference, summary: summary)
            },
            provenance: .explicitSelection,
            confidence: selectedReference == nil ? .unavailable : .confirmed,
            identityScope: identity
        )
        return StyleMemoryContextInput(
            identityScope: identity,
            scope: scope,
            explicitSelection: referenceFact,
            selectedScanSummary: summaryFact,
            calendarOccasion: calendarFact,
            profileSummary: StyleMemoryFact(
                value: profileSummary.isEmpty ? nil : profileSummary,
                provenance: .profile,
                confidence: profileSummary.isEmpty ? .unavailable : .confirmed,
                identityScope: identity
            ),
            workplaceSummary: StyleMemoryFact(
                value: workplace.isEmpty ? nil : workplace,
                provenance: .profile,
                confidence: workplace.isEmpty ? .unavailable : .confirmed,
                identityScope: identity
            )
        )
    }

    private static func applying(
        projection: StyleMemoryWorkerProjection,
        to proposedContext: ChatContext,
        includesSelectedScan: Bool
    ) -> ChatContext {
        var context = proposedContext
        context.profileSummary = appended(
            base: context.profileSummary,
            label: "Confirmed workplace constraints",
            value: projection.workplaceSummary,
            limit: 600
        )
        context.profileSummary = appended(
            base: context.profileSummary,
            label: "Confirmed personal preferences",
            value: projection.profileSummary,
            limit: 600
        )
        if includesSelectedScan {
            context.activeScan = appended(
                base: context.activeScan,
                label: "Selected scan facts",
                value: projection.selectedScanSummary,
                limit: 800
            )
        }
        return context
    }

    private static func appended(base: String, label: String, value: String?, limit: Int) -> String {
        guard let value, !value.isEmpty else {
            return bounded(base, limit: limit)
        }
        let addition = "\(label): \(value)"
        if base.contains(addition) { return bounded(base, limit: limit) }
        let joined = base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? addition
            : "\(base)\n\(addition)"
        guard joined.utf16.count > limit else { return joined }
        // Confirmed workplace/PPE and selected-Scan facts are more important
        // than boilerplate already occupying the legacy string contract.
        guard addition.utf16.count < limit else { return bounded(addition, limit: limit) }
        let baseBudget = max(0, limit - addition.utf16.count - 1)
        let retainedBase = bounded(base, limit: baseBudget)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return retainedBase.isEmpty ? addition : "\(retainedBase)\n\(addition)"
    }

    private static func bounded(_ value: String, limit: Int) -> String {
        guard value.utf16.count > limit else { return value }
        var result = ""
        var count = 0
        for character in value {
            let width = String(character).utf16.count
            guard count + width <= limit else { break }
            result.append(character)
            count += width
        }
        return result
    }
}

enum StyleMemoryWorkerField: CaseIterable, Sendable {
    case profileSummary
    case occasion
    case weatherSummary
    case workplaceSummary
    case selectedScanSummary

    var maximumUTF16Count: Int {
        switch self {
        case .profileSummary: 280
        case .occasion: 160
        case .weatherSummary: 160
        case .workplaceSummary: 160
        case .selectedScanSummary: 320
        }
    }

    var allowedProvenance: Set<StyleMemoryProvenance> {
        switch self {
        case .profileSummary: [.profile]
        case .occasion: [.manualOccasion, .authorizedCalendarEvent]
        case .weatherSummary: [.freshWeather]
        case .workplaceSummary: [.profile]
        case .selectedScanSummary: [.explicitSelection, .openedSavedScan, .completedActiveScan]
        }
    }

    var requiresAuthorization: Bool {
        self == .occasion
    }

    var redactsToSingleLine: Bool { true }
}

struct StyleMemoryWorkerProjection: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let classification: StyleMemoryWorkerProjectionClassification
    let authorityScope: StyleMemoryScopeKind?
    let authorityID: String?
    let selectedScanID: String?
    let selectedScanSummary: String?
    let occasion: String?
    let weather: String?
    let profileSummary: String?
    let workplaceSummary: String?
    let wardrobeItemIDs: [String]
    let shoppingItemID: String?

    private init(
        schemaVersion: Int,
        classification: StyleMemoryWorkerProjectionClassification,
        authorityScope: StyleMemoryScopeKind?,
        authorityID: String?,
        selectedScanID: String?,
        selectedScanSummary: String?,
        occasion: String?,
        weather: String?,
        profileSummary: String?,
        workplaceSummary: String?,
        wardrobeItemIDs: [String],
        shoppingItemID: String?
    ) {
        self.schemaVersion = schemaVersion
        self.classification = classification
        self.authorityScope = authorityScope
        self.authorityID = authorityID
        self.selectedScanID = selectedScanID
        self.selectedScanSummary = selectedScanSummary
        self.occasion = occasion
        self.weather = weather
        self.profileSummary = profileSummary
        self.workplaceSummary = workplaceSummary
        self.wardrobeItemIDs = wardrobeItemIDs
        self.shoppingItemID = shoppingItemID
    }

    static func project(context: StyleMemoryContext, now: Date = Date(), sessionID: String? = nil) -> Self {
        guard context.isWorkerProjectable else {
            return Self.notProjectable(schemaVersion: context.schemaVersion)
        }
        return Self(
            schemaVersion: context.schemaVersion,
            classification: .projectable,
            authorityScope: context.authority.scope.kind,
            authorityID: context.authority.selectedReference?.stableID,
            selectedScanID: context.selectedScan.value?.stableID,
            selectedScanSummary: string(context.selectedScanSummary, field: .selectedScanSummary, now: now, sessionID: sessionID),
            occasion: string(context.occasion, field: .occasion, now: now, sessionID: sessionID),
            weather: string(context.weather, field: .weatherSummary, now: now, sessionID: sessionID),
            profileSummary: string(context.profile, field: .profileSummary, now: now, sessionID: sessionID),
            workplaceSummary: string(context.workplace, field: .workplaceSummary, now: now, sessionID: sessionID),
            wardrobeItemIDs: context.wardrobe.value?.map(\.stableID) ?? [],
            shoppingItemID: context.shopping.value?.stableID
        )
    }

    private static func notProjectable(schemaVersion: Int) -> Self {
        Self(
            schemaVersion: schemaVersion,
            classification: .notProjectable,
            authorityScope: nil,
            authorityID: nil,
            selectedScanID: nil,
            selectedScanSummary: nil,
            occasion: nil,
            weather: nil,
            profileSummary: nil,
            workplaceSummary: nil,
            wardrobeItemIDs: [],
            shoppingItemID: nil
        )
    }

    private static func string(
        _ fact: StyleMemoryFact<String>,
        field: StyleMemoryWorkerField,
        now: Date,
        sessionID: String?
    ) -> String? {
        guard field.allowedProvenance.contains(fact.provenance),
              fact.isFresh(at: now, sessionID: sessionID),
              (!field.requiresAuthorization || fact.provenance != .authorizedCalendarEvent || fact.permission == .authorized),
              let value = fact.value else {
            return nil
        }
        return boundedSingleLine(value, maximumUTF16Count: field.maximumUTF16Count)
    }

    private static func string(
        _ fact: StyleMemoryFact<StyleMemoryScanSummary>,
        field: StyleMemoryWorkerField,
        now: Date,
        sessionID: String?
    ) -> String? {
        guard field.allowedProvenance.contains(fact.provenance),
              fact.isFresh(at: now, sessionID: sessionID),
              let value = fact.value else {
            return nil
        }
        return boundedSingleLine(value.summary, maximumUTF16Count: field.maximumUTF16Count)
    }

    /// Preserves composed characters; output never exceeds the UTF-16 budget.
    private static func boundedSingleLine(_ value: String, maximumUTF16Count: Int) -> String? {
        let normalized = value
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !normalized.isEmpty else { return nil }
        guard normalized.utf16.count > maximumUTF16Count else { return normalized }
        let ellipsis = "…"
        var result = ""
        var count = 0
        for character in normalized {
            let width = String(character).utf16.count
            guard count + width + ellipsis.utf16.count <= maximumUTF16Count else { break }
            result.append(character)
            count += width
        }
        return result.isEmpty ? nil : result + ellipsis
    }
}
