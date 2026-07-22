# App Store Privacy Label Recommendations

Prepared: July 21, 2026

Status: submission recommendation only. App Store Connect has not been changed. The Account Holder must confirm the deployed backend and provider configuration immediately before submission.

## Governing rules

Apple says information processed only on the device is not considered collected for App Privacy disclosure. Derived information sent off-device must be evaluated separately. The conservative recommendations below cover StyleMatch Pro and its service providers and assume the current AI-consent, WeatherKit-only, account, and affiliate-shopping implementation.

Tracking: **No** for every category. The audited app contains no advertising SDK, data-broker flow, or cross-app tracking path.

## Recommended disclosures

| App Store category | Collected | Linked to user | Purpose | Basis and notes |
| --- | --- | --- | --- | --- |
| User ID | Yes | Yes | App Functionality | A pseudonymous account key and time-limited session support Sign in with Apple, account access, and account deletion. |
| Device ID | Yes | Yes to a device; may be associated with an account request | App Functionality; Security | A pseudonymous device hash may authenticate/rate-limit backend requests. Do not classify it as an advertising identifier. |
| Coarse Location | Yes when external AI is enabled and weather context is included | Yes | App Functionality; Product Personalization | Text weather/location context may be included in a consented AI request. Precise coordinates used only through Apple Weather are addressed separately below. |
| Other User Content | Yes | Yes | App Functionality; Product Personalization | User messages and relevant text styling context can be sent to StyleMatch Pro's backend and OpenAI after consent. This includes scan-derived facts, closet context, style preferences, sizes, budget, occasion, and weather context. |
| Purchase History | Conservative Yes if purchase or shopping-tendency context is included in AI requests | Yes | Product Personalization; App Functionality | The source inventory includes shopping-history/tendency fields. Confirm the exact Release request builder before final selection. If this context is never sent off-device or retained beyond real-time service, reassess under Apple's collection definition. |
| Product Interaction | Yes | Yes | App Functionality; Product Personalization | Saved, viewed, dismissed, favorite, and wish-list product interactions may influence recommendations or AI context. Confirm which fields leave the device in the signed Release build. |
| Other Diagnostic Data | Yes, limited | Not intentionally linked for analytics; pseudonymous request association may occur | App Functionality; Security | Backend service status, bounded counts, fixed failure classifications, numeric codes, and rate-limit information may be processed. App-owned diagnostics must contain no prompts, responses, profile values, scan content, URLs, tokens, or identifiers. |

## Evaluate but do not select without evidence

| Category | Recommendation | Reason |
| --- | --- | --- |
| Precise Location | Do not mark as collected by StyleMatch Pro solely for WeatherKit use | Apple states developers are not responsible for data Apple collects through Apple frameworks. The app sends location to Apple Weather, not to the StyleMatch backend. If the app or another partner receives or retains coordinates, this answer must change. |
| Photos or Videos | No | Outfit photos are processed on-device and the production external-AI request contains no photo, Base64 image, or image URL. Reconfirm in the signed Release binary and physical network test. |
| Name / Email Address | Do not select based only on Sign in with Apple | The audited backend uses Apple's subject to derive a pseudonymous account key and does not request name or email in its exchange payload. Change this if another production path collects them. |
| Payment Information | No | Physical-goods purchases occur on retailer sites; StyleMatch Pro does not receive payment-card information. |
| Search History | Reassess at submission | Shopping search terms may be sent to a retailer/catalog service to answer a request. Determine whether any party retains them longer than real-time service before choosing the label. |
| Crash Data / Performance Data | Do not select unless a crash or analytics service is enabled in the submitted build | No third-party crash/analytics SDK was identified in this checkpoint. Apple's own collection is not the developer's disclosure. |

## Processing and retention map

| Data | On device | StyleMatch backend | Cloudflare | OpenAI |
| --- | --- | --- | --- | --- |
| Outfit photo | Analyzed and may be saved locally | Not sent by the production AI path | Not sent by the production AI path | Not sent |
| Scan-derived text and score | Stored locally | Transmitted for a consented AI request; score remains authoritative | Routes/processes the request | Receives relevant text context to generate the response |
| AI messages and context | Conversation history stored locally | Processes the current request; no intentional prompt/response persistence identified | Routes/processes request and operational metadata | Processes input/output; OpenAI states API data may be retained up to 30 days unless another approved control applies |
| Account identifier/session | Stored locally as needed | Account/session records retained for account functionality and deleted through account deletion | D1/Worker infrastructure processes the records | Not sent as prompt content |
| Location/weather | Device obtains Apple Weather data | Only derived weather/location text included in a consented AI request | Routes that consented context | Receives the relevant text context |
| Shopping preferences/interactions | Primarily local | May be included as text context in a consented AI request | Routes that consented context | Receives the relevant text context |
| Privacy-safe diagnostics | Local unified logging or backend operational processing | Fixed events/counts/codes only | Processes operational metadata | No app diagnostic payload intentionally sent |

## Required pre-submission confirmations

1. Re-run the signed Release request-body inspection and confirm zero image transmission.
2. Confirm whether shopping searches, product interactions, or purchase history are retained by any production backend or partner beyond real-time service.
3. Confirm the production OpenAI account has not opted in to model-improvement data sharing; if it has, update the policy and labels before submission.
4. Confirm current Cloudflare D1, KV, Worker-log, and deletion-receipt retention behavior.
5. Confirm no crash/analytics SDK or server log configuration was added after this audit.
6. Enter the final answers in App Store Connect only after these checks; this document does not modify App Store Connect.
