# Context Engine Test Plan

Status: **Proposed test plan — no tests were added or run by this design checkpoint**

## 1. Test layers

1. Pure taxonomy and deterministic evaluator unit tests.
2. Evidence-combination and confidence tests.
3. Persistence/legacy decoding tests.
4. Current-scan and screen-context authority tests.
5. AI payload, response-validation, and fallback contract tests.
6. Voice parity and context-generation tests.
7. UI/state tests for confirmation and correction.
8. Performance/privacy instrumentation tests.
9. Physical-device acceptance.

Every fixture must identify:

- scan ID and completion time;
- visible observations;
- selected occasion;
- proposed/confirmed purpose and workplace profile;
- evidence and missing evidence;
- unchanged Overall Style Score;
- expected compatibility/suitability outputs;
- expected AI and voice facts.

## 2. Required acceptance cases

| # | Case | Setup | Expected result |
|---:|---|---|---|
| 1 | Casual style + factory work purpose | Casual visual style, workwear construction, Work selected, Factory confirmed | Style stays Casual; purpose Factory; workplace compatibility high; no generic Casual-vs-Work warning |
| 2 | Casual style + office work purpose | Casual garments, Work selected, Office confirmed | Style stays Casual; office suitability is evidence-based and may be moderate/low without changing score |
| 3 | Uniform with unreadable logo | Uniform construction, low OCR confidence | Branding/text presence may be recorded generically; no brand/employer; confirmation required |
| 4 | Uniform confirmation | High-confidence specialized workwear proposal | Prompt still appears; confirmation becomes per-scan authority; generation increments |
| 5 | User rejects uniform classification | Proposed Factory uniform rejected | Purpose returns to uncertain; no automatic second choice |
| 6 | Work selected but purpose uncertain | Work occasion with insufficient purpose evidence | Purpose/profile and workplace suitability remain uncertain; limited choices offered |
| 7 | High-confidence dress classification | Clear evening-gown garment evidence | Garment category can be high confidence; purpose still follows confirmation rules |
| 8 | Wedding dress vs evening gown | Ambiguous white formal gown | No forced bridal purpose; show Wedding Dress/Evening Gown choices; never infer event |
| 9 | Scrubs | Scrub construction and Work selected | Garment Medical Scrubs; Healthcare purpose proposed; confirmation required |
| 10 | Construction workwear | High-visibility/workwear cues and Work selected | Construction proposed; safety evidence/missing evidence listed; no compliance claim |
| 11 | Safety footwear visible | Confirmed work purpose and supported footwear cue | Record footwear visible; safety remains advisory, not certified |
| 12 | Safety footwear not visible | Feet outside frame | Missing evidence says footwear not visible; do not say absent or unsafe |
| 13 | Factory background without uniform | Factory-like scene, ordinary casual outfit | Environment may be factory-like; purpose stays uncertain unless other evidence/user confirmation exists |
| 14 | Employer logo detected but not identified | Patch/logo/text presence | Generic branding evidence only; no raw text, employer, wearer, or occupation |
| 15 | User correction | Proposed Warehouse changed to Retail | Retail becomes authoritative for same scan; original proposal remains in provenance; score unchanged |
| 16 | Saved scan restoration | Persisted confirmed purpose/profile reopened | Exact scan/generation/context restored; no newer scan mixed in |
| 17 | AI Assist and AI Stylist consistency | Same active scan and question | Same scan ID, score, style, category, purpose, profile, metrics, and missing evidence |
| 18 | Voice summary consistency | Same active scan | Voice uses same purpose and suitability, one improvement, no private OCR |
| 19 | Screen transition with stale context | Navigate after correction/new scan while an old screen context exists | Validator fails closed; no stale purpose/score response |
| 20 | Legacy scans without purpose fields | Decode historical analysis | Original score/history preserved; transient context labeled limited/uncertain; no automatic persistence |

## 3. Additional taxonomy cases

- Warehouse vs Factory ambiguity.
- Retail uniform vs branded casual shirt.
- Hospitality apron vs home cooking.
- Healthcare scrubs vs costume.
- Business Casual Office vs Everyday Casual.
- Business Formal vs Formal Event.
- Gym / Training vs Sports uniform.
- Travel vs Vacation.
- Wedding Guest vs Wedding Party.
- Church/funeral context cannot be inferred from color or building alone.
- Remote Work cannot be inferred from a home background alone.
- Cultural/traditional garment category does not imply purpose, ethnicity, religion, or nationality.
- Unknown enum values decode to uncertain.
- Other / Uncertain never becomes confirmed without user action.

