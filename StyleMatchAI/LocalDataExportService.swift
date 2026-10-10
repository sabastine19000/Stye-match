import Foundation

/// Produces a user-initiated, local-only copy of the active StyleMatch profile.
/// It intentionally excludes credentials, device identifiers, server-held account
/// data, diagnostics, caches, and shared-link management tokens.
struct LocalDataExportService {
    static let schemaVersion = 1
    private static let maximumDestinationAttempts = 32

    /// The identifier is intentionally independent of any customer data. It is
    /// injectable so collision handling can be tested deterministically.
    private let identifierGenerator: () -> String

    init(identifierGenerator: @escaping () -> String = { UUID().uuidString }) {
        self.identifierGenerator = identifierGenerator
    }

    enum ExportFormat: String, CaseIterable, Identifiable {
        case zip = "ZIP"
        case json = "JSON"

        var id: String { rawValue }
        var fileExtension: String { rawValue.lowercased() }
    }

    struct Result: Equatable {
        let jsonURL: URL
        let zipURL: URL
        let createdAt: Date
        let jsonByteCount: Int

        func url(for format: ExportFormat) -> URL {
            format == .zip ? zipURL : jsonURL
        }
    }

    enum ExportError: LocalizedError, Equatable {
        case encodingFailed
        case archiveFailed
        case destinationUnavailable

        var errorDescription: String? {
            switch self {
            case .encodingFailed:
                return "KigoStylist could not prepare your local data export."
            case .archiveFailed:
                return "KigoStylist could not package your local data export."
            case .destinationUnavailable:
                return "KigoStylist could not reserve a safe location for your local data export."
            }
        }
    }

    private struct Manifest: Codable, Equatable {
        let schemaVersion: Int
        let generatedAt: Date
        let scope: String
        let includedCategories: [String]
        let excludedCategories: [String]
    }

    private struct SharedLinkSummary: Codable, Equatable {
        let url: URL
        let createdAt: Date
        let expiresAt: Date
        let revokedAt: Date?
    }

    private struct ShoppingState: Codable, Equatable {
        let recentlyViewedProductIDs: [String]
        let savedFavoriteProductIDs: [String]
        let wishlistProductIDs: [String]
        let cartProductIDs: [String]
        let shoppingCardProductIDs: [String]
        let preferredRetailerIDs: [String]
    }

    private struct Payload: Codable {
        let manifest: Manifest
        let activeLocalData: [String: JSONValue]
        let profile: StylistProfile
        let outfitMemories: [OutfitMemory]
        let conversations: [ChatConversation]
        let shopping: ShoppingState
        let sharedLinks: [SharedLinkSummary]
        let aiMemories: [AIPersistentMemory]
    }

