# AR5 Production Diagnostic Inventory

Audited: July 21, 2026

Scope: every Swift file in the `StyleMatchAI` production source tree. Search families included direct stdout (`print`, `debugPrint`, `dump`, `NSLog`), unified logging (`Logger`, `os_log`), localized error descriptions, absolute URLs, response bodies, request IDs, prompts, measurements, scores, account identifiers, and recommendation reasons.

## Disposition summary

| Source area | Sensitive capability found | Final disposition |
| --- | --- | --- |
| `AccountService.swift`, `StyleMatchAIApp.swift` | Hashed Apple/account identifier, authentication/session state, build/backend identity | Removed. No account identifier or authentication state is emitted. |
| `ProfileView.swift`, `LoginWelcomeView.swift` | Pants, waist, inseam, profile-name provenance | Removed. Profile storage and UI behavior are unchanged. |
| `OpenAIStylistClient.swift`, `ContentView.swift`, `AIAssistantsView.swift`, `AIStyleAdvisor.swift` | Prompt/request sizes, localized AI errors, developer-key status | Removed. Existing local assertions remain content-free. Request behavior is unchanged. |
| `StylistChatTransport.swift`, `StylistChatModels.swift`, `StylistChatService.swift`, `StylistChatView.swift`, `ChatConversationStore.swift` | Response bodies, request IDs, complete endpoints, underlying errors, chat/navigation content | Direct output removed. Diagnostic errors retain only an allowlisted category and numeric HTTP status. Conversation behavior and user-facing errors are unchanged. |
| `ScanView.swift`, `GarmentColorPaletteEngine.swift` | Labels, classifications, colors, fit, accessories, score components, fingerprints, image digests, mask/vision results, localized errors | Removed outright. No converted scan diagnostic remains. Scanning and scoring code paths are otherwise unchanged. |
| `StylistContextBuilder.swift`, `OutfitMemoryStore.swift`, `PersonalStylistSnapshotStore.swift`, `ProfileStore.swift` | Recommendation-reason payload, account-scoped identifier, store names and localized persistence errors | Removed. Persistence and context-building behavior are unchanged. |
| `ShoppingSearchProviders.swift`, `SaleWatcher.swift`, `StoreSearchView.swift`, `DisplayLabelSanitizer.swift` | Complete request URLs/query strings, product names/IDs, labels, localized errors | Removed. Search, sale, and sanitization behavior are unchanged. |
| `ProductCatalogProvider.swift`, `ShoppingView.swift` | Complete catalog URL, product IDs, localized decode errors, dynamic performance messages | Removed or converted to inert internal compatibility helpers. Catalog/filter/fallback behavior is unchanged. |
| `Services/VoiceStylistService.swift` | Unified playback lifecycle logging | Retained. Fields are limited to fixed stages, Boolean state, bounded text length, numeric timing/error codes, and audio-session enums. Spoken text, voice identifiers/language, and request UUIDs are never logged. |

## Final source rule

- Zero app-owned `print`, `debugPrint`, `dump`, or `NSLog` calls are permitted anywhere in production Swift source, including inside `#if DEBUG`.
- No diagnostic formatter may include prompts, AI responses, response bodies, request IDs tied to network activity, complete URLs, account identifiers, profile values, scan facts, location/city context, product content, authentication state, secrets, or localized error descriptions.
- User-facing localized error text is not a diagnostic and remains where needed for UI behavior.
- The only retained app-owned unified logger is the voice-playback lifecycle logger described above.

An automated source-contract test enforces the stdout ban and the chat diagnostic formatter restrictions.

## Submission provenance boundary

Apple reported reviewing StyleMatch Pro `1.0 (16)`. The locally identified archive with build number 16 is `1.6 (16)`. No evidence in this checkpoint proves that the exact reviewed binary was reproduced. The remediation addresses every defect Apple identified—external-AI consent and disclosure, business-model clarity, WeatherKit attribution, and the public privacy-policy URL—but must not be described as a byte-for-byte reconstruction of the reviewed submission.
