import CryptoKit
import Foundation

/// Legacy recovery validation retained for explicitly injected, private fixtures.
/// Application launch never invokes this importer or bundles customer records.
struct VerifiedScanHistoryRecoveryImporter {
    static let historyKey = "outfitScanHistoryData"
    static let completionKey = "verifiedSevenScanRecoveryImporter.v1.completed"
    static let mergedHistoryDigestKey = "verifiedSevenScanRecoveryImporter.v1.mergedCanonicalSHA256"
    /// Evidence only: this is the SHA-256 of the preserved raw JSON payload,
    /// not the semantic approval gate.
    static let approvedRawPayloadSHA256 = "3f58016983c0e0c262f5ffb24c49d61c841f560bcee7e82733f5a47acaa30641"
    /// Semantic approval gate: record-level JSON decoded from every persisted
    /// saved-scan field, then encoded with JSONEncoder `.sortedKeys`.
    static let approvedCanonicalHistorySHA256 = "bd53b88141065e3a5ab2cca4474e77eacfea12a66b22f602019fc20bd7bb4d84"
    static let expectedRecordCount = 7

    enum Outcome: Equatable {
        case imported
        case alreadyCompleted
        case ineligible
        case sourceUnavailable
        case invalidPayload
        case invalidActiveHistory
        case stableIDConflict
        case readbackFailed
    }

    private let defaults: UserDefaults
    private let recoveryPackageURL: URL?
    private let approvedRawPayloadHash: String?
    private let approvedCanonicalHistoryHash: String
    private let expectedRecordCount: Int
    private let loadHistory: () -> Data?
    private let saveHistory: (Data?) -> Void

    init(
        defaults: UserDefaults = .standard,
        sourceURL: URL? = VerifiedScanHistoryRecoveryImporter.defaultRecoveryPackageURL(),
        approvedRawPayloadHash: String? = nil,
        approvedCanonicalHistoryHash: String = VerifiedScanHistoryRecoveryImporter.approvedCanonicalHistorySHA256,
        expectedRecordCount: Int = VerifiedScanHistoryRecoveryImporter.expectedRecordCount,
        loadHistory: (() -> Data?)? = nil,
        saveHistory: ((Data?) -> Void)? = nil
    ) {
        self.defaults = defaults
        self.recoveryPackageURL = sourceURL
        self.approvedRawPayloadHash = approvedRawPayloadHash
        self.approvedCanonicalHistoryHash = approvedCanonicalHistoryHash
        self.expectedRecordCount = expectedRecordCount
        self.loadHistory = loadHistory ?? { defaults.data(forKey: Self.historyKey) }
        self.saveHistory = saveHistory ?? { data in
            if let data {
                defaults.set(data, forKey: Self.historyKey)
            } else {
                defaults.removeObject(forKey: Self.historyKey)
            }
        }
    }

