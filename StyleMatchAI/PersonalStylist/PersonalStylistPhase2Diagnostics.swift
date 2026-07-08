import Foundation

#if DEBUG
enum PersonalStylistPhase2Diagnostics {
    static func runStorageIsolationSmokeTest() {
        let suiteName = "StyleMatchProPhase2Diagnostics.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let userA = "phase2-user-a"
        let userB = "phase2-user-b"
        let record = GarmentRecord(
            garmentCategory: "pants",
            itemFingerprint: "pants-black-solid",
            colors: ["black"],
            styleTags: ["casual"],
            colorConfidence: 90,
            sourceScanIds: ["scan-a"]
        )
        let memory = OutfitMemory(
            id: UUID(),
            userId: userA,
            scanDate: Date(),
            detectedGarments: ["pants"],
            colors: ["black"],
            detectedStyle: "Casual",
            styleScore: 82,
            occasion: .casual,
            wasWorn: nil,
            wasLiked: nil,
            feedbackTimestamp: nil,
            dislikeReason: nil,
            wouldWearAgain: nil,
            receivedCompliments: nil,
            isFavorite: false,
            timesWorn: 0,
            garmentRecords: [record]
        )

        let userAStore = OutfitMemoryStore(defaults: defaults, userId: userA)
        userAStore.addOrMergeScan(memory)
        let userBStore = OutfitMemoryStore(defaults: defaults, userId: userB)
        let userBMemory = OutfitMemory(
            id: UUID(),
            userId: userB,
            scanDate: Date(),
            detectedGarments: ["pants"],
            colors: ["black"],
            detectedStyle: "Casual",
            styleScore: 82,
            occasion: .casual,
            wasWorn: nil,
            wasLiked: nil,
            feedbackTimestamp: nil,
            dislikeReason: nil,
            wouldWearAgain: nil,
            receivedCompliments: nil,
            isFavorite: false,
            timesWorn: 0,
            garmentRecords: [record]
        )
        userBStore.addOrMergeScan(userBMemory)

        assert(userAStore.memories.count == 1, "Phase 2 diagnostic failed: user A should see one memory.")
        assert(userBStore.memories.count == 1, "Phase 2 diagnostic failed: user B should see only their own memory.")
        assert(userBStore.memories.allSatisfy { $0.userId == userB }, "Phase 2 diagnostic failed: user B saw another user's memories.")

        _ = userAStore.mergeGarmentRecords([record], into: memory.id)
        let mergedRecord = userAStore.garmentRecords.first { $0.itemFingerprint == record.itemFingerprint }
        assert(userAStore.garmentRecords.count == 1, "Phase 2 diagnostic failed: repeated garment duplicated.")
        assert((mergedRecord?.timesSeen ?? 0) >= 2, "Phase 2 diagnostic failed: repeated garment did not increment timesSeen.")

        defaults.set(userA, forKey: "customerAppleUserID")
        PersonalStylistStorage.deleteCurrentUserPersonalization(defaults: defaults)
        assert(OutfitMemoryStore(defaults: defaults, userId: userA).memories.isEmpty, "Phase 2 diagnostic failed: user A data was not deleted.")
        assert(OutfitMemoryStore(defaults: defaults, userId: userB).memories.count == 1, "Phase 2 diagnostic failed: deleting user A removed user B data.")
    }
}
#endif
