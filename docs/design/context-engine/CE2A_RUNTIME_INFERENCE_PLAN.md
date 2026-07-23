# CE2A Runtime Context Inference Plan

Status: **Planning authority only — no CE2A implementation or runtime behavior is active**

Authority:

- Branch: `feature/expanded-garment-classification`
- Planning baseline: `e5b9df1c39c620f5b8e8459a6c2222382fdeb49c`
- CE1 implementation: `369c464737386e6ae21801d217de15b8cd8c997d`
- Governing decisions: ADR-001, ADR-002, ADR-003, ADR-006, ADR-007
- Governing design package: `docs/design/context-engine/`

## 1. Scope

CE2A introduces a deterministic, side-effect-free runtime inference engine that can construct a transient `OutfitContextSnapshot` from already-available authoritative scan inputs.

CE2A may derive:

- outfit purpose;
- workplace profile;
- physical environment type;
- occasion compatibility;
- workplace suitability;
- weather suitability;
- safety suitability;
- aggregate context confidence;
- privacy-safe supporting and conflicting evidence;
- explicit missing evidence;
- field-level provenance.

CE2A compiles into the application and Swift Package, but no existing runtime consumer calls it. Tests invoke the engine directly. The existing Scan Results, AI Assist, standalone AI Stylist Chat, saved-scan AI, voice, screen-context, persistence, and Shopping paths remain unchanged.

## 2. Non-goals

CE2A does not:

- change, recompute, normalize, or reinterpret the Overall Style Score or breakdown;
- replace `OutfitClassificationResult` as garment-category authority;
- modify `calculateStyleScore`;
- persist `OutfitContextSnapshot`;
- rewrite, migrate, backfill, or mutate legacy scans;
- repurpose any existing persistence key;
- adopt the snapshot in `CurrentScanContextProvider`;
- change AI prompts, payloads, validation, fallback, or Worker contracts;
- change Scan Results, UI confirmation, screen awareness, keyboard, microphone, or voice behavior;
- infer or display employer, wearer, occupation, school, event, gender identity, or precise workplace identity;
- retain raw OCR text, names, badge values, or raw brand strings;
- activate purpose-aware numeric scoring;
- change Shopping, catalog, retailer, B5, signing, deployment, TestFlight, or App Store state.

Persistence belongs to CE3, user confirmation UI to CE4, AI/voice adoption to CE5, and physical acceptance to CE6.

## 3. Authority map and exact source inputs

CE2A accepts one immutable `ContextInferenceInput`. The caller must supply a completed scan identity and the existing typed facts; CE2A does not read global state, `UserDefaults`, files, network services, UI state, or conversation history.

| Input | Current source | Authority | CE2A use |
|---|---|---|---|
| `scanID` | Completed scan record/session | Authoritative identity | Copied exactly; empty identity fails closed |
| `completedAt` | Completed scan record | Authoritative timestamp | Copied to snapshot and provenance |
| `score` | `OutfitAnalysisResult.score` | Sole Scan score authority | Copied exactly; never recalculated |
| `scoreBreakdown` | `OutfitAnalysisResult.scoreBreakdown` | Sole Scan breakdown authority | Copied exactly |
| `garmentClassification` | `OutfitAnalysisResult.outfitClassification` | Garment-category authority, including user category correction | Effective category and category confidence only |
| `detectedStyle` | Completed analysis `styleBalance` or an explicitly supplied normalized style | Existing visual-style evidence | Kept separate from category and purpose |
| `selectedOccasion` | Explicit scan occasion; classification occasion only as labeled fallback | User authority when explicit | Context constraint, never sufficient alone |
| `environmentLabel` | Completed analysis environment | Derived physical-scene evidence | Whitelist mapping only; style/formality labels map to uncertain |
| `weather` | `WeatherContextReference` produced from `WeatherContextSnapshot` | Typed weather facts | Separate weather suitability only |
| `classificationEvidence` | `OutfitClassificationResult.evidence` | Existing privacy-bounded category evidence | Kind, confidence, and generic presence only |
| `hasTextEvidence` | Presence of `.visibleText` evidence | Generic OCR-presence signal | Boolean/count only; no text content |
| `hasBrandingEvidence` | Presence of `.branding` evidence | Generic branding-presence signal | Boolean/count only; no brand content |
| `confirmedPurpose` | Transient caller-supplied per-scan correction | User authority for same scan | Highest purpose precedence |
| `confirmedWorkplaceProfile` | Transient caller-supplied per-scan correction | User authority for same scan | Highest workplace precedence |
| `rejectedPurposeIDs` | Transient caller-supplied per-scan rejection set | User authority for same scan | Removes rejected proposals; never selects an alternative |

