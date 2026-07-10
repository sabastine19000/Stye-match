TASK: Remove founder/demo profile defaults from StyleMatch AI and replace with true blank/unset state, with a safe one-time migration. Phase A diagnosis is complete — proceed directly to implementation. Work in the existing worktree at /private/tmp/stylematch-profile-pants-sync.

CONTEXT FROM PHASE A:
Founder/demo defaults (colors "Black, white, navy"; brands "Ralph Lauren, Nike, Levi's"; budget "$50 - $200"; shirt L; pants "Men 36x36"; waist 36; inseam 36; shoe 10; fit Regular) are hardcoded as @AppStorage/UI defaults in ProfileView.swift (line ~14) and repeated in ScanView.swift (line ~10). ProfileStore reads UserDefaults and treats these never-saved defaults as real user data. deleteSavedData() (ProfileView.swift ~1267) resets to founder defaults instead of blank. Completeness scoring uses fixed total = 50 (ProfileView.swift ~885) and a duplicate score in ProfileStore (~120) that counts default-filled fields as complete.

SCOPE — PHASE B1 ONLY. Files you may modify:
- StyleMatchAI/ProfileView.swift
- StyleMatchAI/ScanView.swift (defaults removal only — do NOT touch camera/scan logic)
- StyleMatchAI/PersonalStylist/ProfileStore.swift
- StyleMatchAI/PersonalStylist/StylistProfileModels.swift
- StyleMatchProPhase2Tests/StyleMatchProPhase2Tests.swift
Do NOT modify ClosetView.swift, ContentView.swift, HomeView.swift, or AIAssistantsView.swift in this phase — empty-state copy across those views is Phase B2.

REQUIREMENTS:

1. BLANK DEFAULTS
Replace all founder/demo default values in ProfileView.swift and ScanView.swift with blank/unset (empty string or nil as appropriate). Make preferredFit, budgetRange, climate, and workDressCode support a true unset state — either make them optional or add an explicit .unset/"Not set" case — so decode no longer silently fills "Regular", "$50-$200", "Mild", "Smart casual". Existing saved profiles with real user values must decode unchanged.

2. ONE-TIME FOUNDER-FINGERPRINT MIGRATION
Add a one-time migration gated by a new flag (e.g. UserDefaults key "didRunFounderDefaultsMigration_v1"). The migration clears profile size/preference values ONLY when BOTH conditions hold:
  (a) values exactly match the full founder fingerprint: Men, shirt L, pants "Men 36x36", waist 36, inseam 36, shoe 10, fit Regular, AND
  (b) profileLastSavedAt is nil (no intentional save ever recorded).
CRITICAL: if profileLastSavedAt exists, NEVER clear data, even on an exact fingerprint match — a real user can legitimately have these sizes. This is an AND condition, not a fallback. Partial fingerprint matches must not trigger the reset. The migration runs once and sets the flag regardless of outcome.

3. FIX deleteSavedData()
deleteSavedData() must reset ALL profile fields to blank/unset — never to founder defaults — and must clear profileLastSavedAt and any other "user has saved" markers. After deletion the app must behave identically to a fresh install with the new blank defaults.

4. STOP THE @AppStorage → ProfileStore LAUNDERING PATH
ProfileStore must not treat never-saved @AppStorage/UserDefaults values as user data. Gate ProfileStore's reads on profileLastSavedAt (or an equivalent explicit save marker): if no intentional save has occurred, ProfileStore returns an empty/blank profile rather than echoing UI defaults. State in your report exactly how this gate works.

5. SINGLE SOURCE OF TRUTH FOR COMPLETENESS
Consolidate completeness scoring into one implementation (prefer ProfileStore). Remove the fixed total = 50 in ProfileView. Completeness must count only genuinely user-entered fields; a fresh install must show 0% complete. ProfileView displays the score from the single source.

