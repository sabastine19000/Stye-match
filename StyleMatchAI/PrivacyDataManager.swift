import Foundation

enum StyleMatchDataKey: String, CaseIterable {
    case hasCompletedOnboarding
    case hasChosenAccessMode
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
    case weatherSource
    case weatherLocation
    case liveWeatherUpdatedAt
    case weatherFeelsLike
    case weatherRainChance
    case weatherHumidity
    case weatherWindSpeed
    case weatherUVIndex
    case weatherHourlyForecast
    case weatherDailyForecast
    case weatherAlert
    case weatherErrorMessage
    case pastPurchases
    case fashionJournalCompliments
    case favoriteOutfits
    case outfitDislikes
    case clothingPreferences
    case closetInventory
    case closetItemsData
    case favoriteClosetItemIDs
    case wishlistProductNamesData
    case preferredAIAssistant
    case connectedAIAssistants
    case openAIModel
    case openAIAPIKeyForBetaTesting
    case shareAppContextWithChatGPT
    case hasSeenAIStylistWelcome
    case aiStylistConversationData
    case aiStylistArchivedConversationsData
    case aiInsightConversationData
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
    case guestDataLinkedToApple
    case guestDataTransferSummary
    case voiceAssistantEnabled
    case voiceAssistantVoiceIdentifier
    case voiceAssistantSpeechRate
    case voiceStylistDefaultVoiceHintDismissed
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
        AccountScopedStorage.deleteUserData(for: activeUserID, defaults: defaults)
        AccountScopedStorage.deleteSensitiveDeviceState(defaults: defaults)
        for key in StyleMatchDataKey.allCases {
            defaults.removeObject(forKey: key.rawValue)
        }
        defaults.removeObject(forKey: PersonalStylistStorage.legacyProfileKey)
        defaults.removeObject(forKey: PersonalStylistStorage.legacyMemoriesKey)
        defaults.removeObject(forKey: PersonalStylistStorage.legacyFeedbackCountKey)
        defaults.set("guest", forKey: AccountScopedStorage.activeUserMarkerKey)
        try? OpenAIKeychain.deleteAPIKey()
    }

    func privacyNotes(for feature: StyleMatchFeature) -> String {
        StyleMatchBackendPlan.featureSpecs.first { $0.id == feature }?.privacyNotes ?? StyleMatchPrivacyMode.localFirstSummary
    }
}
