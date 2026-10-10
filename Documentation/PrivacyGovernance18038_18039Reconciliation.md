# Privacy governance reconciliation — Builds 18038 and 18039

**Status:** INTERNAL RELEASE GATE — NOT CUSTOMER-FACING — NOT FOR PUBLICATION

**Audit date:** 2026-08-15
**18038 candidate reviewed:** `c4ea503fb18f707611a3254b5158c10dcb84e3ef`
**18039 owner-beta reviewed:** `760101f4a0f53fcb2adf9fa6a0f1eccce243ac9d`

This is an evidence-first reconciliation of the local iOS source, internal
privacy drafts, in-app controls, and `PrivacyInfo.xcprivacy`. It is not proof
of deployed Worker, CloudKit, Apple, AI-provider, website, or App Store
Connect practices. It must not be used to publish a policy or submit privacy
answers without owner/legal review and deployment evidence.

## Decision

**Privacy documentation and App Store reconciliation are required before
Build 18038 becomes a release build.** The existing policy materials are
explicitly internal drafts, the public URL is not bundled or verifiable from
source, and the source has acquired social, support, Calendar, Home
Intelligence, and notification capabilities that need a single approved
customer explanation.

No runtime behavior, device, backend, App Store Connect answer, or public
policy was changed by this audit.

## Required customer-facing classification

| Data / feature | Source-backed handling | Required classification | Release documentation decision |
| --- | --- | --- | --- |
| Profile, sizes, preferences, Closet, saved scans, local scan image assets, shopping lists and local AI Memory | Stored in account-scoped device storage; `Delete My Saved Data` clears the local stores and saved image assets. | `ON_DEVICE_ONLY` unless the customer enables a separately verified sync or submits it in a request. | Explain local storage and the scope of local deletion. Do not promise server deletion from this control. |
| Optional private CloudKit sync candidates | Source lists Profile, Closet, saved scans/image assets, favorites/watch list, and explicitly saved AI Memory as eligible; temporary context, consent, routes, and unsaved inferences are excluded. Deployment/activation evidence is not part of this audit. | `TRANSMITTED_TO_STYLEMATCH_SERVICE` only after the released CloudKit flow and retention/deletion behavior are verified; Apple is an external platform/service provider. | Do not describe it as active or fully deletable until production behavior and deletion-marker retention are proven. |
| Style Friends profile, friendships, requests, shared looks, reactions, reports, blocks | User-selected social data and server-authoritative relationship/moderation routes in the beta source. Private Profile, Closet, scans, and AI Memory are intentionally not the social profile authority. | `PUBLIC_OR_SHARED_BY_USER` for material the customer explicitly publishes to the applicable audience; `TRANSMITTED_TO_STYLEMATCH_SERVICE` for relationship, block, report, and moderation data. | Add a separate Style Friends section; Privacy is not the social product entry point or its complete disclosure. |
| Direct messages | Message content, conversation/message references, read state, reactions, reports, and block choices use authenticated, staging-gated beta transport. The source does not prove deployed retention or processor practice. | `TRANSMITTED_TO_STYLEMATCH_SERVICE`. | Explain message processing, recipient visibility, safety/reporting, and unknown retention only after the deployed authority is verified. Never classify DM content as on-device-only. |
| AI Customer Service | Dedicated Support model has a consent gate and account session. Source comments prohibit automatic inclusion of Style Friends, Profile, Closet, scans, AI Memory, or CloudKit data. Customer-entered support text can be sent through the support service. | `TRANSMITTED_TO_STYLEMATCH_SERVICE`; downstream `TRANSMITTED_TO_AI_PROVIDER` is **unproven** pending deployed provider evidence. | Give Support its own disclosure and consent copy. Do not say that it has access to all styling/customer data. |
| AI Stylist / Home Intelligence typed context | AI requests use bounded context. Home Intelligence composes available Profile, Closet, scans, Weather, Calendar, occasion, shopping, and work/PPE facts; the exact transmitted subset depends on the request and consent. | `TRANSMITTED_TO_STYLEMATCH_SERVICE` when an AI request is made; `TRANSMITTED_TO_AI_PROVIDER` only where the deployed processor is confirmed. | State that a minimized relevant subset may be used for the requested AI response; do not claim every source stays local. |
| Calendar / EventKit | Full Calendar access is requested contextually. Raw `EKEvent` values are read and title-classified locally into category, time window, bounded duration, and all-day state. Notes, attendees, location, URLs, organizers, calendar IDs, and event IDs are excluded from the projection and AI Memory. The minimized projection can inform Home/Stylist after consent. | Raw EventKit access: `ON_DEVICE_ONLY`; minimized projection used for an AI request: `TRANSMITTED_TO_STYLEMATCH_SERVICE`, and possibly `TRANSMITTED_TO_AI_PROVIDER` only if that processor is verified. | Do not say Calendar data stays entirely on device. Explain both layers and that permission can be disabled/revoked. |
| Weather / requested location or city | Weather presentation uses WeatherKit source authority and its attribution/legal metadata. Requested location/city supports weather lookup; continuous location collection is not established by this audit. | Apple weather service / requested lookup is an external service interaction; data sent to StyleMatch or an AI provider must be confirmed separately per request path. | Name WeatherKit/Apple only after final policy legal review; preserve Apple attribution obligations. |
| Notifications / push tokens | Source foundation describes an authenticated registration containing encrypted APNs token material/digest, preferences, opaque activity, and bounded timestamps; live delivery/retention deployment remains unproven. | `TRANSMITTED_TO_STYLEMATCH_SERVICE` and Apple APNs when activated. | Do not declare live APNs delivery or a retention period until physical/deployed evidence exists. |
| Shop AI and retailer links | Local shopping state can inform Shop AI. Retailer links are user-initiated and then governed by the retailer. Product availability, price, and discount facts are not fabricated. | Local state is `ON_DEVICE_ONLY` until submitted; Shop AI request context follows the AI classification. Retailer interaction is a third-party interaction after a user opens a link. | Disclose Shop AI context and separately identify retailer/affiliate practices only when verified. |
| Account/session identifiers | Source contains authenticated account/session routes and local account-scoped storage. | `TRANSMITTED_TO_STYLEMATCH_SERVICE`. | Verify deployed authentication, token/storage, retention, and deletion practices before final labels. |

