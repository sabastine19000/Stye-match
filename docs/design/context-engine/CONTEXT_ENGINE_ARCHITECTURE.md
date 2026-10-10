# StyleMatch Pro Context Engine Architecture

Status: **Design proposal only — not implemented or accepted**

Baseline:

- Branch: `feature/expanded-garment-classification`
- Audited HEAD: `1e864382797a2882b5a176a5bbd1fd70eadb4a66`
- Governing decisions: ADR-001, ADR-002, ADR-003, ADR-006, ADR-007 in `docs/PROJECT_STATE.md`
- Protected behavior: accepted IA1.1/D7-SL1 Shopping behavior, catalog authorities, B5 retained data, current score ownership, signing, and deployment

## 1. Governing invariants

1. Scan owns the completed numeric style score and its evidence. AI may explain it but may not generate, replace, or silently recalculate it.
2. Garment category, visual style, outfit purpose, selected occasion, workplace profile, physical environment, safety context, and weather context are different facts.
3. User confirmation or correction is authoritative for that scan, but does not rewrite visual evidence.
4. Missing or conflicting evidence stays explicit. `Other / Uncertain` is not promoted to certainty.
5. All AI surfaces consume the same versioned context. No surface keeps an independent “last score,” purpose, or category.
6. A conflict between visible screen state and the authoritative scan fails closed: omit scan-specific claims and request refresh or selection.
7. No logo, text, badge, location, or garment may be used to identify the wearer, employer, gender identity, occupation, school, or event.

## 2. Current decision flow audit

| Stage | Current implementation | Current authority | Finding |
|---|---|---|---|
| 1. Image capture | `StyleMatchAI/ScanView.swift` camera/gallery state and session identity | Active scan view session | Session and image identity are guarded before applying results. |
| 2. Garment detection | Vision labels, deterministic rules, `OutfitClassificationEngine` in `StyleMatchAI/Models.swift` | `OutfitClassificationResult` plus legacy string heuristics | Typed categories exist, but legacy purpose/novelty/traditional classifiers still produce parallel garment/style/occasion strings. |
| 3. Color/pattern/fit | Scan preparation and `calculateStyleScore` in `ScanView.swift` | `OutfitAnalysisResult` and `OutfitScoreBreakdown` | This is the existing numeric score authority and must remain unchanged until separately approved. |
| 4. Occasion selection | `Occasion` in `StylistProfileModels.swift`, selected scan occasion, profile occasion strings | User selection, with legacy canonicalization | Generic `Work` is overloaded; it does not describe factory, office, healthcare, or other workplace context. |
| 5. Score generation | `calculateStyleScore` scores color, pattern, fit, and accessories | Scan engine | Occasion is presently explanatory rather than a numeric score component. Purpose-specific weights are not active. |
| 6. Scan persistence | Saved `OutfitAnalysisResult` and history | Persisted scan record | `OutfitClassificationResult` is additive and legacy-decodes to uncertain, but no typed purpose/workplace/suitability snapshot exists. |
| 7. AI context | `CurrentScanContextProvider`, `StylistAuthoritativeScanContext`, `StylistScreenContext` | Central current-scan provider | Score/scan authority is centralized, but purpose, workplace, environment, safety, missing evidence, and compatibility metrics are absent or flattened. |
| 8. AI Assist | Scan-derived authoritative context | Current scan result | Correctly anchored to the displayed scan, but explanations lack the proposed context dimensions. |
| 9. AI Stylist Chat | Provider resolution immediately before send | Explicit saved scan or latest completed scan | Stale-score protection exists. The new context must extend this same path, not create a second provider. |
| 10. Voice summary | `VoiceScriptBuilder.scanResult` | `OutfitAnalysisResult` | Uses confirmed category when present, otherwise style; it can still flatten garment category and detected style. |

## 3. Current conflations and duplicate sources

### 3.0 Current source-of-truth inventory

This inventory distinguishes authoritative state from helpers that currently derive overlapping descriptions.

