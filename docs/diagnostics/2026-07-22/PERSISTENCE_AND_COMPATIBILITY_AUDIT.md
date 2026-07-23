# Persistence and Compatibility Audit

Date: 2026-07-22

| State | Storage/authority | Local conclusion |
|---|---|---|
| Scan history | `outfitScanHistoryData` | Legacy decode preserved; deterministic latest selection |
| Active scan | typed in-memory handoff | invalidated on new session/deletion |
| Staging/quarantine/B5 | protected device authorities | not accessed or mutated |
| Closet/profile/sizing | existing local stores | regression suite passed; no schema change here |
| Chat history | atomic JSON plus backup | backup refresh repaired; corrupt-primary recovery tested |
| Chat turn scan identity | optional Codable field | old messages decode; new turns are attributable |
| Draft | active chat view/speech snapshot | automated preservation contracts pass |
| Store preferences/favorites | accepted Shopping state | source unchanged |
| Classification correction | saved analysis on explicit action | correction preserves style and score |
| Weather | existing cached/context facts | no storage migration |

## Atomicity and recovery

Before each primary chat write, the existing primary bytes atomically replace the backup. A failure leaves in-memory conversation state intact and sets a generic `persistenceErrorMessage`; it does not log content. Corrupt-primary loading falls back to the latest prior successful primary.

## Compatibility

- `ChatMessage.scanContextID` is optional.
- New outfit-classification fields are optional/defaulted in legacy scan analysis.
- Thumbnail presence is detected without decoding bytes in latest-context lookup.
- No eager rewrite, duplicate migration, automatic deletion, reset, or quarantine operation occurs.

## Remaining gaps

- The generic persistence error is not yet surfaced in chat UI.
- Reinstall/upgrade behavior, DR1 quarantine interaction, and B5 exact preservation require physical validation.
- Test fixtures are isolated in temporary directories and UserDefaults suites; production-like device data was not read.
