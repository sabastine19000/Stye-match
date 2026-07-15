# Build 1.6 Running Real-Device Validation Checklist

Record the app version/build, device model, iOS version, network type, and test time for every session. If a test fails, capture a screenshot or screen recording, the exact taps leading to the failure, whether it reproduces after relaunch, and relevant macOS Console entries from the same timestamp. Never include outfit images, spoken text, account tokens, email addresses, or other private content in shared logs.

## Login and account

- [ ] Apple sign-in and session restoration
  - Steps: Launch signed out, choose Continue with Apple, finish authorization, force-quit, and relaunch.
  - Expected: Sign-in completes once; the correct profile returns after relaunch without another prompt.
  - Capture if it fails: Authorization screen/error, timestamp, device/iOS, and sanitized account/auth Console messages.
- [ ] Guest mode isolation
  - Steps: Enter as guest, change a profile preference and save a scan, sign into Apple, then inspect profile and history.
  - Expected: Guest data does not silently appear in a different account namespace unless the app explicitly offers and completes a transfer.
  - Capture if it fails: Which values crossed accounts, the transition sequence, and screenshots without personal data.
- [ ] Account switching and sign-out
  - Steps: Sign out from Profile, confirm the signed-out screen, sign into a different test account, then switch back.
  - Expected: Each account sees only its own profile, scans, and settings; sign-out never leaves private screens visible.
  - Capture if it fails: Account sequence, affected data category, and sanitized logs.
- [ ] Account deletion
  - Steps: Use a disposable test account, choose Delete Account, read and confirm the warning, complete fresh Apple authorization if requested, then sign in again.
  - Expected: Remote revocation/deletion succeeds, local profile/history/images/credentials are cleared, and a fresh sign-in starts cleanly.
  - Capture if it fails: User-facing message, HTTP status or sanitized error stage, and whether local data remained. Never capture tokens.

## AI Stylist

- [ ] Normal response and score ownership
  - Steps: Open AI Stylist from a completed scan and ask it to explain the result and suggest an improvement.
  - Expected: It explains the stored analysis and recommendations without inventing or changing scores.
  - Capture if it fails: Redacted question/response, displayed stored score, and request timestamp.
- [ ] Loading, cancellation, and recovery
  - Steps: Send a request, observe loading, leave and return, then retry after completion or cancellation.
  - Expected: Only one request is active, loading clears, navigation remains responsive, and retry works.
  - Capture if it fails: Screen recording, timing, network type, and sanitized request lifecycle logs.
- [ ] Network failure
  - Steps: Turn on Airplane Mode, submit a request, restore connectivity, and retry.
  - Expected: A friendly error appears, no private/debug details are exposed, and retry succeeds without duplicate messages.
  - Capture if it fails: Exact user-facing copy, timestamps, and network transition.

## Voice Assistant

- [ ] Preview Voice in Silent Mode
  - Steps: Enable spoken guidance, set the Ring/Silent switch to Silent, raise media volume, then use Profile > Voice Assistant > Preview Voice.
  - Expected: Speech is audible through the speaker and speaking state begins only when playback starts.
  - Capture if it fails: Device/iOS, volume, output route, user-facing error, and Console subsystem `com.sabastine.stylematchai`, category `VoicePlayback`.
- [ ] Scan-result speech path
  - Steps: Complete a scan and tap Listen to Score Summary with Silent Mode both on and off.
  - Expected: It uses the same corrected playback path as Preview Voice, speaks once, and returns to idle.
  - Capture if it fails: Which entry point failed, route, status shown, and VoicePlayback logs.
- [ ] Interruption recovery
  - Steps: Start speech, interrupt with Siri, a call, or an alarm, end the interruption, and retry.
  - Expected: Speaking state stops truthfully, a clear retry path is available, and later playback succeeds.
  - Capture if it fails: Interruption type/timing and VoicePlayback interruption events.

## Outfit scanning

- [ ] Camera and gallery scans
  - Steps: Scan one worn outfit with Camera and the same image from Photos.
  - Expected: Both complete without a crash; detected items and scores are plausible and nearly consistent for identical pixels.
  - Capture if it fails: Input source, lighting, elapsed time, result screenshot, and sanitized scan-stage logs.
- [ ] Content variety
  - Steps: Test a flat lay, worn outfit, accessory-heavy outfit, sleepwear, and bright/dim lighting.
  - Expected: Classification does not hang or use an obviously wrong garment noun; uncertain items use neutral wording.
  - Capture if it fails: Test category, photo conditions, incorrect output, and scan-stage timing.
