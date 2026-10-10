import Foundation
import OSLog

protocol ShoppingDiagnosticsRecording: Sendable {
    func record(_ event: ShoppingDiagnosticEvent)
}

struct ShoppingDiagnosticContext: Equatable, Sendable {
    static let schemaVersion: UInt8 = 1

    let routeID: UUID
    let loadGeneration: Int

    init(routeID: UUID = UUID(), loadGeneration: Int = 0) {
        self.routeID = routeID
        self.loadGeneration = max(0, loadGeneration)
    }

    func withLoadGeneration(_ generation: Int) -> ShoppingDiagnosticContext {
        ShoppingDiagnosticContext(routeID: routeID, loadGeneration: generation)
    }
}

enum ShoppingCatalogLoadTrigger: String, Equatable, Sendable {
    case routeEntry = "route_entry"
    case refresh
    case retry
    case unspecified
}

enum ShoppingCatalogLoadOutcome: String, Equatable, Sendable {
    case success
    case recovered
    case failure
    case cancelled
}

enum ShoppingCatalogCacheLayer: String, Equatable, Sendable {
    case memory
    case disk
}

enum ShoppingCatalogCacheOutcome: String, Equatable, Sendable {
    case hit
    case miss
    case stale
    case joinedInFlight = "joined_in_flight"
    case error
}

enum ShoppingRetailerPolicyMode: String, Equatable, Sendable {
    case allApproved = "all_approved"
    case preferredRetailers = "preferred_retailers"
    case strictStore = "strict_store"
}

enum ShoppingFallbackReason: String, Equatable, Sendable {
    case selectedRetailersZeroInventorySoftFallback = "selected_retailers_zero_inventory_soft_fallback"
    case strictStoreZeroResults = "strict_store_zero_results"
    case catalogSourcesExhausted = "catalog_sources_exhausted"
    case safetyValidationRemovedAll = "safety_validation_removed_all"
    case none
}

enum ShoppingDisplayDestination: String, Equatable, Sendable {
    case products
    case stores
    case browse
    case swipe
    case recommendations
    case unknown
}

enum ShoppingImpressionSurface: String, Equatable, Sendable {
    case productCard = "product_card"
    case compactCard = "compact_card"
    case swipeDeck = "swipe_deck"
}

enum ShoppingPreferenceSource: String, Equatable, Sendable {
    case defaultValue = "default"
    case persisted
    case migrated
}

enum ShoppingPreferenceAction: String, Equatable, Sendable {
    case add
    case remove
    case replace
    case clear
    case normalize
}

enum ShoppingErrorStage: String, Equatable, Sendable {
    case remoteFetch = "remote_fetch"
    case decode
    case safetyValidation = "safety_validation"
    case cacheRead = "cache_read"
    case cacheWrite = "cache_write"
    case bundledLoad = "bundled_load"
    case retailerPolicy = "retailer_policy"
    case displayDerivation = "display_derivation"
    case preferenceLoad = "preference_load"
    case preferenceSave = "preference_save"
}

enum ShoppingErrorSeverity: String, Equatable, Sendable {
    case recoverable
    case fatal
}

enum ShoppingErrorRecoverability: String, Equatable, Sendable {
    case recovered
    case retryable
    case terminal
}

struct ShoppingDiagnosticMetadata: Equatable, Sendable {
    let schemaVersion: UInt8
    let routeID: UUID
    let loadGeneration: Int

    init(context: ShoppingDiagnosticContext) {
        schemaVersion = ShoppingDiagnosticContext.schemaVersion
        routeID = context.routeID
        loadGeneration = context.loadGeneration
    }
}

