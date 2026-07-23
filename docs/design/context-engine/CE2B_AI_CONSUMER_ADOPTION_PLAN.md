# CE2B AI Consumer Adoption Plan

Status: **Planning only — no source, test, Worker, UI, persistence, scoring, voice, Shopping, or runtime behavior has changed**

Authority:

- Branch: `feature/expanded-garment-classification`
- Planning baseline: `f8479740f9d9edcd092b6d6a473d45d1a20bda74`
- CE1 typed contracts: accepted
- CE2A deterministic runtime inference: accepted
- Governing decisions: ADR-001, ADR-002, ADR-003, ADR-006, and ADR-007 in `docs/PROJECT_STATE.md`
- Governing design: all committed documents under `docs/design/context-engine/`

## 1. Scope

CE2B connects the accepted transient `OutfitContextSnapshot` to exactly three AI consumers:

1. scan-specific AI Assist;
2. standalone AI Stylist Chat;
3. the saved-scan AI handoff.

The integration is context-only. It makes one validated, typed snapshot the source of scan facts for every authorized AI request. It does not alter the completed scan, score, persisted scan history, screen presentation, voice behavior, or Shopping behavior.

CE2B must:

- resolve the authoritative scan immediately before each AI request;
- derive one transient snapshot through the accepted CE2A engine;
- bind the request, retained turns, and response to the same scan identity, schema version, and generation;
- preserve explicit historical-scan authority;
- refresh latest-scan authority before every standalone-chat send;
- remove competing AI-only scan reconstruction paths;
- fail closed on missing, stale, malformed, mismatched, or unsupported context;
- retain the existing score and evidence authority without recalculation;
- remain additive at the Worker boundary under ADR-006.

## 2. Non-goals

CE2B does not:

- change the numeric score or score breakdown;
- change scan or garment-classification algorithms;
- add purpose-confirmation or workplace-profile UI;
- change Scan Results presentation;
- change navigation, layout, labels, accessibility copy, or visible controls;
- change voice summaries, speech recognition, or microphone behavior;
- change the screen-awareness contract beyond consuming its existing scan identity and score guards;
- add or change persisted scan fields;
- add or change chat-history persistence fields;
- rewrite legacy scans or conversations;
- persist `OutfitContextSnapshot`;
- add a context cache;
- change Shopping, recommendations, catalog, retailer routing, or ownership claims;
- install on a device or claim physical acceptance;
- deploy or silently change the Worker contract.

## 3. Current-state audit and competing paths

The repository already has a strong score/scan authority boundary, but it does not yet have one typed context path.

| Consumer/path | Current behavior | CE2B finding |
|---|---|---|
| `CurrentScanContextProvider` | Resolves an explicit saved selection or latest valid completed scan and carries `StylistAuthoritativeScanContext` | Retain as the sole scan selector; extend its output through a separate transient snapshot resolver |
| `StylistChatView.currentConversationContext` | Resolves immediately before each standalone send | Correct freshness boundary; replace string-only context assembly with typed resolution |
| `StylistChatService` | Stamps messages with `scanContextID`; filters other scan IDs; also searches legacy assistant text for a conflicting `n/100` pattern | Keep scan-ID stamping; replace text guessing with a complete-turn typed policy |
| `PersonalizationContextBuilder.scanStylistContext` | Reconstructs score, garments, colors, style, occasion, and formality into strings | Retire it as scan-fact authority; retain only non-scan personalization formatting |
| `AIStyleAdvisor.profile` | Independently chooses active/recent scan strings and a score source | Remove scan selection and context reconstruction from this consumer |
| `OpenAIStylistClient` | Rebuilds `ChatContext` from flattened `StyleMatchStylistProfile` strings | Accept one already-resolved request context; do not derive scan facts |
| `ScanView` AI Assist | Builds scan-specific prompts and profile strings directly from `OutfitAnalysisResult` | Pass a scan selection intent and authoritative identity to the shared resolver |
| Saved-scan handoff | Passes an explicit `.savedSelection` context | Preserve fixed historical precedence until the interaction is left or another scan is selected |
| `OutfitContextEngine` | Pure deterministic CE2A inference with no production consumer | Adopt only through the shared transient resolver |

