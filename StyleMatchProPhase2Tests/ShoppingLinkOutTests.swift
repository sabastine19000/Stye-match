import XCTest
@testable import StyleMatchPro

final class ShoppingLinkOutTests: XCTestCase {
    private let productionBaseURL = URL(string: "https://api.stylematchpro.com")!
    private let stagingBaseURL = URL(string: "https://stylematch-affiliate-proxy-staging.sabastine-7000.workers.dev")!

    func testRenamedDisplayTextDoesNotChangeRetailerIdentity() {
        let product = makeProduct(
            retailerID: "macys",
            retailerName: "Macy's Flagship",
            candidateURL: URL(string: "https://api.stylematchpro.com/go/stable-product")!
        )
        let store = SupportedStore(
            id: "macys",
            name: "Macy's",
            domains: ["macys.com"],
            categories: [.clothing],
            affiliateNetwork: "Impact",
            apiStatus: "approved",
            isEnabled: true
        )

        let result = RetailerPreferencePolicy.apply(
            products: [product],
            preferredRetailerIDs: ["macys"],
            supportedStores: [store]
        )

        XCTAssertEqual(result.products.map(\.id), ["stable-product"])
        XCTAssertFalse(result.usedFallback)
    }

    func testExactProductionAndConfiguredStagingHostsAreAccepted() throws {
        XCTAssertEqual(
            try accepted("https://api.stylematchpro.com/go/stable-product", baseURL: productionBaseURL).host,
            "api.stylematchpro.com"
        )
        XCTAssertEqual(
            try accepted("https://stylematch-affiliate-proxy-staging.sabastine-7000.workers.dev/go/stable-product", baseURL: stagingBaseURL).host,
            "stylematch-affiliate-proxy-staging.sabastine-7000.workers.dev"
        )
        XCTAssertEqual(
            failure("https://stylematch-affiliate-proxy-staging.sabastine-7000.workers.dev/go/stable-product", baseURL: productionBaseURL),
            .unapprovedHost
        )
    }

    func testUnapprovedSchemesAndDirectRetailerHostsAreRejected() {
        XCTAssertEqual(failure("http://api.stylematchpro.com/go/stable-product"), .unapprovedScheme)
        XCTAssertEqual(failure("https://www.amazon.com/dp/example"), .unapprovedHost)
        XCTAssertEqual(failure("https://www.macys.com/shop/example"), .unapprovedHost)
    }

    func testLookalikeSuffixAndSubdomainHostsAreRejected() {
        XCTAssertEqual(failure("https://api.stylematchpro.com.evil.example/go/stable-product"), .unapprovedHost)
        XCTAssertEqual(failure("https://evilapi.stylematchpro.com/go/stable-product"), .unapprovedHost)
        XCTAssertEqual(failure("https://preview.api.stylematchpro.com/go/stable-product"), .unapprovedHost)
    }

    func testUserInformationAndUnapprovedPortAreRejected() {
        XCTAssertEqual(failure("https://user:password@api.stylematchpro.com/go/stable-product"), .unapprovedHost)
        XCTAssertEqual(failure("https://api.stylematchpro.com:8443/go/stable-product"), .unapprovedPort)
        XCTAssertNoThrow(try accepted("https://api.stylematchpro.com:443/go/stable-product"))
    }

    func testApprovedGatewayShapesRequireExactlyMatchingProductID() throws {
        XCTAssertEqual(try accepted("https://api.stylematchpro.com/go/stable-product").pathCategory, .rootGo)
        XCTAssertEqual(try accepted("https://api.stylematchpro.com/v1/go/stable-product").pathCategory, .versionedGo)
        XCTAssertEqual(failure("https://api.stylematchpro.com/go/"), .unapprovedPath)
        XCTAssertEqual(failure("https://api.stylematchpro.com/go/stable-product/extra"), .unapprovedPath)
        XCTAssertEqual(failure("https://api.stylematchpro.com/go/other-product"), .productIDMismatch)
    }

    func testEncodedSlashTraversalFragmentAndQueryAreRejected() {
        XCTAssertEqual(failure("https://api.stylematchpro.com/go/stable%2Fproduct"), .unapprovedPath)
        XCTAssertEqual(failure("https://api.stylematchpro.com/go/%2E%2E"), .unapprovedPath)
        XCTAssertEqual(failure("https://api.stylematchpro.com/go/stable-product#fragment"), .unapprovedPath)
        XCTAssertEqual(failure("https://api.stylematchpro.com/go/stable-product?token=value"), .unapprovedPath)
    }

