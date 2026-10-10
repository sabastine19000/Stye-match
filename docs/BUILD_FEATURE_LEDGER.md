# StyleMatch Pro Build and Functionality Ledger

**Status:** Governing build-scope record.
**Established:** 2026-08-13.
**Canonical location:** `docs/BUILD_FEATURE_LEDGER.md` on the highest active integration lane.
**Relationship to `PROJECT_STATE.md`:** `PROJECT_STATE.md` remains the append-only architecture and decision ledger. This file is its build-by-build operational index; a task is incomplete until both records are updated.

## Operating rules

1. Every task that changes, gates, removes, or accepts a material StyleMatch feature appends an entry here and a dated decision in `PROJECT_STATE.md`.
2. A build record separates **committed source**, **protected dirty source**, **runtime evidence**, **physical evidence**, and **unverified claims**. A dirty diff never becomes accepted merely because it exists.
3. No feature is assumed to propagate by build number. Each material feature must state its forward-propagation status.
4. No build role changes without explicit owner approval. Use `BUILD_ROLE_CHANGE_REQUESTED = YES` in the task record before changing a role.
5. Release-critical artifacts may not live only in `/private/tmp`, stdout, a task transcript, or a disposable worktree. Store or recover them under a durable project path and record a SHA-256 here. If recovery is not possible, record `UNVERIFIED` rather than reconstructing a claim.
6. A bounded accepted diff should be a dedicated commit. If a commit is not authorized, record its files and SHA-256 here as `ACCEPTED_UNCOMMITTED_WORK`.

## Status vocabulary

`ABSENT` · `FOUNDATION` · `PARTIAL` · `IMPLEMENTED` · `GATED` · `DISABLED_FOR_RELEASE` · `SOURCE_PASS` · `RUNTIME_PASS` · `PHYSICAL_PASS` · `BLOCKED` · `UNVERIFIED`.

## Current build registry

| Build | Current lane / source identity | Intended role | Current evidence classification |
|---|---|---|---|
| 18035 | `feature/build-18035-ai-memory-screen-context` at `d18d5cbb39773c28953b99642da52bdfbdaedbc2`; reviewed 18035 source/artifact lineage is separately represented by `170a873930a77e2efebd2f766198ecbdf1eadf73` | Previously reviewed 1.8 baseline | Historical scope only; exact reviewed artifact provenance beyond retained archive evidence is `UNVERIFIED` in this ledger. |
| 18036 | `feature/build-18036-collapsible-ask-stylist` at `170a873930a77e2efebd2f766198ecbdf1eadf73`; protected dirty work present | Narrow App Review replacement candidate | WeatherKit remediation/backport authority is `PARTIAL` until a durable canonical patch/commit and full physical evidence are reconciled. |
| 18037 | `feature/build-18037-weather-styling-premium` at `cb7db585f495078315d4a011b335b180c720ed7c`; protected dirty work present | Wide-release Weather lane; Cloud Sync inactive | Weather source is `SOURCE_PASS` by retained source history; customer Cloud Sync is `DISABLED_FOR_RELEASE`. |
| 18038 | `feature/build-18038-style-friends-foundation` at `da4b4c2e069cb26c9d422a3f84bf295f164b8916`; protected dirty work present | Style Friends / Cloud Sync V2 development lane | Style Friends backend acceptance and isolated staging evidence are retained in task authority; current source identity must be re-audited after any UI integration. |
| 18039 | `feature/build-18039-style-friends-premium-dm` at `97195c52aec1755345e85f1ff8e139cb4bc5bbbf`; protected dirty work present | Premium DM, Support AI, later-build beta lane | Source has committed DM/Support work; full iOS compilation is currently `BLOCKED` by a separate ProfileView type-check failure. |

## Feature matrix

The matrix is intentionally conservative. `UNVERIFIED` means no retained source, commit, test, artifact, or bounded task evidence was reconciled in this audit.

| Product area | 18035 | 18036 | 18037 | 18038 | 18039 | Provenance / propagation rule |
|---|---|---|---|---|---|---|
| WeatherKit attribution / Legal authority | FOUNDATION | PARTIAL | SOURCE_PASS | UNVERIFIED | UNVERIFIED | Shared foundation is identified around `27f04e6` / patch `747866…e853`, but retained canonical patch file is missing; later lanes require semantic audit. |
| Weather Styling | FOUNDATION | PARTIAL | SOURCE_PASS | UNVERIFIED | IMPLEMENTED | 18037 redesign authority: `45d128b`; never infer 10-Day or full Hourly from 18036 alone. |
| Full Hourly Forecast | ABSENT | PARTIAL | IMPLEMENTED | UNVERIFIED | IMPLEMENTED | Introduced in 18037 redesign (`45d128b`); 18036 backport evidence is not durable enough to call accepted. |
| 10-Day Forecast | ABSENT | PARTIAL | IMPLEMENTED | UNVERIFIED | IMPLEMENTED | Introduced in 18037 redesign (`45d128b`); 18038/18039 require separate layout/attribution verification. |
| Home weather routing | UNVERIFIED | PARTIAL | IMPLEMENTED | UNVERIFIED | IMPLEMENTED | 18037 Weather scope source authority; later builds must preserve Weather-to-Stylist separation. |
| AI Stylist / AI Memory | IMPLEMENTED | IMPLEMENTED | IMPLEMENTED | IMPLEMENTED | IMPLEMENTED | AI Memory first committed in 18035 lane (`d18d5cb`); only explicitly saved memory is Cloud Sync-eligible. |
| Closet / saved scans / Shopping | IMPLEMENTED | IMPLEMENTED | IMPLEMENTED | IMPLEMENTED | IMPLEMENTED | Existing domain authorities; no future lane may reinterpret scores or ownership. |
| Shop AI / Fashion Intelligence | ABSENT | ABSENT | UNVERIFIED | UNVERIFIED | FOUNDATION | 18039 Fashion Intelligence foundation commit `36a6ce6`; must not leak backward. |
| Profile / premium Profile visuals | IMPLEMENTED | IMPLEMENTED | PARTIAL | PARTIAL | PARTIAL | Current premium Profile changes are protected dirty work in 18037–18039, not accepted commits. 18039 is currently compiler-blocked in `ProfileView.swift`. |
| Style Friends profile, discovery, requests | ABSENT | ABSENT | ABSENT | IMPLEMENTED | IMPLEMENTED | 18038 migrations 0004–0014 and client source are authority. Do not backport. |
| Likes/comments/replies / UGC moderation | ABSENT | ABSENT | ABSENT | IMPLEMENTED | IMPLEMENTED | 18038 commits `fcc8aeb`, `1d76c0b`; migration 0015 reactions/replies and 0016 UGC moderation. |
| Style Friends DM / chat UI | ABSENT | ABSENT | ABSENT | ABSENT | IMPLEMENTED / BLOCKED | 18039 only; committed runtime/client foundation includes `eca66db`, `f8d4c28`; current compile repairs are uncommitted. Must not leak to 18038. |
| AI Customer Service / Support AI | ABSENT | ABSENT | ABSENT | ABSENT | IMPLEMENTED / RUNTIME_UNVERIFIED | 18039 commits `cc1ccdc`, `0096093`, `97195c5`; provider/live acceptance remains a separate gate. |
| CloudKit / iCloud sync | UNVERIFIED | FOUNDATION | DISABLED_FOR_RELEASE | FOUNDATION / GATED | FOUNDATION / GATED | 18037 Release customer sync stays disabled. 18038 V2 local authority exists; customer activation, full transport, two-device, signing, and privacy gates remain blocked. |
| Notifications / APNs | UNVERIFIED | UNVERIFIED | UNVERIFIED | BLOCKED | GATED | 18038 historical profile lacks `aps-environment`; no inference to later signing. |
| Privacy / consent | IMPLEMENTED | IMPLEMENTED | IMPLEMENTED | PARTIAL | PARTIAL | 18036 OpenAI processing disclosure at `170a873`; Cloud Sync and future V3 consent cannot be promoted without separate release/privacy evidence. |
| V3 AI-processing consent | ABSENT | ABSENT | ABSENT | ABSENT | UNVERIFIED | Explicitly barred from backward leakage until separately approved. |
| Account deletion | UNVERIFIED | UNVERIFIED | PARTIAL | IMPLEMENTED / RUNTIME_UNVERIFIED | UNVERIFIED | 18038 account deletion policy/source record exists; remote execution acceptance still separate. |
| Share links / cards | FOUNDATION | FOUNDATION | UNVERIFIED | IMPLEMENTED | IMPLEMENTED | Existing share authority must preserve bounded, opaque references. |

## Build records and dependency boundaries

### Build 18035

- **Committed source lane:** `feature/build-18035-ai-memory-screen-context`, `d18d5cbb39773c28953b99642da52bdfbdaedbc2`; project build settings in this lane currently show 1.8 / 18034, so this worktree is not itself proof of the reviewed 18035 binary.
- **Role:** historical reviewed baseline; not an active propagation target.
- **Material committed source:** user-controlled AI Memory (`d18d5cb`), structured screen context (`51a143b`), saved scan/image lineage inherited from earlier commits.
- **Signing / App Review:** an accepted 18035 App Store archive/profile is described in task evidence, but full archive path/hash is not retained in this repository ledger: `UNVERIFIED` pending durable archive record.
- **Do not backport from later builds:** Weather full Hourly/10-Day, Style Friends, DM, Support AI, V3 consent, activated Cloud Sync.

### Build 18036

- **Lane:** `feature/build-18036-collapsible-ask-stylist`, `170a873930a77e2efebd2f766198ecbdf1eadf73`; MARKETING_VERSION 1.8, CURRENT_PROJECT_VERSION 18036.
- **Role:** owner-authorized narrow App Review replacement candidate; role must not change without explicit authorization.
- **Committed source:** OpenAI processing disclosure `170a873`; existing profile, AI, Closet, scan, and Shopping foundations inherited.
- **Protected uncommitted work:** `StyleMatchAI.xcodeproj/project.pbxproj`, `ContentView.swift`, `StylistOverlaySessionCoordinator.swift`, `WeatherKitAuthority.swift`, `AIMemoryManagerTests.swift`, `StyleMatchProPhase2Tests.swift`.
- **Weather authority:** WeatherKit source foundation was reconstructed in temporary worktrees at `27f04e6`; reported patch SHA is `747866921a1879d057a1d8841df52c031d4d395ab84e83738b1289473205e853`, but the temporary patch is no longer present at the recorded `/private/tmp` path. Classification: `TEMPORARY_AUTHORITY_AT_RISK` / `UNVERIFIED` until a durable patch/commit is recovered or recreated deterministically.
- **App Review/signing/physical:** `UNVERIFIED` in this ledger; never infer from a same-number local install.
- **Propagation:** shared Weather foundation requires semantic integration into later builds; full Hourly/10-Day are later-surface work, not automatic 18036 scope.

### Build 18037

- **Lane:** `feature/build-18037-weather-styling-premium`, `cb7db585f495078315d4a011b335b180c720ed7c`; MARKETING_VERSION 1.8, CURRENT_PROJECT_VERSION 18037.
- **Role:** wide-release Weather lane. `BUILD_18037_RELEASE_CLOUD_SYNC = DISABLED`.
- **Committed source:** cross-device sync lifecycle checkpoint `2cb06cc`; premium Weather redesign `45d128b`; Weather Styling Stylist route `cb7db58`.
- **Protected uncommitted work:** current status lists configuration, WeatherKit, UI, scan/share, test, and project-state changes, plus two untracked scan-comparison files. They require an individually bounded diff before acceptance.
- **Cloud Sync:** Release remains fail-closed/inactive. No customer outbound/inbound sync, no enabled-looking control, and no CloudKit signing work may be inferred from source foundations.
- **Do not leak backward:** full Hourly/10-Day behavior is not proof of 18036 scope; CloudKit activation must not appear in 18037 wide release.

### Build 18038

- **Lane:** `feature/build-18038-style-friends-foundation`, `da4b4c2e069cb26c9d422a3f84bf295f164b8916`; MARKETING_VERSION 1.8, CURRENT_PROJECT_VERSION 18038.
- **Role:** Style Friends and Cloud Sync V2 completion lane; no DM, Support AI, V3 consent, or social-image runtime authority.
- **Committed source:** Style Friends reactions/replies (`fcc8aeb`), UGC source/Worker hardening, Cloud Sync V2 source authorities, account deletion policy, navigation/bio polish.
- **Migration dependency:** isolated account migration manifest contains exactly 16 files (`0001`–`0016`) in `migrations/accounts`; migration `0016_style_friend_ugc_moderation_operator.sql` SHA-256 is `ad20a2ad32a73a24e5d683bae3b37f79bda35be5d1bce095f5d870ecc689377c`.
- **Backend acceptance:** previously accepted Style Friends isolated-staging/security authority is preserved by scope, but its task artifacts were not found at the recorded `/private/tmp` paths during this audit. Do not use a missing temporary artifact as fresh proof; record runtime evidence as `UNVERIFIED` until a durable evidence bundle is restored.
- **Cloud Sync:** V2 authority is source/test foundation only. Customer activation is false; Style Friends data is excluded from private CloudKit sync.
- **Protected uncommitted work:** project, AccountService, CrossDeviceSync, Profile, Style Friends, test, docs, and new transport/test/script paths shown in current status.
- **Do not leak backward:** DM, Support AI, V3 consent, social-image runtime; do not rerun the full Style Friends matrix for unrelated Weather/Profile-only source changes.

### Build 18039

- **Lane:** `feature/build-18039-style-friends-premium-dm`, `97195c52aec1755345e85f1ff8e139cb4bc5bbbf`; MARKETING_VERSION 1.8, CURRENT_PROJECT_VERSION 18039.
- **Role:** later-build premium DM / Support AI / AI Customer Service beta lane; not a backward propagation source for 18036–18038 capabilities.
- **Committed source:** direct-message foundation `eca66db`; Apple-compliant DM/APNs source `d6c148e`; staging chat runtime `f8d4c28`; Style Friends hardening and typed social image client (`1dcb644`, `7df68ef`); AI Customer Service beta (`cc1ccdc`, `0096093`, `97195c5`).
- **Protected uncommitted work:** `ProfileView.swift`, `StyleFriendsChatUI.swift`, `StyleFriendsView.swift`, `StyleMatchSupportCenter.swift`, `StyleFriendsFoundationTests.swift`.
- **Current compile boundary:** `ProfileView.swift`, `StyleFriendsChatUI.swift`, and `StyleFriendsView.swift` compile after bounded compiler-only repairs; the full unsigned iOS build is historically recorded PASS. This is source/build evidence only, not installation authority.
- **2026-08-13 pre-install gate:** the configured staging URL answered HTTP 200 but identified itself as `build-18038-style-friends-staging`, not the required 18039 DM Worker. No synthetic DM fixture or provider request was made. DM and Support customer-facing runtime authority therefore remain BLOCKED. The iPhone 17 Pro Max target was independently connected, paired, unlocked since boot, Developer Mode enabled, and DDI-ready; terminal signing inspection still found zero usable code-signing identities and Xcode profile-resolution errors. Installation remains unauthorized.
- **2026-08-13 blocker-closure staging authority:** dedicated Worker `stylematch-18039-friends-dm-staging` and D1 `06618deb-8114-4c9b-8006-68f4b58350af` were created without altering 18038 and migrated through `0025_account_ai_processing_consents.sql`. Health returns `build-18039-style-friends-dm-staging`. `0016_style_friend_direct_messages.sql` is content-distinct from the 18038 UGC migration. The dedicated Worker has no secrets, leaving DM safety/send and Support provider paths fail-closed; no synthetic fixtures or live-provider calls were run. The Support fixture was updated to test current account-scoped AI consent; local Worker suite passed 282/282. Device signing remains blocked by terminal identity/profile resolution.
- **2026-08-13 owner-provisioned staging credentials:** the owner bound existing dedicated secrets `OPENAI_MODERATION_API_KEY` and `SUPPORT_OPENAI_API_KEY`, and a fresh staging-only `SHARE_TOKEN_PEPPER` was generated directly into, only `stylematch-18039-friends-dm-staging`, after independently re-verifying its runtime identity and D1 `06618deb-8114-4c9b-8006-68f4b58350af`; no secret value, prefix, hash, or length is retained. The next requested moderation activation is **BLOCKED**: the only checked-in OpenAI category mapping remains explicitly marked as a draft requiring policy/data-processing approval, so it was not provisioned as an approved staging authority. No provider request, synthetic DM fixture, Support request, or Support-flag change was performed after credentials were added. Production Support remains disabled. Device signing remains a separate blocked gate.
- **2026-08-13 dedicated DM/Support runtime acceptance:** owner-approved policy `style-friends-dm-safety-v1` maps every supported `omni-moderation-latest` text category to non-punitive `BLOCK_SEND` (`rejectedObjectionable`); no automatic account action or operator-review claim is made. A dedicated operator-only harness at `scripts/build18039-dm-acceptance-harness.mjs`, tested by `test/build18039-dm-acceptance-harness-tests.mjs`, requires the exact 18039 config, Worker identity, D1 ID, and random run ID. It creates and removes only exact-run records, restores DM/Support flags in `finally`, and forbids broad deletion. Live dedicated-staging evidence: moderation authenticated; benign A/B DM, policy block, reply, ordering, block denial, account isolation, and client-response raw-key audit passed; synthetic cleanup and FK check passed. Separate Support synthetic run: absent consent returned `403 aiConsentRequired`; current account-scoped consent reached the provider and returned valid structured responses to the bounded Support questions; cleanup/FK check passed and staging Support returned to 0. Shared 18038 health remains `build-18038-style-friends-staging` with zero dedicated-run accounts. Production Support remains disabled. Terminal device-signing resolution remains blocked.
- **2026-08-13 local signing recovery:** the interactive Xcode account and Keychain Access both show current Apple Development certificates for team `ZV4P3Z2QLA`; the current certificate (expires 2027-07-30) has a nested matching private key in the login keychain and is valid. The terminal user search list/default keychain is the same login keychain and now enumerates eight valid code-signing identities, including Apple Development. The owner iPhone 17 Pro Max is included in local profile `StyleMatch Pro APNs Development 18039 v2` (`0ca6b024-cbba-41ba-a926-bb7f2698eaaa`, expires 2027-08-12, team `ZV4P3Z2QLA`, `aps-environment=development`). A signed Debug device-build preflight selected Xcode's automatic `iOS Team Provisioning Profile: com.sabastine.stylematchai` and failed before compilation because that selected profile lacks Push Notifications / `aps-environment`. The local 18039 APNs profile has no CloudKit entitlement, while the target requires CloudKit as well as Push. No certificate, keychain, profile, project setting, Developer Portal resource, device app, or installation was changed. **Device signing remains BLOCKED only on an entitlement-compatible development profile that includes the target device, Push, and CloudKit.**
- **2026-08-13 historical 18039 signing reconciliation:** that earlier CloudKit conclusion is superseded by a complete `security cms` entitlement decode: local profile `StyleMatch Pro APNs Development 18039 v2` (`0ca6b024-cbba-41ba-a926-bb7f2698eaaa`, SHA-256 `95f2bd2e8d7ce27726570a46785d5add637bfc78f5bdca3f3aab06c7b90d6321`) includes the connected iPhone, development Push, `iCloud.com.sabastine.stylematchai`, CloudKit service, Sign in with Apple, Associated Domains, and WeatherKit. Shell history retains yesterday's successful manual build/install sequence from this lane: `CODE_SIGN_STYLE=Manual`, Apple Development identity `75B6694F0E1F34ABD09802F4726D5DC23A8BF95A`, and `PROVISIONING_PROFILE=0ca6b024-cbba-41ba-a926-bb7f2698eaaa`, followed by `devicectl` install to the owner iPhone UDID. Xcode Devices currently confirms installed `StyleMatch Pro` build `18039`. The temporary signed artifact directory is absent, so its executable hash and embedded-profile bytes cannot be recomputed. Source signing settings from historical commit `f8d4c28` through current product baseline retain automatic Debug signing; the effective delta is terminal manual UUID pinning versus current automatic selection of a non-Push team profile. **Profile compatibility is historically proven; the remaining issue is local automatic-selection/index regression, not a missing portal capability or new profile requirement.**
- **2026-08-13 current-source owner-beta endpoint guard:** before rebuilding the current 18039 dirty source, Debug configuration resolved `STYLEMATCH_API_BASE_URL` and APNs Worker URL to `https://stylematch-friends-staging.sabastine-7000.workers.dev`. Its live `/v1/health` response is `build-18038-style-friends-staging`, not the required dedicated 18039 runtime. The dedicated Worker is instead `https://stylematch-18039-friends-dm-staging.sabastine-7000.workers.dev` and returns `build-18039-style-friends-dm-staging`. No current-source 18039 artifact was built or installed because silently overriding a customer-runtime endpoint at build time is not release authority. The historical 18039 app remains installed. **Owner-beta installation is blocked until the intended Debug endpoint configuration is explicitly reconciled to the dedicated 18039 runtime.**
- **Do not leak backward:** DM, Support AI, customer-service capability, V3 consent, social-image runtime, and any later CloudKit activation.

## Forward-propagation and backward-leakage register

| Feature | To 18036 | To 18037 | To 18038 | To 18039 | Constraint |
|---|---|---|---|---|---|
| Shared WeatherKit attribution / Legal / hourly foundation | ALREADY_PRESENT / RECONCILE | ALREADY_PRESENT / RECONCILE | SEMANTIC_INTEGRATION_REQUIRED | SEMANTIC_INTEGRATION_REQUIRED | Do not assume physical acceptance across lanes. |
| Full Hourly + 10-Day Weather experience | BLOCKED pending bounded 18036 authority | ALREADY_PRESENT | SEMANTIC_INTEGRATION_REQUIRED | SEMANTIC_INTEGRATION_REQUIRED | Later-surface layout/attribution must be independently tested. |
| Premium Profile visual language | YES if owner authorizes | YES / protected dirty | YES / protected dirty | YES / protected dirty | Preserve truthful Cloud Sync state; no backend change. |
| Style Friends foundation / UGC | NO | NO | ALREADY_PRESENT | ALREADY_PRESENT | 18038 authority; no backward social runtime. |
| Style Friends DM / Support AI / AI Customer Service | NO | NO | NO | ALREADY_PRESENT | Strict 18039-only capability boundary. |
| Customer Cloud Sync activation | NO | NO; DISABLED_FOR_RELEASE | BLOCKED | BLOCKED | Needs complete transport, two-device, signing, privacy, deletion evidence. |
| V3 AI-processing consent | NO | NO | NO | BLOCKED / UNVERIFIED | Requires independent owner approval and privacy gate. |

## Durable artifact register

| Artifact | Lane | Recorded identity | Status / recovery action |
|---|---|---|---|
| 18035 reviewed App Store archive | 18035 | `StyleMatchPro-1.8-18035-AppStore-20260808.xcarchive`; version 1.8, build 18035, bundle `com.sabastine.stylematchai`, Apple Distribution signing | **EXTERNAL_DURABLE_EVIDENCE.** Located at `/Users/sabastineesisorigho/Library/Developer/Xcode/Archives/2026-08-08/StyleMatchPro-1.8-18035-AppStore-20260808.xcarchive`; not copied into Git. Archive-content hash was not recomputed in this documentation-only audit. |
| 18036 WeatherKit canonical foundation patch | 18036 | Expected `/private/tmp/build-18036-weatherkit-canonical.patch`; historical SHA-256 `747866921a1879d057a1d8841df52c031d4d395ab84e83738b1289473205e853`; canonical integration commit `27f04e6282e3f14b44cb606dfca010d3a89539ba` | **Temporary patch bytes missing; SHA is historical-only, not recomputed from current bytes.** The named commit remains reachable in Git and can be inspected/reconstructed from source. A reconstruction is a new durable evidence artifact unless it byte-matches the historical SHA; it does not silently restore the missing original patch bytes. |
| 18036 later Weather backport patch | 18036 | Expected historical bounded backport patch; SHA-256 `726496b264df13d98d83757846865ed5aef996d6e435a722e01d2479636fddee` | **Temporary patch bytes missing; SHA is historical-only.** Source/commit ancestry must be independently reconciled before deterministic recreation. Any recreated patch is a new authority until its bytes match this hash. |
| 18038 final security-matrix JSON | 18038 | Expected `/private/tmp/build-18038-security-matrix-results-final.json`; historical SHA-256 `34bf73e022dd0478c2c598c7da87ee3ae63737299aa102698ca567cc8aedffcc` | **Original JSON bytes missing from durable project storage; SHA is historical-only.** `BUILD_18038_SECURITY_MATRIX_ACCEPTANCE = PASS` and `BUILD_18038_STAGING_LIFECYCLE_ACCEPTANCE = PASS` remain historically accepted classifications. Missing JSON prevents fresh byte-level verification, not retroactive downgrading of that accepted result. A recreated artifact is new evidence unless it byte-matches the historical hash. |
| 18038 migration 0016 | 18038 Worker | `migrations/accounts/0016_style_friend_ugc_moderation_operator.sql`; SHA-256 `ad20a2ad32a73a24e5d683bae3b37f79bda35be5d1bce095f5d870ecc689377c` | Durable source file present. |
| 18037 Cloud Sync foundation source bundle | 18037 | Expected `build-18037-cloudsync-foundation-source-20260813.zip`; historical SHA-256 `97ccf75bc797efd18217b04bc9020e4c60bdc3bedc4e23eb32971af9f80fa273` | **ZIP bytes currently missing; SHA is historical-only.** Related Cloud Sync source remains present in the 18037 worktree, but that does not prove byte identity of the missing ZIP. A rebuilt ZIP is a new bundle unless it reproduces the historical hash. |

## Mandatory task-close template

Every future StyleMatch task appends a dated entry here and reports:

```text
BUILD_IDENTITY =
BUILD_ROLE =
FEATURES_ADDED =
FEATURES_CHANGED =
FEATURES_DISABLED =
FEATURES_REMOVED =
FILES_CHANGED =
COMMIT_CREATED =
COMMIT_ID =
BOUNDED_DIFF_SHA256 =
TESTS =
PHYSICAL_ACCEPTANCE =
PRIVACY_DELTA =
SIGNING_DELTA =
PROPAGATION_REQUIRED =
BUILD_FEATURE_LEDGER_UPDATED = PASS
PROJECT_STATE_UPDATED = PASS
EXACT_BLOCKERS =
```

## 2026-08-13 reconciliation entry

- **Audit method:** current worktree source/settings, Git history, retained `PROJECT_STATE.md` records, current migration files, and retained task identities only. No source, backend, signing, device, or deployment action was performed.
- **Outcome:** this ledger provides the first cross-build scope map for 18035–18039. Earlier temporary artifacts are explicitly identified rather than silently promoted.
- **Accepted uncommitted work:** this ledger and the corresponding `PROJECT_STATE.md` pointer are documentation-only changes. They are not committed because no commit authorization was supplied.
- **Historical-identity clarification:** missing artifact names and hashes are retained as historical-only until bytes are recovered and recomputed. Existing Git commits and Xcode archives are recorded separately as recoverable or external durable evidence. A deterministic reconstruction may establish new evidence; it does not retroactively recreate an absent byte-identical artifact without a matching SHA-256.
- **Next durable action:** commit this ledger in a documentation-only bounded commit when authorized; then move each release-critical temporary authority into a durable evidence location or reproduce it deterministically.

## 2026-08-13 — Build 18039 Debug backend authority reconciliation

- **Build / role:** 18039 owner-beta Debug lane, `feature/build-18039-style-friends-premium-dm`, HEAD `2c6a998abf7aea4c32c3a6772c436b554da0daa8` before this protected-dirty configuration change.
- **Authority changed:** `Config/StyleMatchDebug.xcconfig` now compiles `https://stylematch-18039-friends-dm-staging.sabastine-7000.workers.dev` into both `STYLEMATCH_API_BASE_URL` and `STYLEMATCH_APNS_WORKER_URL`. `AppBackendConfiguration.approvedFriendsStagingAPIHost` allowlists that same dedicated host only in Debug. The former shared host `stylematch-friends-staging.sabastine-7000.workers.dev` is rejected by the Debug source contract.
- **Runtime proof:** read-only health checks report dedicated host `build-18039-style-friends-dm-staging` and former shared host `build-18038-style-friends-staging`. The 18038 worktree configuration was read-only inspected and not modified.
- **Release / leakage boundary:** `Config/StyleMatchRelease.xcconfig` remains unchanged, with Style Friends DM and Support disabled; no 18038 source, backend, D1, Worker, signing, profile, portal, or device state changed.
- **Regression coverage:** `StyleFriendsFoundationTests.testBuild18039DebugBackendAuthorityIsDedicatedAndReleaseRemainsUnchanged` asserts the Debug API/APNs endpoints, rejects the shared 18038 host, and preserves the Release-disabled settings. The current project scheme has no XCTest target/testable, so this source test is pending executable test-target infrastructure.
- **Build evidence:** unsigned generic iPhoneOS Debug build passed with `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`; emitted app `Info.plist` contains the dedicated API and APNs worker URLs. `git diff --check` passed.
- **Propagation:** `PROPAGATE_TO_18036 = NO`; `PROPAGATE_TO_18037 = NO`; `PROPAGATE_TO_18038 = NO`; `PROPAGATE_TO_18039 = ALREADY_PRESENT`. This is a dedicated 18039 owner-beta staging authority and must not leak backward.
- **Next gate:** reuse the already historically proven manual signing path only after this tracked configuration change is reviewed; physical installation remains separately unauthorized in this task.

## 2026-08-13 — Build 18039 manual-signing retry

- **Build / role:** 18039 owner-beta Debug lane, same protected-dirty source and dedicated endpoint authority.
- **Historical command reused:** the retained manual pattern explicitly set Apple Development identity `75B6694F0E1F34ABD09802F4726D5DC23A8BF95A`, `CODE_SIGN_STYLE=Manual`, profile specifier `0ca6b024-cbba-41ba-a926-bb7f2698eaaa`, `CODE_SIGNING_ALLOWED=YES`, and `CODE_SIGNING_REQUIRED=YES`.
- **Result:** compilation completed and embedded the requested profile, but the resulting `StyleMatchAI.app` has no `_CodeSignature`; `codesign --verify` reports `code object is not signed at all`. The produced executable SHA-256 is `e1cb7f76a3a3485c88b5e2870e5d0859a032e986da2424ec0f918acb68fd7864`, but it is not an installable owner-beta artifact.
- **No install:** CoreDevice enumeration also timed out before a device selection could be confirmed. No `devicectl install`, launch, backend mutation, source change, profile/certificate/Keychain/portal change, or 18038 action occurred.
- **Classification:** the historical manual path remains historical proof; current signing is **BLOCKED** by the local Xcode/profile-resolution session, which emits repeated `missing required UUID property` diagnostics for local profiles including the requested one. Do not use or install the unsigned output. The next task must repair/reconcile local profile parsing or signing-session behavior without creating a replacement profile.

## 2026-08-13 — Build 18039 CodeSign-phase diagnosis

- **Command comparison:** the current retry used the same effective signing contract as the retained successful command: `CODE_SIGN_STYLE=Manual`, team `ZV4P3Z2QLA`, Apple Development hash `75B6694F0E1F34ABD09802F4726D5DC23A8BF95A`, profile specifier `0ca6b024-cbba-41ba-a926-bb7f2698eaaa`, `CODE_SIGNING_ALLOWED=YES`, and `CODE_SIGNING_REQUIRED=YES`. There is no signing-argument drift.
- **Effective settings:** Debug/iPhoneOS settings resolve to Manual signing, `CODE_SIGNING_ALLOWED=YES`, `CODE_SIGNING_REQUIRED=YES`, the expected team, identity hash, and profile specifier. Code signing was not disabled by a project or command setting.
- **Build-activity evidence:** XCBuildData contains the generated `CodeSign` tasks for the app and debug dylibs, but the artifact has no `_CodeSignature` and no executable CodeSign result. Concurrent local diagnostics report the pinned profile as `missing required UUID property` and `security find-identity -v -p codesigning` currently returns `0 valid identities`.
- **Root cause:** `IDENTITY_RESOLUTION_FAILURE` in the current terminal/Xcode session, with local profile-index parsing also degraded. This is separate from CoreDevice transport and from historical profile compatibility. No repair was performed; no profile, certificate, Keychain, portal, source, backend, or device state changed.

## 2026-08-13 — Build 18039 current owner-beta signed install

- **Source / artifact:** protected-dirty `feature/build-18039-style-friends-premium-dm` at HEAD `2c6a998abf7aea4c32c3a6772c436b554da0daa8` built as version 1.8, build 18039, bundle `com.sabastine.stylematchai`. The owner-visible Terminal enumerated eight identities including Apple Development `75B6694F0E1F34ABD09802F4726D5DC23A8BF95A`; the existing profile decoded to `0ca6b024-cbba-41ba-a926-bb7f2698eaaa` and retained SHA-256 `95f2bd2e8d7ce27726570a46785d5add637bfc78f5bdca3f3aab06c7b90d6321`.
- **Signing / entitlement evidence:** Xcode compilation embedded the correct profile but again omitted its CodeSign output. The exact Xcode-generated entitlements and the same existing identity were used to sign the temporary owner-beta app directly; strict `codesign --verify` passed. Executable SHA-256: `a082ad37b25e9030c7eca0fe25d3bd4adceea6fd9beb584e57a350207155eb0d`. Signed authority includes development APS, `iCloud.com.sabastine.stylematchai` / CloudKit, Sign in with Apple, Associated Domains, and WeatherKit. The compiled Debug API endpoint is the dedicated `https://stylematch-18039-friends-dm-staging.sabastine-7000.workers.dev`.
- **Installation / launch:** `devicectl` resolved requested UDID `00008150-000C18E81AD8401C` to the wired, paired, Developer-Mode-enabled iPhone 17 Pro Max (CoreDevice alias `3BAD6F82-5382-5968-AB33-C43E585A573F`). The verified artifact was installed in place—no uninstall or container deletion—and post-install metadata reports StyleMatch Pro 1.8 (18039). `devicectl` launched the bundle successfully.
- **Physical acceptance:** rendered verification of premium Profile, Style Friends Conversations/chat UI, and AI Customer Service remains owner-device evidence pending; launch is not treated as a visual acceptance substitute. No source, backend, portal, profile, certificate, or 18036–18038 change occurred.

## 2026-08-13 — Build 18039 Apple Push troubleshooting chain

- **Target evidence:** `StyleMatchAI.entitlements` requests `aps-environment = $(APS_ENVIRONMENT)`; Debug resolves `APS_ENVIRONMENT = development`. The same target requests the active CloudKit container/service, Sign in with Apple, Associated Domains, and WeatherKit. `project.pbxproj` records iCloud in `SystemCapabilities` but has no separate Push metadata entry; this metadata omission does not remove the target entitlement and is recorded as a Xcode-project presentation inconsistency rather than evidence that the signed app lacks APS.
- **Profile / identity evidence:** the unchanged profile `0ca6b024-cbba-41ba-a926-bb7f2698eaaa` matches the application identifier and requested iPhone, has `aps-environment = development`, `iCloud.com.sabastine.stylematchai`, WeatherKit, and wildcard authorities for `com.apple.developer.icloud-services` and Associated Domains, plus Sign in with Apple. The Apple Development identity `75B6694F0E1F34ABD09802F4726D5DC23A8BF95A` is visible in the restored owner session.
- **Final-app evidence:** the current signed 18039 artifact strictly verifies and has development APS, `iCloud.com.sabastine.stylematchai` / `CloudKit`, `applinks:stylematchpro.com`, Sign in with Apple, and WeatherKit. The embedded profile is the same pinned UUID. The manual direct signature followed Xcode's failure to emit its CodeSign output; it did not change source, profile bytes, certificates, or portal state.
- **Registration-path evidence:** explicit user action calls notification authorization then `registerForRemoteNotifications()`. The app delegate handles both device-token delivery and registration failure without logging device metadata. No real APNs push was sent in this troubleshooting pass.
- **Classification:** `PUSH_SIGNING_CHAIN_PASS = YES`. `PORTAL_PUSH_CAPABILITY = NOT_VERIFIED` and `PORTAL_CLOUDKIT_CAPABILITY = NOT_VERIFIED` because the authenticated portal surface was not available for read-only inspection. Any capability-checkbox persistence issue remains a separate Apple-portal case `20000134542775`, not a local signed-build blocker.

## 2026-08-13 — Build 18039 physical Weather and Style Friends regression record

- **Failed physical evidence retained:** owner screenshots from the installed 1.8 (18039) showed Full Hourly including a stale prior hour (for example 10 PM when device time was 11:10), sun symbols through overnight Clear/Mostly Clear entries, clipping in the full 10-Day date and condition labels, and no visible Apple Weather attribution/Legal affordance on the full forecast sheets. This is **physical acceptance FAIL** and supersedes prior source-only Weather readiness assertions.
- **Root cause:** current 18039 had not semantically inherited the 18037 Weather presentation authority. It persisted a `prefix(7)` source sequence without current-hour filtering, rendered hourly symbols from condition text (which mapped Clear to sun), used fixed single-line full daily rows, and omitted the full-sheet attribution modifier. This is `NOT_PROPAGATED`, not a persistence-only explanation.
- **Bounded source repair:** `WeatherKitAuthority.swift`, `ContentView.swift`, and `StyleMatchProPhase2Tests.swift` now persist WeatherKit provider symbols, filter/sort hourly entries at the current-hour boundary at fetch and presentation, neutralize legacy symbol fallback, use a vertically adaptive full 10-Day row, and apply the existing provider-derived attribution/Legal authority to the panel and destination sheets. The unsigned iPhoneOS Debug build passes. New deterministic tests are source-present but cannot execute because the scheme's `TestAction` has no testable target.
- **Style Friends classification:** dedicated 18039 configuration deliberately sets `STYLE_FRIENDS_SOCIAL_IMAGES_RUNTIME_AUTHORITY = disabled`; both the Worker image route and the client hero state are explicitly unavailable. Therefore photo restoration is not authorized by an owner-profile data copy. The dedicated D1 is isolated and owner-profile migration requires an authenticated, owner-identity-bound reconciliation—no account data was read or copied in this pass.
- **Current install:** current Weather-fixed source was manually signed with the existing Apple Development identity and Xcode-generated entitlement file after Xcode again omitted its own CodeSign result. Strict verification passed; executable SHA-256 `80720130ca3b577c2b0cb48c702597e363db02d44c4f79213ec8e0de7c486c28`. It was installed in place on `00008150-000C18E81AD8401C` and launched; metadata reports 1.8 (18039). This is not visual acceptance. Owner must now exercise normal notification permission/registration and capture new Weather screenshots before any PASS classification.
- **Durable handoff artifact:** `/private/tmp/StyleMatch18039-weather-regression-evidence-20260813.zip`, SHA-256 `6a8ac9fe29e99a8f88afc315ddfb9e24e47d302f8f9639de22c317479a7918a8`, contains the bounded Weather source/test and ledger-state evidence. It is a new repair artifact, not replacement proof for any historical 18036 patch.

## 2026-08-13 — Build 18039 canonical owner-beta assembly reconciliation

- **Authority method:** physical screenshots remain the failed-runtime authority. The current worktree, its protected dirty diff, reachable commits, reflog-visible ancestry, surviving worktrees, and unreachable Git objects were inspected feature-by-feature. No reset, clean, stash, restore, broad database read, profile, certificate, Worker, D1, or portal mutation was performed.
- **Premium Profile → Account:** the current protected `StyleMatchAI/ProfileView.swift` contained a partial premium-card diff but no recoverable historical full-screen implementation in Git, reflog, dangling blobs, or another worktree. The owner-approved visual target was therefore semantically reconstructed in the existing Account surface: cream selected navigation treatment, elevated dark/cream account and Cloud Sync cards, a prominent unavailable pill/cloud mark, and the structured eligible-data card. The unavailable Cloud Sync contract remains authoritative: no green `On`, no enabled-looking control, and no contradictory attention state. This is source/build evidence only; it remains pending rendered device evidence.
- **Style Friends profile:** committed source authority is `6115a5b5f581f596e862abf671a53300297b05f1` (`redesign Style Friends profile and fix persistence`). Current source still calls authenticated `/v1/friends/profile/me`, persists the returned public projection, and renders display name, bio, and selected categories. A blank current profile is therefore `RUNTIME_DATA_ONLY` until an authenticated owner-bound comparison proves otherwise. The dedicated 18039 D1 must not receive a broad shared-D1 copy.
- **Social images:** committed iOS client authority is `7df68efd0c05cd1b6ce02e4ac0eeed6ace4dc742`, but it adds only a typed image route. The current iOS hero intentionally declares photos unavailable; the dedicated Worker `wrangler.18039.staging.toml` also sets `STYLE_FRIENDS_SOCIAL_IMAGES_RUNTIME_AUTHORITY = disabled` and `STYLE_FRIENDS_IMAGE_SAFETY_RUNTIME_AUTHORITY = disabled`. Photo absence is therefore a separate **disabled capability gate**, not a missing owner-data field. No source/runtime activation or data migration is authorized by this reconciliation.
- **Weather:** accepted bounded protected source authority remains `StyleMatchAI/WeatherKitAuthority.swift` and `StyleMatchAI/ContentView.swift`, semantically reconciling the 18037 WeatherKit presentation foundation (`27f04e6282e3f14b44cb606dfca010d3a89539ba`, later Weather UI lineage `45d128b`) into 18039. It filters the persisted and displayed hourly sequence at the current-hour boundary, preserves provider symbols without clear→sun guessing, uses vertical daily rows, and applies provider-derived attribution/Legal to both full forecast destinations. The exact pending physical conditions are unchanged: hourly alignment, night symbols, 10-Day layout, attribution, and Legal must be captured from the next signed artifact.
- **DM/chat and Support:** current source contains the accepted post-`f8d4c28a71caf03b50f77bcd1c91aabf32d81922` committed authority (`7ab64b0`, `97195c5`, and intervening 18039 commits) plus the protected compile/configuration changes. No DM, moderation, Support, consent, or endpoint source was removed in this reconciliation.
- **Build evidence:** unsigned generic iPhoneOS Debug build passed after the Profile reconciliation. The scheme still has no testable XCTest reference, so source tests cannot be classified as executed. `git diff --check` passed.
- **Canonical-install gate:** no new install was performed. A canonical signed artifact may be built only after the owner-authorized profile-data reconciliation and a separate decision on social-image runtime activation; its physical acceptance cannot be inferred from source/build evidence.
- **Durable handoff artifact:** `/private/tmp/StyleMatch18039-canonical-reconciliation-20260813.zip`, SHA-256 `d200c62c67a5c6e2c98270558d460368f12a415132b5fde81a8dab97a94496b0`, contains the reconciled Profile, Style Friends, Weather, and test-source evidence. It contains no credentials and is a new current-source evidence bundle, not a reconstruction of any missing historical artifact.
- **Propagation / leakage:** `PROPAGATE_TO_18036 = NO`; `PROPAGATE_TO_18037 = NO`; `PROPAGATE_TO_18038 = NO`; `PROPAGATE_TO_18039 = ALREADY_PRESENT / protected dirty`. No 18039 DM, Support, or social-image runtime capability may leak backward.

