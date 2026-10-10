# INTERNAL DRAFT — NOT CUSTOMER-FACING — NOT FOR PUBLICATION

**OWNER/LEGAL REVIEW AND VERIFIED BUSINESS FACTS REQUIRED**

# StyleMatch Pro Privacy Policy — AI Memory Draft

**Last Updated:** August 6, 2026
**Effective Date:** [EFFECTIVE DATE TO BE CONFIRMED]

**Proposed controller (not verified):** Kigo Enterprise LLC, a Georgia limited liability company, is an owner-proposed controller candidate only. **Do not name it as the publisher, developer, or controller until its current Active/Compliance status and its ownership or contractual authority for StyleMatch Pro, the Apple Developer account, domain, backend, support mailbox, affiliate relationships, and payment accounts are evidenced.** The owner-provided privacy/support contact is **hello@goodnessoflifeandfun.com**; mailbox authority remains to be confirmed.

## Scope

This draft explains how StyleMatch Pro handles information in the iOS app, including outfit scans, saved history, AI Stylist requests, AI Memory, weather, optional Calendar Context, sharing, and shopping features. It does not govern third-party retailer sites you choose to open.

StyleMatch Pro is for a general audience and is not directed specifically to children under 13. The app does not claim to provide age verification or parental-consent tools.

## Information Stored on Your Device

StyleMatch Pro may store profile and preference data, size and fit details, Closet data, saved scans and their analysis, thumbnails and durable saved scan image assets, saved conversations, shopping lists and favorites, and user-approved AI Memory records on your device.

Outfit-photo analysis and scoring occur on-device. Locally stored scans, images, preferences, and history remain on the device until you delete them, clear app data, or remove the app, subject to device backup behavior. The current source does not show raw outfit photos being transmitted as part of an AI Stylist chat request.

## AI Memory and Your Controls

AI Memory is a local, user-controlled store for facts you choose to save or confirm, such as style preferences, sizes and fit preferences, work and uniform preferences, PPE or safety preferences, shopping preferences, corrections, and bounded references to saved records where applicable.

You can add a memory, edit it, see why it is remembered, forget one memory, forget a category, clear temporary AI context, clear all AI memories, and export applicable local AI Memory data. Clear All AI Memories removes AI Memory only; it does not delete your Profile, Saved Scans, scan images, Closet items, favorites or shopping lists, or account.

Merely viewing a screen or product, opening a scan, scanning an outfit, checking Weather, enabling Calendar Context, or opening Profile does not automatically create persistent AI Memory. Temporary current-screen and conversation context is separate from persistent AI Memory. Clearing temporary context keeps saved AI memories.

The AI Memory store is designed not to persist raw outfit images, screenshots, raw OCR text, raw Calendar events, passwords, API keys, authentication or session tokens, device identifiers, or full chat transcripts.

## Information Sent for AI Requests

When you request AI assistance, the app source is configured to send the request and a small, relevant subset of confirmed facts to a StyleMatch backend chat endpoint. The app applies a bounded request-context policy and does not send every stored memory with every request. **[PRODUCTION ROUTE, OPERATOR, AND AI-PROVIDER CONFIRMATION REQUIRED: this source configuration alone does not prove the deployed service, its processor, or its live data practices.]**

**[TECHNICAL CONFIRMATION PENDING: production backend, AI-provider, Cloudflare, and security-log retention; whether chat prompts or responses are persisted; and the deployed provider-processing terms.]**

**[APP REVIEW REMEDIATION REQUIRED BEFORE PUBLICATION OR RESUBMISSION: current source does not establish an explicit, pre-transmission AI-data authorization that identifies the recipient, categories of data, purpose, and effect of agreeing. A policy or Terms disclosure alone is not a substitute for that in-app control.]**

## Other Feature Data

- **Sign in with Apple.** The app and a local candidate backend source contain account-authentication code. **[TECHNICAL CONFIRMATION REQUIRED: whether the production service uses this flow, its operator, and deployed account-exchange and token-retention practices.]**
- **Weather.** The current 18039 source uses WeatherKit as the iOS weather authority and carries Apple Weather attribution metadata. If you request location-based weather, location information may be used for that request. A city you enter may be used for weather lookup. **[PUBLICATION CONDITION: confirm the released provider path and every recipient before naming services or describing collection in a public policy.]**
- **Calendar Context.** Calendar Context is off by default. When you enable it and grant full Calendar access, the app reads a bounded upcoming-event window for styling context and does not edit your calendar. Raw EventKit values are inspected locally to derive a minimized category, time window, bounded duration, and all-day state. The app does not persist raw event titles, notes, attendees, URLs, locations, organizers, calendar identifiers, or event identifiers in AI Memory. A minimized projection can inform a requested Home Intelligence or Stylist interaction; do not claim all Calendar-derived data stays on device unless the deployed request path is verified.
- **Style Friends, messages, and Support.** Style Friends can process a customer-selected social profile, friend requests and relationships, explicit shared looks, blocks, reports, reactions, and direct-message content through authenticated service routes. AI Customer Service is a separate, consent-gated support experience and is not a human direct-message service or an automatic export of Profile, Closet, scans, AI Memory, or CloudKit data. **[PUBLICATION CONDITION: verify deployed recipients, moderation access, retention, deletion, and downstream AI-provider processing.]**
- **Sharing and shopping.** Shared links, remote catalog requests, affiliate links, and retailer sites involve separate services. **[TECHNICAL CONFIRMATION PENDING: deployed shared-link expiration/deletion, catalog logging, affiliate processing, and website analytics.]**

## Retention and Deletion

