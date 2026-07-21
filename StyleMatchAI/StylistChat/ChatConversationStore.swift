import Foundation
import Combine

final class ChatConversationStore: ObservableObject {
    @Published private(set) var conversations: [ChatConversation]

    private let fileURL: URL
    private let backupURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let lock = NSRecursiveLock()
    private let maxConversations = 10

    init(fileURL: URL? = nil, userID: String? = nil) {
        let resolvedURL = fileURL ?? Self.defaultFileURL(userID: userID)
        self.fileURL = resolvedURL
        self.backupURL = resolvedURL.deletingLastPathComponent().appendingPathComponent("\(resolvedURL.lastPathComponent).bak")
        conversations = Self.load(fileURL: resolvedURL, backupURL: backupURL)
    }

    func save(_ conversation: ChatConversation) {
        lock.lock()
        defer { lock.unlock() }

        var updated = conversation
        updated.updatedAt = Date()
        conversations.removeAll { $0.id == updated.id }
        conversations.insert(updated, at: 0)
        conversations.sort { $0.updatedAt > $1.updatedAt }
        conversations = Array(conversations.prefix(maxConversations))
        persist()
    }

    func deleteAll() {
        lock.lock()
        defer { lock.unlock() }

        conversations = []
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: backupURL)
    }

    static func deleteAll(for userID: String) {
        let fileURL = defaultFileURL(userID: userID)
        let backupURL = fileURL.deletingLastPathComponent().appendingPathComponent("\(fileURL.lastPathComponent).bak")
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: backupURL)
    }

    private func persist() {
        do {
            let data = try encoder.encode(conversations)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.copyItem(at: fileURL, to: backupURL)
            }
            try atomicWrite(data, to: fileURL)
        } catch {}
    }

    private func atomicWrite(_ data: Data, to url: URL) throws {
        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: tempURL, options: [.atomic])
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
        } else {
            try FileManager.default.moveItem(at: tempURL, to: url)
        }
    }

    private static func load(fileURL: URL, backupURL: URL) -> [ChatConversation] {
        if let conversations = decode(fileURL) {
            return Array(conversations.sorted { $0.updatedAt > $1.updatedAt }.prefix(10))
        }
        if let conversations = decode(backupURL) {
            return Array(conversations.sorted { $0.updatedAt > $1.updatedAt }.prefix(10))
        }
        return []
    }

    private static func decode(_ url: URL) -> [ChatConversation]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([ChatConversation].self, from: data)
    }

    private static func defaultFileURL(userID: String? = nil) -> URL {
        let userID = userID ?? PersonalStylistStorage.activeUserID()
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return directory
            .appendingPathComponent("StyleMatchAI", isDirectory: true)
            .appendingPathComponent("StylistChat-\(PersonalStylistStorage.normalizedUserID(userID)).json")
    }
}
