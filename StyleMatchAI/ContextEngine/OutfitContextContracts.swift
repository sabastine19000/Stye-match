import Foundation

protocol FailClosedStringEnum: Codable, RawRepresentable where RawValue == String {
    static var unknownFallback: Self { get }
}

extension FailClosedStringEnum {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = Self(rawValue: rawValue) ?? Self.unknownFallback
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum OutfitPurpose: String, CaseIterable, Equatable, Hashable, FailClosedStringEnum {
    case factoryManufacturing
    case warehouse
    case office
    case businessCasualOffice
    case businessFormal
    case healthcare
    case retail
    case hospitality
    case construction
    case outdoorWork
    case remoteWork
    case school
    case gymTraining
    case sports
    case travel
    case vacation
    case everydayCasual
    case dateNight
    case weddingGuest
    case weddingParty
    case weddingDress
    case church
    case funeral
    case formalEvent
    case otherUncertain

    static let unknownFallback = OutfitPurpose.otherUncertain
}

enum WorkplaceProfile: String, CaseIterable, Equatable, FailClosedStringEnum {
    case factoryManufacturing
    case warehouse
    case office
    case businessCasualOffice
    case healthcare
    case retail
    case hospitality
    case construction
    case outdoorWork
    case remoteWork
    case otherUncertain

    static let unknownFallback = WorkplaceProfile.otherUncertain
}

enum EnvironmentType: String, CaseIterable, Equatable, FailClosedStringEnum {
    case home
    case office
    case closet
    case bedroom
    case retailStore
    case dressingRoom
    case school
    case gym
    case beach
    case outdoors
    case parkingGarage
    case eventVenue
    case placeOfWorship
    case otherUncertain

    static let unknownFallback = EnvironmentType.otherUncertain
}

enum ContextOccasion: String, CaseIterable, Equatable, FailClosedStringEnum {
    case general
    case work
    case businessFormal
    case weddingGuest
    case party
    case casualDay
    case gym
    case loungewear
    case specialEvent
    case dateNight
    case travel
    case otherUncertain

    static let unknownFallback = ContextOccasion.otherUncertain
}

enum SuitabilityLevel: String, CaseIterable, Equatable, FailClosedStringEnum {
    case high
    case moderate
    case low
    case uncertain
    case notApplicable

    static let unknownFallback = SuitabilityLevel.uncertain
}

struct OccasionCompatibility: Codable, Equatable {
    let level: SuitabilityLevel
    let confidence: ContextConfidence
    let supportingEvidenceIDs: [String]
    let conflictingEvidenceIDs: [String]
    let missingEvidenceIDs: [String]
    let summary: String

    static let uncertain = Self(
        level: .uncertain,
        confidence: .unknown,
        supportingEvidenceIDs: [],
        conflictingEvidenceIDs: [],
        missingEvidenceIDs: ["occasionCompatibility"],
        summary: "Occasion compatibility is uncertain."
    )
}

struct WorkplaceSuitability: Codable, Equatable {
    let level: SuitabilityLevel
    let confidence: ContextConfidence
    let supportingEvidenceIDs: [String]
    let conflictingEvidenceIDs: [String]
    let missingEvidenceIDs: [String]
    let summary: String

    static let uncertain = Self(
        level: .uncertain,
        confidence: .unknown,
        supportingEvidenceIDs: [],
        conflictingEvidenceIDs: [],
        missingEvidenceIDs: ["workplaceProfile"],
        summary: "Workplace suitability is uncertain."
    )
}

struct WeatherSuitability: Codable, Equatable {
    let level: SuitabilityLevel
    let confidence: ContextConfidence
    let supportingEvidenceIDs: [String]
    let conflictingEvidenceIDs: [String]
    let missingEvidenceIDs: [String]
    let summary: String

    static let uncertain = Self(
        level: .uncertain,
        confidence: .unknown,
        supportingEvidenceIDs: [],
        conflictingEvidenceIDs: [],
        missingEvidenceIDs: ["weatherContext"],
        summary: "Weather suitability is uncertain."
    )
}

struct SafetySuitability: Codable, Equatable {
    let level: SuitabilityLevel
    let confidence: ContextConfidence
    let supportingEvidenceIDs: [String]
    let conflictingEvidenceIDs: [String]
    let missingEvidenceIDs: [String]
    let summary: String