TESTS REQUIRED (add to StyleMatchProPhase2Tests.swift):
- Fingerprint matches AND profileLastSavedAt is nil → values cleared, flag set
- Fingerprint matches BUT profileLastSavedAt exists → data fully preserved, flag set (the data-loss guard — this test is mandatory)
- Partial fingerprint match, no save marker → data preserved
- Migration flag already set → migration does not run again
- deleteSavedData() → all fields blank, no founder values present, save marker cleared
- Fresh install (no save marker) → ProfileStore returns blank profile even if UserDefaults contains default-looking values
- Fresh install → completeness = 0%
- Existing real saved profile → decodes unchanged, completeness counts its fields

HARD CONSTRAINTS:
- Zero diff to calculateStyleScore()
- No new AI call sites
- ProfileStore/OutfitMemoryStore atomic write mechanics untouched
- No changes to camera, scan, or classification logic in ScanView.swift
- Verify with: swift test --quiet (macOS destination). NEVER run xcodebuild.
- git diff --check must be clean
- Do not commit; leave changes uncommitted in the worktree (Git access is currently blocked)

REPORT BACK:
- Summary of changes per file
- Exact migration trigger logic as implemented
- How the ProfileStore save-marker gate works
- Test results (count, failures)
- Confirmation of each hard constraint
- Any founder-default values you found beyond the Phase A list, and where

---

## B1 Addendum - Explicit Acceptance Criteria

Add the following section to the end of the Phase B1 prompt. The B1 report must address each criterion explicitly with evidence: test name, code path, or simulated launch trace. Any criterion not demonstrably met means B1 is incomplete.

### Acceptance Criteria - must be individually verified in the report

#### AC1 - Fresh install shows blank size fields

On a first launch with no prior data, meaning no save marker and no legacy keys:

- Size category, shirt size, pants size, waist, inseam, neck, sleeve, shoe size, and preferred fit are all unset or blank. They must never default to Men, L, 36x36, 36, 10, or Regular.
- Profile completeness reflects an empty profile, near 0%, not an inflated value.
- Fit-check strings on scanned items must not claim "using your saved sizes" when no sizes are saved. Report what the empty-state string will be. Final copy is Phase B2, but the conditional must exist in B1.
- Provide or extend a unit test asserting a freshly constructed profile has no size values.

#### AC2 - Existing user with genuinely saved sizes is preserved

A user whose saved sizes happen to equal the old founder defaults, such as 36x36, L, Shoe 10, Regular, and who has the save marker set must come through migration with all values intact.

- The migration condition must be fingerprint AND save-marker-absent. Confirm in the report, with the exact code excerpt, that no branch wipes data on fingerprint match alone. An OR anywhere in this logic is an automatic fail.
- Provide a unit test: profile with default-equal values plus save marker present -> migration is a no-op.
- Provide the inverse test: default-equal values plus no save marker -> values cleared. This is the actual founder-default wipe case.

#### AC3 - Size edits save, persist, and propagate

After a user changes pants size, for example 36x36 -> 34x34, and saves:

- The value persists across app relaunch. Atomic write path must remain unchanged.
- The save marker is set if it was not already.
- The Closet tab Size Profile card reflects the new value.
- Fit-check strings on scanned items read the current saved size, not a cached or stale copy. Identify in the report where fit-check strings source their size data and confirm it is the same single source of truth the Profile editor writes to. If it is a separate copy, flag it. Do not fix it in B1 if it belongs to the pants-sync worktree changes; note the dependency instead.
- Provide a unit test: save -> mutate -> reload store -> assert new value.

#### AC4 - Delete returns to blank, not to defaults

After deleteSavedData() runs:

- All size fields return to unset or blank, and the save marker is cleared.
- Relaunching after deletion must behave exactly like AC1, a fresh install. It must not resurrect 36x36, L, 10, or Regular from any code path, cached struct, or default initializer.
- Provide a unit test: save sizes -> delete -> assert blank state and cleared marker -> simulate relaunch by re-initializing the store -> assert still blank.

### Required report format

For each of AC1-AC4:

- State PASS or FAIL.
- Name the test or tests covering it.
- Cite the file and line of the relevant logic.
- Run `swift test --quiet` with the macOS destination and report the total pass count.
- Leave everything uncommitted.
