import XCTest
@testable import StyleMatchPro

final class ScanUpgradePromptBuilderTests: XCTestCase {
    private let guardrails = [
        "Keep the response under four sentences, warm and specific.",
        StylistMessageComposer.aiPhrasingInstruction
    ]

    func testRepresentativeWorstCaseFitsWorkerMessageBudgetAndRemainsValidJSON() throws {
        let garments = (1...18).map { "detailed garment \($0) with a deliberately long visible description" }
        let patterns = (1...10).map { "pattern \($0) with confidence-qualified detail" }
        let fitAssessment = String(repeating: "fit evidence remains uncertain; ", count: 30)
        let weather = (1...8).map { "weather fact \($0): feels-like conditions and practical guidance" }
        let history = (1...24).map { "history \($0): older confirmed outfit preference with detail" }
        let legacyMessage = legacyDuplicatedMessage(
            garments: garments,
            patterns: patterns,
            fitAssessment: fitAssessment,
            weather: weather,
            history: history
        )
        let prompt = makePrompt(
            garments: garments,
            patterns: patterns,
            fitAssessment: fitAssessment,
            weather: weather,
            history: history
        )

        XCTAssertGreaterThan(legacyMessage.utf16.count, 2_000)
        XCTAssertLessThanOrEqual(prompt.utf16Count, ScanUpgradePrompt.maximumUTF16Count)
        XCTAssertLessThan(prompt.utf16Count, 2_000)
        print("[Scan Upgrade Size Test] duplicated_before_utf16=\(legacyMessage.utf16.count) compact_after_utf16=\(prompt.utf16Count)")
        let payload = try decodedPayload(prompt.message)
        XCTAssertEqual((payload["score"] as? [String: Any])?["value"] as? Int, 80)
        XCTAssertEqual((payload["score"] as? [String: Any])?["tier"] as? String, "Good Match")
        XCTAssertEqual(((payload["outfit"] as? [String: Any])?["colors"] as? [String]) ?? [], ["gray", "cream", "olive"])
        XCTAssertEqual(payload["weather"] as? [String], weather)
        XCTAssertEqual(payload["guardrails"] as? [String], ScanUpgradePrompt.immutableGuardrails + guardrails)
    }

    func testFactsAndGuardrailsAppearExactlyOnce() {
        let tierFact = "tier-unique"
        let scoreFact = "score-breakdown-unique"
        let garmentFact = "garment-unique"
        let colorFact = "color-unique"
        let patternFact = "pattern-unique"
        let fitFact = "fit-unique"
        let weatherFact = "weather-unique"
        let historyFact = "history-unique"
        let guardrailOne = "guardrail-one-unique"
        let guardrailTwo = "guardrail-two-unique"
        let prompt = PersonalizationContextBuilder.buildScanUpgradePrompt(
            score: 80,
            tier: tierFact,
            breakdown: [scoreFact: 20],
            garments: [garmentFact],
            colors: [colorFact],
            patterns: [patternFact],
            fitAssessment: fitFact,
            weatherFacts: [weatherFact],
            historyFacts: [historyFact],
            guardrails: [guardrailOne, guardrailTwo]
        )

        for fact in [tierFact, scoreFact, garmentFact, colorFact, patternFact, fitFact, weatherFact, historyFact, guardrailOne, guardrailTwo] {
            XCTAssertEqual(prompt.message.components(separatedBy: fact).count - 1, 1)
        }
        XCTAssertFalse(prompt.message.contains("allowedMessages"))
        XCTAssertFalse(prompt.message.contains("systemGuardrails"))
    }