    static let uncertain = Self(
        level: .uncertain,
        confidence: .unknown,
        supportingEvidenceIDs: [],
        conflictingEvidenceIDs: [],
        missingEvidenceIDs: ["safetyContext"],
        summary: "Safety suitability is not verified."
    )
}

enum ContextConfidenceLevel: String, CaseIterable, Equatable, FailClosedStringEnum {
    case high
    case medium
    case low

    static let unknownFallback = ContextConfidenceLevel.low
}

struct ContextConfidence: Codable, Equatable {
    let value: Double
    let level: ContextConfidenceLevel

    static let unknown = Self(value: 0, level: .low)

    init(value: Double, level: ContextConfidenceLevel) {
        self.value = min(1, max(0, value))
        self.level = level
    }
}

enum ContextValueOrigin: String, CaseIterable, Equatable, FailClosedStringEnum {
    case legacyDerived
    case userConfirmed
    case scanAuthoritative
    case runtimeInferred
    case unknown

    static let unknownFallback = ContextValueOrigin.unknown
}

enum ContextConfirmationState: String, CaseIterable, Equatable, FailClosedStringEnum {
    case proposed
    case confirmed
    case corrected
    case rejected
    case uncertain

    static let unknownFallback = ContextConfirmationState.uncertain
}

struct EvidenceBackedValue<Value: Codable & Equatable>: Codable, Equatable {
    let value: Value
    let confidence: ContextConfidence
    let evidenceIDs: [String]
    let origin: ContextValueOrigin
    let confirmationState: ContextConfirmationState
}

enum ContextEvidenceKind: String, CaseIterable, Equatable, Hashable, FailClosedStringEnum {
    case visualStyle
    case garmentSilhouette
    case garmentConstruction
    case textPresence
    case brandingPresence
    case selectedOccasion
    case environment
    case weather
    case safety
    case uncertainty

    static let unknownFallback = ContextEvidenceKind.uncertainty
}

struct ContextEvidence: Codable, Equatable, Identifiable {
    let id: String
    let kind: ContextEvidenceKind
    let summary: String
    let confidence: ContextConfidence
    let origin: ContextValueOrigin

    init(
        id: String,
        kind: ContextEvidenceKind,
        summary: String,
        confidence: ContextConfidence,
        origin: ContextValueOrigin
    ) {
        self.id = String(id.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        self.kind = kind
        self.summary = String(summary.trimmingCharacters(in: .whitespacesAndNewlines).prefix(180))
        self.confidence = confidence
        self.origin = origin
    }
}

enum MissingContextKind: String, CaseIterable, Equatable, FailClosedStringEnum {
    case visualStyle
    case garmentCategory
    case purpose
    case occasion
    case workplaceProfile
    case environment
    case weather
    case safety

    static let unknownFallback = MissingContextKind.purpose
}

struct MissingContextEvidence: Codable, Equatable, Identifiable {
    let id: String
    let kind: MissingContextKind
    let reason: String

    init(id: String, kind: MissingContextKind, reason: String) {
        self.id = String(id.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        self.kind = kind
        self.reason = String(reason.trimmingCharacters(in: .whitespacesAndNewlines).prefix(180))
    }
}

enum ContextProvenanceField: String, CaseIterable, Equatable, FailClosedStringEnum {
    case detectedStyle
    case garmentCategory
    case outfitPurpose
    case selectedOccasion
    case workplaceProfile
    case environment
    case weather
    case safety
    case scoringProfile
    case occasionCompatibility
    case workplaceSuitability
    case weatherSuitability
    case safetySuitability
    case overallConfidence

    static let unknownFallback = ContextProvenanceField.outfitPurpose
}

struct ContextProvenanceEntry: Codable, Equatable {
    let field: ContextProvenanceField
    let source: ContextValueOrigin
    let recordedAt: Date
}

struct ContextProvenance: Codable, Equatable {
    let algorithmVersion: String
    let adapterVersion: String?
    let sourceScanID: String
    let sourceCompletedAt: Date
    let legacyFallbackUsed: Bool
    let entries: [ContextProvenanceEntry]
}

enum PurposeScoringProfile: String, CaseIterable, Equatable, FailClosedStringEnum {
    case factoryManufacturing
    case warehouse
    case office
    case businessCasualOffice
    case businessFormal
    case healthcare
    case retail
    case hospitality
    case construction
    case outdoorWork
    case remoteWork
    case school
    case gymTraining
    case sports
    case travel
    case vacation
    case everydayCasual
    case dateNight
    case weddingGuest
    case weddingParty
    case weddingDress
    case church
    case funeral
    case formalEvent
    case accessoriesFootwear
    case protectiveOuterwear
    case swimwear
    case culturalTraditional
    case uncertain