    func testProductIDAllowlistRejectsUnsafeIDsWithoutRewriting() {
        for productID in ["", ".", "..", "slash/id", "back\\slash", "query?id", "hash#id", "percent%id", "white space", "line\nbreak"] {
            XCTAssertFalse(ShoppingProductGatewayValidator.isValidProductID(productID), "Unexpectedly accepted \(productID.debugDescription)")
        }
        XCTAssertTrue(ShoppingProductGatewayValidator.isValidProductID("AZaz-09_product"))
    }

    func testMalformedCandidateReturnsInvalidURL() {
        XCTAssertEqual(
            validationFailure(candidateURL: nil, productID: "stable-product", baseURL: productionBaseURL),
            .invalidURL
        )
    }

    @MainActor
    func testInvalidURLNeverCallsSystemOpener() async {
        let system = FakeShoppingSystemOpener(canOpen: true, completion: true)
        let product = makeProduct(
            candidateURL: URL(string: "https://www.amazon.com/direct")!,
            fallbackURL: URL(string: "https://www.macys.com/fallback")!
        )
        let result = await ShoppingProductOpener(approvedBaseURL: productionBaseURL, systemOpener: system).open(product)

        XCTAssertEqual(result, .failure(.unapprovedHost))
        XCTAssertEqual(system.canOpenCalls, 0)
        XCTAssertEqual(system.nativeOpenCalls, 0)
        XCTAssertEqual(system.browserPresentationCalls, 0)
    }

    @MainActor
    func testCannotOpenReturnsTypedFailureWithoutOpenRequest() async {
        let system = FakeShoppingSystemOpener(canOpen: false, completion: true)
        let result = await ShoppingProductOpener(approvedBaseURL: productionBaseURL, systemOpener: system).open(makeProduct())

        XCTAssertEqual(result, .failure(.cannotOpen))
        XCTAssertEqual(system.canOpenCalls, 1)
        XCTAssertEqual(system.nativeOpenCalls, 0)
        XCTAssertEqual(system.browserPresentationCalls, 0)
    }

    @MainActor
    func testAcceptedAndDeclinedCompletionResultsAreTyped() async {
        let acceptedSystem = FakeShoppingSystemOpener(canOpen: true, nativeCompletion: true, browserCompletion: false)
        let accepted = await ShoppingProductOpener(approvedBaseURL: productionBaseURL, systemOpener: acceptedSystem).open(makeProduct())
        XCTAssertEqual(accepted, .openAccepted)
        XCTAssertEqual(acceptedSystem.canOpenCalls, 1)
        XCTAssertEqual(acceptedSystem.nativeOpenCalls, 1)
        XCTAssertEqual(acceptedSystem.browserPresentationCalls, 0)

        let declinedSystem = FakeShoppingSystemOpener(canOpen: true, nativeCompletion: false, browserCompletion: false)
        let declined = await ShoppingProductOpener(approvedBaseURL: productionBaseURL, systemOpener: declinedSystem).open(makeProduct())
        XCTAssertEqual(declined, .failure(.openDeclined))
        XCTAssertEqual(declinedSystem.nativeOpenCalls, 1)
        XCTAssertEqual(declinedSystem.browserPresentationCalls, 1)
    }

    @MainActor
    func testDeclinedUniversalLinkPresentsValidatedProductInAppBrowser() async {
        let system = FakeShoppingSystemOpener(canOpen: true, nativeCompletion: false, browserCompletion: true)
        let result = await ShoppingProductOpener(approvedBaseURL: productionBaseURL, systemOpener: system).open(makeProduct())

        XCTAssertEqual(result, .openAccepted)
        XCTAssertEqual(system.nativeOpenCalls, 1)
        XCTAssertEqual(system.browserPresentationCalls, 1)
        XCTAssertEqual(system.presentedURLs, [URL(string: "https://api.stylematchpro.com/go/stable-product")!])
    }

    @MainActor
    func testDiagnosticsContainOnlyCanonicalStructuredFields() async {
        let system = FakeShoppingSystemOpener(canOpen: true, completion: true)
        var diagnostics: [ShoppingProductOpenDiagnostic] = []
        let opener = ShoppingProductOpener(
            approvedBaseURL: productionBaseURL,
            systemOpener: system,
            diagnosticSink: { diagnostics.append($0) }
        )

        _ = await opener.open(makeProduct())

        XCTAssertEqual(diagnostics.first?.event, .interactionReceived)
        XCTAssertEqual(diagnostics.last?.event, .completionReceived)
        XCTAssertEqual(diagnostics.last?.productID, "stable-product")
        XCTAssertEqual(diagnostics.last?.retailerID, "macys")
        XCTAssertEqual(diagnostics.last?.validatedHost, "api.stylematchpro.com")
        XCTAssertEqual(diagnostics.last?.pathCategory, .rootGo)
        XCTAssertEqual(diagnostics.last?.completionAccepted, true)
    }