    func testInitialAndFollowUpPreserveEveryImmutableGuardrailSemantic() throws {
        let initial = makePrompt(
            garments: ["shirt", "pants"],
            patterns: ["solid"],
            fitAssessment: "Fit evidence was recorded.",
            weather: ["Warm with high-confidence weather."],
            history: []
        )
        let followUp = makeFollowUpPrompt(question: "How can I improve it?")

        for prompt in [initial, followUp] {
            let payload = try decodedPayload(prompt.message)
            let retained = try XCTUnwrap(payload["guardrails"] as? [String])
            XCTAssertEqual(
                Array(retained.prefix(ScanUpgradePrompt.immutableGuardrails.count)),
                ScanUpgradePrompt.immutableGuardrails
            )
            let semantics = retained.joined(separator: " ").lowercased()
            for required in [
                "<85% garment confidence=uncertain/not fact",
                "background/non-worn",
                "object-only/non-outfit",
                "insufficient/unrecognized",
                "sleepwear/lounge",
                "occasion needs evidence",
                "weather specifics need high confidence",
                "hot=no heavy layers",
                "profile/budget/closet/weather/outfit facts",
                "factual/practical/consistent/nonduplicate/weather-safe",
                "fixed scores",
                "no visual-inspection/unsupported claims"
            ] {
                XCTAssertTrue(semantics.contains(required), "Missing immutable Scan guardrail semantic: \(required)")
            }
            XCTAssertLessThanOrEqual(prompt.utf16Count, ScanUpgradePrompt.maximumUTF16Count)
        }
    }

    func testTrimmingDropsOldestHistoryFirst() throws {
        let history = (1...20).map { "history-\($0)-" + String(repeating: "x", count: 120) }
        let prompt = makePrompt(
            garments: ["shirt", "pants"],
            patterns: ["solid"],
            fitAssessment: "Fit was not verified from this scan.",
            weather: ["Warm and rainy."],
            history: history
        )

        XCTAssertLessThan(prompt.retainedHistoryCount, history.count)
        let payload = try decodedPayload(prompt.message)
        let retained = payload["history"] as? [String] ?? []
        XCTAssertFalse(retained.contains(history[0]))
        XCTAssertEqual(retained.last, history.last)
    }

    func testLongestRemainingSectionTrimsWithoutWeakeningGuardrailsOrScore() throws {
        let prompt = makePrompt(
            garments: ["shirt", "pants"],
            patterns: ["solid"],
            fitAssessment: String(repeating: "very long fit detail ", count: 160),
            weather: ["Warm."],
            history: []
        )

        XCTAssertTrue(prompt.outfitWasTrimmed)
        XCTAssertLessThanOrEqual(prompt.utf16Count, ScanUpgradePrompt.maximumUTF16Count)
        let payload = try decodedPayload(prompt.message)
        XCTAssertEqual((payload["score"] as? [String: Any])?["value"] as? Int, 80)
        XCTAssertEqual(payload["guardrails"] as? [String], ScanUpgradePrompt.immutableGuardrails + guardrails)
        XCTAssertEqual(payload["weather"] as? [String], ["Warm."])
        let outfit = try XCTUnwrap(payload["outfit"] as? [String: Any])
        XCTAssertEqual(outfit["garments"] as? [String], ["shirt", "pants"])
        XCTAssertEqual(outfit["patterns"] as? [String], ["solid"])
        XCTAssertLessThan((outfit["fitAssessment"] as? String)?.utf16.count ?? .max, String(repeating: "very long fit detail ", count: 160).utf16.count)
    }

    func testAllHistoryIsDroppedBeforeLongestSectionIsTruncated() throws {
        let history = (1...4).map { "oldest-order-\($0)-" + String(repeating: "h", count: 100) }
        let fit = String(repeating: "longest-fit-section ", count: 80)
        let prompt = makePrompt(
            garments: ["shirt"],
            patterns: ["solid"],
            fitAssessment: fit,
            weather: ["Weather must remain verbatim."],
            history: history,
            budget: 900
        )

        XCTAssertEqual(prompt.retainedHistoryCount, 0)
        XCTAssertTrue(prompt.outfitWasTrimmed)
        let payload = try decodedPayload(prompt.message)
        XCTAssertEqual(payload["history"] as? [String], [])
        XCTAssertEqual(payload["weather"] as? [String], ["Weather must remain verbatim."])
        let outfit = try XCTUnwrap(payload["outfit"] as? [String: Any])
        XCTAssertLessThan((outfit["fitAssessment"] as? String)?.utf16.count ?? .max, fit.utf16.count)
    }