enum ShoppingDiagnosticPayload: Equatable, Sendable {
    case shoppingLoadStarted(trigger: ShoppingCatalogLoadTrigger, priorCatalogPresent: Bool)
    case shoppingLoadCompleted(source: ProductCatalogSource, receivedCount: Int, safeCount: Int, outcome: ShoppingCatalogLoadOutcome)
    case catalogSourceSelected(source: ProductCatalogSource)
    case catalogCacheResult(layer: ShoppingCatalogCacheLayer, outcome: ShoppingCatalogCacheOutcome, count: Int)
    case retailerSelectionSnapshot(retailerIDs: [String], selectedCount: Int, mode: ShoppingRetailerPolicyMode)
    case retailerFilterCompleted(inputCount: Int, matchedCount: Int, selectedCount: Int, mode: ShoppingRetailerPolicyMode)
    case fallbackActivated(reason: ShoppingFallbackReason, inputCount: Int, fallbackCount: Int)
    case displayFinalized(eligibleCount: Int, recommendationCount: Int, displayedCount: Int, destination: ShoppingDisplayDestination)
    case productImpression(surface: ShoppingImpressionSurface, position: Int, retailerID: String?, source: ProductCatalogSource)
    case preferencesInitialized(selectedCount: Int, source: ShoppingPreferenceSource, registryReady: Bool)
    case preferencesSelectionChanged(action: ShoppingPreferenceAction, beforeCount: Int, afterCount: Int)
    case shoppingError(stage: ShoppingErrorStage, severity: ShoppingErrorSeverity, recoverability: ShoppingErrorRecoverability, classification: ProductCatalogFailureClassification?, errorDomain: String?, errorCode: Int?)
}

struct ShoppingDiagnosticEvent: Equatable, Sendable {
    enum Category: String, Equatable, Sendable {
        case catalog = "shopping.catalog"
        case display = "shopping.display"
        case preferences = "shopping.preferences"
        case errors = "shopping.errors"
    }

    let metadata: ShoppingDiagnosticMetadata
    let payload: ShoppingDiagnosticPayload

    init(context: ShoppingDiagnosticContext, payload: ShoppingDiagnosticPayload) {
        metadata = ShoppingDiagnosticMetadata(context: context)
        self.payload = payload
    }

    var name: String {
        switch payload {
        case .shoppingLoadStarted: return "shopping_load_started"
        case .shoppingLoadCompleted: return "shopping_load_completed"
        case .catalogSourceSelected: return "catalog_source_selected"
        case .catalogCacheResult: return "catalog_cache_result"
        case .retailerSelectionSnapshot: return "retailer_selection_snapshot"
        case .retailerFilterCompleted: return "retailer_filter_completed"
        case .fallbackActivated: return "fallback_activated"
        case .displayFinalized: return "display_finalized"
        case .productImpression: return "product_impression"
        case .preferencesInitialized: return "preferences_initialized"
        case .preferencesSelectionChanged: return "preferences_selection_changed"
        case .shoppingError: return "shopping_error"
        }
    }

    var category: Category {
        switch payload {
        case .shoppingLoadStarted, .shoppingLoadCompleted, .catalogSourceSelected, .catalogCacheResult:
            return .catalog
        case .retailerSelectionSnapshot, .retailerFilterCompleted, .fallbackActivated, .displayFinalized, .productImpression:
            return .display
        case .preferencesInitialized, .preferencesSelectionChanged:
            return .preferences
        case .shoppingError:
            return .errors
        }
    }