`ContextInferenceInput` must not contain:

- raw image bytes;
- raw OCR strings;
- `OutfitTextObservation.text`;
- `OutfitClassificationResult.detectedText` content;
- `OutfitClassificationResult.detectedBranding` content;
- names, badge numbers, employer identifiers, face data, account data, or precise location;
- AI or conversation text.

The input builder may inspect evidence kinds and counts, but must discard text-bearing values before constructing the input.

## 4. CE1 contract extensions required by CE2A

CE1 does not currently distinguish authoritative scan facts from runtime-inferred facts in `ContextValueOrigin`. Reusing `.legacyDerived` would create false provenance. CE2A therefore requires additive, backward-compatible cases:

```swift
enum ContextValueOrigin {
    // Existing
    case legacyDerived
    case userConfirmed
    case unknown

    // CE2A additive cases
    case scanAuthoritative
    case runtimeInferred
}
```

`ContextProvenanceField` requires additive cases for:

- `occasionCompatibility`;
- `workplaceSuitability`;
- `weatherSuitability`;
- `safetySuitability`;
- `overallConfidence`.

Unknown encoded cases continue to fail closed through the CE1 decoder. No field is removed, renamed, or retyped. Schema version remains `1` while the snapshot is transient and the additions are enum vocabulary only; CE3 must decide persistence schema evolution before any record is written.

## 5. Inference order and precedence

The engine executes these steps in a fixed order:

1. Validate structural authority: non-empty `scanID`, score in `0...100`, finite confidence values, and matching supplied scan identity.
2. Copy the authoritative score and breakdown without transformation.
3. Resolve garment category from `OutfitClassificationResult.effectiveCategory`.
4. Normalize detected visual style independently; blank or unsupported style becomes `Other / Uncertain`.
5. Map only a whitelisted physical environment; Business, Casual, Formal, and other style/formality strings become `otherUncertain`.
6. Convert classification evidence into privacy-safe evidence atoms using kind, bounded confidence, and fixed generic summaries.
7. Apply a user-confirmed purpose when supplied for the same scan.
8. Otherwise score purpose candidates using the deterministic evidence model in Section 6.
9. Apply rejected-purpose filtering. Rejection returns the rejected candidate to uncertainty and never promotes the runner-up automatically.
10. Apply specialized-purpose confirmation rules. A specialized result may be proposed but is not confirmed by inference.
11. Resolve workplace profile from explicit confirmation first, then from a supported work-purpose proposal; keep suitability uncertain until confirmation.
12. Derive occasion, workplace, weather, and safety suitability independently.
13. Produce missing-evidence records for every unavailable authority needed by the result.
14. Compute aggregate confidence from the resolved fields and conflicts.
15. Produce complete field-level provenance.
16. Validate invariants: score equality, no private strings, no confirmed inference without user authority, and deterministic ordering.
17. Return the transient snapshot or a typed fail-closed error.

Precedence is:

1. Same-scan user confirmation or correction.
2. Existing authoritative scan category and score facts.
3. Deterministic evidence-backed inference.
4. Explicit uncertainty.

Conversation memory, display labels, unvalidated legacy strings, OCR content, background alone, and selected occasion alone never establish purpose or workplace profile.

## 6. Confidence model and evidence weighting

### 6.1 Thresholds

- High: `>= 0.82`
- Medium: `0.55..<0.82`
- Low: `< 0.55`

Taxonomy-specific minimums from `OUTFIT_PURPOSE_TAXONOMY.md` still apply. The stricter threshold wins. Examples:

- Factory / Manufacturing: minimum proposal `0.72`
- Healthcare: minimum proposal `0.78`
- Construction: minimum proposal `0.78`
- Wedding Dress: minimum proposal `0.86`

No inferred specialized purpose becomes `.confirmed`, regardless of confidence.

### 6.2 Weighted evidence groups

Candidate support is the bounded weighted sum of independent evidence groups:

