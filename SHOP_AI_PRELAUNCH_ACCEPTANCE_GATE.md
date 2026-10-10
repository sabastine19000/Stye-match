# Shop AI Pre-Launch Acceptance Gate

Shop AI is a revenue-critical subsystem. It is not launch-ready until every gate below has:

- automated regression coverage,
- physical-device evidence,
- an explicit PASS result,
- an owner-reviewed explanation for any fallback or degraded state.

User trust is higher priority than inventory volume. If a selected retailer has no products, the app must say that clearly instead of silently replacing the selection with another retailer.

## Launch Status

Current status: NOT LAUNCH-READY

Reason: several gates have automated coverage, but the full Shop AI path does not yet have physical-device evidence across store filtering, link-out, telemetry, image coverage, offline states, and customer-facing explanations.

## Failure Classes

Every Shop AI defect must be classified as exactly one primary failure class before release approval:

| Failure class | Definition |
|---|---|
| catalog defect | Product data is missing, stale, malformed, unsafe, duplicated, wrongly categorized, missing canonical retailer identity, missing image, missing price, unavailable, or absent for a supported retailer. |
| recommendation defect | Ranking, personalization, reason facts, sale matching, weather matching, or recommendation copy is not traceable to deterministic product/user/catalog data. |
| retailer-filter defect | Preferred stores, store chips, Store Search, Browse, Deck, Recommended, Catalog Picks, or Complete the Look filters do not use canonical retailer IDs consistently. |
| fallback UX defect | The app hides source failure, inventory absence, offline mode, bundled/static fallback, or selected-store zero inventory behind misleading generic copy. |
| affiliate-routing defect | Product taps do not use deterministic `AffiliateLinkBuilder` routing, append tracking incorrectly, expose placeholder tracking, route to unsafe URLs, or break retailer checkout handoff. |
| telemetry defect | Required privacy-safe impression, filter, fallback, and outbound-tap signals are missing, duplicated, not attributable to a product/store state, or contain prohibited personal data/URL query values. |

## Gate States

Every gate must use one of these explicit states:

| State | Meaning |
|---|---|
| PASS | Automated regression coverage passed, physical-device evidence is attached, customer-facing behavior is truthful, and no blocker remains. |
| FAIL | A reproducible defect was found. Classify it using the failure classes above and create a corrective checkpoint before re-testing. |
| BLOCKED | Required evidence cannot yet be collected or a prerequisite is missing. Do not claim launch readiness while blocked. |
| PENDING | Work or evidence is incomplete, but no failure has been proven yet. PENDING is not launch-ready. |

## Gate Matrix

| Gate | Automated evidence required | Physical-device evidence required | Current evidence | Status |
|---|---|---|---|---|
| Canonical retailer identity | Decode tests prove remote `store_id` and bundled `retailer_id` survive into `AffiliateProduct.retailerID`; unknown IDs do not infer from display names; equality stays deterministic. | Screenshot or console diagnostic showing active product counts by canonical retailer ID after a real catalog load. | Partial automated coverage exists in `StyleMatchProPhase2Tests`; latest iOS work backfills bundled IDs. | PENDING PHYSICAL |
| Selected-store filtering | Tests prove matching canonical IDs return only selected retailers, missing IDs cannot satisfy filters, zero matches fail open without mutating preferences. | Select stores with products and stores without products on device; capture selected IDs, filtered count, fallback state, displayed count. | Automated coverage exists for policy behavior. | PENDING PHYSICAL |
| Active inventory by retailer | Tests or diagnostics produce count-by-retailer from loaded remote/cache/bundled source. | Capture active inventory table on device for all supported stores after remote load and after fallback source, if used. | Bundled fallback now has 12 countable products across 8 retailer IDs; remote evidence previously showed Amazon-only visible products. | PENDING PHYSICAL |
| Fallback behavior | Tests cover remote success, cache fallback, bundled fallback, total failure, legitimate empty filters, and selected-store zero inventory. | Device evidence for remote/cache/bundled/none source behavior as available; selected-store no-inventory banner must be visible and truthful. | Automated resilience coverage exists; selected-store copy improved. | PENDING PHYSICAL |
| Product image coverage | Tests prove `image_url = null` does not remove products and placeholder rendering remains valid. Catalog validation must report image coverage percentage. | Screenshot grid showing real images where available and placeholders where image URLs are null; no cards disappear. | Null-image handling exists; current bundled fallback has null images. | PENDING IMAGE INVENTORY |
| Price and availability freshness | Tests prove unavailable/out-of-country products are filtered, expired sales are not treated as active, Amazon stored-price rule holds, and catalog source age is shown/recorded. | Device capture of price labels, sale count, source age/cache age, and any static catalog notice. | Partial automated coverage exists. | PENDING PHYSICAL |
| Affiliate-link correctness | Tests prove `AffiliateLinkBuilder` appends approved tracking through `URLComponents`, does not append placeholder IDs, preserves safe `/go` URLs, and blocks unsafe URLs. | Tap one product per represented retailer where inventory exists; capture pre-tap product ID/store ID and returned retailer page. | Automated route coverage exists; physical link-out remains pending for several stores. | PENDING PHYSICAL |
| Recommendation grounding | Tests prove recommendation reasons use deterministic reason facts only and omit generic filler when no personalization evidence exists. | Device evidence for Recommended, Catalog Picks, Complete the Look, and Store Search result reasons matching real loaded products and scan/history facts. | Partial automated coverage exists. | PENDING PHYSICAL |
| Duplicate suppression | Tests prove duplicated live-search results dedupe by deterministic identity and do not collapse distinct products. | Device or fixture evidence from at least two source providers returning overlapping products. | Automated fixture coverage exists for aggregated search dedupe. | PENDING SOURCE FIXTURE |
| Empty and offline states | Tests distinguish unavailable catalog, loaded-empty catalog, narrow filters, selected-store zero inventory, and offline fallback. | Device evidence for each reachable state; no failure may say filters are narrow unless a loaded catalog and real filters caused it. | Automated fallback coverage exists; full physical matrix pending. | PENDING PHYSICAL |
| Click and attribution telemetry | Tests prove telemetry emits privacy-safe recommendation impressions, fallback-state-shown events, product-card taps, outbound retailer opens, retailer/product attribution, and outbound-routing failure reasons. Tests must also prove telemetry never records raw scan images, wardrobe photos, garment fingerprints, measurements, full user profiles, tokens, raw personal identifiers, or outbound URL query values. | Device console or local log evidence for recommendation impressions, fallback state shown, product-card taps, outbound retailer opens, retailer/product attribution, and routing-failure handling with sanitized fields only. | Gap: current code records local viewed product IDs, but formal privacy-safe telemetry gate is not proven. | BLOCKED |
| Customer-facing explanations | Snapshot/source tests verify selected-store no-inventory copy, static catalog notice, retailer responsibility disclosure, FTC disclosure, Amazon price rule, and no fabricated sale urgency. | Screenshots of each explanation in Shopping, My Stores, Store Search, product detail, and fallback states. | Partial copy coverage exists. | PENDING PHYSICAL |