    var publicLogLine: String {
        var fields = [
            "event=\(name)",
            "schema=\(metadata.schemaVersion)",
            "route_id=\(metadata.routeID.uuidString.lowercased())",
            "generation=\(metadata.loadGeneration)"
        ]
        switch payload {
        case let .shoppingLoadStarted(trigger, priorCatalogPresent):
            fields += ["trigger=\(trigger.rawValue)", "prior_catalog=\(priorCatalogPresent)"]
        case let .shoppingLoadCompleted(source, receivedCount, safeCount, outcome):
            fields += ["source=\(source.rawValue)", "received_count=\(receivedCount)", "safe_count=\(safeCount)", "outcome=\(outcome.rawValue)"]
        case let .catalogSourceSelected(source):
            fields += ["source=\(source.rawValue)"]
        case let .catalogCacheResult(layer, outcome, count):
            fields += ["layer=\(layer.rawValue)", "outcome=\(outcome.rawValue)", "count=\(count)"]
        case let .retailerSelectionSnapshot(retailerIDs, selectedCount, mode):
            fields += ["retailer_ids=\(retailerIDs.joined(separator: ","))", "selected_count=\(selectedCount)", "mode=\(mode.rawValue)"]
        case let .retailerFilterCompleted(inputCount, matchedCount, selectedCount, mode):
            fields += ["input_count=\(inputCount)", "matched_count=\(matchedCount)", "selected_count=\(selectedCount)", "mode=\(mode.rawValue)"]
        case let .fallbackActivated(reason, inputCount, fallbackCount):
            fields += ["reason=\(reason.rawValue)", "input_count=\(inputCount)", "fallback_count=\(fallbackCount)"]
        case let .displayFinalized(eligibleCount, recommendationCount, displayedCount, destination):
            fields += ["eligible_count=\(eligibleCount)", "recommendation_count=\(recommendationCount)", "displayed_count=\(displayedCount)", "destination=\(destination.rawValue)"]
        case let .productImpression(surface, position, retailerID, source):
            fields += ["surface=\(surface.rawValue)", "position=\(position)", "retailer_id=\(retailerID ?? "none")", "source=\(source.rawValue)"]
        case let .preferencesInitialized(selectedCount, source, registryReady):
            fields += ["selected_count=\(selectedCount)", "source=\(source.rawValue)", "registry_ready=\(registryReady)"]
        case let .preferencesSelectionChanged(action, beforeCount, afterCount):
            fields += ["action=\(action.rawValue)", "before_count=\(beforeCount)", "after_count=\(afterCount)"]
        case let .shoppingError(stage, severity, recoverability, classification, errorDomain, errorCode):
            fields += [
                "stage=\(stage.rawValue)",
                "severity=\(severity.rawValue)",
                "recoverability=\(recoverability.rawValue)",
                "classification=\(classification?.rawValue ?? "none")",
                "error_domain=\(Self.safeErrorDomain(errorDomain))",
                "error_code=\(errorCode.map(String.init) ?? "none")"
            ]
        }
        return fields.joined(separator: " ")
    }

    private static func safeErrorDomain(_ domain: String?) -> String {
        guard let domain, !domain.isEmpty else { return "none" }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        return domain.unicodeScalars.allSatisfy(allowed.contains) ? domain : "redacted"
    }
}

enum ShoppingDiagnostics {
    static var live: any ShoppingDiagnosticsRecording {
        return OSLogShoppingDiagnostics()
    }

    static var unifiedLoggingEnabled: Bool {
        true
    }
}

struct NoOpShoppingDiagnostics: ShoppingDiagnosticsRecording {
    func record(_ event: ShoppingDiagnosticEvent) {}
}

struct OSLogShoppingDiagnostics: ShoppingDiagnosticsRecording {
    static let subsystem = "com.sabastine.stylematchai"

    private let catalog = Logger(subsystem: subsystem, category: ShoppingDiagnosticEvent.Category.catalog.rawValue)
    private let display = Logger(subsystem: subsystem, category: ShoppingDiagnosticEvent.Category.display.rawValue)
    private let preferences = Logger(subsystem: subsystem, category: ShoppingDiagnosticEvent.Category.preferences.rawValue)
    private let errors = Logger(subsystem: subsystem, category: ShoppingDiagnosticEvent.Category.errors.rawValue)

    func record(_ event: ShoppingDiagnosticEvent) {
        let line = event.publicLogLine
        switch event.category {
        case .catalog:
            catalog.info("\(line, privacy: .public)")
        case .display:
            display.info("\(line, privacy: .public)")
        case .preferences:
            preferences.info("\(line, privacy: .public)")
        case .errors:
            errors.error("\(line, privacy: .public)")
        }
    }
}

final class RecordingShoppingDiagnostics: ShoppingDiagnosticsRecording, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ShoppingDiagnosticEvent] = []

    func record(_ event: ShoppingDiagnosticEvent) {
        lock.lock()
        storage.append(event)
        lock.unlock()
    }

    var events: [ShoppingDiagnosticEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func reset() {
        lock.lock()
        storage.removeAll()
        lock.unlock()
    }
}
