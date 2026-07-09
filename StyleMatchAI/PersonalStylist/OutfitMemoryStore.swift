import Combine
import Foundation

final class OutfitMemoryStore: ObservableObject {
    @Published private(set) var memories: [OutfitMemory]

    private let defaults: UserDefaults
    private let userID: String
    private let memoriesKey: String
    private let mutationLock = NSRecursiveLock()

    init(defaults: UserDefaults = .standard, userId: String? = nil) {
        self.defaults = defaults
        PersonalStylistStorage.migrateLegacyKeysIfNeeded(defaults: defaults)
        self.userID = PersonalStylistStorage.normalizedUserID(userId ?? PersonalStylistStorage.activeUserID(defaults: defaults))
        self.memoriesKey = PersonalStylistStorage.scopedKey(PersonalStylistStorage.legacyMemoriesKey, userID: self.userID)
        memories = Self.loadMemories(from: defaults, key: memoriesKey, userID: self.userID)
    }

    func addScan(_ memory: OutfitMemory) {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        var scopedMemory = memory
        scopedMemory.userId = userID
        memories.removeAll { $0.id == scopedMemory.id }
        memories.append(scopedMemory)
        memories.sort { $0.scanDate > $1.scanDate }
        save()
    }

    func addOrMergeScan(_ memory: OutfitMemory) {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        var scopedMemory = memory
        scopedMemory.userId = userID

        if let index = memories.firstIndex(where: { $0.id == scopedMemory.id }) {
            memories[index] = merge(memory: memories[index], with: scopedMemory)
        } else if let index = firstMatchingGarmentRecordIndex(for: scopedMemory) {
            memories[index] = merge(memory: memories[index], with: scopedMemory)
        } else {
            memories.append(scopedMemory)
        }

        memories.sort { $0.scanDate > $1.scanDate }
        save()
    }

    @discardableResult
    func mergeGarmentRecords(_ records: [GarmentRecord], into outfitID: UUID) -> OutfitMemory? {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        guard let index = memories.firstIndex(where: { $0.id == outfitID }) else {
            return nil
        }

        var memory = memories[index]
        memory.garmentRecords = merge(existingRecords: memory.garmentRecords, incomingRecords: records)
        memory.detectedGarments = Array(Set(memory.garmentRecords.map(\.garmentCategory))).sorted()
        memory.colors = Array(Set(memory.garmentRecords.flatMap(\.colors))).sorted()
        memories[index] = memory
        save()
        return memory
    }

    var garmentRecords: [GarmentRecord] {
        memories.flatMap(\.garmentRecords)
    }

    func recordFeedback(
        outfitId: UUID,
        wasWorn: Bool?,
        wasLiked: Bool?,
        wouldWearAgain: Bool?,
        dislikeReason: String? = nil
    ) {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        guard let index = memories.firstIndex(where: { $0.id == outfitId }) else {
            return
        }

        if let wasWorn {
            applyFeedbackFields(
                at: index,
                wasWorn: wasWorn,
                wasLiked: wasLiked,
                dislikeReason: DislikeReason(legacyValue: dislikeReason),
                now: Date(),
                markComplete: wasLiked != false || dislikeReason != nil
            )
        }

        if let wouldWearAgain {
            memories[index].wouldWearAgain = wouldWearAgain
            if wouldWearAgain {
                memories[index].isFavorite = true
            }
        }

        save()
    }

    func updateFeedback(
        for outfitMemoryId: UUID,
        wasWorn: Bool,
        wasLiked: Bool?,
        dislikeReason: String?
    ) {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        guard let index = memories.firstIndex(where: { $0.id == outfitMemoryId }) else {
            return
        }

        let now = Date()
        applyFeedbackFields(
            at: index,
            wasWorn: wasWorn,
            wasLiked: wasLiked,
            dislikeReason: DislikeReason(legacyValue: dislikeReason),
            now: now,
            markComplete: true
        )
        save()
    }

