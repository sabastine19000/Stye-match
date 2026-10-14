import XCTest
@testable import StyleMatchPro

final class StyleExperienceTests: XCTestCase {
    private func piece(_ name: String, _ category: String, color: String = "Navy") -> ClosetItem {
        ClosetItem(name: name, category: category, color: color, brand: "", size: "Private size", occasion: "", notes: "Private notes")
    }
    private func recommendation(_ items: [ClosetItem], work: String = "") -> DailyStyleRecommendation? {
        DailyStyleRecommendationEngine.recommend(items: items, temperatureFahrenheit: nil, condition: nil, occasion: "", dressCode: "", workSetting: work)
    }
    func testAlternativesAreDistinctCompleteAndOwned() throws {
        let items = [piece("Polo", "Shirt"), piece("Tee", "Shirt"), piece("Chinos", "Pants"), piece("Jeans", "Pants"), piece("Sneakers", "Shoes")]
        let primary = try XCTUnwrap(recommendation(items))
        let alternatives = StyleExperienceAuthority.alternatives(items: items, primary: primary, temperature: nil, condition: nil, occasion: "", dressCode: "", workSetting: "")
        XCTAssertFalse(alternatives.isEmpty)
        XCTAssertEqual(Set(alternatives.map { Set($0.itemIDs) }).count, alternatives.count)
        for alternative in alternatives {
            XCTAssertNotEqual(Set(primary.itemIDs), Set(alternative.itemIDs))
            XCTAssertTrue(Set(alternative.itemIDs).isSubset(of: Set(items.map(\.id))))
            XCTAssertNotNil(recommendation(items.filter { alternative.itemIDs.contains($0.id) }))
        }
    }
    func testNoFabricatedAlternativeForOnlyOneOutfit() throws {
        let items = [piece("Polo", "Shirt"), piece("Chinos", "Pants"), piece("Sneakers", "Shoes")]
        XCTAssertTrue(StyleExperienceAuthority.alternatives(items: items, primary: try XCTUnwrap(recommendation(items)), temperature: nil, condition: nil, occasion: "", dressCode: "", workSetting: "").isEmpty)
    }
    func testAlternativesRetainRequiredSafetyFootwear() throws {
        let boot = piece("Steel toe boots", "Shoes")
        let items = [piece("Polo", "Shirt"), piece("Tee", "Shirt"), piece("Chinos", "Pants"), piece("Sneakers", "Shoes"), boot]
        let options = StyleExperienceAuthority.alternatives(items: items, primary: try XCTUnwrap(recommendation(items, work: "factory")), temperature: nil, condition: nil, occasion: "", dressCode: "", workSetting: "factory")
        for option in options { XCTAssertTrue(option.itemIDs.contains(boot.id)) }
    }
    func testWearPreservesOtherRecordsAndRejectsDeletedItem() throws {
        let item = piece("Polo", "Shirt"), other = UUID()
        let before = Date(timeIntervalSince1970: 10), now = Date(timeIntervalSince1970: 20)
        let data = try JSONEncoder().encode([other.uuidString: before])
        let after = try StyleExperienceAuthority.wearHistory(existing: data, itemIDs: [item.id], currentItems: [item], now: now)
        let history = try JSONDecoder().decode([String: Date].self, from: after)
        XCTAssertEqual(history[other.uuidString], before)
        XCTAssertEqual(history[item.id.uuidString], now)
        XCTAssertThrowsError(try StyleExperienceAuthority.wearHistory(existing: data, itemIDs: [UUID()], currentItems: [item], now: now))
    }
    func testMalformedWearHistoryIsNotReplaced() {
        let item = piece("Polo", "Shirt")
        XCTAssertThrowsError(try StyleExperienceAuthority.wearHistory(existing: Data("broken".utf8), itemIDs: [item.id], currentItems: [item], now: Date()))
    }
    func testShareExcludesPrivateFields() {
        let item = piece("Private name", "Shirt")
        let text = StyleExperienceAuthority.shareText(items: [item])
        XCTAssertTrue(text.contains("Navy Shirt"))
        for value in [item.name, item.size, item.notes, item.id.uuidString] { XCTAssertFalse(text.contains(value)) }
    }
    func testPurchaseCheckCanRecommendSkippingAndDoesNotInventGap() {
        let item = piece("Polo", "Shirt")
        XCTAssertTrue(StyleExperienceAuthority.purchaseCheck(category: "shirt", colors: ["navy"], closet: [item]).contains("Consider skipping"))
        XCTAssertTrue(StyleExperienceAuthority.purchaseCheck(category: "Pants", colors: ["Black"], closet: [item]).contains("not proof"))
        XCTAssertTrue(StyleExperienceAuthority.purchaseCheck(category: "Shirt", colors: ["Navy"], closet: []).contains("do not mean"))
    }
    func testResponseStylesPreserveQuestionAndScoreAuthority() {
        for style in StylistResponseStyle.allCases {
            let request = style.request("Help with my outfit 👕")
            XCTAssertTrue(request.hasPrefix("Help with my outfit 👕"))
            XCTAssertTrue(request.contains("Do not invent or change a Style Score"))
            XCTAssertTrue(request.contains("Use only supplied facts"))
        }
    }
    func testWearHistoryParticipatesInAccountIsolation() {
        XCTAssertTrue(AccountScopedStorage.userDataKeys.contains("closetWearHistoryData"))
    }
}
