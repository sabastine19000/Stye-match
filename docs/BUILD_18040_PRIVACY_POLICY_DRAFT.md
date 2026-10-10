# StyleMatch Privacy Policy — Build 1.8040 draft

**OWNER_AND_LEGAL_REVIEW_REQUIRED**
**Effective date:** To be supplied before publication.
**Contact:** Owner must supply and approve the published privacy contact method.

## What we collect and why

StyleMatch processes account and session information to authenticate account features. It processes the information you provide to operate requested features, including Style Friends messages, reactions, and authorized photo attachments. It may process Profile, Closet, Weather, and completed scan information only where a feature is designed to use that information.

## Ask StyleMatch and OpenAI

When you request an Ask StyleMatch response and have accepted the current AI Processing Consent, StyleMatch sends your question and only the context categories you explicitly select to the StyleMatch Worker. Selected Writing Text is optional and is sent only when selected. Completed scan context contains score, classification, and summary; raw scan images are not sent by the Ask StyleMatch V2 request.

The Worker uses OpenAI as a service provider to generate the response. It requests provider non-storage mode and no background task or provider conversation (`store:false`, `background:false`, no conversation reference). These technical settings do not establish zero retention. OpenAI may retain data for abuse monitoring or as stated in its applicable policy and agreement; this must be reviewed before publication.

The Worker admission record stores a salted request digest, state, timestamps, and provider-call count for idempotency and accounting. It does not store the question, selected text, prompt, scan facts, or completion text in that record.

## Your choices

You may revoke AI Processing Consent in Profile → Your Privacy. Revocation blocks new Ask StyleMatch AI transmission; it does not itself promise retroactive deletion from a processor. Account deletion and available export controls are governed by the account feature’s implemented controls. Style Friends message deletion and photo attachment revocation are separate controls that affect authorized access; their exact retention periods require owner and legal review.

## Storage and sharing

Account/session state is stored using backend account storage and a Keychain-backed local session. Style Friends canonical messages, relationships, and reaction projections use D1; authorized photos use private R2 storage. Local device persistence may store feature state and consent state. Data is not described here as sold, used for advertising, or used for cross-app tracking because this local source audit cannot establish those claims for deployed analytics, contracts, or future configuration.

## Security limitations

StyleMatch uses authentication, authorization, scoped context, and deletion/revocation controls, but no system can guarantee absolute security. Do not include information you do not want processed for the feature you request.
