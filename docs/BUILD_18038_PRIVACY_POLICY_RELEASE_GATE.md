# Build 18038 privacy-policy release gate

**Status: release BLOCKED until this document is reconciled with the published
Privacy Policy, product controls, and deployed retention behavior.** This is an
internal implementation and legal-review record, not customer-facing policy
text and not a claim that any undeployed feature is active.

## Non-negotiable ownership boundary

Deleting a Friends post or revoking its underlying shared-card representation
does **not** delete the owner's original private photo, score, Profile, Closet,
AI Memory, or private scan history. Those private records remain subject to
their separate private-data controls. Conversely, deleting the private source
must follow an explicit source-retention and shared-representation policy; it
must never be inferred from a social-post action.

## Data-impact inventory

| Category | Purpose and authority | Storage / processors | Visibility | Retention and deletion status |
| --- | --- | --- | --- | --- |
| Friend requests and relationships | Server-authoritative request, accept, remove, and block state | Account D1 (`style_friend_relationships`) | The two relationship participants; no contact discovery | Remove deletes the pair. Permanent account deletion removes every active relationship/request. |
| Social profile | Owner-selected display name, avatar reference, bio, and style categories | Account D1 (`style_friend_profiles`) | Owner; accepted friends only after server authorization | Owner can update it. Permanent account deletion removes it. It is never populated from private Profile storage. |
| Opaque social references | Server-issued social routing reference | Account D1 (`style_friend_account_references`) | Authenticated social routes only; not an account key or permission | Active mapping is deleted on permanent deletion. A non-resolving opaque-reference tombstone prevents reuse. |
| Shared card / shared image / score snapshot | An explicitly approved bounded representation of a saved look; score is a snapshot, not a new social score | Existing secure share-card authority; card metadata in Account D1 and approved image authority | External-link recipients only within the existing token scope; a Friends post is visible only to authorized friends | Existing expiry/revoke controls apply. Revoke makes representations unavailable; it does not remove private source data. Source-deletion relationship requires an explicit policy. |
| Friends post and feed | Friends-only presentation metadata: opaque post reference, bounded title/caption/occasion, timestamp, moderation state, and approved card reference | Account D1 (`shared_outfit_posts`) | Authorized friends; owner list | Delete Post soft-deletes the social post. Permanent account deletion removes owned posts and related engagement. |
| Post/comment reactions, comments, replies, reports, moderation | Friends engagement and safety review; reactions are server-authoritative per-viewer Like/Love/Fire/Perfect/Stylish/Want It/Not For Me choices with server-derived aggregates. Replies are shallow post-bound comments. | Account D1 (`style_friend_reactions`, `style_friend_comments`, `style_friend_reports`) | Active reactions/counts, comments, and reply previews only to authorized viewers; reports/moderation are not public | A user may set, switch, or remove one active reaction per authorized post/comment. Deleted/revoked/blocked/unauthorized content rejects new actions. Want It does not establish retailer, product source, purchase history, or ownership, and never enters private Shopping history. Reactions/replies are never private CloudKit data. Minimum moderation evidence may remain private for 90 days. |
| Block state | Prevents new Friends interaction and hides prior engagement from ordinary presentation | Relationship state in Account D1 | The participating accounts only | Blocking does not itself erase moderation records. Retention/erasure policy must be published and implemented. |
| Notification preferences, activity, and APNs token | User-selected Friends notification settings, generic activity routing, and future APNs delivery | Account D1 (`style_friend_notification_*`); Apple APNs only if delivery is separately activated | Account owner; navigation still reauthorizes server-side | Source foundation is not deployed/active. Sign-out/account deletion cleanup is implemented for notification tables; a time-bounded event-retention job is still required before delivery. |
| Product/purchase-detail interaction / Shop This Look | Future owner-initiated social commerce interaction | Not implemented as an active Style Friends capability | Must be bounded by friendship and the selected shared representation | Requires separate processor, affiliate, purchase-detail, consent, and retention review before activation. |
| Ask Stylist About This Look | Future context handoff based only on authorized shared-card facts | Existing Stylist authority if later authorized | Only the requesting authenticated user | Requires separate AI-transmission disclosure and processor/retention review before activation. |

## Required published-policy additions

The canonical policy at `https://stylematchpro.com/privacy` must be updated
and approved before Build 18038 release. The following is proposed policy
wording for legal/owner review; replace bracketed operational facts only after
they are verified.

### Style Friends

> If you choose to use Style Friends, we process the social profile details
> you choose to provide (such as display name, avatar reference, style bio, and
> style categories), friend-request and relationship status, and your block
> choices to provide the Friends service. We do not use Style Friends to expose
> your private StyleMatch Profile, Closet, AI Memory, private scan history,
> CloudKit records, or device files to other users.

