import Combine
import Foundation

final class ProfileStore: ObservableObject {
    @Published var currentProfile: StylistProfile

    private let defaults: UserDefaults
    private let userID: String
    private let profileKey: String
    private let feedbackCountKey: String
    private let mutationLock = NSRecursiveLock()

    init(defaults: UserDefaults = .standard, userId: String? = nil) {
        self.defaults = defaults
        PersonalStylistStorage.migrateLegacyKeysIfNeeded(defaults: defaults)
        let activeUserID = userId ?? PersonalStylistStorage.activeUserID(defaults: defaults)
        FounderProfileDefaultsMigration.run(defaults: defaults, userID: activeUserID)
        self.userID = PersonalStylistStorage.normalizedUserID(activeUserID)
        self.profileKey = PersonalStylistStorage.scopedKey(PersonalStylistStorage.legacyProfileKey, userID: self.userID)
        self.feedbackCountKey = PersonalStylistStorage.scopedKey(PersonalStylistStorage.legacyFeedbackCountKey, userID: self.userID)
        let loadedProfile = Self.loadProfile(from: defaults, key: profileKey, userID: self.userID) ?? Self.makeDefaultProfile(defaults: defaults, userID: self.userID)
        let reconciled = PantsSizeProfileReconciliation.reconcile(defaults: defaults, userID: self.userID, profile: loadedProfile)
        currentProfile = reconciled.profile
        if reconciled.didChangeProfile {
            saveProfile(reconciled.profile)
        }
    }

    func save() {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        var profile = currentProfile
        profile.givenName = StyleMatchAccountNameResolver.profileGivenName(from: profile.givenName)
        profile.lastUpdatedAt = Date()
        currentProfile = profile
        saveProfile(profile)
    }

    func updateGivenName(_ givenName: String?) {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        var profile = currentProfile
        profile.userId = userID
        profile.givenName = StyleMatchAccountNameResolver.profileGivenName(from: givenName)
        profile.lastUpdatedAt = Date()
        currentProfile = profile
        saveProfile(profile)
    }

    func updateProfile(from outfitMemory: OutfitMemory) {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        var profile = currentProfile
        profile.userId = userID
        profile.totalScansCompleted += 1

        let feedbackMultiplier: Double
        if outfitMemory.wasLiked == true || outfitMemory.wouldWearAgain == true || outfitMemory.isFavorite {
            feedbackMultiplier = 1.0
        } else if outfitMemory.wasLiked == false || outfitMemory.wouldWearAgain == false {
            feedbackMultiplier = -1.0
        } else {
            feedbackMultiplier = 0.25
        }

        for color in outfitMemory.colors {
            adjustPreference("color:\(color)", by: 0.15 * feedbackMultiplier, in: &profile)
            if feedbackMultiplier > 0, !profile.favoriteColors.contains(where: { $0.caseInsensitiveCompare(color) == .orderedSame }) {
                profile.favoriteColors.append(color)
            }
            if feedbackMultiplier < 0, !profile.dislikedColors.contains(where: { $0.caseInsensitiveCompare(color) == .orderedSame }) {
                profile.dislikedColors.append(color)
            }
        }

        adjustPreference("style:\(outfitMemory.detectedStyle)", by: 0.20 * feedbackMultiplier, in: &profile)

        if let occasion = outfitMemory.occasion {
            adjustPreference("occasion:\(occasion.rawValue)", by: 0.10 * feedbackMultiplier, in: &profile)
        }

        for record in outfitMemory.garmentRecords {
            adjustPreference("category:\(record.garmentCategory)", by: 0.08 * feedbackMultiplier, in: &profile)
            for tag in record.styleTags {
                adjustPreference("tag:\(tag)", by: 0.06 * feedbackMultiplier, in: &profile)
            }
        }

        if outfitMemory.receivedCompliments == true {
            adjustPreference("complimented:\(outfitMemory.detectedStyle)", by: 0.18, in: &profile)
        }

        if outfitMemory.wasLiked != nil || outfitMemory.wouldWearAgain != nil || outfitMemory.receivedCompliments != nil {
            defaults.set(defaults.integer(forKey: feedbackCountKey) + 1, forKey: feedbackCountKey)
        }

        profile.lastUpdatedAt = Date()
        currentProfile = profile
        recalculateConfidenceScore()
        saveProfile(currentProfile)
    }

