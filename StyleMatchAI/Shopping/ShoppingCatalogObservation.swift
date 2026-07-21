import Foundation

struct ShoppingCatalogObservation: Equatable, Sendable {
    let source: ProductCatalogSource
    let selectedRetailerIDs: [String]
    let inputCount: Int
    let matchedCount: Int
    let usedFallback: Bool
    let fallbackReason: ShoppingFallbackReason
    let eligibleCount: Int
    let recommendationCount: Int
    let displayedCount: Int
    let destination: ShoppingDisplayDestination

    static func make(
        source: ProductCatalogSource,
        selectedRetailerIDs: [String],
        supportedStores: [SupportedStore],
        inputProducts: [AffiliateProduct],
        policyResult: RetailerPreferenceResult,
        eligibleCount: Int,
        recommendationCount: Int,
        displayedCount: Int,
        destination: ShoppingDisplayDestination
    ) -> ShoppingCatalogObservation {
        let approvedIDs = RetailerPreferencePolicy.normalizedPreferredRetailerIDs(
            selectedRetailerIDs,
            supportedStores: supportedStores
        )
        let selectedSet = Set(approvedIDs)
        let matchedCount = inputProducts.reduce(into: 0) { count, product in
            guard let retailerID = RetailerPreferencePolicy.canonicalID(product.retailerID),
                  selectedSet.contains(retailerID) else { return }
            count += 1
        }
        return ShoppingCatalogObservation(
            source: source,
            selectedRetailerIDs: approvedIDs,
            inputCount: inputProducts.count,
            matchedCount: matchedCount,
            usedFallback: policyResult.usedFallback,
            fallbackReason: fallbackReason(for: policyResult, inputCount: inputProducts.count),
            eligibleCount: eligibleCount,
            recommendationCount: recommendationCount,
            displayedCount: displayedCount,
            destination: destination
        )
    }

    static func fallbackReason(for result: RetailerPreferenceResult, inputCount: Int) -> ShoppingFallbackReason {
        if result.usedFallback {
            return .selectedRetailersZeroInventorySoftFallback
        }
        if !result.requestedRetailerIDs.isEmpty, inputCount == 0 {
            return .strictStoreZeroResults
        }
        return .none
    }

    func recordDisplay(
        context: ShoppingDiagnosticContext,
        diagnostics: any ShoppingDiagnosticsRecording
    ) {
        diagnostics.record(
            ShoppingDiagnosticEvent(
                context: context,
                payload: .displayFinalized(
                    eligibleCount: eligibleCount,
                    recommendationCount: recommendationCount,
                    displayedCount: displayedCount,
                    destination: destination
                )
            )
        )
    }
}
