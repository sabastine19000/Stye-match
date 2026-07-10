import Foundation

enum StyleMatchDataKey: String, CaseIterable {
    case hasCompletedOnboarding
    case customerAccountMode
    case customerAccountEmail
    case customerAppleUserID
    case customerAccountSyncEnabled
    case profileName
    case favoriteColors
    case favoriteBrands
    case favoriteStores
    case shoppingBudget
    case sizeProfile
    case sizeCategory
    case shirtSize
    case pantsSize
    case dressSize
    case waistSize
    case inseamLength
    case neckSize
    case sleeveLength
    case shoeSize
    case fitPreference
    case stylePreferences
    case occasions
    case plannedOccasion
    case dressCode
    case occasionFormality
    case weather
    case weatherCity
    case weatherCondition
    case pastPurchases
    case fashionJournalCompliments
    case favoriteOutfits
    case outfitDislikes
    case clothingPreferences
    case closetInventory
    case closetItemsData
    case wishlistProductNamesData
    case preferredAIAssistant
    case connectedAIAssistants
    case openAIModel
    case openAIAPIKeyForBetaTesting
    case shareAppContextWithChatGPT
    case outfitScanHistoryData
    case shoppingRecentlyViewedProductIDs
    case shoppingDismissedProductIDs
    case shoppingSavedFavoriteProductIDs
    case shoppingWishlistProductIDs
    case shoppingCartProductIDs
    case shoppingCardProductIDs
    case shoppingSaleNotificationsEnabled
    case shoppingSaleStateSnapshots
    case shoppingLastKnownSaleState
    case shoppingNotifiedSalePairs
    case shoppingSaleNotificationHistory
    case shoppingRecentSaleEvents
    case shoppingViewedSaleEventIDs
    case profileLastSavedAt
    case profileNeedsCloudSync
}

enum StyleMatchPrivacyMode {
    static let localFirstSummary = "Style Match Pro processes data on the phone first. Guest users can use the app without an account. Cloud assistance is used only when the iPhone cannot complete the request locally or when a feature needs live retailer, payment, notification, account sync, or order data."

    static let cloudMinimumRule = "When cloud help is needed, send only the minimum information required for that request."

    static let deletionRule = "Customers can delete saved account choice, profile, assistant, closet, wishlist, and scan-history data from the phone anytime."
}

struct PrivacyDataManager {
    static let shared = PrivacyDataManager()

    func deleteAllLocalCustomerData(defaults: UserDefaults = .standard) {
        let activeUserID = PersonalStylistStorage.activeUserID(defaults: defaults)
        ChatConversationStore().deleteAll()
        for key in StyleMatchDataKey.allCases {
            defaults.removeObject(forKey: key.rawValue)
        }
        PersonalStylistStorage.deletePersonalization(for: activeUserID, defaults: defaults)
        ShoppingLocalStore.deleteShoppingData(for: activeUserID, defaults: defaults)
        defaults.removeObject(forKey: PersonalStylistStorage.legacyProfileKey)
        defaults.removeObject(forKey: PersonalStylistStorage.legacyMemoriesKey)
        defaults.removeObject(forKey: PersonalStylistStorage.legacyFeedbackCountKey)
        try? OpenAIKeychain.deleteAPIKey()
    }

    func privacyNotes(for feature: StyleMatchFeature) -> String {
        StyleMatchBackendPlan.featureSpecs.first { $0.id == feature }?.privacyNotes ?? StyleMatchPrivacyMode.localFirstSummary
    }
}
