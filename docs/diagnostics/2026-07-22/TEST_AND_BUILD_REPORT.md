# Test and Build Report

Date: 2026-07-22

## Commands and results

| Check | Result |
|---|---|
| Fresh pre-edit `swift test` | PASS — 697/697 |
| `swift test --filter OutfitClassificationTests` | PASS — 14/14 |
| `swift test --filter StylistChatServiceTests` | PASS — 75/75 before final backup test |
| Final `swift test` | PASS — 707/707 in 10.419 seconds |
| Debug simulator `xcodebuild ... -configuration Debug ... CODE_SIGNING_ALLOWED=NO build` | PASS |
| Release simulator `xcodebuild ... -configuration Release ... CODE_SIGNING_ALLOWED=NO build` | PASS using clean derived-data path |
| `xcodebuild ... analyze` | PASS with two pre-existing protected Shopping warnings |
| `swift package show-dependencies --format text` | PASS — no external dependencies |
| `git diff --check` | PASS after final report generation |
| Shopping source drift from pinned `5463866...` | PASS — no changed Shopping/catalog path |

## Non-product tooling incidents

- One focused test compile initially used a nonexistent date-decoder strategy in a new fixture. The fixture was corrected; production code was not implicated.
- One Release rerun encountered a locked build database because the same derived-data path was still held. A fresh derived-data path completed successfully.
- SwiftPM warns that `StyleMatchAI/Info.plist` is unhandled by the verification package target. The Xcode app target consumes its plist normally.
- Static analysis reports an unreachable catch and unused binding in accepted `ShoppingView.swift`. They predate this work and were not changed under the Shopping freeze.

## Compiler warning decision

No warning was found in the modified AI, scan, classification, speech, persistence, or test sources. The only analyzer warnings are in protected Shopping code and are recorded as SYS-014 rather than silently waived.

## Physical limitations

Simulator compilation does not validate microphone routes, Speech permissions, camera orientation, Vision/OCR latency, WeatherKit, Apple sign-in, or retained device data. Those remain in the physical plan.