## 2026-08-13 — Build 18039 WeatherKit precipitation-now truthfulness repair

- **Failed physical authority:** the owner observed dry conditions in Fortson while the app displayed `Isolated Thunderstorms`, a 25% rain chance, and an animated wet/rain presentation. A forecast probability or thunderstorm-risk condition is not proof that precipitation is falling at the device location.
- **Root cause:** `WeatherSnapshot` did not retain `CurrentWeather.precipitationIntensity`. The umbrella/visual authority treated thunderstorm text as hazardous current precipitation; that produced rain particles, a current-thunderstorm alert classification, and `It’s raining now` wording despite no current precipitation measurement.
- **Bounded repair:** `WeatherSnapshot` now persists WeatherKit current precipitation intensity in km/h. Missing legacy intensity fails dry. Active precipitation alone permits `rainingNow`; a thunderstorm condition with zero/missing current intensity becomes `thunderstormRisk`, rendered as a static storm-risk cue without rain particles, continuous animation, or a current-rain claim. The current card now separately displays `Precipitation Now` and `Rain Chance (Next 6h)`. The Scan alert labels risk as `Nearby • Thunderstorm risk` rather than current rain. The known WeatherKit condition/symbol/forecast attribution contracts remain unchanged.
- **Stylist contract:** umbrella/styling guidance now says `Thunderstorms are possible nearby` for risk without active precipitation. A real active precipitation intensity still permits current-rain/drizzle language. Future hourly rain remains a timed forecast, not a current-weather assertion.
- **Tests:** deterministic XCTest source cases cover dry thunderstorm risk plus 25%, active rain, active drizzle, future rain only, stale/dry reset, risk animation disabled, and forecast/current separation. The scheme has no TestableReference, so test execution is `BLOCKED`; it was not fabricated. Unsigned iPhoneOS Debug build passes and `git diff --check` passes.
- **Physical gate:** a newly signed canonical artifact must prove `CURRENT_WEATHER_TRUTHFULNESS_PHYSICAL`, `RAIN_ANIMATION_TRUTHFULNESS_PHYSICAL`, `RAIN_CHANCE_PRESENTATION_PHYSICAL`, and `WEATHER_AI_WORDING_PHYSICAL`. No source/build result promotes those to PASS.
- **Durable handoff artifact:** `/private/tmp/StyleMatch18039-weather-precipitation-truth-20260813.zip`, SHA-256 `7750d00884e26a724c45196e79baea5562ed78ed13188f75d948c7e77f46f937`, contains only the bounded Weather source and deterministic test source. It contains no secrets and is new current-source evidence, not a recreation of historical bytes.

## 2026-08-13 — Build 18039 premium Weather Styling visual upgrade

- **Build / role:** 18039 owner-beta Weather Styling presentation, protected-dirty `feature/build-18039-style-friends-premium-dm` at HEAD `2c6a998abf7aea4c32c3a6772c436b554da0daa8`.
- **Visual authority:** owner-supplied mockup is design direction only. It supplies the premium dark atmosphere, layered glass, purple accent restraint, visual hierarchy, and forecast-card direction. It is not a weather-data authority; no mockup temperature, location, condition, time, precipitation, or forecast value was copied.
- **Bounded implementation:** `WeatherPremiumAtmosphere` uses the existing WeatherKit-derived visual state for a dark, condition-aware atmosphere. Current Weather became a glass hero with a responsive `ViewThatFits` layout; Overview and Details separately state `Precipitation Now` and `Rain Chance (Next 6h)`. Hourly uses deeper material cards and retained provider symbols/current-future authority. 10-Day uses a derived, actual-forecast temperature-range bar and retains adaptive full-sheet rows.
- **Animation / truthfulness:** active rain, drizzle, and active thunderstorm now receive a two-depth Canvas layer with reduced background density and foreground definition. `thunderstormRisk` remains static. No probability, future hourly condition, or risk text activates observed-rain particles. All motion continues to respect `accessibilityReduceMotion`; no timer, backend, WeatherKit fetch, or product-data contract was added.
- **Compliance / protected behavior:** WeatherKit current/future filtering, provider symbols and neutral legacy fallback, 10-Day adaptation, full Hourly and 10-Day Apple Weather attribution plus provider Legal destination, Home routing, and current-rain versus forecast-risk truthfulness remain present. No DM, Support, CloudKit, signing, profile, backend, migration, or 18036–18038 source changed.
- **Validation:** unsigned generic iPhoneOS Debug build passed; `git diff --check` passed. Source regression assertions cover premium atmosphere, two-depth observed precipitation, the existing Reduce Motion policy gate, current/forecast separation, derived daily range bars, and attribution. The shared scheme declares a `TestAction` but no `TestableReference`, so executable XCTest remains blocked and is not reported as passed.
- **Physical state:** **PENDING.** No signing, installation, or screenshot/video acceptance occurred. Required later evidence: iPhone clear/cloudy and naturally observed-rain state or approved deterministic preview, full Hourly, full 10-Day, attribution/Legal visibility, and Reduce Motion behavior.
- **Propagation / leakage:** `PROPAGATE_TO_18036 = NO`; `PROPAGATE_TO_18037 = NO`; `PROPAGATE_TO_18038 = NO`; `PROPAGATE_TO_18039 = ALREADY_PRESENT / protected dirty`. This is a bounded 18039 visual layer and does not activate later CloudKit or social-image capability.
- **Durable handoff artifact:** `/private/tmp/StyleMatch18039-premium-weather-visual-20260813.zip`, SHA-256 `070578f6edf4f2e6e1d627c86ad89e826a5e4932912c4764d73cab0048100bbc`. It contains bounded Weather source/test authority only and no secrets.

## 2026-08-13 — Build 18039 Weather-truthfulness physical-install evidence

- **Source / artifact:** protected-dirty `feature/build-18039-style-friends-premium-dm` at HEAD `2c6a998abf7aea4c32c3a6772c436b554da0daa8` was built as version 1.8, build 18039, bundle `com.sabastine.stylematchai`, using manual signing with Apple Development identity `75B6694F0E1F34ABD09802F4726D5DC23A8BF95A` and existing profile `0ca6b024-cbba-41ba-a926-bb7f2698eaaa`.
- **Verification:** Xcode emitted the signed app; `_CodeSignature` exists and strict `codesign --verify` passed. The embedded profile UUID matches the pinned profile. Signed entitlements include development APS, `iCloud.com.sabastine.stylematchai` / CloudKit, Sign in with Apple, Associated Domains, and WeatherKit. Executable SHA-256: `0268a1cc43188490de9f7c98d85c2ba425ecfbab03b08ae977cdb8f56d4a0364`.
- **Backend authority:** compiled `Info.plist` contains `https://stylematch-18039-friends-dm-staging.sabastine-7000.workers.dev` for both API and APNs Worker URLs.
- **Install / launch:** verified app was installed in place on the authorized iPhone UDID `00008150-000C18E81AD8401C`, without uninstall or app-container deletion; `devicectl` then launched `com.sabastine.stylematchai` successfully.
- **Physical gate:** Weather truthfulness, animation, chance wording, AI wording, hourly alignment, night symbols, 10-Day layout, attribution, and Legal remain **PENDING OWNER DEVICE EVIDENCE** after a manual Weather refresh. Installation and launch do not substitute for rendered acceptance.

## 2026-08-13 — Build 18039 premium-Weather signing retry

- **Result:** compilation from the exact protected 18039 worktree completed and embedded profile `0ca6b024-cbba-41ba-a926-bb7f2698eaaa`; version and build remained 1.8 (18039) and the compiled API/APNs URLs remained dedicated 18039 staging.
- **Blocker:** Xcode again omitted the executable signature. The result has no valid CodeDirectory; `_CodeSignature` resources alone are insufficient and `codesign --verify --deep --strict` reports the app/executable as unsigned. The retained manual direct-sign command, including Xcode's generated `.xcent`, `--timestamp=none`, and `--generate-entitlement-der`, did not produce a valid executable signature in this session.
- **Safety outcome:** the unsigned artifact (executable SHA-256 `e1cb7f76a3a3485c88b5e2870e5d0859a032e986da2424ec0f918acb68fd7864`) was not installed. No profile, certificate, keychain, portal, source, backend, device-app, or 18036–18038 state was changed. Physical premium-Weather acceptance remains pending a valid signed artifact.

## 2026-08-13 — Build 18039 Keychain-restored premium-Weather install

- **Signing recovery:** owner-visible Keychain unlock restored `security find-identity` to eight valid identities, including Apple Development `75B6694F0E1F34ABD09802F4726D5DC23A8BF95A`. Xcode still omitted the executable signature, but signing the transient build bundle and nested debug code with the existing identity, Xcode-generated `.xcent`, `--timestamp=none`, and `--generate-entitlement-der` produced a strict-verifying app. No certificate, profile, portal, source, backend, or cross-build change was made.
- **Artifact:** version 1.8, build 18039, bundle `com.sabastine.stylematchai`; embedded profile `0ca6b024-cbba-41ba-a926-bb7f2698eaaa`; executable SHA-256 `c5f7cb9453e80acc8aa1b65f6bd8c828335745548c59e6f17e3af6222d98ffb7`. Signed entitlements: development APS, `iCloud.com.sabastine.stylematchai` / CloudKit, Sign in with Apple, Associated Domains, and WeatherKit. Compiled API/APNs URLs remain the dedicated 18039 Worker host.
- **Install / launch:** installed in place to authorized iPhone `00008150-000C18E81AD8401C`, preserving the app container, then launched successfully. Device metadata reports StyleMatch Pro 1.8 (18039).
- **Physical gate:** premium Weather background/hero/Hourly/10-Day/rain animation, dry-rain truthfulness, hourly/night/layout, attribution/Legal, performance, and Reduce Motion remain **PENDING OWNER DEVICE EVIDENCE** after Weather refresh. Installation and launch do not establish rendered acceptance.

## 2026-08-13 — Build 18039 Style Friends Profile premium presentation

- **Visual authority:** owner-provided reference is layout direction only. No sample image, display name, biography, or style identity has been added to source, fixtures, or runtime state.
- **Bounded client change:** `StyleMatchAI/StyleFriendsView.swift` now uses a compact dark/cream profile hero, restrained avatar/camera treatment, live profile preview, and selected style-identity tiles. Every visible name, bio, initials, and selected style value remains derived from `SocialProfileDraft`, which is populated only from the authenticated profile projection or current owner edits. The avatar control remains clearly unavailable; no fake image or claim of activation is shown.
- **Save authority:** client `saveSocialProfile` issues authenticated `PUT /v1/friends/profile/me`; Worker handler `friendProfiles.ts` session-authenticates, performs an account-key-bound `INSERT ... ON CONFLICT ... DO UPDATE`, and returns the canonical projection. Display name, bio, categories, discoverability, and read-your-write behavior are source-present. The dedicated D1's empty owner row explains the physical blank state; the owner must save their own values in the existing form rather than copy shared-D1 data.
- **Social-image boundary:** profile-avatar retrieval has owner-or-active-friend authorization in `friendSocialImages.ts`, but activation is blocked: dedicated 18039 config has both image authorities disabled and no R2/Images binding; no owner-avatar upload route exists; the admission helper's generated reference grammar is incompatible with the profile validator; and dedicated image moderation configuration is absent. No flag was changed, no storage was shared with 18038, and photos remain unavailable.
- **Validation:** unsigned generic iPhoneOS Debug build passed with the updated profile view; `git diff --check` passed. The project scheme still lacks a TestableReference, so XCTest execution remains blocked. Existing focused Worker authorization tests passed 14/14 earlier in this task chain; no Worker deployment was attempted.
- **Physical gate:** owner must save real profile fields in the installed authenticated app, refresh/relaunch, then provide rendered evidence. Photo upload/display remains NOT ENABLED pending a separately provisioned dedicated storage/safety capability and bounded upload-route completion.

## 2026-08-13 — Build 18039 Style Friends authenticated-entry repair

- **Failed physical authority:** the Friends Feed's `Sign in to Style Friends` branch rendered only informational copy. Its missing control was a client presentation dead end, not evidence of a second social-account requirement or a dedicated-backend failure.
- **Bounded fix:** the branch now renders a VoiceOver-labelled `Continue with Apple` control. It uses the canonical `StyleMatchAppleNonce`, `StyleMatchAccountClient().exchange`, and `StyleMatchAccountSessionStore.save` flow; no Apple credential, token, or separate Style Friends identity is retained. The existing session-store notification reloads Style Friends after a successful exchange, and valid sessions continue to be reused automatically.
- **Validation:** unsigned generic iPhoneOS Debug build and `git diff --check` pass. A deterministic source assertion requires the action, canonical exchange/save authority, and account-session change observer. XCTest execution is blocked because the shared scheme has no TestableReference. No Worker, D1, deployment, secret, social-image, or 18038 change occurred.
- **Physical gate:** sign/install the exact worktree, then owner Apple consent, authenticated route loading, and relaunch persistence remain pending device evidence.

## 2026-08-13 — Build 18039 Style Friends sign-in owner-beta artifact

- **Artifact:** exact protected-dirty 18039 source compiled as version 1.8 (18039), bundle `com.sabastine.stylematchai`, using team `ZV4P3Z2QLA`, pinned profile `0ca6b024-cbba-41ba-a926-bb7f2698eaaa`, and existing Apple Development identity `75B6694F0E1F34ABD09802F4726D5DC23A8BF95A`. The app carries a CodeSignature directory and bundle signature metadata; local strict verification remains subject to the pre-existing Codex trust-chain result `CSSMERR_TP_NOT_TRUSTED`.
- **Install:** CoreDevice listed the requested owner iPhone as connected and installed this artifact in place to `00008150-000C18E81AD8401C`; no uninstall or app-container deletion occurred. The immediate post-install process-launch/metadata query timed out while CoreDeviceService reinitialized, so launch and installed metadata are not claimed from that query.
- **Physical gate:** owner must open the updated app, use the newly visible Continue with Apple control, and provide device evidence for session establishment, authenticated Feed/Profile/Conversations, and relaunch persistence. No Apple token, authorization code, or raw account identifier is retained.

## 2026-08-13 — Build 18039 APNs notification-entry repair

- **Failed physical authority:** the owner could not find `Manage Style Friends notifications` in the installed app. Source tracing found the existing settings sheet and APNs coordinator, but its only UI entry was far down the authenticated social-profile form. It was absent from the signed-out Feed and not a discoverable global entry.
- **Bounded repair:** authenticated Style Friends now shows a visible `Style Friends notifications` button directly below the section selector. The signed-out card truthfully says sign-in is required and provides the existing Apple account action. The existing settings view continues to invoke the sole coordinator, which requests permission only after a tap and then calls `registerForRemoteNotifications()`. It now displays non-sensitive device-registration state (`Not registered`, `Registering`, `Registered`, or failure), while the app-delegate failure callback updates that state without logging token or error metadata.
- **Validation state:** Swift compilation reached application compilation, but full build is blocked at Xcode asset-catalog processing because the local CoreSimulator service reports no available simulator runtimes. `git diff --check` remains required after a successful build. No signing, install, Worker/D1, credential, profile, portal, DM, Support, or 18038 change occurred in this repair.
- **Physical gate:** blocked pending restoration of the local Xcode/CoreSimulator asset-catalog service. After a clean signed in-place artifact exists, owner evidence must verify the new entry, authorization prompt/status, APNs callback registration state, and dedicated-18039 device registration. No end-to-end push delivery is claimed without an existing authorized sender.

## 2026-08-13 — Build 18039 Style Friends Profile completion audit

- **Visual contract:** the approved reference remains visual-only. The compact dark/cream hero, fallback-initial avatar, live preview, selected style tiles, and accessible save states in the protected current `StyleFriendsView.swift` use only authenticated profile data or unsaved local draft data; no sample person image, name, biography, or style selection is bundled.
- **Profile authority:** existing client `PUT /v1/friends/profile/me` and Worker `friendProfiles.ts` authenticate the account session, constrain the upsert to that account key, and return the same canonical social projection. This supports display-name, bio, selected-style read-your-write and relaunch persistence once the owner signs in. The projection exposes only display name, optional avatar reference, bio, categories, discoverability, and timestamps; no raw account identifier, Apple identity, Closet, AI Memory, scan, or private Profile field is included.
- **Image boundary:** dedicated 18039 has `STYLE_FRIENDS_SOCIAL_IMAGES_RUNTIME_AUTHORITY = disabled` and `STYLE_FRIENDS_IMAGE_SAFETY_RUNTIME_AUTHORITY = disabled`; it has no configured `SOCIAL_IMAGES` binding and no owner-avatar upload/replace/delete route. Existing admission tests prove fail-closed image normalization and opaque storage-reference foundations only; they do not activate profile photos. Runtime photo status remains **NOT ENABLED**.
- **Tests / build:** focused Worker authorization and social-image-admission suites passed 16/16. iOS XCTest remains unavailable because the shared scheme has no TestableReference. Full iPhoneOS compilation is currently blocked at Xcode asset-catalog processing by local CoreSimulator's missing-runtime failure; no signed artifact or physical profile acceptance is claimed.

## 2026-08-13 — Build 18039 local CoreSimulator build-service recovery

- **Root cause / bounded recovery:** the active owner-session Xcode is `/Applications/Xcode.app/Contents/Developer` (Xcode 26.6, build 17F113). CoreSimulator was running in the `user/501` launch domain but its client connection returned no runtimes, which caused `actool` to fail with `supportedRuntimes=[]`. Restarting only the existing user-level `com.apple.CoreSimulator.CoreSimulatorService` restored registration. No simulator runtime, device, Xcode installation, source, profile, certificate, or portal state was removed or changed.
- **Runtime evidence:** `simctl` now registers iOS 18.1 and iOS 26.5, including an available iPhone 17 Pro Max simulator destination. `simdiskimaged` was not independently restarted; restored runtime enumeration establishes that its required service path is operational for the owner session.
- **Build evidence:** the exact protected 18039 worktree completed the previously blocked generic iPhoneOS Debug build, including `CompileAssetCatalogVariant` / `actool`, with `CODE_SIGNING_ALLOWED=NO`; `git diff --check` passed. A subsequent manual signed build with the existing Apple Development identity and profile also completed with an Xcode `CodeSign` phase.
- **Signed artifact:** `/private/tmp/StyleMatch18039-coresimulator-signed-20260813/Build/Products/Debug-iphoneos/StyleMatchAI.app`; embedded profile `0ca6b024-cbba-41ba-a926-bb7f2698eaaa`; strict `codesign --verify --deep --strict` passed. Signed entitlements include development APS, CloudKit container `iCloud.com.sabastine.stylematchai` / CloudKit service, Sign in with Apple, Associated Domains, and WeatherKit. Executable SHA-256: `d81187d6c697943650289e849191246cde2974e3dffb98eb2079848923929bf5`.
- **Install / feature boundary:** no installation occurred in this recovery task. Social-image runtime remains **NOT ENABLED** and no source, Worker, D1, secret, signing-asset, or 18036–18038 state changed.

## 2026-08-13 — Build 18039 recovered CoreSimulator artifact installed

- **Artifact identity:** owner-authorized recovered artifact `/private/tmp/StyleMatch18039-coresimulator-signed-20260813/Build/Products/Debug-iphoneos/StyleMatchAI.app`; executable SHA-256 `d81187d6c697943650289e849191246cde2974e3dffb98eb2079848923929bf5`; embedded profile `0ca6b024-cbba-41ba-a926-bb7f2698eaaa`; strict code-sign verification passed before installation.
- **Install / launch:** installed in place to the authorized iPhone `00008150-000C18E81AD8401C` without uninstall or app-container deletion, then launched. Device metadata reports StyleMatch Pro 1.8 (18039), bundle `com.sabastine.stylematchai`.
- **Physical boundary:** installation and launch do not establish rendered acceptance. Style Friends sign-in/action, premium Profile, notifications entry, premium Weather, and any Support UI state remain **PENDING OWNER DEVICE EVIDENCE**. Social-image runtime remains **NOT ENABLED**. The separate Support key 401-repair lane remains pending the owner-visible credential confirmation and does not become live merely because this binary launches.

## 2026-08-13 — Build 18039 AI Customer Service visibility/runtime repair

