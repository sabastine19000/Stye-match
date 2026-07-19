import Foundation

enum PersonalStylistStorage {
    static let legacyProfileKey = "personalStylistProfileData"
    static let legacyMemoriesKey = "personalStylistOutfitMemoriesData"
    static let legacyFeedbackCountKey = "personalStylistFeedbackCount"

    static func activeUserID(defaults: UserDefaults = .standard) -> String {
        let raw = defaults.string(forKey: "customerAppleUserID")
            ?? defaults.string(forKey: "customerAccountEmail")
            ?? "guest"
        return normalizedUserID(raw)
    }

    static func normalizedUserID(_ userID: String) -> String {
        let trimmed = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmed.isEmpty ? "guest" : trimmed
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_@."))
        let sanitized = fallback.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        return String(sanitized).lowercased()
    }

    static func scopedKey(_ baseKey: String, userID: String) -> String {
        "\(baseKey)_\(normalizedUserID(userID))"
    }

    static func currentUserKeys(defaults: UserDefaults = .standard) -> [String] {
        let userID = activeUserID(defaults: defaults)
        return [
            scopedKey(legacyProfileKey, userID: userID),
            scopedKey(legacyMemoriesKey, userID: userID),
            scopedKey(legacyFeedbackCountKey, userID: userID)
        ]
    }

    static func deleteCurrentUserPersonalization(defaults: UserDefaults = .standard) {
        deletePersonalization(for: activeUserID(defaults: defaults), defaults: defaults)
    }

    @discardableResult
    static func deleteActiveUserData(defaults: UserDefaults = .standard) -> String {
        let userID = activeUserID(defaults: defaults)
        deletePersonalization(for: userID, defaults: defaults)
        return userID
    }

    static func deletePersonalization(for userID: String, defaults: UserDefaults = .standard) {
        for key in [
            scopedKey(legacyProfileKey, userID: userID),
            scopedKey(legacyMemoriesKey, userID: userID),
            scopedKey(legacyFeedbackCountKey, userID: userID),
            scopedKey(ShoppingLocalStore.recentlyViewedBaseKey, userID: userID),
            scopedKey(ShoppingLocalStore.dismissedBaseKey, userID: userID),
            scopedKey(ShoppingLocalStore.savedFavoritesBaseKey, userID: userID),
            scopedKey(ShoppingLocalStore.wishlistBaseKey, userID: userID),
            scopedKey(ShoppingLocalStore.cartBaseKey, userID: userID),
            scopedKey(ShoppingLocalStore.shoppingCardsBaseKey, userID: userID),
            scopedKey(ShoppingLocalStore.preferredRetailerIDsBaseKey, userID: userID),
            scopedKey(ShoppingLocalStore.saleAlertProductIDsBaseKey, userID: userID),
            scopedKey(ShoppingLocalStore.latestKnownPricesBaseKey, userID: userID),
            scopedKey(ShoppingLocalStore.saleNotificationsEnabledBaseKey, userID: userID),
            scopedKey(ShoppingLocalStore.saleStateSnapshotsBaseKey, userID: userID),
            scopedKey(ShoppingLocalStore.lastKnownSaleStateBaseKey, userID: userID),
            scopedKey(ShoppingLocalStore.notifiedSalePairsBaseKey, userID: userID),
            scopedKey(ShoppingLocalStore.saleNotificationHistoryBaseKey, userID: userID),
            scopedKey(ShoppingLocalStore.recentSaleEventsBaseKey, userID: userID),
            scopedKey(ShoppingLocalStore.viewedSaleEventIDsBaseKey, userID: userID),
            scopedKey(ShoppingLocalStore.affiliateDisclosureExpandedBaseKey, userID: userID),
            scopedKey(ShoppingLocalStore.affiliateDisclosureSeenExpandedBaseKey, userID: userID),
            scopedKey(ShareableScoreCardLocalStore.baseKey, userID: userID),
            scopedKey("personalStylistFeedbackLastPromptedAt", userID: userID),
            scopedKey("personalStylistFeedbackFirstSessionSeen", userID: userID),
            scopedKey("customerAccountEmail", userID: userID)
        ] {
            defaults.removeObject(forKey: key)
        }
        PersonalStylistSnapshotStore.deleteData(store: "StylistProfile", userID: userID)
        PersonalStylistSnapshotStore.deleteData(store: "OutfitMemoryStore", userID: userID)
    }

