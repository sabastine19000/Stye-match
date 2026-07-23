# StyleMatch Pro Full System Diagnostic

Date: 2026-07-22

Status: Local diagnostic and safe remediation complete; physical acceptance blocked

Governing decisions: ADR-001, ADR-003, ADR-006, ADR-007

## Pre-edit authority snapshot

- Branch: `feature/expanded-garment-classification`
- Baseline HEAD: `7dee1285445d7e28d529586986a3bd6ec0d61a7c`
- Index: empty
- Protected tracked patch SHA-256: `1e8ab3166dc88dd44e86b787bd5c3fb66305cf1cdd90d97f22e57e7799cca7ea`
- Untracked `OutfitClassificationTests.swift` SHA-256: `64afedc0783294c3220d4e40b30ee57bb53e3baf93372c25700c77f9d471794c`
- `git diff --check`: PASS
- Ignored `Secrets.xcconfig`: present and ignored; contents not inspected
- Fresh Swift test baseline: 697 passed, 0 failed
- Physical-device status: not attempted in this checkpoint
- Accepted IA1.1/D7-SL1 Shopping behavior: protected, out of mutation scope
- B5 retained-data authority: protected, not accessed or mutated

## Initial diagnostic matrix

| System | Initial state | Reason |
|---|---|---|
| Scan score authority | PASS | Existing score owner remains Scan; no scoring change in dirty patch |
| Current scan context | PARTIALLY VERIFIED | Shared typed provider exists and automated 74-to-80 test passes; performance and edge cases require review |
| Historical saved-scan authority | PASS | Explicit saved selection overrides global latest in tests |
| AI Assist/chat consistency | PARTIALLY VERIFIED | Typed authority is shared, but stale message filtering remains text-pattern based |
| Screen awareness | PARTIALLY VERIFIED | Typed context exists; complete transition matrix is not yet evidenced |
| Garment classification | FAIL | Confirmed substring collision and uncertainty-state defects |
| OCR privacy | PASS | Raw OCR strings are transient and generic evidence is persisted |
| OCR performance | NOT EVIDENCED | No dedicated timing/signpost evidence |
| Voice lifecycle | FAIL | Permission-await cancellation can resume a cancelled recognition attempt |
| Keyboard/composer | PARTIALLY VERIFIED | Automated UI-contract tests pass; physical keyboard stress remains mandatory |
| Persistence compatibility | PARTIALLY VERIFIED | Legacy decode is safe; cached classification enrichment mutates saved history |
| Shopping regression | PASS | Accepted Shopping files are unchanged; no redesign is authorized |
| Physical-device reliability | BLOCKED | Separate authorization and device/signing prerequisites required |

This matrix is the pre-remediation baseline. Later sections must not rewrite this snapshot; final results are recorded separately.

## Root causes and repairs

1. **Competing scan authority in conversation history.** New structured scan facts were correct, but persisted assistant prose had no scan identity and could survive into a newer request. `ChatMessage.scanContextID` now binds both sides of a turn to one scan. Request construction drops complete turns bound to a different scan; legacy turns remain compatible and are conservatively filtered when their score conflicts.
2. **Latest-scan read amplification.** `CurrentScanContextProvider` decoded thumbnail bytes merely to establish image presence. Its lightweight decoder now reads only score, analysis, timestamp, occasion, and whether the thumbnail key is non-null.
3. **Classifier lexical collisions.** Substring tests allowed terms such as `swimsuit` to satisfy `suit`. Matching now uses normalized token/phrase boundaries.
4. **False certainty and profile corruption.** Selecting `Other / Uncertain` incorrectly cleared uncertainty, and category correction overwrote detected style. Uncertain remains uncertain; correction preserves `styleBalance`.
5. **Incorrect category policy.** Uniforms could bypass owner confirmation at high confidence and casual dresses inherited formal-event evaluation. Uniform categories now require confirmation; casual dress uses the casual/everyday profile.
6. **Speech start cancellation race.** Permission awaits could resume after the owner had navigated away or cancelled. Every start has an attempt identity checked after each suspension point and immediately before recognition begins.
7. **Cached-repeat persistence side effect.** Reading an exact cached legacy scan silently enriched and rewrote it. Enrichment is now in-memory until an explicit user correction/save path.
8. **Chat backup staleness.** The backup copy was never refreshed once it existed. Each atomic write now atomically replaces the backup with the previous primary and exposes a generic, privacy-safe persistence error if saving fails.
9. **Forced prompt-encoding crash.** A `try!` in verified-context serialization could terminate the app. Encoding now fails closed with an explicit no-inference instruction.
10. **Missing performance instrumentation.** Debug-only OCR and classifier timings now record stage and duration only. No OCR text, image, person, brand, scan ID, or account value is logged.

## Local verification summary

- Focused outfit-classification suite: 14 passed, 0 failed.
- Focused conversational-stylist suite: 75 passed, 0 failed before the final backup test; the final complete suite includes that test.
- Complete final Swift suite: 707 passed, 0 failed.
- Debug iOS Simulator build: PASS, signing disabled.
- Release iOS Simulator compile: PASS, signing disabled.
- Static analysis: PASS with two pre-existing warnings in protected `ShoppingView.swift`; no accepted Shopping source was changed.
- External Swift package dependencies: none.
- `git diff --check`: PASS at each reported checkpoint; final result is recorded in the test report.
- Secrets: ignored configuration exists and is non-empty; values were never read, printed, hashed, or copied.
- Shopping drift from pinned application commit `5463866e7783d8d4e75318423c8d85a23c252d8c`: none in Shopping source/catalog paths.
- Device, signing, installation, B5, deployment, TestFlight, and App Store Connect: not accessed or changed.

## Readiness decision

The local architecture is materially safer and no known critical/high source defect remains open. Release readiness is **BLOCKED**, not failed: real microphone routing/tap ownership, keyboard/voice stress, OCR latency and classification quality, current-scan end-to-end behavior, legacy upgrade behavior, and B5 preservation still require the separately authorized physical plan. Shopping refinement must not begin until those hardware-dependent gates pass and the branch is separately reviewed for commit.