    @discardableResult
    func run() -> Outcome {
        guard defaults.bool(forKey: Self.completionKey) == false else {
            return .alreadyCompleted
        }
        guard eligibleAppleIdentity(), noScopedHistoryExists() else {
            return .ineligible
        }
        guard let recoveryPackageURL,
              let recoveryData = recoveryDataFromPrivatePackage() else {
            return .sourceUnavailable
        }
        let rawPayloadMatches = approvedRawPayloadHash.map {
            Self.payloadHash(recoveryData) == $0
        } ?? (recoveryPackageURL == Self.defaultRecoveryPackageURL()
            ? Self.payloadHash(recoveryData) == Self.approvedRawPayloadSHA256
            : true)
        guard let recoveryRecords = decodeValidRecords(recoveryData),
              let recoveryValues = decodeLosslessRecords(recoveryData),
              recoveryRecords.count == expectedRecordCount,
              recoveryValues.count == expectedRecordCount,
              recoveryRecords.keys.allSatisfy(Self.isValidStableScanID),
              rawPayloadMatches,
              Self.canonicalDigest(for: recoveryData) == approvedCanonicalHistoryHash else {
            return .invalidPayload
        }

        let activeHistory: ([String: RecoveryRecord], [String: CanonicalJSONValue])
        switch decodedActiveHistory() {
        case .absent:
            activeHistory = ([:], [:])
        case .valid(let records, let values):
            activeHistory = (records, values)
        case .invalid:
            return .invalidActiveHistory
        }

        guard let merged = merge(
            currentRecords: activeHistory.0,
            currentValues: activeHistory.1,
            recoveryRecords: recoveryRecords,
            recoveryValues: recoveryValues
        ) else {
            return .stableIDConflict
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let mergedData = try? encoder.encode(merged.values),
              let mergedCanonicalDigest = Self.canonicalDigest(for: mergedData) else {
            return .readbackFailed
        }

        // This is intentionally the only scan-history persistence write performed by the importer.
        let originalHistory = loadHistory()
        saveHistory(mergedData)

        guard let readback = loadHistory(),
              let readbackRecords = decodeValidRecords(readback),
              let readbackValues = decodeLosslessRecords(readback),
              readbackRecords.count == merged.records.count,
              readbackValues == merged.values,
              Self.canonicalDigest(for: readback) == mergedCanonicalDigest,
              activeHistory.1.allSatisfy({ readbackValues[$0.key] == $0.value }),
              recoveryValues.allSatisfy({ readbackValues[$0.key] != nil }),
              noGuestScopedHistoryExists() else {
            restoreOriginalHistory(originalHistory)
            return .readbackFailed
        }

        defaults.set(mergedCanonicalDigest, forKey: Self.mergedHistoryDigestKey)
        defaults.set(true, forKey: Self.completionKey)
        return .imported
    }

    private func eligibleAppleIdentity() -> Bool {
        let appleUserID = defaults.string(forKey: "customerAppleUserID")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !appleUserID.isEmpty && AccountScopedStorage.sessionUserID(defaults: defaults) != "guest"
    }

    private func noScopedHistoryExists() -> Bool {
        let appleUserID = AccountScopedStorage.sessionUserID(defaults: defaults)
        guard appleUserID != "guest" else { return false }

        for userID in [appleUserID, "guest"] {
            for environment in AccountStorageEnvironment.allCases {
                if defaults.object(forKey: AccountScopedStorage.snapshotKey(Self.historyKey, userID: userID, environment: environment)) != nil {
                    return false
                }
            }
            if defaults.object(forKey: AccountScopedStorage.legacySnapshotKey(Self.historyKey, userID: userID)) != nil {
                return false
            }
        }
        return true
    }

    private func noGuestScopedHistoryExists() -> Bool {
        AccountStorageEnvironment.allCases.allSatisfy {
            defaults.object(forKey: AccountScopedStorage.snapshotKey(Self.historyKey, userID: "guest", environment: $0)) == nil
        } && defaults.object(forKey: AccountScopedStorage.legacySnapshotKey(Self.historyKey, userID: "guest")) == nil
    }

    private func recoveryDataFromPrivatePackage() -> Data? {
        guard let recoveryPackageURL else { return nil }
        return try? Data(contentsOf: recoveryPackageURL)
    }

    private func decodeValidRecords(_ data: Data) -> [String: RecoveryRecord]? {
        guard let records = try? JSONDecoder().decode([String: RecoveryRecord].self, from: data),
              records.values.allSatisfy({ $0.isStructurallyValid }) else {
            return nil
        }
        return records
    }

    private func decodeLosslessRecords(_ data: Data) -> [String: CanonicalJSONValue]? {
        guard RecoveryRootKeyScanner.hasUniqueKeys(in: data) else { return nil }
        return try? JSONDecoder().decode([String: CanonicalJSONValue].self, from: data)
    }

    private enum ActiveHistory {
        case absent
        case valid([String: RecoveryRecord], [String: CanonicalJSONValue])
        case invalid
    }

    private func decodedActiveHistory() -> ActiveHistory {
        guard let data = loadHistory(), !data.isEmpty else { return .absent }
        guard let records = decodeValidRecords(data),
              let values = decodeLosslessRecords(data) else {
            return .invalid
        }
        return .valid(records, values)
    }

    private func merge(
        currentRecords: [String: RecoveryRecord],
        currentValues: [String: CanonicalJSONValue],
        recoveryRecords: [String: RecoveryRecord],
        recoveryValues: [String: CanonicalJSONValue]
    ) -> (records: [String: RecoveryRecord], values: [String: CanonicalJSONValue])? {
        var records = currentRecords
        var values = currentValues
        for stableID in recoveryRecords.keys {
            if let existing = values[stableID] {
                guard existing == recoveryValues[stableID] else { return nil }
                continue
            }
            records[stableID] = recoveryRecords[stableID]
            values[stableID] = recoveryValues[stableID]
        }

        let newestFirst = records.keys.sorted { lhs, rhs in
            guard let left = records[lhs], let right = records[rhs] else { return lhs < rhs }
            if left.firstScannedAt != right.firstScannedAt {
                return left.firstScannedAt > right.firstScannedAt
            }
            return lhs < rhs
        }
        let orderedRecords = Dictionary(uniqueKeysWithValues: newestFirst.compactMap { stableID in
            records[stableID].map { (stableID, $0) }
        })
        let orderedValues = Dictionary(uniqueKeysWithValues: newestFirst.compactMap { stableID in
            values[stableID].map { (stableID, $0) }
        })
        return (orderedRecords, orderedValues)
    }

    private func restoreOriginalHistory(_ originalHistory: Data?) {
        if let originalHistory {
            saveHistory(originalHistory)
        } else {
            saveHistory(nil)
        }
    }

    private static func isValidStableScanID(_ stableID: String) -> Bool {
        !stableID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Canonical record-level representation for the approved recovery source.
    ///
    /// - Root: `[stableScanID: record]`, with all persisted fields retained.
    /// - Objects: `JSONEncoder.OutputFormatting.sortedKeys` ordering.
    /// - Arrays: original decoded order.
    /// - Dates/data: represented by the source's JSON numeric/string scalar values,
    ///   then emitted through this encoder's canonical scalar representation.
    /// - Numbers/bools/null: decoded and re-encoded as JSON scalar values;
    ///   absent keys remain absent while explicit null remains `null`.
    /// - Strings: Swift JSONEncoder UTF-8 output, compact with no pretty print
    ///   or trailing newline; required JSON escapes are emitted by Foundation.
    static func canonicalData(for data: Data) -> Data? {
        guard RecoveryRootKeyScanner.hasUniqueKeys(in: data),
              let records = try? JSONDecoder().decode([String: CanonicalJSONValue].self, from: data) else {
            return nil
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(records)
    }

    static func canonicalDigest(for data: Data) -> String? {
        canonicalData(for: data).map(payloadHash)
    }

    static func payloadHash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func defaultRecoveryPackageURL() -> URL? {
        // Recovery data is never a distributable app resource.
        nil
    }

    private struct RecoveryRecord: Decodable {
        let score: Int
        let firstScannedAt: Date
        let scanCount: Int
        let analysis: [String: JSONValue]
        let thumbnailData: Data?

        var isStructurallyValid: Bool {
            (0...100).contains(score)
                && scanCount > 0
                && firstScannedAt.timeIntervalSinceReferenceDate.isFinite
                && !analysis.isEmpty
        }
    }

    private indirect enum JSONValue: Decodable {
        case object([String: JSONValue])
        case array([JSONValue])
        case string(String)
        case number(Double)
        case bool(Bool)
        case null

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() { self = .null }
            else if let value = try? container.decode(Bool.self) { self = .bool(value) }
            else if let value = try? container.decode(Double.self) { self = .number(value) }
            else if let value = try? container.decode(String.self) { self = .string(value) }
            else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
            else { self = .array(try container.decode([JSONValue].self)) }
        }
    }

    private indirect enum CanonicalJSONValue: Codable, Equatable {
        case object([String: CanonicalJSONValue])
        case array([CanonicalJSONValue])
        case string(String)
        case int(Int)
        case double(Double)
        case bool(Bool)
        case null

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() { self = .null }
            else if let value = try? container.decode(Bool.self) { self = .bool(value) }
            else if let value = try? container.decode(Int.self) { self = .int(value) }
            else if let value = try? container.decode(Double.self) { self = .double(value) }
            else if let value = try? container.decode(String.self) { self = .string(value) }
            else if let value = try? container.decode([String: CanonicalJSONValue].self) { self = .object(value) }
            else { self = .array(try container.decode([CanonicalJSONValue].self)) }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .object(let value): try container.encode(value)
            case .array(let value): try container.encode(value)
            case .string(let value): try container.encode(value)
            case .int(let value): try container.encode(value)
            case .double(let value): try container.encode(value)
            case .bool(let value): try container.encode(value)
            case .null: try container.encodeNil()
            }
        }
    }

