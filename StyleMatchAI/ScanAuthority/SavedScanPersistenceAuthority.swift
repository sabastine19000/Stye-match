import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The only saved-scan persistence bridge available to cross-device sync.
/// It owns the existing history key and private Codable representation.
struct SavedScanSyncDTO: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let authoritativeScore: Int
    let savedAt: Date
    let occasion: String?
    let title: String?
    let colors: [String]
    let persistentAnalysisMetadata: Data
    let imageAssetID: String?
    let imageSHA256: String?
    let imageByteCount: Int64?
    let version: String
}

enum SavedScanPersistenceError: Error, Equatable {
    case malformedHistory
    case malformedTombstones
    case missing
    case invalidPayload
    case conflict
    case stale
    case imageMismatch
}

/// Read-only, local-only facts for an explicitly selected saved scan. This is
/// intentionally not Codable: the canonical Stylist builder must replace the
/// local key with a request-scoped alias before creating any network DTO.
struct SavedScanStylistFacts: Equatable, Sendable {
    let localRecordKey: String
    let scanDate: Date
    let selectedOccasion: String?
    let score: Int?
    /// Saved scans do not persist an authoritative score-band field. Legacy
    /// records therefore expose no band instead of recalculating one here.
    let scoreBand: String?
    let detectedStyle: String?
    /// Present only when the persisted palette confidence is `.confident`.
    /// The confidence state itself is intentionally never exposed.
    let palette: [String]?
}

/// Local, read-only share projection; never encoded or used for sync writes.
struct SavedScanShareSource {
    let authoritativeScore: Int
    let title: String?
    let occasion: String?
    let imagePreview: Data?
}

struct SavedScanShareReadResult {
    let savedRecordCount: Int
    let sources: [SavedScanShareSource]
}

final class SavedScanPersistenceAuthority {
    private static let historyKey = "outfitScanHistoryData"
    /// Tombstones are authority-private. They are intentionally separate from
    /// history so a deleted stable ID remains protected when an offline device
    /// later replays an older record.
    private static let tombstoneKey = "savedScanSyncTombstonesV1"
    private let defaults: UserDefaults
    private let images: SavedScanImageAssetStore

    init(defaults: UserDefaults = .standard, images: SavedScanImageAssetStore = SavedScanImageAssetStore()) {
        self.defaults = defaults; self.images = images
    }

    func enumerateSavedScans() throws -> [SavedScanSyncDTO] {
        var records: [SavedScanSyncDTO] = []
        for id in try history().keys.sorted() {
            if let record = try makeSyncRecord(id: id) {
                records.append(record)
            }
        }
        return records
    }

    /// Reads stored facts without sync requirements, migration, or backfill.
    /// An unusable record cannot hide unrelated valid saved scans.
    func readSavedScanShareSources() throws -> SavedScanShareReadResult {
        let all = try history()
        let sources = all.keys.sorted().compactMap { id -> SavedScanShareSource? in
            guard let scan = all[id], (0...100).contains(scan.score),
                  scan.analysis == nil || scan.analysis?.score == scan.score else { return nil }
            var preview: Data?
            if let asset = scan.savedImageAsset,
               asset.ownerScanID == nil || asset.ownerScanID == id,
               !all.contains(where: { $0.key != id && $0.value.savedImageAssetID == asset.id }),
               let data = images.imageData(for: asset.id),
               Self.isValidJPEG(data, width: asset.pixelWidth, height: asset.pixelHeight) {
                preview = data
            }
            if preview == nil, let thumbnail = scan.thumbnailData {
                preview = Self.canonicalJPEG(from: thumbnail)?.data
            }
            return SavedScanShareSource(authoritativeScore: scan.score,
                title: scan.customTitle, occasion: scan.occasion?.rawValue, imagePreview: preview)
        }
        return SavedScanShareReadResult(savedRecordCount: all.count, sources: sources)
    }

