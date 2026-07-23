# StyleMatch Pro Project State and Architecture Decision Ledger

**Status:** Governing project record
**Established:** 2026-07-19
**Repository:** `STYLEMATCH_1_7_AI_STYLIST_PERSONALITY`
**Branch at establishment:** `feature/1.7-ai-stylist-conversation-refinement`
**HEAD at establishment:** `6c41ff4fd847d356745b4e5e8be60355289e9bfc`

This is the single source of truth for approved StyleMatch Pro architecture, policy, checkpoint status, and roadmap. Conversation history, handoff prose, screenshots, and test output are supporting evidence, not substitutes for this ledger.

## Maintenance and acceptance protocol

1. This file is append-only. Never rewrite or delete a dated decision. Supersede an earlier decision with a new dated record that links to it and explains why.
2. Before any task, compare its requested scope with the active decisions below. Report conflicts before changing source.
3. Every checkpoint must name the decision IDs it implements.
4. An accepted checkpoint must append its result and evidence here before it is complete.
5. A proposal, automated pass, physical screenshot, deployment, and accepted checkpoint are distinct states. Do not promote one state to another without its required evidence.
6. If context is lost, read this file, then verify repository HEAD, branch, index, dirty-tree boundaries, deployed environment, and installed artifact before continuing.
7. Existing dirty changes are protected project context. Never stash, reset, restore, clean, broadly stage, or overwrite them without explicit owner authorization.

## Current system architecture

### Runtime boundaries

- **iOS application:** owns presentation, local conversation state, verified closet state, authoritative scan results, shopping preferences, typed context construction, client validation, and evidence-labeled local fallbacks.
- **Stylist conversation service:** one shared conversation architecture receives typed routing intent plus grounded context. Welcome actions and feature entry points may change intent and context, but must not create separate AI pipelines, duplicated prompt logic, or independent conversation stores.
- **Worker:** owns the remote chat proxy, response validation/fallback, backward-compatible API contract, affiliate/catalog endpoints, health classification, and privacy-safe operational diagnostics.
- **Scan engine:** is the sole authority for current outfit evidence, component breakdowns, and StyleMatch scores. AI may explain a completed score but may not generate, recompute, override, reinterpret, or contradict it.
- **Closet:** is the sole authority for verified garment ownership. A recommendation may call an item owned only when Closet evidence identifies it.
- **Shopping:** owns catalog products, retailer registry/filtering, validated outbound destinations, and optional purchase suggestions. Suggested products must never be represented as owned garments.
- **Retailer registry and catalog:** approved retailers come from the registry; products come from the catalog and carry canonical retailer IDs. Direct-access retailers do not imply catalog integration or an affiliate relationship.

### Supported data flow

```text
Verified Closet ─┐
Authoritative Scan ├─> Typed grounded context ─> Shared Stylist conversation
Weather (supplied) ┤                                  │
Explicit occasion ┘                                  ├─> Explain/refine
                                                       └─> Typed handoff
                                                            ├─> Scan
                                                            ├─> Closet
                                                            └─> Shopping
```

Unknown or unavailable evidence is omitted or labeled uncertain. It is never inferred merely to complete a response or layout.

## Active governing decisions

### ADR-001 — Score and evidence authority

**Date:** 2026-07-19
**Status:** Active, permanent unless explicitly superseded

- Scan owns score and current-outfit evidence.
- Closet owns verified garment ownership.
- Stylist interprets supplied evidence but may not invent facts.
- Shopping owns optional product suggestions, separated visibly and semantically from owned items.
- Evidence grounding, saved-scan authority, dynamic score preservation, empty-scan safeguards, plain-text validation, and the score-integrity rule remain protected invariants.
- A component score does not prove a weakness in a particular garment without evidence mapping the component to that garment.
- Observed garment evidence is not itself a recommendation and must not be converted into a weather conflict.

### ADR-002 — Unified Stylist Journey

**Date:** 2026-07-19
**Status:** Approved architecture; end-to-end implementation pending

The canonical journey is:

```text
Dress Me Today → Scan Outfit → Explain My Score → Find Matching Pieces
```

The four welcome actions are typed routing intents into one shared conversation system. They must not create separate model pipelines, prompt stacks, transports, or state stores.

Implementation order:

1. Finish MW1 physical acceptance; stop on failure.
2. Implement DMT1 deterministic verified-outfit engine and integrity gate.
3. Add the four-intent Stylist welcome surface.
4. Rename the scan action to **Explain My Score** without weakening the authoritative scan route.
5. Add typed, evidence-preserving handoffs among Stylist, Scan, Closet, and Shopping.
6. Physically validate the complete morning-to-shopping journey on one pinned build.

The evidence-labeled typed fallback is the product standard. Do not restore the legacy “temporarily unavailable online” wording.

### ADR-003 — Typed context and handoff contracts

**Date:** 2026-07-19
**Status:** Current screen/scan context implemented; cross-domain envelope requirements approved; exact new schema requires design approval before implementation

Implemented conversation context uses typed `ChatContext` and `StylistScreenContext` data, including current tab, entry point, active scan state/identifier, visible score, selected occasion/analysis section, visible aggregates, and closet state where supplied.

Every future cross-domain handoff must preserve, at minimum:

- typed routing intent;
- source domain and destination domain;
- stable source identifier when available;
- authority owner for each fact;
- evidence value and evidence source;
- provenance/ownership classification;
- evidence quality or uncertainty state;
- optional-vs-owned classification for shopping content;
- the current authoritative score without mutation when a scan is active.

