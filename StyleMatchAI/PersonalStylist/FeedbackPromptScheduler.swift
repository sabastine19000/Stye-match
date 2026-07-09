import Foundation

struct ScheduledFeedbackPrompt: Identifiable {
    let id: UUID
    let memory: OutfitMemory

    var scoreSummary: String {
        "\(memory.styleScore) \(memory.detectedStyle)"
    }
}

struct FeedbackPromptDecision: Equatable {
    let shouldPrompt: Bool
    let reason: String
}

enum FeedbackPromptSurface {
    case scanResult
    case scanHistoryDetail
}

struct SchedulerContext {
    let now: Date
    let isFirstScanEver: Bool
    let hasShownPromptThisSession: Bool
    let lastPromptedAt: Date?
    let consecutiveSkips: Int
    let lastSkipAt: Date?
    let surface: FeedbackPromptSurface
}

final class FeedbackPromptScheduler {
    static let minimumPromptAge: TimeInterval = 12 * 60 * 60
    static let maximumPromptAge: TimeInterval = 14 * 24 * 60 * 60
    static let dismissalCooldown: TimeInterval = 48 * 60 * 60
    static let maximumPromptCount = 2
    static let globalPromptCooldown: TimeInterval = 24 * 60 * 60
    static let historyReengagementMinimumAge: TimeInterval = 24 * 60 * 60
    static let skipBackoffThreshold = 2
    static let skipBackoffDuration: TimeInterval = 7 * 24 * 60 * 60

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

    private var consecutiveSkipsKey: String {
        PersonalStylistStorage.scopedKey("personalStylistFeedbackConsecutiveSkips", userID: userID)
    }

    private var lastSkipAtKey: String {
        PersonalStylistStorage.scopedKey("personalStylistFeedbackLastSkipAt", userID: userID)
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

        guard !hasShownPromptThisSession,
              !isWithinGlobalCooldown(now: currentDate),
              !isWithinSkipBackoff(now: currentDate) else {
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

    func recordPromptSkipped(now: Date? = nil) {
        let currentDate = now ?? nowProvider()
        defaults.set(defaults.integer(forKey: consecutiveSkipsKey) + 1, forKey: consecutiveSkipsKey)
        defaults.set(currentDate.timeIntervalSince1970, forKey: lastSkipAtKey)
    }

    func recordFeedbackCompleted() {
        defaults.set(0, forKey: consecutiveSkipsKey)
        defaults.removeObject(forKey: lastSkipAtKey)
    }

    func decision(for scan: OutfitMemory, surface: FeedbackPromptSurface, now: Date? = nil) -> FeedbackPromptDecision {
        let currentDate = now ?? nowProvider()
        let lastPromptedTimestamp = defaults.double(forKey: lastPromptedKey)
        let lastSkipTimestamp = defaults.double(forKey: lastSkipAtKey)
        let context = SchedulerContext(
            now: currentDate,
            isFirstScanEver: store.memories.count <= 1,
            hasShownPromptThisSession: hasShownPromptThisSession,
            lastPromptedAt: lastPromptedTimestamp > 0 ? Date(timeIntervalSince1970: lastPromptedTimestamp) : nil,
            consecutiveSkips: defaults.integer(forKey: consecutiveSkipsKey),
            lastSkipAt: lastSkipTimestamp > 0 ? Date(timeIntervalSince1970: lastSkipTimestamp) : nil,
            surface: surface
        )
        return Self.decision(for: scan, context: context)
    }

    static func decision(for scan: OutfitMemory, context: SchedulerContext) -> FeedbackPromptDecision {
        let decision: FeedbackPromptDecision
        if scan.feedback != nil || scan.feedbackCompletedAt != nil {
            decision = FeedbackPromptDecision(shouldPrompt: false, reason: "feedback already recorded")
        } else if context.isFirstScanEver {
            decision = FeedbackPromptDecision(shouldPrompt: false, reason: "first scan suppressed")
        } else if let lastPromptedAt = context.lastPromptedAt,
                  context.now.timeIntervalSince(lastPromptedAt) < globalPromptCooldown {
            decision = FeedbackPromptDecision(shouldPrompt: false, reason: "within 24h global cooldown")
        } else if context.consecutiveSkips >= skipBackoffThreshold,
                  let lastSkipAt = context.lastSkipAt,
                  context.now.timeIntervalSince(lastSkipAt) < skipBackoffDuration {
            decision = FeedbackPromptDecision(shouldPrompt: false, reason: "fatigue backoff after two skips")
        } else if context.hasShownPromptThisSession {
            decision = FeedbackPromptDecision(shouldPrompt: false, reason: "session prompt cap reached")
        } else {
            switch context.surface {
            case .scanResult:
                decision = FeedbackPromptDecision(shouldPrompt: true, reason: "scan result eligible")
            case .scanHistoryDetail:
                let age = context.now.timeIntervalSince(scan.scanDate)
                let inHistoryWindow = age >= historyReengagementMinimumAge && age <= maximumPromptAge
                decision = FeedbackPromptDecision(
                    shouldPrompt: inHistoryWindow,
                    reason: inHistoryWindow ? "history re-engagement eligible" : "history scan outside 1-14 day window"
                )
            }
        }

        #if DEBUG
        print("[StyleMatch FeedbackPromptScheduler] shouldPrompt=\(decision.shouldPrompt); reason=\(decision.reason)")
        #endif

        return decision
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

    private func isWithinSkipBackoff(now: Date) -> Bool {
        guard defaults.integer(forKey: consecutiveSkipsKey) >= Self.skipBackoffThreshold else {
            return false
        }

        let timestamp = defaults.double(forKey: lastSkipAtKey)
        guard timestamp > 0 else {
            return false
        }

        return now.timeIntervalSince1970 - timestamp < Self.skipBackoffDuration
    }
}
