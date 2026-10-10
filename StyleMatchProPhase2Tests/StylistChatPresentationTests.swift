import XCTest
@testable import StyleMatchPro

final class StylistChatPresentationTests: XCTestCase {
    func testDisplayTextRemovesRawMarkdownAndHTMLMarkers() {
        XCTAssertEqual(
            StylistChatPresentation.displayText("**Best:** `cream` <b>first</b>"),
            "Best: cream first"
        )
    }

    func testDisplayTextPreservesGroundedPlainText() {
        XCTAssertEqual(
            StylistChatPresentation.displayText("87/100 — Excellent. Cream is the best match."),
            "87/100 — Excellent. Cream is the best match."
        )
    }
}