| Evidence group | Maximum contribution | Rules |
|---|---:|---|
| Authoritative garment category | 0.40 | Uses effective category and bounded classifier confidence |
| Garment construction/silhouette | 0.15 | Uses generic evidence kind and confidence; no free-form summary matching |
| Explicit selected occasion | 0.15 | Constraint only; cannot establish purpose alone |
| Generic text/branding presence | 0.10 | Presence only; cannot establish purpose alone |
| Whitelisted physical environment | 0.10 | Background alone is insufficient |
| Accessory/footwear combination | 0.05 | Uses generic evidence kinds when available |
| Existing compatible category/occasion signal | 0.05 | May support but not override category authority |

Rules:

- Each group contributes at most its listed maximum.
- Repeated evidence within a group cannot inflate its maximum.
- At least two independent groups are required for any proposal except an explicit same-scan user confirmation.
- OCR/branding presence, selected occasion, or environment alone always yields uncertainty.
- Evidence order is canonicalized before calculation so array order cannot affect output.
- Unsupported free-form summaries are ignored rather than keyword-scored.
- Confidence values are clamped to `0...1`; non-finite values produce a typed invalid-input failure.

### 6.3 Conflict penalties

- Direct category conflict: `-0.30`
- Explicit occasion conflict: `-0.20`
- Physical-environment conflict: `-0.10`
- Missing secondary evidence: no penalty; record it as missing
- Competing candidates within `0.08`: result remains uncertain and exposes up to three ordered proposals
- Any user-rejected candidate: removed from eligible proposals

A score below the taxonomy minimum is not rounded up. Conflicts that leave no safe proposal produce `otherUncertain`.

## 7. Purpose inference rules

The purpose classifier uses stable category-to-purpose rules rather than natural-language keyword matching.

| Existing category | Eligible purpose candidates | Required additional support |
|---|---|---|
| `workUniform`, `brandedWorkwear` | Factory, Warehouse, Retail, Hospitality, Outdoor Work, Remote Work | Work occasion plus construction, confirmed profile, or whitelisted environment; always confirm |
| `medicalScrubs` | Healthcare | Work occasion or explicit confirmation; always confirm |
| `schoolUniform` | School | School context or explicit confirmation; always confirm |
| `businessCasual`, `femaleBusinessDress` | Business Casual Office, Office, Everyday Casual | Work/Business Formal selection or explicit confirmation |
| `businessFormal`, `mensSuit` | Business Formal, Office, Formal Event, Wedding Guest | Occasion evidence required |
| `tuxedo` | Formal Event, Wedding Guest, Wedding Party | Occasion evidence required |
| `weddingDress` | Wedding Dress | Minimum 0.86 and confirmation required |
| `bridesmaidDress` | Wedding Party, Wedding Guest, Formal Event | Confirmation required for Wedding Party |
| `cocktailDress`, `eveningGown` | Date Night, Formal Event, Wedding Guest | Occasion evidence required |
| `casualDress`, `casualWear` | Everyday Casual, Date Night, Remote Work | Occasion/context support required for non-casual purpose |
| `sportswear`, `activewear` | Sports, Gym / Training | Sport/gym context or confirmation |
| `swimwear` | Vacation | Beach/vacation context or confirmation; otherwise uncertain |
| `outerwear` | Travel, Outdoor Work | Context required; garment alone is insufficient |
| `traditionalCulturalAttire` | Formal Event or Other / Uncertain | Never infer culture, nationality, religion, or event; confirmation required |
| `footwear`, `accessories`, `otherUncertain` | Other / Uncertain | No purpose from a partial-item category alone |

Visual style never maps directly to purpose.

## 8. Uniform confirmation rule

Specialized workwear and uniforms always remain `.proposed` until the user confirms:

- Factory / Manufacturing
- Warehouse
- Healthcare
- Retail branded/service uniform
- Hospitality
- Construction
- Outdoor Work
- School uniform
- Wedding Party
- Wedding Dress
- Funeral

CE2A represents the likely candidate and `confirmationState: .proposed`. Workplace and safety suitability remain `.uncertain` while confirmation is absent. Rejection:

- records the rejected candidate in the transient input/output provenance;
- returns purpose/profile to uncertain;
- does not auto-select the second-ranked candidate;
- does not change garment category, detected style, score, or breakdown.

Confirmation is input-only in CE2A. No UI or persistence flow is added.

## 9. Workplace-profile inference

Workplace profile is evaluated only when:

- selected occasion is Work; or
- purpose is a work purpose; or
- the caller supplies a same-scan confirmed workplace profile.

Rules:

1. Explicit same-scan profile confirmation wins.
2. A confirmed work purpose maps to its matching profile.
3. A proposed specialized work purpose may produce a proposed profile, but workplace suitability remains uncertain.
4. `workUniform` or `brandedWorkwear` alone cannot choose Factory, Warehouse, Retail, or Hospitality.
5. `medicalScrubs` may propose Healthcare when an independent Work signal exists, but still requires confirmation.
6. Construction requires high-visibility/protective-construction evidence plus Work or confirmation; background alone is insufficient.
7. Home environment never implies Remote Work.
8. Office environment never implies the wearer has an office occupation.
9. No employer, occupation, facility, school, or job title is produced.
10. Non-work purposes use `otherUncertain` with workplace suitability `.notApplicable`.

## 10. Environment inference

CE2A maps only normalized, whitelisted physical scene values:

- Home
- Office
- Closet
- Bedroom
- Retail Store
- Dressing Room
- School
- Gym
- Beach
- Outdoors
- Parking Garage
- Event Venue
- Place of Worship

Rules:

- Business, Casual, Formal, Professional, Work, Party, and similar style/occasion labels map to `otherUncertain`.
- A background label supplies environment evidence only.
- Environment confidence is capped at low unless the source is an explicit user-confirmed scene.
- Environment never identifies a workplace, employer, occupation, school, religion, event, or precise location.
- Unknown values fail closed to `otherUncertain`.

## 11. Suitability derivation

All suitability outputs are categorical and cannot affect the numeric score.

### 11.1 Occasion compatibility

- Confirmed purpose plus compatible selected occasion and no direct conflict: `.high` or `.moderate` according to evidence completeness.
- Proposed purpose with compatible occasion: at most `.moderate`.
- Direct confirmed conflict: `.low` with conflicting evidence IDs.
- Missing occasion or uncertain purpose: `.uncertain`.
- No occasion-specific purpose: `.notApplicable` only when supported by explicit non-contextual selection.

The existing `OutfitOccasionCompatibility` may contribute one bounded signal but cannot override purpose confirmation or create a new purpose.

### 11.2 Workplace suitability

- No work purpose/profile: `.notApplicable`.
- Work selected but profile missing or proposed only: `.uncertain`.
- Confirmed profile with supported visible evidence and no conflict: `.high` or `.moderate`.
- Confirmed profile with a direct evidence-backed conflict: `.low`.
- Missing evidence is listed and does not count as a negative.
- Casual visual style is not itself a workplace conflict.

### 11.3 Weather suitability

- Missing weather or confidence below `0.55`: `.uncertain`.
- Weather evidence is evaluated against confirmed/proposed purpose and visible garment evidence.
- Proposed or uncertain purpose caps weather suitability at `.moderate`.
- A direct high-confidence weather conflict may be `.low`.
- Weather suitability never changes the score and never invents a garment requirement.
- Exact location is excluded.

### 11.4 Safety suitability

- No safety-relevant confirmed purpose: `.notApplicable`.
- Safety-relevant purpose unconfirmed: `.uncertain`.
- Required evidence outside the image: `.uncertain` with “not visible,” never “absent.”
- Visible supporting cues may produce at most `.moderate` in CE2A.
- CE2A never emits certified-safe, compliant, OSHA-compliant, employer-compliant, or policy-compliant language.
- A direct visible conflict may be `.low` only for a confirmed purpose and a defined evidence rule.

## 12. Missing-evidence behavior

Missing evidence is explicit, stably identified, and never scored as failure.

Required identifiers include:

- `missing.detectedStyle`
- `missing.garmentCategory`
- `missing.purpose`
- `missing.occasion`
- `missing.workplaceProfile`
- `missing.environment`
- `missing.weather`
- `missing.safety`
- `missing.confirmation.<purposeID>`

The engine:

- emits each identifier at most once;
- sorts identifiers lexicographically;
- uses fixed generic reasons;
- never embeds raw OCR or user text;
- distinguishes missing from conflicting evidence;
- retains uncertainty rather than constructing a complete-looking result.

## 13. Provenance assignment

Every field records one of:

- `scanAuthoritative`: score, breakdown, effective garment category, explicit scan occasion;
- `runtimeInferred`: purpose proposal, environment mapping, suitability, aggregate confidence;
- `userConfirmed`: same-scan purpose/profile/category confirmation;
- `legacyDerived`: only output from `LegacyContextAdapter`;
- `unknown`: unsupported or missing authority.