    func recalculateConfidenceScore() {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        var profile = currentProfile
        let scanConfidence = min(55.0, Double(profile.totalScansCompleted) * 2.75)
        let feedbackConfidence = min(25.0, Double(defaults.integer(forKey: feedbackCountKey)) * 2.5)
        let preferenceConfidence = min(15.0, Double(profile.stylePreferencesLearned.count) * 0.75)
        let profileDetailConfidence = Self.profileCompletenessScore(profile) * 5.0
        let total = 20.0 + scanConfidence + feedbackConfidence + preferenceConfidence + profileDetailConfidence
        profile.profileConfidenceScore = min(95.0, max(20.0, total))
        profile.lastUpdatedAt = Date()
        currentProfile = profile
        saveProfile(profile)
    }

    private func adjustPreference(_ key: String, by delta: Double, in profile: inout StylistProfile) {
        let current = profile.stylePreferencesLearned[key, default: 0]
        profile.stylePreferencesLearned[key] = min(3.0, max(-1.0, current + delta))
    }

    static func profileCompletenessPercentage(_ profile: StylistProfile) -> Int {
        Int((profileCompletenessScore(profile) * 100).rounded())
    }

    private static func profileCompletenessScore(_ profile: StylistProfile) -> Double {
        var completed = 0.0
        var total = 0.0

        func count(_ value: String?) {
            total += 1
            if value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                completed += 1
            }
        }

        count(profile.clothingSizes.shirtSize)
        count(profile.clothingSizes.pantSize)
        count(profile.clothingSizes.shoeSize)
        count(profile.clothingSizes.jacketSize)
        count(profile.clothingSizes.dressSize)

        total += 1
        if !profile.favoriteColors.isEmpty { completed += 1 }

        total += 1
        if !profile.favoriteBrands.isEmpty { completed += 1 }

        total += 1
        if !profile.workDressCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { completed += 1 }

