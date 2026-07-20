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