- [ ] Repeatability, cache, and reanalysis
  - Steps: Scan the exact same image twice, save it, reopen it from History, then explicitly choose Reanalyze.
  - Expected: Reopening preserves the exact stored scores; repeated identical input is nearly stable; only Reanalyze starts new analysis.
  - Capture if it fails: All score sets, action sequence, timestamps, and whether a network call occurred.

## Profile

- [ ] Size and preference persistence
  - Steps: Edit shirt, pants, waist, inseam, shoe size, fit, colors, brands, budget, weather, and closet fields; save and relaunch.
  - Expected: Values remain synchronized and persist exactly for the active user.
  - Capture if it fails: Field names and before/after values, account mode, and screenshots.
- [ ] Voice preference persistence
  - Steps: Toggle spoken guidance, choose a voice/rate if available, relaunch, and preview.
  - Expected: Settings persist and preview reflects them.
  - Capture if it fails: Changed settings, relaunch result, and VoicePlayback logs.
- [ ] Migration/no demo defaults
  - Steps: Update over the previous beta, open Profile, and inspect every section.
  - Expected: Legitimate saved data migrates; founder/demo values do not appear in a new or unrelated account.
  - Capture if it fails: Previous/current build and unexpected fields, without private values.

## Shopping

### Phase 1 — honest missing-image behavior

- [ ] 1. Recommendation-card fallback
  - Steps: Open Shopping and locate a recommended product whose catalog record has no image URL.
  - Expected: The existing card dimensions remain stable and a local bag icon appears without a broken-image flash.
  - Capture if it fails: Product ID, screenshot or recording, device/iOS, timestamp, and any image-request host shown by the network inspector.
- [ ] 2. Search-result fallback
  - Steps: Search for a product known to have no image URL and scroll it on and off screen several times.
  - Expected: The same local bag fallback appears every time; scrolling stays smooth and no remote placeholder request starts.
  - Capture if it fails: Search query, product ID, recording, and sanitized network-request list.
- [ ] 3. Saved/favorite-product fallback
  - Steps: Favorite a product with no image, leave Shopping, relaunch the app, and reopen the saved/favorites surface.
  - Expected: The favorite persists and uses the identical local fallback without layout movement or a crash.
  - Capture if it fails: Product ID, persistence result, screenshot, and crash report if applicable.
- [ ] 4. Product-detail fallback
  - Steps: Open the detail view for a product with no image, rotate the device if currently supported, then return to the list.
  - Expected: Detail layout reserves the intended image area, shows the local fallback, and navigation remains stable.
  - Capture if it fails: Product ID, orientation, before/after screenshots, and navigation sequence.
- [ ] 5. VoiceOver missing-image announcement
  - Steps: Enable VoiceOver and focus the image area of a product without an image on each available shopping surface.
  - Expected: VoiceOver announces “No product image available” once and does not read a fake URL or unlabeled icon.
  - Capture if it fails: Surface, spoken label/focus order, and a safe screen recording.
- [ ] 6. Blank image-value handling
  - Steps: Using a test/catalog item whose image field is blank or whitespace, open its card and detail view.
  - Expected: It behaves exactly like a missing image and initiates no image network request.
  - Capture if it fails: Product ID, raw field classification as blank (not private payload data), screenshot, and network evidence.
- [ ] 7. Invalid image-value handling
  - Steps: Using a test/catalog item with a malformed or non-HTTP(S) image value, open every surface where it appears.
  - Expected: The value is rejected locally, the bag fallback appears, and the app neither crashes nor attempts that URL.
  - Capture if it fails: Product ID, URL scheme only, affected surface, crash log, and sanitized network evidence.
- [ ] 8. Valid HTTPS image behavior
  - Steps: Open a product with a confirmed HTTPS image URL in recommendations, search, favorites, and detail, if one exists in the test catalog.
  - Expected: Its real image continues loading normally; a genuine load failure falls back locally without changing card size.
  - Capture if it fails: Product ID, sanitized image host/status, connection type, and screenshots.
- [ ] 9. Light/dark mode and Dynamic Type layout
  - Steps: View missing-image cards in light and dark mode at default and largest accessibility text sizes on the smallest available iPhone.
  - Expected: The fallback remains visible and legible, card sizes remain consistent, and text does not overlap or clip controls.
  - Capture if it fails: Device, appearance/text settings, shopping surface, and screenshot.