    static func transferPersonalization(
        from sourceUserID: String,
        to destinationUserID: String,
        defaults: UserDefaults = .standard
    ) {
        let source = normalizedUserID(sourceUserID)
        let destination = normalizedUserID(destinationUserID)
        guard source != destination else { return }

        for baseKey in personalizationBaseKeys {
            let sourceKey = scopedKey(baseKey, userID: source)
            let destinationKey = scopedKey(baseKey, userID: destination)
            guard defaults.object(forKey: destinationKey) == nil,
                  let value = defaults.object(forKey: sourceKey) else {
                continue
            }
            defaults.set(value, forKey: destinationKey)
        }
    }

    private static let personalizationBaseKeys = [
        legacyProfileKey,
        legacyMemoriesKey,
        legacyFeedbackCountKey,
        ShoppingLocalStore.recentlyViewedBaseKey,
        ShoppingLocalStore.dismissedBaseKey,
        ShoppingLocalStore.savedFavoritesBaseKey,
        ShoppingLocalStore.wishlistBaseKey,
        ShoppingLocalStore.cartBaseKey,
        ShoppingLocalStore.shoppingCardsBaseKey,
        ShoppingLocalStore.preferredRetailerIDsBaseKey,
        ShoppingLocalStore.saleAlertProductIDsBaseKey,
        ShoppingLocalStore.latestKnownPricesBaseKey,
        ShoppingLocalStore.saleNotificationsEnabledBaseKey,
        ShoppingLocalStore.saleStateSnapshotsBaseKey,
        ShoppingLocalStore.lastKnownSaleStateBaseKey,
        ShoppingLocalStore.notifiedSalePairsBaseKey,
        ShoppingLocalStore.saleNotificationHistoryBaseKey,
        ShoppingLocalStore.recentSaleEventsBaseKey,
        ShoppingLocalStore.viewedSaleEventIDsBaseKey,
        ShoppingLocalStore.affiliateDisclosureExpandedBaseKey,
        ShoppingLocalStore.affiliateDisclosureSeenExpandedBaseKey,
        ShareableScoreCardLocalStore.baseKey,
        "personalStylistFeedbackLastPromptedAt",
        "personalStylistFeedbackFirstSessionSeen",
        "customerAccountEmail"
    ]

    static func migrateLegacyKeysIfNeeded(defaults: UserDefaults = .standard) {
        let userID = activeUserID(defaults: defaults)
        migrateLegacyData(from: legacyProfileKey, to: scopedKey(legacyProfileKey, userID: userID), defaults: defaults)
        migrateLegacyData(from: legacyMemoriesKey, to: scopedKey(legacyMemoriesKey, userID: userID), defaults: defaults)

        let scopedFeedbackKey = scopedKey(legacyFeedbackCountKey, userID: userID)
        if defaults.object(forKey: scopedFeedbackKey) == nil,
           defaults.object(forKey: legacyFeedbackCountKey) != nil {
            defaults.set(defaults.integer(forKey: legacyFeedbackCountKey), forKey: scopedFeedbackKey)
            defaults.removeObject(forKey: legacyFeedbackCountKey)
        }
    }

    private static func migrateLegacyData(from legacyKey: String, to scopedKey: String, defaults: UserDefaults) {
        guard defaults.object(forKey: scopedKey) == nil,
              let legacyData = defaults.data(forKey: legacyKey) else {
            return
        }

        defaults.set(legacyData, forKey: scopedKey)
        defaults.removeObject(forKey: legacyKey)
    }
}

enum AccountStorageEnvironment: String, CaseIterable {
    case production
    case staging
    case localAcceptance = "local-acceptance"

    static var current: AccountStorageEnvironment? {
        classification(for: StyleMatchRuntimeEndpoint.chatResolution())
    }

    static func classification(
        for resolution: StyleMatchRuntimeEndpointResolution?
    ) -> AccountStorageEnvironment? {
        guard let resolution else { return nil }
        if resolution.overrideActive { return .localAcceptance }
        switch resolution.baseURL.host?.lowercased() {
        case AppBackendConfiguration.approvedProductionAPIHost:
            return .production
        case AppBackendConfiguration.approvedStagingAPIHost:
            return .staging
        default:
            return nil
        }
    }
}

enum AccountScopedStorage {
    static let activeUserMarkerKey = "accountScopedActiveUserID"
    static let activeEnvironmentMarkerKey = "accountScopedActiveEnvironment"
    static let migrationVersionKey = "accountScopedStorageVersion"
    static let currentMigrationVersion = 2

