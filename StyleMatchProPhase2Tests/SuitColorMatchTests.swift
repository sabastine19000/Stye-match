import XCTest
@testable import StyleMatchPro

final class SuitColorMatchTests: XCTestCase {
    func testEverySuitAndOccasionHasThreeCompleteStableLooks() throws {
        for suit in SuitColor.allCases {
            for occasion in SuitOccasion.allCases {
                let looks = SuitMatchEngine.looks(suit: suit, occasion: occasion)
                XCTAssertEqual(looks.map(\.style), ["Classic", "Modern", "Bold"])
                XCTAssertEqual(Set(looks.map(\.id)).count, 3)
                XCTAssertEqual(looks, SuitMatchEngine.looks(suit: suit, occasion: occasion))
                for look in looks {
                    XCTAssertEqual(look.shoes, look.belt)
                    XCTAssertFalse(look.explanation.isEmpty)
                    XCTAssertEqual(try JSONDecoder().decode(SuitMatchLook.self,
                        from: JSONEncoder().encode(look)), look)
                }
            }
        }
    }

    func testInterviewDoesNotIntroduceLoudShirtsAndDateCanSkipTie() {
        for suit in SuitColor.allCases {
            XCTAssertTrue(SuitMatchEngine.looks(suit: suit, occasion: .interview).allSatisfy { $0.shirt == "White" })
            XCTAssertTrue(SuitMatchEngine.looks(suit: suit, occasion: .date)[1].tie.hasPrefix("Optional:"))
        }
    }

    func testClosetRequiresMatchingCategoryAndExactColor() {
        let look = SuitMatchEngine.looks(suit: .navy, occasion: .work)[0]
        func item(_ category: String, _ color: String) -> ClosetItem {
            ClosetItem(name: "Test", category: category, color: color, brand: "", size: "", occasion: "", notes: "")
        }
        let shirt = item("Shirt", " WHITE ")
        let shoes = item("Shoes", "Dark brown")
        let matches = SuitMatchEngine.closetMatches(for: look, items: [
            shirt, shoes, item("Dress", "White"), item("Shirt", "Off-white"), item("Tie", "")
        ])
        XCTAssertEqual(matches.map(\.id), [shirt.id, shoes.id])
    }

    func testSavedLooksFollowAccountSwitchAndDeletion() throws {
        let suite = "SuitColorMatchTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("guest", forKey: AccountScopedStorage.activeUserMarkerKey)
        let data = try JSONEncoder().encode(SuitMatchEngine.looks(suit: .navy, occasion: .work))
        defaults.set(data, forKey: "suitMatchSavedLooksData")
        AccountScopedStorage.switchUser(from: "guest", to: "alice", transferSourceData: false, defaults: defaults)
        XCTAssertNil(defaults.data(forKey: "suitMatchSavedLooksData"))
        AccountScopedStorage.switchUser(from: "alice", to: "guest", transferSourceData: false, defaults: defaults)
        XCTAssertEqual(defaults.data(forKey: "suitMatchSavedLooksData"), data)
        AccountScopedStorage.deleteUserData(for: "guest", defaults: defaults)
        XCTAssertNil(defaults.data(forKey: "suitMatchSavedLooksData"))
    }
}