    func recordFeedbackPromptShown(for outfitMemoryId: UUID, now: Date = Date()) {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        guard let index = memories.firstIndex(where: { $0.id == outfitMemoryId }) else {
            return
        }

        memories[index].feedbackPromptCount = max(0, memories[index].feedbackPromptCount) + 1
        save()
    }

    func dismissFeedbackPrompt(for outfitMemoryId: UUID, now: Date = Date()) {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        guard let index = memories.firstIndex(where: { $0.id == outfitMemoryId }) else {
            return
        }

        memories[index].feedbackDismissedAt = now
        save()
    }

    func recordWornAnswer(for outfitMemoryId: UUID, wasWorn: Bool, now: Date = Date()) {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        guard let index = memories.firstIndex(where: { $0.id == outfitMemoryId }) else {
            return
        }

        applyWornAnswer(at: index, wasWorn: wasWorn, now: now)
        if !wasWorn {
            memories[index].wasLiked = nil
            memories[index].wouldWearAgain = nil
            memories[index].dislikeReason = nil
            memories[index].feedbackCompletedAt = now
        }
        save()
    }

    func recordLikedAnswer(for outfitMemoryId: UUID, wasLiked: Bool, now: Date = Date()) {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        guard let index = memories.firstIndex(where: { $0.id == outfitMemoryId }) else {
            return
        }

        memories[index].feedbackTimestamp = now
        memories[index].wasLiked = wasLiked
        memories[index].wouldWearAgain = wasLiked
        if wasLiked {
            memories[index].isFavorite = true
            memories[index].dislikeReason = nil
            memories[index].feedbackCompletedAt = now
        }
        save()
    }

    func recordDislikeReason(for outfitMemoryId: UUID, reason: DislikeReason, now: Date = Date()) {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        guard let index = memories.firstIndex(where: { $0.id == outfitMemoryId }) else {
            return
        }

        memories[index].feedbackTimestamp = now
        memories[index].wasLiked = false
        memories[index].wouldWearAgain = false
        memories[index].dislikeReason = reason
        memories[index].feedbackCompletedAt = now
        save()
    }

    func recordOutfitFeedback(for outfitMemoryId: UUID, feedback: OutfitFeedback) {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        guard let index = memories.firstIndex(where: { $0.id == outfitMemoryId }) else {
            return
        }

        memories[index].feedback = feedback
        memories[index].feedbackTimestamp = feedback.recordedAt
        memories[index].feedbackCompletedAt = feedback.recordedAt

        if let woreIt = feedback.woreIt {
            applyWornAnswer(at: index, wasWorn: woreIt, now: feedback.recordedAt)
        }

        switch feedback.verdict {
        case .loved:
            memories[index].wasLiked = true
            memories[index].wouldWearAgain = true
            memories[index].isFavorite = true
            memories[index].dislikeReason = nil
        case .liked:
            memories[index].wasLiked = true
            memories[index].wouldWearAgain = true
            memories[index].dislikeReason = nil
        case .notForMe:
            memories[index].wasLiked = false
            memories[index].wouldWearAgain = false
        }

        save()
    }

    func updateOccasion(for outfitMemoryId: UUID, occasion: Occasion?) {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        guard let index = memories.firstIndex(where: { $0.id == outfitMemoryId }) else {
            return
        }

        memories[index].occasion = occasion?.canonical
        save()
    }

    private func applyFeedbackFields(
        at index: Int,
        wasWorn: Bool,
        wasLiked: Bool?,
        dislikeReason: DislikeReason?,
        now: Date,
        markComplete: Bool
    ) {
        applyWornAnswer(at: index, wasWorn: wasWorn, now: now)

        if let wasLiked {
            memories[index].wasLiked = wasLiked
            memories[index].wouldWearAgain = wasLiked
            if wasLiked {
                memories[index].isFavorite = true
            }
        }

        if wasLiked == false, let dislikeReason {
            memories[index].dislikeReason = dislikeReason
        } else if wasLiked != false {
            memories[index].dislikeReason = nil
        }

        if markComplete {
            memories[index].feedbackCompletedAt = now
        }
    }

