# Build 18035 App Review Rejection Remediation Audit

**INTERNAL AUDIT — NOT CUSTOMER-FACING — NOT FOR RESUBMISSION**
**INTERNAL IMPLEMENTATION RECORD — NOT CUSTOMER-FACING — NOT FOR RESUBMISSION**

Audit date: August 7, 2026. Apple reviewed **1.0 (18030)**. This document audits the current Build 18035 source baseline, whose app identity remains inherited as **1.8 (18034)**; “Build 18035” is a workstream label, not a CFBundleVersion claim.

## Scope and evidence limits

- Source inspected: the current `feature/build-18035-privacy-ai-memory-reconciliation` checkout at `27dedc5d9a2b08f8731f17747b37f3c119790916` before this documentation-only audit.
- A local candidate Worker checkout was read only. It is not deployment, processor, retention, or production-routing evidence.
- No backend, AI provider, WeatherKit account, Open-Meteo service, website, App Store Connect, device, secret, or production log was accessed.

## A. Third-party AI request path

### Immediate app recipient

`LiveChatTransport` sends a JSON `ChatRequest` to `https://api.stylematchpro.com/v1/chat`. It uses an authenticated bearer session when one is available. The app source establishes this immediate configured recipient only; it does not establish the deployed operator or downstream recipient.

The candidate Worker source contains an OpenAI Chat Completions call. This is evidence that OpenAI is a candidate downstream provider, **not** evidence that production uses OpenAI, what production sends, or how production retains data.

### Source-backed transmitted categories

| Category | Evidence / scope |
|---|---|
| Customer text | The typed chat draft; voice input becomes a local transcript and then follows the same text-send path. Recent conversation messages can also be included, subject to request limits. |
| Account/session | An authenticated bearer session is sent in the `Authorization` header. The live chat transport does not add the separately defined device-hash header. |
| Profile and preferences | Depending on the entry route and context-sharing branch: name, colors, brands, fit, sizes, budget, style/occasion/dress-code, shopping habits/past purchases, favorite outfits, and closet summary can enter the text context. |
| Scan and saved-history facts | Structured current or historical score, score breakdown, detected garments/style/palette, occasion, weather summary, limits, and scan/screen identifiers can enter context. Raw scan images are not fields of `ChatRequest`. |
| AI Memory | A relevant, bounded projection can enter request context: no more than 8 facts / 1,600 serialized characters. |
| Weather and Calendar-derived context | Weather/city summaries and selected occasion can enter context. A bounded local Calendar Context summary may be used when enabled; raw Calendar events are excluded by the typed contract. |
| Classification adjudication | A narrow structured input can include detected garment labels, confidence/candidate categories, apparel/accessory/person/marking booleans, selected occasion, and quality status. It explicitly excludes raw image bytes, raw OCR, profile, history, and chat memory. |
| Raw scan images | No production `ChatRequest` path includes image bytes. The image-provider adapter is disabled for outfit scans; its direct image-request code is DEBUG-only and has no active production caller. |

### Local-only or disabled/planned distinctions

- Vision analysis and numeric scan scoring are local.
- The generic AI provider adapters do not perform outfit-image analysis in the current product path; alternate providers are feature-flag disabled.
- The standard AI tab is `StylistChatView`; legacy/fallback and scan helper paths remain compiled and also construct `LiveChatTransport` requests.
- No deployed provider, provider retention, backend log, or server deletion behavior is proven by this source audit.

## B. Existing consent audit

### Implemented client-side guard

Build 18035 Phase 5A adds a versioned, identity-scoped `AITransmissionConsentStore`. Its only valid states are `undecided`, `accepted`, and `declined`; no stored decision, malformed record, or disclosure-version mismatch resolves as `accepted`. The existing “AI Awareness”/context-sharing toggle remains a separate context-selection control and is not migrated or treated as transmission consent.

`LiveChatTransport.send` is the shared fail-closed boundary. After local payload validation and before a `URLRequest` is constructed or `URLSession` is invoked, it requires the current decision to be `accepted`. `makeURLRequest` repeats the same guard as defense in depth. A declined or undecided decision returns a local consent-required error and starts zero network requests.

The AI Stylist chat surface presents a disclosure before an undecided interactive request: it identifies the immediate recipient (`https://api.stylematchpro.com/v1/chat`), describes bounded request categories and purpose, offers **Agree & Continue** and **Not Now**, and does not name an unverified production downstream provider. Profile exposes a separate AI Transmission Privacy setting to review the disclosure or revoke future AI transmissions. Revocation changes only the future-send decision; it does not delete local content or claim recall of prior transmissions.

### Bypass matrix

| Entry point | Current path | Pre-transmission authorization? |
|---|---|---|
| AI tab typed/starter prompt | `StylistChatView` → `StylistChatService` → `LiveChatTransport` | Disclosure before interactive send when undecided; shared transport blocks unless accepted |
| Voice Stylist | Speech transcript → same send path | Speech permission is separate; the shared transport blocks unless accepted |
| Scan “Ask the Stylist” / saved-scan handoff | Scan handoff → `StylistChatView` → transport | Shared transport blocks unless accepted |
| Scan AI Assist / design idea | `ScanView` → `OpenAIStylistClient` → transport | Shared transport blocks unless accepted |
| Fresh-scan AI recommendation upgrade | Post-score automatic `requestChatGPTRecommendationUpgrade` when signed in | Shared transport blocks unless accepted; no automatic consent is inferred |
| Classification adjudicator | Low-confidence/conflict path while signed in | Shared transport blocks unless accepted; narrow payload remains unchanged |
| Legacy AI / generic `AIStyleAdvisor` routes | Compiled helper paths → `OpenAIStylistClient` → transport | Shared transport blocks unless accepted |
| Closet and Shopping stylist actions | Route into AI/chat or helper paths | Shared transport blocks unless accepted |