Contract rules:

- Missing evidence remains absent or explicitly unavailable.
- A destination may narrow or validate evidence but may not silently upgrade its authority.
- The same typed context builder path applies to typed, voice-transcribed, and starter-prompt sends.
- Voice is transcription-only into an editable draft; explicit send is always required.
- New payload fields must be additive for supported clients unless the owner explicitly approves deprecation.

Before implementing a new handoff schema, the checkpoint must publish the concrete types, routing map, authority matrix, compatibility assessment, migrations, rollback path, tests, and physical acceptance criteria for approval.

### ADR-004 — DMT1 Daily Styling Engine contract

**Date:** 2026-07-19
**Status:** Product contract approved; deterministic engine not yet implemented

Mission: recommend the best verified outfit the available evidence can honestly support—not the most fashionable theoretical outfit.

Evidence priority:

1. Confirmed closet items.
2. Current weather, only when available.
3. Explicit occasion.
4. Saved style preferences.
5. Recent outfit history.
6. Optional shopping suggestions, always outside the owned outfit.

Output requirements:

- Return only complete, distinct outfits.
- Return fewer outfits instead of inventing weaker alternatives.
- Permitted shapes are Best Match alone, Best Match plus Cooler Option, or those plus Slightly Dressier when verified inventory supports them.
- Every garment must include traceable provenance such as a closet item identifier or verified scan identifier.
- Evidence quality is labeled (for example, Strong Match or Limited Context); unsupported percentages are not a substitute for evidence.
- Missing weather, occasion, or history must be labeled rather than guessed.
- Follow-ups such as cooler, more professional, or after work reuse the same engine with changed constraints.
- Shopping remains an optional improvement and cannot be confused with ownership.

Fail-closed recommendation integrity gate:

- every garment exists in verified evidence;
- every outfit is complete;
- no duplicate outfit is returned;
- every explanation references supplied evidence;
- every shopping suggestion is explicitly not owned;
- a failed check removes the affected outfit rather than weakening the contract.

### ADR-005 — Shopping information architecture

**Date:** 2026-07-19
**Status:** Products/Stores separation is implemented only in the current dirty worktree and reported automated-green; it is not yet durable in a commit, and final physical acceptance evidence remains incomplete

- Shopping separates **Products** and **Stores** as first-class destinations.
- Products owns products, recommendations, catalog browsing, Browse/Swipe, Complete the Look, deals, and product filters. It must not render retailer-directory rows.
- Stores owns retailer search, My Stores/All Stores scope, coverage labels, product counts, Manage My Stores, View Products, and validated Open actions. It must not render recommendation cards.
- Store directory ordering is product-count descending, then alphabetical.
- Coverage vocabulary is sourced from `StoreCoverageState` by canonical retailer ID.
- Store browsing is informational and does not mutate preferred retailer IDs.
- The soft-fallback shopping contract remains unchanged.
- The bottom navigation remains unchanged.

Physical evidence has demonstrated primary Products/Stores separation and directory visibility. Remaining IA1.1 evidence includes Browse/Swipe state preservation and complete pinned-build action captures for Nike, Macy's, and Best Buy.

### ADR-006 — Stylist AI Continuity Policy and Compliance Gate

**Date:** 2026-07-19
**Status:** Ratified, active until explicitly replaced

Stylist continuity is release-critical shared infrastructure, not best effort. It covers environment binding, authentication, token/session recovery, persistence, Worker compatibility, dependency health, configuration, evidence-preserving handoffs, diagnostics, recovery, and rollback.

Permanent RG1 rules:

- Debug may use staging; every Release/TestFlight/App Store artifact must prove an authorized production chat host.
- Frozen supported-version request/response contracts run on every Worker change. Breaking a live version is prohibited without explicit owner deprecation.
- Chat regression suites may not be waived, skipped, or deferred.
- Every chat-affecting task declares its impact during preflight.
- Health and dependency failures must be classified, monitored, privacy-safe, and actionable rather than silent.
- Every infrastructure dependency requires named ownership, lifecycle responsibility, health check, compatibility policy, recovery strategy, and rollback plan.
- Every checkpoint report carries a **chat-health** line covering environment binding, supported-version contracts, regression suites, and live health when available.

Mandatory compliance record for any checkpoint that modifies or could influence Stylist AI:

- dependency ownership documented;
- lifecycle responsibilities identified;
- health checks and monitoring active;
- supported-client and Worker compatibility verified;
- recovery procedures validated;
- rollback tested or non-applicability explicitly justified;
- automated regression and integration suites passing;
- physical-device acceptance passing for affected workflows;
- no new unmitigated single point of failure.

If any evidence is missing, status is **Not Accepted**. Evidence may not be silently deferred or treated as documentation-only. An exception requires explicit, time-bounded owner authorization documenting missing evidence, risk, mitigation, and expiration.

### ADR-007 — Append-only project memory and conflict gate

**Date:** 2026-07-19
**Status:** Active

This ledger is the permanent project memory. Every future task begins with an architecture comparison. Conflicts stop implementation until the owner resolves them. Every accepted checkpoint appends its governing decision IDs, exact repository/artifact identities, automated results, physical evidence, environment/deployment state, exceptions, and remaining work.

## Checkpoint ledger

