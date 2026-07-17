// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StyleMatchProPhase2Verification",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "StyleMatchPro", targets: ["StyleMatchPro"])
    ],
    targets: [
        .target(
            name: "StyleMatchPro",
            path: "StyleMatchAI",
            exclude: [
                "AIProviderAdapters.swift",
                "AIAssistantsView.swift",
                "AIStyleAdvisor.swift",
                "Assets.xcassets",
                "BackendFeaturePlan.swift",
                "ChecklistView.swift",
                "ClosetView.swift",
                "ContentView.swift",
                "FashionKnowledgeBase.swift",
                "FeatureGate.swift",
                "HomeView.swift",
                "LoginWelcomeView.swift",
                "OnboardingView.swift",
                "OpenAIKeychain.swift",
                "OpenAIStylistClient.swift",
                "PrivacyInfo.xcprivacy",
                "PrivacyDataManager.swift",
                "ProfileView.swift",
                "PromptDetailView.swift",
                "RoadmapData.swift",
                "RoadmapView.swift",
                "ScanView.swift",
                "ShareableScoreCardViews.swift",
                "ShopView.swift",
                "Shopping/ShoppingPartnerEnvironment.example",
                "Shopping/StoreSearchView.swift",
                "StylistChat/StylistChatView.swift",
                "Shopping/ShoppingView.swift",
                "StyleMatchAI.entitlements",
                "StyleMatchAIApp.swift"
            ],
            sources: [
                "AccountService.swift",
                "AppBackendConfiguration.swift",
                "ShareableScoreCard.swift",
                "Models.swift",
                "GarmentColorPaletteEngine.swift",
                "WeatherContextEngine.swift",
                "Services/SpokenScriptBuilder.swift",
                "Services/VoiceStylistService.swift",
                "Shopping/AffiliateProduct.swift",
                "Shopping/ProductCatalogProvider.swift",
                "Shopping/ShoppingSearchProviders.swift",
                "Shopping/ShoppingRecommendationEngine.swift",
                "Shopping/DisplayLabelSanitizer.swift",
                "Shopping/RecommendationRationale.swift",
                "Shopping/RecommendationRationaleBuilder.swift",
                "Shopping/ProductComplementaryPieceRecommender.swift",
                "Shopping/ShoppingTabUpgradeNotes.swift",
                "Shopping/ShoppingLocalStore.swift",
                "Shopping/ShoppingSaleAlertService.swift",
                "Shopping/SaleWatcher.swift",
                "Shopping/ShoppingSearchEngine.swift",
                "PersonalStylist/StylistProfileModels.swift",
                "PersonalStylist/PersonalStylistStorage.swift",
                "PersonalStylist/ProfileStore.swift",
                "PersonalStylist/OutfitMemoryStore.swift",
                "PersonalStylist/PersonalStylistSnapshotStore.swift",
                "PersonalStylist/PersonalStylistAIContext.swift",
                "PersonalStylist/StylistContextBuilder.swift",
                "PersonalStylist/FeedbackPromptScheduler.swift",
                "PersonalStylist/PersonalStylistEngines.swift",
                "PersonalStylist/StylistMessageComposer.swift",
                "PersonalStylist/ScanNarrativeConsistency.swift",
                "PersonalStylist/OutfitRecallService.swift",
                "PersonalStylist/SaleMatchingService.swift",
                "PersonalStylist/WeatherAdvisor.swift",
                "PersonalStylist/PersonalStylistEngine.swift",
                "PersonalStylist/PersonalStylistIntelligence.swift",
                "PersonalStylist/PersonalStylistPhase2Diagnostics.swift",
                "StylistChat/StylistChatModels.swift",
                "StylistChat/ChatConversationStore.swift",
                "StylistChat/StylistChatTransport.swift",
                "StylistChat/StylistChatService.swift",
                "StylistChat/StylistSpeechInputService.swift",
                "VoiceAssistant/VoiceScript.swift",
                "VoiceAssistant/VoiceScriptBuilder.swift",
                "VoiceAssistant/VoiceAssistantService.swift"
            ],
            resources: [
                .copy("Shopping/ProductCatalog.json"),
                .copy("Shopping/RetailerConfig.json"),
                .copy("Shopping/SupportedStores.json"),
                .copy("Shopping/ShoppingRuntimeConfig.json")
            ]
        ),
        .testTarget(
            name: "StyleMatchProPhase2Tests",
            dependencies: ["StyleMatchPro"],
            path: "StyleMatchProPhase2Tests",
            resources: [
                .copy("Fixtures/mock_deals.json"),
                .copy("Fixtures/amazon_paapi_response.json"),
                .copy("Fixtures/impact_response.json"),
                .copy("Fixtures/cj_response.json"),
                .copy("Fixtures/rakuten_response.json"),
                .copy("Fixtures/sovrn_response.json")
            ]
        )
    ]
)