CE2B is incomplete if any production AI request can still obtain score, style, purpose, occasion, weather, suitability, confidence, or provenance from a parallel string builder.

## 4. Authority map

| Fact | Authority | Consumer rule |
|---|---|---|
| Scan ID and completion time | Active completed scan or persisted saved-scan record selected by `CurrentScanContextProvider` | Must match the snapshot and request binding |
| Overall score and breakdown | Completed `OutfitAnalysisResult` | Copied unchanged; never generated or reconciled by AI |
| Garment category and classification evidence | Completed scan classification | Passed into CE2A; never reconstructed from chat text |
| Detected visual style | Completed scan analysis | Remains distinct from purpose and garment category |
| Selected occasion | Explicit per-scan selection when available; otherwise accepted scan evidence | Passed once into CE2A |
| Purpose, workplace profile, environment, and suitability | Accepted CE2A inference from authoritative scan inputs | One transient `OutfitContextSnapshot` per request |
| User confirmation/correction | Existing per-scan authority, if present in the source analysis | Wins only when scan ID matches |
| Current/latest selection | `CurrentScanContextProvider` | Refreshed immediately before standalone sends |
| Explicit historical selection | Saved-scan handoff | Wins over newer scans for that interaction |
| Visible screen identity and score | `StylistScreenContext` | Validation guard only; never a scan-fact source |
| Conversation text | User/assistant history | Never an authority for score or context fields |
| Shopping/catalog facts | Existing Shopping/catalog authorities | Excluded from CE2B scan context |

## 5. Consumer dependency graph

```text
Completed scan or explicit saved-scan selection
                    |
                    v
       CurrentScanContextProvider
         (sole scan selector)
                    |
                    v
    OutfitContextConsumerProvider
       - validates scan identity
       - builds ContextInferenceInput
       - calls OutfitContextEngine
       - validates CE2A snapshot
       - returns immutable resolution
                    |
                    v
       AIConsumerContextEnvelope
       /             |             \
      v              v              v
Scan AI Assist  Standalone Chat  Saved-scan AI
      \              |              /
       \             |             /
        v            v            v
         ScanBoundRequestAssembler
                    |
                    v
              ChatRequest
                    |
                    v
       capability-approved Worker
```

No consumer may call `OutfitContextEngine` directly. No consumer may create a second `OutfitContextSnapshot`, choose a different scan, or flatten scan facts before the common request assembler validates them.

## 6. Consumer API

### 6.1 Selection intent

Use an explicit selection type:

```swift
enum AIOutfitContextSelection: Equatable {
    case latestCompleted
    case active(preferred: StylistAuthoritativeScanContext, screen: StylistScreenContext)
    case historical(preferred: StylistAuthoritativeScanContext, screen: StylistScreenContext)
}
```

Rules:

- `.latestCompleted` performs a fresh persisted latest-scan lookup for every send.
- `.active` requires the screen scan ID and visible score to match the preferred scan.
- `.historical` requires `.savedSelection`, an existing saved-scan ID, and a matching visible score when supplied.
- A historical selection never upgrades itself to latest based on timestamp.
- A nonhistorical preferred scan may be superseded only by a strictly newer, uniquely resolvable completed scan.
- Two latest candidates with equal completion timestamps are ambiguous. Fail closed unless an explicit active or historical selection resolves the identity.

### 6.2 Provider protocol

```swift
protocol OutfitContextConsumerProviding {
    func resolve(
        selection: AIOutfitContextSelection
    ) -> Result<AIConsumerContextEnvelope, AIConsumerContextFailure>
}
```

The production provider is dependency injected. Tests use fixtures. The provider is stateless, synchronous, and side-effect-free apart from the existing read-only latest/saved-scan lookup.

### 6.3 Immutable result

```swift
struct AIConsumerContextEnvelope: Equatable {
    let binding: AIContextBinding
    let authoritativeScan: StylistAuthoritativeScanContext
    let snapshot: OutfitContextSnapshot
    let screenContext: StylistScreenContext?
    let selectionKind: AIContextSelectionKind
}

struct AIContextBinding: Codable, Equatable {
    let scanID: String
    let completedAt: Date
    let authoritativeScore: Int
    let schemaVersion: Int
    let generation: Int
    let algorithmVersion: String
}
```

