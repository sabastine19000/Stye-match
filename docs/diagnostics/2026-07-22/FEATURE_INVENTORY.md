# StyleMatch Pro Feature Inventory

Date: 2026-07-22

## Authority map

| Feature | Entry points | Primary sources | State authority | Persistence/backend | Initial evidence |
|---|---|---|---|---|---|
| Home and daily styling | `ContentView`, `HomeView` | Home and PersonalStylist modules | Closet, weather, explicit occasion | UserDefaults/profile/weather | Existing automated suite |
| Scan acquisition | `ScanView`, camera/gallery picker | `ScanView.swift` | Scan engine | Local scan history | Existing scan tests |
| Scan results and saved scans | Scan result/history/detail | `ScanView.swift`, `Models.swift` | Scan score and saved scan identity | `outfitScanHistoryData` | B5 and scan regression tests |
| AI Assist | Scan result AI sheet | `ScanView`, context builder | Current scan handoff | Chat Worker | Automated context tests |
| Standalone AI Stylist | AI tab/chat | StylistChat modules | `CurrentScanContextProvider` plus typed screen context | Local conversations and Chat Worker | Automated chat tests |
| Voice transcription | Chat microphone | `StylistSpeechInputService` | One active recognition session | Speech/AVAudioSession | Simulator/unit evidence only |
| Closet | Closet tab/details | `ClosetView`, PersonalStylist storage | Verified Closet ownership | Local persistence | Existing full suite |
| Shopping | Products/Stores/link-out | Shopping modules | Catalog and retailer registry | Worker/cache/bundled catalog | IA1.1/D7-SL1 accepted |
| Profile and sizing | Profile, size profile | `ProfileView`, `ProfileStore` | Explicit user preferences | Local persistence | Existing full suite |
| Weather | Home/scan/stylist | Weather engines/managers | Supplied WeatherKit data | Weather cache | Existing tests; physical attribution separate |
| Sharing | Scan share flow | Scan/share-card modules | Current saved scan | Local card plus optional backend link | Existing share tests |
| Authentication | Welcome/profile | `AccountService`, login views | Apple/backend session | Keychain/backend | Existing automated tests; physical login separate |
| Conversation persistence | Chat history/history picker | `ChatConversationStore.swift` | Conversation ID and ordered typed turns | Atomic JSON primary plus backup | Corruption/pruning/backup-refresh tests |
| Draft and keyboard state | AI chat composer | `StylistChatView.swift` | View draft plus speech draft snapshot | In-memory for active view | Source-contract and lifecycle tests; physical stress pending |
| Garment classification | Scan analysis and correction control | `Models.swift`, `ScanView.swift` | Typed classification plus optional user correction | Embedded in saved analysis | 14 focused taxonomy/compatibility tests |
| OCR evidence | Scan preprocessing | `ScanView.recognizeGarmentText` | Transient observations only | Not persisted raw | Source/privacy audit; device accuracy pending |
| Outfit voice summary | Scan result playback | `VoiceScriptBuilder.swift` | Confirmed typed scan context | None | Automated contract tests; physical playback pending |

## Known duplicate or competing paths

- Scan-specific context construction and standalone chat resolution converge on the typed provider, but some legacy consumers still read `styleBalance` directly.
- Current-scan history is decoded independently for full metadata and saved-ID availability.
- Stale conversation protection currently combines typed authority with response-text inspection.
- Multiple voice implementations exist (`StylistSpeechInputService`, `VoiceStylistService`, and Voice Assistant services); their responsibilities must remain clearly separated between transcription and spoken playback.
- `StylistScreenContext` models tab-level evidence and scan identity but does not model a selected Shopping product, store card, favorite, permission sheet, or detailed loading/error provenance. Generic chat therefore must not claim those unsupported details.
- Home/Dress Me Today contracts exist in source and tests, but complete device evidence is not part of this checkpoint.

## Protected boundaries

- Shopping and retailer authorities are regression-audit only.
- Scores remain exclusively owned by the Scan engine.
- OCR must not persist raw garment text, probable names, employers, or private image content.
- Physical-device-only features cannot receive final PASS from local tests.

## Dependency and lifecycle notes

- Swift Package Manager reports no external package dependencies.
- Backend-dependent AI behavior is exercised with transports/mocks locally; production service behavior was not invoked.
- Current scan authority uses deterministic completion-time ordering with scan ID as an equal-time tie-breaker.
- Existing saved scans and chat messages decode without new required fields. No eager or destructive migration is introduced.
- Debug timing instrumentation contains only public stage labels and elapsed milliseconds.
