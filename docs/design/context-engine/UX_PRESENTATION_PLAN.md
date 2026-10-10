# Context Engine UX Presentation Plan

Status: **Proposal only — no UI implementation**

## 1. Goals

- Explain style, purpose, and appropriateness without crowding the Scan Results screen.
- Keep the existing Overall Style Score visually primary.
- Make uncertainty and confirmation easy to understand.
- Show safety/weather limitations without implying certification.
- Provide one predictable Change control for per-scan authority.

## 2. Information hierarchy

### Level 1 — Existing score card

Preserve:

- Overall Style Score;
- score label;
- detected visual style;
- existing breakdown access.

Do not insert purpose-specific values inside the numeric score.

### Level 2 — Context summary card

Compact default presentation:

```text
Outfit Context

Purpose                 Factory Work — Confirmed
Workplace Suitability   High
Weather Suitability     Good
Safety Suitability      Not verified

Change
```

If no workplace context applies, omit workplace rows rather than displaying meaningless values.

### Level 3 — Confidence and evidence disclosure

Collapsed by default:

```text
Why this context?  82% confidence
```

Expanded:

- visible workwear construction;
- Work occasion selected;
- embroidered text is present, but not retained;
- missing: footwear/safety requirements.

### Level 4 — Warnings

Show only material, supported warnings:

- safety limitation;
- severe weather conflict;
- confirmed occasion/workplace conflict.

Warnings are placed below the context card and above AI explanation. Do not show the current generic “Casual versus Work” warning when factory/warehouse/retail/etc. purpose is confirmed compatible.

## 3. Confirmation flow

### Specialized high confidence

Inline prompt:

> This appears to be a factory work uniform. Is that correct?

Actions:

- Yes, Factory Work
- Change
- Not sure

### Medium confidence

Bottom sheet with at most three evidence-supported purposes:

- Factory / Manufacturing
- Warehouse
- Other / Uncertain

### Low confidence

No preselected choice:

> Outfit purpose is uncertain. Choose a purpose for more relevant advice.

### Rejection

Rejecting the proposal returns to uncertain. It must not automatically choose the second-ranked purpose.

## 4. Change control

“Change” opens a searchable, grouped picker:

- Work;
- Events;
- Everyday and travel;
- Activity;
- School;
- Other / Uncertain.

If Work is chosen, request a workplace profile in the same sheet. The profile can remain Other / Uncertain.

Confirmation copy:

> Purpose updated for this scan. Your original style score did not change.

## 5. Compatibility indicators

Use text plus icon; color is supplementary:

- High — checkmark;
- Moderate — half-filled circle;
- Low — warning;
- Uncertain — question mark;
- Not applicable — hidden or neutral dash.

Accessibility labels include the metric and limitation:

> “Safety suitability, not verified, safety footwear is not visible.”

Do not use percentages for suitability during CE1–CE6.

## 6. AI explanation placement

The existing Personal Stylist Intelligence section should use:

1. one-sentence appearance/context summary;
2. one evidence sentence;
3. one missing-evidence sentence when material;
4. one highest-impact improvement with an advice label.

Example:

> This is a casual-looking factory work outfit, and the confirmed work purpose is compatible. Workwear construction supports that conclusion; safety footwear is not visible. Highest-impact improvement: refine the fit for a cleaner work presentation. Workplace advice.

## 7. Screen-specific behavior

### Scan Results

Full score + compact context + optional evidence.

### AI Assist

Header shows score, detected style, and confirmed purpose. The conversation uses the same scan/generation.

### AI Stylist Chat

When using latest scan:

> Using your latest scan: 80/100 · Casual · Factory Work

When using saved scan:

> Using saved scan from July 21: 74/100 · Everyday Casual

### Voice

Speak score, purpose, one suitability result, and one improvement. Avoid enumerating the entire context.

### Saved history

Add a small purpose label only when confirmed. Proposed/uncertain values are not displayed as settled history facts.

## 8. Uncertainty and privacy copy

- “Text or branding appears present, but StyleMatch Pro does not identify the wearer or employer.”
- “Purpose is uncertain because the image does not show enough workplace context.”
- “Safety suitability is not verified from a style photo.”
- “Choose a purpose if you want more specific advice.”

Never display raw OCR text by default.

## 9. Loading and correction states

- Context analysis may complete with the scan; do not block score display if context remains uncertain.
- Confirmation saves independently and updates context generation.
- Disable AI send briefly only while the correction is being persisted and reconciled.
- If reconciliation fails, preserve the previous confirmed state and show a recoverable error.

## 10. Accessibility and localization

- Dynamic Type must preserve row labels and values without truncating meaning.
- VoiceOver order: score, detected style, purpose, compatibility, warnings, Change.
- Avoid relying on slash-heavy names in speech; read “Factory or Manufacturing.”
- Localized strings must not interpolate raw OCR.
- Right-to-left and compact-width layouts stack labels above values.

## 11. Physical acceptance checklist

- No score-card regression.
- Context card remains readable at largest accessibility text size.
- Confirmation/rejection/correction paths work with VoiceOver.
- AI Assist/chat/voice match the displayed purpose and metrics.
- Stale screen context fails closed.
- No raw OCR, employer, wearer, or precise location appears.
- OCR/context latency is measured on supported iPhone hardware.