The envelope is created once per send. All downstream builders receive it as a value. They cannot substitute a different scan or snapshot.

## 7. Resolution and validation algorithm

For every request:

1. Receive an explicit selection intent from the consumer.
2. Resolve the scan through `CurrentScanContextProvider`.
3. Validate nonempty scan ID, valid completion time, score range, and source kind.
4. Validate the screen claim when the selection supplies screen context.
5. Load the matching authoritative `OutfitAnalysisResult` without writing it.
6. Require analysis score and breakdown to match `StylistAuthoritativeScanContext`.
7. Build `ContextInferenceInput` from the same scan ID, completion time, analysis, selected occasion, weather reference, and any existing scan-bound confirmations.
8. Run `OutfitContextEngine.infer`.
9. Require CE2A validation success.
10. Require snapshot scan ID, completion time, score, breakdown, schema version, provenance source scan ID, and algorithm version to match the resolved scan.
11. Create one immutable envelope and binding.
12. Build the request context and retained-message set from that envelope.
13. Revalidate the binding before accepting the completed response.

No fallback may choose a score from aggregates, the conversation, a profile string, or another saved scan.

## 8. Freshness and precedence

### 8.1 Scan AI Assist

- `ScanView` supplies `.active` for a newly completed scan.
- The selection is tied to the displayed scan ID and visible score.
- The provider derives the snapshot immediately before each send.
- If the displayed scan changes while AI Assist is open, the next send resolves the new active scan.
- If the request is already in flight when the active scan changes, its response is discarded as stale.

### 8.2 Standalone latest-scan chat

- Default standalone chat uses `.latestCompleted`.
- It refreshes the provider immediately before every typed, starter-prompt, or voice-transcribed send.
- A newly completed scan becomes authoritative without an app restart.
- The view must not retain a prior `ChatContext` as the source of the next request.
- Existing visible history remains visible; only grounding changes.

### 8.3 Saved-scan AI

- Opening a saved scan creates `.historical`.
- The selected scan remains authoritative even if a newer scan exists.
- Leaving the saved-scan interaction clears the historical selection.
- Returning to global AI uses `.latestCompleted`.
- Opening a different saved scan replaces the historical selection.
- A deleted, quarantined, unavailable, or mismatched saved scan fails closed; it does not fall through to latest while the UI still claims the historical scan.

### 8.4 Equal timestamps

- Latest selection with multiple valid scans sharing the maximum completion timestamp is ambiguous.
- Do not use lexical scan-ID ordering as evidence of recency.
- Return `.ambiguousLatestAuthority`.
- Explicit active/historical identity resolves the ambiguity if all other guards match.

## 9. Request contract

### 9.1 Additive typed extension

`ChatContext` gains one optional typed field:

```swift
var outfitContext: AIOutfitContextPayload?
```

The payload contains:

- `scanID`;
- `completedAt`;
- `authoritativeScore`;
- optional authoritative breakdown;
- `schemaVersion`;
- `generation`;
- `algorithmVersion`;
- detected style;
- garment category;
- outfit purpose;
- environment;
- selected occasion;
- workplace profile;
- four suitability values;
- confidence;
- privacy-safe evidence identifiers and fixed summaries;
- missing-evidence kinds;
- provenance fields required to validate authority.

The extension is additive. Existing `authoritativeScan`, `activeScan`, `scoreBreakdown`, and screen fields remain during CE2B compatibility rollout, but they must be generated from the envelope—not independently.

### 9.2 Canonical serializer

One `AIOutfitContextPayloadBuilder` converts `AIConsumerContextEnvelope` to request payload. It:

- preserves score and breakdown exactly;
- sorts evidence and missing evidence deterministically;
- enforces bounds;
- emits no raw OCR, location, employer, wearer, name, badge, or image data;
- refuses mismatched or unsupported schema versions;
- derives legacy string fields only from the same envelope during compatibility rollout.

No view, `AIStyleAdvisor`, `OpenAIStylistClient`, or prompt builder formats scan facts independently.

