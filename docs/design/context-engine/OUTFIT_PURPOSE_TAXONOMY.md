# Outfit Purpose Taxonomy

Status: **Proposal only — no runtime taxonomy or scoring change**

## 1. Classification rules

- Outfit purpose describes what the outfit is intended to do. It is not visual style, garment category, occasion, location, employer, or wearer identity.
- Confidence bands retain the current classifier convention: high `>= 0.82`, medium `0.55...0.819`, low `< 0.55`. Per-purpose minimums below may be stricter.
- Specialized workwear and uniforms always request confirmation, even at high confidence.
- Medium confidence requests confirmation.
- Low confidence stays `Other / Uncertain` and offers at most three evidence-supported choices.
- An explicit user correction is authoritative for that scan.
- “Not observed” is missing evidence, not conflicting evidence.

## 2. Taxonomy

| Purpose | Definition | Supporting evidence | Conflicting evidence | Minimum proposal | Confirmation | Scoring profile | Fallback |
|---|---|---|---|---:|---|---|---|
| Factory / Manufacturing | Clothing intended for production-floor work | Uniform/workwear construction, durable fabric, logo/text presence, selected Work, mobility/safety cues | Clearly ceremonial/formal outfit; explicit non-work correction | 0.72 | Always | factoryManufacturing | Work purpose uncertain; ask Factory, Warehouse, or Other |
| Warehouse | Clothing intended for fulfillment, inventory, or loading work | Utility garments, high-visibility elements, durable footwear, Work selection, mobility cues | Formalwear, swimwear, explicit office context | 0.72 | Always | warehouse | Ask Warehouse, Factory, or Other |
| Office | General professional office clothing | Office environment, professional separates, Work selection, structured garments | Protective workwear, athletic kit, sleepwear | 0.68 | Medium; high when context conflicts | office | General Work; workplace unknown |
| Business Casual Office | Polished but non-formal office purpose | Chinos, polo/button-down, blouse, cardigan/blazer, loafers, Work selection | Tuxedo/gown, protective uniform, activewear-only | 0.70 | Medium | businessCasualOffice | Office or Everyday Casual |
| Business Formal | Formal professional purpose | Suit/tailoring, formal business dress, dress shoes, Business Formal selection | Swimwear, sleepwear, athletic uniform | 0.78 | Medium | businessFormal | Formal Event or Office |
| Healthcare | Clinical or care-setting work purpose | Scrub construction, medical-uniform evidence, closed footwear, user Work confirmation | Fashion scrub-style item with explicit non-work correction | 0.78 | Always | healthcare | Work purpose uncertain; ask Healthcare or Other |
| Retail | Customer-facing retail work purpose | Branded/service shirt, badge presence, neat separates, Work selection, store environment | Construction PPE, scrubs, formal ceremony | 0.70 | Always for branded uniform | retail | Work purpose uncertain |
| Hospitality | Hotel, restaurant, event-service, or food-service work purpose | Service uniform, apron, vest, chef/server cues, Work selection | Medical/construction uniform; explicit casual correction | 0.72 | Always | hospitality | Work purpose uncertain |
| Construction | Job-site work purpose | High-visibility/PPE cues, helmet/boots when visible, durable workwear, Work selection | Office formalwear, swimwear, unsafe inference from background alone | 0.78 | Always | construction | Outdoor Work, Factory, or Other |
| Outdoor Work | Work primarily exposed to weather | Workwear plus outdoor environment/weather exposure and user Work confirmation | Indoor formal event; background alone without work evidence | 0.72 | Always | outdoorWork | Work purpose uncertain |
| Remote Work | Clothing intended for work from home | Work selection, home environment, presentable top/comfortable lower layers, explicit confirmation | Home environment alone; sleepwear without user confirmation | 0.65 | Always unless explicitly selected | remoteWork | Everyday Casual or Work uncertain |
| School | Clothing intended for attending school | School-uniform construction, school selection/context, backpack/accessory combination | Employer workwear; explicit casual-only correction | 0.75 | Always for uniform | school | School or Everyday Casual |
| Gym / Training | Clothing intended for exercise or training | Performance fabric, activewear combination, gym context, supportive footwear | Formalwear, work uniform, swim-only evidence | 0.72 | Medium | gymTraining | Sports or Everyday Casual |
| Sports | Clothing intended for organized sport/play | Team uniform/jersey, sport-specific gear, field/court evidence | Fashion jersey with no activity evidence | 0.75 | Medium | sports | Gym / Training or Everyday Casual |
| Travel | Clothing intended for transit and mobility | Travel selection, luggage/airport cues, comfortable layers, practical footwear | Location cue alone; formal ceremony without transit context | 0.65 | Medium | travel | Everyday Casual |
| Vacation | Clothing intended for leisure away from home | Explicit vacation selection, resort/beach/leisure combination | Beach background alone; work uniform | 0.65 | Medium | vacation | Travel or Everyday Casual |
| Everyday Casual | General non-specialized daily wear | Casual separates, ordinary footwear, no specialized purpose evidence | Strong uniform, ceremonial, athletic, or safety evidence | 0.60 | Medium only | everydayCasual | Other / Uncertain |
| Date Night | Clothing selected for a date/social evening | Date Night selection, elevated casual/formal coordination, evening context | Selection absent; work uniform without correction | 0.65 | Medium | dateNight | Everyday Casual or Formal Event |
| Wedding Guest | Guest attire for a wedding | Wedding Guest selection, formal/semi-formal combination, venue evidence | Bridal-specific construction; everyday casual without confirmation | 0.72 | Medium | weddingGuest | Formal Event |
| Wedding Party | Attire for a member of a wedding party | Matching formal party attire, bridesmaid/grooms-party evidence, explicit confirmation | Guest-only selection; bridal-specific evidence | 0.78 | Always | weddingParty | Wedding Guest or Formal Event |
| Wedding Dress | Bridal garment purpose | Bridal gown construction, veil/train evidence, explicit correction/confirmation | White evening dress alone; no bridal evidence | 0.86 | Always | weddingDress | Evening Gown or Formal Event |
| Church | Clothing intended for worship/religious service | Church selection/context plus appropriately coordinated outfit | Building/background alone; do not infer faith | 0.68 | Medium | church | Formal Event or Everyday Casual |
| Funeral | Clothing intended for a funeral/memorial | Explicit selection, subdued formal coordination, venue/context evidence | Dark color alone; never infer bereavement | 0.80 | Always | funeral | Formal Event |
| Formal Event | General ceremony or high-formality event | Formal selection, gown/suit/tuxedo, venue evidence | Everyday casual/activewear with no confirmation | 0.72 | Medium | formalEvent | Other / Uncertain |
| Other / Uncertain | Evidence does not support a safe purpose | Missing, conflicting, or low-confidence evidence | None; uncertainty is valid | N/A | Offer limited choices only | uncertain | Remain uncertain |