- **Physical regression authority:** owner reported that AI Customer Service was no longer visible or usable in the installed 18039 build. The Support Center source, `/v1/support/chat` client, consent-aware service factory, and dedicated 18039 endpoint remained present; this was not a provider, key, Worker, or D1 regression.
- **Root cause / bounded repair:** Debug configuration had explicitly compiled `STYLEMATCH_SUPPORT_RUNTIME_AUTHORITY = disabled`, forcing `StyleMatchUnavailableSupportService` despite the accepted staging service. The dedicated 18039 Debug value is now `stagingAuthorized`; Release remains independently disabled. The existing Profile support action is now visibly labeled **AI Customer Service** with an accessibility hint and continues to present the existing `StyleMatchSupportView`. No new support architecture, provider credential, route, or backend configuration was added.
- **Build / signed artifact:** full generic iPhoneOS Debug build and `git diff --check` passed. The manual signed build completed using Apple Development identity `75B6694F0E1F34ABD09802F4726D5DC23A8BF95A` and embedded profile `0ca6b024-cbba-41ba-a926-bb7f2698eaaa`; strict code-sign verification passed. Compiled `Info.plist` confirms Support authority `stagingAuthorized` and API host `https://stylematch-18039-friends-dm-staging.sabastine-7000.workers.dev`. Executable SHA-256: `045128bbf8e5fbc5d10282f51052d48928925a283cc063f9ca78ac69b935f128`.
- **Install / physical gate:** the verified artifact was installed in place and launched on authorized iPhone `00008150-000C18E81AD8401C`; device metadata reports StyleMatch Pro 1.8 (18039). Entry visibility, Support Center opening, consent presentation, and a truthful live response remain **PENDING OWNER DEVICE EVIDENCE**. Production Support flag remains `0`; no raw credential, token, account key, or provider response was recorded.

## 2026-08-13 — Build 18039 dedicated Apple account-auth recovery

- **Cause / scope:** the isolated Worker initially failed the native Apple exchange with `503 apple_account_pepper_not_configured`. This was a dedicated-18039 environment-configuration gap, independent of Support AI and not an iOS Sign in with Apple defect. The owner restored the six required secret bindings to only `stylematch-18039-friends-dm-staging`: `APPLE_ACCOUNT_ID_PEPPER`, `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY`, `APPLE_CLIENT_ID`, and `APPLE_TOKEN_ENCRYPTION_KEY`. No values are stored here.
- **Authority:** exact Worker identity `build-18039-style-friends-dm-staging`; D1 `06618deb-8114-4c9b-8006-68f4b58350af`. Before legitimate sign-in, aggregate prestate was zero Apple accounts, identity mappings, and sessions. Fresh dedicated staging pepper/token-encryption material therefore creates no existing-18039 account or refresh-token continuity break. No production or 18038/shared staging state was read, changed, or removed.
- **Precheck:** a deliberately invalid synthetic exchange now returns `401 apple_credential_invalid`, rather than any missing-secret configuration error. It proves the route reaches Apple credential validation without sending an actual Apple credential. Private-key parsing and AES key-byte-length validation are intentionally deferred until the real verified identity/authorization-code exchange; they are not overclaimed by this synthetic test.
- **Validation / physical gate:** Worker typecheck passed and full Worker suite passed 282/282. Native owner sign-in is now ready: tap `Continue with Apple` in the installed 18039 app, complete Apple UI, then verify HTTP 200 session creation, authenticated Feed/Profile/Requests/Friends/Conversations, and session persistence across relaunch. No synthetic or source result is a substitute for that physical evidence.

## 2026-08-13 — Build 18039 Style Friends owner-beta screenshot remediation

- **Physical evidence retained:** owner screenshots `IMG_6126.PNG` through `IMG_6128.PNG` are failed rendered-acceptance evidence, not overridden by source tests. They exposed a P2 over-expanded Conversations empty state, a P2 New Friend Posts menu that obscured its own notification controls on compact iPhone, and a P1 Profile presentation that repeated hierarchy, dominated the screen with a notification button, and presented an unavailable-photo camera as if it were actionable. The empty owner profile values themselves remain expected until the newly authenticated owner saves data to the isolated D1.
- **Narrow client remediation:** Conversations now presents its empty state as an upper-screen compact material card. The notification mode is a pushed, checkmarked selection list rather than an in-place menu popover. The Profile section now uses shorter hierarchy, a compact non-actionable unavailable-photo status, a smaller live Public Preview, interactive keyboard dismissal, and a quiet settings row instead of the large banner. No sample identity, bio, style, or photo is shipped.
- **Public bio contract:** the authoritative cap is now **1,000 UTF-16 characters**, aligned between `StyleFriendProfileUpdate` and the dedicated Worker. It is deliberately not a word limit. Worker profile request budget is raised to 6,144 bytes to carry valid multi-byte content plus the public profile envelope while keeping the strict server-side validation boundary.
- **Social-image activation:** **NOT ENABLED.** Migration lineage 0023/0024 and authorized GET groundwork exist, but dedicated 18039 still lacks the required private R2 `SOCIAL_IMAGES` binding, Cloudflare Images `IMAGES` binding, enabled image-safety authority/policy/provider configuration, and owner-avatar upload/replace/delete route. No image flag was changed and no shared/18038 storage was reused. The smallest next owner-approved infrastructure action is to provision dedicated 18039-only R2/Images bindings and a dedicated image-moderation configuration, after which the missing owner-avatar route can be implemented and separately accepted.
- **Validation:** Worker TypeScript typecheck passed and Worker suite passed **282/282** including the updated public-profile bound assertions. The generic unsigned iPhoneOS Debug build passed, including asset catalogs; `git diff --check` passed. The scheme still has no `TestableReference`, so XCTest execution remains blocked and is not claimed. No deployment, signing, installation, profile, certificate, Worker secret, D1 data, Support, Weather, DM, or 18038 state changed.
- **Remaining rendered acceptance:** sign and install this exact reconciled source, then obtain owner evidence for the compact Conversations empty state, notification-mode selection, profile keyboard behavior, real display-name/bio/style save/relaunch, and photo status remaining unavailable. Avatar upload/display is separately blocked as above.
- **Durable handoff artifact:** `/private/tmp/StyleMatch18039-style-friends-screenshot-remediation-20260813.zip`; contains only the bounded Profile/Notifications/Conversations source, matching Worker validation, tests, and ledger evidence—no secret values. Its verified SHA-256 is reported with the task handoff.

## 2026-08-13 — Build 18039 owner-authoritative 2,000-character public bio

- **Contract:** the superseding public Style Friends bio limit is **2,000 UTF-16 characters**, not 240 and not 1,000. iOS `StyleFriendProfileUpdate`, its live editor counter, the Worker profile validator, and Worker request-byte ceiling now share that exact contract. D1 and the social projections persist/return the normalized value without silent truncation.
- **Text semantics:** the multiline editor retains internal line breaks. The iOS save model and Worker both trim pathological leading/trailing whitespace; a whitespace-only optional bio becomes absent. Over-limit drafts remain in the editor and are not submitted; failed saves retain the owner draft for correction/retry.
- **Presentation:** Discovery remains a two-line concise preview. The owner’s preview remains three lines. An authenticated friend profile shows six lines initially and gives an explicit `Read full bio` / `Show less` control for long bios, preventing social lists and cards from becoming unbounded while preserving full fashion self-expression at the profile surface.
- **Validation:** Worker TypeScript typecheck and 282/282 Worker suite pass. Generic unsigned iPhoneOS Debug build passes; `git diff --check` passes. XCTest execution remains blocked by the scheme's missing TestableReference. Physical render and save/relaunch validation remain pending a newly signed in-place install.
## 2026-08-13 — Superseding Style Friends public-bio word contract

- **Supersession:** prior character-only public-bio records remain historical evidence but are no longer the active contract. Owner authority requires **at most 2,000 words**.
- **Authoritative implementation:** iOS uses `StyleFriendProfileUpdate.maximumStyleBioWords = 2_000` and `StyleFriendProfileUpdate.maximumStyleBioUTF16 = 24_000`; the dedicated Worker uses matching `MAX_BIO_WORDS = 2_000` and `MAX_BIO_UTF16 = 24_000`. Both limits are enforced before persistence. The independent 24,000 UTF-16-unit ceiling is a safety bound for realistic 2,000-word English prose plus Unicode/whitespace overhead; it is not a second customer-facing bio target. The Worker request budget is 102,400 bytes, sufficient for the worst-case UTF-8 text envelope while remaining bounded.
- **Text / presentation semantics:** the iOS editor is multiline and reports live words and UTF-16 units. It preserves internal line breaks, trims only leading/trailing pathological whitespace, retains failed-save drafts, and never silently truncates. Worker validation rejects more than 2,000 words or 24,000 UTF-16 units. Discovery receives a normalized 280-scalar excerpt, owner preview remains bounded, and authorized full profiles begin collapsed with explicit `Read full bio` / `Show less` control.
- **Safety / privacy:** only public display name and bio text are sent in bounded Unicode-safe chunks to the existing fail-closed `style-friends-dm-safety-v1` content-safety authority. Account keys, session material, Closet, AI Memory, scans, and other private data are excluded.
- **Validation:** Worker typecheck and full suite pass **283/283**, including 0/1/1,999/2,000/2,001-word, hard-ceiling, Unicode/emoji, and repeated-whitespace/newline cases. Existing Swift Package focused tests pass 70 with one fixture-dependent skip; the shared Xcode scheme still has no `TestableReference`, and no duplicate Xcode test target was added. Generic unsigned iPhoneOS Debug build passes. Physical save/relaunch/rendered acceptance remains pending a later authorized signed install.
- **Governance:** ADR-003 typed contract, ADR-006 fail-closed safety, and ADR-007 append-only evidence apply. No Worker deployment, secret, D1, image-runtime, 18038, signing, or install state changed in this reconciliation.

## 2026-08-13 — Dedicated 18039 Profile Avatar private-infrastructure checkpoint

- **Dedicated scope:** the owner provisioned `SOCIAL_IMAGE_MODERATION_API_KEY` to the isolated Worker only; no secret value is recorded. Dedicated Worker `stylematch-18039-friends-dm-staging` (D1 `06618deb-8114-4c9b-8006-68f4b58350af`) now has private R2 binding `SOCIAL_IMAGES` backed by `stylematch-18039-friends-dm-social-images` and a Cloudflare Images binding `IMAGES`. Both social-image runtime authorities remain **disabled**.
- **Deployment:** Worker version `a9bcd26b-a73a-4a7c-aaa7-2816eba45f8e` deploys the product-owned `style-friends-profile-avatar-safety-v1` configuration with only model, policy, and timeout identifiers. It is pre-activation configuration, not a public availability claim.
- **Lifecycle / privacy:** authenticated owner-only avatar upload, replacement, and removal use `PROFILE_AVATAR` purpose isolation; bounded JPEG/PNG/WebP intake; animation rejection; 512×512 WebP normalization; opaque references; review/reject fail-closed states; immediate revocation; and a retryable private cleanup ledger. Public/friend projections contain neither object keys nor moderation lifecycle detail. Owner `/me` readback can truthfully show pending review.
- **Database / validation:** 0023/0024 social-image schemas were reconciled without reapplying them; the remote migration command reports no migrations to apply and `PRAGMA foreign_key_check` returns zero rows. Worker typecheck and full suite pass **285/285**. Focused `StyleFriendsFoundationTests` pass **71 with one fixture-dependent skip**. Unsigned iPhoneOS Debug build and `git diff --check` pass.
- **Gate:** no synthetic avatar fixture was created, so no fixture cleanup was required. Live provider/normalization/metadata/authorization acceptance and owner physical avatar evidence are **blocked** while the explicit runtime gates stay disabled. No shared staging, Build 18038, or production state changed.

## 2026-08-13 — Dedicated 18039 temporary Profile Avatar live-acceptance run

- **Run authority:** exact Worker `stylematch-18039-friends-dm-staging`, dedicated D1 `06618deb-8114-4c9b-8006-68f4b58350af`, exact dedicated config, and matching health identity were reverified. Before activation, image rows and cleanup rows were zero, foreign-key check was clean, and `SOCIAL_IMAGE_MODERATION_API_KEY` was present by name only. Focused immutable source checkpoints were retained separately for Worker and iOS; unrelated protected 18039 dirty work was neither staged nor altered.
- **Temporary activation:** only `STYLE_FRIENDS_SOCIAL_IMAGES_RUNTIME_AUTHORITY` and `STYLE_FRIENDS_IMAGE_SAFETY_RUNTIME_AUTHORITY` were set to `stagingAuthorized` on Worker version `31e2730b-ad17-4f2c-a1d0-58d40125a49c`. The first run-scoped synthetic JPEG admission returned the intentional fail-closed `503 social_image_unavailable`; no avatar reference, object key, or public image was returned.
- **Rollback / cleanup:** both gates were immediately restored to `disabled` in final Worker version `266e20b7-e1ec-44d3-b090-43ead1377690`. Exact-run cleanup leaves zero synthetic accounts, sessions, social-image rows, and avatar-cleanup rows; remote foreign-key check is clean. No shared staging, 18038, production, APNs, or owner device state changed.
- **Classification:** live normalization, metadata privacy, provider safety, authorization, upload, replacement, removal, and cleanup acceptance are blocked at the first fail-closed admission boundary. The implementation deliberately returns a generic client-safe 503, so this run does not disclose or infer which internal stage (Images normalization, moderation provider, or private-store write) failed. Owner-beta avatar availability remains disabled pending bounded server-side stage diagnostics and a clean rerun.

## 2026-08-13 — Build 18039 reproducible baseline capture

- The mixed, previously accepted Build 18039 Worker and iOS worktree state was captured into dedicated baseline commits before any consequential avatar-admission diagnostics.
- The accidental untracked backend file `test/style-friends-apns-provider-tests 2.mjs` was explicitly excluded from project authority, preserved byte-for-byte in private quarantine, and removed only from the Git worktree. It was not committed, added to package configuration, or used as APNs test coverage.
- No secret value, private-key material, generated archive, DerivedData product, or unaccepted APNs duplicate entered either baseline capture.

## 2026-08-13 — Dedicated 18039 avatar admission diagnostic checkpoint

- A separate Worker diagnostic checkpoint added bounded server-only stage classification. The client contract remains the generic `503 social_image_unavailable`; it does not expose stage or provider detail.
- The dedicated deployed Worker confirms `IMAGES` and private `SOCIAL_IMAGES` bindings are attached. One synthetic replay was temporarily activated and immediately restored to `disabled`; the replay again failed closed before an avatar reference or object was exposed.
- Cloudflare live-tail delivery ended before it yielded the bounded stage events. Consequently the exact stage is **not proven** and image runtime stays disabled. No owner device, shared staging, 18038, or production state changed.

## 2026-08-13 — Durable avatar-admission diagnostic result

- Dedicated-only migration 0026 adds a gated, opaque, bounded diagnostic record. It is written only while the dedicated diagnostic authority is temporarily staging-authorized; no client route exposes it.
- The isolated synthetic Images check passed: binding, decode, transform, 512×512 WebP encoding, and bounded output evidence completed. The next terminal record was `IMAGE_SAFETY_RESPONSE` / `PROVIDER_RESPONSE_INVALID`; no R2 write or full avatar admission was attempted.
- All temporary image and diagnostic authorities were restored to **disabled**. The synthetic runner removed its own diagnostic and fixture evidence; remote social-image count is zero and foreign-key integrity is clean. Owner-beta avatar availability remains blocked pending a bounded moderation provider contract/configuration repair.

## 2026-08-13 — Avatar moderation contract repair

- The dedicated image adapter used the wrong multimodal request shape: a Responses-style `input_image` type with a string URL. It now uses the Moderations API `image_url` type and `image_url.url` data-URL object for the normalized WebP.
- Source typecheck and focused avatar/admission tests pass. The remote retest could not enter moderation because the route returned its runtime-disabled 404 after temporary-gate deployment; all gates were immediately restored to disabled. No R2 or owner-beta activity occurred.

## 2026-08-13 — Avatar route-probe classification correction

- The dedicated synthetic probe now classifies the bounded response error instead of treating every HTTP 404 as a disabled route. The temporary dedicated deployment displayed all three image/diagnostic authorities as `stagingAuthorized`, but the authenticated, profile-absent probe returned `social_image_unavailable`, not `profile_unavailable`; therefore the route gate did not pass.
- All three authorities were restored to **disabled** in Worker version `711efdcc-aeb0-4590-9acd-6bfe016f9c58`. No moderation, R2, lifecycle, owner-device, shared-staging, 18038, or production work ran.

## 2026-08-13 — Avatar runtime-authority instrumentation result

- Temporary dedicated-only route instrumentation recorded only the normalized authority enum, opaque request reference, route ID, and fixed Build 18039 identity. With the three gates temporarily declared `stagingAuthorized`, the deployed handler recorded `STAGING_AUTHORIZED` and returned `profile_unavailable` for the deliberately profile-absent synthetic account.
- This closes the gate-persistence concern: the earlier 404 was a runner-classification issue, not an environment-variable or handler mismatch. All three authorities were restored to **disabled** in Worker version `889d6ba2-4e04-4669-b9f1-b6f29fd02d5d`. The moderation-only retest did not run because the existing runner can proceed to R2, beyond its approved scope.

## 2026-08-13 — Dedicated 18039 APNs registration precheck and synthetic cleanup

- `APNS_TOKEN_ENCRYPTION_KEY` is present on `stylematch-18039-friends-dm-staging` by name only. A bounded authenticated synthetic registration and preference round-trip passed: registration returned 200; the master preference remained independent while New Friend Posts changed; master off/on preserved child selections.
- The run-scoped synthetic APNs fixture was removed in foreign-key dependency order. Post-cleanup counts are zero for synthetic device registrations, sessions, and accounts; the dedicated D1 foreign-key check is clean. No owner device token, account identifier, or private token material was recorded.
- Owner physical registration remains pending from the installed Build 18039 app. This entry is backend/precheck evidence only and does not claim device registration or push delivery.

## 2026-08-13 — Physical notification persistence and avatar-disabled UX remediation

- **Physical owner evidence:** the installed owner beta now reports iPhone notifications allowed and device registration registered. The remaining P1 notification defect is a parent/child UI mismatch: New Friend Posts can show `All friend posts` in its child screen while the parent row regresses to `Off`.
- **Root cause and repair:** the editor previously allowed a late GET to unconditionally replace the local value, and the picker mutated a nested binding without an explicit parent handoff. `StyleFriendsNotificationPreferencesDraft` now preserves unsaved edits across late loads, the picker updates the parent draft directly, and save reconciliation cannot overwrite a newer local edit. This preserves the master preference independently.
- **Avatar truthfulness:** while the dedicated image runtime remains disabled, the profile hero no longer renders an operational Photos picker or camera affordance. It retains initials fallback and one compact unavailable explanation; duplicate failed/rejected feedback is suppressed.
- **Validation:** deterministic notification draft coverage was added. The scheme has no configured XCTest action, so XCTest execution is blocked rather than claimed. Unsigned iPhoneOS Debug compilation passed and `git diff --check` passed. A new signed Build 18039 is required for physical regression acceptance.

## 2026-08-13 — Notification physical-retest artifact installed

- **Source checkpoint:** `be1c6920816045c3a3c0f646bfdaecb823244f23` (`fix(build18039): persist Style Friends notification preferences`). The checkpoint is clean and contains only the accepted notification persistence, disabled-avatar UX, focused deterministic coverage, and ledger/project-state changes.
- **Artifact:** `/private/tmp/stylematch-build18039-notification-retest/Build/Products/Debug-iphoneos/StyleMatchAI.app`; executable SHA-256 `f4a11b3a9fd7fe0eb29a0eac5848945a19427c61a3f1e9654120146875654cf7`; embedded-profile SHA-256 `95f2bd2e8d7ce27726570a46785d5add637bfc78f5bdca3f3aab06c7b90d6321`.
- **Pre-install verification:** strict deep code-sign verification passed; bundle `com.sabastine.stylematchai`, version `1.8`, build `18039`, team `ZV4P3Z2QLA`, APS development entitlement, CloudKit container, dedicated 18039 staging host, and Debug APNs authority all matched. Social-image runtime remains `disabled`.
- **Install:** `devicectl` completed an in-place install to the authorized owner iPhone. Physical notification persistence and disabled-avatar UX acceptance remain pending owner evidence. The project currently has no XCTest target/TestableReference, so XCTest is explicitly blocked rather than claimed.

## 2026-08-13 — Dedicated avatar runtime completion attempt

- **Route authority:** a temporary dedicated-only deployment showed all three runtime authorities as `stagingAuthorized`. The bounded authenticated probe returned `profile_unavailable` with observed authority `STAGING_AUTHORIZED`; this proves the avatar route passed its runtime gate. The earlier `social_image_unavailable` classification was not a persistent runtime-authority defect.
- **Moderation boundary:** the corrected Moderations image request reached the provider and received HTTP `401`, recorded as `IMAGE_SAFETY_RESPONSE` / `PROVIDER_AUTH`. No R2 write, avatar record, or owner data was created. This is an external credential/project-authority failure and cannot be repaired without the owner supplying a valid dedicated image-moderation key for the intended OpenAI project.
- **Rollback and validation:** all three dedicated avatar authorities were restored to `disabled` in Worker version `70d1a438-1f97-44e4-9f29-535844d4f173`. Synthetic accounts/images/diagnostics are zero and foreign-key integrity is clean. Worker typecheck and full suite passed (287/287). Owner-beta avatar activation remains blocked until the credential is corrected and live acceptance is rerun.

## 2026-08-13 — Dedicated avatar owner-beta activation

