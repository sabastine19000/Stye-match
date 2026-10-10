# Personal Color & Fit Profile

Status: Planning spec only. Not approved for Beta 2.0 implementation.

Date: 2026-07-14

## Goal

Improve recommendation relevance using optional color-palette assistance and fit preferences while preserving StyleMatch Pro's core guardrails:

- Deterministic outfit scoring must not change.
- No new Worker endpoints.
- No face imagery, raw body measurements, raw skin samples, or sensitive identity traits leave the device.
- Any inferred signal is presented as a user-correctable suggestion, never as a fact.
- Manual preferences remain available even when camera assistance is skipped.

## Current Codebase Fit

The current app already has several integration points that make this feasible as a future local personalization feature:

- Profile storage: `StyleMatchAI/PersonalStylist/StylistProfileModels.swift`, `StyleMatchAI/PersonalStylist/ProfileStore.swift`, `StyleMatchAI/PersonalStylist/PersonalStylistStorage.swift`
- Profile editing and onboarding: `StyleMatchAI/ProfileView.swift`, `StyleMatchAI/OnboardingView.swift`
- AI context: `StyleMatchAI/PersonalStylist/StylistContextBuilder.swift`
- Shopping recommendations and rationales: `StyleMatchAI/Shopping/ShoppingRecommendationEngine.swift`, `StyleMatchAI/Shopping/RecommendationRationaleBuilder.swift`
- Scan and palette systems: `StyleMatchAI/ScanView.swift`, `StyleMatchAI/GarmentColorPaletteEngine.swift`, `StyleMatchAI/Models.swift`
- Local deletion/privacy inventory: `StyleMatchAI/PrivacyDataManager.swift`

The existing profile model already includes `favoriteColors`, `dislikedColors`, `favoriteBrands`, `preferredFit`, `budgetRange`, `clothingSizes`, and learned preference weights. That means V1 fit and color preferences can be added as local profile fields without creating a parallel memory store.

Two current implementation details need special care:

1. `BodyProportions` currently contains `bodyType: String?`. Future work must not surface this as a user-facing body classification, and should avoid building new behavior on top of fixed body labels.
2. `ScanView.swift` currently has `skinToneStyleNote()`, which samples pixels and returns an assertive undertone-style sentence. Future work should gate, soften, or replace that path so undertone assistance is opt-in, confidence-aware, and user-confirmed.

## Part A: Optional Color-Palette Assistance

### Product Positioning

Use product names like:

- Optional Color-Palette Assistance
- Undertone suggestion
- Palette preference

Avoid product names like:

- skin-tone detection
- face analysis
- body type detection
- ethnicity or race inference

### Feasibility

Feasibility: possible, but not V1-ready.

Estimated effort: Large.

The technical path is feasible on iOS using on-device Vision face detection plus local pixel sampling, but the product and privacy risks are high enough that this should be treated as a research feature after Beta 2.0. The safer first release is manual color-palette preference entry.

### Existing Files That Would Host Future Work

- `StyleMatchAI/ScanView.swift`: currently imports Vision and already has person/face detection helpers used in scan validation. A future camera-assist module should be separated from scoring and scan score calculation.
- `StyleMatchAI/GarmentColorPaletteEngine.swift`: currently handles garment palette extraction and skin-reference exclusion for garment color truth. Future undertone assistance must not weaken garment palette truth or allow invented garment colors.
- `StyleMatchAI/Models.swift`: `OutfitAnalysisResult` carries `colorPalette`, palette confidence, and `skinToneStyleNote`. Future UI should only mention undertone compatibility when both garment color and user-confirmed undertone are available.
- `StyleMatchAI/PersonalStylist/StylistProfileModels.swift`: likely home for confirmed broad palette preference fields.
- `StyleMatchAI/ProfileView.swift`: likely home for editing confirmed color-palette preferences.
- `StyleMatchAI/PersonalStylist/StylistContextBuilder.swift`: future AI-bound context must use only aggregated, confirmed, non-sensitive profile facts.
- `StyleMatchAI/Shopping/RecommendationRationaleBuilder.swift`: future recommendation copy can explain "why this matters" using confirmed preferences and detected garment colors.
- `StyleMatchAI/PrivacyDataManager.swift`: must include any new local preference keys in local deletion and privacy inventory.

### Proposed Data Model

Store only confirmed, broad preferences. Do not store raw pixels, face crops, sampled skin colors, or raw body/face measurements.