### 9.3 Worker compatibility

Before the typed field is sent to production:

1. freeze the existing request fixture;
2. prove the current Worker either ignores the optional field safely or accepts it under an explicit supported-version capability;
3. add Worker contract tests that validate the typed extension and preserve old-client behavior;
4. verify the supported-client health gate under ADR-006;
5. retain the current authoritative legacy fields as a temporary compatibility projection from the same envelope.

If capability is absent:

- do not silently flatten new purpose/workplace/suitability claims into unrelated legacy fields;
- send only the existing authoritative scan fields derived from the envelope;
- use a local evidence-bound fallback for questions that require unsupported typed dimensions;
- report the unsupported capability through a privacy-safe guard ID.

Worker changes, deployment, and live health execution require a separate authorization. CE2B cannot be accepted until the Worker compatibility evidence required by ADR-006 exists.

## 10. Stale-conversation policy

### 10.1 Structured authority

Conversation text is never parsed to decide which score, style, purpose, occasion, weather, or suitability is true.

The existing legacy score regex is transitional only. CE2B removes it from the authoritative path. It may not be expanded to search for phrases such as “74 points,” style names, occasion words, or weather text.

### 10.2 Complete-turn assembly

A complete turn is:

- one user message; and
- its following completed assistant message;
- both with the same existing `scanContextID`.

Request assembly groups history into complete turns before applying the message-count limit.

Rules:

- a turn bound to another scan ID is excluded in full;
- a legacy turn with no scan ID is excluded from scan-fact grounding whenever an authoritative snapshot is present;
- an incomplete historical user or assistant message is excluded;
- the new current user message remains included even though its assistant reply does not yet exist;
- local error rows and empty assistant messages are excluded;
- visible persisted history is not deleted or rewritten;
- message order is preserved;
- the final payload never contains a dangling user message from a removed turn.

### 10.3 Schema and generation

CE2B does not change chat-history persistence. Therefore:

- the in-flight request carries the full `AIContextBinding`;
- active-session completed turns may retain an in-memory binding sidecar;
- restored conversations have only their existing optional `scanContextID`;
- restored legacy turns without schema/generation proof are visible but excluded from scan-specific grounding;
- restored turns with a matching scan ID still cannot supply structured facts; the fresh snapshot supplies them;
- schema/generation mismatch invalidates grounding for the full turn.

A later persistence checkpoint may add durable context binding metadata. CE2B must not do so.

### 10.4 Stale text examples

The following text may remain visible but cannot override the envelope:

- `74/100`;
- `74 points`;
- an old detected style;
- an old occasion;
- old weather;
- an old purpose or workplace profile;
- an old assistant refusal claiming that it can only see a prior scan.

Correctness comes from typed exclusion and fresh context, not phrase matching.

## 11. In-flight response validation

Each send captures an immutable `AIContextBinding` and request UUID.

Before appending or displaying a completed response:

1. verify the request is still the active request;
2. re-resolve the relevant selection;
3. compare scan ID, score, schema version, generation, and algorithm version;
4. reject the response if authority changed;
5. reject a malformed or empty response using existing error handling;
6. do not mutate conversation context on failure;
7. preserve the user draft or allow a deliberate retry through existing controls.

Token streaming may render only after the response validator has enough bounded content to apply existing safety checks. If the current transport cannot validate safely during streaming, CE2B must buffer the scan-specific response and display it only after validation rather than expose stale tokens.

## 12. Error and no-context behavior

Define:

```swift
enum AIConsumerContextFailure: Equatable {
    case noCompletedScan
    case missingSelectedScan
    case quarantinedOrDeletedScan
    case ambiguousLatestAuthority
    case screenIdentityMismatch
    case scoreMismatch
    case contextInferenceFailed(String)
    case unsupportedSchemaVersion
    case unsupportedWorkerCapability
    case contextChangedDuringRequest
    case payloadTooLarge
}
```

Behavior:

- General styling questions may proceed in explicit no-scan mode.
- A scan-specific question must not proceed with fabricated or fallback scan facts.
- Historical-selection failure must not silently switch to latest.
- Context mismatch produces a recoverable, nontechnical message asking the user to reopen or retry.
- Offline and timeout errors preserve the binding but do not save an incomplete assistant turn.
- A malformed backend response cannot mutate, replace, or confirm context.
- No error path writes scan or context data.

