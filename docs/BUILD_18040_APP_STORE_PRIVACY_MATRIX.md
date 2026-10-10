# Build 1.8040 App Store privacy reconciliation — DRAFT_OWNER_REVIEW_REQUIRED

| App Store disclosure topic | Code evidence | Proposed owner review action |
|---|---|---|
| Identifiers / account data | Apple subject-derived account and backend session | Confirm “linked to user” classification and retention in deployed D1. |
| User content | Ask messages, optional selected text, Style Friends messages/photos | Add if absent; identify functional purpose and processor disclosure. |
| Photos | Style Friends attachments; Ask V2 excludes raw scan images | Disclose social photo handling separately; do not label Ask V2 as photo transmission. |
| Purchases / tracking / advertising | No evidence in V2 transport | Do not assert “not collected” globally without reviewing analytics, affiliate and production configuration. |
| Diagnostics | Bounded admission state/provider-call metadata | Confirm whether it is linked to account and exact retention. |

Required changes are **proposed only**. No App Store Connect answer or website policy is changed by this document.

## Proposed policy addition

**Effective date: owner to set before publication.** StyleMatch uses account and session information to provide authenticated features. When you choose to use Ask StyleMatch and have accepted the current AI Processing Consent, StyleMatch may send your question and only the context scopes you select—such as limited profile, Closet, Weather, or completed scan facts—to the StyleMatch service and OpenAI to generate the requested response. Raw scan images are not part of the Ask StyleMatch V2 request. OpenAI acts as a service provider for that requested response. The service is configured not to create a provider conversation or background task and to request non-storage mode; these settings do not replace the applicable provider terms or legal retention obligations.

You can withdraw AI Processing Consent in the app; withdrawal stops new AI context transmission. You can use account deletion and available export controls for your StyleMatch data. Style Friends messages and authorized photos are governed by message deletion and attachment revocation controls. Contact method: owner must confirm the published support contact before this text is released.

## Exact in-app summary wording

“Ask StyleMatch sends your question only after you accept AI Processing Consent. You choose which limited context to include. Scan images are not sent; completed scan facts, if selected, include only score, classification, and summary. You can review or revoke consent in Profile → Your Privacy.”
