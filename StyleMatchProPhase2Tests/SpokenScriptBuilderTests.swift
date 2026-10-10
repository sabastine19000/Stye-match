import XCTest
@testable import StyleMatchPro

final class SpokenScriptBuilderTests: XCTestCase {
    func testSpeechFriendlyTextStripsMarkdownEmojiAndBullets() {
        let input = """
        ## Score Notes ✨
        - **Colors** work well.
        • `Fit` could be cleaner.
        1. Try polished shoes.
        """

        let spoken = SpokenScriptBuilder.speechFriendlyText(from: input)

        XCTAssertFalse(spoken.contains("#"))
        XCTAssertFalse(spoken.contains("*"))
        XCTAssertFalse(spoken.contains("`"))
        XCTAssertFalse(spoken.contains("✨"))
        XCTAssertFalse(spoken.contains("•"))
        XCTAssertFalse(spoken.contains("- "))
        XCTAssertTrue(spoken.contains("Colors work well."))
        XCTAssertTrue(spoken.contains("Fit could be cleaner."))
    }

    func testSpeechFriendlyTextConvertsScoreForTheEar() {
        let spoken = SpokenScriptBuilder.speechFriendlyText(from: "Your outfit scored 87/100. Strong casual look.")

        XCTAssertTrue(spoken.contains("87 out of 100"))
        XCTAssertFalse(spoken.contains("87/100"))
    }

    func testSpeechFriendlyTextTrimsAtSentenceBoundary() {
        let input = [
            "Sentence one is clear.",
            "Sentence two is clear.",
            "Sentence three is clear.",
            "Sentence four is clear.",
            "Sentence five should not be spoken."
        ].joined(separator: " ")

        let spoken = SpokenScriptBuilder.speechFriendlyText(from: input)

        XCTAssertTrue(spoken.hasSuffix("."))
        XCTAssertFalse(spoken.contains("Sentence five"))
        XCTAssertLessThanOrEqual(spoken.split(separator: ".").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count, 4)
    }

    func testScanScriptSelectionIsDeterministicAndVariesBySeed() {
        let explanation = "Your outfit scored 86/100. The colors work well together."

        let first = SpokenScriptBuilder.scanScript(explanation: explanation, scanIdentifier: "scan-a")
        let repeated = SpokenScriptBuilder.scanScript(explanation: explanation, scanIdentifier: "scan-a")
        let second = SpokenScriptBuilder.scanScript(explanation: explanation, scanIdentifier: "scan-b")

        XCTAssertEqual(first, repeated)
        XCTAssertNotEqual(first, second)
    }
}