## 13. Dependency injection and concurrency

### 13.1 Injection

- `StylistChatService` receives `OutfitContextConsumerProviding` and a selection provider.
- Scan AI Assist receives the same protocol through its request service, not through a view-owned string.
- `OpenAIStylistClient` receives an already-assembled `ChatRequest`; it does not choose scan context.
- Test fixtures inject deterministic provider results and transport responses.

### 13.2 Threading

- CE2A inference remains pure and synchronous.
- Scan-history reads occur once per request resolution.
- Request assembly operates on immutable values.
- UI state changes remain `@MainActor`.
- Provider/inference work may run off-main only if the caller passes immutable input.
- No singleton, notification observer, lock, cache, or shared mutable “last score” is introduced.
- Rapid sends are serialized by the existing active-request guard; a second send cannot reuse a stale envelope.

## 14. Context-version handling

- Accept only `OutfitContextSnapshot.currentSchemaVersion`.
- Unknown future schema versions fail closed.
- Require `snapshot.provenance.algorithmVersion == OutfitContextEngine.algorithmVersion`.
- Require nonnegative generation.
- Generation is part of request identity even while CE2A currently emits generation `0`.
- A future correction checkpoint may increment generation, but CE2B must already reject mismatches.
- Legacy `StylistAuthoritativeScanContext` without a snapshot may be adapted transiently only through the accepted CE2A input and engine; it may not be sent as purpose-certain context.

## 15. Privacy boundaries

Allowed:

- scan ID required for internal binding;
- score and breakdown;
- typed category, style, purpose, occasion, workplace profile, environment class;
- categorical suitability;
- bounded confidence;
- fixed privacy-safe evidence summaries and IDs;
- missing-evidence kinds;
- algorithm/schema/generation provenance.

Prohibited:

- raw OCR text;
- names, badges, employer or school identity;
- wearer identity or gender identity;
- faces or image bytes;
- image paths, URLs, or device identifiers;
- precise location;
- private Shopping URLs, tokens, or account data;
- raw conversation diagnostics;
- invented occupation, event, brand, or ownership.

Diagnostics contain only guard ID, selection kind, schema version, generation, payload byte count, retained/excluded turn counts, resolution duration, and success/failure category. Scan IDs are omitted or irreversibly truncated/hashed under the existing privacy logging policy.

## 16. Performance and request-size budget

Targets:

- CE2A inference remains p95 below 20 ms after scan evidence is available;
- provider selection plus inference and validation: p95 below 30 ms;
- payload serialization: p95 below 5 ms;
- context refresh occurs once per send;
- no second Vision, OCR, classification, or weather request;
- typed context extension: maximum 16 KB excluding existing analysis text;
- complete request remains within the existing service/body limit;
- maximum 20 request messages and 2,000 UTF-16 units per message remain unchanged.

Compaction order if the context extension approaches 16 KB:

1. preserve binding, score, breakdown, schema, generation, and algorithm version;
2. preserve typed values and confirmation states;
3. preserve suitability levels and confidence;
4. preserve missing-evidence kinds;
5. retain only referenced evidence;
6. drop optional fixed summaries last.

Never truncate identifiers or enum raw values into a different valid meaning.

## 17. Telemetry and diagnostics

Debug-only or existing privacy-safe diagnostics record:

- `ce2b.resolve.started`;
- `ce2b.resolve.succeeded`;
- `ce2b.resolve.failed.<guard>`;
- `ce2b.history.turn_excluded.<reason>`;
- `ce2b.request.capability.<supported|legacy|blocked>`;
- `ce2b.response.binding_changed`;
- inference and serialization durations;
- encoded context and request byte counts;
- number of complete turns retained and excluded.

Do not log request text, response text, score, OCR, scan image metadata, raw scan ID, profile values, or typed evidence summaries.

## 18. Backend and response compatibility

Required compatibility evidence:

- current-client/current-Worker request passes;
- current-client/typed-capable Worker request passes;
- old client remains accepted by typed-capable Worker;
- unsupported capability follows the documented local fallback;
- `400`, `401`, `413`, `429`, timeout, malformed SSE, and empty response behavior remain stable;
- authentication headers and endpoint selection remain unchanged;
- supported-version health gate passes before physical acceptance;
- response validation preserves the authoritative binding.

CE2B does not introduce a new response shape unless separately designed and authorized. The Worker continues to stream text; the iOS client validates it against the immutable request binding and the existing response-safety contract.

## 19. Rollback plan

CE2B must be isolated in one implementation commit and one later acceptance commit.

Rollback:

1. disable typed context emission with one compile-time/internal capability gate;
2. retain the accepted CE1/CE2A contracts and inference engine;
3. restore the pre-CE2B legacy request projection, which is generated from the same scan authority while rollback is active;
4. do not roll back, rewrite, or migrate saved scans or chat history;
5. do not change score, Shopping, or catalog state;
6. revert the isolated CE2B commit if the compatibility or physical gate fails.

Rollback cannot claim typed-context acceptance. It returns AI consumers to the prior accepted scan-authority behavior while leaving CE1/CE2A dormant.

## 20. Exact file-change forecast

The forecast must be revalidated immediately before implementation. Unexpected files are a stop condition.

### New production files

- `StyleMatchAI/ContextEngine/AIConsumerContextEnvelope.swift`
- `StyleMatchAI/ContextEngine/OutfitContextConsumerProvider.swift`
- `StyleMatchAI/StylistChat/ScanBoundConversationPolicy.swift`

### Modified production files

- `StyleMatchAI/ContextEngine/ContextInferenceInput.swift`
  - add only a shared, deterministic factory if required to avoid duplicate input construction;
- `StyleMatchAI/StylistChat/StylistChatModels.swift`
  - additive request payload, binding types, and context validation;
- `StyleMatchAI/StylistChat/StylistChatService.swift`
  - per-send resolution, complete-turn filtering, and in-flight binding validation;
- `StyleMatchAI/StylistChat/StylistChatView.swift`
  - dependency/selection wiring only; no visible UI change;
- `StyleMatchAI/PersonalStylist/StylistContextBuilder.swift`
  - remove scan-fact authority from string builders while retaining non-scan personalization;
- `StyleMatchAI/AIStyleAdvisor.swift`
  - stop selecting or reconstructing scan facts;
- `StyleMatchAI/OpenAIStylistClient.swift`
  - accept a resolved request context instead of rebuilding one from profile strings;
- `StyleMatchAI/ScanView.swift`
  - supply active/historical selection intent and authoritative identity only;
- `StyleMatchAI/ContentView.swift`
  - inject the shared provider and preserve explicit handoff lifetime;
- `StyleMatchAI.xcodeproj/project.pbxproj`
  - include new source and test files;
- `Package.swift`
  - include new source and test files.

### New tests

- `StyleMatchProPhase2Tests/ContextEngineCE2BTests.swift`

### Modified tests

- `StyleMatchProPhase2Tests/StylistChatServiceTests.swift`
- `StyleMatchProPhase2Tests/ScanUpgradePromptBuilderTests.swift`
- `StyleMatchProPhase2Tests/StyleMatchProPhase2Tests.swift`
  - source-boundary assertions only if existing project policy keeps these checks here.

### Explicitly unchanged

- scan persistence models and keys;
- `ChatConversationStore` persistence format;
- score calculation;
- garment classifier and CE2A inference rules;
- Scan Results UI;
- voice and screen-awareness contracts;
- Shopping, catalog, retailer, Worker deployment, configuration, signing, and release files.

If implementation proves `ChatConversationStore`, a persistence model, Worker source, UI presentation, voice, Shopping, or scoring must change, stop and request a new checkpoint.

## 21. Test matrix

Assertions inspect the typed request envelope, binding, retained complete turns, and transport request. Generated prose alone is insufficient.