## 4. Score-preservation tests

For every purpose/profile fixture:

- capture the original `OutfitAnalysisResult.score`;
- build context and suitability metrics;
- assert score and breakdown are unchanged;
- confirm correction changes only context fields;
- confirm AI payload contains one authoritative score;
- reject any AI response with a different score.

Existing score regression fixtures must pass without modification except additive fixture decoding.

## 5. Confidence and evidence tests

- High specialized purpose still asks confirmation.
- High non-specialized purpose displays likely value according to taxonomy.
- Medium presents no more than three supported choices.
- Low remains uncertain.
- Missing evidence never decreases a numeric score.
- Contradictory evidence lowers context confidence or produces uncertainty.
- OCR alone cannot establish purpose.
- Background alone cannot establish purpose.
- Selected occasion alone cannot establish purpose.
- User confirmation outranks proposal for the same scan only.

## 6. Persistence and migration tests

- Encode/decode complete versioned context.
- Decode record with no context.
- Decode future unknown purpose/profile safely.
- Preserve original raw record and score through legacy access.
- Do not rewrite old scans during read.
- Context generation increments atomically on correction.
- Interrupted correction preserves previous authority.
- Duplicate scan ID with conflicting generation fails closed.
- No raw OCR text or precise location appears in persisted JSON.

## 7. AI and screen-awareness tests

- Current screen matches authoritative scan.
- Scan ID mismatch.
- Score mismatch.
- Generation mismatch.
- Purpose mismatch.
- Workplace profile mismatch.
- Suitability mismatch.
- Missing-evidence mismatch.
- Explicit historical scan remains authoritative.
- New completed scan replaces latest-scan authority without app restart.
- In-flight turn from old generation is excluded from grounding.
- Typed, voice-transcribed, and starter-prompt sends use the same builder.
- Worker unsupported-version path uses local typed fallback without losing score authority.

## 8. Voice tests

- Spoken score matches scan.
- Spoken purpose matches confirmation.
- Spoken suitability is categorical.
- Voice states uncertainty when purpose is uncertain.
- Voice omits raw OCR and exact location.
- Recognition started on generation N and sent after generation N+1 fails closed.
- Repeated speech sessions retain existing lifecycle protections.

## 9. UX tests

- Context summary does not crowd score at compact width.
- Largest Dynamic Type.
- VoiceOver order and labels.
- High/medium/low confirmation flows.
- Reject and Change actions.
- Work selection requests workplace profile.
- Non-work purposes omit workplace row.
- Safety/weather warnings appear only when supported.
- Correction acknowledgment says score unchanged.

## 10. Performance and privacy gates

Measure separately:

- existing Vision/OCR duration;
- incremental context-engine duration;
- persistence size increase;
- AI payload size increase;
- first display time;
- correction-to-context-refresh time.

Proposed targets:

- no second OCR request;
- deterministic context calculation p95 under 20 ms after observations are ready;
- context payload under 16 KB excluding existing analysis text;
- no raw OCR, badge/name, employer, wearer, face identity, or precise location in persistence/logs/AI payload;
- Debug timing logs contain duration and guard identifiers only.

## 11. Physical-device acceptance

On supported iPhone hardware:

1. Run representative factory, office, scrubs, formal, wedding ambiguity, activewear, and uncertain scans.
2. Measure OCR plus context latency.
3. Confirm score is unchanged.
4. Confirm/reject/correct purposes.
5. Compare Scan Results, AI Assist, standalone AI Stylist, saved scan, and voice.
6. Navigate while context updates and confirm stale state fails closed.
7. Inspect privacy-safe device logs.
8. Verify prior retained records remain intact; new test scans are additive under the separately approved retained-data strategy.

No physical acceptance may be claimed from simulator/unit evidence.

## 12. Release stop rules

Stop on:

- any score drift;
- forced purpose/category;
- raw OCR/private identity exposure;
- AI/voice context disagreement;
- stale screen context accepted as current;
- legacy record mutation;
- unsupported Worker contract;
- material OCR/context latency regression;
- Shopping/catalog/B5/signing/deployment drift.
