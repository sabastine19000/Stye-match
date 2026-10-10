import Foundation

enum PersonalStylistSnapshotStore {
    private static let fm = FileManager.default
    private static let lock = NSRecursiveLock()

    static func loadData(store: String, userID: String, rootDirectory: URL? = nil) -> Data? {
        lock.lock()
        defer { lock.unlock() }

        let main = mainURL(store: store, userID: userID, rootDirectory: rootDirectory)
        if let data = try? Data(contentsOf: main) {
            return data
        }
        return latestSnapshotData(store: store, userID: userID, rootDirectory: rootDirectory)
    }

    @discardableResult
    static func saveData(_ data: Data, store: String, userID: String, rootDirectory: URL? = nil) -> Result<Void, Error> {
        lock.lock()
        defer { lock.unlock() }

        let main = mainURL(store: store, userID: userID, rootDirectory: rootDirectory)
        if let existing = try? Data(contentsOf: main) {
            do {
                try rotateSnapshots(store: store, userID: userID, rootDirectory: rootDirectory)
                try writeProtected(existing, to: snapshotURL(store: store, userID: userID, index: 1, rootDirectory: rootDirectory))
            } catch {
                return .failure(error)
            }
        }

        do {
            try ensureDirectory(rootDirectory: rootDirectory)
            try writeProtected(data, to: main)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    /// Replaces the current document and every recoverable snapshot with the
    /// same sanitized bytes. This is used only for user-directed deletion:
    /// retaining an older recovery copy would otherwise make a forgotten value
    /// recoverable. Snapshots are written before the main document, so a
    /// failed write leaves the existing main document authoritative.
    @discardableResult
    static func replaceDataAndRecoverySnapshots(
        _ data: Data,
        store: String,
        userID: String,
        rootDirectory: URL? = nil
    ) -> Result<Void, Error> {
        lock.lock()
        defer { lock.unlock() }

        do {
            try ensureDirectory(rootDirectory: rootDirectory)
            for index in 1...3 {
                try writeProtected(data, to: snapshotURL(store: store, userID: userID, index: index, rootDirectory: rootDirectory))
            }
            try writeProtected(data, to: mainURL(store: store, userID: userID, rootDirectory: rootDirectory))
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    static func restoreFromSnapshot(store: String, userID: String, rootDirectory: URL? = nil) -> Data? {
        restoreFromSnapshot(store: store, userID: userID, rootDirectory: rootDirectory, validator: { _ in true })
    }

    static func restoreFromSnapshot(store: String, userID: String, rootDirectory: URL? = nil, validator: (Data) -> Bool) -> Data? {
        lock.lock()
        defer { lock.unlock() }

        for index in 1...3 {
            guard let data = try? Data(contentsOf: snapshotURL(store: store, userID: userID, index: index, rootDirectory: rootDirectory)),
                  validator(data) else {
                continue
            }

            do {
                try ensureDirectory(rootDirectory: rootDirectory)
                try writeProtected(data, to: mainURL(store: store, userID: userID, rootDirectory: rootDirectory))
            } catch {}
            return data
        }

        return nil
    }

    static func deleteData(store: String, userID: String, rootDirectory: URL? = nil) {
        lock.lock()
        defer { lock.unlock() }

        let urls = [mainURL(store: store, userID: userID, rootDirectory: rootDirectory)] + (1...3).map { snapshotURL(store: store, userID: userID, index: $0, rootDirectory: rootDirectory) }
        for url in urls {
            do {
                try fm.removeItem(at: url)
            } catch {
                guard fm.fileExists(atPath: url.path) else { continue }
            }
        }
    }

    static func snapshotCount(store: String, userID: String, rootDirectory: URL? = nil) -> Int {
        lock.lock()
        defer { lock.unlock() }

        return (1...3).filter { fm.fileExists(atPath: snapshotURL(store: store, userID: userID, index: $0, rootDirectory: rootDirectory).path) }.count
    }

    static func replaceMainDataForTesting(_ data: Data, store: String, userID: String, rootDirectory: URL? = nil) throws {
        lock.lock()
        defer { lock.unlock() }

        try ensureDirectory(rootDirectory: rootDirectory)
        try writeProtected(data, to: mainURL(store: store, userID: userID, rootDirectory: rootDirectory))
    }

    private static func latestSnapshotData(store: String, userID: String, rootDirectory: URL?) -> Data? {
        for index in 1...3 {
            if let data = try? Data(contentsOf: snapshotURL(store: store, userID: userID, index: index, rootDirectory: rootDirectory)) {
                return data
            }
        }
        return nil
    }

    private static func rotateSnapshots(store: String, userID: String, rootDirectory: URL?) throws {
        try ensureDirectory(rootDirectory: rootDirectory)
        let third = snapshotURL(store: store, userID: userID, index: 3, rootDirectory: rootDirectory)
        try? fm.removeItem(at: third)
        for index in stride(from: 2, through: 1, by: -1) {
            let source = snapshotURL(store: store, userID: userID, index: index, rootDirectory: rootDirectory)
            guard fm.fileExists(atPath: source.path) else { continue }
            let destination = snapshotURL(store: store, userID: userID, index: index + 1, rootDirectory: rootDirectory)
            try? fm.removeItem(at: destination)
            try fm.moveItem(at: source, to: destination)
        }
    }

    private static func mainURL(store: String, userID: String, rootDirectory: URL?) -> URL {
        directoryURL(rootDirectory: rootDirectory)
            .appendingPathComponent("\(store)_\(PersonalStylistStorage.normalizedUserID(userID)).json")
    }

    private static func snapshotURL(store: String, userID: String, index: Int, rootDirectory: URL?) -> URL {
        directoryURL(rootDirectory: rootDirectory)
            .appendingPathComponent("\(store)_\(PersonalStylistStorage.normalizedUserID(userID)).backup\(index).json")
    }

    private static func directoryURL() -> URL {
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        return base.appendingPathComponent("StyleMatchPro/PersonalStylist", isDirectory: true)
    }

    private static func directoryURL(rootDirectory: URL?) -> URL {
        rootDirectory ?? directoryURL()
    }

    private static func ensureDirectory(rootDirectory: URL?) throws {
        let directory = directoryURL(rootDirectory: rootDirectory)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try StyleMatchLocalDataProtection.protect(
            directory,
            backupPolicy: .includeUserCreatedData,
            fileManager: fm
        )
    }

    private static func writeProtected(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try StyleMatchLocalDataProtection.protect(
            url,
            backupPolicy: .includeUserCreatedData,
            fileManager: fm
        )
    }
}
