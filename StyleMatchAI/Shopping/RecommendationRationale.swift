import Foundation

struct ShoppingRecommendationPreferences: Codable, Equatable {
    var usesWardrobeHistory: Bool
    var usesFavoriteBrands: Bool
    var usesFavoriteColors: Bool
    var usesBudgetRange: Bool
    var usesCurrentTrends: Bool
    var usesWeather: Bool
    var usesCalendarEvents: Bool

    static let `default` = ShoppingRecommendationPreferences(
        usesWardrobeHistory: true,
        usesFavoriteBrands: true,
        usesFavoriteColors: true,
        usesBudgetRange: true,
        usesCurrentTrends: true,
        usesWeather: false,
        usesCalendarEvents: false
    )
}

struct RecommendationRationale: Equatable {
    enum Reason: String, CaseIterable, Equatable {
        case matchesWardrobe
        case matchesColors
        case matchesStyle
        case onSaleToday
        case similarToLiked

        var displayText: String {
            switch self {
            case .matchesWardrobe: return "Matches your wardrobe"
            case .matchesColors: return "Matches your preferred colors"
            case .matchesStyle: return "Matches your style"
            case .onSaleToday: return "On sale today"
            case .similarToLiked: return "Similar to items you've liked"
            }
        }
    }

    let reasons: [Reason]
    let headline: String

    var isTrendingFallback: Bool {
        reasons.isEmpty
    }
}
