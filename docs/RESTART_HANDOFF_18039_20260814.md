# Build 1.8039 restart handoff — 2026-08-14

## Rule of resumption

Resume from this document and the append-only ledgers, not from terminal history or chat. Do not reset, clean, restore, stash, or deploy any worktree listed below.

## Canonical worktrees

| Area | Worktree | Branch | HEAD | State |
| --- | --- | --- | --- | --- |
| iOS app | `/Users/sabastineesisorigho/Documents/Codex/Worktrees/STYLEMATCH_BUILD_18039_STYLE_FRIENDS_PREMIUM_DM_20260812` | `feature/build-18039-style-friends-premium-dm` | `3ad2080ee10d1f14d0c0be41165444da847eaa7c` | Dirty; final patch below is authoritative for the overlay. |
| dedicated backend | `/Users/sabastineesisorigho/Documents/Codex/Worktrees/STYLEMATCH_BUILD_18039_STYLE_FRIENDS_DM_BACKEND_20260812` | `feature/build-18039-style-friends-dm-authority` | `9a322e4de82645700d26c502b1a9ab104df6d12b` | Dirty; tracked patch and untracked archive below are authoritative. |
| canonical Worker reconciliation | `/Users/sabastineesisorigho/Documents/Codex/Worktrees/STYLEMATCH_BUILD_18039_WORKER_CANONICAL_RECONCILIATION_20260814` | `reconcile/build-18039-worker-candidate-validation-20260814` | `a25bf12f6b68e9108497ae066906c29559323eea` | Clean. |
| fashion-intelligence core | `/Users/sabastineesisorigho/Documents/Codex/Worktrees/STYLEMATCH_BUILD_18039_FASHION_INTELLIGENCE_CORE_20260812` | `feature/build-18039-fashion-intelligence-core` | `36a6ce614d49ac1a010535157d7d2f50ce21bde1` | Clean. |

## Accepted checkpoints

- Support consent UX: `4c47a825bdc6a3f3eac184751b6dcbb109d7db32`.
- Support composer lifecycle: `3ad2080ee10d1f14d0c0be41165444da847eaa7c`.
- Canonical semantic Worker reconstruction: `f32ff3a1dcf10ad7cc80e9d50edfdf41e504e76d`.
- Shadow validation: `ba56b5a5afca39395d0d0344e6aef55cbceb22a6`.
- Candidate-provider gate: `a25bf12f6b68e9108497ae066906c29559323eea`.

The reconstructed Worker is semantic, not byte-identical to historical live deployment authority.

## Dirty-overlay authority

Evidence root: `/Users/sabastineesisorigho/Documents/Codex/Evidence/PRE_RESTART_BUILD_18039_20260814/`.

| Overlay | Base HEAD | Durable representation | SHA-256 | Files/classification |
| --- | --- | --- | --- | --- |
| iOS tracked overlay | `3ad2080ee10d1f14d0c0be41165444da847eaa7c` | `ios-final-dirty-overlay-3ad2080.patch` | `b599412e146bed8a4c3eaf6c98de9d2fea1eff92d891ee3edd6152e1c1c8aa33` | Accepted uncommitted adaptive-avatar and AI-consent/support integration work, associated source-contract tests, plus append-only ledgers. |
| backend tracked overlay | `9a322e4de82645700d26c502b1a9ab104df6d12b` | `backend-final-dirty-overlay-9a322e4.patch` | `ed7fb914d16dbf1554bd6db576634698821cf26f1f50712bf53122fa51b7b656` | Accepted avatar/support source work mixed with in-progress diagnostic-only changes; do not commit/deploy wholesale. |
| backend untracked overlay | `9a322e4de82645700d26c502b1a9ab104df6d12b` | `backend-untracked-diagnostics-9a322e4.tar.gz` | `6ed7bb9e36dfe305b250a41ab36117a13ba0264ae8219d3b88f4320cd4c768ba` | Diagnostic-only migrations and `avatarUploadTrace.ts` / `supportChatTrace.ts`; preserve but do not deploy without a new narrow authorization. |

The initial snapshot pair (`f74a14…` iOS and `0217e3…` backend) is retained in the same evidence directory for chronology; the final snapshot rows above are the resume authority.