| Checkpoint | Current state | Governing decisions | Evidence or remaining gate |
|---|---|---|---|
| Screen-context routing, navigation-aware AI, saved-scan authority, score preservation and validation | Completed and previously verified | ADR-001, ADR-003 | Protected invariants; rerun affected regressions on future changes |
| Worker response honesty hardening | Completed and staging-replayed in earlier work | ADR-001, ADR-006 | Weather/category validator regressions remain mandatory |
| Shopping D3 → SD1-V → SD2 → SD3 / IA1 | Current dirty-tree implementation reported automated-green; not yet durable in a commit; primary device layout observed; IA1.1 pending complete physical record | ADR-005 | Preserve Products/Stores isolation and remaining Route D/E evidence |
| SL1 in-app browser | Reported as implemented/device-used in project handoffs; formal acceptance record not yet appended | ADR-005, ADR-006 | Reconcile exact automated and pinned-device evidence before treating as accepted baseline |
| MW1 morning flow | Current dirty-tree implementation reported automated-green at 679/679; not yet durable in a commit; physical acceptance pending | ADR-002, ADR-003, ADR-006 | Speak question, review draft, explicit send, verify combinations/colors/weather/work fit, single-send chips, non-trapping keyboard |
| DMT1 | Contract approved; not implemented | ADR-002, ADR-004, ADR-006 | Design approval, deterministic engine, integrity gate, tests, physical 15-second flow |
| RG1 reliability machinery | Prepared only in dirty/untracked iOS and Worker worktrees; reported automated-green at iOS 681/681 and Worker 132/132 with TypeScript passing; not yet durable, deployed, or accepted | ADR-006 | Authentic 1.5/1.6 captures, isolated commits, Release artifact inspection, separately authorized live health/alert deployment and run, strict per-hunk evidence |
| CS1 catalog seeding | Candidate work reported; owner sign-off and authorized staging import pending | ADR-001, ADR-005 | Reconcile candidate review sheet, legitimate image sources, URL validation, no production write |
| Unified Stylist welcome and cross-domain journey | Approved architecture; not implemented | ADR-002, ADR-003, ADR-004 | Must follow MW1 physical acceptance and DMT1 engine |

## Regression and acceptance requirements

### Always protected

- `calculateStyleScore` and score-integrity behavior.
- Saved-scan authority, dynamic score preservation, and empty-scan safeguards.
- Plain conversational response validation and evidence grounding.
- No unsupported garment/category deductions or invented weather.
- Chat privacy exclusions and typed fallback ownership labels.
- Canonical retailer IDs, supported-store registry, catalog safety validation, and validated openers.
- Remote → cache → bundled catalog ordering and soft-fallback semantics.

### Automated gates

- Focused tests for the affected lane.
- Full iOS suite.
- Full Worker suite and TypeScript when Worker or shared chat behavior can be affected.
- Frozen supported-version chat contracts.
- Release environment-binding inspection for distribution artifacts.
- `git diff --check` and empty index at start/end.
- Baseline preimage evidence proving protected dirty hunks remain byte-identical.
- The cross-repository release gate must fail closed if any required input is absent or red.

### Physical gates

- Use the exact pinned artifact without rebuilding during a replay.
- Capture the UI and privacy-safe console/Worker evidence from the same attempt.
- Distinguish automated, diagnostic, and formal acceptance runs.
- Stop at the specified route boundary.
- A missing capture is pending evidence, not a pass or failure.
- Chat-affecting work requires affected-flow device acceptance before acceptance.

## Version compatibility assumptions

- Supported target versions currently named by policy: 1.5, 1.6, 1.7, and future supported releases.
- Current 1.7 Debug configuration may bind to staging; current-tree Release configuration is intended to bind to `https://api.stylematchpro.com` and must be verified in the built artifact.
- The bindings of shipped 1.5 and TestFlight 1.6 artifacts are unknown until their archived artifacts are inspected.
- Existing 1.5/1.6 Worker fixtures are prepared compatibility fixtures and conservative reconstructions in an untracked dirty worktree, not durable or authentic byte-for-byte captures, until Organizer archives or captured requests replace/confirm them.
- Worker contract evolution is additive for supported clients. Removal, rename, or retyping requires explicit deprecation approval and a rollback plan.

## Active roadmap and open work

Priority order at establishment:

1. Inspect Xcode Organizer for authentic 1.5/1.6 archives and bindings.
2. Authorize an inspection-only Release artifact plus staging `/health/chat` and alert-delivery gate run.
3. Complete MW1 physical morning acceptance; stop if it fails.
4. Produce and approve the DMT1 typed design, then implement its deterministic verified-outfit engine.
5. Implement the unified four-intent Stylist welcome and typed cross-domain handoffs.
6. Complete IA1.1 remaining physical navigation/action evidence.
7. Review CS1 candidate catalog and authorize staging only if the review passes.
8. Build the partitioned commit train while preserving established ordering and checkpoint boundaries.

## Technical debt and deferred items

- Authentic 1.5/1.6 chat fixtures and shipped-artifact binding evidence are missing.
- RG1 requires `/health/chat`, but its implementation exists only in the dirty Worker worktree. The route is absent from committed canonical Worker HEAD and production, and requires an isolated commit plus separately authorized deployment. Alerting and the signed Release gate have not been activated or physically proven.
- Earlier RG1 work recorded whole-tree baselines but did not retain strict per-hunk preimages for every already-dirty owned file; per-hunk preimage evidence is mandatory going forward.
- The upstream saved-scan garment/title assertion issue (for example, an olive jogger identified as a jacket) remains in the assertion-audit lane; do not mutate historical scan evidence as part of chat validation.
- Shopping catalog depth, legitimate product imagery, and Amazon PA-API eligibility remain incomplete.
- CS1 production import is not authorized.
- IA2+ presentation work (Shopping home, compact product cards, recommendation accordions, slot-based Complete the Look, filter sheet, Saved destination) remains separate from IA1.
- Commit train, Macy's/Best Buy source attestations, cache freshness, and catalog trust-marker work remain queued.
- A formal SL1 acceptance record needs reconciliation before the in-app browser checkpoint is marked accepted in this ledger.

