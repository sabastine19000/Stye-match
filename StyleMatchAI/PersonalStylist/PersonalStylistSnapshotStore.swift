import Foundation

enum PersonalStylistSnapshotStore {
    private static let fm = FileManager.default
    private static let lock = NSRecursiveLock()

    static func loadData(store: String, userID: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }

        let main = mainURL(store: store, userID: userID)
        if let data = try? Data(contentsOf: main) {
            return data
        }
        return latestSnapshotData(store: store, userID: userID)
    }

    static func saveData(_ data: Data, store: String, userID: String) {
        lock.lock()
        defer { lock.unlock() }

        let main = mainURL(store: store, userID: userID)
        if let existing = try? Data(contentsOf: main) {
            do {
                try rotateSnapshots(store: store, userID: userID)
                try existing.write(to: snapshotURL(store: store, userID: userID, index: 1), options: .atomic)
            } catch {}
        }

        do {
            try ensureDirectory()
            try data.write(to: main, options: .atomic)
        } catch {}
    }

    static func restoreFromSnapshot(store: String, userID: String) -> Data? {
        restoreFromSnapshot(store: store, userID: userID, validator: { _ in true })
    }

    static func restoreFromSnapshot(store: String, userID: String, validator: (Data) -> Bool) -> Data? {
        lock.lock()
        defer { lock.unlock() }

        for index in 1...3 {
            guard let data = try? Data(contentsOf: snapshotURL(store: store, userID: userID, index: index)),
                  validator(data) else {
                continue
            }

            do {
                try ensureDirectory()
                try data.write(to: mainURL(store: store, userID: userID), options: .atomic)
            } catch {}
            return data
        }

        return nil
    }

    static func deleteData(store: String, userID: String) {
        lock.lock()
        defer { lock.unlock() }

        let urls = [mainURL(store: store, userID: userID)] + (1...3).map { snapshotURL(store: store, userID: userID, index: $0) }
        for url in urls {
            do {
                try fm.removeItem(at: url)
            } catch {
                guard fm.fileExists(atPath: url.path) else { continue }
            }
        }
    }

    static func snapshotCount(store: String, userID: String) -> Int {
        lock.lock()
        defer { lock.unlock() }

        return (1...3).filter { fm.fileExists(atPath: snapshotURL(store: store, userID: userID, index: $0).path) }.count
    }

    static func replaceMainDataForTesting(_ data: Data, store: String, userID: String) throws {
        lock.lock()
        defer { lock.unlock() }

        try ensureDirectory()
        try data.write(to: mainURL(store: store, userID: userID), options: .atomic)
    }

    private static func latestSnapshotData(store: String, userID: String) -> Data? {
        for index in 1...3 {
            if let data = try? Data(contentsOf: snapshotURL(store: store, userID: userID, index: index)) {
                return data
            }
        }
        return nil
    }

    private static func rotateSnapshots(store: String, userID: String) throws {
        try ensureDirectory()
        let third = snapshotURL(store: store, userID: userID, index: 3)
        try? fm.removeItem(at: third)
        for index in stride(from: 2, through: 1, by: -1) {
            let source = snapshotURL(store: store, userID: userID, index: index)
            guard fm.fileExists(atPath: source.path) else { continue }
            let destination = snapshotURL(store: store, userID: userID, index: index + 1)
            try? fm.removeItem(at: destination)
            try fm.moveItem(at: source, to: destination)
        }
    }

    private static func mainURL(store: String, userID: String) -> URL {
        directoryURL()
            .appendingPathComponent("\(store)_\(PersonalStylistStorage.normalizedUserID(userID)).json")
    }

    private static func snapshotURL(store: String, userID: String, index: Int) -> URL {
        directoryURL()
            .appendingPathComponent("\(store)_\(PersonalStylistStorage.normalizedUserID(userID)).backup\(index).json")
    }

    private static func directoryURL() -> URL {
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        return base.appendingPathComponent("StyleMatchPro/PersonalStylist", isDirectory: true)
    }

    private static func ensureDirectory() throws {
        try fm.createDirectory(at: directoryURL(), withIntermediateDirectories: true)
    }
}