Suggested future profile fields:

```swift
enum UndertonePreference: String, Codable {
    case unset
    case warm
    case cool
    case neutral
    case uncertain
}

enum PreferenceSource: String, Codable {
    case manual
    case userConfirmedCameraSuggestion
}

struct ColorPaletteProfile: Codable {
    var favoriteColors: [String]
    var avoidedColors: [String]
    var preferredNeutrals: [String]
    var preferredAccentColors: [String]
    var undertone: UndertonePreference
    var undertoneSource: PreferenceSource?
    var colorSeason: String?
    var confidence: String?
    var updatedAt: Date?
}
```

Notes:

- `colorSeason` should remain optional and broad.
- If Monk Skin Tone scale is used, use it as a calibration and QA reference only. Do not expose or persist a Monk score by default.
- Low-confidence camera estimates should be withheld or shown as "uncertain", not guessed.

### Consent Flow

1. Entry point: Profile, Style DNA, or a future Style Coach card.
2. Screen title: "Optional Color-Palette Assistance".
3. Explain that the feature can help choose colors, is optional, and works without camera assistance.
4. Offer two paths:
   - "Choose manually"
   - "Try camera suggestion"
5. Require explicit consent before camera-based analysis.
6. Allow skip without penalty.

### Manual Input Flow

Manual entry should be the default V1 path:

- Favorite colors
- Avoided colors
- Preferred neutrals
- Preferred accent colors
- Optional undertone self-selection: warm, cool, neutral, unsure, skip
- Optional palette preference: high contrast, muted, bright, neutral-heavy, no preference

### Optional Camera-Assist Flow

Camera-assist should be research-only until accuracy, bias, lighting, and privacy validation are complete.

Allowed future processing:

- On-device Vision face detection
- Skin-region pixel sampling on device
- Lighting suitability check
- Confidence score
- Suggested broad undertone: warm, cool, neutral, or uncertain
- Optional color-season mapping only after confidence and user confirmation

Disallowed:

- Sending face imagery to the Worker or third-party AI by default
- Storing face images
- Storing raw sampled pixels
- Inferring race, ethnicity, nationality, health, attractiveness, or identity traits
- Claiming an undertone as definite

### Confirmation and Correction

Every camera-assisted result must be framed as a suggestion:

Good:

> Warm-neutral palette estimate, moderate confidence. Adjust if this does not look accurate.

Avoid:

> Your skin tone is definitely warm.

The user must be able to:

- Accept
- Edit
- Dismiss
- Clear later

Unconfirmed suggestions must not become persistent memory.

### Integration With Palette Truth

Recommendations may mention undertone compatibility only when both values are real app facts:

- The garment color came from the detected/stored garment palette with sufficient confidence.
- The undertone preference was manually selected or user-confirmed.

Allowed example:

> This olive jacket works with your confirmed warm-neutral palette preference and the scan's detected navy and cream colors.

Not allowed:

> This color matches your skin tone.

The feature must not invent garment colors, override detected color palettes, or change `calculateStyleScore()`.

### Failure and Empty States

- No consent: show manual preferences only.
- No face visible: offer manual selection.
- Multiple people in frame: do not estimate.
- Poor lighting or heavy shadows: withhold result.
- Makeup, filters, or color cast detected: show low-confidence/uncertain.
- User skips: recommendations continue using existing profile and outfit memory.

### Privacy and Compliance

Implementation would require:

- Privacy policy update for optional on-device face processing.
- App Store privacy label review.
- Clear consent copy.
- Local deletion support through existing deletion paths.
- No Worker endpoint.
- No default third-party AI transmission.

## Part B: Fit Preference

### Product Positioning

Use product names like:

- Fit Preferences
- Silhouette Preferences
- Fit and Silhouette Profile

Avoid:

- body type detection
- body shape classification
- "your body type is X"

### Feasibility

Feasibility: strong for manual V1.

Estimated effort: Medium.

The current app already has `FitPreference`, `preferredFit`, clothing sizes, profile editing, AI context, and shopping recommendation surfaces. A manual preference-only V1 can be added without camera analysis, body labels, scoring changes, or backend changes.

### Existing Files That Would Host Future Work