| Domain | Current repository location | Current role | Authority assessment |
|---|---|---|---|
| Active image/session | `StyleMatchAI/ScanView.swift` scan state and analysis session identity | Guards image replacement and asynchronous result application | Authoritative for the in-progress scan only |
| Completed scan model | `OutfitAnalysisResult` in `StyleMatchAI/Models.swift` | Stores score, breakdown, descriptive fields, classification, and AI sections | Authoritative persisted scan result |
| Numeric score | `calculateStyleScore` and `OutfitScoreBreakdown` in `StyleMatchAI/ScanView.swift` | Computes color/pattern/fit/accessory score | Sole numeric score authority |
| Garment category | `OutfitClassificationEngine` and `OutfitClassificationResult` in `StyleMatchAI/Models.swift` | Typed garment classification with evidence and correction | Preferred category authority, subject to confirmation |
| Legacy purpose/category | `clothingPurposeClassification`, novelty rules, and traditional-attire rules in `StyleMatchAI/ScanView.swift` | Produces string garment/style/occasion/dress-code summaries | Parallel derived logic; not a safe future authority |
| Detected style | Scan heuristics, `detectedStyleTitle`, `styleBalance`, and classification display helpers in `StyleMatchAI/ScanView.swift` | Presents style/category labels | Multiple overlapping derivations; needs one typed style output |
| Occasion | `Occasion` in `StyleMatchAI/PersonalStylist/StylistProfileModels.swift`, scan selection, and legacy profile strings | Represents user intent and older profile data | Explicit scan selection is authority; legacy strings are fallback inputs |
| Formality conflict | `FormalityMismatchEvaluator` in `StylistProfileModels.swift` | Compares style/formality strings with occasion | Derived warning; currently unaware of purpose/workplace profile |
| Environment | `detectedEnvironment(from:)` in `ScanView.swift` | Maps Vision labels to a single string | Derived evidence only; currently mixes scene, style, and event |
| Weather facts | `WeatherContextSnapshot` in `StyleMatchAI/WeatherContextEngine.swift` | Typed conditions, activity, region, time, and confidence | Weather-fact authority for its snapshot |
| Weather activity | `WeatherContextEngine.inferActivity` | Infers activity from occasion/environment strings | Derived helper; currently inherits conflation |
| Scan persistence/history | Scan history persistence and `CurrentScanContextProvider.latestCompleted` | Restores saved results and selects latest completed scan | Persisted record is authority when valid |
| Current AI scan selection | `CurrentScanContextProvider` in `StyleMatchAI/StylistChat/StylistChatModels.swift` | Resolves explicit saved scan or latest completed scan | Sole current-scan selection authority |
| AI scan payload | `StylistAuthoritativeScanContext` and `ChatContext` | Carries authoritative scan facts to AI paths | Authoritative transport after provider validation |
| Screen awareness | `StylistScreenContext` and builders in `ScanView.swift`/`AIStyleAdvisor.swift` | Carries visible scan ID, score, tab, and entry point | Authority for what is visible, not for scan facts |
| AI Assist | Scan-to-advisor context construction in `ScanView.swift` and `AIStyleAdvisor.swift` | Explains the selected scan | Consumer; must not derive an independent context |
| Standalone chat | `StylistChatView` and `StylistChatService` | Resolves context immediately before send and filters stale turns | Consumer with correct provider boundary |
| Voice | `StyleMatchAI/VoiceAssistant/VoiceScriptBuilder.swift` | Formats scan summaries for speech | Consumer; currently chooses category or style presentation independently |
| Worker response | Chat proxy/response validation outside this iOS context proposal | Returns explanation under supported-version contract | Consumer/validator; never score or scan authority |

### 3.1 Conflations

- `detectedEnvironment(from:)` returns genuine scenes such as Office, Gym, or Beach, but also returns style/formality labels such as Business and Casual.
- `detectedStyleTitle` may display the effective garment category as the detected style.
- `OutfitClassificationResult` currently contains garment category, selected occasion, occasion compatibility, and scoring-profile selection in one record.
- `FormalityMismatchEvaluator` compares a style string with a generic occasion. A casual visual style can therefore be warned against `Work` even when a casual factory uniform is appropriate.
- `WeatherContextEngine.inferActivity` derives activity from combined occasion and environment strings, allowing purpose, place, and event to substitute for one another.
- Legacy `clothingPurposeClassification`, novelty rules, traditional-attire rules, profile strings, and the typed classifier can each produce competing garment, style, dress-code, or occasion descriptions.
- `styleBalance` and related presentation fields may carry category labels rather than a pure visual-style assessment.

