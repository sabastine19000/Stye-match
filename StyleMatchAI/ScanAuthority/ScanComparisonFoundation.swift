import Foundation

enum ScanScoreModelVersion: String, Codable, Equatable { case legacyUnknown; case styleMatchScoreV1 = "stylematch_score_v1"; static let current: Self = .styleMatchScoreV1; static func persisted(_ value: String?) -> Self { guard let value, let known = Self(rawValue: value) else { return .legacyUnknown }; return known } }
enum ScanComparisonCompatibility: String, Codable, Equatable { case fullyCompatible, limitedLegacyUnknown, limitedIncompatibleModel }
struct StoredScanComparisonCategoryDelta: Codable, Equatable, Identifiable { let id: String; let olderValue: Int; let newerValue: Int; let maximum: Int; var delta: Int { newerValue - olderValue } }
struct StoredScanComparison: Codable, Equatable, Identifiable { static let schemaVersion = 1; let id: UUID; let schema: Int; let olderScanID: String; let newerScanID: String; let createdAt: Date; let olderScore: Int; let newerScore: Int; let compatibility: ScanComparisonCompatibility; let categoryDeltas: [StoredScanComparisonCategoryDelta]; let summary: String; var overallDelta: Int { newerScore - olderScore } }
enum ScanComparisonPersistenceError: Error, Equatable { case invalidReferences, invalidRecord }
final class ScanComparisonPersistenceAuthority {
    private static let baseKey = "storedScanComparisonsV1"; private let defaults: UserDefaults; private let userID: String
    init(defaults: UserDefaults = .standard, userID: String? = nil) { self.defaults = defaults; self.userID = PersonalStylistStorage.normalizedUserID(userID ?? PersonalStylistStorage.activeUserID(defaults: defaults)) }
    var comparisons: [StoredScanComparison] { guard let data = defaults.data(forKey: key), let decoded = try? JSONDecoder().decode([StoredScanComparison].self, from: data) else { return [] }; return decoded.sorted { $0.createdAt > $1.createdAt } }
    func save(_ comparison: StoredScanComparison, existingScanIDs: Set<String>) throws { guard comparison.schema == StoredScanComparison.schemaVersion, comparison.olderScanID != comparison.newerScanID, existingScanIDs.contains(comparison.olderScanID), existingScanIDs.contains(comparison.newerScanID) else { throw ScanComparisonPersistenceError.invalidReferences }; guard (0...100).contains(comparison.olderScore), (0...100).contains(comparison.newerScore), comparison.summary.count <= 320 else { throw ScanComparisonPersistenceError.invalidRecord }; var updated = comparisons.filter { $0.id != comparison.id }; updated.append(comparison); defaults.set(try JSONEncoder().encode(updated), forKey: key) }
    func delete(id: UUID) { defaults.set(try? JSONEncoder().encode(comparisons.filter { $0.id != id }), forKey: key) }
    private var key: String { PersonalStylistStorage.scopedKey(Self.baseKey, userID: userID) }
}
struct ScanComparisonSnapshot: Equatable { let olderID: String; let newerID: String; let olderDate: Date; let newerDate: Date; let olderScore: Int; let newerScore: Int; let compatibility: ScanComparisonCompatibility; let categoryDeltas: [StoredScanComparisonCategoryDelta]; var overallDelta: Int { newerScore - olderScore }; var improvementSummary: [String] { categoryDeltas.filter { $0.delta > 0 }.map { "\($0.id) improved by \($0.delta) points." } }; var workOnSummary: [String] { categoryDeltas.filter { $0.delta < 0 }.map { "\($0.id) declined by \(abs($0.delta)) points." } } }
enum ScanComparisonBuilder {
    static func make(idA: String, scanA: StoredOutfitScan, idB: String, scanB: StoredOutfitScan) -> ScanComparisonSnapshot? { guard idA != idB, let analysisA = scanA.analysis, let analysisB = scanB.analysis else { return nil }; let older: (String, StoredOutfitScan, OutfitAnalysisResult); let newer: (String, StoredOutfitScan, OutfitAnalysisResult); if scanA.firstScannedAt <= scanB.firstScannedAt { older = (idA, scanA, analysisA); newer = (idB, scanB, analysisB) } else { older = (idB, scanB, analysisB); newer = (idA, scanA, analysisA) }; let compatibility = compatibility(older.1.scoreModelVersion, newer.1.scoreModelVersion); let categories: [StoredScanComparisonCategoryDelta]; if compatibility == .fullyCompatible, let lhs = older.2.scoreBreakdown, let rhs = newer.2.scoreBreakdown { categories = deltas(lhs, rhs) } else { categories = [] }; return .init(olderID: older.0, newerID: newer.0, olderDate: older.1.firstScannedAt, newerDate: newer.1.firstScannedAt, olderScore: older.1.score, newerScore: newer.1.score, compatibility: compatibility, categoryDeltas: categories) }
    static func compatibility(_ older: String?, _ newer: String?) -> ScanComparisonCompatibility { let lhs = older?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""; let rhs = newer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""; guard !lhs.isEmpty, !rhs.isEmpty else { return .limitedLegacyUnknown }; return lhs == ScanScoreModelVersion.current.rawValue && rhs == ScanScoreModelVersion.current.rawValue ? .fullyCompatible : .limitedIncompatibleModel }
    private static func deltas(_ older: OutfitScoreBreakdown, _ newer: OutfitScoreBreakdown) -> [StoredScanComparisonCategoryDelta] { [("Color Harmony", older.colorHarmony, newer.colorHarmony, 25), ("Pattern Mix", older.patternBalance, newer.patternBalance, 20), ("Fit", older.fitQuality, newer.fitQuality, 25), ("Accessories", older.accessoryUse, newer.accessoryUse, 10)].map { .init(id: $0.0, olderValue: $0.1, newerValue: $0.2, maximum: $0.3) } }
}
struct CompareStylistRouteRequest: Equatable {
    let comparison: ScanComparisonSnapshot
    let occasion: String?
    let workContext: String?
    let ppeConstraint: String?

