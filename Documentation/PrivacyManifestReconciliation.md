# PrivacyInfo.xcprivacy Reconciliation — Build 18035 Draft

**INTERNAL DRAFT — NOT CUSTOMER-FACING — NOT FOR PUBLICATION**
**OWNER/LEGAL REVIEW AND VERIFIED BUSINESS FACTS REQUIRED**

## Current manifest declarations

- Tracking: `false`; no tracking domains.
- Required-reason APIs: UserDefaults (`CA92.1`), file timestamps (`C617.1`), and system boot time (`35F9.1`).
- Collected data declarations: User ID, Device ID, Precise Location, and Other User Content.

## AI Memory conclusion

No manifest edit is proposed solely for Phase 3 AI Memory. The store is local-only and the existing `Other User Content` declaration already covers the bounded chat/request content category at the manifest level. Apple collection and privacy-label classifications still require owner/legal review of deployed Worker and provider practices.

The manifest cannot cure the App Review findings: it neither presents pre-transmission AI authorization nor identifies a verified downstream AI recipient. The WeatherKit entitlement also requires a provider-path and attribution decision; do not treat this no-manifest-change conclusion as evidence that WeatherKit attribution is satisfied.

## Required follow-up

Re-run this reconciliation after any change to AI request routing, third-party SDKs, analytics, affiliate processing, account identity, or cloud sync. Do not remove existing manifest declarations without source and deployment evidence.