### Shared looks, scores, and audience

> A look is shared only after you take an explicit sharing action and complete
> the applicable review and publish step. A Friends post can include the
> approved shared-card representation, selected image, StyleMatch score
> snapshot, title, caption, occasion, and timestamp. Friends posts are visible
> only to authorized friends. An external share link has the separate audience,
> expiration, and revocation rules shown when you create that link; possession
> of a link does not make a recipient your friend or give access to Friends
> features.

### Social interactions and moderation

> We process likes, comment reactions, comments, reports, and block actions to operate Style
> Friends, prevent abuse, and administer moderation. Comments and reports may
> contain information you choose to submit. Do not include sensitive personal
> information in social content. [State the verified moderation access and
> retention period here before publication.]

### Revocation and deletion distinction

> Deleting a Friends post removes that social post and its normal Friends
> presentation. Revoking a shared representation stops access to that shared
> representation. Neither action automatically deletes your original private
> photo, StyleMatch score, Profile, Closet, AI Memory, or private scan history.
> Use the applicable private-data or account-deletion control to delete those
> private records. [State the verified source-deletion and backend-erasure
> process here before publication.]

### Notifications

> If you choose to allow Style Friends notifications, we process your
> notification preference settings and a device notification token to send the
> notification categories you select. Notification previews are designed to be
> generic. You can change notification permissions in iPhone Settings and
> notification preferences in StyleMatch. [Name Apple APNs and the verified
> service providers, storage locations, and retention period before delivery is
> activated.]

### Service providers and future features

> We use service providers that host and operate the authenticated StyleMatch
> services and approved shared-card delivery. [List verified processors and
> their roles, including hosting/storage and Apple APNs when active.] Shop This
> Look, retailer/affiliate links, purchase-detail questions, and Ask Stylist
> About This Look require separate disclosure of the information sent to the
> relevant retailer, affiliate, or AI processor before those features are made
> available.

### Private iCloud Cloud Sync — proposed policy wording

> If you choose to turn on Cloud Sync after it becomes available, StyleMatch
> stores the eligible data described in the Cloud Sync control in your private
> iCloud/CloudKit database so it can synchronize between your devices that are
> signed in to the same iCloud account. Eligible data is limited to Profile and
> style preferences, Closet items, saved scans with their saved score,
> timestamps, metadata, and associated saved image, Shopping favorites and
> watch-list identifiers, and AI Memory that you explicitly saved. We do not
> use Cloud Sync for temporary AI conversations or context, consent or
> permission settings, secrets or tokens, diagnostics, routing metadata,
> caches, transient interface state, or Style Friends social data.

> Cloud Sync is optional. Turning it off stops future synchronization; it does
> not by itself delete copies already stored in iCloud. Before Cloud Sync is
> released, we will provide the applicable deletion controls, explain the
> retention period for deletion markers needed to prevent stale-device
> restoration, and identify Apple as the iCloud/CloudKit service provider.
> If the iCloud account on a device changes or is unavailable, Cloud Sync stops
> safely and does not move data into another iCloud account.

### App Store privacy disclosure — proposed reconciliation

Before release, reconcile the App Store privacy disclosure with the verified
customer implementation: declare the applicable user-content/profile,
photos-or-videos, identifiers, and diagnostics categories only to the extent
they are actually transmitted or retained by the released private CloudKit
feature; identify synchronization as the purpose; identify Apple iCloud/
CloudKit as a service provider where the disclosure requires it; and state
whether each category is linked to the user. Do not declare Style Friends
social data as private CloudKit data. The final selection must be verified
against the deployed schema, runtime traffic, retention behavior, and Apple’s
then-current disclosure taxonomy before submission.

## Consent, permission, and UI requirements

- Friends profile editing, friend requests, and block/remove are explicit
  authenticated actions; no contact discovery or silent social publishing.
- Sharing stays two-step: select **Share with Friends**, review the bounded
  representation, then explicitly publish. Share Link/Copy Share Link remains
  a separate capability.
- APNs permission is requested only after an explicit owner action. Delivery is
  not approved until the system prompt, generic preview behavior, settings,
  APNs processor disclosure, and deployed retention controls are validated.
- Any future retailer, affiliate, purchase-detail, or Stylist handoff must use
  its existing consent authority and cannot rely on a Friends relationship or
  possession of an external share link as consent.

## Release reconciliation checklist

Before a Build 18038 pre-install or release decision, verify and record:

1. The canonical public policy contains approved equivalents of every section
   above, with verified controller/contact, processor, and retention facts.
2. Account deletion has tested cleanup or an explicitly approved retention
   process for every social table: relationships, profiles, opaque references,
   posts, likes, comments, reports, and notification data.
