# Ask StyleMatch Intelligence Core — Build 1.8040

## Local implementation boundary

This checkpoint adds one user-facing Ask StyleMatch entry point and a typed
local request/router boundary. It makes **no provider request**, stores no AI
conversation, and changes no Worker contract. The provider seam emits only a
descriptor with `store: false`, `background: false`, and no conversation
reference. It is unavailable until a separately reviewed, server-enforced
contract is implemented in an isolated Worker lane.

## Specialty boundaries

| Specialty | Permitted local context | Explicitly excluded |
| --- | --- | --- |
| Fashion Stylist | Public fashion knowledge plus selected profile, closet, completed-scan facts, weather/occasion, and budget/brand scopes | Raw scan image, OCR, private messages, credentials |
| App Support | Public support knowledge and a coarse basic-account-status scope | Apple credentials, session tokens, diagnostic payloads, other specialties' context |
| Writing Assist | Only text explicitly supplied in the request | Conversation history, scan/profile/closet context, automated actions |

The router uses an explicit manual selection when supplied. A mixed automatic
request requires a clarification rather than combining data scopes. Current
research is explicitly unavailable locally and is never silently executed.

## Scan authority

`AskStyleMatchScanFacts` copies the completed scan authority's score,
classification, and summary exactly. It contains no image and has no score or
classification calculation capability. Ask StyleMatch may later explain these
facts but must never generate, change, round, or persist them.

## Future server gate

Before any live AI/provider capability, a separate Worker lane must add a
server-side typed contract, authentication and account isolation, rate and
spend controls, consent verification, audit-safe event metadata, moderation,
retention/deletion behavior, and provider-response validation. This iOS-only
checkpoint does not claim those controls are deployed.
