import XCTest
@testable import StyleMatchPro

final class ShareableScoreCardTests: XCTestCase {
    override func tearDown() {
        ShareCardConfigURLProtocol.reset()
        super.tearDown()
    }

    func testPayloadContainsOnlyEnabledSections() throws {
        let payload = ShareableScoreCardCreatePayload(
            enabledSections: ShareableScoreCardEnabledSections(
                photo: false,
                overallScore: true,
                categoryScores: false,
                notes: true,
                recommendations: false,
                scanDate: true
            ),
            overallScore: 91,
            scoreTitle: "Excellent",
            categoryScores: [ShareableScoreCardCategoryScore(title: "Fit", value: "24/25")],
            outfitDescription: "Navy blazer with white sneakers.",
            recommendations: ["Add a watch."],
            scanDate: Date(timeIntervalSince1970: 1_789_200_000),
            photo: ShareableScoreCardPhoto(mimeType: "image/jpeg", base64: "abc")
        )

        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any]
        XCTAssertEqual(object?["overallScore"] as? Int, 91)
        XCTAssertEqual(object?["outfitDescription"] as? String, "Navy blazer with white sneakers.")
        XCTAssertNotNil(object?["scanDate"])
        XCTAssertNil(object?["categoryScores"])
        XCTAssertNil(object?["recommendations"])
        XCTAssertNil(object?["photo"])
    }

    func testPhotoExcludedWhenToggleOff() throws {
        let payload = ShareableScoreCardCreatePayload(
            enabledSections: ShareableScoreCardEnabledSections(
                photo: false,
                overallScore: true,
                categoryScores: true,
                notes: true,
                recommendations: true,
                scanDate: true
            ),
            overallScore: 88,
            scoreTitle: "Strong",
            categoryScores: [],
            outfitDescription: "Score-only share.",
            recommendations: [],
            scanDate: Date(),
            photo: ShareableScoreCardPhoto(mimeType: "image/jpeg", base64: "private-photo")
        )

        let json = String(data: try JSONEncoder().encode(payload), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("private-photo"))
        XCTAssertFalse(json.contains("\"mimeType\""))
        XCTAssertFalse(json.contains("\"base64\""))
    }

    func testDeepLinkRoutingParsesShareTokensOnly() throws {
        let token = String(repeating: "A", count: 43)
        XCTAssertEqual(
            ShareableScoreCardRoute.parse(URL(string: "https://share.stylematch.test/share/\(token)")!)?.token,
            token
        )
        XCTAssertNil(ShareableScoreCardRoute.parse(URL(string: "https://share.stylematch.test/cards/\(token)")!))
        XCTAssertNil(ShareableScoreCardRoute.parse(URL(string: "stylematch://share/\(token)")!))
        XCTAssertNil(ShareableScoreCardRoute.parse(URL(string: "https://share.stylematch.test/share/not%20safe")!))
    }

    func testLocalStorePersistsCreatorManagementTokenOnlyForSenderManagement() throws {
        let suiteName = "ShareableScoreCardTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ShareableScoreCardLocalStore(defaults: defaults, userID: "tester@example.com")

        store.saveCreatedCard(
            token: String(repeating: "B", count: 43),
            url: URL(string: "https://share.stylematch.test/share/\(String(repeating: "B", count: 43))")!,
            managementToken: String(repeating: "C", count: 43),
            expiresAt: "2026-08-12T10:22:21.540Z"
        )

        XCTAssertEqual(store.cards.count, 1)
        XCTAssertEqual(store.cards[0].creatorManagementToken, String(repeating: "C", count: 43))
        store.markRevoked(token: String(repeating: "B", count: 43))
        XCTAssertNotNil(store.cards[0].revokedAt)
    }

    func testShareableCardPathsDoNotCallScoringAIOrOutfitMemoryWrites() throws {
        let shareSource = try source("ShareableScoreCard.swift")
        let viewSource = try source("ShareableScoreCardViews.swift")
        let combined = shareSource + viewSource

        XCTAssertFalse(combined.contains("calculateStyleScore("))
        XCTAssertFalse(combined.contains("OpenAIStylistClient"))
        XCTAssertFalse(combined.contains("PersonalizationContextBuilder"))
        XCTAssertFalse(combined.contains("OutfitMemoryStore("))
        XCTAssertFalse(combined.contains(".recordWornAnswer"))
        XCTAssertFalse(combined.contains(".recordLikedAnswer"))
    }

    func testProductionBackendDefaultsUseApiAndShareDomains() throws {
        XCTAssertEqual(AppBackendConfiguration.defaultAPIBaseURL.absoluteString, "https://api.stylematchpro.com")
        XCTAssertEqual(AppBackendConfiguration.defaultShareDomain, "stylematchpro.com")
        XCTAssertEqual(ShareableScoreCardConfiguration.production?.baseURL.absoluteString, "https://api.stylematchpro.com")
        XCTAssertEqual(StylistChatConfiguration.production?.baseURL.absoluteString, "https://api.stylematchpro.com")

        let accountSource = try projectSource("StyleMatchAI/AccountService.swift")
        XCTAssertTrue(accountSource.contains("AppBackendConfiguration.production().apiBaseURL"))
        XCTAssertFalse(accountSource.contains("workers.dev"))
    }

    func testBundleConfigurationReadsInjectedInfoPlistKeys() throws {
        let legacySecret = "valid-legacy-secret-\(UUID().uuidString)"
        let cardSecret = "valid-card-secret-\(UUID().uuidString)"
        let bundle = try makeConfigurationBundle(info: [
            "STYLEMATCH_API_BASE_URL": "https://api.stylematchpro.com",
            "STYLEMATCH_SHARE_DOMAIN": "stylematchpro.com",
            "STYLIST_CHAT_APP_SHARED_SECRET": legacySecret,
            "STYLEMATCH_CARD_APP_SHARED_SECRET": cardSecret
        ])

        let configuration = AppBackendConfiguration.production(bundle: bundle)

        XCTAssertEqual(configuration.apiBaseURL.absoluteString, "https://api.stylematchpro.com")
        XCTAssertEqual(configuration.shareDomain, "stylematchpro.com")
        XCTAssertEqual(configuration.appSharedSecret, legacySecret)
        XCTAssertEqual(configuration.cardAppSharedSecret, cardSecret)
    }

    func testSecretCleaningFailsClosedForMissingBlankAndPlaceholderValues() {
        XCTAssertNil(AppBackendConfiguration.cleanSecret(nil))
        XCTAssertNil(AppBackendConfiguration.cleanSecret(""))
        XCTAssertNil(AppBackendConfiguration.cleanSecret("   "))
        XCTAssertNil(AppBackendConfiguration.cleanSecret("REPLACE_WITH_WORKER_APP_SHARED_SECRET"))
        XCTAssertNil(AppBackendConfiguration.cleanSecret("placeholder-secret"))
        XCTAssertNil(AppBackendConfiguration.cleanSecret("pending-secret"))
        XCTAssertNil(AppBackendConfiguration.cleanSecret("changeme"))
    }

    func testValidInjectedSecretIsAcceptedWithoutChangingIt() {
        let secret = "valid-local-secret-\(UUID().uuidString)"
        XCTAssertEqual(AppBackendConfiguration.cleanSecret(secret), secret)
    }

    func testMissingOrPlaceholderShareCardSecretFailsBeforeNetwork() async throws {
        let session = makeShareCardSession(statusCode: 201)
        let client = ShareableScoreCardClient(
            configuration: ShareableScoreCardConfiguration(
                baseURL: AppBackendConfiguration.defaultAPIBaseURL,
                cardAppSharedSecret: "REPLACE_WITH_CARD_APP_SHARED_SECRET"
            ),
            session: session
        )

        do {
            _ = try await client.create(minimalSharePayload())
            XCTFail("Expected placeholder secret to fail closed before networking.")
        } catch let error as ShareableScoreCardError {
            XCTAssertEqual(error, .configurationUnavailable)
        }

        XCTAssertNil(ShareCardConfigURLProtocol.lastRequest)
    }

    func testShareCardCreateUsesApiBaseAndPreservesDeviceAuthHeaders() async throws {
        let session = makeShareCardSession(
            statusCode: 201,
            responseData: Data("""
            {
              "token": "\(String(repeating: "A", count: 43))",
              "url": "https://stylematchpro.com/share/\(String(repeating: "A", count: 43))",
              "creator_management_token": "\(String(repeating: "B", count: 43))",
              "expires_at": "2026-08-12T10:22:21.540Z"
            }
            """.utf8)
        )
        let suiteName = "ShareableScoreCardAuth.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let secret = "valid-local-secret-\(UUID().uuidString)"
        let client = ShareableScoreCardClient(
            configuration: ShareableScoreCardConfiguration(
                baseURL: AppBackendConfiguration.defaultAPIBaseURL,
                cardAppSharedSecret: secret
            ),
            session: session,
            defaults: defaults
        )

        _ = try await client.create(minimalSharePayload())

        let request = try XCTUnwrap(ShareCardConfigURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.scheme, "https")
        XCTAssertEqual(request.url?.host, "api.stylematchpro.com")
        XCTAssertEqual(request.url?.path, "/v1/cards")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let deviceHash = try XCTUnwrap(request.value(forHTTPHeaderField: "X-Device-Hash"))
        let signature = try XCTUnwrap(request.value(forHTTPHeaderField: "X-App-Auth"))
        XCTAssertEqual(deviceHash.count, 64)
        XCTAssertEqual(signature.count, 64)
        XCTAssertNotEqual(signature, secret)
    }

    func testTrackedProductionSourcesDoNotUseWorkersDevForLiveConfigs() throws {
        let liveConfigPaths = [
            "StyleMatchAI/ShareableScoreCard.swift",
            "StyleMatchAI/StylistChat/StylistChatTransport.swift",
            "StyleMatchAI/AccountService.swift",
            "StyleMatchAI/Shopping/ShoppingRuntimeConfig.json"
        ]

        for path in liveConfigPaths {
            XCTAssertFalse(try projectSource(path).contains("workers.dev"), path)
        }
    }

    func testShareableScoreCardUsesCardSpecificSecretOnly() throws {
        let source = try source("ShareableScoreCard.swift")

        XCTAssertTrue(source.contains("cardAppSharedSecret"))
        XCTAssertFalse(source.contains("STYLIST_CHAT_APP_SHARED_SECRET"))
        XCTAssertFalse(source.contains("appSharedSecret: backend.appSharedSecret"))
    }

    func testInfoPlistAndAssociatedDomainBuildSettingsAreConfigured() throws {
        let project = try projectSource("StyleMatchAI.xcodeproj/project.pbxproj")
        let plist = try projectSource("StyleMatchAI/Info.plist")
        let sharedConfig = try projectSource("Config/StyleMatchShared.xcconfig")
        let entitlements = try projectSource("StyleMatchAI/StyleMatchAI.entitlements")

        XCTAssertTrue(sharedConfig.contains("STYLEMATCH_API_BASE_URL = https:/$()/api.stylematchpro.com"))
        XCTAssertTrue(sharedConfig.contains("STYLEMATCH_SHARE_DOMAIN = stylematchpro.com"))
        XCTAssertTrue(sharedConfig.contains("STYLEMATCH_CARD_APP_SHARED_SECRET = REPLACE_WITH_LOCAL_SECRET"))
        XCTAssertTrue(sharedConfig.contains("STYLIST_CHAT_APP_SHARED_SECRET = REPLACE_WITH_LOCAL_SECRET"))
        XCTAssertTrue(project.contains("INFOPLIST_KEY_STYLEMATCH_API_BASE_URL = \"$(STYLEMATCH_API_BASE_URL)\";"))
        XCTAssertTrue(project.contains("INFOPLIST_KEY_STYLEMATCH_SHARE_DOMAIN = \"$(STYLEMATCH_SHARE_DOMAIN)\";"))
        XCTAssertTrue(project.contains("INFOPLIST_KEY_STYLEMATCH_CARD_APP_SHARED_SECRET = \"$(STYLEMATCH_CARD_APP_SHARED_SECRET)\";"))
        XCTAssertTrue(project.contains("INFOPLIST_KEY_STYLIST_CHAT_APP_SHARED_SECRET = \"$(STYLIST_CHAT_APP_SHARED_SECRET)\";"))
        XCTAssertTrue(plist.contains("<key>STYLEMATCH_API_BASE_URL</key>"))
        XCTAssertTrue(plist.contains("<string>$(STYLEMATCH_API_BASE_URL)</string>"))
        XCTAssertTrue(plist.contains("<key>STYLEMATCH_SHARE_DOMAIN</key>"))
        XCTAssertTrue(plist.contains("<string>$(STYLEMATCH_SHARE_DOMAIN)</string>"))
        XCTAssertTrue(plist.contains("<key>STYLEMATCH_CARD_APP_SHARED_SECRET</key>"))
        XCTAssertTrue(plist.contains("<string>$(STYLEMATCH_CARD_APP_SHARED_SECRET)</string>"))
        XCTAssertTrue(plist.contains("<key>STYLIST_CHAT_APP_SHARED_SECRET</key>"))
        XCTAssertTrue(plist.contains("<string>$(STYLIST_CHAT_APP_SHARED_SECRET)</string>"))
        XCTAssertTrue(project.contains("StyleMatchDebug.xcconfig"))
        XCTAssertTrue(project.contains("StyleMatchRelease.xcconfig"))
        XCTAssertTrue(entitlements.contains("applinks:$(STYLEMATCH_SHARE_DOMAIN)"))
        XCTAssertFalse(entitlements.contains("api.stylematchpro.com"))
    }

    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("StyleMatchAI")
        return try String(contentsOf: root.appendingPathComponent(relativePath))
    }

    private func projectSource(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath))
    }

    private func makeConfigurationBundle(info: [String: String]) throws -> Bundle {
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("StyleMatchConfig.\(UUID().uuidString)")
            .appendingPathExtension("bundle")
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        let plistURL = bundleURL.appendingPathComponent("Info.plist")
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: plistURL, options: .atomic)
        return try XCTUnwrap(Bundle(url: bundleURL))
    }

    private func minimalSharePayload() -> ShareableScoreCardCreatePayload {
        ShareableScoreCardCreatePayload(
            enabledSections: ShareableScoreCardEnabledSections(
                photo: false,
                overallScore: true,
                categoryScores: false,
                notes: false,
                recommendations: false,
                scanDate: true
            ),
            overallScore: 90,
            scoreTitle: "Strong",
            categoryScores: [],
            outfitDescription: "",
            recommendations: [],
            scanDate: Date(timeIntervalSince1970: 1_789_200_000),
            photo: nil
        )
    }

    private func makeShareCardSession(statusCode: Int, responseData: Data = Data("{}".utf8)) -> URLSession {
        ShareCardConfigURLProtocol.reset()
        ShareCardConfigURLProtocol.statusCode = statusCode
        ShareCardConfigURLProtocol.responseData = responseData
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ShareCardConfigURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class ShareCardConfigURLProtocol: URLProtocol {
    static var lastRequest: URLRequest?
    static var statusCode = 200
    static var responseData = Data()

    static func reset() {
        lastRequest = nil
        statusCode = 200
        responseData = Data()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
