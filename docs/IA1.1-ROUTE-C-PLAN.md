# IA1.1 Route C Plan — Best Buy Native-App Continuation

**Status:** Prepared only; execution requires separate authorization
**Governing decisions:** ADR-001, ADR-005, ADR-006, ADR-007
**Acceptance/documentation baseline:** Route B record prepared from composition HEAD `9558c53d45334523c135940b7494a9e778fd6e51`
**Pinned application source:** `5463866e7783d8d4e75318423c8d85a23c252d8c`
**Installed candidate:** `com.sabastine.stylematchai`, StyleMatch Pro 1.7 (1)
**Executable SHA-256:** `f58e67fb3da80a716f85e8c27d0db7059a85b5cc371605538aab4e124bd42a02`

## Scope

Route C will validate only the Best Buy Shopping route and native-app continuation through the centralized universal-link flow. It will not treat manually opening Best Buy as evidence, execute another retailer route, declare IA1.1 or D7/SL1 accepted, update the ledger during execution, or begin CS1, SR1, TestFlight, deployment, or implementation work.

## Immutable authorities

- Active B5: 3 records; SHA-256 `2851dbd25dcc9fbc628517f831c61d37a4bac352e8b83ca6f8be7febc51a9200`.
- Staging B5: 6 records; SHA-256 `d8005542e432a022d7be91a16897e436b60fbddb18c19c02ee301ec9362c7053`.
- Quarantine: 0 keys.
- Catalog, retailer registry, installed artifact, signing, source, tests, and repository state remain unchanged.
- Route A and Route B acceptance records are historical authorities and are not reopened by Route C.

## Owner preparation

1. Keep the physical iPhone connected by wired USB, unlocked, awake, and on the Home Screen.
2. Fully quit iPhone Mirroring before preflight and keep it closed throughout capture.
3. Confirm the Best Buy app is already installed and available. Do not install, update, sign in to, or otherwise configure it during Route C.
4. Avoid exposing Best Buy account information, purchase history, saved addresses, payment data, notifications, or unrelated phone content in screenshots or runtime evidence.

## Preflight

1. Confirm iPhone Mirroring is absent; do not terminate it or any other process without explicit authorization.
2. Confirm the wired iPhone is connected, unlocked, awake, paired, trusted, and available to Instruments.
3. Confirm the composition repository remains at the separately authorized Route C baseline with a clean worktree and empty index.
4. Confirm the installed StyleMatch Pro bundle, version/build, executable identity, and signing identity still match the pinned candidate.
5. Confirm the installed Best Buy application identity read-only without launching it.
6. Confirm current B5 active, staging, and quarantine authorities match exactly by read-only acquisition.
7. Inventory StyleMatchAI processes. Establish a clean process boundary only if separately authorized; do not infer absence from an unavailable inventory and do not perform an unapproved termination.
8. Create a new explicit evidence directory. Start privacy-safe console capture and run xctrace directly as the foreground PTY process using the validated Logging protocol. No wrapper, pipe, `tee`, backgrounding, or external timeout.
9. Confirm foreground recording is active before requesting the first owner action.

Any failed precondition stops Route C before physical interaction. There is no automatic retry, installation, repair, or process termination.

## Owner-operated route

Codex provides exactly one instruction at a time and waits for owner confirmation. The owner performs every tap, swipe, selection, app transition, and screenshot directly on the physical iPhone.

1. Launch the pinned StyleMatch Pro candidate through the armed capture procedure and open Shopping.
2. Select Best Buy as the only store and capture the selected-store state.
3. Verify the UI truthfully identifies Best Buy and does not represent another retailer's products as Best Buy inventory.
4. Use only the approved Best Buy product or direct-store path. An unapproved product substitution is a hard stop.
5. Capture the StyleMatch Pro state immediately before the destination action, including selected store, active tab/filter, navigation position, and relevant product/fallback context.
6. Tap the approved Best Buy path once.
7. Verify the transition resulted from that tap through the centralized universal-link flow and continued into the installed Best Buy app. Manually opening or app-switching to Best Buy is not acceptable evidence.
8. Capture a privacy-safe Best Buy destination screenshot that proves native-app continuation without exposing account or purchase data.
9. Do not browse, sign in, purchase, add to cart, grant permissions, or interact further in Best Buy.
10. Stop the physical route after destination evidence is secured. Returning to StyleMatch Pro is not required unless separately authorized.

## Capture finalization and evidence

1. After the final native-destination screenshot, send one direct Ctrl-C to the foreground xctrace PTY or allow its declared natural limit to complete.
2. Await recording completion, save messages, process exit, and trace-size stability before export.
3. Preserve the original trace unchanged. Require `form.template`, `UI_state_metadata.bin`, `corespace/MANIFEST.plist`, run metadata, runtime stores, an `os-log` schema, and nonempty runtime rows.
4. Export the TOC and explicit os-log table with unrestricted Xcode cache access. If the CLI serializer fails while the trace is structurally valid, retain the trace and use the accepted Instruments GUI inspection/export fallback; do not repeat Route C automatically.
5. Correlate the owner-witnessed tap and destination screenshot with same-attempt runtime evidence. Do not infer native continuation solely from the presence of the Best Buy app or from owner words.
6. Privacy-review raw and sanitized derivatives and record paths, sizes, and SHA-256 hashes. Do not expose tokens, private URLs, identifiers, account content, scan content, prompt content, or unrelated activity.
7. Reacquire retained data read-only and require an exact match to all immutable B5 authorities.

## Route C pass requirements

- Best Buy is the only selected store.
- Retailer attribution and any thin-inventory fallback are truthful.
- The approved Best Buy path is exercised exactly once from StyleMatch Pro.
- The centralized universal-link flow continues into the installed Best Buy app.
- Native continuation is tied to the product/direct-store tap; manual Best Buy launch or app switching is not accepted.
- Same-attempt screenshots and usable privacy-safe runtime evidence are retained.
- The trace finalizes normally and remains unchanged.
- B5 matches exactly: 3 active, 6 staging, 0 quarantine.
- No purchase, cart mutation, sign-in, permission grant, crash, security rejection, unauthorized termination, retry, source/catalog/build/install/signing/deployment change, or downstream action occurs.

## Hard stops

Stop immediately on device lock/disconnection, iPhone Mirroring interference, identity drift, dirty composition state, missing Best Buy app, capture failure, misleading attribution, unapproved path substitution, browser-only fallback where native continuation is required, manual destination substitution, unexpected sign-in/payment exposure, B5 mismatch, or any apparent need for repair or mutation. Report the exact boundary without retrying.

## Required Route C report

Return the attempt timestamps, StyleMatch Pro PID, physical results, pre-destination and native-destination comparison, console and xctrace evidence paths/hashes, screenshot references, post-route B5 comparison, privacy review, complete Git status, and one verdict: `ROUTE C — PASS`, `ROUTE C — FAIL`, `ROUTE C — BLOCKED`, or `ROUTE C — NOT ATTEMPTED`.

Do not update the acceptance ledger or project state during Route C execution. Any acceptance record requires a separate authorization after the evidence package is complete.