    private struct RecoveryRootKeyScanner {
        private let bytes: [UInt8]
        private var index = 0

        private init(_ data: Data) {
            bytes = Array(data)
        }

        static func hasUniqueKeys(in data: Data) -> Bool {
            var scanner = Self(data)
            guard let keys = scanner.rootObjectKeys(), scanner.isAtEnd else { return false }
            return Set(keys).count == keys.count
        }

        private var isAtEnd: Bool {
            var copy = self
            copy.skipWhitespace()
            return copy.index == copy.bytes.count
        }

        private mutating func rootObjectKeys() -> [String]? {
            skipWhitespace()
            guard consume("{") else { return nil }
            skipWhitespace()
            if consume("}") { return [] }

            var keys = [String]()
            while true {
                guard let key = parseString(), consume(":"), skipValue() else { return nil }
                keys.append(key)
                skipWhitespace()
                if consume("}") { return keys }
                guard consume(",") else { return nil }
                skipWhitespace()
            }
        }

        private mutating func skipValue() -> Bool {
            skipWhitespace()
            guard index < bytes.count else { return false }
            switch bytes[index] {
            case ascii("{"):
                index += 1
                skipWhitespace()
                if consume("}") { return true }
                while true {
                    guard parseString() != nil, consume(":"), skipValue() else { return false }
                    skipWhitespace()
                    if consume("}") { return true }
                    guard consume(",") else { return false }
                    skipWhitespace()
                }
            case ascii("["):
                index += 1
                skipWhitespace()
                if consume("]") { return true }
                while true {
                    guard skipValue() else { return false }
                    skipWhitespace()
                    if consume("]") { return true }
                    guard consume(",") else { return false }
                    skipWhitespace()
                }
            case ascii("\""):
                return parseString() != nil
            default:
                let start = index
                while index < bytes.count, !isDelimiter(bytes[index]) { index += 1 }
                return start < index
            }
        }

