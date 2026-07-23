# StyleMatch Pro Defect Register

Date: 2026-07-22

| ID | Severity | Feature | Defect and root cause | Initial status |
|---|---|---|---|---|
| SYS-001 | High | Garment classification | `Other / Uncertain` was stored as a user-confirmed category, causing `isUncertain` to become false | Fixed; regression test |
| SYS-002 | High | Garment classification | Raw substring matching allowed `swimsuit` to match the `suit` category | Fixed; token-boundary test |
| SYS-003 | High | Voice | A cancelled permission-awaiting start could resume and begin recognition after teardown | Fixed locally; physical proof blocked |
| SYS-004 | High | Scan evidence | User category correction overwrote independently detected `styleBalance` | Fixed; preservation test |
| SYS-005 | Medium | Uniform classification | High-confidence uniform categories bypassed requested confirmation | Fixed; confirmation test |
| SYS-006 | Medium | Scoring profile | Casual dress mapped to formal-event criteria | Fixed; profile test |
| SYS-007 | Medium | Chat history | Stale-context filtering relied on `N/100` text and could leave unmatched user turns | Fixed for typed turns; legacy conservative filter retained |
| SYS-008 | Medium | Performance | Latest-scan send path decoded history including thumbnail bytes | Fixed with lightweight decoder |
| SYS-009 | Medium | OCR/performance | OCR/classification stages lacked dedicated timing evidence | Instrumented in Debug; device benchmark blocked |
| SYS-010 | Medium | Persistence | Cached legacy scan enrichment wrote classification during a repeat read path | Fixed; read path no longer persists |
| SYS-011 | Process blocker | Physical acceptance | Creating new unique scans necessarily changes active B5 history, conflicting with an exact-hash requirement | Open; plan requires isolated test data or an owner-authorized baseline strategy |
| SYS-012 | Medium | Chat persistence | Backup creation used `copyItem` without replacing an existing backup, leaving recovery stale | Fixed; backup-refresh recovery test |
| SYS-013 | Medium | AI context | Verified-context JSON used `try!`, creating a theoretical process-termination path | Fixed; fail-closed source test |
| SYS-014 | Low | Static analysis | Accepted `ShoppingView.swift` has an unreachable catch and unused binding warning | Open and out of scope; no behavior failure shown |
| SYS-015 | Medium | Screen awareness | Typed context does not carry selected product/store/favorite/detail identities | Open; unsupported evidence must remain unavailable |
| SYS-016 | Medium | Persistence UX | Save failure is now observable in the store but is not yet surfaced in chat UI | Open; data remains in memory and no private error is logged |

Each confirmed repair requires a focused regression test. Physical voice, OCR latency, and device-data conclusions remain blocked until separately authorized.

## Residual severity decision

No critical defect is known from local evidence. No high defect remains open in source, but SYS-003 cannot be closed as a release gate until physical audio acceptance succeeds. SYS-011 is the controlling evidence-design blocker for a physical scan campaign. SYS-015 and SYS-016 are medium follow-ups and are not silently treated as passes.