| ID | Scenario | Required assertion |
|---|---|---|
| CE2B-01 | Previous scan 74, newest scan 80 | Latest provider binds scan 80 and authoritative score 80 |
| CE2B-02 | AI Assist after scan 80 | Request snapshot and legacy projection both use the same scan 80 |
| CE2B-03 | Standalone chat after scan 80 | Fresh per-send resolution uses scan 80 |
| CE2B-04 | Explicit historical scan 74 | Saved selection remains bound to scan 74 despite newer scan 80 |
| CE2B-05 | Leave historical and return to latest | Next global send refreshes and binds scan 80 |
| CE2B-06 | New scan completes while chat remains open | Next send switches to new scan without restart |
| CE2B-07 | New scan completes during request | Old response is rejected before acceptance/display |
| CE2B-08 | App relaunch with restored conversation | Visible history restores; fresh snapshot supplies authority |
| CE2B-09 | Legacy assistant says `74/100` | Turn is excluded by missing/mismatched binding, not text parsing |
| CE2B-10 | Legacy assistant says `74 points` | Same structured exclusion; no phrase-specific rule |
| CE2B-11 | Stale style text | Old turn cannot populate `detectedStyle` |
| CE2B-12 | Stale occasion text | Old turn cannot populate selected occasion |
| CE2B-13 | Stale weather text | Old turn cannot populate weather |
| CE2B-14 | Stale purpose/workplace text | Old turn cannot populate purpose/profile |
| CE2B-15 | Complete-turn removal | Both members of an old turn are excluded |
| CE2B-16 | Dangling user after removal | Payload contains no dangling historical user turn |
| CE2B-17 | Current unsent assistant | Current user question remains; empty assistant is excluded |
| CE2B-18 | Equal latest timestamps | Latest mode fails closed as ambiguous |
| CE2B-19 | Equal timestamps with explicit saved ID | Explicit matching historical selection succeeds |
| CE2B-20 | Deleted saved scan | Historical send is blocked; latest is not substituted |
| CE2B-21 | Quarantined/invalid saved scan | Historical send fails closed |
| CE2B-22 | Failed scan with no completed analysis | No scan-specific request is sent |
| CE2B-23 | Missing snapshot | Scan-specific send is blocked; general no-scan mode remains available |
| CE2B-24 | Snapshot scan-ID mismatch | Provider returns identity-mismatch failure |
| CE2B-25 | Snapshot score mismatch | Provider rejects context; score is never reconciled |
| CE2B-26 | Schema-version mismatch | Request is blocked |
| CE2B-27 | Algorithm-version mismatch | Request is blocked |
| CE2B-28 | Generation mismatch | Stale turn/response is rejected |
| CE2B-29 | Malformed backend response | No context mutation; incomplete turn is not grounded |
| CE2B-30 | Offline | Existing network error behavior; binding stays immutable |
| CE2B-31 | Timeout | Same as offline; no incomplete assistant grounding |
| CE2B-32 | Rapid repeated sends | One active send; no envelope reuse across changed authority |
| CE2B-33 | Starter-prompt send | Same provider and assembler as typed send |
| CE2B-34 | Voice-transcribed send | Same provider and assembler; no voice-output change |
| CE2B-35 | Request-size boundary | Typed extension is at or below 16 KB and request remains valid |
| CE2B-36 | Evidence ordering | Identical input produces byte-stable typed payload |
| CE2B-37 | No raw OCR retention | Encoded request and diagnostics omit raw text/name/employer |
| CE2B-38 | Missing evidence | Missing values remain explicit; no invented field |
| CE2B-39 | Conflicting evidence | Low/uncertain typed result is preserved |
| CE2B-40 | AI Assist/chat consistency | Envelopes are identical for the same scan and selection |
| CE2B-41 | Saved-scan consistency | Saved handoff and request bind the same scan/generation |
| CE2B-42 | Legacy projection consistency | Legacy strings are derived from the typed envelope only |
| CE2B-43 | Current Worker compatibility | Existing request contract remains accepted |
| CE2B-44 | Unsupported typed capability | Local fail-closed/fallback path executes without stale claims |
| CE2B-45 | Old client/new Worker | Old request fixture remains accepted |
| CE2B-46 | No persistence write | Scan and chat persistence bytes are unchanged by context resolution |
| CE2B-47 | No score mutation | Score/breakdown before and after every request are identical |
| CE2B-48 | No Shopping drift | Protected Shopping/catalog hashes remain unchanged |
| CE2B-49 | Request diagnostics privacy | Logs contain only approved guard/timing/count metadata |
| CE2B-50 | Deterministic repeated resolution | Same selection and inputs produce identical envelope/payload |

