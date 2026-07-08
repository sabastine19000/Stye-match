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
            scopedKey(ShoppingLocalStore.saleNotificationsEnabledBaseKey, userID: userID),
            scopedKey(ShoppingLocalStore.saleStateSnapshotsBaseKey, userID: userID),
            scopedKey(ShoppingLocalStore.lastKnownSaleStateBaseKey, userID: userID),
            scopedKey(ShoppingLocalStore.notifiedSalePairsBaseKey, userID: userID),
            scopedKey(ShoppingLocalStore.saleNotificationHistoryBaseKey, userID: userID),
            scopedKey(ShoppingLocalStore.recentSaleEventsBaseKey, userID: userID),
            scopedKey(ShoppingLocalStore.viewedSaleEventIDsBaseKey, userID: userID)
        ] {
            defaults.removeObject(forKey: key)
        }
        PersonalStylistSnapshotStore.deleteData(store: "StylistProfile", userID: userID)
        PersonalStylistSnapshotStore.deleteData(store: "OutfitMemoryStore", userID: userID)
    }

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

enum LegacyProfileKeyMigration {
    static let migrationFlag = "didPurgeLegacyProfileKeys_v1_3"

    static let legacyGlobalProfileKeys = [
        "profileName",
        "favoriteColors",
        "favoriteBrands",
        "favoriteStores",
        "shoppingBudget",
        "budget",
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