## Required preflight template for every new task

```text
Project-state comparison: read docs/PROJECT_STATE.md
Requested checkpoint:
Governing ADRs:
Architecture conflicts: none | list and stop
Chat impact: none | binding | auth | persistence | transport | context | Worker | handoff
Authority impact: Scan | Closet | Stylist | Shopping | none
Repositories and pinned HEADs:
Index state:
Protected dirty-hunk baseline hashes:
Allowed files/hunks:
Required focused/full/contract tests:
Required physical acceptance:
Rollback plan:
Chat-health line: binding / contracts / suites / live health
```

## Required acceptance append format

Append—not replace—a dated record containing:

```text
Decision ID and checkpoint:
Date:
Status: Accepted | Not Accepted | Pending Evidence | Superseded
Repository HEAD(s):
Files/hunks owned:
Automated evidence:
Physical evidence:
Environment, deployment and artifact identity:
Authority and compatibility assessment:
Continuity compliance record:
Rollback evidence:
Exceptions and expiration:
Open follow-up:
```

## Decision history

### 2026-07-19 — Ledger established

ADR-001 through ADR-007 were consolidated from owner-approved project directives and the verified repository state available on this date. Where an implementation or physical result could not be proven from repository evidence, its status was recorded as pending rather than accepted. Future decisions must be appended below this entry.

### 2026-07-22 — IA1.1 Route A (Nike) accepted

Decision ID and checkpoint: IA1.1-RA — Route A Nike physical acceptance

Date: 2026-07-22

Status: Accepted

Governing decisions: ADR-001, ADR-005, ADR-006, ADR-007

Repository HEAD(s): `STYLEMATCH_BETA_2_0_SHOPPING_COMPOSITION` at `5463866e7783d8d4e75318423c8d85a23c252d8c` on `release/beta-2.0-shopping-composition`

Files/hunks owned: This acceptance record only. No application source, tests, catalog, build settings, retained data, or deployment state changed during Route A.

Automated evidence: The foreground Logging trace finalized normally and was preserved unchanged. CLI TOC export passed (3,579 bytes; SHA-256 `327051971315b56cb6fc3fb5d0d248ea2e0851a8322d97fff075b63384d6d1b1`). Explicit os-log export passed (1,713,077 bytes; 3,773 rows; SHA-256 `862bd33f13005a70b89a8bc26fe1c762bae0a6b4a44d94ed1682fd483f3bbe32`). Sanitized os-log evidence SHA-256: `f513d00d1a5294ddcaa84962f672e93d5158f2187894fe5f7c66b4ead2cf2cd6`. The complete Route A report SHA-256 is `eaa70c9fc51288d3eae61b12c4be9c0486a9a44b95f5b6c657ad8eef6e12b4ad`.

Physical evidence: On the installed pinned StyleMatch Pro 1.7 (1) candidate, Nike-only selection passed; the truthful empty-inventory fallback passed; the selected-store disclosure identified Nike; visible fallback recommendations identified their actual retailer (Amazon) rather than being represented as Nike inventory; the approved Nike direct-store path passed; and the in-app browser reached `nike.com`. Owner screenshots were visually validated during the bounded attempt, but the declared Downloads paths did not materialize as local files for hashing. No screenshot hashes were invented.

Environment, deployment and artifact identity: Bundle `com.sabastine.stylematchai`; version/build 1.7 (1); executable SHA-256 `f58e67fb3da80a716f85e8c27d0db7059a85b5cc371605538aab4e124bd42a02`; pinned ZIP SHA-256 `88f980042606fed10057528302a33fddb7b8de07164438ff748c4ee04e5afff3`. Foreground xctrace recorded PID 7731 from 2026-07-22 17:52:09.987 EDT through 17:59:55.265 EDT and ended by one direct Ctrl-C after destination evidence. No crash, security rejection, automatic retry, unauthorized termination, build, installation, signing change, catalog change, source change, or deployment occurred.

Authority and compatibility assessment: Shopping retailer attribution and soft-fallback truthfulness were preserved. Immutable B5 remained an exact match after the route: active 3 records at `2851dbd25dcc9fbc628517f831c61d37a4bac352e8b83ca6f8be7febc51a9200`; staging 6 records at `d8005542e432a022d7be91a16897e436b60fbddb18c19c02ee301ec9362c7053`; quarantine 0. Sanitized B5 comparison SHA-256: `6a7eb0f27cba5f70569623dc031f5ea27e65a03424c704760c3fdef7c0d4c5ef`.

Continuity compliance record: Chat impact was none. No Stylist binding, authentication, persistence, transport, context, Worker contract, or handoff changed. Existing supported-version contracts, regression suites, and live-health state were therefore not modified by this physical Shopping acceptance checkpoint.

Rollback evidence: Not applicable to the accepted physical result. This append-only entry may be superseded only by a separately authorized later record; it must not be rewritten.

Exceptions and expiration: None. The absence of hashable screenshot files is explicitly recorded and is not represented as hashed evidence; the accepted same-attempt trace, CLI exports, owner-observed UI, and exact B5 comparison remain authoritative.

