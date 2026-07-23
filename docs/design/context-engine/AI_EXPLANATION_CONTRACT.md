# AI Explanation Contract

Status: **Proposal only — no prompt, Worker, or response behavior has changed**

## 1. Shared authority

Scan Results, AI Assist, standalone AI Stylist Chat, saved-scan AI, and voice must receive the same validated `OutfitContextSnapshot` from `CurrentScanContextProvider`.

Every scan-specific response must be tied to:

- scan ID and completion timestamp;
- context schema version and generation;
- original Overall Style Score and breakdown;
- detected visual style;
- garment category;
- user-confirmed or proposed purpose;
- selected occasion;
- confirmed workplace profile;
- separate compatibility/suitability assessments;
- evidence and missing evidence;
- context provenance.

No surface may independently derive “last score,” purpose, workplace profile, or compatibility from conversation memory.

## 2. Required explanation shape

When the user asks about a scan, the response should contain only the parts supported by the question and evidence, in this priority:

1. **What is visible:** visual style and garment facts.
2. **What it appears intended for:** confirmed purpose, or a qualified proposal.
3. **How it fits the selected context:** occasion/workplace compatibility.
4. **Why:** strongest supporting and conflicting evidence.
5. **What is missing:** facts the image cannot verify.
6. **One highest-impact improvement:** exactly one evidence-backed action.
7. **Advice label:** fashion, workplace, safety, or weather.

The AI must not dump all seven parts into every short answer. It should answer the question first, then add the smallest necessary qualification.

## 3. Terminology contract

| Concept | Required phrasing | Prohibited substitution |
|---|---|---|
| Visual style | “The visual style reads as Casual.” | “The outfit purpose is Casual.” |
| Garment category | “The garment appears to be Branded Workwear.” | “You work for [brand].” |
| Proposed purpose | “This may be Factory / Manufacturing workwear.” | “This is definitely your factory uniform.” |
| Confirmed purpose | “You confirmed Factory / Manufacturing for this scan.” | “The model proved this is factory wear.” |
| Missing evidence | “Safety footwear is not visible.” | “You are not wearing safety footwear.” |
| Safety assessment | “Safety suitability is not verified from this image.” | “This outfit is workplace safe/compliant.” |
| Score | “This scan scored 80/100.” | Any recalculated or AI-generated score |

## 4. Response examples

### 4.1 Confirmed factory purpose

> This scan scored 80/100. The visual style reads as Casual, and you confirmed the purpose as Factory / Manufacturing. Those facts do not conflict: the outfit appears practical for factory work. The strongest support is the workwear construction and selected Work context. Safety footwear is not visible, so safety suitability is not verified. The highest-impact improvement is a cleaner, more intentional fit. This is workplace presentation advice.

### 4.2 Medium-confidence proposal

> This looks most like warehouse or factory workwear, but the evidence is not strong enough to choose for you. The durable garments support both; the workplace profile is missing. Which context fits?

### 4.3 Low confidence

> The outfit purpose is uncertain. I can describe the visible casual style, but I need your context before giving workplace-specific advice.

### 4.4 Weather advice

> The outfit is suitable for the confirmed purpose, but the current heat makes breathability the main concern. This is weather advice; it does not change the saved 80/100 score.

### 4.5 Historical scan

> You opened the July 21 saved scan, so I’m using that scan’s confirmed context—not the newer scan.

## 5. Highest-impact improvement selection

Choose one improvement from supported weaknesses, in this order:

1. explicit safety conflict for a confirmed purpose;
2. explicit occasion/workplace conflict;
3. severe weather mismatch with high-confidence weather;
4. weakest visible score component;
5. condition/fit/presentation issue;
6. request missing evidence when no improvement is supportable.

Do not produce generic “Swap one piece” advice. Name the dimension and why it matters.

## 6. Confidence behavior

- High confidence specialized workwear: state the likely purpose and ask for confirmation.
- Medium: present up to three likely choices.
- Low: state uncertainty; do not choose a purpose.
- User correction: use the correction for that scan and mention it as user-confirmed when relevant.
- Conflicting evidence: explain the conflict briefly and ask one question.
- Missing evidence: do not invent details to make the answer complete.

## 7. Prompt/payload structure

AI-facing payload should remain typed until the final serialization layer:

```text
authoritativeScan {
  scanIdentity
  overallStyleScore
  scoreBreakdown
  outfitContext {
    detectedStyle
    garmentCategory
    outfitPurpose
    environmentType
    selectedOccasion
    workplaceProfile
    occasionCompatibility
    workplaceSuitability
    weatherSuitability
    safetySuitability
    confidence
    evidence
    missingEvidence
    provenance
  }
}
```

The system instruction must state:

- preserve score authority;
- never infer wearer/employer/gender identity;
- distinguish missing from conflicting evidence;
- label the advice dimension;
- reject stale or internally inconsistent context.

## 8. Response validation

Before display:

- reject an unsupported score or scan ID;
- reject a purpose/profile contradicted by the authoritative confirmed values;
- reject employer/wearer identity claims;
- reject “safe/compliant” claims without a separately approved authority;
- reject advice that treats visual style as purpose;
- reject a response that omits an essential uncertainty qualifier;
- fall back to a local evidence summary using the same typed context.

## 9. Voice rules

Voice uses the same context and validation, but:

- lead with score only when the user asked about score;
- use one purpose and one suitability result;
- speak one improvement;
- mention at most one missing-evidence limitation;
- do not speak raw OCR, precise location, or private profile values;
- keep existing brevity and accessibility limits.

## 10. Compatibility

The AI payload extension must be additive. Older Worker versions receive the existing authoritative scan fields. New clients must not assume a new Worker response shape until the supported-version contract and health gate accept it under ADR-006.
