import Foundation

enum FeatureReleaseStage: String {
    case publicNow
    case apiPrepared
    case internalTesting
    case futureRelease
}

enum ProcessingLocation: String {
    case onDevice
    case cloudOnlyWhenNeeded
    case secureCloudRequired
}

struct BackendFeatureSpec: Identifiable {
    let id: StyleMatchFeature
    let title: String
    let stage: FeatureReleaseStage
    let processingLocation: ProcessingLocation
    let endpoint: String
    let customerDataUsed: [String]
    let privacyNotes: String
}

enum StyleMatchBackendPlan {
    static let releaseRule = "Build one major feature at a time, test it fully, protect customer privacy, and release only when reliable."

    static let outfitOccasions = [
        "Work",
        "Business meeting",
        "Church",
        "Wedding",
        "Funeral",
        "Graduation",
        "Birthday party",
        "Date night",
        "Casual",
        "Vacation",
        "Beach",
        "Cruise",
        "Gym",
        "Hiking",
        "Camping",
        "Concert",
        "Sporting event",
        "Holiday",
        "Thanksgiving",
        "Christmas",
        "New Year's Eve",
        "Valentine's Day",
        "Interview",
        "Networking event",
        "Family gathering",
        "Baby shower",
        "Bridal shower",
        "Photoshoot",
        "Airport travel",
        "Rainy day",
        "Winter",
        "Summer",
        "Spring",
        "Fall"
    ]