## 22. Planned implementation verification

The implementation checkpoint must run:

1. focused CE2B tests;
2. accepted CE1 tests;
3. accepted CE2A tests;
4. existing Stylist Chat and scan-context tests;
5. stale-turn and complete-turn tests;
6. frozen chat request fixtures;
7. Worker compatibility tests in the authorized Worker checkout;
8. full Swift suite;
9. Debug simulator build;
10. Release simulator compile;
11. static analysis;
12. `git diff --check`;
13. protected Shopping/catalog hash comparison;
14. source scan proving no persistence, voice, UI presentation, scoring, or Shopping adoption.

Because CE2B changes AI request behavior, automated evidence is not sufficient for formal acceptance. ADR-006 requires supported-version health verification and later physical validation of AI Assist, standalone latest scan, historical saved scan, stale-context transition, offline behavior, and retained-data integrity.

## 23. Acceptance criteria

| Criterion | Required evidence |
|---|---|
| One scan selector | All three consumers resolve through `CurrentScanContextProvider` |
| One snapshot provider | No production consumer invokes CE2A or reconstructs context independently |
| AI Assist exactness | Typed request matches displayed scan ID, score, and snapshot |
| Standalone freshness | Provider resolves immediately before every send |
| Historical precedence | Explicit saved scan remains authoritative |
| Return to latest | Global chat refreshes latest authority |
| Complete-turn safety | Old/mismatched turns are excluded in complete pairs |
| No text authority | No score/style/purpose/weather phrase parsing determines context |
| In-flight safety | Changed binding prevents stale response acceptance |
| Fail closed | Missing/mismatched/version-invalid context never becomes scan-specific advice |
| Additive compatibility | Current and old clients remain supported; typed capability is proven |
| Privacy | No prohibited evidence appears in request, logs, or persistence |
| Performance | Provider and payload targets pass |
| No persistence change | Existing scan and chat persisted bytes remain unchanged |
| No score drift | Exact score/breakdown preserved |
| No UI/voice/Shopping drift | Protected sources/hashes and behavior remain unchanged |
| Physical requirement | Remains BLOCKED until separately authorized physical acceptance |

CE2B cannot be accepted from response prose alone. The typed request, provider selection, binding, history filtering, compatibility result, and response validation must be directly evidenced.

## 24. Stop rules

Stop implementation immediately if:

- the baseline branch, HEAD, clean state, or committed plan differs;
- a source requires score recalculation;
- a second scan selector or snapshot builder is proposed;
- AI context must be inferred from conversation text;
- a persistence schema/write is required;
- raw OCR, private identity, precise location, or Shopping data would enter the context;
- Worker compatibility cannot be proven additively;
- a current accepted client contract breaks;
- a historical scan silently falls through to latest;
- a schema, generation, scan ID, or score mismatch is accepted;
- a stale response can be displayed after authority changes;
- new UI, voice, screen-awareness, scoring, Shopping, catalog, signing, or deployment work is required;
- an unexpected file falls outside the forecast.

Produce a gap report rather than expanding scope.

## 25. Narrow implementation authorization

A future CE2B implementation authorization may permit only:

- the files forecast in section 20;
- the shared transient provider, immutable envelope, canonical payload builder, and complete-turn policy;
- AI Assist, standalone chat, and saved-scan request adoption;
- additive compatibility projection and capability handling;
- tests and verification in sections 21 and 22;
- one isolated local implementation commit after all gates pass.

It must separately specify the Worker checkout and contract-test authority before any Worker edit, deployment, or health check.

It must not permit:

- persistence changes;
- UI presentation changes;
- voice-output changes;
- screen-context contract changes;
- scoring changes;
- Shopping/catalog changes;
- device installation;
- acceptance ledger updates;
- push, deployment, TestFlight, or App Store work.

CE2B implementation remains unopened until that separate authorization is issued.