An active confirmed AI Memory is retained locally until it is edited, forgotten, cleared, expires, or applicable account or local-data deletion occurs. When a record expires, it stops being active; the current app does not yet physically compact expired or superseded records as a general retention process. When you explicitly forget a memory, forget a category, or clear all AI memories, the current app removes those selected AI Memory records from the active local document and its recovery snapshots. Corrections may retain only the associated local correction lineage while its active replacement remains present; a user-directed forget or clear does not retain that memory solely for correction history.

Temporary context is request- or session-scoped and is not the AI Memory store. The current app does not claim fixed server or provider retention periods. Information is otherwise retained only as reasonably necessary to provide the requested service, maintain security, satisfy legal obligations, or resolve disputes, subject to the unresolved technical confirmations above.

## Safety and Workplace Guidance

Workplace, uniform, fit, weather, and PPE suggestions are informational only. They do not replace employer rules, safety procedures, PPE requirements, manufacturer instructions, medical advice, or professional advice.

## Your Choices and Contact

You can use the app’s data controls to manage AI Memory, export applicable local data, clear local data, manage shared links, disable Calendar Context, or revoke permissions in iOS Settings. Local deletion does not by itself confirm deletion of server-side account data. Use an available account-deletion flow or contact **hello@goodnessoflifeandfun.com** for help.

We will update this policy’s Last Updated date and effective date when a revised policy is published.

**[OWNER OR ATTORNEY REVIEW REQUIRED: confirm Kigo Enterprise LLC’s Georgia Active/Compliance status, service ownership and authority, any required public mailing address, jurisdiction-specific disclosures, deployed server/provider retention, and publication date before publication.]**

## Build 1.8 (18038) proposed policy revision — private sync, Style Friends, and deletion

This proposed revision must be incorporated into the published policy only after
owner/legal approval and the deployment evidence identified below.

### Private iCloud synchronization

When enabled, StyleMatch's private iCloud/CloudKit synchronization is intended
to keep supported private StyleMatch records consistent across a person's own
devices. Source-backed categories are Profile/personalization data, saved scans
and supported image assets, Closet data, Shopping data, and explicitly saved AI
Memory. This private iCloud data is distinct from Style Friends. Friendship,
Friends posts, and share links do not give another person access to a user's
private CloudKit records, private Profile, Closet, AI Memory, or private scan
history. Signing out ends the session and does not itself delete data; permanent
account deletion follows the applicable account-deletion flow.

### Style Friends and sharing

If a person chooses to use Style Friends, StyleMatch processes friend requests,
accepted relationships, blocks, a chosen social profile (display name, avatar
reference, style bio, and style categories), opaque social references,
Friends-only shared outfit posts, approved shared images, score snapshots,
Friends feed activity, Likes, Comments, and Reports/moderation. The social
service uses a bounded shared representation; it does not directly share the
private source scan or private account data. Likes and Comments never change a
StyleMatch score.

Revoke Share makes the applicable shared representation unavailable but does
not delete the original private photo, score, scan history, Profile, Closet, or
AI Memory. Delete Friends Post removes the social post and its engagement but
does not automatically revoke a separate external shared card. Social/shared
representations are revoked on account deletion and subject to the applicable
deletion/retry architecture.

### Notifications, weather, and providers

Style Friends notifications require iOS permission and, when delivery is
activated, may process protected APNs device-registration material, notification
preferences, and privacy-safe activity for friend requests, accepted requests,
Friends posts, Likes, and Comments. Purchase-detail requests are not active
unless separately enabled. Sign-out removes the active registration; permanent
account deletion removes the deleted account's registrations, preferences, and
activity.

Weather Styling uses WeatherKit conditions when available. Location is used for
weather only when requested by the person, and an entered city can be used for a
weather lookup; StyleMatch does not claim continuous location collection.
Weather facts may support temperature, rain, umbrella, wind, humidity, and UV
guidance. Apple services include Sign in with Apple, iCloud/CloudKit where
enabled, WeatherKit, and APNs when activated. Cloudflare supports applicable
backend services. A bounded AI request may be processed by the StyleMatch
backend and applicable AI provider. Retailers process information supplied to
them after a person opens their link under their own policies.

### Permanent deletion and a later return

Sign Out ends a session without deleting the account or data. Permanent Delete
Account has no recovery or grace period in the current implementation. It
removes active Friends relationships, social profile, posts, engagement,
notification state, and active social reference, and revokes owner shared
cards. A person who returns later using the same supported external identity
receives a new StyleMatch account; permanently deleted private and social data
is not restored or reassigned. Old social references remain retired and
non-resolving.

StyleMatch may retain minimal private moderation/audit evidence for up to 90
days for abuse, safety, or legal purposes. It is not public or Friends-visible.
The service also retains the minimum non-user-facing opaque tombstone necessary
to prevent identifier reuse or deleted-account resurrection; it is not an active
account identifier. The design includes scheduled expiry deletion.

### Publication conditions

This revision is intentionally pending: Style Friends deployment, APNs physical
acceptance, private CloudKit/iCloud physical acceptance, deployed moderation
purge observation, deployed social-image cleanup/retry observation, real recent
Apple-reauth deletion acceptance, deployed AI-provider/retention confirmation,
and final App Store Privacy disclosure review. It is not yet a published policy.

### Future sale and price alerts — not active

If StyleMatch later offers sale or price-drop alerts, it will use Apple's APNs
and iOS UserNotifications with the authenticated StyleMatch backend. Apple does
not detect retailer prices: an approved retailer, affiliate, or product-data
source must verify a current price before an alert is created. Sale & Price
Alerts will have a separate preference from Style Friends, Weather, and other
categories, and iOS notification permission remains the device-level control.
Alerts will use bounded opaque product/watch references and reauthorize the
current product or watch when opened. This proposed disclosure is not a claim
that sale alerts or a price-watch service are active today.