- [ ] 10. Offline and repeated-loading stability
  - Steps: Load Shopping online, enable Airplane Mode, relaunch, repeatedly open/close missing-image products, then restore connectivity.
  - Expected: Cached/offline behavior remains intact, missing images never trigger retries to a fabricated host, and the UI recovers without a crash.
  - Capture if it fails: Cache precondition, product ID, transition timing, exact message, request list, and crash report.

### General shopping validation

- [ ] Catalog, filters, favorites, and outbound link
  - Steps: Load Shopping, search/filter/sort, save and unsave an item, open detail, then tap the buy link.
  - Expected: Results remain consistent, price/merchant are correct, favorites persist, and the approved merchant destination opens safely.
  - Capture if it fails: Query/filter, product ID, destination host/status, and screenshots. Do not capture affiliate secrets.
- [ ] Backend unavailable
  - Steps: Load once online, enable Airplane Mode, relaunch Shopping, search, and tap a product.
  - Expected: The approved cached/offline catalog or a clear empty/error state appears; no crash or fake product image occurs.
  - Capture if it fails: Whether a cache existed, exact copy, product ID, and network logs.

## Sharing

- [ ] Preview privacy controls
  - Steps: Share a completed scan, toggle photo, overall score, category scores, description, suggestions, and branding individually.
  - Expected: Preview updates accurately and never includes email, profile, sizes, location, identifiers, prompts, or raw API data.
  - Capture if it fails: Toggle combination and a redacted preview screenshot.
- [ ] Square and portrait cards
  - Steps: Render both formats in light and dark mode with normal and very large Dynamic Type.
  - Expected: Photo, scores, date, description, and up to three stored recommendations fit without clipping or overlap.
  - Capture if it fails: Format, appearance settings, text size, and exported card.
- [ ] Saved scan and missing-data sharing
  - Steps: Share a saved scan, then a scan with no available photo or recommendations.
  - Expected: Saved values remain exact; missing photo produces a score-only card; recommendation fallback is safe and no reanalysis occurs.
  - Capture if it fails: Stored versus shared values and whether network/analysis activity started.
- [ ] Share sheet and cancellation
  - Steps: Open Share, cancel, reopen, share to Messages or AirDrop, and choose Save Image. Repeat on iPad if available.
  - Expected: Cancellation is harmless, image/caption are present, no fake App Store URL appears, and iPad presentation is anchored without a crash.
  - Capture if it fails: Device/orientation, chosen activity, screenshot, and crash log.

## Camera and photo library

- [ ] First-use permissions
  - Steps: On a fresh install, deny Camera and Photos separately, retry, follow the Settings recovery path, grant access, and retry.
  - Expected: Denial shows useful guidance, Settings recovery works, and capture/picking succeeds after permission is granted.
  - Capture if it fails: Permission state from Settings, exact message, and screen recording.
- [ ] Limited Photos access
  - Steps: Grant Limited Photos access, select an allowed image, then try to add another allowed image.
  - Expected: Picker respects limited access and never exposes an unapproved asset.
  - Capture if it fails: iOS permission state and picker behavior, without sharing private photos.
- [ ] Background/rotation handling
  - Steps: Open the camera or picker, rotate if supported, background and foreground the app, then cancel and reopen.
  - Expected: UI remains correctly sized and responsive with no duplicate picker or lost navigation state.
  - Capture if it fails: Device/orientation, exact transition, and crash log if any.

## Notifications

- [ ] Permission allow/deny
  - Steps: Exercise the notification opt-in once with Deny and once after enabling it in Settings.
  - Expected: The app respects the choice, does not loop prompts, and clearly reflects disabled status.
  - Capture if it fails: Authorization status, number of prompts, and screenshot.
- [ ] Notification routing
  - Steps: Open each available test notification from foreground, background, and terminated states.
  - Expected: It opens the intended existing destination without a dead end or duplicate navigation.
  - Capture if it fails: Notification type/payload with private fields removed and launch state.

## Performance and battery

- [ ] Cold and warm launch
  - Steps: Time launch after force-quit, then background/foreground five times.
  - Expected: Home becomes interactive consistently with no prolonged blank screen or rising delay.
  - Capture if it fails: Five timings, device/iOS, storage free, and Instruments trace if available.