    init(comparison: ScanComparisonSnapshot, occasion: String? = nil, workContext: String? = nil, ppeConstraint: String? = nil) {
        self.comparison = comparison
        self.occasion = occasion
        self.workContext = workContext
        self.ppeConstraint = ppeConstraint
    }

    /// This is deliberately a small, customer-visible summary. Stable scan IDs,
    /// image references, and persistence internals never cross into the chat route.
    var customerVisibleFacts: [String] {
        var facts = [
            "Customer explicitly opened AI Stylist from Compare.",
            "Compared scans from \(Self.dateFormatter.string(from: comparison.olderDate)) and \(Self.dateFormatter.string(from: comparison.newerDate)).",
            "Scores: \(comparison.olderScore)/100 → \(comparison.newerScore)/100 (\(comparison.overallDelta >= 0 ? "+" : "")\(comparison.overallDelta)).",
            compatibilityFact
        ]
        if comparison.compatibility == .fullyCompatible, !comparison.categoryDeltas.isEmpty {
            facts.append("Category changes: " + comparison.categoryDeltas.map { "\($0.id) \($0.delta >= 0 ? "+" : "")\($0.delta)" }.joined(separator: ", ") + ".")
        }
        [occasion.map { "Occasion: \($0)." }, workContext.map { "Work context: \($0)." }, ppeConstraint.map { "PPE or workplace constraint: \($0)." }]
            .compactMap { $0 }
            .forEach { facts.append($0) }
        facts.append(contentsOf: comparison.improvementSummary + comparison.workOnSummary)
        return Array(facts.prefix(8))
    }

    private var compatibilityFact: String {
        switch comparison.compatibility {
        case .fullyCompatible:
            "Category comparison is compatible with the same scoring model."
        case .limitedLegacyUnknown:
            "Category comparison is unavailable because at least one historical scan has an unknown scoring model."
        case .limitedIncompatibleModel:
            "Category comparison is unavailable because the scans use different scoring models."
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
