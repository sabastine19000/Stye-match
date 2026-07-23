# AI Authority and Context Audit

Date: 2026-07-22

Governing decisions: ADR-001, ADR-003, ADR-006

## Authority contract

| Fact | Owner | Consumer rule | Local result |
|---|---|---|---|
| Numeric score and breakdown | Scan | AI may explain, never calculate or override | PASS |
| Scan identity/completion | `CurrentScanContextProvider` | One immutable context per request | PASS |
| Explicit historical selection | Saved scan handoff | Overrides global latest for that interaction | PASS |
| Latest standalone scan | Provider reload at send time | Newer completed record wins deterministically | PASS |
| Closet ownership | Closet storage | Historical/Shopping items cannot become owned | PASS |
| Product recommendation | Shopping | Remains external and separately attributed | PASS; regression only |
| Garment category | Typed scan classification plus correction | Correction is authoritative; uncertainty remains explicit | PASS locally |
| Weather/occasion | Same scan analysis/context | No cross-scan mixing | PASS locally |

## Request lifecycle

`StylistChatService.send` resolves and validates current context before creating the user and assistant turns. Both messages receive the same optional `scanContextID`. The request builder excludes complete typed turns whose ID conflicts with current authority. Legacy messages remain decodable and are filtered conservatively by conflicting score evidence.

The provider rejects incomplete or inconsistent stored analyses, orders completion timestamps deterministically, and uses scan ID for equal timestamps. It carries only an on-device image-presence marker, never image bytes or paths. Latest-scan lookup no longer decodes thumbnail bytes.

## Scenario matrix

| Scenario | Evidence | Result |
|---|---|---|
| Prior 74, new 80 | `testCurrentScanProviderPromotesNewerCompletedScanOverStaleLiveContext`; `testChatRequestUsesAuthoritative80AndDropsStale74AssistantMemory` | PASS |
| Immediate post-scan question | Send-time provider resolution and current scan tests | PASS locally; device pending |
| AI Assist/standalone consistency | Shared typed scan constructor/provider tests | PASS locally; device pending |
| Explicit older saved scan | `testExplicitOlderSavedScanRemainsAuthoritativeForHistoricalQuestions` | PASS |
| New scan with old conversation open | typed turn exclusion test | PASS |
| Relaunch/legacy history | legacy message decode and conversation restoration tests | PASS |
| Empty history | provider returns no authority; no-invention contracts | PASS |
| Failed/deleted scan | saved-scan invalidation tests | PASS |
| Quarantined scan | no direct local fixture tied to DR1 quarantine | NOT EVIDENCED |
| Equal timestamps | source tie-break review | PASS by deterministic code; dedicated named test recommended |
| Occasion change after scan | selected scan facts propagate; end-to-end UI not run | PARTIALLY VERIFIED |
| Weather update | same-context weather tests | PARTIALLY VERIFIED |
| Backend timeout/auth/offline/malformed | transport error tests | PASS locally |
| Long/duplicate sends | request-size and duplicate-submission tests | PASS |
| Voice/typed same conversation | convergence tests | PASS locally; hardware pending |
| Draft/navigation | source-contract tests | PARTIALLY VERIFIED; physical pending |

## Remaining limitations

- Legacy untyped prose cannot be perfectly attributed to a scan. The compatibility filter fails closed on conflicting score text but cannot create historical identity retrospectively.
- Generic AI chat has tab-level context, not arbitrary visual access.
- Quarantine integration and physical latest-scan behavior remain blocked.
- AI Home and Dress Me Today have automated coverage but no new runtime acceptance in this checkpoint.
