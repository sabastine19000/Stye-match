import Foundation

struct DetectedLabel: Codable {
    let identifier: String
    let confidence: Float
}

/// Canonical persisted representation for `outfitScanHistoryData`. This is
/// intentionally the same Codable model formerly owned by ScanView so Build
/// 18035 history continues to decode byte-for-byte by its existing keys.
struct StoredOutfitScan: Codable {
    let score: Int
    let analysis: OutfitAnalysisResult?
    let firstScannedAt: Date
    var scanCount: Int
    let thumbnailData: Data?
    var customTitle: String?
    var occasion: Occasion?
    let imageDigest: String?
    var savedImageAsset: SavedScanImageAsset?
    let deterministicInputs: StoredDeterministicScorerInputs?
    let scoreModelVersion: String?

    var savedImageAssetID: String? { savedImageAsset?.id }

    init(score: Int, analysis: OutfitAnalysisResult?, firstScannedAt: Date, scanCount: Int, thumbnailData: Data? = nil, customTitle: String? = nil, occasion: Occasion? = nil, imageDigest: String? = nil, savedImageAsset: SavedScanImageAsset? = nil, deterministicInputs: StoredDeterministicScorerInputs? = nil, scoreModelVersion: String? = nil) {
        self.score = score; self.analysis = analysis; self.firstScannedAt = firstScannedAt; self.scanCount = scanCount
        self.thumbnailData = thumbnailData; self.customTitle = customTitle; self.occasion = occasion
        self.imageDigest = imageDigest; self.savedImageAsset = savedImageAsset; self.deterministicInputs = deterministicInputs
        self.scoreModelVersion = scoreModelVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        score = try container.decode(Int.self, forKey: .score)
        analysis = try container.decodeIfPresent(OutfitAnalysisResult.self, forKey: .analysis)
        firstScannedAt = try container.decode(Date.self, forKey: .firstScannedAt)
        scanCount = try container.decodeIfPresent(Int.self, forKey: .scanCount) ?? 1
        thumbnailData = try container.decodeIfPresent(Data.self, forKey: .thumbnailData)
        customTitle = try container.decodeIfPresent(String.self, forKey: .customTitle)
        if let occasionLabel = try container.decodeIfPresent(String.self, forKey: .occasion) {
            occasion = (Occasion(rawValue: occasionLabel) ?? Occasion(label: occasionLabel))?.canonical
        } else { occasion = nil }
        imageDigest = try container.decodeIfPresent(String.self, forKey: .imageDigest)
        savedImageAsset = try container.decodeIfPresent(SavedScanImageAsset.self, forKey: .savedImageAsset)
        deterministicInputs = try container.decodeIfPresent(StoredDeterministicScorerInputs.self, forKey: .deterministicInputs)
        scoreModelVersion = try container.decodeIfPresent(String.self, forKey: .scoreModelVersion)
    }
}

struct StoredDeterministicScorerInputs: Codable {
    let colorPalette: [String]
    let colorPaletteConfidence: GarmentPaletteConfidence
    let labels: [DetectedLabel]
    let detectedItems: [String]
    let styleCategory: String
}