### Audit conclusion

**Client implementation complete; release and App Review evidence still pending.** The transport guard and disclosed interactive chat route are source-backed. Required physical acceptance, deployed-backend/provider confirmation, policy publication, App Store disclosure reconciliation, and any App Review response remain separate gates.

### Smallest technically correct remediation

1. Perform physical acceptance for the disclosure, decline, later reconsideration, and revocation flows.
2. Confirm the deployed backend operator and any downstream AI provider before naming them publicly.
3. Reconcile the public policy and App Store privacy responses only with deployment-backed retention, logging, and processor facts.
4. Do not treat automatic scan upgrades or adjudication as consented until the shared transport observes an explicit accepted decision.

Likely implementation surface: `StylistChatTransport.swift`, `StylistChatService.swift`, `OpenAIStylistClient.swift`, `StylistChatView.swift`, `ScanView.swift`, current AI entry surfaces in `ContentView.swift` / `AIAssistantsView.swift`, `ProfileView.swift`, a new localized consent store/view, and focused tests proving every outbound route fails closed before consent.

## C. WeatherKit and weather-source audit

### Evidence

- The target contains `com.apple.developer.weatherkit`, WeatherKit imports, and a WeatherKit provisioning-profile reference.
- Unrouted or uncalled source includes `WeatherService.shared.weather(for:)` in `AIAssistantsView` and `WeatherAdvisor.fetchAdvice`.
- The active main-shell weather path is `ContentView` → `StyleMatchLiveWeatherManager` → `https://api.open-meteo.com/v1/forecast`; it receives location coordinates or a geocoded city, then saves displayed values in local preferences.
- Profile’s “Live Weather Status,” “Location Permission,” “Last Updated,” “Refresh Weather,” and “Change Weather City” controls open `WeatherStylingPanel`, which displays temperature, condition, forecast, wind, humidity, UV, and alert summaries. It has no Apple Weather mark, WeatherKit attribution, or WeatherKit legal-source link.

### Compliance status

**Unknown / deficient if any displayed data is WeatherKit-derived.** The source contains no WeatherKit attribution presentation. Apple documentation states that WeatherKit publishing requires attribution and exposes the Apple Weather mark and legal attribution URL via `WeatherService.attribution`. If WeatherKit is retained for displayed weather, every WeatherKit-derived display and transformed value needs the applicable attribution and legal link. [Apple WeatherKit attribution requirements](https://developer.apple.com/weatherkit/)

The current active Profile flow instead appears to use Open-Meteo. This contradiction must be resolved before responding to App Review: either verify a real WeatherKit display path and implement attribution, or separately authorize removal/reconciliation of unused WeatherKit entitlement/code and then audit Open-Meteo attribution/terms. This audit does not authorize either path.

### Minimum WeatherKit remediation if retained

- Fetch `WeatherService.attribution` alongside WeatherKit data.
- Display the supplied Apple Weather mark and a tappable `legalPageURL` wherever Apple weather data or a WeatherKit-derived transformed recommendation is presented, including Profile, Weather Styling, Home/Scan weather cards, and any AI-facing weather result.
- Preserve attribution with cached WeatherKit values for the valid cache lifetime; do not present a stale transformed value without its source attribution.
- Perform an on-device recording that shows the real WeatherKit route, Apple Weather mark, legal source link, refresh, and a location/city flow only after the implementation is compliant.

## D. App Store / policy reconciliation

- The public draft must not claim user authorization exists today. Add the in-app consent design and validate it before stating that AI data is sent with permission.
- The worksheet must be re-evaluated against the actual deployed backend/provider and the active Open-Meteo-versus-WeatherKit decision; `PrivacyInfo.xcprivacy` is not a complete privacy-label answer.
- The current policy draft, Terms draft, choices draft, retention audit, worksheet, checklist, and publication manifest have been annotated with this App Review gate. They remain internal and unpublished.

## E. Required remediation matrix

| Apple finding | Current implementation | Evidence | Status | Required change | Tests / physical evidence |
|---|---|---|---|---|---|
| 5.1.1(i)/5.1.2(i): data disclosure | Chat can send text plus structured context; deployed provider unknown | `ChatRequest`, `LiveChatTransport`, request builders | Noncompliant | Enumerate verified categories and recipient in in-app disclosure; verify downstream provider before naming it | Payload tests; UI copy/accessibility test; device recording of disclosure before first send |
| 5.1.1(i)/5.1.2(i): consent | Toggle defaults on; no shared transport guard; automatic scan routes exist | UI defaults and transport call sites | Noncompliant | Versioned affirmative consent + centralized fail-closed transport preflight + revocation | All entry-point, restart, revoke, decline, and automatic-route tests; device recording |
| 5.2.5: WeatherKit | Entitlement/imports exist; no attribution UI; active weather path is Open-Meteo | entitlement, WeatherKit calls, WeatherStylingPanel | Unknown / deficient | Decide provider; if WeatherKit retained, add Apple mark + legal link to every display | Unit/UI tests; device recording showing attribution and legal link |

## Stop condition

Do not resubmit, respond to Apple, publish a policy, update App Store Connect, sign, archive, upload, install, deploy, push, or tag based on this audit. Implementation requires separate authorization after the owner chooses the verified backend/provider disclosure and weather-provider direction.