- [ ] Scan resource use
  - Steps: Run five representative scans while watching Xcode memory/CPU and device temperature.
  - Expected: Memory returns toward baseline, UI remains responsive, and the device does not sustain severe thermal state.
  - Capture if it fails: Per-scan times, peak memory/CPU, thermal warning, and input dimensions.
- [ ] Battery/network/disk
  - Steps: Use scans, AI, shopping, and sharing for 20 minutes; review battery impact, network requests, and app storage.
  - Expected: No unexplained request loop, runaway cache, excessive background work, or abnormal drain.
  - Capture if it fails: Battery delta, request counts/hosts, storage before/after, and energy log.

## Accessibility

- [ ] VoiceOver navigation
  - Steps: Enable VoiceOver and traverse Login, Home, Scan Result, Profile, Shopping, Sharing, and account actions.
  - Expected: Controls have meaningful labels/order, scores are understandable, missing images are announced, and destructive actions are explicit.
  - Capture if it fails: Screen/control, spoken label, focus order, and recording if safe.
- [ ] Dynamic Type and screen sizes
  - Steps: Test smallest/default/largest accessibility text on the smallest available iPhone and a large iPhone.
  - Expected: Text wraps or scrolls without hiding controls, overlap, or horizontal clipping.
  - Capture if it fails: Device, text size, orientation, and screenshot.
- [ ] Appearance and accessibility settings
  - Steps: Test light/dark mode, Increase Contrast, Reduce Motion, and Reduce Transparency.
  - Expected: Content remains legible, meaningful state is not color-only, and navigation remains usable.
  - Capture if it fails: Setting combination and screenshot.

## Bluetooth and audio

- [ ] Speaker, AirPods, and Bluetooth output
  - Steps: Play Preview Voice through speaker, AirPods, and another Bluetooth route; change routes between attempts.
  - Expected: The selected route is used and state returns to idle after speech.
  - Capture if it fails: Route type, connect sequence, volume, and VoicePlayback logs.
- [ ] Route removal during speech
  - Steps: Start speech through AirPods, disconnect them mid-sentence, then retry through speaker.
  - Expected: Playback stops cleanly with truthful state/a safe message and retry succeeds.
  - Capture if it fails: Route-change reason and VoicePlayback logs.
- [ ] Other audio coexistence
  - Steps: Play music/podcast audio, invoke voice playback, then finish or cancel it.
  - Expected: Spoken guidance is intelligible and audio-session behavior recovers predictably afterward.
  - Capture if it fails: Source app, route, before/after state, and audio logs.

## Offline behavior

- [ ] Offline launch and local data
  - Steps: Load the app online once, enable Airplane Mode, force-quit, relaunch, and open Profile and saved scans.
  - Expected: Local data remains available and remote-only areas show safe, actionable errors.
  - Capture if it fails: Screen, cache precondition, message, and crash log.
- [ ] Connectivity transition
  - Steps: Start AI, shopping, or another remote action on poor/offline connectivity, restore connectivity, and retry once.
  - Expected: The first request times out safely; retry works without duplicates or stale loading.
  - Capture if it fails: Network transition/timing, duplicate count, and sanitized lifecycle logs.

## Edge cases

- [ ] Rapid repeated taps
  - Steps: Rapidly tap Scan, Save, Reanalyze, Share, buy link, sign-out, and delete confirmation controls.
  - Expected: Expensive/destructive actions execute at most once and navigation does not stack duplicates.
  - Capture if it fails: Screen recording, tap count, duplicate effects, and logs.
- [ ] Low storage and large photo
  - Steps: With a safe low-storage test condition, import a very large photo, scan it, save it, and generate both share cards.
  - Expected: The app downsizes/handles it without termination and shows friendly errors if work cannot complete.
  - Capture if it fails: Free storage, image dimensions/file size, memory warning, and crash report.
- [ ] Backgrounding during work
  - Steps: Background and foreground during scan analysis, AI response, image rendering, and account action.
  - Expected: No false completion, corrupted save, duplicated request, or stuck loading state.
  - Capture if it fails: Stage and exact timing, resulting state, and lifecycle logs.
- [ ] Long and missing content
  - Steps: Open records with long names/descriptions and legitimately missing optional photo, category score, recommendation, or product image data.
  - Expected: Layout remains stable, local fallbacks are honest, and no force-unwrap crash occurs.
  - Capture if it fails: Data condition, screen size/text size, screenshot, and crash report.
