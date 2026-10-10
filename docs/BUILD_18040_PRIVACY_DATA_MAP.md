# Build 1.8040 privacy data map — DRAFT_OWNER_REVIEW_REQUIRED

## Ask StyleMatch V2

| Data | Purpose and destination | Storage / retention boundary |
|---|---|---|
| Apple subject and opaque StyleMatch account/session | Authenticate the request to the StyleMatch Worker | Backend account/session records; iOS session is Keychain-backed. |
| Question and selected writing text | Requested AI response; selected text is optional and explicitly scoped | Sent only after current AI Processing Consent. The V2 admission table stores no plaintext question, selected text, prompt, scan facts, or completion. |
| Consent version, mode, granted scopes, request reference | Enforce consent, minimize context, idempotency and provider-use accounting | Worker stores salted canonical digest, state, timestamps and provider-call count. |
| Profile, Closet, Weather, budget and immutable scan facts | Optional, scoped answer context | Only the selected allowlisted scope is serialized. Scan facts are score/classification/summary only; raw scan images are excluded. |
| Style Friends text, photos and reactions | Separate social features | D1 canonical message/projection data; photos are private R2 objects subject to attachment authorization, deletion and revocation. |

OpenAI is a processor for a requested Ask StyleMatch response. The V2 provider request uses `store:false`, `background:false`, and no provider conversation reference. This does not prove that every processor or infrastructure log has zero retention; owner review of the deployed provider agreement and infrastructure settings is required.

No source evidence supports advertising, sale, cross-app tracking, or a tracking identifier in Ask StyleMatch. This is a source-level finding only and must be confirmed against production analytics, contracts, and App Store Connect before publication.

## Controls

Consent may be revoked from Profile → Your Privacy → AI Processing Consent. Revocation blocks further AI transmission; it does not claim retroactive deletion from third parties. Account deletion, export, and Style Friends deletion/revocation remain governed by their existing account and attachment authorities.