### 3.2 Existing authorities that must be retained

| Fact | Authority |
|---|---|
| Numeric overall style score and breakdown | Completed scan analysis |
| Scan identity and completion time | Persisted scan record/current active scan |
| Garment visual evidence | Vision observations and privacy-safe evidence summaries |
| User-selected occasion | Explicit occasion selection |
| User-confirmed category/purpose/profile | Per-scan confirmation record |
| Current scan for AI | `CurrentScanContextProvider` |
| Current visible screen state | `StylistScreenContext` |
| Weather facts | `WeatherContextSnapshot` |
| Shopping/catalog facts | Out of scope and unchanged |

### 3.3 Duplicate logic to retire through migration

- Legacy `ClothingPurposeMatch` string construction in `ScanView.swift`.
- Environment rules that classify Business or Casual as locations.
- Separate formatting of category/style for Scan, AI Assist, chat, and voice.
- String-only compatibility and mismatch logic.
- String-derived weather activity when a typed purpose/profile is available.

Retirement must be phased. Existing saved scans continue to decode, and legacy strings remain display fallbacks until typed context is proven.

## 4. Proposed typed contract

The existing `CurrentScanContextProvider` remains the single scan selector. It supplies one versioned `OutfitContextSnapshot`:

```swift
struct OutfitContextSnapshot: Codable, Equatable {
    let schemaVersion: Int
    let generation: Int
    let scanID: String
    let completedAt: Date

    let detectedStyle: EvidenceBackedValue<DetectedStyle>
    let garmentCategory: EvidenceBackedValue<OutfitCategory>
    let outfitPurpose: EvidenceBackedValue<OutfitPurpose>
    let environmentType: EvidenceBackedValue<EnvironmentType>

    let selectedOccasion: Occasion?
    let occasionCompatibility: SuitabilityAssessment
    let workplaceProfile: EvidenceBackedValue<WorkplaceProfile>
    let workplaceSuitability: SuitabilityAssessment
    let weatherContext: WeatherContextReference
    let weatherSuitability: SuitabilityAssessment
    let safetyContext: SafetyContext
    let safetySuitability: SuitabilityAssessment

    let userConfirmedPurpose: OutfitPurpose?
    let confidence: ContextConfidence
    let evidence: [ContextEvidence]
    let missingEvidence: [MissingEvidence]
    let scoringProfile: PurposeScoringProfileID
    let provenance: ContextProvenance
}
```

Supporting rules:

- `EvidenceBackedValue` stores the proposed value, confidence, evidence identifiers, origin, and confirmation state.
- `SuitabilityAssessment` is initially categorical (`high`, `moderate`, `low`, `uncertain`, `notApplicable`) with rationale and confidence. It is not a new score.
- `WeatherContextReference` contains only the minimum typed weather facts and the snapshot timestamp; exact location is excluded from AI context unless separately required and approved.
- `SafetyContext` records visible/confirmed requirements, supported observations, missing observations, and explicit limitations. It does not certify compliance.
- `ContextProvenance` identifies algorithm version, source scan, evidence timestamps, user corrections, and legacy-fallback use.
- `generation` increments when the user changes purpose/profile or a new completed scan replaces the active scan.

### 4.1 Separate concepts

Example:

```text
detectedStyle: Casual
garmentCategory: Branded Workwear
outfitPurpose: Factory / Manufacturing
environmentType: Home
selectedOccasion: Work
workplaceProfile: Factory / Manufacturing
occasionCompatibility: High
workplaceSuitability: High
weatherSuitability: Moderate
safetySuitability: Uncertain (footwear not visible)
```

No field overwrites another.

## 5. Context construction and validation flow