    private func applyWornAnswer(at index: Int, wasWorn: Bool, now: Date) {
        let wasAlreadyWorn = memories[index].wasWorn == true
        memories[index].feedbackTimestamp = now
        memories[index].wasWorn = wasWorn

        if wasWorn && !wasAlreadyWorn {
            memories[index].timesWorn = max(1, memories[index].timesWorn + 1)
            for recordIndex in memories[index].garmentRecords.indices {
                memories[index].garmentRecords[recordIndex].timesWorn = max(1, memories[index].garmentRecords[recordIndex].timesWorn + 1)
                memories[index].garmentRecords[recordIndex].lastWorn = now
            }
        }
    }

    func favoriteOutfits() -> [OutfitMemory] {
        memories
            .filter { $0.isFavorite || $0.wasLiked == true || $0.wouldWearAgain == true }
            .sorted { lhs, rhs in
                if lhs.styleScore == rhs.styleScore {
                    return lhs.scanDate > rhs.scanDate
                }
                return lhs.styleScore > rhs.styleScore
            }
    }

    func mostWornOutfits(limit: Int) -> [OutfitMemory] {
        Array(
            memories
                .filter { $0.timesWorn > 0 || $0.wasWorn == true }
                .sorted { lhs, rhs in
                    if lhs.timesWorn == rhs.timesWorn {
                        return lhs.scanDate > rhs.scanDate
                    }
                    return lhs.timesWorn > rhs.timesWorn
                }
                .prefix(max(0, limit))
        )
    }