3. Deleting a post, revoking a card, deleting a private source, signing out,
   blocking, and deleting an account each have distinct tested behavior.
4. Public-link viewers receive only the existing bounded share capability; they
   do not gain friendship, feed, comment, or private-data access.
5. Notification data, APNs permissions, generic previews, and any activity
   retention are validated before APNs delivery is activated.
6. App Store privacy disclosures and any jurisdiction-specific notices are
   reconciled with deployed behavior.

Until all six checks pass, Build 18038 is **not release-ready**.

## Account deletion and retention policy — proposed implementation contract

The following policy is enforced only when the authenticated account-deletion
authority completes. It is distinct from **Revoke Share** (which revokes only
the shared representation) and **Delete Post** (which removes only the social
post presentation). Neither of those actions deletes private StyleMatch scan
history, photos, scores, Profile, Closet, or AI Memory. **Delete Account** is
the separate account-level process that reconciles private-data deletion and
all server-side Style Friends data.

| Data type | Account-deletion action | Retention purpose/period |
| --- | --- | --- |
| Relationships and pending requests | DELETE_IMMEDIATELY | None. Other accounts no longer see the deleted account. |
| Social profile, active opaque-reference mapping, posts, likes, authored comments | DELETE_IMMEDIATELY | None. A non-identifying opaque-reference tombstone is retained solely to prevent reference reuse; it cannot resolve to an account, profile, or social content. |
| Notification registrations, preferences, activity | DELETE_IMMEDIATELY | None. Sign-out removes registrations only; deletion removes all three. |
| Owner shared cards and social image objects | Revoke immediately; delete associated object through private retry cleanup | Public/Friends access stops before object cleanup. Retry metadata contains only the object key and is removed after completion. |
| Reports filed by or about the deleted account | ANONYMIZE_THEN_RETAIN | Minimum moderation evidence is retained privately for 90 days to investigate abuse or legal/safety obligations, then must be purged. It is never social/publicly visible. |
| Private iOS data | ALREADY_DELETED_BY_EXISTING_ACCOUNT_FLOW | The existing private account-deletion authority remains responsible for scans, images, Profile, Closet, Shopping, AI Memory, and local state. |

### Account lifecycle and a later return

**Sign Out** ends the current session only. The account and its data remain
available if the person later signs in again. **Delete Account** is permanent;
there is no cancellation or recovery period in the current implementation.
After deletion completes, a person may later authenticate using a supported
identity provider to create a **new** StyleMatch account. That new account does
not restore private photos, scans, scores/history, Profile, Closet, AI Memory,
work context, Shopping history, chats, relationships, social profile, posts,
likes, comments, notification registrations, or activity from the deleted
account.

The backend retains two minimal, non-user-facing tombstone categories only:

- a one-way identity-hash tombstone, required to ensure that a future sign-in
  receives a new account authority instead of reactivating a deleted one; and
- a retired opaque social-reference tombstone, required to ensure that a
  deleted social reference never resolves or is reassigned.

Neither tombstone stores an Apple subject, email, scan, image, Closet,
Profile, AI Memory, social content, or active session. Active identity mapping
is removed during deletion; old sessions and refresh credentials are unusable.
The current policy has no deactivation state and no grace period. Any future
cancellation window requires separate approval, a stated duration, UI date,
automatic idempotent expiry, and a matching Privacy Policy update.

Required public-policy wording before release:

> When you delete your StyleMatch account, we remove your active Style Friends
> relationships, social profile, posts, likes, comments, notification settings
> and registrations, and revoke shared cards you created so their public and
> Friends presentations are unavailable. We may retain a minimal, non-public
> moderation record for up to 90 days when it is needed to investigate abuse,
> safety, or legal matters. We retire social references so they cannot be
> reassigned, but they no longer resolve to your account or social profile.
> Signing out keeps your account and data available when you return. Deleting
> your account is permanent. If you return later, you may create a new
> StyleMatch account, but permanently deleted data and prior Friends
> relationships are not restored.

Runtime validation of the Worker contract and the 90-day purge operation is
required before this policy may be marked release-ready.

### 2026-08-11 notification runtime evidence

An isolated synthetic A/B/C notification matrix validated only the test D1
schema and a local Worker runtime. It did not use a real APNs token, APNs
credential, production/staging environment, or physical device. It confirms
that device registrations are removed on sign-out while durable notification
preferences/activity remain until the distinct account-deletion authority runs.
The source defines a 90-day moderation-retention period and a daily scheduled
purge, but neither has been deployed or observed in a production scheduled
execution; real-account deletion was intentionally not performed. The
notifications policy section, App Store disclosure, processor identification,
account-delete evidence, and deployed retention evidence therefore remain
release blockers.