    func testScanUpgradeCallSiteUsesCompactBuilderAndOldBuilderIsGone() throws {
        let sourceURL = repositoryRoot().appendingPathComponent("StyleMatchAI/ScanView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("buildScanUpgradePrompt("))
        XCTAssertTrue(source.contains("debugRequestLabel: \"scan_upgrade\""))
        XCTAssertFalse(source.contains("buildScoreExplanationPrompt("))
    }

    func testRepresentativeScanFollowUpCompactsFormerOversizedPayload() throws {
        let legacy = representativeLegacyFollowUpMessage()
        let prompt = makeFollowUpPrompt(question: "Why did this outfit receive this score, and how can I improve it?")

        XCTAssertGreaterThan(legacy.utf16.count, 3_000)
        XCTAssertLessThanOrEqual(prompt.utf16Count, ScanUpgradePrompt.maximumUTF16Count)
        XCTAssertLessThanOrEqual(prompt.utf16Count, StylistChatMessageLimit.maximumUTF16Length)
        print("[Scan Follow-Up Size Test] legacy_utf16=\(legacy.utf16.count) compact_utf16=\(prompt.utf16Count)")

        let payload = try decodedPayload(prompt.message)
        let score = try XCTUnwrap(payload["score"] as? [String: Any])
        XCTAssertEqual(score["value"] as? Int, 82)
        XCTAssertEqual(score["tier"] as? String, "Strong")
        XCTAssertEqual(
            score["breakdown"] as? [String: Int],
            ["accessories": 7, "color": 21, "fit": 20, "occasion": 18, "pattern": 17]
        )
        let outfit = try XCTUnwrap(payload["outfit"] as? [String: Any])
        XCTAssertEqual(outfit["colors"] as? [String], ["navy", "blue", "cream"])
        XCTAssertFalse((payload["evidence"] as? [String] ?? []).isEmpty)
        XCTAssertEqual(payload["weather"] as? [String], ["72°F", "clear", "feels like 72°F", "low rain chance"])
        XCTAssertEqual(
            Array((payload["guardrails"] as? [String] ?? []).prefix(ScanUpgradePrompt.immutableGuardrails.count)),
            ScanUpgradePrompt.immutableGuardrails
        )
    }

    func testFollowUpPreservesUTF16UserTextAndEveryGeneratedMessageFits() {
        let question = "Would 😀 work with this outfit?"
        let prompt = makeFollowUpPrompt(question: question)
        let messages = [
            ChatRequest.RequestMessage(role: "assistant", content: "Previous answer"),
            ChatRequest.RequestMessage(role: "user", content: prompt.message)
        ]

        XCTAssertEqual(StylistChatMessageLimit.utf16Length(of: "😀"), 2)
        XCTAssertTrue(prompt.message.contains(question))
        XCTAssertNil(StylistChatMessageLimit.validationError(for: messages))
        XCTAssertTrue(messages.allSatisfy { $0.content.utf16.count <= 2_000 })
    }

    func testScanFollowUpDoesNotDuplicateStructuredJSONIntoAppContext() throws {
        let sourceURL = repositoryRoot().appendingPathComponent("StyleMatchAI/ScanView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "private func askChatGPTAboutCurrentScan("))
        let end = try XCTUnwrap(source.range(of: "private func generateDesignIdea(", range: start.upperBound..<source.endIndex))
        let followUpSource = String(source[start.lowerBound..<end.lowerBound])

        XCTAssertTrue(followUpSource.contains("buildScanFollowUpPrompt("))
        XCTAssertFalse(followUpSource.contains("structuredOutfitFacts("))
        XCTAssertFalse(followUpSource.contains("Current outfit analysis JSON"))
        XCTAssertFalse(followUpSource.contains("Previous outfit analysis"))
    }

    func testCompletedFallbackUsesApprovedCopyWithoutRetryOrInternalError() throws {
        let fallback = try XCTUnwrap(ScanAIFallbackPresentation.completed(localAdvice: "The fixed score reflects strong color balance."))

        XCTAssertTrue(fallback.message.contains(ScanAIFallbackPresentation.friendlyOfflineMessage))
        XCTAssertTrue(fallback.message.contains("The fixed score reflects strong color balance."))
        XCTAssertFalse(fallback.message.localizedCaseInsensitiveContains("api_error"))
        XCTAssertNil(fallback.retryPrompt)
    }

    func testTrueNoAnswerFallbackStillAllowsRetry() {
        XCTAssertNil(ScanAIFallbackPresentation.completed(localAdvice: " \n "))

        let fallback = ScanAIFallbackPresentation.noAnswer(prompt: "Help me improve this")
        XCTAssertEqual(fallback.retryPrompt, "Help me improve this")
    }

    func testInitialScanAdviceInstructionRemainsUnchanged() throws {
        let prompt = makePrompt(
            garments: ["shirt", "jeans"],
            patterns: ["solid"],
            fitAssessment: "Clean fit evidence.",
            weather: ["Warm."],
            history: []
        )

        XCTAssertTrue(prompt.message.hasPrefix(ScanUpgradePrompt.initialAdviceInstruction))
        XCTAssertNil(try decodedPayload(prompt.message)["evidence"])
    }

    private func makePrompt(
        garments: [String],
        patterns: [String],
        fitAssessment: String,
        weather: [String],
        history: [String],
        budget: Int = ScanUpgradePrompt.maximumUTF16Count
    ) -> ScanUpgradePrompt {
        PersonalizationContextBuilder.buildScanUpgradePrompt(
            score: 80,
            tier: "Good Match",
            breakdown: ["color": 20, "pattern": 20, "fit": 13, "occasion": 0, "accessories": 6],
            garments: garments,
            colors: ["gray", "cream", "olive"],
            patterns: patterns,
            fitAssessment: fitAssessment,
            weatherFacts: weather,
            historyFacts: history,
            guardrails: guardrails,
            budget: budget
        )
    }

    private func makeFollowUpPrompt(question: String) -> ScanUpgradePrompt {
        PersonalizationContextBuilder.buildScanFollowUpPrompt(
            question: question,
            score: 82,
            tier: "Strong",
            breakdown: ["color": 21, "pattern": 17, "fit": 20, "occasion": 18, "accessories": 7],
            garments: (1...12).map { "visible garment \($0) with confidence-qualified detail" },
            colors: ["navy", "blue", "cream"],
            patterns: ["solid", "low-pattern appearance"],
            fitAssessment: String(repeating: "fit evidence from the completed scan; ", count: 12),
            evidenceFacts: [
                "color harmony: coordinated navy and cream palette",
                "coordination: balanced casual outfit",
                "formality: casual",
                "seasonal evidence: mild weather match",
                "occasion evidence: everyday",
                "improvement evidence: add one restrained finishing accessory"
            ],
            weatherFacts: ["72°F", "clear", "feels like 72°F", "low rain chance"],
            historyFacts: (1...12).map { "history \($0): confirmed preference" },
            guardrails: guardrails + ["Keep objective score evidence distinct from personalized advice."]
        )
    }

    private func representativeLegacyFollowUpMessage() -> String {
        let structuredFacts: [String: Any] = [
            "scanSource": "camera",
            "normalized": true,
            "detectedItems": ["shirt", "jeans"],
            "itemConfidence": [["item": "shirt", "confidence": 0.92], ["item": "jeans", "confidence": 0.90]],
            "colors": ["navy", "blue"],
            "colorDetection": ["garment_colors": ["navy", "blue"], "confidence": 80, "notes": "High confidence: garment colors came from the completed scan palette."],
            "patterns": ["solid or low-pattern appearance"],
            "fabricsAndTextures": ["unknown"],
            "outfitCategory": "Casual",
            "styleRankings": [["name": "Casual", "confidence": 90, "reason": "Detected casual garments"]],
            "occasion": "Everyday",
            "weather": "72°F, clear",
            "weatherSource": "live",
            "feelsLike": "72°F",
            "rainChance": "0%",
            "humidity": "45%",
            "windSpeed": "5 mph",
            "uvIndex": "4",
            "environment": "indoor",
            "lighting": "clear",
            "scanType": "full outfit",
            "styleScore": 82,
            "scoreBreakdown": ["colorHarmony": 21, "patternBalance": 17, "fitQuality": 20, "occasionMatch": 18, "accessoryUse": 7],
            "scoreTier": "Strong",
            "scoreOwner": "StyleMatch AI scoring logic",
            "outfitFingerprint": "saved-result",
            "culturalAwareness": String(repeating: "culture-neutral evidence from completed scan; ", count: 4),
            "guardrails": [
                "Facts only in the Computer Vision layer.",
                "ChatGPT explains and improves but does not control the score.",
                "Do not infer race, ethnicity, nationality, religion, age, gender, or identity.",
                "Do not guess brands unless high confidence evidence is provided.",
                "Do not label traditional clothing casual by default.",
                "Do not call hoodie, hooded flannel, plaid shacket, jeans, boots, or rugged casual outfits business casual unless at least two business-style items are detected.",
                "If styleRankings show Casual first, describe the outfit as everyday casual and avoid work/business wording.",
                "If outfitCategory is Sleepwear or Loungewear, explain it as home comfort clothing and avoid business wording.",
                "If outfitCategory is Unrecognized Item, ask for a clearer photo.",
                "Ask for a better image if lighting or clothing visibility is unreliable."
            ]
        ]
        let data = try! JSONSerialization.data(withJSONObject: structuredFacts, options: [.prettyPrinted, .sortedKeys])
        let json = String(decoding: data, as: UTF8.self)
        return """
        Previous outfit analysis:
        \(json)

        User question:
        Why did this outfit receive this score, and how can I improve it?

        Answer as StyleMatch Pro's Personal AI Stylist.
        Give specific, actionable recommendations.
        Include actual brand names, price ranges, stores, product types, or closet-item ideas when relevant.
        Keep the response conversational, not JSON, because this is a chat follow-up.
        Do not ask the customer to repeat the score, clothing, colors, lighting, weather, or detected items.
        Do not generate a new score. Explain the existing StyleMatch Pro score only.
        Use garment_colors/colorDetection only for colors and ignore background colors.
        If the previous analysis says a style is casual, rugged casual, sleepwear, traditional wear, or another non-business category, do not call it business casual.
        Keep the answer friendly, direct, professional, fashion-focused, and practical.
        """
    }

    private func legacyDuplicatedMessage(
        garments: [String],
        patterns: [String],
        fitAssessment: String,
        weather: [String],
        history: [String]
    ) -> String {
        let scoreFacts = ["This is a strong look at 80/100."]
        let allowedMessages = scoreFacts + weather + history
        let payload: [String: Any] = [
            "score": 80,
            "scoreTier": "Good Match",
            "scoreFacts": scoreFacts,
            "outfit": [
                "garments": garments,
                "colors": ["gray", "cream", "olive"],
                "patterns": patterns,
                "fitAssessment": fitAssessment
            ],
            "weatherFacts": weather,
            "historyFacts": history,
            "allowedMessages": allowedMessages,
            "systemGuardrails": guardrails
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let json = String(decoding: data, as: UTF8.self)
        return "\(json)\nGUARDRAILS:\n\(guardrails.joined(separator: "\n"))"
    }

    private func decodedPayload(_ message: String) throws -> [String: Any] {
        let marker = "FACTS:\n"
        let json = try XCTUnwrap(message.components(separatedBy: marker).last)
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
