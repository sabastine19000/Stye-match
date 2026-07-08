import Foundation

enum RoadmapData {
    static let buildPhases: [BuildPhase] = [
        BuildPhase(title: "App Foundation", description: "Create the SwiftUI app structure, tabs, reusable screens, and mock data."),
        BuildPhase(title: "Version 1.0", description: "Add the core outfit scan and outfit result experience."),
        BuildPhase(title: "Version 1.1", description: "Add user profile, style preferences, sizes, budget, and saved settings."),
        BuildPhase(title: "Version 1.2", description: "Add the Virtual Closet so users can save clothing they already own."),
        BuildPhase(title: "Version 2.3", description: "Add AI clothing recommendations without shopping links."),
        BuildPhase(title: "Version 2.4", description: "Add trusted retailer product matching and external product links."),
        BuildPhase(title: "Version 2.5", description: "Personalize shopping by profile, closet, size, budget, and style."),
        BuildPhase(title: "Version 2.6", description: "Compare prices across retailers and highlight best value."),
        BuildPhase(title: "Version 2.7", description: "Add smart wishlist, sharing, and price-drop notification logic."),
        BuildPhase(title: "Version 2.8", description: "Add AI Personal Shopper for complete occasion-based outfits."),
        BuildPhase(title: "Version 2.9", description: "Review future private checkout only after the affiliate marketplace is proven."),
        BuildPhase(title: "Version 3.0", description: "Unify everything into a complete AI fashion platform.")
    ]

