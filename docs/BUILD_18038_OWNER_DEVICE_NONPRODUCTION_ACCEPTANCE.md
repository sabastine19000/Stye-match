# Build 18038 Style Friends owner-device acceptance harness

Status: `OWNER_DEVICE_NONPRODUCTION_ACCEPTANCE_ONLY`

This source-only harness is for a separately authorized signed Debug owner-device artifact. It is compiled only when both `DEBUG` and `STYLE_FRIENDS_OWNER_DEVICE_ACCEPTANCE` are present; it is excluded from Release and from Simulator fixtures.

The harness accepts only an out-of-band, in-memory synthetic bearer session and optional synthetic approved-card reference at launch. It requires the exact HTTPS endpoint `stylematch-18038-friends-auth-test.sabastine-7000.workers.dev`, whose approved isolated D1 authority is `1205c191-6fa7-4618-b1bd-83eb336a855c`. It rejects missing or invalid input and does not fall back to production or staging.

The override is limited to Style Friends and its synthetic-card social operation. It never writes the normal Keychain session, normal share-card history, Profile, Closet, AI Memory, scans, CloudKit, or production ShareableScoreCard data. The visible `Style Friends Test Environment` indicator distinguishes fixture content from customer data.

This is a nonproduction testing mechanism, not a customer-facing data practice. It adds no Release/App Store privacy disclosure category. The public policy remains `PUBLICATION_CANDIDATE_PENDING_EVIDENCE`.
