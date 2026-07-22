# AR5 Test Change Inventory

Audited: July 21, 2026

The first AR5 full-suite run executed 531 tests and reported 32 failed assertions. Those failures were concentrated in legacy source-contract tests that required diagnostic strings or emitters removed by the approved app-wide privacy remediation. No runtime behavior test failed. Expectations were changed only where the old assertion required prohibited diagnostic output or used a removed no-op diagnostic helper as a source-range boundary.

## Legacy tests aligned with the privacy policy

| File and test | Old expectation | New expectation | Why the old expectation conflicted | Functional-regression protection |
| --- | --- | --- | --- | --- |
| `Build16FingerprintIntegrityTests.swift` — `testScanDebugUsesStableDigestPrefixAndVersion` → `testScanDebugDigestAndFingerprintContentIsNotEmitted` | Required `fingerprintVersion` and image-digest-prefix text in scan diagnostics. | Requires both markers and `logScanDebug` to be absent; retains the nondeterministic-hash ban. | Fingerprint and digest content are scan-derived identifiers and cannot be emitted. | All fingerprint reuse, exact digest matching, and deterministic scoring tests remain unchanged and pass. |
| `Build16PaletteTruthTests.swift` — `testGarmentCropSamplingRequiresErodedForegroundIntersection` | Required a diagnostic sentence for the skipped maskless crop. | Requires the foreground-mask threshold, fail-closed `nil` path, adaptive strong mask, and no center-crop fallback. | The sentence existed only to expose scan internals. | The actual mask threshold and skip behavior remain asserted. |
| `Build16PaletteTruthTests.swift` — `testEveryMaskedPaletteSourcePropagatesAdaptiveStrongEvidence` | Required a `strongCoverage` diagnostic field. | Requires adaptive erosion and strong-mask propagation; bans `print` in the candidate body. | Coverage text exposed internal scan evidence. | The data flow being tested remains asserted directly. |
| `Build16PaletteTruthTests.swift` — `testCredibleSourceDisagreementForcesLowConfidenceAndIsLogged` | Required ranked candidates, family shares, and disagreement diagnostic payloads. | Requires low-confidence enforcement plus corroborated-family and confidence-reason handoff; requires ranked diagnostic text to be absent. | Candidate rankings and family shares are scan-derived content. | The selector disagreement fixture and low-confidence policy remain unchanged and pass. |
| `Build16PaletteTruthTests.swift` — `testMasklessGarmentCropIsSkippedInsteadOfSamplingCenterSixtyPercent` | Required a skipped-sampling diagnostic sentence. | Requires the foreground threshold and continues to prohibit center-60 sampling and its helper. | The sentence was output-only. | The fail-closed sampling rule remains asserted from implementation structure. |
| `Build16PaletteTruthTests.swift` — `testFlatLayPaletteRegionDiscoveryRunsAfterAcceptanceWithoutChangingGate` | Required a `paletteRegionDiscovery` diagnostic marker. | Requires the palette-region helper, person-scan guard, and actual call; requires the marker to be absent. | The marker exposed scan-path internals. | Region discovery and acceptance ordering remain asserted. |
| `Build16PaletteTruthTests.swift` — `testScanPassesFlatLayBorderSamplesIntoIlluminantCalibration` | Required a naming-calibration diagnostic marker. | Requires background samples and their illuminant handoff; requires the marker to be absent. | Naming-calibration text exposed scan-derived values. | Calibration inputs remain asserted. |
| `Build16PerformanceTests.swift` — `testDebugLogEmitterRetainsTagsAndFlushesSerializedOutput` → `testSensitivePaletteAndScanStdoutEmitterIsRemoved` | Required the serial stdout queue, `print`, `fflush`, debug tags, and scan emitter. | Requires the emitter, queue label, stdout calls, and scan-debug wrapper to be absent. | AR5 explicitly prohibits app-owned stdout even in Debug. | This test governed diagnostics, not palette behavior; the full scan/palette suites remain intact. |
| `Build16PerformanceTests.swift` — `testPaletteRuntimeInstrumentationIncludesCallerCounterAndStageTiming` → `testPaletteRuntimeKeepsInternalStageTimingWithoutContentEmission` | Required call-stack capture, invocation counters, and detailed timing log strings. | Retains internal timing computation assertions while prohibiting call-stack, tracker, and color-debug output. | Call stacks and detailed scan timings were acceptance-rejected diagnostics. | Stage timing continues to feed internal extraction without emission; performance and palette tests pass. |
| `Build16TrustHardeningTests.swift` — `testRegionClassificationRunsAtFormerUnknownExitAndBeforeSceneQualifiedRejection` | Used debug verdict strings to prove branch ordering. | Uses the actual rejected/unknown return statements and region-validation calls to prove the same ordering; requires the old marker absent. | Debug strings were not behavior and leaked scan-path state. | The exact branch-order relationship remains asserted. |
| `Build16TrustHardeningTests.swift` — `testRejectedLabelWithoutEligibleSceneStillRejectsWithoutRegionAttempt` | Required a Debug failure print before the rejected return. | Requires the scene gate, region attempt, no print, and the same rejected return. | The print exposed classification content. | Rejection behavior remains directly asserted. |
| `Build16TrustHardeningTests.swift` — `testRegionDiagnosticLoggingIsDebugOnly` → `testRegionDiagnosticContentIsNotEmitted` | Required region diagnostics to exist inside `#if DEBUG`. | Requires all region diagnostic markers and scan-gate prints absent while retaining the region-validation helper. | The approved policy is zero sensitive output, not Debug-only output. | Region-generation, thresholds, and validation tests remain unchanged and pass. |
| `StyleMatchProPhase2Tests.swift` — `testStoreSearchUsesSharedWorkerBackedCatalogProvider` | Required a Store Search failure diagnostic containing the error. | Requires shared loader/filter use, safe user-facing failure copy, and the diagnostic marker absent. | Localized errors can contain URLs or query-derived content. | Loader, relaxed filter, and UI failure behavior remain asserted. |
| `StyleMatchProPhase2Tests.swift` — `testProfileEditsStayLocalAndDoNotCauseBackendRequests` | Used the removed no-op `logPantsSave` helper as the end boundary of `saveProfileDraft`. | Uses the next real function, `syncPersonalStylistProfile`, as the boundary. | The no-op helper existed only for diagnostics and accepted profile measurements. | The test still asserts local persistence and forbids URLSession, AccountService, chat transport, sharing, tasks, and awaits. |

