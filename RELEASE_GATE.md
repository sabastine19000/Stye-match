# StyleMatch Pro Release Gate

Read and follow this file at the start of every StyleMatch Pro release. Do not bypass any gate.

Never declare a release candidate ready to push, archive, upload, submit, tag, or deploy unless every applicable item below is verified and reported with exact evidence from the current source state.

## Required checks

1. Confirm the exact branch and full commit hash.
2. Confirm `git status` is clean.
3. Confirm the local commit relationship to `origin/main`.
4. Confirm the compiled app identity:
   - Display name
   - Bundle identifier
   - Marketing version
   - Build number
5. Run and report:
   - Focused tests
   - Full test suite
   - Debug build
   - Release build
   - Release static analyzer
   - `git diff --check`
6. Confirm the tested physical-device build matches the same source commit. If the commit is not embedded or otherwise provable, mark this `NOT VERIFIED`.
7. Confirm no uncommitted files are required by the release.
8. Confirm no version, signing, backend, production-configuration, or secret changes occurred unexpectedly.
9. List every unresolved release blocker and validation gap.
10. Finish with exactly one release decision:
    - `GO`
    - `NO-GO`
    - `GO AFTER LISTED FIXES`

## Evidence rules

- Do not rely on previous results without first confirming that the source commit and working tree are unchanged.
- Report commands, hashes, test totals, build outcomes, and compiled identity values as applicable.
- If a check is not performed or cannot be proven, label it `NOT VERIFIED`. Never infer that it passed.
- Physical-device screenshots or observations do not prove source provenance unless the installed binary can be matched to the current commit.
- A dirty working tree is not an approved release source unless every change is explicitly reviewed and checkpointed first.

## Mandatory authorization stop

Before any push, archive, TestFlight upload, App Store submission, tag, or deployment, stop and request explicit authorization. Passing this gate does not itself authorize any of those actions.

## StyleMatch Pro 1.6 Build 15 checkpoint evidence

The following values identify the current checkpoint and must be freshly revalidated before release action:

- Commit: `49e8fb3a7c9faca60d2d46fc4b8722662bdaa3d7`
- Branch: `main`
- Expected relationship: two commits ahead of `origin/main`
- Focused tests: `46/46`
- Full test suite: `510/510`
- Debug build: passed
- Release build: passed
- Release analyzer: passed
- `git diff --check`: passed
- Display name: `StyleMatch Pro`
- Bundle identifier: `com.sabastine.stylematchai`
- Marketing version: `1.6`
- Build number: `15`

These recorded values are historical checkpoint evidence only. Re-run or otherwise revalidate every required gate against the unchanged commit and clean working tree before declaring readiness.