    static let unknownFallback = PurposeScoringProfile.uncertain
}

enum ContextGarmentCategory: String, CaseIterable, Equatable, FailClosedStringEnum {
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

    static let unknownFallback = ContextGarmentCategory.otherUncertain
}

struct WeatherContextReference: Codable, Equatable {
    let observedAt: Date?
    let airTemperature: Int?
    let feelsLikeTemperature: Int?
    let humidityPercent: Int?
    let rainChancePercent: Int?
    let windMph: Int?
    let uvIndex: Int?
    let condition: String?
    let confidence: ContextConfidence

    static let unknown = Self(
        observedAt: nil,
        airTemperature: nil,
        feelsLikeTemperature: nil,
        humidityPercent: nil,
        rainChancePercent: nil,
        windMph: nil,
        uvIndex: nil,
        condition: nil,
        confidence: .unknown
    )

    var hasEvidence: Bool {
        observedAt != nil
            || airTemperature != nil
            || feelsLikeTemperature != nil
            || humidityPercent != nil
            || rainChancePercent != nil
            || windMph != nil
            || uvIndex != nil
            || condition != nil
    }

    init(
        observedAt: Date?,
        airTemperature: Int?,
        feelsLikeTemperature: Int?,
        humidityPercent: Int?,
        rainChancePercent: Int?,
        windMph: Int?,
        uvIndex: Int?,
        condition: String?,
        confidence: ContextConfidence
    ) {
        self.observedAt = observedAt
        self.airTemperature = airTemperature
        self.feelsLikeTemperature = feelsLikeTemperature
        self.humidityPercent = humidityPercent
        self.rainChancePercent = rainChancePercent
        self.windMph = windMph
        self.uvIndex = uvIndex
        let trimmedCondition = condition?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.condition = trimmedCondition.flatMap { $0.isEmpty ? nil : String($0.prefix(80)) }
        self.confidence = confidence
    }

    static func privacySafeReference(
        to snapshot: WeatherContextSnapshot,
        observedAt: Date?
    ) -> Self {
        Self(
            observedAt: observedAt,
            airTemperature: snapshot.airTemperature,
            feelsLikeTemperature: snapshot.feelsLikeTemperature,
            humidityPercent: snapshot.humidityPercent,
            rainChancePercent: snapshot.rainChancePercent,
            windMph: snapshot.windMph,
            uvIndex: snapshot.uvIndex,
            condition: snapshot.condition,
            confidence: ContextConfidence(
                value: Double(min(100, max(0, snapshot.confidence))) / 100,
                level: snapshot.confidence >= 82 ? .high : (snapshot.confidence >= 55 ? .medium : .low)
            )
        )
    }
}

struct SafetyContext: Codable, Equatable {
    let supportingEvidenceIDs: [String]
    let missingEvidenceIDs: [String]
    let limitations: [String]

    static let unverified = Self(
        supportingEvidenceIDs: [],
        missingEvidenceIDs: ["safetyContext"],
        limitations: ["Safety requirements were not verified from this legacy scan."]
    )
}

struct OutfitContextSnapshot: Codable, Equatable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let generation: UInt64
    let scanID: String
    let completedAt: Date
    let authoritativeScore: Int
    let authoritativeBreakdown: OutfitScoreBreakdown?

    let detectedStyle: EvidenceBackedValue<String>
    let garmentCategory: EvidenceBackedValue<ContextGarmentCategory>
    let outfitPurpose: EvidenceBackedValue<OutfitPurpose>
    let environmentType: EvidenceBackedValue<EnvironmentType>

    let selectedOccasion: EvidenceBackedValue<ContextOccasion>
    let occasionCompatibility: OccasionCompatibility
    let workplaceProfile: EvidenceBackedValue<WorkplaceProfile>
    let workplaceSuitability: WorkplaceSuitability
    let weatherContext: WeatherContextReference
    let weatherSuitability: WeatherSuitability
    let safetyContext: SafetyContext
    let safetySuitability: SafetySuitability

    let userConfirmedPurpose: OutfitPurpose?
    let confidence: ContextConfidence
    let evidence: [ContextEvidence]
    let missingEvidence: [MissingContextEvidence]
    let scoringProfile: PurposeScoringProfile
    let provenance: ContextProvenance
}
