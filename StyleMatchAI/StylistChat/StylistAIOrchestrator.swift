import Foundation

/// The local capability selected for an already-admitted Stylist request.
/// This classification never leaves the app and does not grant authority to
/// any fact; the canonical intelligence snapshot remains that authority.
enum StylistAICapability: String, Equatable {
    case generalStylist
    case scanAdvisor
    case closetAssistant
    case personalShopper
    case outfitBuilder
    case workplaceAdvisor
    case weatherStylist
}

/// Local-only execution choice for the existing Stylist send pipeline.
/// `requiresConsent` is intentionally reserved for a future caller-owned
/// consent phase; Phase 2A-3 never produces or consumes it.
enum StylistAIOrchestrationOutcome: Equatable {
    case localResponse(capability: StylistAICapability, response: String, semanticResponseID: StylistSemanticResponseID)
    case requiresClarification(capability: StylistAICapability, prompt: String, semanticResponseID: StylistSemanticResponseID)
    case requiresConsent(capability: StylistAICapability)
    case networkRequest(capability: StylistAICapability)
    case unavailable(reason: StylistIntelligenceAdmissionReason)
}

/// Inputs assembled by existing authorities. `networkContext` is already the
/// established safe `networkSafeContext` projection; the orchestrator treats
/// it as an opaque handoff and never reads or mutates it.
struct StylistAIOrchestrationInput {
    let snapshot: StylistIntelligenceSnapshot
    let conversationScope: StylistConversationScope
    let intent: StylistQueryIntent
    let preflight: StylistConversationPreflight
    let networkContext: ChatContext
}

/// Pure local orchestration over canonical admission outcomes. It does not
/// read stores, perform I/O, persist state, inspect FeatureGate, or construct
/// any Worker request.
enum StylistAIOrchestrator {
    static func decide(_ input: StylistAIOrchestrationInput) -> StylistAIOrchestrationOutcome {
        let capabilityResult = capability(for: input)
        switch capabilityResult {
        case let .unavailable(reason):
            return .unavailable(reason: reason)
        case let .selected(capability):
            guard let response = input.preflight.localReply,
                  let semanticResponseID = input.preflight.semanticResponseID else {
                return .networkRequest(capability: capability)
            }

            if semanticResponseID == .workplaceSafetyClarification {
                return .requiresClarification(
                    capability: capability,
                    prompt: response,
                    semanticResponseID: semanticResponseID
                )
            }
            // Existing non-clarification preflight replies retain their
            // established transport behavior in this phase. The typed local
            // response case is available for future deterministic replies
            // once their behavior is explicitly migrated.
            return .networkRequest(capability: capability)
        }
    }

    private enum CapabilityResult {
        case selected(StylistAICapability)
        case unavailable(StylistIntelligenceAdmissionReason)
    }

    private static func capability(for input: StylistAIOrchestrationInput) -> CapabilityResult {
        if input.conversationScope.isScanBound {
            return admitted(.scan, in: input.snapshot)
                ? .selected(.scanAdvisor)
                : .unavailable(reason(for: .scan, in: input.snapshot) ?? .missingAuthoritativeScan)
        }

        if input.conversationScope.isContextual,
           !admitted(.screenAwareness, in: input.snapshot) {
            return .unavailable(reason(for: .screenAwareness, in: input.snapshot) ?? .generalStylistContextCleared)
        }

        if admitted(.productConsideration, in: input.snapshot) {
            return .selected(.personalShopper)
        }

        if let productReason = reason(for: .productConsideration, in: input.snapshot),
           productReason != .noActiveProductContext {
            return .unavailable(productReason)
        }

        if input.snapshot.screen?.kind == .closetItem,
           admitted(.screenAwareness, in: input.snapshot) {
            return .selected(.closetAssistant)
        }

        if input.intent == .workplace || input.intent == .footwear,
           admitted(.workplace, in: input.snapshot) {
            return .selected(.workplaceAdvisor)
        }

        if input.intent == .futureOrTomorrow,
           admitted(.weather, in: input.snapshot) {
            return .selected(.weatherStylist)
        }

        if input.intent == .completeOutfit {
            return .selected(.outfitBuilder)
        }

        return .selected(.generalStylist)
    }

    private static func admitted(
        _ domain: StylistIntelligenceFactDomain,
        in snapshot: StylistIntelligenceSnapshot
    ) -> Bool {
        snapshot.admissions.first(where: { $0.domain == domain })?.decision == .admitted
    }

    private static func reason(
        for domain: StylistIntelligenceFactDomain,
        in snapshot: StylistIntelligenceSnapshot
    ) -> StylistIntelligenceAdmissionReason? {
        snapshot.admissions.first(where: { $0.domain == domain })?.reason
    }
}
