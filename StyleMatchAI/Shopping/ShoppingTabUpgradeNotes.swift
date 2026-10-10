import Foundation

#if DEBUG
enum ShoppingTabUpgradeNotes {
    static let phase0Findings = """
    Phase 0 findings:
    - Recommendation copy is composed in ShoppingRecommendationEngine.ProductRecommendationReasonFacts.oneLineReason and consumed by ShoppingView.productCard plus StoreSearchView result cards.
    - Raw OutfitMemory labels can enter ProductRecommendationReasonFacts.referencedOutfit through ShoppingRecommendationEngine.outfitPhrase and ShoppingSaleAlertService.outfitPhrase.
    - The affiliate disclosure is rendered in ShoppingView.disclosureSummary with a full sheet, and StoreSearchView has its own disclosure row/sheet.
    - ComplementaryPieceRecommender exists in PersonalStylistEngines.swift with recommendations(for: GarmentRecord, ownedRecords:limit:), so the Shop tab uses a separate catalog-backed product adapter instead of changing that API.
    - Product cards use curated catalog fields from AffiliateProduct.name/category/subcategory/colors, while the risky remembered-outfit labels came from OutfitMemory.detectedGarments and colors.
    """
}
#endif