## New or strengthened AR5 tests

These tests had no former expectation. They add coverage rather than replace behavior requirements.

### `StyleMatchProPhase2Tests.swift`

- `testThirdPartyAIConsentDefaultsAndMigratesToUnknown`: new and legacy users fail closed.
- `testThirdPartyAIConsentGrantDeclineAndWithdrawalAreFailClosed`: only current granted consent authorizes AI.
- `testConcurrentFirstUseActionsShareOneConsentDecision`: concurrent first-use actions share one decision.
- `testAIConsentTransportAndPhotoLocalitySourceContracts`: all AI paths are consent-gated and image providers are unreachable.
- `testProductionSourceContainsNoAppOwnedStdoutOrSensitiveDiagnosticFormatting`: zero direct stdout, request IDs, voice identifiers/language, prompt-debug formatters, or sensitive chat formatting.
- `testAppReviewWeatherAndPrivacyContracts`: WeatherKit entitlement, one provider, attribution component, legal link, privacy URL, and unchanged score boundary.
- `testAppleWeatherPermissionDenialUsesSavedCityOrPreservesLastKnownData`: denial does not invent weather.
- `testAppleWeatherUnavailableAndOfflinePreserveLastKnownData`: unavailable/offline behavior is last-known or unavailable.
- `testAppleWeatherStalenessBoundary`: stale weather is labeled and bounded.
- `testAppleWeatherContextHandoffUsesOnlyAvailableWeatherFacts`: stylist context receives only available facts.
- `testAppleWeatherFailurePathsAndStylistHandoffAreWired`: production failure and handoff paths use the shared policy.
- `testWeatherKitIsTheSingleWeatherProvider`: exactly one active WeatherKit fetch path and no Open-Meteo manager.

### `StylistChatServiceTests.swift`

- `testHTTP413RetainsStatusBodyRequestIDAndEndpointDiagnostically` → `testHTTP413RetainsOnlyPrivacySafeStatusDiagnostic`: replaces body/request-ID/endpoint retention with category plus numeric status only.
- `testLiveTransportUnknownConsentCreatesNoURLRequest`: unknown consent creates zero intercepted requests.
- `testLiveTransportDeclinedConsentCreatesNoURLRequest`: declined consent creates zero requests.
- `testLiveTransportWithdrawnConsentCreatesNoURLRequest`: withdrawn consent creates zero requests.
- `testLiveTransportOutdatedDisclosureCreatesNoURLRequest`: outdated consent creates zero requests.
- `testLiveTransportGrantedConsentCreatesOneSanitizedBackendRequest`: granted consent creates exactly one backend request, preserves bearer authentication, and excludes tokens and image forms from the body.
- `testConcurrentUnknownConsentAttemptsCreateNoURLRequests`: concurrent attempts cannot bypass the consent gate.

## Evidence that behavior was not weakened

- Focused AI-consent, WeatherKit, score, and privacy suites all pass.
- The full direct suite passes 531/531 after the expectation changes.
- Debug and Release simulator builds succeed.
- The final Debug and Release binary scans contain none of the rejected diagnostic markers.
- Scan scoring, deterministic fingerprinting, palette extraction, persistence, Shopping behavior, and user-facing failure tests remain present and passing.