    static let featureSpecs: [BackendFeatureSpec] = [
        BackendFeatureSpec(
            id: .guestMode,
            title: "Guest Mode",
            stage: .publicNow,
            processingLocation: .onDevice,
            endpoint: StyleMatchAPIPlan.shared.endpoint(for: .guestMode),
            customerDataUsed: ["Local style profile", "Local scan history"],
            privacyNotes: "Customers can use the app without a username or password. Keep guest data on device unless a cloud-only feature is requested."
        ),
        BackendFeatureSpec(
            id: .signInWithApple,
            title: "Sign in with Apple",
            stage: .apiPrepared,
            processingLocation: .cloudOnlyWhenNeeded,
            endpoint: StyleMatchAPIPlan.shared.endpoint(for: .signInWithApple),
            customerDataUsed: ["Apple user identifier", "Optional account sync preference"],
            privacyNotes: "Recommended account path. Use Apple private relay support where available and request only the minimum account information."
        ),
        BackendFeatureSpec(
            id: .emailPasswordAuth,
            title: "Email and Password Account",
            stage: .futureRelease,
            processingLocation: .secureCloudRequired,
            endpoint: StyleMatchAPIPlan.shared.endpoint(for: .emailPasswordAuth),
            customerDataUsed: ["Email address", "Encrypted authentication credentials"],
            privacyNotes: "Do not release until password reset, rate limits, encryption, account deletion, and privacy policy language are complete."
        ),
        BackendFeatureSpec(
            id: .outfitScan,
            title: "AI Outfit Scan",
            stage: .publicNow,
            processingLocation: .onDevice,
            endpoint: StyleMatchAPIPlan.shared.endpoint(for: .outfitScan),
            customerDataUsed: ["Selected outfit photo", "Saved style profile"],
            privacyNotes: "Analyze on device first. Send to cloud only if local detection cannot complete the request."
        ),
        BackendFeatureSpec(
            id: .multiSurfaceClothingScan,
            title: "Multi-Surface Clothing Scan",
            stage: .publicNow,
            processingLocation: .onDevice,
            endpoint: StyleMatchAPIPlan.shared.endpoint(for: .multiSurfaceClothingScan),
            customerDataUsed: ["Selected clothing photo", "Detected clothing scene"],
            privacyNotes: "Accept clothing on people, mannequins, beds, hangers, in bags, and clear item-only photos. Analyze on device first."
        ),
        BackendFeatureSpec(
            id: .skinAwareStyling,
            title: "Skin-Aware Styling",
            stage: .apiPrepared,
            processingLocation: .onDevice,
            endpoint: StyleMatchAPIPlan.shared.endpoint(for: .skinAwareStyling),
            customerDataUsed: ["Visible photo colors only"],
            privacyNotes: "Use visible color harmony only. Do not identify race, ethnicity, or sensitive personal traits."
        ),
        BackendFeatureSpec(
            id: .personalizedShopping,
            title: "Personalized AI Shopping",
            stage: .publicNow,
            processingLocation: .cloudOnlyWhenNeeded,
            endpoint: StyleMatchAPIPlan.shared.endpoint(for: .personalizedShopping),
            customerDataUsed: ["Favorite colors", "Favorite brands", "Budget", "Sizes", "Past purchases", "Favorite outfits", "Weather", "Occasion", "Closet inventory", "Approved affiliate product catalog"],
            privacyNotes: "Use profile and closet data to avoid random recommendations. Return only approved affiliate product records with product name, image URL, price, sale alert, retailer name, category, affiliate URL, and tracking ID. StyleMatch Pro recommends and links out; approved retailers handle checkout, payment, fulfillment, shipping, refunds, returns, and customer service."
        ),
        BackendFeatureSpec(
            id: .trustedRetailerLinks,
            title: "Affiliate Retailer Marketplace",
            stage: .publicNow,
            processingLocation: .cloudOnlyWhenNeeded,
            endpoint: StyleMatchAPIPlan.shared.endpoint(for: .trustedRetailerLinks),
            customerDataUsed: ["Selected product", "Retailer name", "Affiliate URL", "Affiliate tracking ID", "Product image URL", "Product category", "Current price", "Sale alert"],
            privacyNotes: "Open approved retailer purchase pages such as Nike, Macy's, Best Buy, Amazon, and other affiliate partners. Do not process payments, hold inventory, ship orders, manage returns, or present StyleMatch Pro as the seller."
        ),
        BackendFeatureSpec(
            id: .priceComparison,
            title: "Price Comparison",
            stage: .apiPrepared,
            processingLocation: .secureCloudRequired,
            endpoint: StyleMatchAPIPlan.shared.endpoint(for: .priceComparison),
            customerDataUsed: ["Budget", "Preferred brands", "Sizes", "Selected product category", "Approved retailer catalog", "Affiliate tracking IDs"],
            privacyNotes: "Cloud required to search multiple retailers. Send only the minimum shopping request. Compare affiliate product records without creating a StyleMatch cart or payment flow."
        ),
        BackendFeatureSpec(
            id: .smartWishlist,
            title: "Smart Wishlist",
            stage: .apiPrepared,
            processingLocation: .cloudOnlyWhenNeeded,
            endpoint: StyleMatchAPIPlan.shared.endpoint(for: .smartWishlist),
            customerDataUsed: ["Saved wishlist products", "Size preference", "Color preference"],
            privacyNotes: "Wishlist can stay local. Cloud notifications are optional for price drops, color availability, and restocks."
        ),
        BackendFeatureSpec(
            id: .aiPersonalShopper,
            title: "AI Personal Shopper",
            stage: .apiPrepared,
            processingLocation: .cloudOnlyWhenNeeded,
            endpoint: StyleMatchAPIPlan.shared.endpoint(for: .aiPersonalShopper),
            customerDataUsed: ["Virtual Closet", "Budget", "Sizes", "Weather", "Occasion", "Favorite colors", "Style preferences"],
            privacyNotes: "Check closet first, use owned clothing first, recommend only missing items, and explain every choice."
        ),
        BackendFeatureSpec(
            id: .inAppCheckout,
            title: "In-App Shopping",
            stage: .futureRelease,
            processingLocation: .secureCloudRequired,
            endpoint: StyleMatchAPIPlan.shared.endpoint(for: .inAppCheckout),
            customerDataUsed: ["Selected product", "Size", "Color", "Retailer order details"],
            privacyNotes: "Not part of the first affiliate marketplace release. Requires secure payment, order, tax, fraud, fulfillment, refund, return, customer service, and retailer integration review before any release. Do not store payment data in the app."
        ),
        BackendFeatureSpec(
            id: .orderTracking,
            title: "Order Tracking",
            stage: .futureRelease,
            processingLocation: .secureCloudRequired,
            endpoint: StyleMatchAPIPlan.shared.endpoint(for: .orderTracking),
            customerDataUsed: ["Retailer order ID", "Order status", "Delivery estimate"],
            privacyNotes: "Show tracking from retailer systems. Keep order data minimal."
        ),
        BackendFeatureSpec(
            id: .completeFashionPlatform,
            title: "Complete AI Fashion Platform",
            stage: .futureRelease,
            processingLocation: .cloudOnlyWhenNeeded,
            endpoint: StyleMatchAPIPlan.shared.endpoint(for: .completeFashionPlatform),
            customerDataUsed: ["Closet", "Outfit plans", "Wishlist", "Budget", "Calendar occasions", "Weather", "Shopping history"],
            privacyNotes: "Release feature by feature after testing and privacy review."
        )
    ]
}