    /// A small Codable representation that preserves JSON-compatible local
    /// preferences without exporting unknown UserDefaults keys.
    private indirect enum JSONValue: Codable {
        case string(String)
        case number(Double)
        case bool(Bool)
        case array([JSONValue])
        case object([String: JSONValue])
        case null

        init?(propertyListValue: Any) {
            switch propertyListValue {
            case let value as String:
                self = .string(value)
            case let value as Bool:
                self = .bool(value)
            case let value as NSNumber:
                self = .number(value.doubleValue)
            case let value as [Any]:
                self = .array(value.compactMap(JSONValue.init(propertyListValue:)))
            case let value as [String: Any]:
                var object: [String: JSONValue] = [:]
                for (key, item) in value {
                    guard let converted = JSONValue(propertyListValue: item) else { return nil }
                    object[key] = converted
                }
                self = .object(object)
            case let value as Data:
                guard let jsonObject = try? JSONSerialization.jsonObject(with: value),
                      let converted = JSONValue(propertyListValue: jsonObject) else {
                    return nil
                }
                self = converted
            default:
                return nil
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() { self = .null }
            else if let value = try? container.decode(Bool.self) { self = .bool(value) }
            else if let value = try? container.decode(Double.self) { self = .number(value) }
            else if let value = try? container.decode(String.self) { self = .string(value) }
            else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
            else { self = .object(try container.decode([String: JSONValue].self)) }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let value): try container.encode(value)
            case .number(let value): try container.encode(value)
            case .bool(let value): try container.encode(value)
            case .array(let value): try container.encode(value)
            case .object(let value): try container.encode(value)
            case .null: try container.encodeNil()
            }
        }
    }

    func prepare(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        now: Date = Date(),
        destinationDirectory: URL? = nil
    ) throws -> Result {
        let activeUserID = AccountScopedStorage.activePresentationUserID(defaults: defaults)
        let profile = ProfileStore(defaults: defaults, userId: activeUserID).currentProfile
        let memories = OutfitMemoryStore(defaults: defaults, userId: activeUserID).memories
        let conversations = ChatConversationStore(userID: activeUserID).conversations
        let shoppingStore = ShoppingLocalStore(defaults: defaults, userID: activeUserID)
        let sharedLinks = ShareableScoreCardLocalStore(defaults: defaults, userID: activeUserID).cards.map {
            SharedLinkSummary(url: $0.url, createdAt: $0.createdAt, expiresAt: $0.expiresAt, revokedAt: $0.revokedAt)
        }
        let aiMemories = AIPersistentMemoryStore(defaults: defaults, userID: activeUserID).exportRecords()

        var localData: [String: JSONValue] = [:]
        for key in AccountScopedStorage.userDataKeys {
            guard key != "openAIModel", let value = defaults.object(forKey: key),
                  let encoded = JSONValue(propertyListValue: value) else { continue }
            localData[key] = encoded
        }

        let payload = Payload(
            manifest: Manifest(
                schemaVersion: Self.schemaVersion,
                generatedAt: now,
                scope: "local-device-only",
                includedCategories: [
                    "active profile and preferences",
                    "saved scans and closet data retained on this device",
                    "local stylist memory and conversations",
                    "explicit AI Memory preferences and corrections",
                    "local shopping preferences and lists",
                    "shared-link status and expiration metadata"
                ],
                excludedCategories: [
                    "server-held account data and cloud-synced records",
                    "account sessions, Apple identifiers, and email addresses",
                    "API keys, passwords, Keychain values, and credentials",
                    "device identifiers, diagnostics, caches, and logs",
                    "shared-link management tokens"
                ]
            ),
            activeLocalData: localData,
            profile: profile,
            outfitMemories: memories,
            conversations: conversations,
            shopping: ShoppingState(
                recentlyViewedProductIDs: shoppingStore.recentlyViewedProductIDs,
                savedFavoriteProductIDs: shoppingStore.savedFavorites,
                wishlistProductIDs: shoppingStore.wishlistProductIDs,
                cartProductIDs: shoppingStore.cartProductIDs,
                shoppingCardProductIDs: shoppingStore.shoppingCardProductIDs,
                preferredRetailerIDs: shoppingStore.preferredRetailerIDs
            ),
            sharedLinks: sharedLinks,
            aiMemories: aiMemories
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload) else { throw ExportError.encodingFailed }

        let baseDirectory = destinationDirectory ?? fileManager.temporaryDirectory
        let destination = try reserveDestination(in: baseDirectory, now: now, fileManager: fileManager)
        let root = destination.root
        let jsonURL = root.appendingPathComponent(destination.jsonFilename)
        let zipURL = root.appendingPathComponent(destination.zipFilename)
        do {
            try data.write(to: jsonURL, options: [.atomic])
            try StoredZIPArchive.write(entryNamed: jsonURL.lastPathComponent, data: data, to: zipURL)
            try StyleMatchLocalDataProtection.protect(
                root,
                backupPolicy: .excludeReconstructableOrTransientData,
                fileManager: fileManager
            )
            try StyleMatchLocalDataProtection.protect(
                jsonURL,
                backupPolicy: .excludeReconstructableOrTransientData,
                fileManager: fileManager
            )
            try StyleMatchLocalDataProtection.protect(
                zipURL,
                backupPolicy: .excludeReconstructableOrTransientData,
                fileManager: fileManager
            )
        } catch {
            try? fileManager.removeItem(at: root)
            throw ExportError.archiveFailed
        }

        return Result(jsonURL: jsonURL, zipURL: zipURL, createdAt: now, jsonByteCount: data.count)
    }

    static func removeTemporaryExport(at result: Result, fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: result.jsonURL.deletingLastPathComponent())
    }

    private struct ReservedDestination {
        let root: URL
        let jsonFilename: String
        let zipFilename: String
    }

    private func reserveDestination(in baseDirectory: URL, now: Date, fileManager: FileManager) throws -> ReservedDestination {
        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

        for _ in 0..<Self.maximumDestinationAttempts {
            let identifier = identifierGenerator()
            guard Self.isSafeIdentifier(identifier) else { continue }

            let root = baseDirectory.appendingPathComponent("StyleMatchLocalExport-\(identifier)", isDirectory: true)
            do {
                try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
                let timestamp = Self.fileDate(now)
                return ReservedDestination(
                    root: root,
                    jsonFilename: Self.filename(timestamp: timestamp, identifier: identifier, format: .json),
                    zipFilename: Self.filename(timestamp: timestamp, identifier: identifier, format: .zip)
                )
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError {
                continue
            }
        }

        throw ExportError.destinationUnavailable
    }

    private static func filename(timestamp: String, identifier: String, format: ExportFormat) -> String {
        "StyleMatch-local-export-\(timestamp)-\(identifier).\(format.fileExtension)"
    }

    private static func isSafeIdentifier(_ identifier: String) -> Bool {
        guard !identifier.isEmpty, identifier.count <= 64 else { return false }
        return identifier.unicodeScalars.allSatisfy {
            ($0.value >= 48 && $0.value <= 57) ||
            ($0.value >= 65 && $0.value <= 90) ||
            ($0.value >= 97 && $0.value <= 122) ||
            $0.value == 45
        }
    }

    private static func fileDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss.SSS'Z'"
        return formatter.string(from: date)
    }
}

