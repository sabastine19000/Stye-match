import Foundation

enum StoredScanLifecycle: String, Codable, Sendable {
    case completed
    case inProgress
    case failed
    case placeholder
    case deleted
    case quarantined
}

struct StoredScanAuthorityMetadata: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let generation: ScanGeneration
    let contextFingerprint: String
    let completionOrdinal: UInt64?
}

struct StoredScanRecord: Codable, @unchecked Sendable {
    let score: Int?
    let analysis: OutfitAnalysisResult?
    let firstScannedAt: Date?
    let occasion: Occasion?
    let thumbnailData: Data?
    let lifecycle: StoredScanLifecycle?
    let authorityMetadata: StoredScanAuthorityMetadata?

    var inferredState: ScanAuthorityState {
        switch lifecycle {
        case .completed:
            return analysis == nil ? .partial : .completed
        case .inProgress: return .inProgress
        case .failed: return .failed
        case .placeholder: return .placeholder
        case .deleted: return .deleted
        case .quarantined: return .quarantined
        case nil:
            return analysis == nil ? .partial : .completed
        }
    }
}

struct DecodedStoredScan: @unchecked Sendable {
    let id: LocalScanRecordID
    let record: StoredScanRecord
    let decodeCorrupt: Bool

    init(
        id: LocalScanRecordID,
        record: StoredScanRecord,
        decodeCorrupt: Bool = false
    ) {
        self.id = id
        self.record = record
        self.decodeCorrupt = decodeCorrupt
    }

    var state: ScanAuthorityState {
        decodeCorrupt ? .corrupt : record.inferredState
    }
}

enum StoredScanRecordDecoder {
    static func decode(_ data: Data?) -> Result<[DecodedStoredScan], ScanAuthorityError> {
        guard let data, !data.isEmpty else {
            return .success([])
        }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return .failure(.scanCorrupt)
        }

        let decoder = JSONDecoder()
        var records: [DecodedStoredScan] = []
        for rawID in dictionary.keys.sorted() {
            guard let id = LocalScanRecordID(rawValue: rawID) else {
                continue
            }
            guard JSONSerialization.isValidJSONObject(dictionary[rawID] as Any),
                  let recordData = try? JSONSerialization.data(
                    withJSONObject: dictionary[rawID] as Any,
                    options: [.sortedKeys]
                  ),
                  let record = try? decoder.decode(StoredScanRecord.self, from: recordData) else {
                records.append(DecodedStoredScan(
                    id: id,
                    record: StoredScanRecord(
                        score: nil,
                        analysis: nil,
                        firstScannedAt: nil,
                        occasion: nil,
                        thumbnailData: nil,
                        lifecycle: nil,
                        authorityMetadata: nil
                    ),
                    decodeCorrupt: true
                ))
                continue
            }
            records.append(DecodedStoredScan(id: id, record: record))
        }
        return .success(records)
    }
}