1. Capture immutable image/session identity.
2. Produce visual observations, garment observations, OCR-presence evidence, palette/pattern/fit evidence, and scene evidence.
3. Compute the existing numeric score exactly as today.
4. Classify visual style and garment category independently.
5. Infer purpose candidates from garment structure, selected occasion, environment, accessory/footwear combinations, and privacy-safe text/branding presence.
6. Apply confidence and confirmation rules from `OUTFIT_PURPOSE_TAXONOMY.md`.
7. Resolve an explicit user purpose/profile correction last; retain the original model proposal in provenance.
8. Evaluate occasion, workplace, weather, and safety suitability separately.
9. Persist the completed analysis plus the additive versioned context snapshot.
10. Have `CurrentScanContextProvider` return the same snapshot to Scan Results, AI Assist, chat, saved-scan AI, and voice.
11. Validate screen scan ID, generation, purpose/profile confirmation, score, and compatibility snapshot before a response.

## 6. Fail-closed rules

- Scan IDs differ: do not include scan-specific context.
- Score differs from the authoritative analysis: reject the context; never reconcile by choosing a value.
- Context generation differs from the visible screen: refresh before sending.
- User-confirmed purpose/profile differs: prefer the persisted confirmation only after verifying the same scan ID and generation.
- Evidence is missing: mark it missing; do not convert absence into a negative finding.
- Purpose and workplace profile conflict: show uncertainty and ask one confirmation question.
- Legacy scan has no typed context: derive an explicitly labeled transient legacy context; do not persist it without user action or a separately approved migration.
- Safety evidence is incomplete: say “not verified,” never “safe.”

## 7. Expected implementation file boundary

No files below are changed by this design checkpoint. Expected future changes:

### New production files

- `StyleMatchAI/ContextEngine/OutfitContextSnapshot.swift`
- `StyleMatchAI/ContextEngine/OutfitPurpose.swift`
- `StyleMatchAI/ContextEngine/WorkplaceProfile.swift`
- `StyleMatchAI/ContextEngine/ContextEvidence.swift`
- `StyleMatchAI/ContextEngine/OutfitContextEngine.swift`
- `StyleMatchAI/ContextEngine/PurposeClassifier.swift`
- `StyleMatchAI/ContextEngine/SuitabilityEvaluator.swift`
- `StyleMatchAI/ContextEngine/PurposeScoringProfile.swift`
- `StyleMatchAI/ContextEngine/ContextValidator.swift`
- `StyleMatchAI/ContextEngine/LegacyContextAdapter.swift`
- `StyleMatchAI/Scan/OutfitContextSection.swift`

### Modified production files

- `StyleMatchAI/Models.swift`
- `StyleMatchAI/ScanView.swift`
- `StyleMatchAI/PersonalStylist/StylistProfileModels.swift`
- `StyleMatchAI/WeatherContextEngine.swift`
- `StyleMatchAI/StylistChat/StylistChatModels.swift`
- `StyleMatchAI/StylistChat/StylistChatService.swift`
- `StyleMatchAI/StylistChat/StylistChatView.swift`
- `StyleMatchAI/AIStyleAdvisor.swift`
- `StyleMatchAI/VoiceAssistant/VoiceScriptBuilder.swift`
- `StyleMatchAI.xcodeproj/project.pbxproj`
- `Package.swift`

### Tests

- `StyleMatchProPhase2Tests/ContextEngineTests.swift`
- `StyleMatchProPhase2Tests/OutfitPurposeTaxonomyTests.swift`
- `StyleMatchProPhase2Tests/WorkplaceProfileTests.swift`
- `StyleMatchProPhase2Tests/SuitabilityEvaluatorTests.swift`
- `StyleMatchProPhase2Tests/ContextPersistenceTests.swift`
- `StyleMatchProPhase2Tests/AIContextConsistencyTests.swift`
- `StyleMatchProPhase2Tests/ScreenContextValidationTests.swift`
- `StyleMatchProPhase2Tests/VoiceContextConsistencyTests.swift`
- Existing classification, chat, scan, persistence, weather, and voice tests where fixtures must gain additive fields

The final implementation boundary must be revalidated immediately before editing.

## 8. Impact analysis

### Migration and persistence