- The replaced dedicated moderation credential passes the isolated provider probe. Synthetic acceptance passed for private 512×512 WebP normalization, source metadata-marker removal, opaque authorized owner/friend retrieval, replacement revocation, removal revocation, and foreign-key-clean fixture cleanup. Deterministic safety coverage verifies allow, review, rejection, and fail-closed provider behavior; no live harmful-image submission was used.
- The dedicated Worker image and image-safety authorities are now `stagingAuthorized`; the temporary diagnostics authority is disabled. Debug iOS is aligned to the dedicated staging authority; Release remains disabled. No production, shared staging, Build 18038, APNs, secret value, or owner image was touched. A fresh signed Debug owner-beta artifact is required before physical avatar acceptance.
- Validation after Debug activation: Worker typecheck and full suite passed (288/288); unsigned iPhoneOS Debug build passed from iOS checkpoint `abeb4bc85e3f705bc1d70aa1483d90e027892936`; `git diff --check` passed. The project has no configured XCTest action, so XCTest is not claimed.

## 2026-08-13 — Avatar owner-beta signed artifact

- Signed source checkpoint: `0cc0d25bd1f73e8242a663ef5fe0510f0006dbf0`. Artifact: `/private/tmp/stylematch-build18039-avatar-owner/Build/Products/Debug-iphoneos/StyleMatchAI.app`.
- Verification passed: strict deep codesign; bundle `com.sabastine.stylematchai`; version/build `1.8` / `18039`; team `ZV4P3Z2QLA`; APS development; CloudKit, Sign in with Apple, Associated Domains, and WeatherKit entitlements; embedded profile UUID `0ca6b024-cbba-41ba-a926-bb7f2698eaaa`; dedicated 18039 host; Debug avatar authority `stagingAuthorized`.
- Hashes: executable `a2e37cf93cfe1bfa62f4e8e4dbee1c0489a1153c79c3e30e440cafeec3053e64`; embedded profile `95f2bd2e8d7ce27726570a46785d5add637bfc78f5bdca3f3aab06c7b90d6321`.
- In-place installation did not begin: CoreDevice could list the paired iPhone but its control-channel connection timed out/was invalidated. No app uninstall, replacement, container deletion, or owner-data change occurred. Physical avatar and notification acceptance remain pending a reachable device.

## 2026-08-13 — Fresh avatar owner-beta artifact retry

- The app source is unchanged from functional checkpoint `0cc0d25bd1f73e8242a663ef5fe0510f0006dbf0`; current HEAD differed only by prior append-only ledger records. Fresh artifact: `/private/tmp/stylematch-build18039-avatar-owner-fresh/Build/Products/Debug-iphoneos/StyleMatchAI.app`.
- Strict codesign, bundle/version/build/team, development APS entitlement, dedicated 18039 host, Debug avatar authority, and profile UUID passed. Executable SHA-256: `0da35954df878acecc953e4255ce128526b530e0f4fec88122453209dcda92d6`; embedded-profile SHA-256: `95f2bd2e8d7ce27726570a46785d5add637bfc78f5bdca3f3aab06c7b90d6321`.
- In-place installation did not start because CoreDevice could not locate the requested iPhone identifier. No uninstall, replacement, container/data change, or physical acceptance occurred.

## 2026-08-13 — Durable cross-build preservation checkpoint

- iOS preservation HEAD: `c9cbd89ec33cf09d7807ea87bac1ea3cb1db573b`; functional avatar source checkpoint: `0cc0d25bd1f73e8242a663ef5fe0510f0006dbf0`.
- Dedicated Worker source checkpoint: `61d71ad64bdb864c5fbc503df1c161dec1aa4868`; durable Worker documentation checkpoint: `92205577dfea3c6a25ff2e2158912bae421d6f50`; deployed Worker version: `bf7a532e-4d33-42b4-9ba1-44ea5f503fd2`; dedicated D1: `06618deb-8114-4c9b-8006-68f4b58350af`.
- Runtime authority: Debug avatar/image and image-safety are `stagingAuthorized`; Release avatar runtime and temporary diagnostics are disabled. The fresh signed Debug artifact remains evidence only; its temporary path is not durable authority.
- Source, Worker, signing, simulator, install, and physical evidence remain separate. Avatar physical acceptance and notification relaunch confirmation remain pending a reachable owner device.

## 2026-08-13 — Source archive supplement

- Reproducible source snapshot for checkpoint `0f6b01a420faa86757d223dc03bed53498c0b0d7`: `/private/tmp/StyleMatch-18039-ios-0f6b01a-source.zip` (SHA-256 `6ec63d347772d2aa8720589cd2a5c567a0881e8be88ba48e5f8dd2930b4bf8f9`). The Git checkpoint and ledger are authoritative; the temporary archive is supplemental only.
# 2026-08-13 — Cross-build global AI control persistence repair

Build 18039 previously persisted only `stylistGlobalControlEdge`, so a recreated root always restored the global AI control expanded. It now reads and writes the shared device-global `floatingStylistControlPlacement.v1` Codable authority established in Build 18037: bounded placement plus `isCollapsed`, synchronously restored before presentation. The former edge-only value remains a non-destructive fallback for already-installed older 18039 clients. Absent/corrupt v1 data returns the accepted expanded default. This presentation preference is isolated from account/session, AI Memory, Style Friends, Weather, and backend state. Physical force-close/relaunch acceptance remains pending.

## 2026-08-13 — Style Friends Notifications premium UX V2

The existing navigated New Friend Posts screen now provides descriptive, Dynamic-Type-safe full-width choices with one selected checkmark. The parent screen places the selected mode beneath its label, separates iOS permission from device registration and Style Friends preferences, and moves the long privacy explanation into a compact disclosure. The existing draft/save/reload semantics, master-child preservation, and device-registration independence are unchanged. Automated StyleFriends suite: 73 tests, 1 existing fixture skip, 0 failures. Physical visual/relaunch acceptance remains pending.

## 2026-08-13 — Profile Privacy search selection repair

Owner evidence showed `pri` matched Privacy but did not select it reliably. Search selection now dismisses the keyboard, updates the selected section, aligns the selector, and invokes the registered Privacy scroll. Privacy, APNs, and Style Friends contracts are unchanged; physical retest is pending.

## 2026-08-13 — Current-rain current-versus-future styling parity

The accepted fresh WeatherKit umbrella authority remains unchanged. Styling now additionally limits wet-shoe/rain-layer treatment to positive current precipitation intensity; a future hourly advisory remains future-oriented umbrella guidance and cannot make the current outfit appear wet. Focused Weather umbrella tests passed. Physical Home/Weather agreement and current-rain banner acceptance remain pending.

## 2026-08-13 — Style Friends Conversations premium empty-state refinement

The live 18039 Conversations route now distinguishes loading, empty, populated, recoverable-error, and authorization-unavailable states. The empty state is a compact premium card with a functional `Find Style Friends` CTA that dismisses the conversation sheet and reuses the existing discovery route; it does not create a second relationship or messaging path. A bounded privacy disclosure accurately refers to relationship, block, moderation, and generic-notification-preview enforcement without claiming end-to-end encryption. Existing conversation, retry, ordering, authorization, and Worker transport authorities are unchanged. Source-contract DM coverage passed; simulator and physical acceptance remain pending.

### 2026-08-13 — Conversations populated-state regression guard

Diff review against the pre-refinement checkpoint confirms the `.populated` branch, `StyleFriendsConversationRow`, `StyleFriendsLiveChatView`, unread/latest-preview/timestamp projection, ordering, and failed-send/retry path are unchanged. `StyleFriendsFoundationTests` passed 72 tests with one pre-existing local-fixture skip and no failures. This proves source-level preservation only; physical populated-conversation acceptance remains required.

## 2026-08-13 — Dedicated owner iPad beta-validation lane

The paired owner-beta target is `Sabastine ipad pro 13 inch` (`74C11E87-A287-55C2-8AD7-2B1C5918911E`), reported paired and available by CoreDevice. Build 18037 remains reserved for the owner iPhone Apple-reviewer lane; Build 18039 Debug is the iPad beta lane. The app supports device families `1,2`, iPad portrait/landscape orientation, and iOS 16+. Conversations empty-state content is capped at 680 points on larger layouts; notification copy is device-neutral and APNs registration remains an explicit, session-scoped, device-token registration flow. No iPad installation occurred. CoreDevice timed out before OS version, Developer Mode, and installed-app identity could be queried. Style Friends/DM are Worker-owned and do not use CloudKit; the existing CloudKit code retains typed schema validation and iCloud-account fail-closed boundaries. Physical iPad validation remains mandatory.

### 2026-08-13 — AI Customer Service staging reactivation and iPad source guard

The accepted Support Center was recovered as present: Profile exposes **AI Customer Service**, Debug resolves only the dedicated 18039 staging authority, Release remains disabled, and the authenticated Support client retains chat, cases, messages, escalation, and bug-report routes. Dedicated Worker checkpoint `7c2f3174b119c7ee4509beb45b701028f389c5c1` restored eight additive approved `build18039-support-v2` knowledge records and completed synthetic consent-gated provider/route acceptance. Dedicated D1 Support was then enabled for owner beta; shared staging, Build 18038, production, and credential values were untouched. Human escalation delivery remains not configured.

iOS checkpoint `833102c03b511871c72b34146c160d425d72436d` constrains Support Home and Support Chat content to a 720-point readable maximum on iPad while retaining adaptive full-width iPhone layout. `StyleFriendsFoundationTests` passed 73 executed tests with one existing fixture skip and no failures. Physical iPad validation remains mandatory for entry, consent, chat, keyboard, long responses, case detail, scrolling, Dynamic Type, VoiceOver, and light/dark rendering; source/build evidence does not substitute for it.

- **Build boundary:** Support source parses and its focused suite passes, but the full unsigned iPhoneOS Debug build is blocked by pre-existing non-Support source at `ProfileView.swift:2506`: `navigationProxy` is out of scope. This task did not alter Profile source, signing, installation, or either device lane.

### 2026-08-13 — iPad sequential reviewer and owner-beta install gate

The owner iPad has two ordered roles: Phase 1 is Build 18037 physical acceptance, Apple reviewer video, and resubmission; Phase 2 is an in-place upgrade to Build 18039 for owner-beta validation. Build 18039 must not be installed on the iPad until the owner confirms `REVIEWER_18037_PHASE_COMPLETE = YES`. Before every iPad install, record `IPAD_CURRENT_BUILD`, `REQUESTED_BUILD`, reviewer-phase completion, `IPAD_INSTALL_PHASE`, and `INSTALL_ALLOWED`. If the request is 18039 and reviewer completion is not confirmed, `INSTALL_ALLOWED = BLOCKED`. No uninstall is authorized absent a proven install-state defect.

### 2026-08-13 — Profile navigation proxy compile repair

`ProfileNavigationControls` declared `navigationProxy` inside the horizontal chip `ScrollViewReader`, while search-result buttons were outside that lexical closure. The result was an out-of-scope reference at `ProfileView.swift:2506` and a full iPhoneOS compile failure. The minimum repair keeps the existing reader and typed `select(section, using:)` authority, moving the search result list into that reader. Search selection still dismisses the keyboard, clears search, selects the section, keeps the chip visible, and calls the existing section scroll closure.

Focused Profile navigation/search tests passed, including Privacy matching and selection-source coverage. The full unsigned iPhoneOS Debug build now succeeds; `git diff --check` passes. No Support AI, Worker, avatar, notification, DM, Weather, bio, privacy, signing, installation, or device-lane authority changed.

### 2026-08-14 — AI Stylist runtime boundary and Weather context isolation

The isolated Build 18039 Worker has no `AI_API_KEY` secret binding (name-only inspection); AI Stylist `/v1/chat` consequently creates an OpenAI request without the required provider credential and its fail-closed Worker path returns the generic provider failure rendered in the owner screenshot. This is separate from accepted Support AI, which has its own `SUPPORT_OPENAI_API_KEY` binding and must not be substituted. The required owner-only recovery is to securely provision the approved dedicated staging Stylist credential under `AI_API_KEY`, then run consent-gated live acceptance.

The iOS repair isolates WeatherKit presentation: a General Stylist session clears inherited weather context and renders no attribution; an explicit `weather_styling` handoff retains bounded weather context and the Apple Weather mark/legal link. Apple’s current WeatherKit guidance requires the Apple Weather trademark and legal link wherever Apple weather data is displayed. Focused tests passed; physical/provider acceptance remains pending.

The AI Stylist UI now keeps a retryable failed user turn, displays an accessible 44-point Retry action, and resends its captured context exactly once per explicit tap without duplicating visible conversation history. This is client recovery only and does not mask the missing dedicated Worker `AI_API_KEY` runtime prerequisite.

### 2026-08-14 — Home search Style Friends discovery

Home search now registers the existing Build 18039 Style Friends destinations: Style Friends, Friends, Find Style Friends, Friend Requests, Conversations (including the Messages alias), Shared Looks, and Friends Feed. A typed, short-lived `styleFriendsHomeSearchRoute.v1` handoff selects the existing Profile tab and presents the existing Style Friends sheet at the requested supported destination; it creates no second search, authentication path, or navigation stack. Exact/title-prefix matches rank above incidental keyword matches while preserving declaration order for ties. Focused source-contract coverage and an unsigned iPhoneOS Debug build passed. Physical search/routing acceptance remains required.

### 2026-08-14 — Curated Theme system V2

The 18039 Theme editor now starts its preview richness from the applied device-local preference. Preview remains draft-only until Apply. Curated choices are StyleMatch Signature, System, Midnight, Luxury Gold, Rose Fashion, Ocean, Emerald, and Monochrome; legacy raw values remain decodable and unknown values fall back to System. The unsigned iPhoneOS Debug build passed; physical global-theme acceptance remains required.

### 2026-08-14 — Deterministic Theme Engine V1 and local adaptive policy

Build 18039 now has a finite, semantic `StyleMatchThemeTokens` rendering authority for shared screen, card, and page-band surfaces. It preserves the existing stable persisted theme raw values while exposing the approved registry: Signature, System, Midnight, Luxury Gold, Rose Fashion, Ocean, Emerald, and Monochrome. Status, warning, and error retain semantic system colors rather than being recolored by fashion themes.

`styleMatchThemeMode` is a device-local preference with Manual, System, and Adaptive modes. The first Adaptive policy is `local-adaptive-v1`: it uses only time of day and device appearance to recommend an approved theme, never applies an arbitrary appearance, never contacts an AI provider, and never inspects DMs, Support, scans, Closet, AI Memory, location, or account data. Applying remains an explicit owner action; unknown mode/theme values fall back safely to System. Swift parse and diff checks pass. Full iPhoneOS build is presently host-blocked before Swift compilation because CoreSimulator/simdiskimaged makes `actool` report no available simulator runtimes. Physical/accessibility verification remains required.

### 2026-08-14 — Theme roadmap scope correction (supersedes unaccepted adaptive activation)

The local Adaptive UI/persistence activation described above was not checkpointed or accepted and is removed. Build 18039 inherits the deterministic 18038 Theme Engine contract only at this stage. Adaptive Appearance is explicitly deferred until the 18038 engine has completed app-wide token/adoption and accessibility acceptance. No provider AI/theme call, adaptive mode preference, or automatic theme selection ships in this checkpoint.

### 2026-08-14 — Support AI physical-unavailable reconciliation

Owner physical evidence showed Support Home rendered while Support Chat displayed a generic unavailable result. Current Debug source is correctly bound to `https://stylematch-18039-friends-dm-staging.sabastine-7000.workers.dev` with `STYLEMATCH_SUPPORT_RUNTIME_AUTHORITY = stagingAuthorized`; Release remains disabled. The accepted dedicated staging state is `support_ai_enabled = 1`, secret name `SUPPORT_OPENAI_API_KEY` present, and eight approved `build18039-support-v2` knowledge records.

The proven iOS defect was error classification: the Worker’s bounded `aiConsentRequired` error decoded as an unknown response and rendered generic Support-AI unavailable copy. The Support client now maps it to `consentRequired`; an absent/expired local account resolves to a sign-in-required service instead of a disabled service. Chat states now distinguish sign-in, consent, sending, answer, retryable connectivity/rate-limit failure, provider/response failure, and disabled service. Support Home no longer exposes staging language, collapses the privacy explanation into a disclosure, removes duplicate Report-a-Bug entry, and preserves all routes. Focused Support tests passed. A full unsigned iPhoneOS build remains host-blocked by CoreSimulator/simdiskimaged asset-catalog failure. A new signed 18039 Debug artifact and physical retest are required; no iPad installation is authorized before the 18037 reviewer phase completes.

### 2026-08-14 — Semantic Theme Engine social and Support adoption

Build 18039 now routes the Style Friends landing screen, Conversations list/empty/error surfaces, direct-message chrome, notification settings and New Friend Posts list, and AI Customer Service Home/chat cards through the existing deterministic `appScreenBackground(.profile)` and `appCard(.profile, radius:)` primitives. This replaces presentation-only grouped-system surfaces and material cards while preserving message authorization, retry/recovery, moderation, Support runtime, knowledge, notification persistence, and account/device state. Status, warning, error, and Apple-owned UI remain semantic/system-controlled. No Adaptive Appearance or provider/theme behavior was added. Focused source-contract coverage validates the shared primitive use; physical theme/accessibility validation remains required.

### 2026-08-14 — Support iPad layout regression assertion reconciliation

The Support Home and Support Chat still retain their two existing 720-point readable-content-width constraints. The source-contract assertion was updated only to account for the newly inserted semantic page-background modifier between that width constraint and the navigation title. Focused verification passes; no Support runtime, privacy, route, or visual-layout contract changed.

### 2026-08-14 — Consolidated 18039 morning owner-beta handoff

Final iOS source checkpoint is `239fd3e9b2cce19ffc31ad9f97809a531d23a61c`, clean and reproducible. Worker source checkpoint is `24ecb0c24fbc65bfa7e601f84f634d9939c1d694`; the last documented dedicated staging deployment after `AI_API_KEY` provisioning is `1f6c28db-971f-47c5-8419-4a5dc96bde6c`. Dedicated staging remains the only owner-beta authority; no shared staging, production, credential, or runtime mutation was made during this handoff.

Worker typecheck and full deterministic suite pass. Focused iOS Support and social/theme source-contract tests pass. A fresh unsigned iPhoneOS build could not produce an artifact because the host `CoreSimulatorService`/`simdiskimaged` failure makes `actool` report no iPhone simulator runtimes. Local valid development identities are present, but signing and strict artifact verification are intentionally blocked until a build exists. `devicectl` likewise cannot enumerate CoreDevice devices; no iPhone identifier or install command is asserted. The iPad is explicitly blocked for 18039 until the 18037 reviewer phase is confirmed complete.

### 2026-08-14 — Build 18039 local Adaptive Appearance engine

Build 18039 now inherits the resolved-appearance seam accepted in Build 18038 checkpoint `f40a7bf58fbf37cf67a20ac73cf46730f806ecf4`: stable Manual/System/Adaptive modes; preserved `selectedAppTheme` and `selectedThemeIntensity`; additive `styleMatchAppearanceMode` and `styleMatchAdaptiveTheme`; and one resolver for screen, card, page-band, and root rendering. Missing/corrupt mode repairs to Manual, preserving legacy selected themes. Adaptive accepts only `StyleMatchAppTheme.availableThemes` identifiers and falls back to the valid selected theme, then System.

The `local-adaptive-v1` engine is deterministic and device-local. It ranks only the approved registry based on time plus optional explicit occasion/style preference, and filters candidates for dark/light compatibility, increased contrast, and reduced transparency. It never reads DMs, Support, scans/photos, Closet, AI Memory, precise location, identity, or auth state. It has no provider, Worker, or network call. The Appearance screen supplies Manual/System/Adaptive selection, explanation copy, Keep this theme, and Return to Adaptive. An adaptive manual selection persists a lock so a recommendation cannot immediately override it.

Validation: focused SwiftPM `Build16PaletteTruthTests` passed 60/60 after correcting an existing stale scan decode-location assertion to `ScanAuthority/StoredOutfitScan.swift`. Fresh unsigned generic-iPhoneOS Debug build passed at `/private/tmp/stylematch-18039-adaptive-local`; `git diff --check` passed. Physical/accessibility validation and full semantic-token adoption remain separate. Adaptive source is ready; premium-ready remains blocked until the eight primary surfaces reach full token adoption.

### 2026-08-14 — XCTest authority decision

Build 18039 adopts the current project-wide decision: SwiftPM `StyleMatchProPhase2Tests` is the canonical XCTest authority and `swift test` is the supported execution path. The shared Xcode scheme's TestAction is non-authoritative for this SwiftPM target because the Xcode project contains only the application target; no duplicate native XCTest target or scheme workaround was created. This is not a product/build blocker.

### 2026-08-14 — Resolver parity repair supersedes provisional Adaptive readiness

Forensic comparison found that the prior 18039 resolver report used a 60-method source-contract inventory while 18038 contained 65. Seven shared resolver contracts were missing from 18039: local/shared authority; legacy-manual preservation; the `selectedAppTheme = system` versus missing-mode collision; mode/adaptive fallback; preview-versus-applied isolation; three-primitive consistency; and device-local persistence/fallback. The two 18039-only Adaptive tests remain additional coverage.

`Build16PaletteTruthTests` now contains all 65 shared contracts plus the two 18039-specific Adaptive tests. Canonical SwiftPM execution passed **67/67**. In particular, the legacy system collision test proves a missing appearance-mode value resolves to Manual while the selected theme still resolves to `.system`; the two raw values are not conflated. The source contracts also retain zero provider/network appearance dependency and no Worker, OpenAI, Support AI, AI Memory, or CloudKit appearance authority.