Snapshot provenance:

- algorithm version: `ce2a-runtime-v1`;
- adapter version: `nil`;
- source scan ID and completion timestamp: copied exactly;
- `legacyFallbackUsed`: `false`;
- entries: canonical field order, never input-array order;
- generation: `0` because persistence and correction generation are CE3/CE4 concerns.

CE2A must not claim user confirmation for model inference.

## 14. Performance budget

CE2A reuses prepared scan/classification/weather facts and performs no Vision, OCR, image decode, network, disk, or persistence work.

Targets:

- p95 inference below 20 ms after existing Vision/OCR completes;
- one bounded pass over evidence;
- no regex over OCR text;
- no second OCR or classification request;
- bounded candidate set from the committed taxonomy;
- snapshot below 16 KB when encoded in tests, excluding existing analysis text;
- Debug timing instrumentation may record duration, evidence counts, selected candidate IDs, and fail-closed guard IDs only.

Instrumentation must not log raw OCR, brand strings, scan images, precise location, user identifiers, or conversation text.

## 15. Threading and concurrency model

CE2A is a pure synchronous value transformation:

- immutable input;
- local working state only;
- no singleton;
- no cache;
- no actor-owned mutable state;
- no global reads or writes;
- no callbacks or detached tasks;
- no UI or main-thread dependency.

The engine is safe to call from an existing analysis task. The future consumer owns scheduling. CE2A does not introduce `Task`, `DispatchQueue`, locks, notifications, observers, or `@MainActor` work.

Where supported by current compiler settings, new input/result helper values should conform to `Sendable`. If existing CE1 or legacy model types prevent checked `Sendable`, the implementation must not use `@unchecked Sendable`; it should keep the boundary synchronous and document the limitation.

## 16. Error handling

Expected uncertainty is data, not an error. It returns a valid snapshot with uncertain fields.

Typed structural failures include:

- empty or whitespace-only scan ID;
- score outside `0...100`;
- non-finite confidence;
- confirmed purpose/profile attached to a different scan identity;
- internally contradictory authoritative category state;
- invariant failure where the output score/breakdown differs from input;
- privacy validation failure.

The API should return:

```swift
Result<OutfitContextSnapshot, ContextInferenceFailure>
```

Failure returns no partial authoritative snapshot. Error values contain stable guard identifiers and generic messages only. They contain no raw evidence text or personal data.

## 17. Privacy boundaries

CE2A may retain only:

- generic evidence kinds;
- bounded confidence;
- fixed generic summaries;
- stable purpose/category/environment identifiers;
- missing/conflicting evidence IDs;
- timestamps and scan identity already authorized by the local scan record.

CE2A must discard or exclude:

- raw OCR;
- names and embroidered names;
- badge numbers;
- employer/brand/school strings;
- face or body identity;
- occupation;
- exact workplace or location;
- conversation and microphone content;
- image paths and bytes.

A privacy validator must reject any evidence summary not selected from a fixed internal catalog. Runtime evidence summaries cannot interpolate caller-provided strings.

## 18. Legacy behavior preservation and migration impact

- CE2A does not modify `OutfitAnalysisResult` coding keys.
- CE2A does not add an `outfitContext` persistence field.
- CE2A does not touch `CurrentScanContextProvider.latestCompleted`.
- CE2A does not read or write `UserDefaults`.
- CE2A does not rewrite existing saved scans.
- `LegacyContextAdapter` remains the only CE1 transient adapter for old records.
- Existing records, keys, scores, breakdowns, category confirmations, and history ordering remain byte-for-byte unchanged.
- CE3 must separately design optional persistence, schema versioning, generation, atomic correction, and legacy decoding before adoption.

Migration/persistence impact for CE2A: **none**.

## 19. Exact file-change forecast

### New production files

- `StyleMatchAI/ContextEngine/ContextInferenceInput.swift`
- `StyleMatchAI/ContextEngine/OutfitContextEngine.swift`
- `StyleMatchAI/ContextEngine/PurposeClassifier.swift`
- `StyleMatchAI/ContextEngine/WorkplaceProfileClassifier.swift`
- `StyleMatchAI/ContextEngine/SuitabilityEvaluator.swift`
- `StyleMatchAI/ContextEngine/ContextInferenceValidator.swift`

### Modified production/integration files

- `StyleMatchAI/ContextEngine/OutfitContextContracts.swift`
  - additive origin and provenance enum cases only;
  - no existing field removal, rename, or retyping.
