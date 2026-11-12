# Suit & Color Match

Entry: Home → Suit & Color Match. Uses the existing HomeView and Models target sources; no package, API key, backend change or paid service required.

Implemented: eight suit colors, five occasions, Classic/Modern/Bold looks, shirt/tie/shoe/belt colors, labeled visual palettes, local photo reference with mandatory manual color confirmation, exact category/color closet matches, persistent save/remove actions. Interview shirts remain conservative; modern/bold date looks allow an optional tie. Other occasions currently share the same palette logic. Saved looks use existing account presentation snapshots and delete-data handling. Reference photos remain temporary and are not saved or sent to a server.

Limits: palette previews are color swatches, not generated outfit photography or virtual try-on. No automatic photo color detection. No fit/fabric inference. Closet matching requires recorded exact colors and supported category labels; uncertain matches are omitted. No new pricing or paywall changes.

Validation: `git diff --check` passes. XCTest cases added for the full suit/occasion matrix, JSON round trips, conservative interview recommendations, optional date ties, false-positive closet matches, and account switching/deletion. Swift and Xcode are unavailable in the implementation environment; these tests and iOS compilation have NOT run.

Before release on Mac:
1. Run `swift test` using the existing Package.swift.
2. Build the StyleMatchAI Xcode scheme for iPhone and iPad; resolve any compiler issues before distribution.
3. Open Home → Suit & Color Match; check all pickers and three result sections, VoiceOver, Dynamic Type, light/dark mode and back navigation.
4. Select a photo; results must wait for manual color confirmation. Try cancellation, unreadable images, images over 15 MB, and rapidly selecting another image.
5. Add closet pieces with matching and nonmatching categories/colors; only matching entries should appear.
6. Save, relaunch, remove, switch accounts and run Delete Local Data; check persistence and isolation.
7. Verify behavior on a physical iPhone before preparing a signed TestFlight build. This change has not been distributed or installed.
