# Physical Acceptance Plan

Date: 2026-07-22

Status: Prepared only; execution requires separate authorization

## Preconditions

1. Freeze and record branch commit/artifact identity after an authorized commit/build.
2. Verify signing, bundle/version/build, entitlements, executable hash, device model/OS, and clean repository.
3. Resolve SYS-011: use isolated scan test data or an explicitly authorized retained-data baseline strategy. Never overwrite immutable B5 by implication.
4. Capture pre-install active/staging/quarantine authorities.
5. Install from the exact candidate without uninstalling.

## Additive B5 rule requiring owner approval

If the owner authorizes physical testing against the existing retained-data set, completing new scan scenarios is expected to add records and therefore cannot satisfy a byte-identical active-history hash.

The permitted additive rule is:

- every pre-campaign active record must remain present and byte-for-byte unchanged;
- every pre-campaign staging record must remain present and byte-for-byte unchanged;
- quarantine must remain unchanged and no existing record may move into it;
- each added active record must be attributable to an explicitly performed test step, structurally valid, uniquely identified, and accompanied by its creation timestamp;
- no prior record may be deleted, rewritten, duplicated, restored, migrated, reordered in a semantically destructive way, or silently reclassified;
- the post-campaign payload hash and counts become evidence for that campaign only and do not supersede immutable B5 without a separate baseline-adoption authorization.

If record-level comparison cannot prove these properties without exposing private content, use an isolated test profile/container instead. Stop rather than weakening the rule. The owner must explicitly choose and authorize one of these strategies before installation or scan creation.

## Campaign

1. **Data preservation:** verify pre/post install and pre/post campaign retained authorities.
2. **Latest authority:** begin with an older 74 scan, complete an 80 scan, ask AI Assist and standalone chat immediately; compare scan ID, score, style, confidence, occasion, weather, breakdown, classification, and completion time.
3. **Historical authority:** open the older scan and verify it remains selected; delete/invalidate a test record and verify fail-closed behavior.
4. **Screen awareness:** move Home → Scan → AI → Closet → Shopping → AI; verify no prior-screen claims. Product/store questions must decline unsupported specificity.
5. **Classification:** test clear work uniform, ambiguous outfit, user correction, unreadable/angled text, and one representative formal/active category. Capture confirmation behavior and privacy-safe Debug timing.
6. **OCR performance:** record OCR/classification durations, total result latency, device temperature, and memory symptoms. Do not retain raw OCR.
7. **Voice/keyboard:** execute the stress plan in `VOICE_KEYBOARD_STABILITY_AUDIT.md`; preserve instrumentation guard outcomes and verify real transcription.
8. **Lifecycle:** background/foreground during chat/voice, relaunch with draft/history, permission denial/recovery, offline/timeout behavior.
9. **Shopping smoke:** regression only against accepted IA1.1/D7-SL1; no redesign or new acceptance inference.
10. **Final integrity:** reacquire retained authorities and reconcile.

## Stop conditions

Stop on crash, stale/mixed scan identity, invented evidence, data mismatch, unexpected migration/quarantine, invalid signing/artifact identity, privacy-bearing logs, unapproved Shopping drift, or inability to bind evidence to the exact build. Do not auto-repair, rebuild, reinstall, or replace the candidate.

## Required evidence

Timestamped screenshots/video, sanitized console and trace, artifact hashes, device/OS, scan IDs in hashed/truncated form, performance timings, exact B5 comparisons, per-criterion verdicts, and a statement of any missing evidence.
