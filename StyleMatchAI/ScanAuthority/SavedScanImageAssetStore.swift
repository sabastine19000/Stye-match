import Foundation

/// Stores accepted scan-image bytes outside the persisted scan-history JSON.
/// The history retains only this opaque identifier; it never stores an absolute path.
struct SavedScanImageAsset: Codable, Equatable {
    let id: String
    let pixelWidth: Int
    let pixelHeight: Int
    let formatVersion: Int
    /// New assets may carry their stable saved-scan owner. Older assets omit
    /// this additive field and retain their relationship through the history
    /// record that names them.
    let ownerScanID: String?

    init(
        id: String,
        pixelWidth: Int,
        pixelHeight: Int,
        formatVersion: Int,
        ownerScanID: String? = nil
    ) {
        self.id = id
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.formatVersion = formatVersion
        self.ownerScanID = ownerScanID
    }
}

final class SavedScanImageAssetStore {
    static let currentFormatVersion = 1

    private let rootDirectory: URL
    private let legacyRootDirectory: URL
    private let fileManager: FileManager

    init(rootDirectory: URL? = nil, userID: String? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let storageRoot = rootDirectory ?? fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent("StyleMatchPro", isDirectory: true)
        .appendingPathComponent("SavedScanImages", isDirectory: true)

        legacyRootDirectory = storageRoot
        self.rootDirectory = storageRoot.appendingPathComponent(
            Self.accountDirectoryName(for: userID ?? PersonalStylistStorage.activeUserID()),
            isDirectory: true
        )
    }

    @discardableResult
    func storeJPEG(
        _ data: Data,
        pixelWidth: Int,
        pixelHeight: Int,
        ownerScanID: String? = nil
    ) -> SavedScanImageAsset? {
        guard !data.isEmpty, pixelWidth > 0, pixelHeight > 0 else { return nil }
        let asset = SavedScanImageAsset(
            id: UUID().uuidString.lowercased(),
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            formatVersion: Self.currentFormatVersion,
            ownerScanID: ownerScanID
        )
        do {
            try ensureProtectedDirectory()
            try writeProtected(data, to: url(for: asset.id))
            return asset
        } catch {
            return nil
        }
    }

    func imageData(for assetID: String?) -> Data? {
        guard let assetID, isOpaqueAssetID(assetID) else { return nil }
        return try? Data(contentsOf: url(for: assetID), options: .mappedIfSafe)
    }

    /// Stores bytes supplied by the saved-scan authority only after that
    /// authority has verified their owner, checksum and byte count. Keeping the
    /// caller-supplied opaque ID preserves the scan-to-image relationship across
    /// devices without introducing a second image store.
    @discardableResult
    func storeValidatedJPEG(_ data: Data, for asset: SavedScanImageAsset) -> Bool {
        guard !data.isEmpty,
              asset.pixelWidth > 0,
              asset.pixelHeight > 0,
              asset.formatVersion == Self.currentFormatVersion,
              isOpaqueAssetID(asset.id) else {
            return false
        }

        do {
            try ensureProtectedDirectory()
            try writeProtected(data, to: url(for: asset.id))
            return true
        } catch {
            return false
        }
    }

    func removeIfUnreferenced(assetID: String?, referencedAssetIDs: Set<String>) {
        guard let assetID, !referencedAssetIDs.contains(assetID), isOpaqueAssetID(assetID) else { return }
        try? fileManager.removeItem(at: url(for: assetID))
    }

    /// Moves only the active account's referenced legacy assets into its
    /// account-scoped directory. The migration is idempotent and does not
    /// copy images into another account's namespace.
    func migrateLegacyAssets(named assetIDs: Set<String>) {
        assetIDs.forEach { assetID in
            guard isOpaqueAssetID(assetID) else { return }
            migrateLegacyAssetIfNeeded(assetID: assetID)
        }
    }

    func removeAllAccountAssets() {
        try? fileManager.removeItem(at: rootDirectory)
    }

    private func url(for assetID: String) -> URL {
        rootDirectory.appendingPathComponent(assetID).appendingPathExtension("jpg")
    }

    private func legacyURL(for assetID: String) -> URL? {
        legacyRootDirectory.appendingPathComponent(assetID).appendingPathExtension("jpg")
    }

    private func migrateLegacyAssetIfNeeded(assetID: String) {
        let destination = url(for: assetID)
        guard !fileManager.fileExists(atPath: destination.path),
              let legacy = legacyURL(for: assetID),
              fileManager.fileExists(atPath: legacy.path) else {
            return
        }
        do {
            try ensureProtectedDirectory()
            try fileManager.moveItem(at: legacy, to: destination)
            try StyleMatchLocalDataProtection.protect(
                destination,
                backupPolicy: .includeUserCreatedData,
                fileManager: fileManager
            )
        } catch {
            // A failed migration leaves the existing legacy asset intact so a
            // later foreground attempt can recover it without data loss.
        }
    }

    private func ensureProtectedDirectory() throws {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try StyleMatchLocalDataProtection.protect(
            rootDirectory,
            backupPolicy: .includeUserCreatedData,
            fileManager: fileManager
        )
    }

    private func writeProtected(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try StyleMatchLocalDataProtection.protect(
            url,
            backupPolicy: .includeUserCreatedData,
            fileManager: fileManager
        )
    }

    private func isOpaqueAssetID(_ value: String) -> Bool {
        UUID(uuidString: value) != nil
    }

    private static func accountDirectoryName(for userID: String) -> String {
        PersonalStylistStorage.protectedStorageIdentifier(for: userID)
    }
}