- `Package.swift`
  - add new CE2A sources only.
- `StyleMatchAI.xcodeproj/project.pbxproj`
  - add new CE2A sources only.

### New tests

- `StyleMatchProPhase2Tests/ContextEngineCE2ATests.swift`

### Explicitly unchanged

- `StyleMatchAI/Models.swift`
- `StyleMatchAI/ScanView.swift`
- `StyleMatchAI/StylistChat/`
- `StyleMatchAI/AIStyleAdvisor.swift`
- `StyleMatchAI/VoiceAssistant/`
- `StyleMatchAI/PersonalStylist/`
- `StyleMatchAI/WeatherContextEngine.swift`
- all persistence/history files and keys;
- all Shopping, catalog, retailer, Worker, configuration, signing, and deployment files.

The implementation checkpoint must stop before editing if the exact required boundary expands beyond these files.

## 20. Test matrix

| ID | Case | Required assertions |
|---|---|---|
| CE2A-01 | Casual style plus factory-work purpose | Style remains Casual; Factory proposed; confirmation required; score unchanged |
| CE2A-02 | Casual style plus office purpose | Style remains Casual; Office supported only by independent Work/context evidence; score unchanged |
| CE2A-03 | Work selected with insufficient workplace evidence | Purpose/profile/workplace suitability uncertain |
| CE2A-04 | High-confidence uniform | Specialized purpose remains proposed; never auto-confirmed |
| CE2A-05 | Rejected uniform suggestion | Rejected purpose removed; runner-up not auto-selected; category/score unchanged |
| CE2A-06 | Factory background without uniform | Environment may map; purpose remains uncertain |
| CE2A-07 | Unreadable or ambiguous OCR | Generic text-presence evidence only; no raw text or identity |
| CE2A-08 | Medical scrubs | Healthcare proposed with independent Work signal; confirmation required |
| CE2A-09 | Construction workwear | Construction proposed only with workwear/protective evidence plus Work; safety stays advisory |
| CE2A-10 | Wedding attire | Wedding Dress requires threshold and confirmation; ambiguous gown remains uncertain |
| CE2A-11 | Casual dress | Category stays Casual Dress; Everyday Casual only with sufficient context |
| CE2A-12 | Ambiguous outfit | Purpose and profile remain uncertain; up to three ordered proposals |
| CE2A-13 | Conflicting occasion and garment | Conflict lowers confidence or fails closed; no forced purpose |
| CE2A-14 | Missing weather | Weather suitability uncertain; missing weather recorded |
| CE2A-15 | Missing occasion | Occasion compatibility and unsupported purpose remain uncertain |
| CE2A-16 | User-confirmed purpose | Same-scan confirmation wins; model proposal retained in provenance; score unchanged |
| CE2A-17 | Deterministic repeated inference | Equal input produces field-for-field and encoded-byte-equivalent output |
| CE2A-18 | No score mutation | Score and breakdown exactly equal input across every fixture |
| CE2A-19 | No persistence write | Source boundary contains no `UserDefaults`, file writes, keychain, database, or migration calls |
| CE2A-20 | No raw OCR retention | Encoded snapshot and errors exclude injected names, badge IDs, employers, and OCR text |
| CE2A-21 | Legacy compatibility | Existing CE1 legacy adapter results remain unchanged; no record rewrite |
| CE2A-22 | Environment conflation guard | Business/Casual/Formal labels map to environment uncertainty |
| CE2A-23 | Branding alone | Branding presence cannot establish work purpose or employer |
| CE2A-24 | Occasion alone | Work, Wedding, or Gym selection alone cannot establish purpose |
| CE2A-25 | Competing candidates | Candidates within `0.08` remain uncertain with stable ordering |
| CE2A-26 | Unknown future enums | Decode and inference fail closed to uncertain |
| CE2A-27 | Invalid score/input | Typed failure, no partial snapshot, no private error content |
| CE2A-28 | Confidence bounds | Non-finite input fails; finite confidence is clamped/bounded deterministically |
| CE2A-29 | Suitability separation | Four categorical metrics remain independent and never modify score |
| CE2A-30 | Consumer isolation | No production consumer references `OutfitContextEngine` outside CE2A files |
| CE2A-31 | Performance | Representative fixture loop meets the agreed deterministic budget in test instrumentation |
| CE2A-32 | Snapshot size | Representative encoded snapshot remains below 16 KB |