The prior scan decode-location assertion correction remains an existing completed scope expansion from `af3eb40`; it was not changed by this parity repair and no Scan product behavior changed. Pre-existing in-progress token migration diffs in `StyleMatchAI/HomeView.swift` and `StyleMatchAI/ProfileView.swift` were preserved outside this checkpoint. This supersedes the prior parity claim: `RESOLVER_PARITY_WITH_18038 = PASS`; Adaptive source readiness is restored only after the unsigned-build gate below, while premium/physical readiness remains blocked by token-adoption and device validation.

Validation after parity repair: the unsigned generic-iPhoneOS Debug build passed and `git diff --check` passed. The resolver-parity checkpoint contains only the focused source-contract tests and these append-only records; the Home/Profile token migration remains deliberately separate.

### 2026-08-14 — Home/Profile semantic token migration compile repair

The separate Home/Profile migration replaces neutral Home search/result card surfaces with resolved Home `cardBackground`/`elevatedCardBackground` tokens and routes Profile navigation search, selected chips, and container surfaces through resolved Profile tokens. The semantic intent is preserved: standard cards use `cardBackground`, elevated containers use `elevatedCardBackground`, and selected navigation uses the existing `accent` token with a high-contrast foreground. No resolver or Adaptive decision behavior changed.

The compiler failure at `ProfileView.swift:2490` was proven as SwiftUI ViewBuilder generic-inference/complexity caused by inline selected-state conditional token expressions inside the `ForEach` label. The source-equivalent repair extracts `isSelected`, typed background, and typed foreground values before the button label and adds an explicit `id: \.self` to retain collection identity. A follow-up compile revealed that the claimed `selectedBackground`/`selectedForeground` token members do not exist in `StyleMatchThemeTokens`; the repair deliberately uses the existing semantic `accent` instead of creating a second token authority. Unsigned generic-iPhoneOS Debug build and `git diff --check` pass. Home behavior, Profile search/privacy routing, bio/avatar, and Adaptive/resolver behavior remain unchanged.

### 2026-08-14 — Final 18039 morning owner-beta artifact

Final source authority is recorded at the companion handoff checkpoint. Canonical SwiftPM focused resolver/theme coverage passed 67/67 and a fresh unsigned generic-iPhoneOS Debug build passed. The fresh Debug artifact is `/private/tmp/stylematch-18039-final-signed/Build/Products/Debug-iphoneos/StyleMatchAI.app`; strict codesign verification passed. It is bundle `com.sabastine.stylematchai`, version/build `1.8`/`18039`, Team `ZV4P3Z2QLA`, development APS, and the dedicated 18039 staging host. Executable SHA-256: `78e744db8716e5b6e1957f06dfb7eed2efead4b9458536a714201bb3dbfa32b4`; embedded-profile SHA-256: `95f2bd2e8d7ce27726570a46785d5add637bfc78f5bdca3f3aab06c7b90d6321`.

The only approved target is `Sabastine iphone 17 pro Max` (`3BAD6F82-5382-5968-AB33-C43E585A573F`), currently paired but unavailable. Installation is pending and was not performed. Build 18039 must not install on the iPad; `18039_IPAD_INSTALL_ALLOWED = NO`. Physical owner-beta acceptance remains pending.

### 2026-08-14 — Build 18039 explicit occasion authority compile repair

Checkpoint `6cef2b5baf8a8e90e82a4dc840637e830764d03c` establishes saved-scan occasion precedence: explicit user selection, then confirmed Work Uniform category, then classifier fallback. Workplace authority remains separately typed. The compiler repair passes `updated.outfitClassification` into `canonicalOccasionForPersistence`; the helper needs the classification sub-value for category, confidence, and selected-occasion evidence, not the enclosing `OutfitAnalysisResult`. This preserves Work Uniform mapping to `.work` and does not alter scoring, image storage, Weather, provider, or Stylist behavior. SwiftPM Scan authority tests passed 182/182; stored-scan-to-Stylist coverage passed 1/1; a fresh unsigned iPhoneOS Debug build and `git diff --check` passed. Historical scans are not bulk-rewritten without deterministic original-selection evidence. Physical validation remains pending.

### 2026-08-14 — Build 18039 device preview macro isolation

Checkpoint `bcc806c827c040d86b3e275fb746429bcc959dfe` isolates the sole standalone Style Friends `#Preview` macro to `DEBUG && targetEnvironment(simulator)`. Preview fixtures and live `FriendChatView` construction are unchanged; no runtime behavior is compiled out for iPhoneOS device Debug builds. This removes preview macro/plugin expansion from the owner-beta device build path. The subsequent fresh unsigned iPhoneOS Debug build passed.

### 2026-08-14 — Build 18039 safe customer-copy polish and regression hardening

Customer-facing Support terminology is now consistently “Report a Problem”; the Worker route and `bugReport` typed category remain unchanged. Internal beta/staging wording was removed from the avatar unavailable state and Style Friends sign-in VoiceOver hint. Notifications now use the customer-facing section title “Notifications on This Device” rather than registration terminology. Support disabled copy now truthfully says unavailable right now. A focused source-contract test protects these wording boundaries. Validation passed: copy contract 1/1, Adaptive/theme `Build16PaletteTruthTests` 68/68, General-after-Weather isolation 1/1, Support states 1/1, and Style Friends route search 1/1; `git diff --check` passed. No backend, provider, transport, preference, or scan authority behavior changed. Host signing/physical acceptance remain pending.

Follow-up checkpoint removes the remaining Feed unavailable-state implementation term “secure feed endpoint”; it now describes only the truthful customer outcome. The same copy contract passed 1/1 and `git diff --check` remains clean.

Additional safe AI Stylist regression execution passed: duplicate submission prevention 1/1 and failed-send preservation 1/1. These tests retain the user message while clearing sending state and prevent duplicate provider requests; no provider configuration or runtime behavior changed.

### 2026-08-14 — Build-gate reconciliation

A second fresh unsigned iPhoneOS diagnostic again failed at `actool` because CoreSimulator/simdiskimaged exposes no iPhone simulator runtime. It emitted no Swift or `ProfileView.swift` error, but the host abort means those gates remain unproven rather than passed. Primary surface token adoption remains partial: 50 shared primitive uses coexist with 45 remaining hard-coded/material presentation candidates requiring semantic review. No Adaptive Appearance was introduced.

### 2026-08-14 — Host recovery and Profile token compile repair

The local `CoreSimulatorService` and `CoreDeviceService` were safely restarted in their existing user launchd domain; installed iOS simulator runtimes and CoreDevice enumeration recovered without changing product source, Xcode, profiles, certificates, simulators, or devices. The prior asset-catalog host block is therefore closed.

The subsequent exact-source Debug build exposed a real, independent compiler defect in `StyleMatchAppTheme.tokens(for:)`: its local `palette` value shadowed the `palette(for:)` method. Five semantic accent lookups now explicitly use `self.palette(for:)`. A fresh unsigned generic-iPhoneOS Debug build succeeds. Signed-artifact verification and installation remain separate and no device was modified.

### 2026-08-14 — Corrective 18039 signed morning artifact

Artifact source checkpoint: `6ab588578c4ceef3593fce4e64c9164e4f4646da` (the required correction atop the non-compiling `d00267ac` snapshot). Fresh generic iPhoneOS Debug build and strict codesign verification pass. The artifact is `/private/tmp/stylematch-18039-morning-signed-fixed/Build/Products/Debug-iphoneos/StyleMatchAI.app`; bundle identity is `com.sabastine.stylematchai`, version/build `1.8`/`18039`, Team `ZV4P3Z2QLA`, and APS environment `development`.

The executable SHA-256 is `4d30d5df4712a93c22ddfd9a19f8555ae43311d6379bfca9fc4f7a1e0f81af8f`; the embedded provisioning-profile SHA-256 is `95f2bd2e8d7ce27726570a46785d5add637bfc78f5bdca3f3aab06c7b90d6321`. Debug binds only to the dedicated 18039 staging host and has accepted staging authorities; Release xcconfig remains disabled. No installation occurred. The only permitted future target is the enumerated iPhone 17 Pro Max, not the iPad reviewer lane.

### 2026-08-14 — Build 18039 Style Friends chat semantic presentation

Checkpoint `759468084b9c82945c6153314a28c5d08cff782a` moves the conversation reaction picker and composer from fixed purple/system-grouped presentation to the existing resolved Theme Engine. Selected reactions and send use `socialAccent`; composer and reaction container surfaces use `cardBackground` and `elevatedCardBackground`. DM transport, relationship authorization, moderation, retry, and privacy contracts are unchanged. Focused SwiftPM source-contract coverage passed 1/1 and `git diff --check` passed. Host iPhoneOS build and physical light/dark, Dynamic Type, iPad, send/retry validation remain pending; no provider call was added.

### 2026-08-14 — Current-head signed owner-beta artifact and in-place install

Source authority `94115ebab01617bc835c66be5475399e1e6c8343` was rebuilt as a fresh generic iPhoneOS Debug product after the retained `/private/tmp` artifact was lost on restart. Xcode automatic signing could not resolve the already-installed profile, so the accepted existing profile `0ca6b024-cbba-41ba-a926-bb7f2698eaaa` and existing Apple Development identity `75B6694F0E1F34ABD09802F4726D5DC23A8BF95A` were used for the established manual signing path; no certificate, profile, portal, or project configuration changed. Strict deep verification passed. Bundle/version/build are `com.sabastine.stylematchai`, `1.8` / `18039`; Team is `ZV4P3Z2QLA`; development APS, Sign in with Apple, and CloudKit `iCloud.com.sabastine.stylematchai` entitlements are present. The compiled Debug endpoint is the dedicated `stylematch-18039-friends-dm-staging` host, whose health identity is `build-18039-style-friends-dm-staging`.

The durable signed artifact is stored at `/Users/sabastineesisorigho/Documents/Codex/Evidence/BUILD_18039_CURRENT_HEAD_94115ebab_20260814/StyleMatchAI.app`; executable SHA-256 is `04586e40625b103477756a07b3c9a0678ed2837683c7234ab5978cf0512b33ef`. It was installed in place—without uninstalling or deleting app data—only to the confirmed wired iPhone 17 Pro Max UDID `00008150-000C18E81AD8401C` (CoreDevice `3BAD6F82-5382-5968-AB33-C43E585A573F`) and launched. Device inventory confirms `StyleMatch Pro`, `com.sabastine.stylematchai`, version/build `1.8` / `18039`. Physical feature acceptance remains owner-pending.

### 2026-08-14 — Physical launch crash artifact-signing correction

Device console evidence proved the installed app terminated at `dyld` before application startup: `StyleMatchAI.debug.dylib` was present but unsigned. The companion `__preview.dylib` was also unsigned. This was a manual-artifact packaging defect, not a source, backend, Apple-auth, Weather, Support, APNs, or feature initialization failure. Both embedded dylibs were signed using only the existing accepted identity, then the parent bundle was re-signed with the existing profile entitlements. A Documents-backed `.app` copy receives Finder/FileProvider metadata that invalidates its sealed resources, so the durable authority is now the xattr-free package `/Users/sabastineesisorigho/Documents/Codex/Evidence/BUILD_18039_CURRENT_HEAD_94115ebab_20260814/StyleMatchAI-signed-verified.zip` (package SHA-256 `884d40b5e0490dbb43afd7dc234ab45d412cb1e5566efc663ad6ccab455695ce`). It extracts to a strict-verifying app; corrected executable SHA-256 is `5058879d74033e34080613ac541c2c469f038d0b5176ca0d50d92d87f01ef1be`.

The corrected artifact was installed in place only to the iPhone 17 Pro Max, preserving its app container. Device inventory confirms `com.sabastine.stylematchai`, `1.8` / `18039`; console launch reached normal keyboard-extension initialization and the process remained running beyond 30 seconds. Feature acceptance remains owner-pending.

### 2026-08-14 — Fresh current-source owner-beta update before avatar runtime trace

The current accepted Build 18039 worktree at `314ae216a78b295ecd5f5ba4e98d0ab9b8bfab67` was rebuilt as a new Debug iPhoneOS artifact using only the existing Apple Development identity and provisioning profile. Full build succeeded. The parent executable and both embedded Debug dylibs (`StyleMatchAI.debug.dylib` and `__preview.dylib`) carry the same Team `ZV4P3Z2QLA` signature; strict deep verification passed. Bundle/version/build are `com.sabastine.stylematchai`, `1.8` / `18039`; embedded profile UUID is `0ca6b024-cbba-41ba-a926-bb7f2698eaaa`; APS is development and CloudKit is `iCloud.com.sabastine.stylematchai`. Executable SHA-256: `13de427a715c33818f73906d8999d25b8852b6c5b58f1605650749a70a78d97d`.

It was installed in place only to the authorized iPhone `00008150-000C18E81AD8401C`, without uninstalling or deleting the app container. Device inventory confirms `com.sabastine.stylematchai`, version/build `1.8` / `18039`, and the new process remained running after launch. Avatar admission diagnosis remains separate: a fresh installed-app retry is required before classifying its runtime failure.

### 2026-08-14 — Dedicated 18039 General Stylist provider-boundary diagnostic

The dedicated Worker `stylematch-18039-friends-dm-staging` temporarily recorded only provider status category, bounded error category, latency, and configured model identifier for one authorized Stylist retry. It was scoped to the dedicated Build 18039 staging identity, and did not record prompts, responses, credentials, account/session identifiers, authorization headers, or provider payloads. No owner retry reached the Worker after the diagnostic deployment, so the table recorded zero rows and no provider HTTP status, error category, or latency was established.

The normal Worker was immediately restored. The empty table was removed by the paired D1 migration, and the resulting normal Worker deployment is `2e74dda9-8931-4082-94bb-424aea8c1c02`. The generic client-visible 502 mapping remains a provider-boundary symptom, not evidence of a particular provider auth, model-access, timeout, network, or response-parsing cause. No iOS source, model, endpoint, key, prompt architecture, or production Worker was changed.

### 2026-08-14 — CoreSimulator XPC host-tooling incident

On macOS `26.5.2 (25F84)` with Xcode `26.6 (17F113)` and `/Applications/Xcode.app/Contents/Developer`, first-launch checks are complete and no Xcode component repair is pending. Nevertheless, `CoreSimulatorService` and `simdiskimaged` are launchd-running while their XPC connection invalidates before runtime/device-set discovery. `simctl` reports runtime discovery failure and the iPhoneOS asset-catalog phase fails with `supportedRuntimes=[]`. This is classified as `CORESIMULATOR_XPC_INSTABILITY`, not a StyleMatch source, signing, entitlement, provisioning, or asset-catalog defect. No destructive simulator action or source workaround was taken. Sanitized evidence and an Apple Feedback draft are preserved under `/Users/sabastineesisorigho/Documents/Codex/Evidence/HOST_TOOLING_CORESIMULATOR_XPC_20260814/`. Fresh iOS builds/installations remain host-blocked; backend-only work may continue independently.

### 2026-08-14 — Current AI-processing consent discoverability and authority repair

Physical General Stylist diagnosis established that the dedicated Worker received the request, the account-session gate passed, and the Worker returned `403 aiConsentRequired` because the account did not hold the current server consent version `2026-08-13.ai-processing.v3`. The pre-existing Profile route was buried as **AI Transmission Privacy** and its disclosure only wrote a device-local UserDefaults record using the obsolete `2026-08-08.ai-transmission.v2` version; it could not satisfy the account-scoped Worker gate.

Build 18039 now exposes **AI Processing Consent** in Profile → Your Privacy and **Review AI Consent** directly on the Stylist failure row. Agree & Continue first reads the current version from `/v1/account/ai-processing-consent`, records explicit authenticated acceptance to that endpoint, verifies the valid response, and only then writes the local decision and resumes the captured request. A failed remote record leaves consent fail-closed and shows a customer-safe retry message. The transport maps chat HTTP 403 to the direct consent action rather than the generic Stylist-provider error. No consent is auto-accepted, no account identifier is accepted from UI state, and no prompt, token, image, AI Memory, or secret is sent by the new consent flow.

Focused SwiftPM consent/disclosure contracts passed 2/2. The broader `StylistChatServiceTests` suite compiled the changed source and had one pre-existing unrelated `testMismatchedScanFailsClosedWithoutChangingScreenContextAuthority` assertion failure (`unavailable` vs `available`). A fresh unsigned generic-iPhoneOS Debug build succeeded. Signing, in-place installation, explicit owner acceptance, and one physical General Stylist response remain pending.

The validated current source was packaged in `/private/tmp/stylematch-18039-ai-consent-manual-signed/StyleMatchAI.app` because Xcode could read but did not register the existing capability-complete profile. The artifact uses only the existing Apple Development identity and profile; both embedded Debug dylibs were signed before the parent bundle, and strict deep verification passed. Executable SHA-256: `45a691ea2cc76b8ba742db3de941aa5111e4a39954c3fe9ebd39e055e4f911e5`. It was installed in place—without uninstalling or deleting data—only to `00008150-000C18E81AD8401C`. CoreDevice confirms `com.sabastine.stylematchai`, version/build `1.8` / `18039`, and launch was requested successfully. Explicit owner consent acceptance and one physical General Stylist response remain required.

### 2026-08-14 — Support data-consent action and saved-message repair

Physical Support Chat correctly reached the account-scoped current-consent gate (`aiConsentRequired`) but exposed only explanatory text. The existing authority remains unchanged: current version `2026-08-13.ai-processing.v3`, authenticated `GET` then `POST /v1/account/ai-processing-consent`, with the Worker response required before the device-local marker is written.

The Support Chat consent state now exposes **Review Support Data Consent**. Its disclosure limits the stated Support request to the question plus bounded app diagnostics; it states exclusions for private messages, image bytes, Profile details, Closet, Scan content, AI Memory, precise location, account identifiers, and session tokens. It uses the existing account-scoped consent API and does not auto-accept or auto-send. The blocked support question remains locally preserved; after explicit successful acceptance, the owner must intentionally select **Send Saved Question**.

Focused SwiftPM Support consent contracts passed 3/3, and the existing Support source contract passed 1/1. Fresh iPhoneOS build and physical acceptance remain pending the host tooling gate. No Support Worker, provider credential, runtime flag, consent version, or backend data flow changed; `PRIVACY_POLICY_REVIEW = NOT_REQUIRED` because the data flow and consent authority were not broadened.

### 2026-08-14 — Support Chat response accepted; composer and transcript polish

Physical owner evidence now confirms a successful AI Customer Service response after explicit current consent acceptance. This reclassifies the Support provider path as **physical response PASS**; no provider, model, credential, Worker, or runtime diagnosis was reopened.

The client previously passed the draft to `model.ask` without clearing it and had no first-class transcript for the submitted question. Support Chat now creates an immutable local outgoing entry only after nonblank eligibility and the single in-flight guard pass, then clears the composer immediately. It keeps the customer question and successful assistant answer in the current Support-chat session; failed messages remain as one failed entry and retry that entry rather than the empty composer. Consent-blocked messages remain unsent until explicit acceptance and an explicit send action. The view scrolls to the newest state, retains multiline entry, keeps 44-point actions, and has accessible labels; no new server-side conversation storage was introduced.

Focused SwiftPM Support composer/consent contracts passed 6/6; the existing Support source contract passed 1/1; `git diff --check` passed. Fresh build/install and physical composer/consent retest remain blocked by the separate host tooling incident. No consent text or data flow was broadened, so `PRIVACY_POLICY_REVIEW = NOT_REQUIRED`.

### 2026-08-14 — Pre-restart preservation authority

Build 18039 preservation is restart-safe: accepted Support consent UX is committed at `4c47a825bdc6a3f3eac184751b6dcbb109d7db32`; Support composer lifecycle is committed at `3ad2080ee10d1f14d0c0be41165444da847eaa7c`; the semantic canonical Worker reconstruction is `f32ff3a1dcf10ad7cc80e9d50edfdf41e504e76d`; isolated shadow validation is `ba56b5a5afca39395d0d0344e6aef55cbceb22a6`; and candidate-provider gating is `a25bf12f6b68e9108497ae066906c29559323eea`. The current iOS adaptive-avatar/Stylist-consent overlay and dedicated-backend avatar/diagnostic overlay are intentionally uncommitted and are preserved by durable SHA-256-verified evidence patches before restart. The private-master/derivative avatar architecture remains unimplemented and unapproved; the currently installed app has the earlier 2048px/6MB preparation, while adaptive fashion-quality preparation remains source-only.

The active `stylematch-18039-friends-dm-staging` Worker is frozen: historical deployed provenance is not byte-exact, canonical candidate validation is not fully provider-backed, and no `wrangler deploy` is authorized until a future separately approved manifest-backed deployment. Fresh iOS build/install remains blocked solely by the documented CoreSimulator/simdiskimaged XPC host incident. No secrets are included in this record.

### 2026-08-14 — Build 18039 Style Friends premium navigation source redesign

Governing decisions: ADR-003 (single typed client authority), ADR-006 (privacy boundary), and ADR-007 (append-only provenance). The cramped system `Picker` menu was presentation-only: it derives a narrow intrinsic popover from multiword labels, causing wrapping and inconsistent row rhythm on the physical iPhone. It is replaced with a dedicated SwiftUI social-navigation sheet and a compact selected-section trigger. The exact five existing `Section` cases, local selection binding, navigation destinations, service/session authority, DM, moderation, privacy, and backend contracts are preserved.