        return total == 0 ? 0 : completed / total
    }

    private func saveProfile(_ profile: StylistProfile) {
        guard let data = try? JSONEncoder().encode(profile) else {
            return
        }
        PersonalStylistSnapshotStore.saveData(data, store: "StylistProfile", userID: userID)
        defaults.set(data, forKey: profileKey)
    }

    private static func loadProfile(from defaults: UserDefaults, key: String, userID: String) -> StylistProfile? {
        let decoder = JSONDecoder()
        func canDecodeProfile(_ data: Data) -> Bool {
            (try? decoder.decode(StylistProfile.self, from: data)) != nil
        }

        if let data = PersonalStylistSnapshotStore.loadData(store: "StylistProfile", userID: userID),
           let profile = try? decoder.decode(StylistProfile.self, from: data) {
            return profile
        }
        if let recoveredData = PersonalStylistSnapshotStore.restoreFromSnapshot(
            store: "StylistProfile",
            userID: userID,
            validator: canDecodeProfile
        ),
           let profile = try? decoder.decode(StylistProfile.self, from: recoveredData) {
            return profile
        }
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(StylistProfile.self, from: data)
    }

    private static func makeDefaultProfile(defaults: UserDefaults, userID: String) -> StylistProfile {
        guard FounderProfileDefaultsMigration.hasIntentionalProfileSave(defaults: defaults) else {
            return blankProfile(userID: userID)
        }

        let now = Date()
        return StylistProfile(
            id: UUID(),
            userId: userID,
            givenName: nil,
            favoriteColors: splitList(defaults.string(forKey: "favoriteColors") ?? ""),
            dislikedColors: [],
            favoriteBrands: splitList(defaults.string(forKey: "favoriteBrands") ?? ""),
            declaredUndertone: nil,
            preferredFit: FitPreference.fromProfileInput(defaults.string(forKey: "fitPreference")),
            preferredPantFit: PantFitPreference.fromProfileInput(
                PantFitPreference.migratedValue(
                    currentValue: defaults.string(forKey: "preferredPantFit"),
                    legacyOverallFit: defaults.string(forKey: "fitPreference")
                )
            ),
            styleGoals: splitList(defaults.string(forKey: "styleGoals") ?? ""),
            preferredNeutrals: splitList(defaults.string(forKey: "preferredNeutrals") ?? ""),
            preferredAccentColors: splitList(defaults.string(forKey: "preferredAccentColors") ?? ""),
            comfortPreferences: splitList(defaults.string(forKey: "comfortPreferences") ?? ""),
            preferredPantRise: cleanOptional(defaults.string(forKey: "preferredPantRise")) ?? "",
            shoppingFocus: cleanOptional(defaults.string(forKey: "shoppingFocus")) ?? "",
            preferredShoppingCategories: splitList(defaults.string(forKey: "preferredShoppingCategories") ?? ""),
            workSetting: cleanOptional(defaults.string(forKey: "workSetting")) ?? "",
            travelFrequency: cleanOptional(defaults.string(forKey: "travelFrequency")) ?? "",
            hobbiesActivities: splitList(defaults.string(forKey: "hobbiesActivities") ?? ""),
            stylistVoice: cleanOptional(defaults.string(forKey: "stylistVoice")) ?? "",
            budgetRange: parseBudget(defaults.string(forKey: "shoppingBudget") ?? ""),
            climate: cleanOptional(defaults.string(forKey: "weatherCondition")) ?? "",
            workDressCode: cleanOptional(defaults.string(forKey: "dressCode")) ?? "",
            bodyProportions: nil,
            clothingSizes: ClothingSizes(
                shirtSize: cleanOptional(defaults.string(forKey: "shirtSize")),
                pantSize: cleanOptional(defaults.string(forKey: "pantsSize")),
                shoeSize: cleanOptional(defaults.string(forKey: "shoeSize")),
                jacketSize: nil,
                dressSize: cleanOptional(defaults.string(forKey: "dressSize"))
            ),
            stylePreferencesLearned: [:],
            createdAt: now,
            lastUpdatedAt: now,
            totalScansCompleted: 0,
            profileConfidenceScore: 20
        )
    }

    private static func blankProfile(userID: String) -> StylistProfile {
        let now = Date()
        return StylistProfile(
            id: UUID(),
            userId: userID,
            givenName: nil,
            favoriteColors: [],
            dislikedColors: [],
            favoriteBrands: [],
            declaredUndertone: nil,
            preferredFit: .unset,
            preferredPantFit: .unset,
            styleGoals: [],
            preferredNeutrals: [],
            preferredAccentColors: [],
            comfortPreferences: [],
            preferredPantRise: "",
            shoppingFocus: "",
            preferredShoppingCategories: [],
            workSetting: "",
            travelFrequency: "",
            hobbiesActivities: [],
            stylistVoice: "",
            budgetRange: .neutral,
            climate: "",
            workDressCode: "",
            bodyProportions: nil,
            clothingSizes: ClothingSizes(),
            stylePreferencesLearned: [:],
            createdAt: now,
            lastUpdatedAt: now,
            totalScansCompleted: 0,
            profileConfidenceScore: 20
        )
    }

    private static func splitList(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func parseBudget(_ text: String) -> BudgetRange {
        let numbers = text
            .components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted)
            .compactMap { Double($0) }
        guard let first = numbers.first else {
            return .neutral
        }
        let minPrice = first
        let maxPrice = numbers.dropFirst().first ?? first
        let tier: String
        switch maxPrice {
        case ..<75:
            tier = "Budget"
        case 75..<250:
            tier = "Mid"
        default:
            tier = "Premium"
        }
        return BudgetRange(minPrice: minPrice, maxPrice: maxPrice, preferredTier: tier)
    }

    private static func cleanOptional(_ text: String?) -> String? {
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
