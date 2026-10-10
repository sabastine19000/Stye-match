# Backend and Provider Retention Evidence Audit — Draft

**INTERNAL DRAFT — NOT CUSTOMER-FACING — NOT FOR PUBLICATION**
**OWNER/LEGAL REVIEW AND VERIFIED BUSINESS FACTS REQUIRED**

Status: **No deployed backend or provider retention claim is established by this audit. Do not publish a fixed retention period from this document.**

## Confirmed from the current iOS source

- AI requests use the StyleMatch backend chat route at `/v1/chat` under the configured `https://api.stylematchpro.com` base URL.
- The request can include chat messages and the app’s typed `ChatContext`; Phase 3 adds only a bounded relevant subset of active confirmed AI Memory facts to that context.
- Raw outfit images are not added by the AI Memory resolver.
- The client sends an authorization bearer token when an authenticated session is available.
- The client can derive and hash a device identifier for chat transport. The local source does not establish server retention or linkage behavior for that hash.

## Local candidate Worker source — not production evidence

The separately checked local candidate Worker checkout is on its own dirty `main` worktree. Its source and bindings may describe intended behavior, but this audit did not access a deployed Worker, its data stores, provider dashboards, Cloudflare settings, or operational logs. The following are therefore **not publishable production claims**:

- The candidate chat provider posts to the OpenAI Chat Completions API.
- Candidate account code sets a 30-day session lifetime, performs expired-session and expired-deletion-receipt cleanup during relevant account requests, and creates a 24-hour deletion receipt after an account deletion routine.
- Candidate account code includes Apple-token revocation and account/session deletion routines.
- Candidate rate-limit counters use TTLs in source (including one-hour account-exchange and hourly/daily rate-limit windows).
- Candidate configuration names Cloudflare Workers bindings for KV, D1, and R2, and includes a configured share domain. Source/configuration does not prove that any named binding, route, share flow, or cleanup task is deployed or operating.
- A separate local share-phase checkout contains source with a 30-day card TTL. It is not evidence of a deployed fixed shared-link retention period and must not be stated in a public policy.

## Evidence classification

| Topic | What is actually established | Publication posture |
|---|---|---|
| AI chat | iOS source can send a request to the configured StyleMatch backend; candidate Worker source can call OpenAI | Confirm deployed route/operator, provider terms, persistence, and logs before naming a processor or retention period |
| Authentication | iOS source has authenticated transport; candidate Worker source contains Apple exchange/session/deletion routines | Confirm production use, token storage, expiry, revocation, and deletion behavior |
| Sharing | App source has sharing routes; candidate source/configuration exists | Do not claim a fixed expiry, deletion, or cleanup policy |
| Catalog / affiliate | App source can open retailer links; local candidate catalog/affiliate source exists | Confirm active relationships, recipient data, logging, and tracking before disclosure |
| Security and operations | Candidate code contains rate limiting and Cloudflare bindings | Confirm IP/header, abuse, error, backup, and security-log collection and retention |

## App Review transmission finding

The current iOS source can send a customer message and structured chat context to the configured StyleMatch backend. The source further contains an authenticated automatic post-scan AI-upgrade route and a bounded classification-adjudication route. It does not prove the deployed backend/provider recipient or retention, but it means a public retention audit must cover more than a manually typed AI-tab question.

## Evidence still required from the deployed Worker, providers, and operations

- Whether chat prompts or responses are persisted, and for how long.
- Session and token expiry, revocation, and deletion behavior.
- Apple authorization-exchange records and refresh-token retention.
- Shared-score-link expiry, revocation, deletion, and cleanup behavior.
- Remote catalog request logging and affiliate processing.
- IP address, device-header, rate-limit, abuse-prevention, and security-log retention.
- Cloudflare, AI-provider, website analytics, cookie, retailer, and affiliate provider processing terms.
- Backup retention and restoration behavior outside the app’s local snapshot store.

## Publication conclusion

Use only conditional wording such as “where configured,” “subject to technical confirmation,” or “retained only as reasonably necessary” until primary production evidence is available.