- `StyleMatchAI/PersonalStylist/StylistProfileModels.swift`: existing `FitPreference` and `preferredFit` live here.
- `StyleMatchAI/ProfileView.swift`: currently displays and saves fit/profile fields.
- `StyleMatchAI/OnboardingView.swift`: future home for first-run self-select fit questions.
- `StyleMatchAI/PersonalStylist/ProfileStore.swift`: local profile persistence.
- `StyleMatchAI/PersonalStylist/StylistContextBuilder.swift`: already includes preferred fit in AI context when set.
- `StyleMatchAI/Shopping/ShoppingRecommendationEngine.swift`: future product ranking boost/filter surface.
- `StyleMatchAI/Shopping/RecommendationRationaleBuilder.swift`: future explanation surface.
- `StyleMatchAI/PrivacyDataManager.swift`: currently has `fitPreference` in privacy keys; any new fit fields must be added here.

### V1 Manual Preference Flow

Entry points:

- Onboarding
- Profile
- Style DNA
- Shopping preferences

User-selectable fields:

- Preferred fit: slim, regular, relaxed, oversized, tailored, athletic
- Silhouette preference: structured, soft, clean lines, layered, minimal, statement
- Common fit concerns: too tight, too loose, sleeves too long, pants too long, waist fit, shoulder fit, shoe comfort
- Category-specific preferences:
  - Tops
  - Bottoms
  - Dresses
  - Outerwear
  - Shoes
  - Accessories

All labels should describe garment preference, not the user's body.

Good:

> I prefer relaxed tops and tailored outerwear.

Avoid:

> My body type needs relaxed tops.

### Recommendation Behavior

Fit preferences may:

- Boost matching products.
- De-emphasize products that conflict with explicit preference.
- Improve rationale text.
- Help future Style Coach suggestions.

Fit preferences must not:

- Exclude all products unless the user explicitly filters.
- Change deterministic outfit scoring.
- Produce body labels.
- Override safety validation or affiliate routing.

### AI Context Boundary

Only broad, confirmed preferences may enter AI context.

Allowed:

> Preferred fit: relaxed tops, tailored outerwear.

Not allowed:

> User has pear body type.

The AI may use this for explanations, suggestions, and shopping recommendations only. It must not affect score calculation.

### V2 Body-Pose Detection

Body-pose detection is out of scope for V1.

It should only be reconsidered if:

- V1 self-select skip rate is high.
- Users explicitly ask for camera assistance.
- Bias, privacy, and accessibility risks are validated.
- The feature can describe clothing effects without labeling the user's body.

Even then, any camera-derived output must be a user-confirmed suggestion, not persistent memory by default.

## Testing Matrix

### Fit and Silhouette

- Loose clothing
- Fitted clothing
- Layered clothing
- Partial body visibility
- Front-facing pose
- Angled pose
- Sitting pose
- Different camera distances
- Lens distortion
- Different heights and proportions
- Mobility aids
- Diverse body sizes
- Category-specific preferences
- Skip/manual-only path
- Preference clearing
- Large text and VoiceOver

### Optional Color-Palette Assistance

- Daylight
- Warm indoor lighting
- Cool indoor lighting
- Mixed lighting
- Shadows
- Makeup
- Different camera models
- Different skin depths
- Different undertones
- Partial face visibility
- No face visible
- Multiple people in frame
- Low-confidence result
- Manual correction
- Preference clearing
- Garment palette confidence mismatch

## Success Metrics

Manual V1:

- Completion rate for fit/color preference setup.
- Skip rate.
- Edit/correction rate.
- Recommendation tap-through rate.
- Recommendation save/favorite rate.
- Reduction in "not for me" feedback tied to fit or colors.
- User-reported trust in recommendations.

Camera-assist research:

- User opt-in rate.
- Low-confidence/withheld rate.
- User correction rate.
- Consistency across lighting conditions.
- Bias review across skin depths, undertones, camera models, and body sizes.

## Release Recommendation

Recommended path:

1. Safe to prototype after Beta 2.0: manual, editable fit and color preferences.
2. Requires additional research first: camera-assisted undertone suggestions.
3. Do not proceed: automatic body labels, fixed body-type classification, face recognition, race/ethnicity inference, attractiveness analysis, or any scoring influence.

## Explicit Non-Goals

- No changes to `calculateStyleScore()`.
- No Worker endpoint.
- No backend storage by default.
- No raw face, skin, or body measurement storage.
- No body-type labels.
- No race, ethnicity, nationality, health, or attractiveness inference.
- No claim that a color is universally good or bad for a person.
- No AI-bound private data beyond confirmed broad preferences.