## In-app consent and control reconciliation

| Surface | Current source evidence | Required correction before release |
| --- | --- | --- |
| AI Processing Consent | A dedicated control and disclosure exists in Profile. | Make the disclosure identify the categories that may be used for the specific AI request, the recipient(s), purpose, and effect of consent; confirm it matches the deployed route. |
| Calendar Context | Contextual opt-in, `requestFullAccessToEvents()`, disable/disconnect controls, and EventKit-change refresh exist. | Explain full Calendar access in plain language and distinguish raw local inspection from minimized contextual transmission. |
| Delete My Saved Data | Clears local account-scoped data, saved scan image assets, sensitive state, relevant defaults, and local API-key storage. | Keep the explicit device-only limitation. Name any data intentionally outside this local deletion scope only after verification. |
| Delete Account | An account-delete surface exists, but server-side purge and third-party/processor completion are outside this source-only audit. | Do not claim complete server/provider deletion until the live deletion workflow and retention exceptions are observed. |
| Style Friends actions | Publishing, friendship, block, report, and messaging require explicit user action and authenticated session. | Add a concise social-data explanation adjacent to primary social/support entry points; retain privacy settings as controls, not the primary social destination. |
| Notifications | System permission and preference UI exist; staging/deployment state is not policy proof. | Explain the device-token and preference use before enabling production delivery. |

## Documentation contradictions and gaps

1. `PrivacyPolicyAIMemoryDraft.md` still states that the active weather path
   uses Open-Meteo. The reviewed 18039 source has a WeatherKit authority with
   official attribution metadata. This is a policy-draft contradiction and
   must be corrected before publication.
2. The draft discusses Calendar Context but does not fully explain the two
   data layers: raw EventKit values stay within the sanitizer, while a
   minimized projection may be used in a requested AI interaction.
3. The draft Style Friends section predates the current DM and AI Customer
   Service surfaces. Social profile, DM, report/block, and Support must have
   distinct disclosures; Support must not be represented as a human DM.
4. `PrivacyInfo.xcprivacy` declares User ID, Device ID, Precise Location, and
   Other User Content only. It is not a complete App Store privacy answer and
   must be reconciled with the actual released social, message, support,
   notification, and optional CloudKit flows.
5. The public `https://stylematchpro.com/privacy` content is external to this
   worktree and could not be verified from source. Publication parity is
   therefore unproven.
6. Server, AI-provider, Apple-service, hosting, moderation, security-log,
   and retailer/affiliate retention are not established by an iOS source
   audit. Do not invent durations, processors, linkage, or tracking answers.

## App Store Connect release gate

Before an App Store privacy questionnaire is changed for Build 18038, require
all of the following:

1. A dated, owner/legal-approved public policy that incorporates the relevant
   rows above and identifies the verified controller/contact and processors.
2. A deployed-traffic and retention audit for authenticated social, DM,
   Support/AI, notification, account deletion, CloudKit, Shop AI, and
   retailer/affiliate flows.
3. A feature-by-feature mapping from the release build to App Store data-type,
   purpose, linkage, tracking, and retention selections. Do not use the
   privacy manifest as a substitute for this mapping.
4. Physical validation that each consent/control describes the released
   behavior and that revoke, disable, local deletion, sign-out, and account
   deletion have the documented distinct effects.

Until these conditions are met:

`APP_PRIVACY_RECONCILIATION = BLOCKED_PENDING_OWNER_LEGAL_AND_DEPLOYMENT_EVIDENCE`

## Owner decisions required

- Confirm the legal controller, support/privacy contact, public policy owner,
  and publication authority.
- Confirm every deployed service provider, AI provider, hosting/logging
  processor, retailer/affiliate relationship, and retention period.
- Confirm whether social, DM, Support, CloudKit, and APNs are enabled in the
  intended 18038 release, rather than merely present in beta source.
- Approve the final customer wording and App Store classifications after the
  deployment evidence is attached.
