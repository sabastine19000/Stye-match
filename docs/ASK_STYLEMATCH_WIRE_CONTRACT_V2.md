# Ask StyleMatch Wire Contract V2

`POST /v1/chat` remains the sole chat endpoint. A request without
`contract_version` is the unmodified Build 1.8039 legacy request. A V2 request
sets `contract_version: 2` and receives the existing SSE framing.

## Request

```json
{
  "contract_version": 2,
  "client_request_reference": "5f0c1d22-7ac2-4c91-a4f6-3b830a2f1c30",
  "consent_version": "2026-08-13.ai-processing.v3",
  "mode_selection": { "kind": "manual", "mode": "fashion_stylist" },
  "granted_scopes": ["profile_preferences", "scan_summary"],
  "messages": [{ "role": "user", "content": "How can I style this?" }],
  "scan_facts": { "score": 84, "classification": "smart_casual", "summary": "Balanced outfit" }
}
```

`AskStyleMatchRequest.clientRequestReference` maps to the UUID string
`client_request_reference`. `modeSelection.automatic` maps to
`{"kind":"automatic"}`; `.manual(mode)` maps to
`{"kind":"manual","mode":mode.rawValue}`. The closed `mode` values are
`fashion_stylist`, `app_support`, and `writing_assist`. `grantedScopes` maps
to sorted, duplicate-free `AskStyleMatchScope.rawValue` strings. `question`
maps to one legacy bounded `messages` object with role `user`; no history is
silently acquired. `localeIdentifier` is local display/routing metadata and is
not transmitted. `scanFacts` maps only to `score`, `classification`, and
`summary`; raw images and scan identifiers are never serialized. Optional
`scan_facts` and `selected_writing_text` are omitted when absent, never null.

`selected_writing_text` is a bounded Unicode string carried only when
`selected_writing_text` is an approved requested scope. The Worker presents it
to the provider as quoted untrusted material, never as instructions.

## Admission and response

The Worker authenticates the bearer session, verifies current account-scoped
consent matching `consent_version`, validates the closed request shape, applies
rate/budget and moderation gates, and reserves account + request reference
before a provider call. It records no prompt, selected text, scan facts, or
completion. The provider request sets `store:false`, `background:false`, and
does not use a provider conversation object.

Successful V2 requests retain legacy SSE `data:` payloads and `[DONE]`.
Responses add `x-stylematch-contract-version: 2` and
`x-stylematch-client-request-reference`. Safe JSON errors retain the existing
`error` field and may be `idempotency_conflict`, `request_in_progress`, or
`request_already_completed`. A completed response is not replayed because its
content is intentionally not stored.

Provider retention is governed by the configured provider policy; `store:false`
is a provider request setting, not a claim of zero provider retention.
