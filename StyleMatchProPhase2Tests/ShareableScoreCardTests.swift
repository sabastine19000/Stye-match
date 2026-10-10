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
        let canonicalHost = "stylematchpro.com"
        XCTAssertEqual(
            ShareableScoreCardRoute.parse(
                URL(string: "https://stylematchpro.com/share/\(token)")!,
                canonicalShareDomain: canonicalHost
            )?.token,
            token
        )
        XCTAssertNil(ShareableScoreCardRoute.parse(URL(string: "https://share.stylematch.test/share/\(token)")!, canonicalShareDomain: canonicalHost))
        XCTAssertNil(ShareableScoreCardRoute.parse(URL(string: "https://stylematchpro.com.evil.test/share/\(token)")!, canonicalShareDomain: canonicalHost))
        XCTAssertNil(ShareableScoreCardRoute.parse(URL(string: "https://user:password@stylematchpro.com/share/\(token)")!, canonicalShareDomain: canonicalHost))
        XCTAssertNil(ShareableScoreCardRoute.parse(URL(string: "https://stylematchpro.com:8443/share/\(token)")!, canonicalShareDomain: canonicalHost))
        XCTAssertNil(ShareableScoreCardRoute.parse(URL(string: "https://stylematchpro.com/share/\(token)?next=https://evil.test")!, canonicalShareDomain: canonicalHost))
        XCTAssertNil(ShareableScoreCardRoute.parse(URL(string: "https://stylematchpro.com/cards/\(token)")!, canonicalShareDomain: canonicalHost))
        XCTAssertNil(ShareableScoreCardRoute.parse(URL(string: "stylematch://share/\(token)")!, canonicalShareDomain: canonicalHost))
        XCTAssertNil(ShareableScoreCardRoute.parse(URL(string: "https://stylematchpro.com/share/not%20safe")!, canonicalShareDomain: canonicalHost))
    }

    func testLocalStoreTracksCreatedCardsWithoutPersistingRevocationSecrets() throws {
        let suiteName = "ShareableScoreCardTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ShareableScoreCardLocalStore(defaults: defaults, userID: "tester@example.com")

        store.saveCreatedCard(
            token: String(repeating: "B", count: 43),
            url: URL(string: "https://share.stylematch.test/share/\(String(repeating: "B", count: 43))")!,
            expiresAt: "2026-08-12T10:22:21.540Z",
            overallScore: 91
        )

        XCTAssertEqual(store.cards.count, 1)
        XCTAssertEqual(store.cards[0].overallScore, 91)
        let encoded = try JSONEncoder().encode(store.cards[0])
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("creatorManagementToken"))
        store.markRevoked(token: String(repeating: "B", count: 43))
        XCTAssertNotNil(store.cards[0].revokedAt)
    }

    func testExistingLocallyTrackedCardsDecodeAfterRevocationSecretRemoval() throws {
        let token = String(repeating: "C", count: 43)
        let legacyData = Data("""
        {
          "token": "\(token)",
          "url": "https://stylematchpro.com/share/\(token)",
          "creatorManagementToken": "legacy-owner-capability",
          "createdAt": 0,
          "expiresAt": 2592000
        }
        """.utf8)

        let card = try JSONDecoder().decode(CreatedShareableScoreCard.self, from: legacyData)
        XCTAssertEqual(card.token, token)
        XCTAssertEqual(card.url.host, "stylematchpro.com")
        XCTAssertNil(card.overallScore)
    }

    func testRevocationWordingStatesThatOnlyTheSharedRepresentationIsRemoved() throws {
        let source = try projectSource("StyleMatchAI/ShareableScoreCardViews.swift")
        XCTAssertTrue(source.contains("Revoke Share"))
        XCTAssertTrue(source.contains("Your original photo, score, and saved KigoStylist data remain in your account."))
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
        XCTAssertEqual(ShareableScoreCardConfiguration.production.baseURL.absoluteString, "https://api.stylematchpro.com")
        XCTAssertEqual(StylistChatConfiguration.production?.baseURL.absoluteString, "https://api.stylematchpro.com")

        let accountSource = try projectSource("StyleMatchAI/AccountService.swift")
        XCTAssertTrue(accountSource.contains("StyleMatchLiveClientEndpointFactory = .current()"))
        XCTAssertTrue(accountSource.contains("endpointFactory.accountBaseURL"))
        XCTAssertFalse(accountSource.contains("workers.dev"))
    }

    func testBundleConfigurationReadsOnlyPublicEndpointInfoPlistKeys() throws {
        let bundle = try makeConfigurationBundle(info: [
            "STYLEMATCH_API_BASE_URL": "https://api.stylematchpro.com",
            "STYLEMATCH_SHARE_DOMAIN": "stylematchpro.com"
        ])

        let configuration = AppBackendConfiguration.production(bundle: bundle)

        XCTAssertEqual(configuration.apiBaseURL.absoluteString, "https://api.stylematchpro.com")
        XCTAssertEqual(configuration.shareDomain, "stylematchpro.com")
    }

    func testShareCardCreateRequiresAnUnexpiredAccountSessionBeforeNetwork() async throws {
        let session = makeShareCardSession(statusCode: 201)
        let client = ShareableScoreCardClient(
            configuration: ShareableScoreCardConfiguration(baseURL: AppBackendConfiguration.defaultAPIBaseURL),
            session: session,
            accountSession: {
                StyleMatchAccountSession(
                    token: String(repeating: "A", count: 43),
                    expiresAt: .distantPast,
                    appleSubject: "apple-subject-expired",
                    endpointHost: "api.stylematchpro.com"
                )
            }
        )

        do {
            _ = try await client.create(minimalSharePayload())
            XCTFail("Expected an expired account session to fail closed before networking.")
        } catch let error as ShareableScoreCardError {
            XCTAssertEqual(error, .unauthorized)
        }

        XCTAssertNil(ShareCardConfigURLProtocol.lastRequest)
    }

    func testShareCardCreateUsesApiBaseAndAuthenticatedAccountSessionWithoutAppSecret() async throws {
        let session = makeShareCardSession(
            statusCode: 201,
            responseData: Data("""
            {
              "token": "\(String(repeating: "A", count: 43))",
              "url": "https://stylematchpro.com/share/\(String(repeating: "A", count: 43))",
              "expires_at": "2026-08-12T10:22:21.540Z"
            }
            """.utf8)
        )
        let client = ShareableScoreCardClient(
            configuration: ShareableScoreCardConfiguration(baseURL: AppBackendConfiguration.defaultAPIBaseURL),
            session: session,
            accountSession: {
                StyleMatchAccountSession(
                    token: String(repeating: "S", count: 43),
                    expiresAt: .distantFuture,
                    appleSubject: "apple-subject-current",
                    endpointHost: "api.stylematchpro.com"
                )
            }
        )

        _ = try await client.create(minimalSharePayload())

        let request = try XCTUnwrap(ShareCardConfigURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.scheme, "https")
        XCTAssertEqual(request.url?.host, "api.stylematchpro.com")
        XCTAssertEqual(request.url?.path, "/v1/cards")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(String(repeating: "S", count: 43))")
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Device-Hash"))
        XCTAssertNil(request.value(forHTTPHeaderField: "X-App-Auth"))
    }

    func testShareCardCreateRejectsSessionFromAnotherEnvironmentBeforeNetwork() async throws {
        let session = makeShareCardSession(statusCode: 201)
        let client = ShareableScoreCardClient(
            configuration: ShareableScoreCardConfiguration(baseURL: AppBackendConfiguration.defaultAPIBaseURL),
            session: session,
            accountSession: {
                StyleMatchAccountSession(
                    token: String(repeating: "S", count: 43),
                    expiresAt: .distantFuture,
                    appleSubject: "apple-subject-staging",
                    endpointHost: "stylematch-friends-staging.sabastine-7000.workers.dev"
                )
            }
        )

        do {
            _ = try await client.create(minimalSharePayload())
            XCTFail("A backend session from another environment must not be sent to the link endpoint.")
        } catch let error as ShareableScoreCardError {
            XCTAssertEqual(error, .unauthorized)
        }

        XCTAssertNil(ShareCardConfigURLProtocol.lastRequest)
    }

    func testShareCardCreateUsesMatchingOwnerBetaSessionAndEndpoint() async throws {
        let ownerBetaHost = "stylematch-friends-staging.sabastine-7000.workers.dev"
        let session = makeShareCardSession(
            statusCode: 201,
            responseData: Data("""
            {
              "token": "\(String(repeating: "B", count: 43))",
              "url": "https://stylematchpro.com/share/\(String(repeating: "B", count: 43))",
              "expires_at": "2026-08-12T10:22:21.540Z"
            }
            """.utf8)
        )
        let client = ShareableScoreCardClient(
            configuration: ShareableScoreCardConfiguration(baseURL: try XCTUnwrap(URL(string: "https://\(ownerBetaHost)"))),
            session: session,
            accountSession: {
                StyleMatchAccountSession(
                    token: String(repeating: "S", count: 43),
                    expiresAt: .distantFuture,
                    appleSubject: "apple-subject-owner-beta",
                    endpointHost: ownerBetaHost
                )
            }
        )

        _ = try await client.create(minimalSharePayload())

        let request = try XCTUnwrap(ShareCardConfigURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.host, ownerBetaHost)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(String(repeating: "S", count: 43))")
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

    func testShareableScoreCardUsesOnlyTheExistingAccountSessionAuthority() throws {
        let source = try source("ShareableScoreCard.swift")

        XCTAssertTrue(source.contains("StyleMatchAccountSessionStore.load"))
        XCTAssertTrue(source.contains("requiresAccountSession"))
        XCTAssertFalse(source.contains("cardAppSharedSecret"))
        XCTAssertFalse(source.contains("X-App-Auth"))
        XCTAssertFalse(source.contains("X-Device-Hash"))
    }

    func testInfoPlistAndAssociatedDomainBuildSettingsAreConfigured() throws {
        let project = try projectSource("StyleMatchAI.xcodeproj/project.pbxproj")
        let plist = try projectSource("StyleMatchAI/Info.plist")
        let sharedConfig = try projectSource("Config/StyleMatchShared.xcconfig")
        let entitlements = try projectSource("StyleMatchAI/StyleMatchAI.entitlements")

        XCTAssertTrue(sharedConfig.contains("STYLEMATCH_API_BASE_URL = https:/$()/api.stylematchpro.com"))
        XCTAssertTrue(sharedConfig.contains("STYLEMATCH_SHARE_DOMAIN = stylematchpro.com"))
        XCTAssertFalse(sharedConfig.contains("STYLEMATCH_CARD_APP_SHARED_SECRET"))
        XCTAssertFalse(sharedConfig.contains("STYLIST_CHAT_APP_SHARED_SECRET"))
        XCTAssertTrue(sharedConfig.contains("#include? \"../Secrets.xcconfig\""))
        XCTAssertTrue(project.contains("INFOPLIST_KEY_STYLEMATCH_API_BASE_URL = \"$(STYLEMATCH_API_BASE_URL)\";"))
        XCTAssertTrue(project.contains("INFOPLIST_KEY_STYLEMATCH_SHARE_DOMAIN = \"$(STYLEMATCH_SHARE_DOMAIN)\";"))
        XCTAssertFalse(project.contains("STYLEMATCH_CARD_APP_SHARED_SECRET"))
        XCTAssertFalse(project.contains("STYLIST_CHAT_APP_SHARED_SECRET"))
        XCTAssertTrue(plist.contains("<key>STYLEMATCH_API_BASE_URL</key>"))
        XCTAssertTrue(plist.contains("<string>$(STYLEMATCH_API_BASE_URL)</string>"))
        XCTAssertTrue(plist.contains("<key>STYLEMATCH_SHARE_DOMAIN</key>"))
        XCTAssertTrue(plist.contains("<string>$(STYLEMATCH_SHARE_DOMAIN)</string>"))
        XCTAssertFalse(plist.contains("STYLEMATCH_CARD_APP_SHARED_SECRET"))
        XCTAssertFalse(plist.contains("STYLIST_CHAT_APP_SHARED_SECRET"))
        XCTAssertTrue(plist.contains("<key>ITSAppUsesNonExemptEncryption</key>\n\t<false/>"), "Release plist must declare no non-exempt encryption for Apple export compliance.")
        XCTAssertTrue(plist.contains("<key>NSLocationWhenInUseUsageDescription</key>"))
        XCTAssertTrue(plist.contains("uses your location only when you request local weather guidance"))
        XCTAssertTrue(plist.contains("<key>NSCalendarsUsageDescription</key>"))
        XCTAssertTrue(plist.contains("KigoStylist uses selected upcoming calendar context on this device to improve outfit recommendations when you enable Calendar Context."))
        XCTAssertFalse(plist.contains("calendar access is used to create"))
        XCTAssertTrue(project.contains("StyleMatchDebug.xcconfig"))
        XCTAssertTrue(project.contains("StyleMatchRelease.xcconfig"))
        XCTAssertTrue(entitlements.contains("applinks:$(STYLEMATCH_SHARE_DOMAIN)"))
        XCTAssertFalse(entitlements.contains("api.stylematchpro.com"))
    }

    func testExportComplianceDeclaresOnlyExemptEncryption() throws {
        let plist = try projectSource("StyleMatchAI/Info.plist")
        let sources = [
            try projectSource("StyleMatchAI/AccountService.swift"),
            try projectSource("StyleMatchAI/StyleFriendsDMOperationJournal.swift"),
            try projectSource("StyleMatchAI/CrossDeviceSync/SyncMutationV2Authority.swift")
        ].joined(separator: "\n")

        XCTAssertTrue(plist.contains("<key>ITSAppUsesNonExemptEncryption</key>"))
        XCTAssertTrue(plist.contains("<false/>"))
        XCTAssertTrue(sources.contains("CryptoKit"))
        XCTAssertTrue(sources.contains("SHA256"))
        XCTAssertTrue(sources.contains("HMAC"))
        for forbidden in ["AES.GCM", "ChaChaPoly", "Curve25519", "CCCrypt", "CryptoSwift"] {
            XCTAssertFalse(sources.contains(forbidden), "Unexpected non-audited encryption implementation: \(forbidden)")
        }
    }

    func testPrivacyManifestMatchesCoarseWeatherLocationDisclosure() throws {
        let manifest = try projectSource("StyleMatchAI/PrivacyInfo.xcprivacy")
        let weather = try projectSource("StyleMatchAI/WeatherKitAuthority.swift")

        XCTAssertTrue(manifest.contains("NSPrivacyCollectedDataTypeCoarseLocation"))
        XCTAssertFalse(manifest.contains("NSPrivacyCollectedDataTypePreciseLocation"))
        XCTAssertTrue(weather.contains("locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers"))
        XCTAssertTrue(weather.contains("service.weather(for: location)"))
        XCTAssertFalse(weather.contains("location.coordinate"))
        XCTAssertFalse(weather.contains("latitude"))
        XCTAssertFalse(weather.contains("longitude"))
    }

    func testStyleMatchTargetBuildIdentityIsBuild18055AcrossAppConfigurations() throws {
        let project = try projectSource("StyleMatchAI.xcodeproj/project.pbxproj")

        XCTAssertEqual(project.components(separatedBy: "CURRENT_PROJECT_VERSION = 18039;").count - 1, 0)
        XCTAssertEqual(project.components(separatedBy: "CURRENT_PROJECT_VERSION = 18046;").count - 1, 0)
        XCTAssertEqual(project.components(separatedBy: "CURRENT_PROJECT_VERSION = 18048;").count - 1, 0)
        XCTAssertEqual(project.components(separatedBy: "CURRENT_PROJECT_VERSION = 18049;").count - 1, 0)
        XCTAssertEqual(project.components(separatedBy: "CURRENT_PROJECT_VERSION = 18055;").count - 1, 3)
        XCTAssertEqual(project.components(separatedBy: "MARKETING_VERSION = 1.8.2;").count - 1, 3)
        XCTAssertEqual(project.components(separatedBy: "PRODUCT_BUNDLE_IDENTIFIER = com.sabastine.stylematchai;").count - 1, 3)
        XCTAssertFalse(project.contains("CURRENT_PROJECT_VERSION = 18033;"))
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
