# Screen Awareness Matrix

Date: 2026-07-22

The AI receives typed evidence only. It does not receive screen pixels.

| Surface/state | Permitted evidence | Forbidden inference | Result |
|---|---|---|---|
| Home | home entry point, authorized profile/weather aggregates | active outfit without scan | PARTIALLY VERIFIED |
| Scan camera/no result | scan tab, no active scan, visible aggregates | current score or garment | PASS locally |
| Live scan result | scan ID, score, occasion, section, typed analysis | unrelated saved scan | PASS locally |
| Saved scan detail | selected saved ID and that scan’s facts | globally latest scan | PASS |
| Closet | loaded-empty/loaded-with-items/unavailable | ownership of history/Shopping items | PASS locally |
| Outfit detail | no dedicated typed detail identity | specific selected outfit | NOT EVIDENCED |
| Shopping root | shop tab/entry point only | selected product, price, retailer card | PARTIALLY VERIFIED |
| Store selection | no typed selected-store field | named current store | NOT EVIDENCED |
| Product detail | no typed product ID | product-specific answer | NOT EVIDENCED |
| Favorites | no dedicated favorite identity | current favorite item | NOT EVIDENCED |
| Profile | profile entry point and authorized preferences | hidden/private fields | PARTIALLY VERIFIED |
| AI Stylist | AI tab plus carried typed scan only when authorized | prior screen after invalidation | PASS locally |
| Weather/daily recommendation | weather facts supplied by context owner | live conditions not present | PARTIALLY VERIFIED |
| Loading/error/permission | limited state-specific copy in owning view | successful content | PARTIALLY VERIFIED |

## Transition safeguards

- Current scan handoff invalidates on new camera/gallery sessions and deletion.
- Saved scan availability is rechecked.
- Root-tab selection dismisses the keyboard without manufacturing scan context.
- Context is validated at send time, not frozen only when chat opens.
- Contradictory screen/scan identities fail closed.

## Gap

The typed model does not yet represent selected products, store cards, favorites, outfit detail, or explicit loading/error timestamps. Until a separately scoped contract is added, AI must answer those questions generically or state that the selected item is unavailable. This checkpoint did not modify Shopping.