## Durable evidence outside `/private/tmp`

- Signed current-head package and manifest: `/Users/sabastineesisorigho/Documents/Codex/Evidence/BUILD_18039_CURRENT_HEAD_94115ebab_20260814/`.
- CoreSimulator host incident and Apple Feedback draft: `/Users/sabastineesisorigho/Documents/Codex/Evidence/HOST_TOOLING_CORESIMULATOR_XPC_20260814/`.
- Support consent archive: `/Users/sabastineesisorigho/Documents/Codex/Evidence/BUILD_18039_SUPPORT_CONSENT_UX_4c47a82_20260814/`.
- Support composer archive: `/Users/sabastineesisorigho/Documents/Codex/Evidence/BUILD_18039_SUPPORT_CHAT_POLISH_3ad2080_20260814/`.
- Canonical Worker source archive and manifest: `/Users/sabastineesisorigho/Documents/Codex/Evidence/BUILD_18039_WORKER_CANONICAL_f32ff3a_20260814.zip` and `.manifest.md`.
- Shadow validation archive: `/Users/sabastineesisorigho/Documents/Codex/Evidence/BUILD_18039_WORKER_SHADOW_VALIDATION_ba56b5a_20260814/`.
- Candidate-gate archive: `/Users/sabastineesisorigho/Documents/Codex/Evidence/BUILD_18039_WORKER_CANDIDATE_GATE_a25bf12_20260814/`.
- Adaptive avatar and current client source are represented by the final iOS overlay patch above; no private-master/derivative migration is authorized or implemented.

## Current product/runtime state

- `IOS_SOURCE_BLOCKER = NO`.
- `FRESH_IOS_BUILD_BLOCKER = CORESIMULATOR_XPC_HOST_TOOLING`.
- `FRESH_IOS_INSTALL_BLOCKED = YES`.
- `SERVER_SIDE_WORK_MAY_CONTINUE = YES`, only under the candidate/shadow governance.
- Current installed app is Build `1.8 (18039)` and contains the earlier 2048px/6MB avatar preparation; adaptive fashion-quality preparation is source-only pending a fresh signed build.
- Support AI response is physical PASS after explicit current consent. Consent UX and composer lifecycle have source/test acceptance; physical confirmation of their latest source remains pending a new build.
- General Stylist reached the Worker and was blocked by stale AI-processing consent before provider dispatch; provider classification remains unproven pending a post-consent trace.
- Avatar failure root cause is bounded client payload `IMAGE_SIZE_LIMIT`; server storage/moderation/D1 were not implicated in that trace.

## Worker deployment governance

`LIVE_WORKER_DEPLOYMENT = FROZEN` for `stylematch-18039-friends-dm-staging`. Historical live source provenance is not byte exact and the candidate baseline is not fully provider validated. No `wrangler deploy` is authorized after restart unless separately approved.

Every future deployment requires a durable pre/post manifest containing: Git SHA; clean status or dirty-diff SHA; Worker name; config; D1 ID; R2 binding names; secret names only; migration set; test results; deployment timestamp; Cloudflare version ID; and script ETag if available.

## First actions after restart

1. Unlock the login keychain and verify `security find-identity` contains the accepted Apple Development identity. Do not alter certificates, profiles, or the portal.
2. Verify CoreSimulatorService and simdiskimaged stability before attempting an iOS build. Do not delete runtimes or devices.
3. Do not deploy the Worker.
4. Recheck all four worktrees against the HEADs and dirty-overlay hashes above.
5. Resume source and runtime work only from the ledger and this handoff; never reconstruct state from chat history or `/private/tmp`.

## Current blockers and next authorized actions

- Fresh iOS builds/installations: blocked by the Mac/Xcode CoreSimulator XPC incident.
- Live Worker deployment: frozen pending owner-reviewed candidate provider validation and a manifest-backed deployment decision.
- Avatar physical retest: requires a fresh signed iOS build that includes the source-only adaptive preparation.
- General Stylist provider acceptance: requires explicit current AI-processing consent and one new bounded trace after deployment authority is safely established.
- Support current physical experience: core provider response is proven; latest consent/composer UX awaits a newly built binary.

No secrets, tokens, account identifiers, private photos, object keys, provider bodies, or credential material are contained in this handoff.