    /// Enumerates only existing decoded saved-scan facts. This method never
    /// reads image assets, decodes persistent metadata, writes defaults, or
    /// migrates/backfills legacy records.
    func enumerateSavedScanStylistFacts() throws -> [SavedScanStylistFacts] {
        let savedHistory = try history()
        return savedHistory
            .keys
            .sorted()
            .compactMap { key in
                guard let scan = savedHistory[key] else { return nil }
                let storedInputs = scan.deterministicInputs
                let confidentPalette = storedInputs?.colorPaletteConfidence == .confident
                    ? storedInputs?.colorPalette
                    : nil
                return SavedScanStylistFacts(
                    localRecordKey: key,
                    scanDate: scan.firstScannedAt,
                    selectedOccasion: scan.occasion?.rawValue,
                    score: (0...100).contains(scan.score) ? scan.score : nil,
                    scoreBand: nil,
                    detectedStyle: storedInputs?.styleCategory,
                    palette: confidentPalette
                )
            }
    }
    func readSavedScan(id: String) throws -> SavedScanSyncDTO { guard let dto = try makeSyncRecord(id: id) else { throw SavedScanPersistenceError.missing }; return dto }
    func currentVersion(scanID: String) throws -> String { try readSavedScan(id: scanID).version }

    func makeSyncRecord(id: String) throws -> SavedScanSyncDTO? {
        guard let scan = try history()[id] else { return nil }
        guard (0...100).contains(scan.score), let analysis = scan.analysis, analysis.score == scan.score else { throw SavedScanPersistenceError.invalidPayload }
        let metadata = try Self.canonicalMetadata(for: scan)
        let imageData = images.imageData(for: scan.savedImageAssetID)
        let checksum = imageData.map(Self.digest)
        return SavedScanSyncDTO(id: id, authoritativeScore: scan.score, savedAt: scan.firstScannedAt, occasion: scan.occasion?.rawValue, title: scan.customTitle, colors: analysis.colorPalette, persistentAnalysisMetadata: metadata, imageAssetID: scan.savedImageAssetID, imageSHA256: checksum, imageByteCount: imageData.map { Int64($0.count) }, version: Self.digest(metadata))
    }

    /// Validates the entire record before inserting only its stable ID. Exact
    /// replay is a no-op. Divergent versions deliberately fail closed instead
    /// of applying a whole-history last-write-wins policy; a future conflict UI
    /// can make an explicit, customer-visible resolution decision.
    func applyRemoteSavedScan(_ dto: SavedScanSyncDTO) throws {
        let decoded = try validatedRemoteScan(dto)
        let tombstones = try tombstones()
        if tombstones[dto.id] != nil {
            throw SavedScanPersistenceError.stale
        }

        var all = try history()
        if let local = try makeSyncRecord(id: dto.id) {
            if local.version == dto.version { return }
            throw SavedScanPersistenceError.conflict
        }
        all[dto.id] = decoded
        try save(all)
    }

    /// Commits a received saved scan only after its metadata and the exact
    /// associated image have both validated. The image bytes are stored before
    /// the history record becomes visible; if the history write fails the
    /// unreferenced image is removed again. This is the inbound atomicity
    /// boundary used by CloudKit reconciliation.
    func applyRemoteSavedScanAtomically(
        _ dto: SavedScanSyncDTO,
        asset: SavedScanImageAsset,
        data: Data,
        sha256: String,
        byteCount: Int64
    ) throws {
        let decoded = try validatedRemoteScan(dto)
        guard let metadataAsset = decoded.savedImageAsset,
              metadataAsset.id == asset.id,
              metadataAsset.pixelWidth == asset.pixelWidth,
              metadataAsset.pixelHeight == asset.pixelHeight,
              metadataAsset.formatVersion == asset.formatVersion,
              metadataAsset.ownerScanID == nil || metadataAsset.ownerScanID == dto.id,
              asset.ownerScanID == nil || asset.ownerScanID == dto.id,
              dto.imageAssetID == asset.id,
              dto.imageSHA256 == sha256,
              dto.imageByteCount == byteCount,
              Int64(data.count) == byteCount,
              Self.digest(data) == sha256,
              Self.isValidJPEG(data, width: asset.pixelWidth, height: asset.pixelHeight) else {
            throw SavedScanPersistenceError.imageMismatch
        }

        guard (try tombstones())[dto.id] == nil else { throw SavedScanPersistenceError.stale }
        var all = try history()
        if let local = try makeSyncRecord(id: dto.id) {
            guard local.version == dto.version else { throw SavedScanPersistenceError.conflict }
            // Exact replay may repair a previously interrupted image write, but
            // it never alters the visible record or substitutes another asset.
            guard images.storeValidatedJPEG(data, for: asset) else {
                throw SavedScanPersistenceError.imageMismatch
            }
            return
        }

        guard images.storeValidatedJPEG(data, for: asset) else {
            throw SavedScanPersistenceError.imageMismatch
        }
        all[dto.id] = decoded
        do {
            try save(all)
        } catch {
            images.removeIfUnreferenced(
                assetID: asset.id,
                referencedAssetIDs: Set((try? history().values.compactMap(\.savedImageAssetID)) ?? [])
            )
            throw error
        }
    }

