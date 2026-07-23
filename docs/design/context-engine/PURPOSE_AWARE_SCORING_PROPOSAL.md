# Purpose-Aware Scoring Proposal

Status: **Proposal only — the existing numeric score remains unchanged**

## 1. Decision requested

This proposal separates the completed StyleMatch score from purpose-specific appropriateness. It does not authorize a scoring-algorithm change.

| Output | Current behavior | Proposed CE1–CE6 behavior | Numeric effect |
|---|---|---|---|
| Overall Style Score | Existing color/pattern/fit/accessory score | Preserve exact score and breakdown | None |
| Occasion Compatibility | Mostly string mismatch/warning | Categorical evidence-backed assessment | Explanatory only |
| Workplace Suitability | Not separately represented | Categorical assessment using confirmed profile | Explanatory only |
| Weather Suitability | Advice exists | Categorical assessment tied to typed weather facts | Explanatory only |
| Safety Suitability | Not separately represented | Categorical, limitation-first assessment | Explanatory only |
| AI Confidence | Classification confidence only | Context confidence with evidence/missing evidence | Explanatory only |

Recommended approval: keep all new metrics categorical through physical acceptance. Numeric sub-scores, composite scores, or changes to the Overall Style Score require a later `PS1` decision.

## 2. Initial metric contract

```swift
enum SuitabilityLevel: String, Codable {
    case high, moderate, low, uncertain, notApplicable
}

struct SuitabilityAssessment: Codable, Equatable {
    let level: SuitabilityLevel
    let confidence: Double
    let supportingEvidenceIDs: [String]
    let conflictingEvidenceIDs: [String]
    let missingEvidenceIDs: [String]
    let summary: String
    let highestImpactImprovement: String?
}
```

Rules:

- Suitability may not change the saved numeric score.
- No suitability level is derived solely from detected style.
- Missing evidence lowers confidence; it is not scored as failure.
- Safety `high` means “no supported visible conflict for the confirmed context,” not certified safe.
- If purpose/profile is unconfirmed, workplace and safety suitability remain uncertain.

## 3. Proposed future weighting profiles

The weights below are design inputs for a later separately approved experiment. They sum to 100 within each profile and must not be used in production under this checkpoint.