The sheet supplies generous 52-point rows, consistent 28-point icon geometry, selected-state clarity, accessible labels/hints, and Dynamic Type adaptation that permits two lines only at accessibility text sizes. The trigger uses the existing profile surface/material styling and the sheet has no provider, route, account, or private-data behavior. A focused source contract passed 1/1. The broader Style Friends suite exercised 78 tests: 74 passed, one disposable integration test skipped, and three existing unrelated assertions failed (`APNs token lifecycle`, `Profile routes`, and `profile/notification compact presentation`); none were changed by this UI-only work. A second unsigned iPhoneOS compile could not begin because the known CoreSimulator/simdiskimaged XPC host incident recurred. No signing, installation, iPad, Worker, or backend action occurred. Physical acceptance requires a new signed 18039 owner-beta binary and owner review.
### 2026-08-14 — Build 18039 reproducible owner-beta source authority

Decision ID: `BUILD18039-OWNER-BETA-SOURCE-AUTHORITY`. Governing decisions: ADR-003 (one typed client/runtime authority), ADR-006 (privacy and consent boundaries), and ADR-007 (append-only provenance). The preserved base `f507a7f79d95df1fad974e84b7299437de9ba6aa` plus the accepted overlay `ios-current-dirty-overlay-f507a7f-20260814-1345.patch` were reconstructed in a dedicated owner-beta worktree. The overlay SHA-256 is `79147b0ff3778f2945742e55ee1126e14088605f9d38b9b7cf1553a8c3e236b7` and the reconstructed staged diff reproduces that same SHA exactly.

The authority includes the approved adaptive avatar preparation, Style Friends profile/DM changes, explicit account-scoped AI-processing and Support-data consent actions, Support composer/transcript lifecycle, General Stylist composer duplicate-send and draft-clearing behavior, and their focused source contracts. It preserves existing Weather/Stylist, notifications/APNs client, and privacy boundaries; no Worker, credential, device, signing, or runtime state changed. This checkpoint is source-only and is the sole accepted source authority for the `iphone-18039` installer lane; a fresh build/sign/install still requires separate authorization.

### 2026-08-14 — Style Friends premium navigation final polish

The accepted custom sheet remains the presentation authority; it was not redesigned. Its trigger, icon treatment, selected state, outline, and subtle header material now use the existing resolved Profile palette instead of the unrelated global system accent. Normal-size sheet height is reduced to 382 points with five 52-point rows and tighter spacing; accessibility Dynamic Type uses the large detent and retains the two-line adaptation. The five existing local destinations, selection binding, dismissal semantics, VoiceOver labels/hints, session authority, DM, moderation, and backend contracts are unchanged.

Focused navigation contract passed 1/1 and a fresh unsigned generic-iPhoneOS Debug build passed. The broader Style Friends suite again executed 78 tests with one opt-in fixture skipped and the same three unrelated pre-existing failures (`APNs token lifecycle`, `Profile routes`, and `profile/notification compact presentation`); the navigation contract passes within that suite. A new signed artifact and physical owner review are intentionally pending separate authorization.

### 2026-08-14 — Premium Notifications settings source redesign

The Notifications surface was a client-only hierarchy defect: the previous `Form` gave iOS permission, device registration, and every preference equal, oversized visual weight. It also always offered device registration after permission was allowed, even when the coordinator already reported `registered`. The redesign retains the existing staged `StyleFriendsNotificationPreferencesDraft` save contract and the same native toggles, but presents a compact permission status card, truthful device-registration card, grouped Friends and Activity preferences, concise descriptions, and an expandable privacy explanation. The registered state now says **This iPhone is registered** and intentionally has no registration action; idle and failed states expose bounded register/retry actions only when permission allows them.

Save remains required because preferences are staged. Save is disabled until there is a draft change, while Done asks the owner to keep editing or explicitly discard unsaved changes. APNs registration, authorization requests, token handling, Worker/provider configuration, delivery semantics, and preference payload meanings are unchanged. Focused SwiftPM notification/persistence contracts pass 4/4 and `git diff --check` passes. The unsigned app build was started with signing disabled; SwiftPM directly compiled the changed screen, while the separately recurring CoreSimulator/Xcode instability prevented recording a completed full-build result in this task. No signing, device install, iPad action, Worker mutation, or secret change occurred. Physical review remains `PENDING_NEW_BINARY`.

The reproducible checkpoint archive is stored under `/Users/sabastineesisorigho/Documents/Codex/Evidence/BUILD_18039_NOTIFICATIONS_PREMIUM_20260814/`; its exact source SHA-256 is recorded alongside the archive. The protected `iphone-18039` installer lane resolves the accepted notifications source checkpoint with `SOURCE_BUILD_AUTHORIZED=NO` and no active signed artifact manifest; a fresh build/sign artifact requires separate owner authorization.

### Build 18039 — Home Intelligence typed authority (2026-08-15)

- **Status:** Source candidate pending signed iPhone owner-beta artifact and physical acceptance.
- **Scope:** Replaced the generic Home detail-card route with a shared typed authority for Weather, Calendar, Outfit Checklist, Laundry, Missing Pieces, and Shopping.
- **Truthfulness:** Uses WeatherKit snapshots, sanitized/consented Calendar projections, and saved-Closet/shopping evidence only. Missing saved data is not treated as a customer fact or ownership claim; laundry status remains unknown without actual wear/care evidence.
- **Stylist:** Each detail produces a bounded, customer-visible typed snapshot via the existing root Stylist presentation authority; no new server contract or client secret is introduced.
- **Validation:** Home Intelligence semantic tests 4/4 PASS; Home Engagement navigation test 1/1 PASS; unsigned generic-iPhoneOS Debug build PASS. Full legacy SwiftPM suite has 34 unrelated pre-existing failures and is not an acceptance gate for this isolated candidate.
- **Isolation:** Build 18037, Build 18038, Worker, backend, and artifact authorities are unchanged. Controlled backport to Build 18038 is forbidden until owner physical acceptance of this Build 18039 candidate.

### Build 18039 — Home Intelligence customer-usefulness gate (2026-08-15)

- **Status:** Updated source candidate pending fresh signed iPhone artifact and owner physical acceptance.
- **Customer value:** Each Home Intelligence workspace now exposes what is known, why it matters today, and ranked next actions. Unknown saved-Closet states recover through Closet, Scan, typed Stylist advice, or optional Shop instead of ending in an unhelpful list of unknowns.
- **Shop context:** Opening Shop from Home publishes the existing bounded Home snapshot without presenting a second overlay; the current Weather/occasion/gap/profile context is ready for the existing Shop Stylist entry without duplicating customer input.
- **Layout safety:** Home detail actions reserve clearance for the global floating Stylist button. The button remains the only interactive overlay control; no root hit-testing or navigation model changed.
- **Validation:** Home Intelligence semantic/recovery tests 5/5 PASS; Home navigation test 1/1 PASS; unsigned generic-iPhoneOS Debug build PASS.
- **Isolation:** Build 18037, Build 18038, Worker, backend, and accepted artifacts remain unchanged. No controlled 18039-to-18038 backport is authorized before physical owner usefulness acceptance.

### Build 18039 — Home action routing and Calendar intelligence repair (2026-08-15)

- **Scope:** 18039 owner-beta only. Home action cards now call the existing root tab-selection authority rather than assigning a tab directly, so the destination is mounted before the action is presented. Each rendered action has a 52-point minimum target, constrained content shape, stable accessibility identifier, label, and rationale hint. The existing typed Stylist and Shop handoffs remain unchanged.
- **Calendar:** `NSCalendarsFullAccessUsageDescription` and the iOS 17 `requestFullAccessToEvents()` path are present. Home now observes `EKEventStoreChanged` and refreshes a local, bounded 14-day projection of up to three relevant events. Local title classification supports birthdays, anniversaries, holidays, work, appointments, travel, dinner/date, weddings, concerts/shows, celebrations, and ceremonies. Only category, time bucket, bounded duration, all-day flag, and expiry reach Home/Stylist; notes, attendees, location, URL, identifiers, and raw titles remain excluded.
- **Consent:** Calendar remains opt-in through the existing Profile → Calendar Context consent explanation; Home’s Connect Calendar action opens that existing customer-controlled flow. No Calendar permission request runs at launch.
- **Isolation:** No Build 18037/18038, Worker, backend, profile capability, or production authority changed. Physical acceptance requires a new 18039 signed iPhone candidate.

### Build 18039 — Calendar runtime-diagnostic correction (2026-08-15)

- **Status:** Source candidate pending signed iPhone owner-beta artifact and physical owner retest.
- **Root cause addressed:** The former recognized-only title classifier could drop every valid EventKit event whose title did not match a fixed category keyword, thereby conflating an unrecognized accessible event with no event. The Home and Stylist projections also used inconsistent look-ahead windows.
- **Repair:** EventKit queries explicit visible event calendars through one device-calendar/time-zone-aware 21-day range. A valid, nonblank, future event with no specific category now projects as privacy-minimized `otherSignificantEvent`; expired and blank-title events stay distinct aggregate rejection reasons. All-day and recurring state are retained only as minimized facts.
- **Runtime proof path:** Debug-only Build Information reports authorization and query state, visible-calendar count, bounded window, aggregate event lifecycle counts, and aggregate rejection reasons. It contains no title, calendar name, attendee, location, note, URL, identifier, or event payload.
- **Validation:** `CalendarContextServiceTests` 6/6 PASS; Home Intelligence semantic contracts 8/8 PASS; unsigned generic-iPhoneOS Debug build PASS; `git diff --check` pending final checkpoint verification.
- **Isolation:** Build 18037, Build 18038, Worker, backend, production authority, and protected artifacts remain unchanged. A controlled 18038 backport is explicitly deferred until the owner physically verifies this 18039 runtime fix.

### Build 18039 — Release configuration authority repair (2026-08-15)

- **Status:** Source checkpoint; fresh signed owner-beta artifact and physical Calendar retest remain pending.
- **Root cause:** `approvedFriendsStagingAPIHost` was correctly Debug-only, yet Release-compiled request validators in DM, Support, and development APNs referenced it directly. This made Release fail to compile even though the Release xcconfig disables the relevant runtimes.
- **Repair:** `AppBackendConfiguration.isAuthorizedFriendsStagingHost(_:)` is the sole owner-beta host predicate. Debug accepts only the dedicated 18039 staging host; Release always returns `false`. DM, Support, Notifications, and the owner-acceptance endpoint use the predicate, removing direct staging-host comparisons from Release-compiled paths.
- **Isolation:** Release xcconfig remains production-host only and explicitly disables DM, Support, social-image, and APNs runtime authorities. No raw secret, client API key, production fallback to staging, Worker mutation, or endpoint configuration change was introduced.
- **Validation:** focused canonical-authority and Debug/Release-isolation tests 2/2 PASS; unsigned generic-iPhoneOS Debug PASS; unsigned isolated generic-iPhoneOS Release PASS; `git diff --check` PASS.
- **Lane protection:** Build 18037 and Build 18038 source/artifact authorities, devices, Worker/backend, and production state remain unchanged.

### Build 18039 — DM photo transport, composer layout, and public-name refresh (2026-08-16)

- **Physical evidence:** The installed owner-beta reported “Photo attachment not sent,” compressed the Send label vertically with the keyboard open, and retained a historical public display name in an active chat header. The previously accepted failed-send ownership state remained correct: the text draft was not duplicated.
- **Photo repair:** `PhotosPicker` data is decoded and deterministically normalized to an actual bounded JPEG before the photo attachment route is called. This aligns the bytes with the declared `image/jpeg` contract and its 5 MiB client/Worker maximum. Privacy-safe Debug owner diagnostics identify picker load, normalization, request/auth, HTTP, response decode, inferred R2 commit after `201`, finalization, message link, and rendering without recording private data.
- **Presentation repair:** The composer gives the text field flexible priority while keeping Send horizontally fixed and readable. Active chat refresh fetches the accepted friend’s authenticated public social profile after the server conversation projection, so a stale navigation/conversation snapshot cannot override the current public name or avatar.
- **Validation:** focused iOS contracts 4/4 PASS; Worker attachment/profile contracts 5/5 PASS; Swift parse PASS; unsigned generic-iPhoneOS Debug build PASS; `git diff --check` PASS. No Worker source or deployment change was required: the existing dedicated staging attachment route and bindings are contract-tested.
- **Physical follow-up:** Install this exact client checkpoint, send one photo once, and verify the bounded Debug stages plus send/retry behavior, horizontal composer with keyboard, Friends/Conversations/header/View Social Profile name convergence, and relaunch persistence. Build 18037, Build 18038, Worker deployment, staging data, and production remain unchanged.
## 2026-08-18 — Retry-safe private share delivery (owner-beta recovery)

- Kept the text draft, photo bytes, share snapshot, and reply selection visible until the Worker confirms the complete handoff.
- Added a stable local `client_share_ref` to the snapshot transport contract and retained it through send, snapshot, and association retries.
- Added an explicit `createShare` recovery phase so an already-canonical message can resume the attachment handoff without issuing a second text send.
- Verification: focused `StyleFriendsFoundationTests/testDirectMessageComposerKeepsAnUnsentDraftVisibleAndFocusable` passed; fresh unsigned iPhoneOS Debug build produced `StyleMatchAI.app`.
- This is not physical acceptance: the compatible idempotent Worker contract and Current Scan/Score entry point remain outstanding.
## 2026-08-18 — Weather current-condition animation repair

- Fixed the live WeatherKit presentation path so rain, drizzle, snow, and thunderstorm risk derive from the same freshly received WeatherKit observation instead of being reclassified as stale during later rendering.
- Preserved the fail-closed boundary: persisted or non-live weather still yields no current-condition animation.
- Verification: `WeatherConditionAnimationTests` 6/6 passed.

## 2026-08-19 — Current Scan/Score → Style Friends local source checkpoint

- Added the local Current Scan/Score sharing flow: completed-result eligibility, immutable transient snapshot authority, authenticated destination selection, preview/note validation, retry-safe message/share handoff, and recipient classification compatibility.
- Snapshot classification is the canonical completed-result `effectiveCategory.rawValue`; legacy four-field snapshots omit it and unknown future values remain unavailable rather than remapped.
- The retry-safe coordinator retains the frozen destination, image, score, classification, summary, note, message reference, and share reference until canonical success. It has no Saved Scan, Scan History, CloudKit, Cloud Sync V2, importer, or reconciliation write path.
- App-hosted verification passed: full `StyleMatchAI-Tests` scheme with zero test failures; focused current-share suite 12/12; smoke test 1/1; unsigned simulator and generic iPhoneOS builds passed.
- SwiftPM completed 1,608 tests with 33 failures and one skip, matching the recorded baseline count. These pre-existing release blockers remain unwaived; no feature-scoped failure was observed.
- No Worker modification, deployment, signing, installation, or physical-device acceptance occurred.

## 2026-08-19 — SwiftPM reconciliation and local reaction acceptance

- Reconciled all 33 active SwiftPM assertions without changing production source: current source-contract expectations now cover Build 1.8039 identity, strict opaque references, exact-image scan reuse, observed-precipitation-only weather guidance, fail-closed Stylist context, and the current accessibility/Cloud Sync contracts.
- Added direct app-hosted proof that a canonical successful saved-scan share leaves the saved-scan and scan-history representations unchanged and invokes no scan-persistence-adjacent collaborator.
- Added canonical reaction refresh/relaunch coverage. The local Worker’s disposable D1 fixtures prove authenticated two-account add/change/remove, server-derived projection, account isolation, blocked/deleted rejection, and cleanup.
- Final local verification: SwiftPM 1,608 executed, 0 failed, 1 repository-authoritative environment skip; app-hosted scheme 15/15; focused current-share suite 14/14; unsigned simulator and generic iPhoneOS builds passed.
- No deployment, signing, installation, remote D1/R2 access, Worker source change, or physical-device acceptance occurred.

## 2026-08-21 — Permanent WeatherKit attribution contract

- A single registered `WeatherAttributionSurface` contract now covers Home, Weather Styling, Hourly Forecast, 10-Day Forecast, scan-weather guidance, Closet weather guidance, AI weather guidance, and weather chat. Future Apple Weather surfaces must register a surface and use the shared component.
- The shared component renders only the Apple-provided `combinedMarkLightURL` / `combinedMarkDarkURL` selected for appearance and links only to `legalPageURL`. The prior plain provider-name fallback was removed; unavailable attribution fails closed rather than displaying Apple weather data unattributed.
- Regression coverage verifies runtime URL provenance, light/dark selection, legal-link usage, accessibility labels, no constructed Apple logo/text fallback, and every registered weather surface.
- Local verification: focused WeatherKit class 430/430, complete SwiftPM 1,615 executed / 1 skipped / 0 failed, app-hosted 17/17, unsigned simulator and generic iPhoneOS builds PASS. Simulator WeatherKit service calls remain blocked by the unsigned simulator entitlement state; physical later-candidate evidence remains required.
- This is a source-only WeatherKit checkpoint. SIWA, Worker, Cloudflare, production, physical devices, signing, and TestFlight remain unchanged.

## 2026-08-21 — Build 18042 deliberate local cross-lane integration

- Integrated the accepted Ask StyleMatch V2 iOS privacy/core/UI contract with the accepted 18041 WeatherKit/precipitation and notification baseline, without rewriting any protected 18039–18041 or 18040 lane.
- The paired Worker integration retains legacy `/v1/chat` behavior and adds the versioned V2 admission flow: consent-scoped validation, account-scoped idempotency, additive migration `0039_ask_stylematch_v2_admissions`, provider `store: false` / `background: false`, and no plaintext prompt/response persistence.
- The signed-build Support Chat authority repair remains allowlist-, shared-session-, consent-, and moderation-gated; it is not compiler-mode gated.
- Local verification: focused Intelligence Core 10/10; focused Support authority 1/1; complete SwiftPM; Worker typecheck; Worker suite 310/310 including V2 fresh/upgrade/legacy coverage; app-hosted XCTest; unsigned iPhone 17 simulator and generic iPhoneOS builds; diff checks and secret scan clean; strict fsck clean apart from pre-existing unreachable objects.
- This is an integration checkpoint only. No Build 18042 number was assigned; no signing, archive, install, deployment, Cloudflare, D1/R2, App Store Connect, TestFlight, or production action occurred.

## 2026-08-21 — Build 18042 OwnerBeta signed-candidate configuration

- Added a separate `OwnerBeta` configuration and shared archive scheme to the isolated Build 18042 candidate lane. Debug and Release configurations are unchanged.
- OwnerBeta is Release-like (`wholemodule` compilation, optimized device build) but uses development signing and the approved owner-beta staging host `https://stylematch-friends-staging.sabastine-7000.workers.dev`.
- The embedded integration-source marker remains `58ee70ab4829e24b2a488c66b15d780c9a5d2a7b`; it is intentionally distinct from the later configuration checkpoint that records this build-only setup.
- OwnerBeta enables only the separately approved staging runtime authorities for shared session, Ask StyleMatch V2, Style Friends, profile/avatar, notification preferences, Support Chat, and bounded diagnostics. Release remains `https://api.stylematchpro.com` with those staging authorities disabled.
- Local verification: focused OwnerBeta configuration tests 4/4, complete SwiftPM, app-hosted XCTest 20/20, unsigned OwnerBeta simulator and generic-iPhoneOS builds, diff check, changed-file secret scan, and strict fsck passed. The exact integrated Worker remains unchanged and its existing 310/310 evidence remains tied to `a6af5c114a1d1715977c3ce99c36eba23bfcf3bf` / lockfile `ed849684912ccaf7d6543ad5ff891108c4c98750e7889e9f6833b5b3baa5e341`.
- No Worker deployment, device operation, App Store Connect/TestFlight upload, production mutation, or Apple sign-in occurred.

## 2026-08-21 — Build 18043 local Friends Feed, notification, and Support integration

- The OwnerBeta-only iOS lane contains authenticated Friends Feed loading, explicit empty/retry/refresh/pagination states, server-authorized social-image loading, post publishing/deletion, reactions, comments, purchase questions, and canonical relationship remove/block refresh. It keeps private Scan, Closet, Profile, location, and AI Memory data out of Feed projections.
- The notification request preserves the `dm_enabled` contract and backwards-safe decoding; historical profile/avatar transfer remains prohibited because opaque account ownership did not match. Current-account profile/avatar acceptance remains physical-gated.
- Local evidence: full SwiftPM **1,634 executed, 1 skipped, 0 failures**; app-hosted XCTest **20/20 PASS**; unsigned OwnerBeta simulator and generic iPhoneOS builds PASS; `git diff --check`, changed-file secret scan, and strict fsck PASS. No signing, archiving, installation, deployment, D1/R2 mutation, Support enablement, or physical acceptance occurred.

## 2026-08-22 — Build 18043 OwnerBeta authority boundary hardening

- Debug no longer embeds the owner-beta staging endpoint or any Style Friends, Feed, Support, social-image, or APNs runtime authority. OwnerBeta remains the sole staging-authorized configuration; Release remains production-hosted and fail closed for those authorities.
- The corresponding source-contract tests verify Debug is inert, OwnerBeta retains the exact approved staging authorities, and Release remains disabled. The change does not alter Worker routes, credentials, data, device state, or feature behavior.
- Validation: focused Foundation contracts 93 executed / 1 repository-authoritative skip / 0 failures; complete SwiftPM 1,634 executed / 1 skipped / 0 failures; app-hosted XCTest 20/20; unsigned OwnerBeta simulator and generic iPhoneOS builds PASS; high-confidence secret scan and `git diff --check` PASS. Strict fsck reported only pre-existing unreachable objects.

