# Outfit Sharing Real-Device Validation Checklist

Use this checklist on the exact build intended for device approval. Record any failure with the device, iOS version, share-card format, and steps to reproduce.

## Test setup

- [ ] Install a fresh development build on a physical iPhone.
- [ ] Confirm the build/version shown in Xcode matches the intended device build.
- [ ] Prepare one completed live scan and one saved scan with a known photo, score, category scores, description, recommendations, and scan date.
- [ ] If available, prepare saved scans with no photo, no category scores, no recommendations, and an unusually long description.

## Completed scan result

- [ ] `Share Outfit` is visible after a scan completes.
- [ ] `Scan Again`, Save, Reanalyze, and existing result controls remain usable and are not displaced.
- [ ] Tapping `Share Outfit` opens `Share Preview` before the system Share Sheet.
- [ ] Photo sharing defaults off; overall score, category scores, description, suggestions, and branding default on.
- [ ] Each privacy toggle immediately updates the preview and exported card.
- [ ] The displayed scan date matches the completed scan.

## Card formats and appearance

- [ ] Square Post renders correctly in light appearance.
- [ ] Square Post renders correctly in dark appearance.
- [ ] Portrait Story renders correctly in light appearance.
- [ ] Portrait Story renders correctly in dark appearance.
- [ ] A saved square image is 1080 x 1080 pixels.
- [ ] A saved portrait image is 1080 x 1920 pixels.
- [ ] A long outfit description remains inside the card without overlap or broken layout.
- [ ] Up to three recommendations appear; a fourth recommendation never appears.

## Missing and fallback content

- [ ] A scan with no photo shows the score-only message, disables the photo toggle, renders, and shares without crashing.
- [ ] Missing category scores are omitted and the category toggle is disabled.
- [ ] Missing recommendations show: `This outfit is already well coordinated. Small accessory or fit adjustments may improve the score further.`
- [ ] Rendering failure, if induced, shows `We couldn’t prepare this outfit card. Please try again.` without technical details.

## Saved-scan consistency

- [ ] Record the saved scan's photo, overall score, categories, description, recommendations, and date before sharing.
- [ ] Share from the saved-scan row action, swipe action, context action, and opened saved detail.
- [ ] Every entry point uses the same stored photo, score, categories, description, recommendations, and date.
- [ ] Opening or sharing the saved scan does not show analysis progress, make the camera/photo picker appear, change a score, or add another history entry.

## Native Share Sheet

- [ ] The editable caption starts with the stored overall score and can be changed or disabled.
- [ ] No App Store link is shared when no official link is configured.
- [ ] Share successfully to Messages and at least one other installed destination.
- [ ] AirDrop appears when available.
- [ ] Save Image works only when selected by the user.
- [ ] Copy works when offered by the destination list.
- [ ] Cancelling the Share Sheet returns safely with no error alert.
- [ ] Reopening and sharing again after cancellation works.

## Accessibility and adaptive layout

- [ ] VoiceOver reads `Share Outfit` with a useful hint.
- [ ] VoiceOver reads the score as a value out of 100.
- [ ] VoiceOver identifies both format choices, both appearance choices, all privacy controls, caption controls, and the Share Card button.
- [ ] VoiceOver reads the generated card as one concise summary rather than many decorative elements.
- [ ] Preview remains usable at the largest Accessibility Dynamic Type size.
- [ ] Preview remains usable in light mode and dark mode with sufficient contrast.
- [ ] Test portrait and landscape orientation wherever the app currently supports both.
- [ ] Test on the smallest and largest available iPhone sizes, or equivalent Simulator sizes if only one physical iPhone is available.

## iPad presentation

- [ ] Open Share Preview on a physical iPad or iPad Simulator in portrait.
- [ ] Open the system Share Sheet; it is anchored and does not crash with a popover exception.
- [ ] Repeat in landscape and after rotating while Share Preview is open.
- [ ] Dismiss by cancellation and complete one share; both return safely to the preview.

## Privacy, network, and resilience

- [ ] Preview and card rendering work in Airplane Mode, confirming no new upload is required.
- [ ] The card and caption contain no email, Apple account data, profile fields, clothing sizes, location, weather city, private identifiers, AI prompts, API responses, or debug text.
- [ ] The original outfit image is included only when the photo toggle is explicitly enabled.
- [ ] Completing or cancelling a share does not create an app-managed duplicate image.
- [ ] Repeat share/cancel at least ten times with a high-resolution photo; the app remains responsive and does not retain stale cards.
- [ ] Background and resume the app from Share Preview and from the Share Sheet; the app returns safely.

## Sign-off

- Device:
- iOS version:
- App version/build:
- Date:
- Result: Pass / Fail
- Issues or screenshots:
