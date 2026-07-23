# Screen Context Update Plan

Status: **Proposal only — current screen-awareness behavior is unchanged**

## 1. Current contract

`StylistScreenContext` currently carries:

- current tab;
- active scan state and ID;
- selected occasion and analysis section;
- visible Overall Style Score;
- entry point;
- visible aggregate statistics;
- closet state.

`StylistAuthoritativeScanContext.matches` primarily reconciles active scan ID and visible score. This protects score continuity but cannot detect stale purpose/profile/compatibility state.

## 2. Proposed additive fields

```swift
struct StylistScreenContext: Codable, Equatable {
    // existing fields unchanged
    var contextSchemaVersion: Int?
    var activeContextGeneration: Int?
    var selectedPurpose: OutfitPurpose?
    var selectedWorkplaceProfile: WorkplaceProfile?
    var purposeConfirmationState: ConfirmationState?
    var visibleCompatibility: VisibleCompatibilityMetrics?
    var visibleContextConfidence: ContextConfidence?
    var visibleMissingEvidenceIDs: [String]
}
```

`VisibleCompatibilityMetrics` contains categorical occasion, workplace, weather, and safety suitability only. It never contains a replacement Overall Style Score.

## 3. Matching requirements

A screen context is scan-specific only when all supplied fields match the authoritative snapshot:

1. active scan ID;
2. visible Overall Style Score;
3. context schema version;
4. context generation;
5. selected/confirmed purpose;
6. selected/confirmed workplace profile;
7. compatibility metrics displayed on screen;
8. missing-evidence identifiers relevant to the visible section.

Optional legacy fields do not create authority. Their absence triggers limited-context behavior.

## 4. Fail-closed matrix

| Conflict | AI behavior | UI behavior |
|---|---|---|
| Scan ID mismatch | Remove scan-specific context; do not answer from history | Refresh or ask the user to select a scan |
| Score mismatch | Reject send/fallback; never choose one score | Show refresh state |
| Generation mismatch | Resolve provider again once; if still mismatched, stop | Re-render from authoritative snapshot |
| Purpose mismatch | Use neither value in a claim | Ask for reconfirmation |
| Workplace profile mismatch | Workplace advice unavailable | Show authoritative saved confirmation after refresh |
| Compatibility mismatch | Do not state suitability | Recompute deterministic display from the same snapshot |
| Missing-evidence mismatch | Use union only for limitations; make no negative claim | Refresh indicators |
| Legacy context | Use score/category facts only and label limited context | Offer optional context selection |
| No active scan on current screen | Do not inject previously visible scan automatically | Chat may use explicit saved selection or latest completed authority per existing provider rules |

## 5. Transition behavior

### Scan completion

1. Persist analysis and context.
2. Advance context generation.
3. Update visible screen state from the persisted snapshot.
4. Enable AI actions only after ID, score, and generation match.

### User correction

1. Save correction to the same scan.
2. Increment generation.
3. Recompute compatibility/suitability deterministically.
4. Invalidate any in-flight AI turn stamped with the older generation.
5. Preserve the original model proposal in provenance.

### Navigate to AI Assist

Pass the exact scan ID and generation. Do not rebuild purpose from labels or conversation memory.

### Navigate to standalone AI Stylist

Resolve immediately before send:

- explicit saved scan selection wins;
- otherwise latest completed scan authority applies;
- current screen metadata must validate if it claims an active scan.

### Voice

Stamp the same scan ID and generation at recognition start and revalidate before sending the transcript. If the context changed while speaking, ask the user to retry against the updated scan.

### Saved scan

Opening a historical scan makes that scan authoritative for the saved-scan interaction. A newer scan does not override it until the user leaves or selects the newer scan.

## 6. Conversation-turn stamping

Extend existing stale-turn protections with:

```text
authoritativeScanID
contextGeneration
confirmedPurposeID
confirmedWorkplaceProfileID
contextSchemaVersion
```

Completed turns from another scan/generation remain in visible history but are excluded from scan-fact grounding.

## 7. Legacy and compatibility behavior

- Add fields as optional for decoding older local history.
- Preserve current Worker request fields.
- Send the context extension only when supported-version capability is proven.
- Never silently flatten the new context into old `detectedStyle` or `occasionAssessment` strings.
- Local fallback can format the typed context without a Worker response.

## 8. Required validation

- Unit tests for every conflict row.
- Navigation tests for Scan → AI Assist → AI Stylist → saved scan.
- In-flight correction and new-scan tests.
- Voice transcript context-change test.
- Legacy screen-context decode.
- Physical validation of on-screen score/purpose/profile/metrics versus AI and voice.
- Chat-health and supported-version checks under ADR-006.
