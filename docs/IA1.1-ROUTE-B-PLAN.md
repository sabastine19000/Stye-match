# IA1.1 Route B Plan — Macy's and D7 Browser Fallback

**Status:** Prepared only; execution requires separate authorization
**Governing decisions:** ADR-001, ADR-005, ADR-006, ADR-007
**Pinned composition HEAD:** `5463866e7783d8d4e75318423c8d85a23c252d8c`
**Installed candidate:** `com.sabastine.stylematchai`, StyleMatch Pro 1.7 (1)
**Executable SHA-256:** `f58e67fb3da80a716f85e8c27d0db7059a85b5cc371605538aab4e124bd42a02`

## Scope

Route B will validate only the Macy's Shopping route and the D7 in-app-browser fallback/dismissal behaviors. It will not execute Best Buy Route C, declare D7/SL1 accepted, update the ledger, or begin CS1, SR1, TestFlight, deployment, or any implementation work.

## Immutable authorities

- Active B5: 3 records; SHA-256 `2851dbd25dcc9fbc628517f831c61d37a4bac352e8b83ca6f8be7febc51a9200`.
- Staging B5: 6 records; SHA-256 `d8005542e432a022d7be91a16897e436b60fbddb18c19c02ee301ec9362c7053`.
- Quarantine: 0 keys.
- Catalog, retailer registry, installed artifact, signing, source, tests, and repository state remain unchanged.

## Preflight

1. Confirm iPhone Mirroring is fully closed; do not terminate it or any other process without explicit authorization.
2. Confirm the wired iPhone is connected, unlocked, awake, paired, trusted, and available to Instruments.
3. Confirm the composition repository remains at the pinned HEAD with a clean worktree and index.
4. Confirm the installed bundle, version/build, executable identity, and signing identity still match the pinned candidate.
5. Confirm the current B5 active, staging, and quarantine authorities match exactly by read-only acquisition.
6. Establish the separately authorized process boundary, if required. Do not infer process absence from an unavailable inventory and do not perform an unapproved termination.
7. Create a new explicit evidence directory. Start privacy-safe console capture and run xctrace directly as the foreground PTY process using the validated Logging protocol. No wrapper, pipe, `tee`, backgrounding, or external timeout.
8. Confirm foreground recording is active before requesting the first owner action.

Any failed precondition stops Route B before physical interaction. There is no automatic retry or repair.

## Owner-operated route

Codex provides exactly one instruction at a time and waits for owner confirmation. The owner performs all taps, swipes, selections, browser dismissal, and screenshots on the physical iPhone.

1. Launch the pinned app through the armed capture procedure and open Shopping.
2. Select Macy's as the only store and capture the selected-store state.
3. Verify the UI truthfully identifies Macy's and does not misrepresent products from another retailer as Macy's inventory.
4. Use only the approved Macy's product or fallback path. An unapproved product substitution is a hard stop.
5. Confirm the centralized opener presents the in-app browser and reaches the expected public Macy's destination.
6. Capture the browser destination without exposing credentials, account data, tokens, or private URLs.
7. Record the pre-dismissal Shopping context required for D7: selected store, active filter, navigation position, and relevant product/fallback context.
8. Dismiss the in-app browser normally.
9. Verify return to the same prior Shopping state with the selected store, filter, navigation, and product/fallback context preserved.
10. Capture the post-dismissal state.

## Capture finalization and evidence

1. After the final post-dismissal screenshot, send one direct Ctrl-C to the foreground xctrace PTY or allow its declared natural limit to complete.
2. Await recording completion, save messages, process exit, and trace-size stability before export.
3. Preserve the original trace unchanged. Require `form.template`, `UI_state_metadata.bin`, `corespace/MANIFEST.plist`, run metadata, runtime stores, an `os-log` schema, and nonempty runtime rows.
4. Export the TOC and explicit os-log table with unrestricted Xcode cache access. If the CLI serializer fails while the trace is structurally valid, retain the trace and use the approved Instruments GUI inspection/export fallback; do not repeat the physical route automatically.
5. Privacy-review raw and sanitized derivatives and record paths, sizes, and SHA-256 hashes. Do not expose tokens, private URLs, identifiers, account content, scan content, or unrelated activity.
6. Reacquire retained data read-only and require an exact match to all immutable B5 authorities.

## Route B pass requirements

- Macy's is the only selected store.
- Retailer attribution and any thin-inventory fallback are truthful.
- The approved Macy's path opens the in-app browser at the expected public destination.
- Normal dismissal returns to Shopping.
- Selected store, filter, navigation, and product/fallback context are preserved across dismissal.
- Same-attempt screenshots and usable privacy-safe runtime evidence are retained.
- The trace finalizes normally and remains unchanged.
- B5 matches exactly: 3 active, 6 staging, 0 quarantine.
- No crash, security rejection, unauthorized termination, retry, source/catalog/build/install/signing/deployment change, or downstream action occurs.

## Hard stops

Stop immediately on device lock/disconnection, identity drift, dirty composition state, capture failure, misleading attribution, unapproved path substitution, browser failure, lost dismissal state, B5 mismatch, or any apparent need for repair or mutation. Report the exact boundary without retrying.

## Required Route B report

Return the attempt timestamps, PID, physical results, pre/post dismissal state comparison, console and xctrace evidence paths/hashes, screenshot references, post-route B5 comparison, privacy review, complete Git status, and one verdict: `ROUTE B — PASS`, `ROUTE B — FAIL`, `ROUTE B — BLOCKED`, or `ROUTE B — NOT ATTEMPTED`.
