# StyleMatch Pro v1.2 Handoff Summary

This is the active StyleMatch Pro iOS project used for the latest phone build.

## Build Identity

- App display name: StyleMatch Pro 1
- Version: 1.2
- Build: 7
- Bundle ID: com.sabastine.stylematchai
- Correct Xcode project: StyleMatchAI.xcodeproj

## Important Product Rule

StyleMatch Pro owns the scoring engine.

ChatGPT/AI Stylist may explain scan results, personalize advice, suggest improvements, and help with shopping/design ideas, but it must not generate, recalculate, override, or contradict the StyleMatch Pro score.

## Major Areas Added or Refined

- Camera and gallery scan flow
- Scan history with recent outfit cards
- Outfit classification guardrails for casual, loungewear, business casual, traditional/cultural wear, and non-clothing rejection
- Deterministic style score logic in ScanView
- ChatGPT AI Stylist chat and score explanation
- Screen-aware AI context for current scan results
- Personal stylist profile data models
- Outfit memory and feedback-ready personalization stores
- PersonalizationContextBuilder for compact prompt context
- Weather styling UI and live weather display path
- Profile and theme controls
- Internal beta-ready app identity: version 1.2 build 7

## Phase 2 Personalization

Personalization context is injected only into AI-facing prompts:

- Score explanation
- Design suggestions
- Shopping recommendations
- Chat/stylist responses where app context sharing is enabled

The deterministic score path remains separate from AI.

## Key Files

- StyleMatchAI/ScanView.swift
- StyleMatchAI/OpenAIStylistClient.swift
- StyleMatchAI/ShopView.swift
- StyleMatchAI/AIStyleAdvisor.swift
- StyleMatchAI/PersonalStylist/StylistProfileModels.swift
- StyleMatchAI/PersonalStylist/ProfileStore.swift
- StyleMatchAI/PersonalStylist/OutfitMemoryStore.swift
- StyleMatchAI/PersonalStylist/StylistContextBuilder.swift
- StyleMatchAI/PersonalStylist/PersonalStylistAIContext.swift
- StyleMatchProPhase2Tests/StyleMatchProPhase2Tests.swift

## Current Testing Recommendation

Use this as an internal beta build only. Do not public-release yet.

Primary beta focus:

- App launches reliably
- Camera and gallery scan work
- Score appears quickly
- Clothing category is realistic
- ChatGPT responds with relevant answers
- Weather styling updates
- Scan history and closet data persist
- Profile/theme settings do not break the UI

