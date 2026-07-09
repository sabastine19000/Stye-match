import Combine
import Foundation
import SwiftUI

enum StyleMatchFeature: String, CaseIterable {
    case guestMode
    case signInWithApple
    case emailPasswordAuth
    case outfitScan
    case multiSurfaceClothingScan
    case skinAwareStyling
    case closet
    case aiAssistantChoice
    case trustedRetailerLinks
    case personalizedShopping
    case priceComparison
    case smartWishlist
    case aiPersonalShopper
    case inAppCheckout
    case orderTracking
    case budgetTracking
    case wardrobeOrganization
    case travelPacking
    case calendarPlanning
    case weatherRecommendations
    case fashionAnalytics
    case styleProgressReports
    case completeFashionPlatform
    case retailerAPI
    case paymentAPI
}

enum StyleMatchReleaseChannel {
    case customerPublic
    case founderBeta
}

enum StyleMatchBuildSettings {
    // Internal/TestFlight founder build exposes private beta setup tools.
    // Switch back to .customerPublic before wide release.
    #if DEBUG
    static let releaseChannel: StyleMatchReleaseChannel = .founderBeta
    #else
    static let releaseChannel: StyleMatchReleaseChannel = .customerPublic
    #endif

    static var allowsLocalFounderAPIKey: Bool {
        #if DEBUG
        releaseChannel == .founderBeta
        #else
        false
        #endif
    }

    static var requiresBackendAIProxy: Bool {
        releaseChannel == .customerPublic
    }
}

private struct StyleMatchOnChangeModifier<Value: Equatable>: ViewModifier {
    let value: Value
    let action: (Value) -> Void
    @State private var previousValue: Value?

    func body(content: Content) -> some View {
        content.onReceive(Just(value)) { newValue in
            defer { previousValue = newValue }
            guard let previousValue, previousValue != newValue else { return }
            action(newValue)
        }
    }
}

extension View {
    @ViewBuilder
    func styleMatchOnChange<Value: Equatable>(
        of value: Value,
        perform action: @escaping (Value) -> Void
    ) -> some View {
        if #available(iOS 17.0, *) {
            self.onChange(of: value) { _, newValue in
                action(newValue)
            }
        } else {
            self.modifier(StyleMatchOnChangeModifier(value: value, action: action))
        }
    }
}

struct FeatureGate {
    static let shared = FeatureGate()

    private let customerVisibleFeatures: Set<StyleMatchFeature> = [
        .guestMode,
        .signInWithApple,
        .outfitScan,
        .multiSurfaceClothingScan,
        .skinAwareStyling,
        .closet,
        .aiAssistantChoice,
        .trustedRetailerLinks,
        .personalizedShopping
    ]

    private let apiReadyFeatures: Set<StyleMatchFeature> = [
        .emailPasswordAuth,
        .priceComparison,
        .smartWishlist,
        .aiPersonalShopper,
        .budgetTracking,
        .wardrobeOrganization,
        .travelPacking,
        .calendarPlanning,
        .weatherRecommendations,
        .fashionAnalytics,
        .styleProgressReports,
        .completeFashionPlatform,
        .retailerAPI
    ]

    func isCustomerVisible(_ feature: StyleMatchFeature) -> Bool {
        switch StyleMatchBuildSettings.releaseChannel {
        case .customerPublic:
            return customerVisibleFeatures.contains(feature)
        case .founderBeta:
            return customerVisibleFeatures.contains(feature) || apiReadyFeatures.contains(feature)
        }
    }

    func isPreparedForAPI(_ feature: StyleMatchFeature) -> Bool {
        customerVisibleFeatures.contains(feature) || apiReadyFeatures.contains(feature)
    }
}

struct StyleMatchAPIPlan {
    static let shared = StyleMatchAPIPlan()

    let baseURL = "https://api.stylematchpro.com/v1"

    func endpoint(for feature: StyleMatchFeature) -> String {
        switch feature {
        case .guestMode:
            return "/auth/guest"
        case .signInWithApple:
            return "/auth/apple"
        case .emailPasswordAuth:
            return "/auth/email"
        case .outfitScan:
            return "/scan/outfit"
        case .multiSurfaceClothingScan:
            return "/scan/clothing-surfaces"
        case .skinAwareStyling:
            return "/styling/skin-aware-color"
        case .closet:
            return "/closet/items"
        case .aiAssistantChoice:
            return "/assistants/preference"
        case .trustedRetailerLinks:
            return "/retailers/trusted-links"
        case .personalizedShopping:
            return "/shopping/personalized"
        case .priceComparison:
            return "/shopping/price-comparison"
        case .smartWishlist:
            return "/wishlist"
        case .aiPersonalShopper:
            return "/stylist/outfit-builder"
        case .inAppCheckout:
            return "/checkout"
        case .orderTracking:
            return "/orders/tracking"
        case .budgetTracking:
            return "/budget/tracking"
        case .wardrobeOrganization:
            return "/closet/organization"
        case .travelPacking:
            return "/planning/travel-packing"
        case .calendarPlanning:
            return "/planning/calendar"
        case .weatherRecommendations:
            return "/recommendations/weather"
        case .fashionAnalytics:
            return "/analytics/fashion"
        case .styleProgressReports:
            return "/reports/style-progress"
        case .completeFashionPlatform:
            return "/platform"
        case .retailerAPI:
            return "/retailers/integrations"
        case .paymentAPI:
            return "/payments/secure"
        }
    }
}

enum CustomerAccountMode: String, CaseIterable, Identifiable {
    case guest = "Guest"
    case apple = "Sign in with Apple"
    case email = "Email and Password"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .guest:
            return "Use Style Match Pro without creating an account. Data stays on this phone unless a cloud feature is needed."
        case .apple:
            return "Recommended for customers who want private account sign-in, cloud sync, wishlist, and future order history."
        case .email:
            return "Prepared for later. Email and password should launch after account security, reset flows, and privacy review are finished."
        }
    }

    var isAvailableNow: Bool {
        switch self {
        case .guest, .apple:
            return true
        case .email:
            return false
        }
    }
}

enum PreferredAIAssistant: String, CaseIterable, Identifiable {
    case siri = "Siri"
    case chatGPT = "ChatGPT"
    case gemini = "Gemini"
    case claude = "Claude"
    case perplexity = "Perplexity"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .siri:
            return "Use Apple's assistant experience for quick voice-first help."
        case .chatGPT:
            return "Use ChatGPT for conversational outfit advice, styling ideas, and personalized fashion answers."
        case .gemini:
            return "Use Google's assistant experience for broad research and style ideas."
        case .claude:
            return "Use Claude for careful explanations and polished outfit guidance."
        case .perplexity:
            return "Use Perplexity for answer-focused shopping and comparison research."
        }
    }

    var apiProviderKey: String {
        switch self {
        case .siri:
            return "apple_siri"
        case .chatGPT:
            return "openai_chatgpt"
        case .gemini:
            return "google_gemini"
        case .claude:
            return "anthropic_claude"
        case .perplexity:
            return "perplexity"
        }
    }
}

struct AssistantIntegrationPlan {
    static let shared = AssistantIntegrationPlan()

    func endpoint(for assistant: PreferredAIAssistant) -> String {
        "\(StyleMatchAPIPlan.shared.baseURL)/assistants/\(assistant.apiProviderKey)"
    }
}