    static let versions: [RoadmapVersion] = [
        RoadmapVersion(
            title: "App Foundation",
            version: "Foundation",
            goal: "Build the first clean iOS app structure for Style Match Pro.",
            features: [
                "Home tab",
                "Roadmap tab",
                "Checklist tab",
                "Profile tab",
                "Reusable SwiftUI views",
                "Mock roadmap data"
            ],
            prompt: """
Build the foundation for a mobile app called Style Match Pro.

Create a clean, scalable app structure with Home, Scan, Closet, Shop, and Profile sections. Use mock data first. Keep the first version simple and reliable.
""",
            acceptanceTests: [
                "App launches successfully.",
                "Tabs work.",
                "All starter screens render.",
                "No blank screens.",
                "No broken imports."
            ]
        ),
        RoadmapVersion(
            title: "Core Outfit Scan Experience",
            version: "1.0",
            goal: "Let users scan or upload an outfit photo and receive an AI-style result.",
            features: [
                "Photo upload",
                "Loading state",
                "Outfit score",
                "Color match rating",
                "Occasion fit rating",
                "Style balance rating",
                "Improvement suggestions"
            ],
            prompt: """
Add the first real Style Match Pro user flow: outfit scan and outfit result.

The user should upload or take an outfit photo, see an analyzing state, then receive an outfit score, ratings, notes, and three improvement suggestions.

Use mocked AI results for now.
""",
            acceptanceTests: [
                "User can select an image.",
                "Result screen shows the selected image.",
                "Mock analysis renders correctly.",
                "App does not crash if image selection is canceled."
            ]
        ),
        RoadmapVersion(
            title: "User Profile And Preferences",
            version: "1.1",
            goal: "Save the user's style profile so recommendations can become personal.",
            features: [
                "Name",
                "Favorite colors",
                "Avoided colors",
                "Favorite brands",
                "Budget",
                "Clothing sizes",
                "Typical occasions",
                "Location"
            ],
            prompt: """
Add a Style Profile system to Style Match Pro.

Users should save favorite colors, avoided colors, brands, sizes, budget, style preferences, occasions, and location. Persist the profile locally.
""",
            acceptanceTests: [
                "User can edit and save profile.",
                "Profile persists after restart.",
                "Recommendations change based on preferences.",
                "Empty profile state works."
            ]
        ),
        RoadmapVersion(
            title: "Virtual Closet",
            version: "1.2",
            goal: "Let users save clothing they already own.",
            features: [
                "Add clothing item",
                "Upload item photo",
                "Category",
                "Brand",
                "Color",
                "Size",
                "Season",
                "Occasion",
                "Closet filters"
            ],
            prompt: """
Add a Virtual Closet feature.

Users should add clothing items with photos, category, brand, color, size, season, occasion, and notes. Show closet items in a clean grid and allow filtering.
""",
            acceptanceTests: [
                "User can add a closet item.",
                "Closet item photo displays.",
                "Filters work.",
                "Closet persists after restart.",
                "Recommendations check closet first."
            ]
        ),
        RoadmapVersion(
            title: "AI Clothing Recommendations",
            version: "2.3",
            goal: "Recommend outfit improvements without selling anything yet.",
            features: [
                "Shoes",
                "Shirts",
                "Pants",
                "Jackets",
                "Dresses",
                "Watches",
                "Belts",
                "Jewelry",
                "Handbags",
                "Hats"
            ],
            prompt: """
Add AI Clothing Recommendations.

Analyze the user's outfit result and recommend pieces that would improve the outfit. Explain why each recommendation improves color balance, occasion fit, or style. Do not include product links, prices, stores, or checkout yet.
""",
            acceptanceTests: [
                "Recommendations are specific.",
                "Explanations are helpful.",
                "Different profiles receive different recommendations.",
                "Closet items are checked first."
            ]
        ),
        RoadmapVersion(
            title: "Retail Store Integration",
            version: "2.4",
            goal: "Let users shop recommended items from trusted retailers.",
            features: [
                "Shop Recommendation button",
                "Product image",
                "Price",
                "Sale alert",
                "Sizes",
                "Colors",
                "Retailer name",
                "External retailer link",
                "Affiliate URL",
                "Affiliate tracking ID",
                "Sold and shipped by retailer disclosure"
            ],
            prompt: """
Add Retail Store Integration.

For each recommendation, add a Shop Recommendation button. Show product cards from trusted retailers such as Macy's, Nordstrom, Bloomingdale's, Saks Fifth Avenue, Neiman Marcus, Dillard's, Ralph Lauren, Nike, Adidas, Levi's, Tommy Hilfiger, and Calvin Klein.

Build this as an affiliate marketplace. StyleMatch Pro recommends products and opens approved retailer purchase pages. Do not build payment processing, order submission, inventory ownership, fulfillment, returns, refunds, or customer service handling yet.
""",
            acceptanceTests: [
                "Shop buttons appear.",
                "Product cards load.",
                "Retailer links open.",
                "Loading failures show fallback UI.",
                "No payment code is added.",
                "Cards clearly say sold and shipped by the retailer."
            ]
        ),
        RoadmapVersion(
            title: "Personalized AI Shopping",
            version: "2.5",
            goal: "Recommend products based on the user's profile, closet, budget, and size.",
            features: [
                "Favorite colors",
                "Favorite brands",
                "Budget",
                "Clothing sizes",
                "Past purchases",
                "Favorite outfits",
                "Weather",
                "Occasion",
                "Closet inventory"
            ],
            prompt: """
Add Personalized AI Shopping.

Use the user's profile and closet to filter and rank products by size, budget, brand, color, style, occasion, and weather.
""",
            acceptanceTests: [
                "Different users see different product rankings.",
                "Wrong sizes are deprioritized.",
                "Above-budget products are marked.",
                "Favorite brands rank higher."
            ]
        ),
        RoadmapVersion(
            title: "Price Comparison",
            version: "2.6",
            goal: "Help users find the best value across retailers.",
            features: [
                "Lowest price",
                "Sale price",
                "Original price",
                "Shipping cost",
                "Estimated delivery",
                "Best value badge"
            ],
            prompt: """
Add Price Comparison.

Compare the same or similar item across multiple retailers. Highlight best value based on price, shipping, delivery speed, size availability, return policy, and user preference match.
""",
            acceptanceTests: [
                "Multiple retailer options display.",
                "Lowest price is visible.",
                "Best value has an explanation.",
                "Missing shipping data does not crash."
            ]
        ),
        RoadmapVersion(
            title: "Smart Wishlist",
            version: "2.7",
            goal: "Let users save products and track future buying opportunities.",
            features: [
                "Save to Wishlist",
                "Multiple wishlists",
                "Price drop logic",
                "Restock logic",
                "New color logic",
                "Sharing"
            ],
            prompt: """
Add Smart Wishlist.

Users should save products, organize wishlists, remove items, share wishlists, and prepare notification logic for price drops, new colors, and size restocks.
""",
            acceptanceTests: [
                "Products save to wishlist.",
                "Wishlist persists.",
                "Items can be removed.",
                "Sharing opens.",
                "Notification service is isolated."
            ]
        ),
        RoadmapVersion(
            title: "AI Personal Shopper",
            version: "2.8",
            goal: "Build complete outfits for real-life situations.",
            features: [
                "Work",
                "Business meeting",
                "Church",
                "Wedding",
                "Funeral",
                "Graduation",
                "Birthday party",
                "Date night",
                "Vacation",
                "Beach",
                "Cruise",
                "Gym",
                "Hiking",
                "Camping",
                "Concert",
                "Interview",
                "Airport travel",
                "Rainy day",
                "Seasonal outfits"
            ],
            prompt: """
Add AI Personal Shopper.

Users should request complete outfits for real-life occasions. The AI should check the Virtual Closet first, use existing clothing whenever possible, recommend missing items only, consider weather, event, budget, favorite colors, style preferences, and size profile.
""",
            acceptanceTests: [
                "Closet items are prioritized.",
                "Budget is respected.",
                "Weather affects the outfit.",
                "Occasion affects the outfit.",
                "Multiple outfit options can be compared."
            ]
        ),
        RoadmapVersion(
            title: "In-App Shopping",
            version: "2.9",
            goal: "Future-only direct checkout review after the affiliate marketplace is proven.",
            features: [
                "Cart",
                "Size selection",
                "Color selection",
                "Secure checkout",
                "Retailer fulfillment",
                "Order tracking"
            ],
            prompt: """
Add In-App Shopping.

This is not part of the first shopping release. Users should first browse affiliate recommendations and complete purchases with approved retailers. Only revisit direct checkout after legal, payment, fraud, fulfillment, refund, return, tax, customer support, and retailer integration reviews are complete.

Use a trusted checkout experience if this future phase is approved. Do not store raw card numbers.
""",
            acceptanceTests: [
                "Feature remains hidden from the first public affiliate marketplace release.",
                "Retailer checkout remains the active release path.",
                "Payment uses secure test mode before any future pilot.",
                "No raw card data is stored.",
                "Order tracking states are sourced from retailer systems only."
            ]
        ),
        RoadmapVersion(
            title: "Complete AI Fashion Platform",
            version: "3.0",
            goal: "Unify Style Match Pro into a complete fashion ecosystem.",
            features: [
                "AI Stylist",
                "Virtual Closet",
                "Outfit Planning",
                "Shopping",
                "Wishlist",
                "Budget Tracking",
                "Travel Packing",
                "Calendar Planning",
                "Weather Recommendations",
                "Order Tracking",
                "Fashion Analytics",
                "Style Progress Reports"
            ],
            prompt: """
Unify Style Match Pro into a complete AI-powered fashion platform.

Add a dashboard with recent scans, favorite outfits, closet gaps, upcoming planned outfits, wishlist price drops, budget usage, and style progress.
""",
            acceptanceTests: [
                "All major sections are reachable.",
                "Dashboard loads without errors.",
                "Data connects cleanly.",
                "Empty states are polished.",
                "Users can delete personal data."
            ]
        )
    ]
}
