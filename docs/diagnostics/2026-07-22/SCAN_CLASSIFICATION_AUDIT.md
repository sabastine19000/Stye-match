# Scan Classification Audit

Date: 2026-07-22

## Pipeline

Camera/gallery image → orientation-aware Vision image → visual observations → transient OCR observations → typed classifier → confidence/confirmation policy → optional user correction → unchanged numeric scorer → saved analysis → shared AI context.

Raw OCR text is used only for classification evidence. The persisted result retains generic evidence labels, not recognized strings, names, employer text, image paths, or inferred wearer identity.

## Taxonomy coverage

Focused fixtures cover work and school uniforms, medical scrubs, business casual/formal, suit, tuxedo, casual/business/cocktail/evening/wedding/bridesmaid dresses, activewear, sportswear, outerwear, cultural/traditional attire, footwear, accessories, swimwear collision, ambiguity, and correction.

## Confidence policy

- High-confidence non-uniform: direct category.
- Medium: proposal requiring confirmation.
- Low: `Other / Uncertain`.
- Uniform categories: confirmation required even when evidence is strong.
- Rejected/uncertain choice remains uncertain.
- User correction changes the category/scoring profile but preserves independent detected style and the numeric score.

## Scoring impact

Classification selects qualitative evaluation criteria only. The existing numeric score remains Scan-owned and unchanged. Workwear, formal-event, professional, athletic, protective, outerwear, swimwear, cultural-attire, footwear, accessory, and casual profiles prevent universal casualwear assumptions.

## Accuracy and privacy boundaries

- Boundary-aware terms prevent `swimsuit` from becoming `suit`.
- OCR/logo evidence is insufficient by itself; visual construction and selected occasion are combined.
- No person, occupation, employer, event, gender identity, or brand is invented.
- Ambiguity is retained rather than forced.

## Performance

Debug builds record `stage=ocr` and `stage=classification` with duration only. Latest-context reads skip thumbnail decoding. Real-device OCR latency, rotated/partial logo accuracy, memory pressure, and older-device performance remain BLOCKED.

## Migration

All new classification fields decode with defaults through the existing analysis compatibility path. Existing records are not eagerly rewritten. Cached exact-match legacy scans receive in-memory enrichment only; explicit user correction is the write authority. No destructive migration is introduced.
