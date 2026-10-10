# Style Friends notifications — privacy impact (Build 18038 foundation)

Status: source foundation only. APNs delivery is not activated, no APNs
credential is configured here, and this work does not deploy or install an app.

## Data boundary

The device registers only after the owner explicitly grants iOS notification
permission. The backend accepts the authenticated account session and stores a
digest plus encrypted APNs token, platform, APNs environment, categories, and
bounded timestamps. It never returns the token through an API and the iOS app
does not keep it in social UI state.

Event activity contains only an event type and opaque social references. It
does not carry an email, Apple subject, raw account key, share token, card
digest, CloudKit ID, scan ID, Closet/Profile data, AI Memory, comment body, or
purchase detail. A notification tap is only a navigation hint; the client must
perform an authenticated request and the server rechecks friendship, block,
post, revoke, and deletion state before it shows content.

## Lock screen and delivery policy

The approved copy is deliberately generic: for example, “A friend shared a
new outfit” or “Someone liked your shared outfit.” Rich previews, comment
text, exact purchase details, and outfit metadata require a future privacy
review. The initial new-post mode is **Off**; the only implemented delivery
selection is explicit **All friend posts**, using server-side indexed D1
selection. Selected/important modes are displayed as future-safe preference
values but do not fan out without a separately approved selection authority.

## Retention and account isolation

Push registrations are removed when the current account signs out. Account
deletion removes notification registrations, preferences, and event activity
in addition to the existing account-deletion flow. This foundation requires a
future operational retention job before live delivery is activated; durable
event retention is therefore not approved as an indefinite policy.

Sign-out is not deletion: it preserves the account and its data for a later
sign-in. A completed account deletion removes registrations, preferences, and
activity permanently. A later sign-in creates a new account/session authority;
old notification state is not restored.

## Required future gate

Before enabling delivery, complete a separate review for APNs credentials,
production/development environment separation, invalid-token feedback,
time-bounded activity retention, authorization-on-open physical validation,
and user-facing privacy disclosure updates.

## 2026-08-11 isolated nonproduction runtime evidence

Migration `0011_style_friend_notifications.sql` was applied only to the
isolated `friends-auth-test` D1 database. A synthetic A/B/C local Worker
runtime matrix verified authenticated registration storage (digest plus
encrypted token representation), conservative preference defaults, bounded
event activity, server-authorized fanout, stale relationship denial, and
revoked-share denial. No real APNs token, credential, delivery, production or
staging resource was used.

The matrix also confirmed the intentional lifecycle distinction: sign-out
removes the active account's device registrations while retaining its
preference and event rows; account deletion remains the separate source-owned
cleanup path for registrations, preferences, and activity. The account-delete
flow was not exercised against a real account because it requires recent Apple
reauthentication. The Worker source now includes a daily retention purge for
the 90-day moderation records, but it has not been deployed or observed in a
scheduled production/runtime execution. Therefore the required future gate
remains open and this document does not approve APNs delivery or release
readiness.