## 3. Purpose versus related facts

| Fact | Example | Meaning |
|---|---|---|
| Detected style | Casual | Visual styling language |
| Garment category | Branded Workwear | What the garments are |
| Outfit purpose | Factory / Manufacturing | What the outfit is for |
| Selected occasion | Work | User’s immediate event intent |
| Workplace profile | Factory / Manufacturing | Workplace evaluation frame |
| Environment | Home | Where the image appears to be captured |
| Safety context | Safety footwear not visible | Evidence-limited functional observation |

## 4. Evidence combination

Purpose inference may combine:

- garment silhouette and construction;
- accessory/footwear combinations;
- selected occasion;
- confirmed workplace profile;
- physical environment;
- privacy-safe presence of text, patches, or branding;
- weather/activity context;
- explicit user correction.

No single OCR string, logo, background, color, or garment label is enough to identify a workplace purpose on its own.

## 5. User confirmation language

- High specialized confidence: “This appears to be a factory work uniform. Is that correct?”
- Medium: “This looks most like warehouse workwear or factory workwear. Which fits?”
- Low: “The outfit purpose is uncertain. Choose a purpose if you want workplace-specific advice.”
- Correction: “Purpose updated for this scan. Visual style and original evidence remain unchanged.”

## 6. Unknown and future values

Persist raw stable identifiers. Unknown decoded values map to `Other / Uncertain` while preserving the original raw value in migration diagnostics when privacy-safe. New purposes require a taxonomy update, scoring proposal, compatibility matrix, migration test, and AI explanation test before release.
