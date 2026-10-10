# StyleMatch Pro App Store Connect Privacy Worksheet — Draft

**INTERNAL DRAFT — NOT CUSTOMER-FACING — NOT FOR PUBLICATION**
**OWNER/LEGAL REVIEW AND VERIFIED BUSINESS FACTS REQUIRED**

Status: **Draft only. Do not enter or submit these answers in App Store Connect until the unresolved deployed backend, provider, website, affiliate, and ownership facts are confirmed. App source and local candidate Worker code are not proof of production collection, linkage, retention, or processor status.**

| Data type | Current source-backed handling | Purpose | Linked / tracking | Status |
|---|---|---|---|---|
| User ID | Account-scoped app data and authenticated chat route | App functionality | Manifest declares linked; tracking false | Verify deployed account handling |
| Device ID | The chat transport can derive and hash a device identifier for requests | App functionality / abuse prevention | Manifest declares not linked; tracking false | Retention pending |
| Precise Location | Used when a user requests weather | App functionality / personalization | Manifest declares not linked; tracking false | Weather-provider review pending |
| Other User Content | Chat content, bounded current context, and a relevant subset of confirmed AI Memory facts may be transmitted when the user requests AI assistance | App functionality / personalization | Manifest declares linked; tracking false | Backend/provider logging and retention pending |
| Photos | Scan images are locally retained; the current source does not show raw outfit photos in AI Stylist chat requests | App functionality | Not tracking | Shared-link handling pending |
| Calendar | Raw events stay outside AI Memory; a bounded local context can be used after opt-in | App functionality / personalization | Not tracking | Provider and App Store classification review pending |
| Audio / Speech | Requested only after a user initiates voice input | App functionality | Not tracking | Apple service handling review pending |

## Reconciliation limits

- `PrivacyInfo.xcprivacy` is a source declaration, not a complete legal determination of App Store privacy-label answers.
- The current app contains no bundled policy fallback. Verify the published external policy URL rather than claiming source-to-bundle parity.
- Do not infer live analytics, crash reporting, cookies, affiliate tracking, or a fixed share-link lifetime from local candidate backend source.
- Current app source is capable of sending customer messages and structured styling context to the configured backend. Before entering any answer, reconcile the required in-app consent flow, the deployed backend recipient, and any downstream AI provider.
- Current weather source calls Open-Meteo from the active weather manager, while the target also retains WeatherKit entitlement/code. Confirm production provider and all recipient/collection implications before completing Location answers.

## AI Memory note

AI Memory is local-only persistent storage in this phase. Only a bounded, relevant subset of active confirmed facts can be added to an AI request. It does not make every stored memory part of every request.

## Required verification before App Store Connect entry

- Verify all integrated-provider, Worker, website analytics, affiliate, retailer, Cloudflare, and security-log practices.
- Verify the deployed account, session, token, chat, share-link, catalog-log, and provider retention behavior.
- Verify whether Apple’s definitions require any additional collection categories or linked-data treatment.
- Do not claim tracking is false as a legal conclusion solely because the manifest has `NSPrivacyTracking=false`.
- Set the public Privacy Policy URL to `https://stylematchpro.com/privacy` only after publication parity and owner/legal approval.

## Build 18038 Style Friends reconciliation — pending App Store review

| Actual data practice | Policy coverage | App Store privacy disclosure | Consent / permission UI | Status |
|---|---|---|---|---|
| Private iCloud synchronization of supported private records | Build 18038 private-sync section | Reconcile linked data and iCloud processing | Existing Cloud Sync control; physical sync acceptance pending | Pending |
| Friends relationships and social profile | Style Friends section | Reconcile user content / identifiers as applicable | Explicit Friends actions; authenticated session required | Pending deployment review |
| Approved shared image and score snapshot | Sharing section | Reconcile photos and user content | Explicit Share / Publish review flow | Pending deployment review |
| Likes, Comments, Reports, and feed | Style Friends section | Reconcile user content | Friends-only authorization | Pending deployment review |
| APNs registration/preferences/activity | Notifications section | Reconcile device identifier and user content handling | iOS notification permission and in-app preferences | APNs inactive/pending |
| Permanent deletion, 90-day private moderation retention, and tombstones | Deletion section | Ensure retention/deletion answers match published policy | Delete Account confirmation / recent reauth | Deployed purge and real-account acceptance pending |
| WeatherKit weather and requested location/city | Weather section | Reconcile location collection/use | Location permission or entered city | Physical/provider acceptance pending |

No Style Friends answer should be entered in App Store Connect as final until
the corresponding deployed practice, retention behavior, and policy publication
are verified.

| Future Sale & Price Alerts | Not active: requires a verified approved price source, authenticated backend event validation, APNs, separate preferences, and privacy review | Do not declare until implemented and reviewed | Separate in-app category plus iOS notification permission | Not active |