Focused tests must also preserve all 16 CE1 tests without modification.

## 21. Planned automated verification for implementation

The later CE2A implementation authorization should require:

1. focused CE2A tests;
2. focused CE1 tests;
3. existing garment-classification tests;
4. existing score-preservation/fingerprint tests;
5. persistence and legacy-decoding tests;
6. full Swift suite;
7. Debug simulator build;
8. Release simulator compile;
9. static analysis;
10. `git diff --check`;
11. source scan proving no persistence writer or consumer adoption;
12. protected Shopping/catalog hash comparison.

Worker tests and live health are NOT APPLICABLE to CE2A because payloads, Worker contracts, and consumers remain unchanged. Physical acceptance is NOT APPLICABLE to CE2A’s unconsumed pure engine, but becomes mandatory once CE3–CE5 adopts its output.

## 22. Stop rules

Stop implementation immediately if:

- any score or breakdown changes;
- a purpose is derived from visual style alone;
- OCR, branding, environment, or occasion alone establishes purpose;
- specialized workwear is marked confirmed without user authority;
- raw/private text enters input, snapshot, logs, errors, or fixtures;
- any persistence key or saved record is read or written by CE2A;
- any AI, UI, voice, screen-context, or Shopping consumer adopts the engine;
- an existing category correction is overwritten;
- deterministic repeated input produces unequal output;
- a conflict is hidden rather than recorded;
- the planned file boundary must expand;
- a CE1, classification, score, persistence, full-suite, build, static-analysis, or whitespace gate fails;
- Shopping/catalog hashes drift;
- repair would require B5, signing, device, deployment, TestFlight, or App Store action.

No failing gate may be waived inside CE2A.

## 23. CE2A acceptance matrix

| Criterion | Required evidence | Acceptance state before implementation |
|---|---|---|
| Pure transient inference | Source review and no-write tests | NOT EVIDENCED |
| Score/breakdown unchanged | Focused and existing score regressions | NOT EVIDENCED |
| Category authority preserved | Focused classification tests | NOT EVIDENCED |
| Style/purpose separation | Purpose fixtures | NOT EVIDENCED |
| Purpose/workplace uncertainty | Missing/conflict fixtures | NOT EVIDENCED |
| Specialized confirmation | Uniform/wedding/scrubs/construction fixtures | NOT EVIDENCED |
| Determinism | Equality and encoded-output tests | NOT EVIDENCED |
| Privacy | Injected-private-data tests and source/log scan | NOT EVIDENCED |
| Fail-closed behavior | Invalid/unknown/conflict tests | NOT EVIDENCED |
| No persistence adoption | Source boundary and legacy record tests | NOT EVIDENCED |
| No consumer adoption | Reference scan outside CE2A files | NOT EVIDENCED |
| Performance and size | Test instrumentation | NOT EVIDENCED |
| Full regression/build health | Full suite and simulator builds | NOT EVIDENCED |
| Shopping/catalog continuity | Pre/post hashes | NOT EVIDENCED |
| Physical evidence | Unconsumed pure engine | NOT APPLICABLE |

CE2A is accepted only when every applicable row is PASS and an append-only acceptance record is separately authorized and committed. Passing tests alone does not constitute acceptance.

## 24. Chat-health and rollback plan

Chat impact during CE2A: none at runtime. Binding, authentication, persistence, transport, prompt construction, Worker contracts, supported-client behavior, and live health are unchanged.

Rollback:

- CE2A must be isolated in one implementation commit.
- Because no consumer or persistence path adopts it, rollback is a source-only revert before CE3.
- No data migration or cleanup is required.
- CE3 must not begin until CE2A is formally reviewed, accepted, recorded, and synchronized.

## 25. Narrow implementation authorization

A future authorization may permit only:

1. additive CE1 origin/provenance enum cases described in Section 4;
2. the six new CE2A production files in Section 19;
3. Package and Xcode project source-list additions;
4. one new CE2A test file;
5. the automated checks in Section 21;
6. an implementation report and stop before commit.

It must continue to prohibit:

- persistence and migration;
- `CurrentScanContextProvider` adoption;
- AI, UI, voice, screen-context, and Shopping adoption;
- scoring changes;
- device, B5, signing, deployment, TestFlight, and App Store actions;
- commit and push unless separately authorized.

The implementation authorization must use the then-current clean local/remote HEAD and a fingerprint of this approved planning document.