    func applyRemoteTombstone(id: String, version: String) throws {
        guard !id.isEmpty, !version.isEmpty else { throw SavedScanPersistenceError.invalidPayload }
        var tombstones = try tombstones()
        if let existing = tombstones[id] {
            guard existing == version else { throw SavedScanPersistenceError.stale }
            return
        }

        var all = try history()
        if let local = try makeSyncRecord(id: id), local.version != version {
            // A deletion from a replica that does not name the exact object
            // version must not delete a newer or divergent local scan.
            throw SavedScanPersistenceError.stale
        }
        all.removeValue(forKey: id)
        tombstones[id] = version
        try save(all)
        try saveTombstones(tombstones)
    }

    func readImageAsset(scanID: String) throws -> (assetID: String, data: Data, sha256: String, byteCount: Int64)? {
        let dto = try readSavedScan(id: scanID)
        guard let assetID = dto.imageAssetID, let data = images.imageData(for: assetID) else { return nil }
        return (assetID, data, Self.digest(data), Int64(data.count))
    }

    /// The owner-only CloudKit path additionally needs image dimensions to
    /// construct a typed `SavedScanImageAsset`. A legacy scan may retain only
    /// its own embedded thumbnail. In that case, convert only that exact image
    /// to canonical JPEG bytes, bind it to the same stable scan ID, and retain
    /// every historical score/timestamp/analysis fact unchanged.
    func readValidatedImageAsset(scanID: String) throws -> (asset: SavedScanImageAsset, data: Data, sha256: String, byteCount: Int64)? {
        var all = try history()
        guard var scan = all[scanID] else { throw SavedScanPersistenceError.missing }

        if let existing = scan.savedImageAsset {
            let isReferencedByAnotherScan = all.contains {
                $0.key != scanID && $0.value.savedImageAssetID == existing.id
            }
            guard !isReferencedByAnotherScan,
                  existing.ownerScanID == nil || existing.ownerScanID == scanID,
                  let data = images.imageData(for: existing.id),
                  let recovered = Self.assetMetadata(id: existing.id, data: data),
                  recovered.pixelWidth == existing.pixelWidth,
                  recovered.pixelHeight == existing.pixelHeight,
                  recovered.formatVersion == existing.formatVersion else {
                throw SavedScanPersistenceError.imageMismatch
            }
            return (existing, data, Self.digest(data), Int64(data.count))
        }

        guard let thumbnail = scan.thumbnailData,
              let canonical = Self.canonicalJPEG(from: thumbnail) else {
            throw SavedScanPersistenceError.imageMismatch
        }
        guard let migrated = images.storeJPEG(
            canonical.data,
            pixelWidth: canonical.pixelWidth,
            pixelHeight: canonical.pixelHeight,
            ownerScanID: scanID
        ),
        let stored = images.imageData(for: migrated.id),
        stored == canonical.data else {
            throw SavedScanPersistenceError.imageMismatch
        }

        scan.savedImageAsset = migrated
        all[scanID] = scan
        do {
            try save(all)
        } catch {
            images.removeIfUnreferenced(
                assetID: migrated.id,
                referencedAssetIDs: Set((try? history().values.compactMap(\.savedImageAssetID)) ?? [])
            )
            throw error
        }
        return (migrated, stored, Self.digest(stored), Int64(stored.count))
    }