        private mutating func parseString() -> String? {
            skipWhitespace()
            guard consume("\"") else { return nil }
            let start = index - 1
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                if byte == ascii("\\") {
                    guard index < bytes.count else { return nil }
                    index += 1
                } else if byte == ascii("\"") {
                    let token = Data(bytes[start..<index])
                    return try? JSONDecoder().decode([String].self, from: Data("[".utf8) + token + Data("]".utf8)).first
                } else if byte < 0x20 {
                    return nil
                }
            }
            return nil
        }

        private mutating func consume(_ character: Character) -> Bool {
            skipWhitespace()
            guard index < bytes.count, bytes[index] == ascii(character) else { return false }
            index += 1
            return true
        }

        private mutating func skipWhitespace() {
            while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) {
                index += 1
            }
        }

        private func isDelimiter(_ byte: UInt8) -> Bool {
            byte == ascii(",") || byte == ascii("]") || byte == ascii("}") || [0x20, 0x09, 0x0A, 0x0D].contains(byte)
        }

        private func ascii(_ character: Character) -> UInt8 {
            character.asciiValue!
        }
    }
}


/// Explicit local recovery only; never searches guest or other-account stores.
/// The caller supplies a preserved payload and its independently verified owner.
enum ScopedScanHistoryRecovery {
    enum Outcome: String {
        case restored, alreadyPresent, wrongAccount, invalidPayload, existingHistory, readbackFailed
    }

    static func restore(
        data: Data,
        expectedSHA256: String,
        ownerStorageIdentifier: String,
        defaults: UserDefaults
    ) -> Outcome {
        let user = AccountScopedStorage.sessionUserID(defaults: defaults)
        guard user != "guest",
              AccountScopedStorage.activePresentationUserID(defaults: defaults) == user,
              AccountScopedStorage.activeEnvironment(defaults: defaults) == .production,
              PersonalStylistStorage.protectedStorageIdentifier(for: user) == ownerStorageIdentifier else {
            return .wrongAccount
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == expectedSHA256,
              let records = try? JSONDecoder().decode([String: StoredOutfitScan].self, from: data),
              !records.isEmpty,
              records.keys.allSatisfy({ !$0.isEmpty }),
              records.values.allSatisfy({ (0...100).contains($0.score) && $0.firstScannedAt.timeIntervalSinceReferenceDate.isFinite && $0.scanCount > 0 }) else {
            return .invalidPayload
        }
        let historyKey = "outfitScanHistoryData"
        let snapshotKey = AccountScopedStorage.snapshotKey(historyKey, userID: user, environment: .production)
        let original = defaults.object(forKey: historyKey)
        let snapshot = defaults.object(forKey: snapshotKey)
        for existing in [original, snapshot] {
            guard let existing else { continue }
            guard let bytes = existing as? Data else { return .existingHistory }
            if bytes == data || bytes.isEmpty { continue }
            guard let empty = try? JSONDecoder().decode([String: StoredOutfitScan].self, from: bytes), empty.isEmpty else {
                return .existingHistory
            }
        }
        if defaults.data(forKey: historyKey) == data, defaults.data(forKey: snapshotKey) == data {
            return .alreadyPresent
        }
        // Preserve a same-owner snapshot before making the active history visible.
        // Keep the original bytes, scores, timestamps, IDs and thumbnails intact.
        defaults.set(data, forKey: snapshotKey)
        defaults.set(data, forKey: historyKey)
        guard defaults.data(forKey: historyKey) == data, defaults.data(forKey: snapshotKey) == data else {
            for (key, value) in [(historyKey, original), (snapshotKey, snapshot)] {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
            return .readbackFailed
        }
        return .restored
    }
}
