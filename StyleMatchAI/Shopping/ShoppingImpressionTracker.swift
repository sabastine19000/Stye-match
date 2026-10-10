import Foundation

final class ShoppingImpressionTracker: @unchecked Sendable {
    private struct Key: Hashable {
        let productID: String
        let surface: ShoppingImpressionSurface
        let routeID: UUID
    }

    private let lock = NSLock()
    private var recorded: Set<Key> = []

    @discardableResult
    func recordIfNeeded(
        productID: String,
        retailerID: String?,
        approvedRetailerIDs: Set<String>,
        surface: ShoppingImpressionSurface,
        position: Int,
        source: ProductCatalogSource,
        context: ShoppingDiagnosticContext,
        diagnostics: any ShoppingDiagnosticsRecording
    ) -> Bool {
        let key = Key(productID: productID, surface: surface, routeID: context.routeID)
        lock.lock()
        let inserted = recorded.insert(key).inserted
        lock.unlock()
        guard inserted else { return false }

        let canonicalRetailerID = RetailerPreferencePolicy.canonicalID(retailerID)
        let validatedRetailerID = canonicalRetailerID.flatMap { approvedRetailerIDs.contains($0) ? $0 : nil }
        diagnostics.record(
            ShoppingDiagnosticEvent(
                context: context,
                payload: .productImpression(
                    surface: surface,
                    position: max(0, position),
                    retailerID: validatedRetailerID,
                    source: source
                )
            )
        )
        return true
    }

    func reset() {
        lock.lock()
        recorded.removeAll()
        lock.unlock()
    }
}
