# RG1 distribution binding inventory

| Channel | Evidence | Effective chat binding |
|---|---|---|
| 1.7 Debug device builds from the current dirty tree | `Config/StyleMatchDebug.xcconfig` | intended staging binding; configuration change is not yet durable |
| 1.7 Release/TestFlight/App Store builds from the current dirty tree | `Config/StyleMatchShared.xcconfig` plus the prepared artifact gate | intended production binding; configuration and gate are not yet durable, and no signed Release artifact has proven the effective host |
| TestFlight 1.6 already in the field | no archived `.app`/`.ipa` was supplied to RG1 | unknown; inspect the archived artifact before relying on it |
| 1.5 already in the field | no archived `.app`/`.ipa` was supplied to RG1 | unknown; inspect the archived artifact before relying on it |

Unknown means unverified, not staging-bound. RG1 never infers a shipped artifact's host from current source.

The binding-verification and cross-repository release-gate scripts are prepared in the dirty iOS worktree but remain untracked and not yet durable.
