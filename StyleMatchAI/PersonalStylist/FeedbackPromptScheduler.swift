import Foundation

struct ScheduledFeedbackPrompt: Identifiable {
    let id: UUID
    let memory: OutfitMemory

    var scoreSummary: String {
        "\(memory.styleScore) \(memory.detectedStyle)"
    }
}

final class FeedbackPromptScheduler {
    static let minimumPromptAge: TimeInterval = 12 * 60 * 60
    static let maximumPromptAge: TimeInterval = 14 * 24 * 60 * 60
    static let dismissalCooldown: TimeInterval = 48 * 60 * 60
    static let maximumPromptCount = 2
    static let globalPromptCooldown: TimeInterval = 24 * 60 * 60

    private let store: OutfitMemoryStore
    private let defaults: UserDefaults
    private let userID: String
    private let nowProvider: () -> Date
    private var hasShownPromptThisSession = false

    private var lastPromptedKey: String {
        PersonalStylistStorage.scopedKey("personalStylistFeedbackLastPromptedAt", userID: userID)
    }

    private var firstSessionSeenKey: String {
        PersonalStylistStorage.scopedKey("personalStylistFeedbackFirstSessionSeen", userID: userID)
    }

    init(
        store: OutfitMemoryStore,
        defaults: UserDefaults = .standard,
        userId: String? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.defaults = defaults
        self.userID = PersonalStylistStorage.normalizedUserID(userId ?? PersonalStylistStorage.activeUserID(defaults: defaults))
        self.nowProvider = now
    }

    func nextPromptCandidate(now: Date? = nil) -> OutfitMemory? {
        let currentDate = now ?? nowProvider()
        guard defaults.bool(forKey: firstSessionSeenKey) else {
            defaults.set(true, forKey: firstSessionSeenKey)
            return nil
        }

        guard !hasShownPromptThisSession, !isWithinGlobalCooldown(now: currentDate) else {
            return nil
        }

        return store.memories
            .filter { isEligible($0, now: currentDate) }
            .sorted { $0.scanDate > $1.scanDate }
            .first
    }

    func recordPromptShown(for outfitID: UUID, now: Date? = nil) {
        let currentDate = now ?? nowProvider()
        hasShownPromptThisSession = true
        store.recordFeedbackPromptShown(for: outfitID, now: currentDate)
        defaults.set(currentDate.timeIntervalSince1970, forKey: lastPromptedKey)
    }

    private func isEligible(_ memory: OutfitMemory, now: Date) -> Bool {
        let age = now.timeIntervalSince(memory.scanDate)
        guard age >= Self.minimumPromptAge, age <= Self.maximumPromptAge else {
            return false
        }

        guard memory.feedbackCompletedAt == nil,
              memory.feedbackPromptCount < Self.maximumPromptCount else {
            return false
        }

        if let dismissedAt = memory.feedbackDismissedAt,
           now.timeIntervalSince(dismissedAt) < Self.dismissalCooldown {
            return false
        }

        return true
    }

    private func isWithinGlobalCooldown(now: Date) -> Bool {
        let timestamp = defaults.double(forKey: lastPromptedKey)
        guard timestamp > 0 else {
            return false
        }
        return now.timeIntervalSince1970 - timestamp < Self.globalPromptCooldown
    }
}
