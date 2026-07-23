# Workplace Profile Matrix

Status: **Proposal only — no workplace inference or scoring behavior is active**

## 1. Authority model

`Work` remains an occasion. `WorkplaceProfile` describes the evaluation environment within that occasion.

Authority order:

1. User-confirmed workplace profile for the same scan.
2. Explicit saved profile selection, when the user chooses to apply it.
3. Evidence-backed proposed profile requiring confirmation.
4. `Other / Uncertain`.

Visual evidence may suggest a profile but may not identify an employer, job title, occupation, school, facility, wearer, or precise location.

## 2. Required profiles

| Profile | Primary evaluation needs | Supporting evidence | Conflicts/limitations | Confirmation rule | Safety boundary |
|---|---|---|---|---|---|
| Factory / Manufacturing | Mobility, durability, condition, breathability, clean presentation, task-appropriate fit | Workwear construction, utility shirt/pants, patch/text presence, selected Work, factory cues | Factory background alone is insufficient; logo does not identify employer | Always confirm | Report only visible/missing cues; never certify PPE or dress-code compliance |
| Warehouse | Mobility, durable fit, visibility, footwear practicality, temperature/layering | Utility garments, high-visibility cues, warehouse environment, selected Work | Retail stockroom or factory may look similar | Always confirm | Footwear/PPE absent from frame is “not verified” |
| Office | Professional presentation, fit, condition, indoor comfort, role-neutral appropriateness | Structured separates, office environment, selected Work | Home desk does not prove office work; avoid occupation inference | Confirm at medium confidence | No safety claim unless an explicit requirement exists |
| Business Casual Office | Professional polish without full formalwear, fit, coordination, footwear | Chinos/trousers, polo/button-down/blouse, cardigan/blazer, loafers, selected Work | Same garments may be Everyday Casual | Confirm unless explicitly selected | Functional/safety rating is normally not applicable |
| Healthcare | Mobility, cleanliness/condition, coverage, closed-footwear evidence, comfort | Scrub construction, clinical-uniform cues, selected Work | Scrub-style fashion or costume requires correction path | Always confirm | Do not claim infection-control or facility-policy compliance |
| Retail | Customer-facing neatness, mobility, brand-neutral uniform presentation, footwear comfort | Service shirt, badge/patch presence, retail setting, selected Work | Logo/badge cannot identify employer or wearer | Always confirm branded/service attire | Do not infer loss-prevention or job duties |
| Hospitality | Service presentation, movement, condition, coverage, heat/indoor comfort | Apron, chef/server/service uniform, venue cues, selected Work | Restaurant guest attire may look similar | Always confirm | Do not certify food-safety compliance |
| Construction | Mobility, visibility, protective coverage, condition, footwear/head protection when visible | High-visibility and workwear cues, site environment, selected Work | Site background alone cannot establish work purpose | Always confirm | Explicitly state that visual review is not PPE or regulatory certification |
| Outdoor Work | Weather exposure, sun/rain protection, mobility, footwear, breathability | Workwear plus outdoor exposure and explicit Work context | Outdoor photo alone is insufficient | Always confirm | Weather/safety advice must name missing evidence |
| Remote Work | Camera-ready presentation when relevant, comfort, fit, indoor weather neutrality | Work selection, home environment, explicit remote-work confirmation | Home environment alone cannot establish work | Confirm unless directly selected | Usually no workplace-safety assessment |
| Other / Uncertain | General visible presentation only | Missing or conflicting profile evidence | Must not be forced into a workplace type | Offer limited choices; allow no selection | Suitability stays uncertain |

## 3. Compatibility semantics

`WorkplaceSuitability` is separate from visual style:

- `high`: visible/confirmed outfit evidence supports the confirmed profile, with no material visible conflict;
- `moderate`: broadly workable, with one supported improvement or missing secondary evidence;
- `low`: a confirmed profile has a direct, evidence-backed conflict;
- `uncertain`: profile or required evidence is missing/conflicting;
- `notApplicable`: no workplace purpose/profile applies.

A casual detected style can have high factory, warehouse, retail, healthcare, construction, outdoor-work, or remote-work suitability.

## 4. Profile selection UX

- With `Work` selected and no profile: show “Workplace type — Choose for more relevant advice.”
- With a supported proposal: show “Likely workplace profile: Factory / Manufacturing” and require confirmation.
- With confirmation: show “Factory / Manufacturing — Confirmed” and a Change action.
- Rejecting a proposal does not select another profile automatically.
- Choosing `Other / Uncertain` keeps workplace suitability uncertain.

## 5. Safety and privacy language

Allowed:

- “Closed footwear is visible.”
- “Safety footwear cannot be verified from this image.”
- “High-visibility material appears present.”
- “This is a visual styling assessment, not a PPE compliance inspection.”

Prohibited:

- “You work for Company X.”
- “This badge belongs to [person].”
- “This uniform proves you are a nurse/employee/student.”
- “This outfit meets OSHA, hospital, school, or employer policy.”
- “No helmet is present” when the head is outside the image; use “helmet not visible.”

## 6. Persistence

Persist:

- stable profile identifier;
- proposal confidence;
- generic evidence identifiers/summaries;
- user confirmation/correction and timestamp;
- missing-evidence identifiers;
- evaluator version.

Do not persist:

- raw OCR text;
- probable company/school/person names;
- badge numbers;
- face identity;
- exact workplace location;
- inferred occupation.
