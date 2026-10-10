# Build 18035 AI Memory Data-Flow Inventory

**INTERNAL DRAFT — NOT CUSTOMER-FACING — NOT FOR PUBLICATION**
**OWNER/LEGAL REVIEW AND VERIFIED BUSINESS FACTS REQUIRED**

Status: **Source-backed draft, reviewed against commit `d18d5cbb39773c28953b99642da52bdfbdaedbc2` and reconciled in this worktree.**

## Persistent AI Memory

- Categories: Style Preferences, Sizes & Fit, Work & Uniform, PPE / Safety, Shopping Preferences, Corrections, and bounded Referenced Outfits.
- Creation: explicit Remember, confirmed suggestion, approved reference, or a completed explicit edit. Viewing app content does not call the store mutation path.
- Scope: normalized active local identity; the store uses Application Support under the Personal Stylist snapshot root.
- Capacity: 1,000 active confirmed records per normalized identity. A new ordinary save at capacity returns an explicit capacity result; it does not evict an active record. An edit supersedes an existing active record without increasing the active count.
- Export: active records only are included in the local export. The export excludes credentials, tokens, device identifiers, diagnostics, raw images, raw OCR, raw Calendar events, and internal routing identifiers.
- Expiration: records with an expiry stop being active when their expiry is reached. Persistent records otherwise have no fixed expiry. Current source does not physically compact expired or superseded inactive history as a general retention process; inactive records do not consume the 1,000 active-record capacity.

## User-directed deletion

- Forget Memory removes the selected record and its correction lineage from the AI Memory document and its three recovery snapshots.
- Forget Category removes records in that category from the document and recovery snapshots.
- Clear All AI Memories removes all AI Memory records for the active local identity from the document and recovery snapshots.
- Clear Temporary AI Context is separate, does not write a persistent context store, and keeps AI Memory.
- `Delete My Saved Data` invokes the current identity’s personalization deletion path, including the AI Memory document and recovery snapshots, then clears the broader supported local customer data. This local deletion does not by itself prove server-side account deletion.

## AI request transmission

- The app’s chat service sends requests to the StyleMatch backend `/v1/chat` endpoint when the user requests AI assistance.
- The resolver can add a small relevant subset of active confirmed AI Memory facts to the typed request context, bounded to 8 facts and 1,600 serialized characters.
- The resolver excludes raw images, screenshots, raw OCR, raw Calendar events, full Profile snapshots, full scan history, full chat history, credentials, tokens, device identifiers, and internal routing or generation identifiers from its own memory projection.
- The broader existing `ChatContext` remains an independently audited request contract; source evidence for deployed backend/provider retention is not available in this lane.

## App Review transmission finding — source-backed

- `LiveChatTransport` serializes the customer’s text and a `ChatContext` to the configured StyleMatch backend `/v1/chat` endpoint, with an authenticated bearer session where available. The client request includes no raw scan image field.
- Depending on the entry point, `ChatContext` can carry bounded profile preferences, size/fit, budget, closet summaries, saved or active scan facts and score breakdowns, weather/city summaries, selected occasion, screen context, recent conversation text, and a relevant AI Memory projection. A scan classification adjudication route sends a narrower structured input that excludes images, raw OCR, profile, history, and chat memory.
- A versioned, identity-scoped AI transmission decision is stored locally as `undecided`, `accepted`, or `declined`. No decision or a version mismatch is `undecided`; `shareAppContextWithChatGPT` remains a separate context-selection preference and is never migrated into consent.
- `LiveChatTransport` enforces this decision after local request validation and before it constructs or sends a network request. The request is blocked locally unless the current decision is `accepted`; the request builder repeats the guard defensively.
- Interactive AI Stylist chat presents an explicit disclosure before an undecided send. It names the immediate recipient `https://api.stylematchpro.com/v1/chat`, describes bounded categories and purpose, and offers Agree & Continue or Not Now. The disclosure intentionally omits unverified downstream-provider identity.
- A fresh completed scan can initiate an optional AI recommendation upgrade after local scoring when an account session exists. It cannot transmit unless the same shared transport observes `accepted`; it never creates consent automatically. The bounded classification adjudicator is covered by the same boundary.
- Profile provides AI Transmission Privacy controls for later review and revocation. Revocation blocks future AI transmissions but does not delete local app data or assert remote recall/deletion.
- The immediate recipient evidenced in app source is the configured StyleMatch backend host. A local candidate Worker source can call OpenAI, but deployed downstream provider behavior is unverified.

## Separate authorities

Profile, Saved Scans, scan image assets, Closet, Shopping/favorites, Calendar, and Weather remain their own source stores. AI Memory stores selected bounded facts and references only; it does not duplicate those stores wholesale.