    /// Existing screens continue using these shared presentation keys. At an
    /// account boundary they are snapshotted and restored under the destination
    /// user, preventing one local account from rendering another account's data.
    static let userDataKeys = [
        "profileName",
        "favoriteColors",
        "favoriteBrands",
        "favoriteStores",
        "shoppingBudget",
        "budget",
        "styleGoals",
        "preferredNeutrals",
        "preferredAccentColors",
        "comfortPreferences",
        "preferredPantRise",
        "shoppingFocus",
        "preferredShoppingCategories",
        "workSetting",
        "travelFrequency",
        "hobbiesActivities",
        "stylistVoice",
        "styleConsultationCompletedAt",
        "sizeProfile",
        "sizeCategory",
        "shirtSize",
        "pantsSize",
        "dressSize",
        "waistSize",
        "inseamLength",
        "neckSize",
        "sleeveLength",
        "shoeSize",
        "fitPreference",
        "preferredPantFit",
        "stylePreferences",
        "occasions",
        "plannedOccasion",
        "dressCode",
        "occasionFormality",
        "weather",
        "weatherCity",
        "weatherCondition",
        "weatherSource",
        "weatherLocation",
        "liveWeatherUpdatedAt",
        "weatherFeelsLike",
        "weatherRainChance",
        "weatherHumidity",
        "weatherWindSpeed",
        "weatherUVIndex",
        "weatherHourlyForecast",
        "weatherDailyForecast",
        "weatherAlert",
        "weatherErrorMessage",
        "pastPurchases",
        "fashionJournalCompliments",
        "favoriteOutfits",
        "outfitDislikes",
        "clothingPreferences",
        "closetInventory",
        "closetItemsData",
        "favoriteClosetItemIDs",
        "wishlistProductNamesData",
        "outfitScanHistoryData",
        "aiStylistConversationData",
        "aiStylistArchivedConversationsData",
        "aiInsightConversationData",
        "shareAppContextWithChatGPT",
        "hasSeenAIStylistWelcome",
        "openAIModel",
        "profileLastSavedAt",
        "profileNeedsCloudSync"
    ]

    static let sensitiveDeviceKeys = [
        "stylistChatDeviceHash",
        "stylistChatFallbackDeviceID",
        "shoppingPendingSaleProductID"
    ]