## 2026-08-22 — Build 18043 OwnerBeta physical-candidate identity

- Isolated OwnerBeta descendant for owner-beta physical acceptance only: marketing version `1.8`, build `18043`, source marker `c7754270f8962f6faa3710ccf4f6e65ebc6f4725`. Release is unchanged.
- Local validation: SwiftPM 1,634 executed / one skip / zero failures; app-hosted XCTest passed; unsigned OwnerBeta simulator and generic iPhoneOS builds passed. No installation or App Store/TestFlight activity occurred in this source record.

## 2026-08-22 — Build 18043 Style Friends avatar size-safety repair

- Build remains `1.8 (18043)`. A missing current-account public profile is an expected precondition; the profile-photo control now directs the user to the required display-name setup rather than behaving as an inert control.
- The avatar preparation path now derives dimensions from decoded ImageIO pixel metadata, downscales before raster decoding using a 24,000,000-pixel budget, preserves aspect ratio without upscaling, re-encodes a metadata-free JPEG, and verifies the final image dimensions and raw-body size before upload.
- Application limits are 7 MiB for the client raw JPEG body and 8 MiB / 24,000,000 decoded pixels at the Worker. These are StyleMatch safety policies, not Cloudflare platform limits.
- Local evidence: focused Style Friends tests 95 executed / 1 existing fixture skip / 0 failures; complete SwiftPM 1,636 executed / 1 existing fixture skip / 0 failures; unsigned OwnerBeta generic iPhoneOS build passed; `git diff --check` passed.
- Physical acceptance remains pending. No remote, D1, R2, signing, installation, or device mutation occurred.

## 2026-08-22 — Build 18043 Style Friends avatar state and failure visibility

- Build remains `1.8 (18043)` and the embedded source marker remains unchanged. The OwnerBeta configuration test now expects the authorized marker `ed1b5d094a566c8f37faeab7e34e42fb25b6d677`; Release remains production-hosted and fail closed.
- Failed, revoked, unavailable, and unconfirmed avatar outcomes remain visible across canonical refresh instead of being silently represented as a missing photo. The retry flow uses only the in-memory selected Photos picker item.
- Local evidence: configuration test 1/1; focused avatar tests 6/6; complete SwiftPM 1,638 executed / 1 skipped / 0 failures; unsigned generic iPhoneOS OwnerBeta compile and `git diff --check` passed.
- No Worker, D1/R2, signing, archive, device, external AI, or remote mutation occurred. Physical avatar acceptance remains separately required.

## 2026-08-22 — Build 18043 avatar-persistence OwnerBeta installation

- Signed OwnerBeta artifact from source checkpoint `4c9891cced7221d8b0d5f6995f446c21f0684652`, with embedded source marker `400cd982f9cc16df3352f61c6d9430bdbcc1b0d5`, was installed in place on the authorized owner iPhone only. Bundle identity and installed version remained `com.sabastine.stylematchai`, `1.8 (18043)`.
- Archive verification passed: strict codesign, embedded-profile CMS decode, target-device profile membership, staging endpoint, Team ID, Sign in with Apple, WeatherKit, and development APNs entitlements.
- Owner-confirmed saved-scan preservation baseline is 9. No scan, sign-in, environment, iPad, Worker, D1/R2, or profile migration action occurred. Avatar physical acceptance remains pending owner action.

## 2026-08-22 — Build 18043 avatar upload physical failure boundary

- Owner physical acceptance selected one avatar: a temporary preview appeared, but the canonical view later displayed “Photo upload did not complete. Your active photo was not changed.” The owner did not press Retry. Saved scans remain 9 and the current public profile name, bio, and styles remain present.
- The displayed text is the generic catch at `StyleFriendsView.swift:780-783`. It proves an error during the avatar POST/decode sequence, but does not by itself distinguish a missing session/unsent request, transport error, non-accepted HTTP response, or accepted-response decoding failure. It is not the canonical-refetch or authenticated-image-read failure state.
- The active owner-beta Worker version metadata has the approved D1/R2 binding names, but lacks the required dedicated social-image moderation/policy binding names and the redacted avatar-diagnostic authority. The Worker source therefore fails closed at image-safety admission before R2 or D1 avatar-reference persistence whenever that path is reached. Retained evidence cannot prove the exact status or stage of this single prior attempt because no durable per-attempt trace was enabled.
- No retry, source change, direct D1/R2 write, deployment, or device mutation occurred during this diagnosis. A separate, explicit staging-only authorization is required to prepare verified redacted diagnostic capture and repair the missing moderation configuration before one owner Retry attempt.

## 2026-08-23 — Build 18043 transient Style Friends profile refresh repair

- The Style Friends profile UI now treats an authoritative canonical `nil` response as the only route to the current-account “create profile” state. Loading, session, transport, and unrelated concurrent-refresh failures preserve the already-known canonical profile and draft fields instead of presenting a false profile-missing state.
- The repair retains the existing shared session, profile/avatar ownership, validation, and truthful error paths; it does not alter the source marker, Worker, D1/R2, signing, archive, installation, device, or remote state.
- Local validation against this exact source repair: focused `StyleFriendsFoundationTests` 105 executed / 1 existing skip / 0 failures; complete SwiftPM 1,646 executed / 1 existing skip / 0 failures; unsigned OwnerBeta generic iPhoneOS build PASS; `git diff --check` PASS.
- Physical avatar acceptance and the separately diagnosed staging image-safety configuration blocker remain pending and are not claimed as resolved by this source-only checkpoint.

## 2026-08-24 — Build 18043 fact-only AI Stylist context (local only)

- `StylistContextBuilder` is the sole production authority selecting Stylist contextual facts. `OpenAIStylistClient` now consumes its canonical output through the authenticated StyleMatch Worker transport and no longer independently selects profile, Closet, Saved Scan, or memory fields. Historical ancestry for the already-accepted builder is waived and disclosed; current-source uniqueness and live-consumer tests passed.
- Added a read-only, non-serializable Saved Scan fact projection and a matching Closet projection. They use only already-decoded authoritative fields, expose no image-bearing field, metadata, confidence value, account identity, or storage key to the network, and do not alter storage format, writes, migration, retention, sync, score, or palette detection. Only a confident stored palette is available; all other confidence states omit it.
- Fact selection is explicit per send and account-scoped consent defaults denied until the authenticated Worker returns current state. Local scan keys become request-scoped aliases before serialization; stale, deleted, inaccessible, or unconsented selections fail closed without a latest-scan fallback. Ordinary context-free chat remains unchanged.
- Local validation: focused Swift tests 209/209; full SwiftPM 1,651 executed / 1 existing skip / 0 failures; unsigned generic iPhoneOS OwnerBeta build; diff and privacy/path audits PASS. No image egress, Worker deployment, D1/R2 write, secret access, device action, or avatar/source-marker change occurred.

## 2026-08-24 — Build 18043 fact-only context finalization correction (local only)

- Corrected the final fact-context boundary so no selected attachment preserves the existing context-free `/v1/chat` path, while an unavailable, unauthorized, malformed, oversized, or stale explicit selection fails closed without clearing the customer’s local selection. Known-empty source lists, no selection, and assembly failure now remain distinct UI states.
- The canonical authority is now the concrete `StylistContextBuilder`; `PersonalizationContextBuilder` is its compatibility alias. It validates request-scoped aliases, encodes scan dates as ISO-8601 strings required by the Worker, rejects over-limit fields/items/bytes instead of truncating, and keeps the 24 KiB fact-context limit client-side.
- Selected facts render beside the composer as individually removable chips. Selection clears only after an accepted send, account/conversation change, or relaunch; local record keys, images, palette confidence, and persistence metadata remain absent from serialization.
- Red-first evidence preserved for the prior non-ISO scan-date encoding. Final validation: focused Swift 211/211; full SwiftPM 1,653 executed / 1 existing skip / 0 failures; unsigned OwnerBeta generic iPhoneOS build, Worker suite 327/327, Worker typecheck, privacy/path audit, and `git diff --check` PASS.

## 2026-08-24 — Build 18043 semantic iOS Vision V1 integration (local only)

- Added the iOS client for the accepted Worker Vision V1 contract only: `contract_version`, `request_id`, `prompt`, and allowlisted selected-image, canonical Saved Scan, Closet, and explicitly selected style-preference attachments. The preserved legacy vision patch remains provenance evidence and was not applied.
- A selected photo is decoded and re-encoded in memory as metadata-stripped JPEG before request construction. The client enforces a 5 MiB JPEG, 16 MP decoded-pixel, and 8 MiB full-wire budget. It does not serialize dimensions, filenames, paths, local record keys, consent claims, account identity, aliases, or unallowlisted properties. Empty no-photo conversations retain `/v1/chat`.
- Account-authoritative scope state remains default-off. Attachments are explicit per send, survive local/authorization/transport failure, and clear only after successful completion or account/conversation change. The request UUID is reused only for a byte-equivalent retry; vision responses and sanitized errors are bounded before UI use.
- Validation: focused Stylist suite 135/135; full SwiftPM 1,657 executed / 1 existing skip / 0 failures; unsigned generic-iPhoneOS OwnerBeta build PASS; `git diff --check`, privacy/raw-content review, and protected-file audit PASS. No Worker source, deployment, provider call, secret access, remote D1/R2 write, signing, archive, or device mutation occurred. Build 18043 remains **BLOCKED** pending separately authorized staging configuration, live-model/privacy acceptance, and device acceptance.

## 2026-08-24 — Build 18043 iOS-to-Worker JPEG byte-contract evidence (local only)

- Added a synthetic ImageIO-normalized JPEG handoff and a cross-worktree acceptance test. The test passes each exact `JSONEncoder` request byte stream, without re-encoding, to the repaired Worker Vision V1 parser for image-only, each image-plus-fact variant, and the fully combined variant.
- The test fixture is synthetic only and stored transiently under `/private/tmp`; no customer image, path, Photos identifier, or source metadata is placed in source or ledger evidence. No iOS production behavior changed in this follow-up.
- Validation: focused cross-contract test PASS; full SwiftPM 1,660 executed / 1 existing skip / 0 failures. Build 18043 remains **BLOCKED** pending separately authorized staging, provider/privacy, and physical-device acceptance.

## 2026-08-25 — Build 18043 selected-fact consent and grounded-chat repair (local only)

- The Stylist composer now maps only the currently selected attachment categories to their matching account-authoritative scoped-consent controls, reloads `/v1/account/ai-scopes` after a grant, and retains draft and selections on failure. No client scope authority, scan persistence, scoring, palette, image, or Worker Vision behavior changed.
- The fact-only Worker prompt now requires direct use of selected Scan facts: exact supplied score and band for score questions, then best-first grounded colour recommendations with at most three alternatives. It explicitly prohibits score calculation/invention and re-asking supplied facts.
- Native chat rendering removes visible raw Markdown/HTML-like markers and retains composer-safe scroll clearance. Focused iOS presentation tests 2/2, full SwiftPM 1,666 executed / 2 skipped / 0 failures; Worker full suite 327/327 plus fact-context suite 6/6; Worker offline TypeScript check and Wrangler 4.120.0 local dry-run PASS. No staging, provider, D1/R2, signing, installation, or device action occurred. Physical acceptance remains pending.

## 2026-08-25 — Build 18043 grounded-chat staging gate

- Checkpoint ancestry is verified: iOS grounded-chat work descends from preserved `94f4e7eb34f5f2519c5801fb6678109eca411a1a`; Worker checkpoint `6124d509c72ad88c2d5c342b1d9cbcc002a27af7` descends from accepted `11e01c123b34fd15ec999814c49a3ce414c829d8`. Both isolated worktrees are clean.
- Current local acceptance is PASS: unsigned generic-iPhoneOS OwnerBeta build, serial SwiftPM 1,666 / 2 skipped / 0 failures, Worker 327/327 plus 6/6 fact-context tests, TypeScript, diff checks, and Wrangler 4.120.0 dry-run.
- The 0%-traffic staging candidate was **not created**. `wrangler versions list --config wrangler.owner-beta.18042.toml --json` stopped before contacting Cloudflare because this non-interactive session has no `CLOUDFLARE_API_TOKEN`; no token was created, read, or supplied. Consequently staging traffic, D1, R2, provider calls, and rollback version remain unchanged. Device installation remains deferred by owner direction.

## 2026-08-25 — Build 18043 iOS build-identity repair (local only)

- Corrected the authoritative app-target `CURRENT_PROJECT_VERSION` in Debug and Release from `18039` to `18043`; OwnerBeta already resolved to `18043`. Marketing version remains `1.8` in all three configurations.
- This is a build-identity correction only. No Swift application feature, endpoint, Worker, persistence, score, palette, scan, Closet, consent, image, signing, device, or remote state changed.
- Compiled-bundle, simulator launch/relaunch, generic iPhoneOS, source-hash, test, diff, privacy, and Git-integrity evidence is retained with the local repair checkpoint. This record is `LOCAL ONLY — NOT STAGED — NOT DEVICE ACCEPTED`.

## 2026-08-25 — Build 18044 local intelligence V2 and credential retirement

- Active iOS provider-key entry, read/write, export, adapter, and direct-provider paths are removed. `LegacyProviderCredentialRetirement` is delete-only and clears only the historical generic-password target plus fallback preference without reading either value. The temporary marker is limited to that helper pending a later post-device-cleanup removal checkpoint.
- Local gates: V2/keychain matrix 31/31; two fresh SwiftPM runs 1,697 executed / 2 skipped / 0 failures; unsigned OwnerBeta `1.8 (18044)`; dual simulator launch/relaunch; canonical Worker suite 328/328 twice; intelligence suite 184/184; TypeScript and Wrangler 4.120.0 dry-run PASS. No remote or device mutation occurred.
- Source checkpoints: iOS `ab8eb7fc6de44417e60511907aeb8302a977f79b` (tree `db1408258de152e41aa706ecf0d91da724441ad9`) and Worker `c76d4a233de47ee8e4bc4d034111d33fb120f4b2` (tree `f39f599815a347aab879ec8126b6dd7708888ebd`). The canonical Worker command now includes a manifest guard (328 tests); the historical exact-I RED artifact remains provenance-only and is deliberately excluded from that green suite.
- Runtime configuration is fail-closed: `STYLEMATCH_INTELLIGENCE_CORE_V1_ENABLED=true` and `OPENAI_INTELLIGENCE_MODEL=gpt-5.6-terra`. No credential value was read, transmitted, or retained. This is local-only: live model-quality, staging, physical-device, and Customer Service acceptance remain pending. A later post-device-cleanup build must remove the transitional delete-only helper and its permitted marker.

## 2026-08-25 — Build 18044 final device compatibility matrix

- iPad Pro remains on StyleMatch Pro `1.8 (18043)` and must retain V1 compatibility. It is not an installation target for Build 18044.
- The only prospective Build 18044 device target is the owner iPhone 17 Pro Max, as an in-place update to `1.8 (18044)` after complete staging acceptance. No Build 18045 is created or implied.
- Build 18044 retains the exact-target delete-only Keychain retirement helper. It may run once only on the authorized iPhone after installation; it must record only the cleanup result and never read a credential value. Staging acceptance is currently blocked by the fail-closed Intelligence Core configuration mismatch, so no device action has occurred.

## 2026-08-30 — Build 18045 DM operation recovery (uncommitted local checkpoint)

- Parent preserved: `7c4ddec9f30983d01f256d55b2dc7a84fe29d73a` / `f3a4696687efeb2e020f2139b71c161b86c01ea0`. The Build 18044 Smart AI Engine is unchanged.
- Added a device-only, content-free Keychain journal and sender-scoped operation-status recovery. It records only HMAC scope/payload tags, canonical UUID, type, phase, bounded timestamps/counters, and opaque server material; it has no draft text, photo bytes, URL, raw account/thread ID, token, or AI context.
- Recovery is invoked after authenticated Style Friends session readiness; chat appearance remains a shared-coordinator fallback. Both paths are status-only and deduplicated. Confirmed logout/account deletion removes only the confirmed account/environment tag; temporary auth and network failures do not trigger cleanup.
- Focused parser PASS. New tests: `testBuild18045OperationJournalUsesDeviceOnlyKeychainQueriesAndNoPrivatePayloadFields`, `testBuild18045OperationProtocolIsPersistedBeforeSendAndLegacyPathHasNoHeaders`, and `testBuild18045RecoveryIsSessionReadyDeduplicatedAndNeverNeedsRawConversationPersistence`.
- Remaining: owner-session SwiftPM discovery/run must show all three tests beyond the 1,697 Build 18044 baseline; the unsigned iPhoneOS build is host-blocked at `actool` by the known CoreSimulator/simdiskimaged registration failure. No signing, archive, device, or remote action occurred.

## 2026-08-30 — Build 18045 retry/abandon completion (uncommitted)

- Retry now queries sender-scoped status before any resend. Only an exact `not_committed` result permits reuse of the in-memory frozen payload and original operation ID. `committed` retires the journal without resend; unknown, malformed, timeout, and old-Worker responses leave the operation locked.
- Abandon deletes only the local Keychain operation record and presentation lock. It contains no network-capable collaborator and does not send, upload, delete, recall, or query remote state.
- Current iOS patch hash: `6283229b7c69b85f8261580026e0f55c37cec98e89ea7f52e3f756807fc86b18`; journal hash: `c568bd289e171806a8e9c95d67262bd764ed0b157191262cf4d6259218b58b8c`. Swift parser and diff/integrity gates PASS. Full SwiftPM remains an owner-session gate.

## 2026-08-30 — Build 18045 focused owner-session gate blocked by host sandbox

- The three corrected behavioral journal/recovery tests were not discovered or executed in the restricted Codex session: SwiftPM failed while compiling `Package.swift` before test discovery with `sandbox-exec: sandbox_apply: Operation not permitted`.
- This is a host execution boundary, not an application test or compile verdict. Swift parsing and `git diff --check` pass locally. The exact owner-session command remains required before any full SwiftPM, unsigned iPhoneOS, Worker staging, commit, signing, archive, or device gate.

## 2026-08-30 — Build 18045 owner-session validation completed

- The normal owner Xcode/SwiftPM session supersedes the restricted-session sandbox limitation: `StyleMatch-18045-full-swiftpm.log` records 1,700 executed tests, 2 existing documented skips, 0 failures, and exit 0. It includes the three Build 18045 behavioral journal/recovery tests without reducing the accepted Build 18044 baseline.
- The generic physical-iPhone compile is also recorded as an unsigned proof only in `StyleMatch-18045-generic-iphoneos.log`: arm64 iPhoneOS, iOS 26.5 SDK, iOS 16.0 deployment target, `** BUILD SUCCEEDED **`, and `IPHONEOS_COMPILE_EXIT=0`. The temporary product is expressly not an installation artifact.
- No signing, archive, deployment, migration, traffic change, device action, or customer-data access occurred while collecting this evidence.

## 2026-08-30 — Build 18045 OwnerBeta staging identity gate failed closed

- Owner OAuth preflight confirmed the intended account and the approved OwnerBeta D1 tuple, but the live 100%-traffic Worker lacks the exact `STYLEMATCH_INTELLIGENCE_CORE_V1_ENABLED="enabled"` and `OPENAI_INTELLIGENCE_MODEL="gpt-5.6-terra"` bindings required by the committed OwnerBeta configuration.
- The generic staging D1 was not substituted. No migration, version upload, deployment, traffic action, archive, signing, device inventory, or installation occurred. A repaired, binding-parity-approved OwnerBeta staging configuration is required before this iOS commit can be signed for a physical candidate.

## 2026-08-30 — Build 18045 signed-candidate preflight blocked before archive

- The isolated iOS lane was clean at `ca36f8e81e371832f86ea2ff93c4ed51ee1f887b` / tree `d59832cc81209cc9c824dd7a5bc2ecac6a301459`; `git diff --check` and `git fsck --full --strict` passed.
- Effective `StyleMatchAI-OwnerBeta` settings resolve to bundle `com.sabastine.stylematchai`, team `ZV4P3Z2QLA`, marketing version `1.8`, but `CURRENT_PROJECT_VERSION=18044`. `Config/StyleMatchOwnerBeta.xcconfig` retains `STYLEMATCH_BACKEND_LANE = 18043 OWNER BETA PHYSICAL ACCEPTANCE ONLY`. Its staging host is the intended OwnerBeta host, but this stale lane metadata cannot prove the Build 18045 staged-backend identity.
- The preserved-Xcode `devicectl list devices` gate stopped before enumeration: `Timed out waiting for CoreDeviceService to fully initialize` (`com.apple.coredevice.devicectl error 1`). The iPhone could not be freshly identified and the iPad could not be freshly excluded.
- No archive, signing, provisioning, installation, launch, app-container access, Keychain access, Worker/staging mutation, production action, or physical-device action occurred. `PHYSICAL_OWNER_BETA_ELIGIBLE=NO`.
- Required next authorization: a deliberately scoped Build 18045 OwnerBeta build-identity/backend-lane configuration repair, followed by affected local validation and a fresh CoreDevice/device and signing preflight.
