import Combine
import Foundation

/// Wire-compatible with Build 18037's device-global floating-control
/// preference. Earlier 18039 builds stored only the horizontal edge.
private struct FloatingStylistControlPlacement: Codable, Equatable {
    static let `default` = FloatingStylistControlPlacement(horizontal: 1, vertical: 1)

    var horizontal: Double
    var vertical: Double

    init(horizontal: Double, vertical: Double) {
        self.horizontal = Self.clamp(horizontal)
        self.vertical = Self.clamp(vertical)
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0.5 }
        return min(max(value, 0), 1)
    }
}

/// Device-global presentation preference only. It deliberately excludes
/// account, session, conversation, AI Memory, Weather, and Style Friends data.
private struct FloatingStylistControlPreferenceStore {
    static let key = "floatingStylistControlPlacement.v1"
    static let legacyEdgeKey = "stylistGlobalControlEdge"

    struct Preferences: Codable, Equatable {
        var placement: FloatingStylistControlPlacement
        var isCollapsed: Bool

        static let `default` = Preferences(placement: .default, isCollapsed: false)
    }

    let defaults: UserDefaults
    let key: String

    func load() -> Preferences {
        if let data = defaults.data(forKey: key), !data.isEmpty {
            if let preferences = try? JSONDecoder().decode(Preferences.self, from: data) {
                return Preferences(
                    placement: .init(horizontal: preferences.placement.horizontal, vertical: preferences.placement.vertical),
                    isCollapsed: preferences.isCollapsed
                )
            }
            // Keep Build 18037's first placement-only v1 payload compatible.
            if let placement = try? JSONDecoder().decode(FloatingStylistControlPlacement.self, from: data) {
                return Preferences(placement: placement, isCollapsed: false)
            }
            return .default
        }

        let legacyRawValue = defaults.string(forKey: Self.legacyEdgeKey)
        return Preferences(
            placement: .init(horizontal: legacyRawValue == "leading" ? 0 : 1, vertical: 1),
            isCollapsed: false
        )
    }

    func save(_ preferences: Preferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: key)
        let edge = preferences.placement.horizontal < 0.5 ? "leading" : "trailing"
        // Maintain the legacy additive edge value for an already-installed
        // older 18039 app; it is not a second collapsed-state authority.
        defaults.set(edge, forKey: Self.legacyEdgeKey)
    }
}

/// Root-owned, in-memory presentation coordination for the global Stylist
/// sheet. It deliberately holds no serializable route data and never writes
/// route state; only the fixed visual edge preference is persisted locally.
/// Chat persistence remains limited to existing send/save paths.
@MainActor
final class StylistOverlaySessionCoordinator: ObservableObject {
    enum FloatingControlEdge: String, Equatable {
        case leading
        case trailing
    }

    enum FloatingControlPresentation: Equatable {
        case expanded(edge: FloatingControlEdge)
        case collapsed(edge: FloatingControlEdge)

        var edge: FloatingControlEdge {
            switch self {
            case let .expanded(edge), let .collapsed(edge):
                return edge
            }
        }

        var isCollapsed: Bool {
            if case .collapsed = self {
                return true
            }
            return false
        }
    }

    enum Route: Equatable {
        case general
        case screenAwareness(generation: UInt64, reference: StyleMemoryReference?)
        case scan
    }

    @Published private(set) var isPresented = false
    @Published private(set) var route: Route = .general
    /// Presentation-only state for the root global control. It deliberately
    /// has no effect on the active route, conversation, or service.
    @Published private(set) var floatingControlPresentation: FloatingControlPresentation = .expanded(edge: .trailing)

    let service: StylistChatService
    private let floatingControlPreferenceStore: FloatingStylistControlPreferenceStore
    private var floatingControlPlacement: FloatingStylistControlPlacement

    init() {
        let store = FloatingStylistControlPreferenceStore(defaults: .standard, key: FloatingStylistControlPreferenceStore.key)
        let preferences = store.load()
        service = StylistChatService()
        floatingControlPreferenceStore = store
        floatingControlPlacement = preferences.placement
        floatingControlPresentation = Self.presentation(for: preferences)
    }

    init(service: StylistChatService, floatingControlEdgeDefaults: UserDefaults = .standard) {
        let store = FloatingStylistControlPreferenceStore(defaults: floatingControlEdgeDefaults, key: FloatingStylistControlPreferenceStore.key)
        let preferences = store.load()
        self.service = service
        floatingControlPreferenceStore = store
        floatingControlPlacement = preferences.placement
        floatingControlPresentation = Self.presentation(for: preferences)
    }

    var usesScreenAwareness: Bool {
        if case .screenAwareness = route {
            return true
        }
        return false
    }

    func presentGeneral() {
        if route == .general {
            service.ensureVerifiedGeneralConversation()
        } else {
            transition(to: .general)
        }
        isPresented = true
    }

    func presentScreenAwareness(_ snapshot: ScreenAwarenessSnapshot) {
        transition(to: .screenAwareness(generation: snapshot.generation, reference: snapshot.localReference))
        isPresented = true
    }

    func presentScan() {
        transition(to: .scan)
        isPresented = true
    }

    func dismiss() {
        isPresented = false
    }

    func useGeneralStylist() {
        presentGeneral()
    }

    func collapseFloatingControl(toward edge: FloatingControlEdge) {
        floatingControlPlacement = .init(
            horizontal: edge == .leading ? 0 : 1,
            vertical: floatingControlPlacement.vertical
        )
        floatingControlPresentation = .collapsed(edge: edge)
        persistFloatingControlPreferences()
    }

    func expandFloatingControl() {
        floatingControlPresentation = .expanded(edge: floatingControlPresentation.edge)
        persistFloatingControlPreferences()
    }

    func moveFloatingControl(to edge: FloatingControlEdge) {
        floatingControlPlacement = .init(
            horizontal: edge == .leading ? 0 : 1,
            vertical: floatingControlPlacement.vertical
        )
        switch floatingControlPresentation {
        case .expanded:
            floatingControlPresentation = .expanded(edge: edge)
        case .collapsed:
            floatingControlPresentation = .collapsed(edge: edge)
        }
        persistFloatingControlPreferences()
    }

    private static func presentation(for preferences: FloatingStylistControlPreferenceStore.Preferences) -> FloatingControlPresentation {
        let edge: FloatingControlEdge = preferences.placement.horizontal < 0.5 ? .leading : .trailing
        return preferences.isCollapsed ? .collapsed(edge: edge) : .expanded(edge: edge)
    }

    private func persistFloatingControlPreferences() {
        floatingControlPreferenceStore.save(
            .init(
                placement: floatingControlPlacement,
                isCollapsed: floatingControlPresentation.isCollapsed
            )
        )
    }

    private func transition(to nextRoute: Route) {
        guard route != nextRoute else { return }
        // A new explicit authority must never inherit a general or other
        // contextual thread. Exact scan opening remains delegated to the
        // existing scan conversation authority in StylistChatView.
        switch nextRoute {
        case .general:
            service.ensureVerifiedGeneralConversation()
        case .screenAwareness:
            service.beginContextualConversation()
        case .scan:
            service.newChat()
        }
        route = nextRoute
    }
}