    func testEveryShoppingProductEntryPointUsesCentralizedOpener() throws {
        let shopping = try source("StyleMatchAI/Shopping/ShoppingView.swift")
        let search = try source("StyleMatchAI/Shopping/StoreSearchView.swift")
        let scan = try source("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(shopping.contains("ShoppingProductOpener.live().open(product, candidateURL: candidateURL)"))
        XCTAssertTrue(search.contains("ShoppingProductOpener.live().open(product)"))
        XCTAssertTrue(scan.contains("ShoppingProductOpener.live().open(product)"))
        XCTAssertFalse(shopping.contains("UIApplication.shared.open(AffiliateLinkBuilder.outboundURL(for: product)"))
        XCTAssertFalse(search.contains("UIApplication.shared.open(AffiliateLinkBuilder.outboundURL(for: product)"))
        XCTAssertFalse(scan.contains("UIApplication.shared.open(AffiliateLinkBuilder.outboundURL(for: product)"))
    }

    func testRetailerDestinationAcceptsOnlyConfiguredHTTPSDomain() throws {
        let store = makeStore(domains: ["macys.com"])
        let result = ShoppingRetailerDestinationValidator.validate(
            candidateURL: URL(string: "https://www.macys.com/shop/featured?query=shirts"),
            retailer: store
        )

        guard case .success(let validated) = result else {
            return XCTFail("Expected the configured retailer domain to pass validation")
        }
        XCTAssertEqual(validated.host, "www.macys.com")
    }

    func testRetailerDestinationRejectsNonAllowlistedAndLookalikeHosts() {
        let store = makeStore(domains: ["macys.com"])

        for rawURL in [
            "https://example.com/shop",
            "https://macys.com.evil.example/shop",
            "https://preview.macys.com/shop"
        ] {
            XCTAssertEqual(
                ShoppingRetailerDestinationValidator.validate(
                    candidateURL: URL(string: rawURL),
                    retailer: store
                ),
                .failure(.unapprovedHost)
            )
        }
    }

    func testRetailerDestinationRejectsHTTP() {
        XCTAssertEqual(
            ShoppingRetailerDestinationValidator.validate(
                candidateURL: URL(string: "http://www.macys.com/shop"),
                retailer: makeStore(domains: ["macys.com"])
            ),
            .failure(.unapprovedScheme)
        )
    }

    @MainActor
    func testRetailerDestinationSurfacesCompletionResult() async {
        let store = makeStore(domains: ["macys.com"])
        let acceptedSystem = FakeShoppingSystemOpener(canOpen: true, nativeCompletion: true, browserCompletion: false)
        let accepted = await ShoppingRetailerDestinationOpener(systemOpener: acceptedSystem).open(
            URL(string: "https://www.macys.com/shop")!,
            retailer: store
        )
        XCTAssertEqual(accepted, .openAccepted)
        XCTAssertEqual(acceptedSystem.canOpenCalls, 1)
        XCTAssertEqual(acceptedSystem.nativeOpenCalls, 1)
        XCTAssertEqual(acceptedSystem.browserPresentationCalls, 0)

        let declinedSystem = FakeShoppingSystemOpener(canOpen: true, nativeCompletion: false, browserCompletion: false)
        var diagnostics: [ShoppingRetailerOpenDiagnostic] = []
        let declined = await ShoppingRetailerDestinationOpener(
            systemOpener: declinedSystem,
            diagnosticSink: { diagnostics.append($0) }
        ).open(URL(string: "https://macys.com/shop")!, retailer: store)

        XCTAssertEqual(declined, .failure(.openDeclined))
        XCTAssertEqual(diagnostics.last?.completionAccepted, false)
        XCTAssertEqual(diagnostics.last?.failure, .openDeclined)
        XCTAssertEqual(diagnostics.last?.retailerID, "macys")
        XCTAssertEqual(diagnostics.last?.validatedHost, "macys.com")
    }

    @MainActor
    func testDeclinedUniversalLinkPresentsValidatedRetailerInAppBrowser() async {
        let store = makeStore(domains: ["macys.com"])
        let destination = URL(string: "https://www.macys.com/shop")!
        let system = FakeShoppingSystemOpener(canOpen: true, nativeCompletion: false, browserCompletion: true)

        let result = await ShoppingRetailerDestinationOpener(systemOpener: system).open(destination, retailer: store)

        XCTAssertEqual(result, .openAccepted)
        XCTAssertEqual(system.nativeOpenCalls, 1)
        XCTAssertEqual(system.browserPresentationCalls, 1)
        XCTAssertEqual(system.presentedURLs, [destination])
    }

    func testShoppingSurfacesContainNoRawUIApplicationOpenCalls() throws {
        for path in [
            "StyleMatchAI/Shopping/AffiliateProduct.swift",
            "StyleMatchAI/Shopping/ShoppingView.swift",
            "StyleMatchAI/Shopping/StoreSearchView.swift",
            "StyleMatchAI/ScanView.swift"
        ] {
            XCTAssertFalse(try source(path).contains("UIApplication.shared.open"), path)
        }
    }

    private func validationFailure(candidateURL: URL?, productID: String, baseURL: URL) -> ShoppingProductOpenFailure? {
        guard case .failure(let failure) = ShoppingProductGatewayValidator.validate(
            candidateURL: candidateURL,
            productID: productID,
            approvedBaseURL: baseURL
        ) else { return nil }
        return failure
    }

    private func failure(
        _ rawURL: String,
        productID: String = "stable-product",
        baseURL: URL? = nil
    ) -> ShoppingProductOpenFailure? {
        validationFailure(
            candidateURL: URL(string: rawURL),
            productID: productID,
            baseURL: baseURL ?? productionBaseURL
        )
    }

    private func accepted(
        _ rawURL: String,
        baseURL: URL? = nil
    ) throws -> ShoppingValidatedGatewayURL {
        let result = ShoppingProductGatewayValidator.validate(
            candidateURL: URL(string: rawURL),
            productID: "stable-product",
            approvedBaseURL: baseURL ?? productionBaseURL
        )
        switch result {
        case .success(let validated): return validated
        case .failure(let failure): throw failure
        }
    }

    private func makeProduct(
        retailerID: String = "macys",
        retailerName: String = "Macy's",
        candidateURL: URL = URL(string: "https://api.stylematchpro.com/go/stable-product")!,
        fallbackURL: URL? = nil
    ) -> AffiliateProduct {
        AffiliateProduct(
            id: "stable-product",
            name: "Stable Product",
            category: .clothing,
            subcategory: "shirt",
            colors: ["white"],
            retailerID: retailerID,
            retailer: Retailer(
                name: retailerName,
                trackingID: AffiliateLinkBuilder.pendingApprovalTrackingID,
                trackingParamName: "stylematch",
                disclosureName: retailerName
            ),
            affiliateURL: candidateURL,
            fallbackURL: fallbackURL,
            price: nil,
            salePrice: nil,
            saleEndsAt: nil,
            availableColors: nil,
            customerRating: nil,
            reviewCount: nil,
            estimatedShippingText: nil,
            tags: [],
            genderPresentation: nil
        )
    }

    private func makeStore(domains: [String]) -> SupportedStore {
        SupportedStore(
            id: "macys",
            name: "Macy's",
            domains: domains,
            categories: [.clothing],
            affiliateNetwork: "Impact",
            apiStatus: "approved",
            isEnabled: true
        )
    }

    private func bundledProducts() throws -> [AffiliateProduct] {
        try BundledCatalogProvider.decodeProducts(
            catalogData: Data(contentsOf: projectURL("StyleMatchAI/Shopping/ProductCatalog.json")),
            retailerConfigData: Data(contentsOf: projectURL("StyleMatchAI/Shopping/RetailerConfig.json"))
        )
    }

    private func supportedStores() throws -> [SupportedStore] {
        try BundledStoreDirectoryProvider.decodeStores(
            Data(contentsOf: projectURL("StyleMatchAI/Shopping/SupportedStores.json"))
        )
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: projectURL(path), encoding: .utf8)
    }

    private func projectURL(_ path: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(path)
    }
}

@MainActor
private final class FakeShoppingSystemOpener: ShoppingSystemOpening {
    let canOpen: Bool
    let nativeCompletion: Bool
    let browserCompletion: Bool
    private(set) var canOpenCalls = 0
    private(set) var nativeOpenCalls = 0
    private(set) var browserPresentationCalls = 0
    private(set) var presentedURLs: [URL] = []

    init(canOpen: Bool, completion: Bool) {
        self.canOpen = canOpen
        self.nativeCompletion = completion
        self.browserCompletion = false
    }

    init(canOpen: Bool, nativeCompletion: Bool, browserCompletion: Bool) {
        self.canOpen = canOpen
        self.nativeCompletion = nativeCompletion
        self.browserCompletion = browserCompletion
    }

    func canOpenURL(_ url: URL) -> Bool {
        canOpenCalls += 1
        return canOpen
    }

    func openUniversalLink(_ url: URL) async -> Bool {
        nativeOpenCalls += 1
        return nativeCompletion
    }

    func presentInAppBrowser(_ url: URL) async -> Bool {
        browserPresentationCalls += 1
        presentedURLs.append(url)
        return browserCompletion
    }
}