Open follow-up: Route B (Macy's plus the D7 in-app-browser dismissal/state-preservation evidence) is planned in `docs/IA1.1-ROUTE-B-PLAN.md` but is not authorized for execution. Route C, D7/SL1 acceptance, CS1, SR1, TestFlight, deployment, and other downstream work remain unopened.

### 2026-07-22 — IA1.1 Route B (Macy's and D7 browser fallback) accepted

Decision ID and checkpoint: IA1.1-RB — Route B Macy's physical acceptance and D7 browser-dismissal evidence

Date: 2026-07-22

Status: Accepted

Governing decisions: ADR-001, ADR-005, ADR-006, ADR-007

Repository HEAD(s): `STYLEMATCH_BETA_2_0_SHOPPING_COMPOSITION` at `9558c53d45334523c135940b7494a9e778fd6e51` on `release/beta-2.0-shopping-composition`; installed pinned application source remained `5463866e7783d8d4e75318423c8d85a23c252d8c`.

Files/hunks owned: This acceptance record and the separately prepared Route C procedure only. No application source, tests, catalog, build settings, retained data, or deployment state changed during Route B.

Automated evidence: The foreground Logging trace for StyleMatch Pro PID 7874 finalized normally after one direct Ctrl-C, was saved, and was preserved unchanged. Stable trace archive identity: 2,500,608 bytes, SHA-256 `455c6c1ec3e4779c98ebf7ace40e8743ced0f1505888ebbf250580ec5234948d`. Explicit os-log export passed with 2,308 rows (1,534,075 bytes; SHA-256 `5656b1f5effbab5f95a80dbcdf02c205cd85178be0323aef33e85b24ea9509d8`). Sanitized os-log evidence SHA-256: `2c8aeed8bb339f01a75a5e1d6bc5bec5f1fa8063a61fedac46c3f89248f1a6a4`. The CLI TOC serializer produced a retained zero-byte artifact (SHA-256 `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`); Instruments GUI fallback opened the same trace and rendered the `00:08:04` run, StyleMatch Pro PID 7874, and 2,308 Messages rows, confirming usable runtime data. The complete Route B report SHA-256 is `4075f10f457fa88bd9a4ae1898ad1d08502ab3effe60fff4482ed24069d40898`.

Physical evidence: Macy's-only selection passed. The thin-inventory fallback truthfully stated that selected-store inventory was unavailable and identified Macy's as the selected store. Visible fallback recommendations remained correctly attributed to Amazon rather than being represented as Macy's inventory. The approved Macy's direct-store path opened the in-app browser at public `macys.com`. Normal dismissal returned to Shopping > Stores > My Stores with Macy's, `No products available yet`, the same `Open` action, and the same navigation and fallback context preserved. Retained screenshots: fallback SHA-256 `14184bde9c63c4c373c8edcea98848164c0a7e7363168b60d3125e0fff645e6c`; Macy's destination SHA-256 `de4a03f995ebc23995d7dae1dd7644b947158ce19319124c574d621d88d1ee6f`; post-dismissal state SHA-256 `887dc3f08c34d69a40ce563a91c4d072941e73ad09bdb49ea88a87199ba7b0b5`.

Environment, deployment and artifact identity: Bundle `com.sabastine.stylematchai`; version/build 1.7 (1); installed pinned candidate unchanged. One separately authorized supported `devicectl` termination targeted only the pre-existing StyleMatchAI PID 7813 to establish the required process boundary; it succeeded once, and the confirmation inventory showed zero StyleMatchAI processes. No retry, unauthorized termination, crash, security rejection, source change, catalog change, build, installation, reinstall, replacement, signing change, or deployment occurred.

Authority and compatibility assessment: Immutable B5 remained an exact match after Route B: active 3 records at `2851dbd25dcc9fbc628517f831c61d37a4bac352e8b83ca6f8be7febc51a9200`; staging 6 records at `d8005542e432a022d7be91a16897e436b60fbddb18c19c02ee301ec9362c7053`; quarantine 0. Sanitized B5 comparison SHA-256: `64c879b0449e20a7c53949a11acb379399ff138374238e5e819892d0b17d581f`.

Continuity compliance record: Chat impact was none. No Stylist binding, authentication, persistence, transport, context, Worker contract, or handoff changed. Existing supported-version contracts, regression suites, live-health state, retailer authorities, and the accepted B5 authority were not modified by this physical Shopping acceptance checkpoint.

Rollback evidence: Not applicable to the accepted physical result. This append-only entry may be superseded only by a separately authorized later record; it must not be rewritten.

Exceptions and expiration: The owner-declared 18:24:30 Stores screenshot did not materialize at its declared local path, so no hash was invented. The retained 18:23 fallback, 18:25 destination, and 18:26 post-dismissal screenshots independently establish the bounded state transition. The zero-byte CLI TOC remains explicitly classified as a serializer artifact; acceptance relies on the structurally complete retained trace, explicit nonempty os-log export, privacy-reviewed derivative, and accepted Instruments GUI fallback.

Open follow-up: Route C (Best Buy native-app continuation) is prepared in `docs/IA1.1-ROUTE-C-PLAN.md` but is not authorized for execution. Route B supplies the Macy's-specific D7 browser-open and state-preserving dismissal evidence; D7/SL1 is not separately accepted by this record. Route C, D7/SL1 final acceptance, CS1, SR1, TestFlight, deployment, and other downstream work remain unopened.

### 2026-07-22 — IA1.1 Route C (Best Buy native-app continuation) accepted

Decision ID and checkpoint: IA1.1-RC — Route C Best Buy physical acceptance and native-app continuation evidence

Date: 2026-07-22

Status: Accepted

Governing decisions: ADR-001, ADR-005, ADR-006, ADR-007

Repository HEAD(s): `STYLEMATCH_BETA_2_0_SHOPPING_COMPOSITION` at `f8076a737f53f2823625b9131250f724def0415e` on `release/beta-2.0-shopping-composition`; installed pinned application source remained `5463866e7783d8d4e75318423c8d85a23c252d8c`.

Files/hunks owned: This acceptance record only. No application source, tests, catalog, build settings, retained data, or deployment state changed during Route C.

Automated evidence: The foreground Logging trace for StyleMatch Pro PID 8248 finalized normally after one direct Ctrl-C, ran for 260.254624 seconds (00:04:20), ended with `exit(0)`, and was preserved. Frozen pre-GUI trace identity: 2,296,832 bytes, SHA-256 `9c64f749f6e9c9198581ed50fc840a07b21b6bea9052f828840e3d927f1589eb`. The CLI TOC export passed (3,565 bytes; SHA-256 `86d89ad66d8d59c4695657fbd33d71543b293ef7e96f6cdd9e82ff845087fd52`) and exposed the run plus `os-log` schema. The explicit CLI os-log serializer produced a retained zero-byte artifact (SHA-256 `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`). Instruments GUI fallback opened the same trace and rendered 1,114 unified-log Messages rows for StyleMatch Pro PID 8248; screenshot SHA-256 `32e5e507eb249bbbacb9f9cbd880074eaad6433424c650caa61ee8c318988c88`. Sanitized runtime evidence SHA-256: `ccabfff83750db3ccc9616e5b44a902102943b1a030cb8557f443565301c6bb9`. The Route C final report SHA-256 is `e5988afc3530625868a7ec40612222110b17b21375446fe8eaa4402007b3c214`; evidence manifest SHA-256 is `440a939d97b66034879127d44e0db4c5a0e2fcf6646385882e4815fcbd44b298`.

Physical evidence: Best Buy was selected exclusively. The truthful zero-catalog state displayed `No products available yet`, and the direct-store disclosure stated that StyleMatch Pro did not claim a catalog integration or affiliate relationship. The owner tapped the Best Buy `Open` action exactly once from StyleMatch Pro; the installed native Best Buy app opened without manual app-switcher substitution. The native destination displayed the system return link `< StyleMatch Pro`, confirming StyleMatch Pro as the originating application. Selected-store screenshot SHA-256: `556cd5b6172e0b16f4aa91ec2f824c9e9410f30a8886038ba92765f425ffbd52`. Native-destination screenshot SHA-256: `fda558586d45e1c24e5fd0fd387aa491adfb93898136f95a44bdc11222fb41ef`. The native screenshot is restricted evidence because ordinary private account UI is visible; no personal content is reproduced in this ledger.

Environment, deployment and artifact identity: Bundle `com.sabastine.stylematchai`; version/build 1.7 (1); installed pinned candidate unchanged. One separately authorized supported `devicectl` termination targeted only the verified pinned StyleMatch Pro PID 8011 to establish the process boundary. It succeeded once; the confirmation inventory showed zero processes in the pinned StyleMatch Pro bundle container. The separate StyleMatch AI 1.0.20 application was not touched. No crash, security rejection, automatic retry, unauthorized termination, source change, catalog change, build, installation, reinstall, replacement, signing action, or deployment occurred.

Authority and compatibility assessment: Immutable B5 remained an exact match after Route C: active 3 records at `2851dbd25dcc9fbc628517f831c61d37a4bac352e8b83ca6f8be7febc51a9200`; staging 6 records at `d8005542e432a022d7be91a16897e436b60fbddb18c19c02ee301ec9362c7053`; quarantine 0. Sanitized B5 comparison SHA-256: `264805f74f35cc3315060f829caed3d79ebaa8fdd37339db19b7f1383293b178`. Whole-preferences runtime churn did not affect any accepted retained-data authority.

Continuity compliance record: Chat impact was none. No Stylist binding, authentication, persistence, transport, context, Worker contract, or handoff changed. Existing supported-version contracts, regression suites, live-health state, retailer authorities, and the accepted B5 authority were not modified by this physical Shopping acceptance checkpoint.

Rollback evidence: Not applicable to the accepted physical result. This append-only entry may be superseded only by a separately authorized later record; it must not be rewritten.

Exceptions and expiration: The CLI os-log zero-byte result is classified as the known serializer artifact, not an application failure. Acceptance relies on the structurally complete finalized trace, nonempty TOC, privacy-reviewed derivative, and the accepted Instruments GUI fallback showing 1,114 unified-log rows. No required physical criterion is missing.

Open follow-up: Route C is complete. D7/SL1 remains separately unaccepted until the authorized criterion-by-criterion reconciliation of Routes A, B, and C is complete. CS1, SR1, TestFlight, deployment, App Store Connect, and other downstream work remain unopened.

### 2026-07-22 — IA1.1 and D7/SL1 final acceptance

Decision ID and checkpoint: IA1.1-FINAL / D7-SL1 — Three-retailer Shopping and centralized link-opening acceptance

Date: 2026-07-22

Status: Accepted

Governing decisions: ADR-001, ADR-005, ADR-006, ADR-007

Repository HEAD(s): Route C documentation baseline `b53ac0b61d76b7e43a3afe38a1b5996d178d0854` on `release/beta-2.0-shopping-composition`; installed pinned application source `5463866e7783d8d4e75318423c8d85a23c252d8c`. Route A, B, and C documentation commits are `9558c53d45334523c135940b7494a9e778fd6e51`, `f8076a737f53f2823625b9131250f724def0415e`, and `b53ac0b61d76b7e43a3afe38a1b5996d178d0854`, respectively. The documentation commits change no application source, tests, catalog, retailer authority, build setting, or runtime configuration relative to the pinned source.

Files/hunks owned: This append-only final acceptance record only. The final report and evidence manifest are retained outside source history at `Evidence/IA1.1/D7_SL1_FINAL_RECONCILIATION_2026-07-22/`. No application or device state was changed by reconciliation.

Automated evidence: The committed centralized-opening source contract remains byte-identical to the pinned application source. `ShoppingLinkOutTests.swift` SHA-256 `083a207581a011b58c407b2a46523ee8f869bb4c6188835f449f709713ab1a06`; `AffiliateProduct.swift` `e5062eb332ce6f1ee5b58c75fdf7c9edc74894ed9756bd2961f69611265b1820`; `ShoppingView.swift` `9a1c08de953f528d04a2355e05758f49629fb8aa388253dd01035d1b4d1f9471`; `StoreSearchView.swift` `4ef79d81b804c0423f447e50d0e85f8e426105e7f126da210caad8535ca99fa4`; `ScanView.swift` `76205cda73ae04698db85d160a6c9fe5d12f6e58b402586334dfcc5758199189`. This read-only reconciliation did not rerun tests. The signed pinned-device build log SHA-256 is `10a8084076bcbef432fb1c5c2b1b08f3dbc53eb20d0b38babea76084b8e8474c`.

Physical evidence: Route A accepted Nike-only selection, truthful zero-inventory/fallback retailer labeling, the approved Nike direct-store path, and the in-app browser at public `nike.com`; report SHA-256 `eaa70c9fc51288d3eae61b12c4be9c0486a9a44b95f5b6c657ad8eef6e12b4ad`. Route B accepted Macy's-only selection, truthful fallback attribution, public `macys.com` in the in-app browser, normal dismissal, and preservation of the selected store, filter/tab, navigation, and product/fallback context; report SHA-256 `4075f10f457fa88bd9a4ae1898ad1d08502ab3effe60fff4482ed24069d40898`. Route C accepted Best Buy-only selection, truthful direct-store state, one approved Open action, native Best Buy continuation, and the system return link to StyleMatch Pro; report SHA-256 `e5988afc3530625868a7ec40612222110b17b21375446fe8eaa4402007b3c214`. The final criterion-by-criterion report SHA-256 is `67ecd30d60e2bc84311214ea28f975b266ed8a5592ea84b89b172ab103a48fb2`; evidence manifest SHA-256 is `b047b91f0c01046b43e17469fe17d6296f2e2d19cc4431a2d0e8a857f68bac2a`.

Environment, deployment and artifact identity: Pinned artifact manifest SHA-256 `f90d7c42ee1a17457be1d100dbabe94e9883702fe31cf380c5007ab63533f885`; bundle `com.sabastine.stylematchai`; StyleMatch Pro 1.7 (1); executable SHA-256 `f58e67fb3da80a716f85e8c27d0db7059a85b5cc371605538aab4e124bd42a02`; pinned ZIP SHA-256 `88f980042606fed10057528302a33fddb7b8de07164438ff748c4ee04e5afff3`. Catalog and retailer files in the installed artifact match pinned source exactly. No source/catalog/build/install/signing/deployment mutation occurred across the accepted routes or final reconciliation.

Authority and compatibility assessment: D7/SL1 is accepted. Centralized validated opening is retained for Shopping product/store entry points; configured HTTPS validation fails closed; universal-link/native opening is attempted first; declined/unavailable universal links use the validated in-app-browser destination; typed completion results are preserved; invalid destinations do not invoke the opener; and bypassing raw opens are excluded by the committed source contract. Physical evidence confirms in-app-browser fallback, clean state-preserving dismissal, and native Best Buy continuation. Immutable B5 remained exact after every route: active 3 records at `2851dbd25dcc9fbc628517f831c61d37a4bac352e8b83ca6f8be7febc51a9200`; staging 6 records at `d8005542e432a022d7be91a16897e436b60fbddb18c19c02ee301ec9362c7053`; quarantine 0.

Continuity compliance record: Chat impact was none. No Stylist binding, authentication, persistence, transport, context, Worker contract, or handoff changed. Privacy-reviewed derivatives contain only bounded runtime/aggregate evidence. Raw logs and the Route C native screenshot remain restricted local evidence. No crash, security rejection, automatic retry, unauthorized process action, source change, catalog change, build, installation, signing action, deployment, or retained-data mutation occurred in an accepted route.

Rollback evidence: The physical and documentation acceptance records are append-only. The application rollback boundary remains the pinned source/artifact pair. Any future change to the centralized opener, catalog/retailer authorities, installed artifact, or retained-data authority invalidates only the affected future evidence and requires a new checkpoint; this record is not rewritten.

Exceptions and expiration: Route A screenshots were visually validated but did not materialize at the declared paths, so no screenshot hashes are claimed. Route A retains successful CLI TOC and explicit os-log exports. Route B's zero-byte CLI TOC is classified as a serializer artifact because its explicit os-log export and Instruments GUI fallback were usable. Route C's zero-byte explicit CLI os-log export is classified as a serializer artifact because its nonempty TOC and Instruments GUI fallback rendered 1,114 rows. These are evidence-tool limitations, not application failures.

Open follow-up: IA1.1 and D7/SL1 are complete. CS1 remains a separate prerequisite and is not accepted or begun by this record. SR1, TestFlight, deployment, App Store Connect, push, and every downstream checkpoint remain unauthorized until separately approved.

### 2026-07-23 — CE1 typed Context Engine contracts and legacy adapter accepted

Decision ID and checkpoint: CE1 — Typed outfit-context contracts and behavior-neutral legacy adapter

Date: 2026-07-23

Status: Accepted

Governing decisions: ADR-001, ADR-003, ADR-006, ADR-007

Repository HEAD(s): `STYLEMATCH_EXPANDED_GARMENT_CLASSIFICATION` implementation commit `369c464737386e6ae21801d217de15b8cd8c997d` on `feature/expanded-garment-classification`; parent `06f0826434db3f6b1422adb66e5ef58bd50d4feb`. Implementation patch SHA-256: `edb30dfd9a4ec24d921b0e3a377b57028173f12b78bb1ba20720836bc550c056`.

Files/hunks owned: Five implementation files with 1,308 insertions and no deletions: `Package.swift`; `StyleMatchAI.xcodeproj/project.pbxproj`; `StyleMatchAI/ContextEngine/OutfitContextContracts.swift`; `StyleMatchAI/ContextEngine/LegacyContextAdapter.swift`; and `StyleMatchProPhase2Tests/ContextEngineCE1Tests.swift`. This acceptance checkpoint owns only this append-only ledger entry. No production source or test file changed during acceptance reconciliation.

Automated evidence: Focused CE1 tests passed 16/16. The full Swift suite passed 723/723. Debug simulator build passed. Release simulator compile passed. Static analysis passed, with only the two documented pre-existing warnings in protected Shopping code. `git show --check` and the implementation whitespace check passed. The acceptance review did not rerun these unchanged green gates because the reviewed implementation commit and patch identity matched exactly and no contradictory evidence was found. The committed CE1 test file contains 16 focused test methods covering typed adaptation, explicit uncertainty, deterministic output, unknown-value fallback, score and breakdown preservation, privacy-safe evidence, non-rewriting legacy access, and absence of Shopping/catalog/persistence-write dependencies.

Physical evidence: NOT APPLICABLE to CE1 itself. CE1 adds a behaviorally inactive contract layer and deterministic transient adapter with no runtime consumer adoption, UI path, AI payload, voice path, scoring path, persistence write, or device behavior. This classification does not constitute physical acceptance of any future Context Engine runtime behavior. All hardware-dependent Context Engine behavior remains unimplemented and unaccepted.

Environment, deployment and artifact identity: No build artifact was installed or deployed by CE1 acceptance. No signing, certificate, provisioning, TestFlight, App Store Connect, Worker, deployment, device, or B5 action occurred. Protected Shopping and catalog files remained byte-identical: `ShoppingView.swift` SHA-256 `9a1c08de953f528d04a2355e05758f49629fb8aa388253dd01035d1b4d1f9471`; `StoreSearchView.swift` SHA-256 `4ef79d81b804c0423f447e50d0e85f8e426105e7f126da210caad8535ca99fa4`; `ProductCatalog.json` SHA-256 `6c7abb5e08905334d0e0e3196d32c03153db5a830330f69819c49c63997819e3`.

Authority and compatibility assessment: CE1 preserves the existing score and breakdown exactly and does not recompute either. Legacy scans are read into a transient typed snapshot without rewriting records, destructive migration, key reuse, or persistence mutation. Unsupported purpose and workplace values remain explicitly uncertain; `.otherUncertain` remains uncertain; detected visual style remains separate from garment category and purpose; identical inputs produce deterministic adapter output; and unknown future enum values decode to documented fail-closed fallbacks. The contract includes typed purpose, workplace profile, environment, occasion/workplace/weather/safety suitability, confidence, evidence, missing evidence, scoring-profile, and provenance fields. Raw OCR text, speech, names, employer identity, branding identity, badge values, and other private legacy evidence are not copied into the snapshot; generic presence-only summaries are used. Project and Swift Package integration are additive. CE2 runtime inference, persistence integration, current-scan consumer adoption, UI confirmation, AI/voice integration, and scoring experiments remain unopened.

Continuity compliance record: Chat impact is none at runtime. CE1 introduces types but does not modify binding, authentication, persistence, transport, current-scan selection, prompt construction, Worker payloads, response validation, handoffs, or live health. Supported-version contracts and Worker behavior remain unchanged; Worker suite, live-health checks, and device chat acceptance are NOT APPLICABLE to this inactive layer. Dependency ownership remains the iOS Context Engine contract layer; lifecycle and rollback are compile-time source boundaries. No new active dependency or single point of failure was introduced.

Rollback evidence: CE1 is isolated in implementation commit `369c464737386e6ae21801d217de15b8cd8c997d`. A future rollback may revert that commit before CE2 consumer adoption without migrating or rewriting user data. No amend, rebase, reset, merge, or history rewriting occurred.

Exceptions and expiration: None for CE1. Physical evidence is explicitly NOT APPLICABLE only because no runtime path consumes CE1. This exception does not extend to CE2 or any later runtime, persistence, AI, UI, voice, scoring, or device checkpoint.

Open follow-up: CE1 is formally accepted. Overall release readiness remains BLOCKED. Q2/CE2 planning and implementation remain unopened and require separate authorization. No physical Context Engine behavior, release candidate, Shopping refinement, deployment, TestFlight, or App Store action is accepted by this record.