| Profile | Proposed criteria and weights |
|---|---|
| Factory / Manufacturing | Safety evidence 20, comfort/breathability 15, condition 15, fit 15, mobility 15, workplace appropriateness 10, coordination 5, professional presentation 5 |
| Warehouse | Mobility 20, footwear practicality 15, safety/visibility evidence 15, comfort 15, condition 10, fit 10, weather/temperature suitability 10, presentation 5 |
| Office | Professional appropriateness 25, fit 20, condition 15, coordination 15, footwear 10, indoor comfort 10, accessories 5 |
| Business Casual Office | Fit 20, workplace polish 20, coordination 20, condition 15, footwear 10, comfort 10, accessories 5 |
| Business Formal | Tailoring 25, formality 20, color harmony 15, footwear 15, condition 10, accessories 10, occasion alignment 5 |
| Healthcare | Mobility 20, condition/clean presentation 20, comfort 15, fit/coverage 15, footwear evidence 10, workplace appropriateness 10, weather suitability 5, coordination 5 |
| Retail | Customer-facing presentation 20, mobility 15, fit 15, condition 15, footwear comfort 10, workplace appropriateness 10, coordination 10, weather suitability 5 |
| Hospitality | Service presentation 20, mobility 15, condition 15, fit/coverage 15, comfort 10, workplace appropriateness 10, footwear 10, weather/heat suitability 5 |
| Construction | Safety evidence 25, mobility 15, condition 15, visibility 10, footwear evidence 10, weather protection 10, fit 10, workplace appropriateness 5 |
| Outdoor Work | Weather protection 20, safety evidence 15, mobility 15, breathability/thermal comfort 15, footwear 10, condition 10, fit 10, presentation 5 |
| Remote Work | Presentability 20, comfort 20, fit 15, coordination 15, condition 10, camera-visible polish 10, weather suitability 5, accessories 5 |
| School | Dress-context appropriateness 20, condition 15, fit 15, comfort 15, coordination 15, footwear 10, mobility 5, weather suitability 5 |
| Gym / Training | Mobility 25, activity suitability 20, comfort 15, footwear 15, fit 10, condition 5, weather suitability 5, coordination 5 |
| Sports | Sport-specific function 25, mobility 20, footwear/equipment evidence 15, fit 10, condition 10, weather suitability 10, team/kit coordination 5, comfort 5 |
| Travel | Comfort 20, mobility 15, footwear practicality 15, layering flexibility 15, condition 10, coordination 10, weather suitability 10, security/practical accessories 5 |
| Vacation | Activity suitability 20, weather suitability 20, comfort 15, fit 15, coordination 10, footwear 10, condition 5, accessories 5 |
| Everyday Casual | Fit 20, color harmony 20, pattern balance 15, condition 15, comfort 10, occasion suitability 10, footwear 5, accessories 5 |
| Date Night | Fit 20, coordination 20, occasion alignment 20, condition 10, footwear 10, accessories 10, weather suitability 5, comfort 5 |
| Wedding Guest | Event formality 20, fit 20, coordination 15, venue appropriateness 15, condition 10, footwear 10, accessories 5, seasonal suitability 5 |
| Wedding Party | Ceremony alignment 20, fit 20, coordinated-party requirements 15, condition 10, footwear 10, accessories 10, venue appropriateness 10, seasonal suitability 5 |
| Wedding Dress | Silhouette/fit 25, fabric/condition 15, ceremony formality 15, venue appropriateness 15, accessories 10, footwear 5, seasonal suitability 10, comfort/mobility 5 |
| Church | Context appropriateness 20, fit 15, condition 15, coordination 15, comfort 10, footwear 10, accessories 10, weather suitability 5 |
| Funeral | Context appropriateness 25, formality 20, fit 15, condition 10, subdued coordination 10, footwear 10, weather suitability 5, comfort 5 |
| Formal Event | Formality 20, fit/tailoring 20, coordination 15, condition 10, footwear 10, accessories 10, venue appropriateness 10, seasonal suitability 5 |
| Other / Uncertain | No weighted score; visible facts and missing evidence only |

## 4. Compatibility evaluation

Compatibility is a rules-and-evidence conclusion, not a subtraction from style score.

Example:

```text
Overall Style Score: 80/100 (unchanged)
Detected Style: Casual
Purpose: Factory / Manufacturing — Confirmed
Occasion Compatibility: High
Workplace Suitability: High
Weather Suitability: Moderate
Safety Suitability: Uncertain — footwear not visible
AI Confidence: 82%
```

The app must never say “Casual is inappropriate for Work” without a purpose/profile-specific conflict.

## 5. Future numeric experiment requirements

Before any numeric purpose score:

1. Freeze representative evidence fixtures for every purpose.
2. Define criterion rubrics and inter-rater review.
3. Prove that missing evidence is not punished.
4. Decide whether purpose metrics are displayed as categories, percentages, or scores.
5. Define migration and comparison behavior for historical scans.
6. Run fairness, privacy, and cultural-attire reviews.
7. Prove Overall Style Score remains independently reproducible.
8. Obtain explicit owner approval for weights and UI language.

## 6. Migration strategy

- Existing scans retain their original score and breakdown permanently.
- Additive suitability context may be computed transiently for a legacy scan and labeled “Limited context.”
- Do not backfill or persist new suitability metrics without user review or an approved migration.
- A user correction changes purpose/profile authority, not the original score.

## 7. Validation gates

- Unit: every profile produces deterministic categorical assessments.
- Contract: AI receives original score and separate metrics.
- Regression: existing score fixtures remain byte-for-byte/field-for-field unchanged.
- Physical: UI shows the original score and compatibility metrics as distinct sections.
- Accessibility: labels say “suitability” or “compatibility,” never imply a second hidden score.