## Required Physical Acceptance Pack

Each Shop AI acceptance run must attach:

- app version/build,
- commit SHA under test,
- device model and iOS version,
- catalog source: remote, cache, bundled, or none,
- loaded product count,
- product count by canonical retailer ID,
- selected retailer IDs,
- filtered product count,
- fallback state and reason,
- final displayed count by retailer,
- recommendation impressions observed,
- fallback-state events observed,
- product card taps observed,
- outbound retailer opens observed,
- retailer and product attribution observed,
- outbound routing failure reason when a failure is exercised,
- screenshots of Shopping home, My Stores, Store Search, product cards, product detail, fallback/error states, and retailer link-out,
- sanitized console diagnostics,
- exact PASS/FAIL per gate.

Do not fill any field with guessed values. If a value was not observed, mark it `NOT OBSERVED`.

## Required Automated Regression Pack

Before launch approval, the automated suite must include focused tests for:

- remote and bundled canonical retailer identity,
- selected-store filtering across every Shopping surface,
- missing/unknown retailer IDs failing safely,
- active product counts by retailer,
- zero-inventory selected stores preserving preferences while showing truthful fallback,
- remote success, valid cache fallback, bundled fallback, and total source failure,
- image URL null handling and image coverage reporting,
- Amazon price rule,
- expired sale suppression and sale-price freshness,
- unsafe URL rejection and safe `/go` preservation,
- affiliate tracking parameter insertion and placeholder suppression,
- grounded recommendation reason facts,
- duplicate suppression across catalog/live-search providers,
- offline and legitimate empty-filter states,
- privacy-safe telemetry payload shape, including impressions, fallback-state shown, product-card taps, outbound retailer opens, retailer/product attribution, and routing-failure reasons.

Telemetry must avoid sending or storing wardrobe photos, scan images, full user profiles, raw personal identifiers, measurements, tokens, credentials, or outbound URL query values.

## Store No-Inventory Rule

When selected stores produce zero matching products:

1. Keep the selected stores selected.
2. Explain that those selected stores currently have no matching products.
3. If the app fails open to all approved retailers, say so plainly.
4. Show the selected store names.
5. Never imply the replacement products came from the selected stores.

Approved fallback copy pattern:

> No matching products are currently available from your selected stores. Showing recommendations from all approved retailers until more inventory becomes available. Selected stores: Nike, Macy's, Best Buy, Target, Walmart.

## Launch Decision Rule

Shop AI may be called launch-ready only when every row in the Gate Matrix is PASS with linked evidence. A single BLOCKED or PENDING gate blocks launch-readiness language.

Feature expansion, catalog growth, and retailer onboarding may continue only after the affected gate remains truthful in degraded inventory states.