    func recentlyRecommendedColors(days: Int) -> [String] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -max(0, days), to: Date()) ?? .distantPast
        var seen = Set<String>()

        return memories
            .filter { $0.scanDate >= cutoff }
            .sorted { $0.scanDate > $1.scanDate }
            .flatMap(\.colors)
            .compactMap { color -> String? in
                let cleaned = color.trimmingCharacters(in: .whitespacesAndNewlines)
                let key = cleaned.lowercased()
                guard !cleaned.isEmpty, !seen.contains(key) else {
                    return nil
                }
                seen.insert(key)
                return cleaned
            }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(memories) else {
            #if DEBUG
            print("[StyleMatch PersonalStylist] Could not encode OutfitMemoryStore.")
            #endif
            return
        }
        PersonalStylistSnapshotStore.saveData(data, store: "OutfitMemoryStore", userID: userID)
        defaults.set(data, forKey: memoriesKey)
    }

    private static func loadMemories(from defaults: UserDefaults, key: String, userID: String) -> [OutfitMemory] {
        let decoder = JSONDecoder()
        func decodeMemories(_ data: Data) -> [OutfitMemory]? {
            try? decoder.decode([OutfitMemory].self, from: data)
        }

        let data = PersonalStylistSnapshotStore.loadData(store: "OutfitMemoryStore", userID: userID)
            ?? defaults.data(forKey: key)
        guard let data else { return [] }

        let decoded: [OutfitMemory]
        if let memories = decodeMemories(data) {
            decoded = memories
        } else if let recoveredData = PersonalStylistSnapshotStore.restoreFromSnapshot(
            store: "OutfitMemoryStore",
            userID: userID,
            validator: { decodeMemories($0) != nil }
        ),
                  let memories = decodeMemories(recoveredData) {
            decoded = memories
        } else {
            #if DEBUG
            print("[StyleMatch PersonalStylist] Could not decode OutfitMemoryStore for \(userID).")
            #endif
            return []
        }
        return decoded
            .filter { PersonalStylistStorage.normalizedUserID($0.userId) == userID }
            .sorted { $0.scanDate > $1.scanDate }
    }

    private func merge(memory existing: OutfitMemory, with incoming: OutfitMemory) -> OutfitMemory {
        var merged = incoming
        merged.garmentRecords = merge(existingRecords: existing.garmentRecords, incomingRecords: incoming.garmentRecords)
        merged.timesWorn = max(existing.timesWorn, incoming.timesWorn)
        merged.wasWorn = incoming.wasWorn ?? existing.wasWorn
        merged.wasLiked = incoming.wasLiked ?? existing.wasLiked
        merged.feedbackTimestamp = incoming.feedbackTimestamp ?? existing.feedbackTimestamp
        merged.dislikeReason = incoming.dislikeReason ?? existing.dislikeReason
        merged.feedbackPromptCount = max(existing.feedbackPromptCount, incoming.feedbackPromptCount)
        merged.feedbackDismissedAt = incoming.feedbackDismissedAt ?? existing.feedbackDismissedAt
        merged.feedbackCompletedAt = incoming.feedbackCompletedAt ?? existing.feedbackCompletedAt
        merged.feedback = incoming.feedback ?? existing.feedback
        merged.occasion = incoming.occasion?.canonical ?? existing.occasion?.canonical
        merged.wouldWearAgain = incoming.wouldWearAgain ?? existing.wouldWearAgain
        merged.receivedCompliments = incoming.receivedCompliments ?? existing.receivedCompliments
        merged.isFavorite = existing.isFavorite || incoming.isFavorite
        return merged
    }

    private func merge(existingRecords: [GarmentRecord], incomingRecords: [GarmentRecord]) -> [GarmentRecord] {
        var recordsByFingerprint: [String: GarmentRecord] = [:]
        for existing in existingRecords {
            if let stored = recordsByFingerprint[existing.itemFingerprint] {
                recordsByFingerprint[existing.itemFingerprint] = merge(record: stored, with: existing)
            } else {
                recordsByFingerprint[existing.itemFingerprint] = existing
            }
        }

        for incoming in incomingRecords {
            if var existing = recordsByFingerprint[incoming.itemFingerprint] {
                existing = merge(record: existing, with: incoming)
                recordsByFingerprint[incoming.itemFingerprint] = existing
            } else {
                recordsByFingerprint[incoming.itemFingerprint] = incoming
            }
        }

        return recordsByFingerprint.values.sorted { first, second in
            if first.timesWorn == second.timesWorn {
                return first.lastSeenAt > second.lastSeenAt
            }
            return first.timesWorn > second.timesWorn
        }
    }

    private func firstMatchingGarmentRecordIndex(for incoming: OutfitMemory) -> Int? {
        let fingerprints = Set(incoming.garmentRecords.map(\.itemFingerprint))
        guard !fingerprints.isEmpty else { return nil }
        return memories.firstIndex { memory in
            !Set(memory.garmentRecords.map(\.itemFingerprint)).isDisjoint(with: fingerprints)
        }
    }

    private func merge(record existing: GarmentRecord, with incoming: GarmentRecord) -> GarmentRecord {
        var merged = existing
        merged.timesSeen = max(1, existing.timesSeen + max(1, incoming.timesSeen))
        merged.timesWorn = max(existing.timesWorn, incoming.timesWorn)
        merged.lastWorn = incoming.lastWorn ?? existing.lastWorn
        merged.lastSeenAt = max(existing.lastSeenAt, incoming.lastSeenAt)
        merged.sourceScanIds = Array(Set(existing.sourceScanIds + incoming.sourceScanIds)).sorted()
        merged.colors = Array(Set(existing.colors + incoming.colors)).sorted()
        merged.styleTags = Array(Set(existing.styleTags + incoming.styleTags)).sorted()
        merged.colorConfidence = max(existing.colorConfidence, incoming.colorConfidence)
        return merged
    }
}