    /// Applies bytes only to the exact image asset named by the scan record.
    /// This cannot substitute another scan's image, and no image bytes are
    /// accepted until checksum and length match the record metadata.
    func applyRemoteImage(
        for record: SavedScanSyncDTO,
        asset: SavedScanImageAsset,
        data: Data,
        sha256: String,
        byteCount: Int64
    ) throws {
        _ = try readSavedScan(id: record.id)
        guard record.imageAssetID == asset.id,
              record.imageSHA256 == sha256,
              record.imageByteCount == byteCount,
              Int64(data.count) == byteCount,
              Self.digest(data) == sha256,
              images.storeValidatedJPEG(data, for: asset) else {
            throw SavedScanPersistenceError.imageMismatch
        }
    }

    private func history() throws -> [String: StoredOutfitScan] {
        guard let data = defaults.data(forKey: Self.historyKey), !data.isEmpty else { return [:] }
        guard let decoded = try? JSONDecoder().decode([String: StoredOutfitScan].self, from: data) else { throw SavedScanPersistenceError.malformedHistory }
        return decoded
    }
    private func save(_ history: [String: StoredOutfitScan]) throws { defaults.set(try JSONEncoder().encode(history), forKey: Self.historyKey) }
    private func tombstones() throws -> [String: String] {
        guard let data = defaults.data(forKey: Self.tombstoneKey), !data.isEmpty else { return [:] }
        guard let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            throw SavedScanPersistenceError.malformedTombstones
        }
        return decoded
    }
    private func saveTombstones(_ tombstones: [String: String]) throws {
        defaults.set(try JSONEncoder().encode(tombstones), forKey: Self.tombstoneKey)
    }
    private func validatedRemoteScan(_ dto: SavedScanSyncDTO) throws -> StoredOutfitScan {
        guard !dto.id.isEmpty, (0...100).contains(dto.authoritativeScore), dto.savedAt <= Date(), !dto.persistentAnalysisMetadata.isEmpty, dto.version == Self.digest(dto.persistentAnalysisMetadata) else { throw SavedScanPersistenceError.invalidPayload }
        let decoded = try JSONDecoder().decode(StoredOutfitScan.self, from: dto.persistentAnalysisMetadata)
        guard try Self.canonicalMetadata(for: decoded) == dto.persistentAnalysisMetadata,
              decoded.score == dto.authoritativeScore,
              decoded.firstScannedAt == dto.savedAt,
              decoded.analysis?.score == dto.authoritativeScore,
              decoded.occasion?.rawValue == dto.occasion,
              decoded.customTitle == dto.title,
              decoded.analysis?.colorPalette == dto.colors else {
            throw SavedScanPersistenceError.invalidPayload
        }
        return decoded
    }
    private static func canonicalMetadata(for scan: StoredOutfitScan) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(scan)
    }

    /// Legacy saved scans retain an opaque image ID rather than dimensions.
    /// Recover the dimensions from the exact JPEG bytes, or fail closed rather
    /// than inventing metadata for a CloudKit asset.
    private static func assetMetadata(id: String, data: Data) -> SavedScanImageAsset? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else {
            return nil
        }
        return SavedScanImageAsset(
            id: id,
            pixelWidth: width,
            pixelHeight: height,
            formatVersion: SavedScanImageAssetStore.currentFormatVersion
        )
    }

    private static func canonicalJPEG(from data: Data) -> (data: Data, pixelWidth: Int, pixelHeight: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else {
            return nil
        }

        let destinationData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            destinationData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImageFromSource(
            destination,
            source,
            0,
            [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        let canonical = destinationData as Data
        guard assetMetadata(id: "migration-validation", data: canonical) != nil else { return nil }
        return (canonical, width, height)
    }
    private static func isValidJPEG(_ data: Data, width: Int, height: Int) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let type = CGImageSourceGetType(source),
              let uniformType = UTType(type as String),
              uniformType.conforms(to: .jpeg),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              properties[kCGImagePropertyPixelWidth] as? Int == width,
              properties[kCGImagePropertyPixelHeight] as? Int == height else {
            return false
        }
        return true
    }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
