# Build 18037 Security Gate Phase 2 — Local Data Protection

**Checkpoint base:** `f479ecce882a206d36dfef763fb2fee82617a0d7`  
**Status:** source validation pending; no device validation, signing, installation, CloudKit mutation, or account mutation is part of this gate.

## Policy

All file-backed customer data uses iOS `NSFileProtectionComplete`: it is not
available while the device is locked. User-created records remain eligible for
the owner's normal encrypted device/iCloud backup. Reconstructable or
transient files are explicitly excluded from backup. `UserDefaults` is a
compatibility authority for existing records, so the app protects its own
preferences plist after launch and subsequent defaults changes; individual
defaults keys cannot carry independent iOS file-protection attributes.

| Data class | Persistent authority/path | Sensitivity | Backup | Account boundary and deletion |
| --- | --- | --- | --- | --- |
| Saved-scan photos | `Application Support/StyleMatchPro/SavedScanImages/account-<SHA-256>/` | High | Include | Hash-namespaced per active account; active-account referenced legacy images migrate once; account deletion removes only that namespace. |
| Saved-scan metadata and tombstones | `UserDefaults` (`outfitScanHistoryData`, authority tombstones) | High | Include | `AccountScopedStorage` snapshots/clears shared records across account switches; deletion clears active data. |
| Profile, personalization, work context, Outfit Memory and explicit AI Memory | `UserDefaults` plus `Application Support/StyleMatchPro/PersonalStylist/*.json` and recovery snapshots | High | Include | Account-scoped keys/snapshots; profile/memory deletion removes main and recovery files. |
| Stylist conversations and cached assistant responses | `Application Support/StyleMatchAI/StylistChat-account-<SHA-256>.json` and `.bak`; compatibility defaults | High | Include | Per-user conversation files; legacy filenames migrate in place; account deletion calls conversation cleanup. |
| Closet, Shopping, favorites/watch list, sale state | Account-scoped `UserDefaults` snapshots | Medium/High | Include | `AccountScopedStorage` isolates, restores and deletes the active account's snapshot. |
| Weather/personalization caches | Account-scoped `UserDefaults` | Medium | Include | Snapshot boundary and active-account deletion. |
| Recovery/import snapshots | Personal Stylist snapshots and saved-scan recovery authority | High | Include | Same complete-protection and account-scoped deletion policy; retained snapshots are bounded recovery copies only. |
| Explicit export archive | `temporaryDirectory/StyleMatchExport-*/` JSON/ZIP | High, transient | Exclude | Created only for a user-directed export; protected until normal temporary-file lifecycle cleanup. |
| Palette diagnostics | `Documents/StyleMatchDiagnostics/` (Debug diagnostics) | Low/diagnostic | Exclude | No account payload retention policy is expanded by this gate. |

## Account isolation

The account switch authority snapshots the complete supported shared-data set,
clears the presentation keys, then restores only the selected account's
snapshot. This is storage-authority isolation, not UI filtering. Saved-scan
photos additionally use a non-reversible account namespace and cannot be
looked up by another account's image store. Tests cover cross-account image
non-visibility and scoped deletion.

## Release AI-provider boundary

The direct third-party provider adapters and local founder API-key gate are
compiled only under `#if DEBUG`; non-Debug builds force the customer-public
channel and `allowsLocalFounderAPIKey == false`. Runtime preference cannot
enable that code in Release. The app target no longer contains
`STYLIST_CHAT_APP_SHARED_SECRET`; authenticated account sessions remain the
only share-link authorization authority.

## Residual verification

The policy is source-tested and must still be verified on a physical iOS
device by inspecting created file protection/backup attributes after an
unlock/relock cycle. That device evidence is intentionally outside this gate.