    static func sessionUserID(defaults: UserDefaults = .standard) -> String {
        let mode = defaults.string(forKey: "customerAccountMode") ?? "guest"
        guard mode == "apple",
              let appleUserID = defaults.string(forKey: "customerAppleUserID"),
              !appleUserID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "guest"
        }
        return PersonalStylistStorage.normalizedUserID(appleUserID)
    }

    static func activePresentationUserID(defaults: UserDefaults = .standard) -> String {
        PersonalStylistStorage.normalizedUserID(
            defaults.string(forKey: activeUserMarkerKey) ?? sessionUserID(defaults: defaults)
        )
    }

    static func activeEnvironment(defaults: UserDefaults = .standard) -> AccountStorageEnvironment {
        guard let rawValue = defaults.string(forKey: activeEnvironmentMarkerKey),
              let environment = AccountStorageEnvironment(rawValue: rawValue) else {
            // Version 1 snapshots predate environment isolation and are production data.
            return .production
        }
        return environment
    }

    /// Called before older launch migrations. Returning true means this launch
    /// captured legacy shared data and must restore it after those migrations.
    @discardableResult
    static func prepareForLaunch(
        defaults: UserDefaults = .standard,
        environment: AccountStorageEnvironment? = AccountStorageEnvironment.current
    ) -> Bool {
        guard let environment else { return false }
        let sessionUser = sessionUserID(defaults: defaults)
        let storedUser = PersonalStylistStorage.normalizedUserID(
            defaults.string(forKey: activeUserMarkerKey) ?? sessionUser
        )
        let hadEnvironmentMarker = defaults.string(forKey: activeEnvironmentMarkerKey) != nil
        let storedEnvironment = activeEnvironment(defaults: defaults)

        if !hadEnvironmentMarker {
            // Preserve the version 1 presentation and snapshots as production-only data.
            snapshotSharedData(for: storedUser, environment: .production, defaults: defaults)
            migrateLegacySnapshotToProduction(for: storedUser, defaults: defaults)
        }

        if storedUser == sessionUser, storedEnvironment == environment {
            defaults.set(sessionUser, forKey: activeUserMarkerKey)
            defaults.set(environment.rawValue, forKey: activeEnvironmentMarkerKey)
            defaults.set(currentMigrationVersion, forKey: migrationVersionKey)
            return !hadEnvironmentMarker && environment == .production
        }

        if hadEnvironmentMarker {
            snapshotSharedData(for: storedUser, environment: storedEnvironment, defaults: defaults)
        }
        clearSharedData(defaults: defaults)
        if environment == .production {
            migrateLegacySnapshotToProduction(for: sessionUser, defaults: defaults)
        }
        restoreSharedData(for: sessionUser, environment: environment, defaults: defaults)
        defaults.set(sessionUser, forKey: activeUserMarkerKey)
        defaults.set(environment.rawValue, forKey: activeEnvironmentMarkerKey)
        defaults.set(currentMigrationVersion, forKey: migrationVersionKey)
        return false
    }

    static func restoreCapturedLaunchData(
        defaults: UserDefaults = .standard,
        environment: AccountStorageEnvironment? = nil
    ) {
        let activeUser = defaults.string(forKey: activeUserMarkerKey) ?? sessionUserID(defaults: defaults)
        let resolvedEnvironment = environment ?? activeEnvironment(defaults: defaults)
        clearSharedData(defaults: defaults)
        restoreSharedData(for: activeUser, environment: resolvedEnvironment, defaults: defaults)
    }

    static func switchUser(
        from sourceUserID: String,
        to destinationUserID: String,
        transferSourceData: Bool,
        defaults: UserDefaults = .standard,
        environment: AccountStorageEnvironment? = AccountStorageEnvironment.current
    ) {
        guard let environment else { return }
        let source = PersonalStylistStorage.normalizedUserID(sourceUserID)
        let destination = PersonalStylistStorage.normalizedUserID(destinationUserID)
        guard source != destination else {
            defaults.set(destination, forKey: activeUserMarkerKey)
            defaults.set(environment.rawValue, forKey: activeEnvironmentMarkerKey)
            return
        }

        snapshotSharedData(for: source, environment: environment, defaults: defaults)
        if transferSourceData, !hasUserData(for: destination, defaults: defaults, environment: environment) {
            copySnapshot(from: source, to: destination, environment: environment, defaults: defaults)
            if environment == .production {
                PersonalStylistStorage.transferPersonalization(from: source, to: destination, defaults: defaults)
            }
        }

        clearSharedData(defaults: defaults)
        if environment == .production {
            migrateLegacySnapshotToProduction(for: destination, defaults: defaults)
        }
        restoreSharedData(for: destination, environment: environment, defaults: defaults)
        defaults.set(destination, forKey: activeUserMarkerKey)
        defaults.set(environment.rawValue, forKey: activeEnvironmentMarkerKey)
    }

    static func hasUserData(
        for userID: String,
        defaults: UserDefaults = .standard,
        environment: AccountStorageEnvironment? = AccountStorageEnvironment.current
    ) -> Bool {
        guard let environment else { return false }
        let normalized = PersonalStylistStorage.normalizedUserID(userID)
        if userDataKeys.contains(where: {
            defaults.object(forKey: snapshotKey($0, userID: normalized, environment: environment)) != nil
        }) {
            return true
        }

        guard environment == .production else { return false }
        return [
            PersonalStylistStorage.legacyProfileKey,
            PersonalStylistStorage.legacyMemoriesKey,
            ShoppingLocalStore.savedFavoritesBaseKey,
            ShoppingLocalStore.wishlistBaseKey
        ].contains { baseKey in
            defaults.object(forKey: PersonalStylistStorage.scopedKey(baseKey, userID: normalized)) != nil
        }
    }

    static func deleteUserData(
        for userID: String,
        defaults: UserDefaults = .standard,
        environment: AccountStorageEnvironment? = AccountStorageEnvironment.current
    ) {
        guard let environment else { return }
        let normalized = PersonalStylistStorage.normalizedUserID(userID)
        userDataKeys.forEach {
            defaults.removeObject(forKey: snapshotKey($0, userID: normalized, environment: environment))
        }
        if environment == .production {
            PersonalStylistStorage.deletePersonalization(for: normalized, defaults: defaults)
            ShoppingLocalStore.deleteShoppingData(for: normalized, defaults: defaults)
            ChatConversationStore.deleteAll(for: normalized)
        }

        if PersonalStylistStorage.normalizedUserID(defaults.string(forKey: activeUserMarkerKey) ?? "guest") == normalized,
           activeEnvironment(defaults: defaults) == environment {
            clearSharedData(defaults: defaults)
        }
    }

    static func deleteSensitiveDeviceState(defaults: UserDefaults = .standard) {
        sensitiveDeviceKeys.forEach { defaults.removeObject(forKey: $0) }
    }

    private static func snapshotSharedData(
        for userID: String,
        environment: AccountStorageEnvironment,
        defaults: UserDefaults
    ) {
        let normalized = PersonalStylistStorage.normalizedUserID(userID)
        for key in userDataKeys {
            let destination = snapshotKey(key, userID: normalized, environment: environment)
            if let value = defaults.object(forKey: key) {
                defaults.set(value, forKey: destination)
            } else {
                defaults.removeObject(forKey: destination)
            }
        }
    }

    private static func restoreSharedData(
        for userID: String,
        environment: AccountStorageEnvironment,
        defaults: UserDefaults
    ) {
        let normalized = PersonalStylistStorage.normalizedUserID(userID)
        for key in userDataKeys {
            if let value = defaults.object(forKey: snapshotKey(key, userID: normalized, environment: environment)) {
                defaults.set(value, forKey: key)
            }
        }
    }

    private static func clearSharedData(defaults: UserDefaults) {
        userDataKeys.forEach { defaults.removeObject(forKey: $0) }
    }

    private static func copySnapshot(
        from sourceUserID: String,
        to destinationUserID: String,
        environment: AccountStorageEnvironment,
        defaults: UserDefaults
    ) {
        for key in userDataKeys {
            let source = snapshotKey(key, userID: sourceUserID, environment: environment)
            let destination = snapshotKey(key, userID: destinationUserID, environment: environment)
            if let value = defaults.object(forKey: source) {
                defaults.set(value, forKey: destination)
            }
        }
    }

    private static func migrateLegacySnapshotToProduction(for userID: String, defaults: UserDefaults) {
        let normalized = PersonalStylistStorage.normalizedUserID(userID)
        for key in userDataKeys {
            let legacyKey = legacySnapshotKey(key, userID: normalized)
            let productionKey = snapshotKey(key, userID: normalized, environment: .production)
            if defaults.object(forKey: productionKey) == nil,
               let legacyValue = defaults.object(forKey: legacyKey) {
                defaults.set(legacyValue, forKey: productionKey)
            }
        }
    }

    static func snapshotKey(
        _ key: String,
        userID: String,
        environment: AccountStorageEnvironment
    ) -> String {
        PersonalStylistStorage.scopedKey("accountScoped.\(environment.rawValue).\(key)", userID: userID)
    }

    static func legacySnapshotKey(_ key: String, userID: String) -> String {
        PersonalStylistStorage.scopedKey("accountScoped.\(key)", userID: userID)
    }
}