/// A minimal standards-compliant ZIP writer for one JSON document. Stored (not
/// compressed) entries are deliberately used so the archive can be generated
/// without shelling out or depending on a third-party archive library.
private enum StoredZIPArchive {
    static func write(entryNamed name: String, data: Data, to url: URL) throws {
        let nameData = Data(name.utf8)
        let crc = crc32(data)
        var archive = Data()

        archive.appendLE(UInt32(0x04034b50))
        archive.appendLE(UInt16(20))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(0))
        archive.appendLE(crc)
        archive.appendLE(UInt32(data.count))
        archive.appendLE(UInt32(data.count))
        archive.appendLE(UInt16(nameData.count))
        archive.appendLE(UInt16(0))
        archive.append(nameData)
        archive.append(data)

        let centralDirectoryOffset = UInt32(archive.count)
        archive.appendLE(UInt32(0x02014b50))
        archive.appendLE(UInt16(20))
        archive.appendLE(UInt16(20))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(0))
        archive.appendLE(crc)
        archive.appendLE(UInt32(data.count))
        archive.appendLE(UInt32(data.count))
        archive.appendLE(UInt16(nameData.count))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt32(0))
        archive.appendLE(UInt32(0))
        archive.append(nameData)

        let centralDirectorySize = UInt32(archive.count) - centralDirectoryOffset
        archive.appendLE(UInt32(0x06054b50))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(1))
        archive.appendLE(UInt16(1))
        archive.appendLE(centralDirectorySize)
        archive.appendLE(centralDirectoryOffset)
        archive.appendLE(UInt16(0))
        try archive.write(to: url, options: [.atomic])
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xedb88320 : crc >> 1
            }
        }
        return crc ^ 0xffffffff
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        append(Data(bytes: &littleEndian, count: MemoryLayout<T>.size))
    }
}