- Add an optional versioned `outfitContext` to persisted scan analysis.
- Preserve legacy decoding exactly; absent fields map to an unpersisted `.legacyUncertain` adapter.
- Do not rewrite retained scans in place.
- Persist user confirmations as per-scan authority with timestamp and prior proposal in provenance.
- Unknown future enum values must decode to `otherUncertain`/`other` without data loss.

### Performance

- Reuse the existing Vision labels and OCR request; do not issue a second OCR pass.
- Purpose classification and suitability evaluation are deterministic and should run from prepared observations.
- Target incremental context-engine CPU time: p95 below 20 ms after Vision/OCR completes.
- Measure end-to-end OCR and context latency on supported physical devices before acceptance.

### Privacy

- Raw OCR text, probable names, badges, faces, employer names, and precise locations are not persisted or sent to AI.
- Evidence records retain generic facts such as “embroidered text present,” not the text itself.
- Employer and wearer identity inference is prohibited.
- Safety output is advisory and evidence-limited, not certification.

### Compatibility and chat health

- The Worker/API payload change must be additive and versioned.
- Older clients/workers ignore unknown context fields.
- Any implementation checkpoint must rerun frozen chat contracts, compatibility tests, stale-turn filtering, and supported-version health gates under ADR-006.

## 9. Narrow implementation phases

1. **CE1 — Types and legacy adapter:** add enums/contracts, decoding, provenance, and unit tests; no UI or scoring behavior.
2. **CE2 — Deterministic context engine:** generate purpose/profile/environment/suitability context from existing observations; no score changes.
3. **CE3 — Persistence and current-scan authority:** persist optional context and extend `CurrentScanContextProvider`; prove legacy and stale-context behavior.
4. **CE4 — Scan UX confirmation:** show purpose/profile/confidence and allow authoritative correction; no AI payload change.
5. **CE5 — AI and voice integration:** one typed prompt path, explanation contract, screen-context validation, and compatibility gates.
6. **CE6 — Physical acceptance:** device latency, OCR privacy, corrections, saved scans, AI Assist/chat/voice parity, interruptions, and retained-data additive integrity.
7. **PS1 — Optional scoring experiment:** only after separate approval of `PURPOSE_AWARE_SCORING_PROPOSAL.md`; never bundled into CE1–CE6.

Each phase requires a separate authorization, test report, and stop decision.

## 10. Authorization coverage matrix

| Authorized phase | Delivered design evidence | Completion |
|---|---|---|
| 1. Audit decision flow | Sections 2–3 of this document, including the 10-stage pipeline, authority inventory, conflations, and duplicate logic | Complete |
| 2. Typed Context Engine | Sections 4–6 of this document | Complete as design |
| 3. Purpose taxonomy | `OUTFIT_PURPOSE_TAXONOMY.md` | Complete as design |
| 4. Workplace profiles | `WORKPLACE_PROFILE_MATRIX.md` | Complete as design |
| 5. Score vs appropriateness | `PURPOSE_AWARE_SCORING_PROPOSAL.md`, sections 1–2 and 4 | Complete as design |
| 6. Purpose-specific scoring | `PURPOSE_AWARE_SCORING_PROPOSAL.md`, sections 3–7 | Complete as proposal; no runtime score change |
| 7. Confidence/confirmation | `OUTFIT_PURPOSE_TAXONOMY.md`, sections 1 and 5; `UX_PRESENTATION_PLAN.md`, sections 3–4 | Complete as design; implementation intentionally blocked |
| 8. AI explanations | `AI_EXPLANATION_CONTRACT.md` | Complete as design |
| 9. Screen awareness | `SCREEN_CONTEXT_UPDATE_PLAN.md` | Complete as design |
| 10. UX behavior | `UX_PRESENTATION_PLAN.md` | Complete as design |
| 11. Tests | `TEST_PLAN.md`, including all 20 named cases | Complete as test plan; no tests added or run |
| 12. Impacts/files/phases | Sections 7–9 of this document and all eight named deliverables | Complete |

The words “implement” and “update” in phases 7–9 are interpreted as design requirements here because the authorization’s controlling hard boundary forbids source edits until this architecture is reviewed. Runtime implementation remains unstarted.