enum LegacyProfileKeyMigration {
    static let migrationFlag = "didPurgeLegacyProfileKeys_v1_3"

    static let legacyGlobalProfileKeys = [
        "profileName",
        "favoriteColors",
        "favoriteBrands",
        "favoriteStores",
        "shoppingBudget",
        "budget",
        "styleGoals",
        "preferredNeutrals",
        "preferredAccentColors",
        "comfortPreferences",
        "preferredPantRise",
        "shoppingFocus",
        "preferredShoppingCategories",
        "workSetting",
        "travelFrequency",
        "hobbiesActivities",
        "stylistVoice",
        "styleConsultationCompletedAt",
        "sizeProfile",
        "sizeCategory",
        "shirtSize",
        "pantsSize",
        "dressSize",
        "waistSize",
        "inseamLength",
        "neckSize",
        "sleeveLength",
        "shoeSize",
        "fitPreference",
        "preferredPantFit",
        "stylePreferences",
        "occasions",
        "plannedOccasion",
        "dressCode",
        "occasionFormality",
        "pastPurchases",
        "favoriteOutfits",
        "outfitDislikes",
        "fashionJournalCompliments",
        "clothingPreferences",
        "closetInventory"
    ]

    static func run(defaults: UserDefaults = .standard) {
        guard defaults.bool(forKey: migrationFlag) == false else { return }

        for key in legacyGlobalProfileKeys {
            defaults.removeObject(forKey: key)
        }

        defaults.set(true, forKey: migrationFlag)
    }
}

enum StyleMatchAppLaunchMigrations {
    static func run(defaults: UserDefaults = .standard) {
        LegacyProfileKeyMigration.run(defaults: defaults)
    }
}
