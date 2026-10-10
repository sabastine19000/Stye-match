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

    func testOfficialProductDestinationAcceptsCanonicalRetailerDomainAndSubdomain() throws {
        let product = makeProduct(
            retailerID: "gucci",
            retailerName: "Not Used For Authority",
            candidateURL: URL(string: "https://www.gucci.com/us/en/pr/product")!
        )
        let store = makeStore(id: "gucci", name: "Gucci", domains: ["gucci.com"])

        for rawURL in ["https://gucci.com/us/en/pr/product", "https://www.gucci.com/us/en/pr/product", "https://shop.gucci.com/us/en/pr/product"] {
            let result = ShoppingProductDestinationValidator.validate(
                gatewayCandidateURL: URL(string: rawURL),
                officialProductURL: URL(string: rawURL),
                product: product,
                supportedStores: [store],
                approvedBaseURL: productionBaseURL
            )
            guard case let .success(.officialRetailer(validated)) = result else {
                return XCTFail("Expected canonical official product destination for \(rawURL)")
            }
            XCTAssertEqual(validated.url.absoluteString, rawURL)
        }
    }

    func testOfficialProductDestinationFailsClosedWithoutCanonicalEnabledMatchingRetailer() {
        let product = makeProduct(
            retailerID: "gucci",
            retailerName: "Gucci",
            candidateURL: URL(string: "https://www.gucci.com/us/en/pr/product")!
        )
        let gucci = makeStore(id: "gucci", name: "Gucci", domains: ["gucci.com"])
        let prada = makeStore(id: "prada", name: "Prada", domains: ["prada.com"])
        let directURL = URL(string: "https://www.gucci.com/us/en/pr/product")!

        XCTAssertEqual(
            productDestinationFailure(product: product, gatewayURL: directURL, officialURL: directURL, stores: []),
            .unapprovedHost
        )
        XCTAssertEqual(
            productDestinationFailure(
                product: makeProduct(retailerID: "", candidateURL: directURL),
                gatewayURL: directURL,
                officialURL: directURL,
                stores: [gucci]
            ),
            .unapprovedHost
        )
        XCTAssertEqual(
            productDestinationFailure(product: product, gatewayURL: directURL, officialURL: URL(string: "https://www.prada.com/us/en/pr/product")!, stores: [gucci, prada]),
            .unapprovedHost
        )
        XCTAssertEqual(
            productDestinationFailure(
                product: product,
                gatewayURL: directURL,
                officialURL: URL(string: "https://gucci.com.evil.example/product")!,
                stores: [gucci]
            ),
            .unapprovedHost
        )
        XCTAssertEqual(
            productDestinationFailure(
                product: product,
                gatewayURL: directURL,
                officialURL: URL(string: "https://gucci.com@evil.example/product")!,
                stores: [gucci]
            ),
            .unapprovedHost
        )
        XCTAssertEqual(
            productDestinationFailure(
                product: product,
                gatewayURL: directURL,
                officialURL: URL(string: "http://www.gucci.com/product")!,
                stores: [gucci]
            ),
            .unapprovedScheme
        )
        for rawURL in ["file:///tmp/product", "data:text/plain,product", "javascript:alert(1)"] {
            XCTAssertEqual(
                productDestinationFailure(
                    product: product,
                    gatewayURL: directURL,
                    officialURL: URL(string: rawURL),
                    stores: [gucci]
                ),
                .unapprovedScheme
            )
        }
        XCTAssertEqual(
            productDestinationFailure(
                product: product,
                gatewayURL: directURL,
                officialURL: directURL,
                stores: [makeStore(id: "gucci", name: "Gucci", domains: ["gucci.com"], enabled: false)]
            ),
            .unapprovedHost
        )
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
        let productAuthority = try source("StyleMatchAI/Shopping/AffiliateProduct.swift")

        XCTAssertTrue(shopping.contains("ShoppingProductOpener.live().open("))
        XCTAssertTrue(shopping.contains("supportedStores: supportedStores"))
        XCTAssertTrue(productAuthority.contains("ShoppingProductDestinationValidator.validate("))
        XCTAssertTrue(productAuthority.contains("approvedBaseURL: URL = AppBackendConfiguration.defaultAPIBaseURL"))
        XCTAssertFalse(productAuthority.contains("approvedBaseURL: URL = AppBackendConfiguration.production().apiBaseURL"))
        XCTAssertTrue(search.contains("ShoppingProductOpener.live().open(") && search.contains("supportedStores: retailers"))
        XCTAssertTrue(scan.contains("ShoppingProductOpener.live().open(product)"))
        XCTAssertFalse(shopping.contains("UIApplication.shared.open(AffiliateLinkBuilder.outboundURL(for: product)"))
        XCTAssertFalse(search.contains("UIApplication.shared.open(AffiliateLinkBuilder.outboundURL(for: product)"))
        XCTAssertFalse(scan.contains("UIApplication.shared.open(AffiliateLinkBuilder.outboundURL(for: product)"))
    }

    func testBundledDirectoryUsesStaticTiersWithoutCommercePromotion() throws {
        let stores = try supportedStores()
        let registry = RetailerCatalogRegistry(stores: stores)

        XCTAssertEqual(registry.tier(retailerID: "nordstrom"), .luxuryMultiBrand)
        XCTAssertEqual(registry.tier(retailerID: "nike"), .athleticStreetwear)
        XCTAssertEqual(registry.tier(retailerID: "target"), .everydayValue)
        XCTAssertEqual(registry.commerceDataCapability(retailerID: "nordstrom"), .unavailable)
        XCTAssertEqual(registry.commerceDataCapability(retailerID: "nike"), .unavailable)
        XCTAssertEqual(registry.commerceDataCapability(retailerID: "target"), .unavailable)
    }

    func testBundledDirectoryLuxuryPilotsPreserveExistingRetailerContracts() throws {
        let stores = try supportedStores()
        let registry = RetailerCatalogRegistry(stores: stores)

        XCTAssertEqual(stores.count, 40)
        XCTAssertEqual(Set(stores.map(\.id)).count, stores.count)
        XCTAssertEqual(
            Set(stores.map(\.id)),
            [
                "abercrombie", "adidas", "amazon", "american-eagle", "asos", "best-buy",
                "bergdorf-goodman", "bloomingdales", "burberry", "coach", "dicks", "ebay",
                "etsy", "fashion-nova", "foot-locker", "gap", "gucci", "hm", "jcrew", "kohls",
                "levis", "louis-vuitton", "macys", "michael-kors", "mr-porter", "neiman-marcus",
                "nike", "nordstrom", "old-navy", "prada", "saint-laurent", "saks-fifth-avenue",
                "sephora", "shein", "ssense", "target", "ulta", "uniqlo", "walmart", "zara"
            ]
        )

        let expectedTiers: [String: RetailerTier] = [
            "adidas": .athleticStreetwear,
            "foot-locker": .athleticStreetwear,
            "macys": .everydayValue,
            "levis": .everydayValue,
            "zara": .everydayValue,
            "hm": .everydayValue,
            "gucci": .designerLuxury,
            "prada": .designerLuxury,
            "burberry": .designerLuxury,
            "saint-laurent": .designerLuxury,
            "louis-vuitton": .designerLuxury,
            "nordstrom": .luxuryMultiBrand,
            "saks-fifth-avenue": .luxuryMultiBrand,
            "neiman-marcus": .luxuryMultiBrand,
            "bloomingdales": .luxuryMultiBrand,
            "bergdorf-goodman": .luxuryMultiBrand,
            "ssense": .luxuryMultiBrand,
            "mr-porter": .luxuryMultiBrand,
            "nike": .athleticStreetwear,
            "target": .everydayValue,
            "ebay": .everydayValue,
            "etsy": .everydayValue,
            "asos": .everydayValue,
            "uniqlo": .everydayValue,
            "gap": .everydayValue,
            "old-navy": .everydayValue,
            "abercrombie": .premiumMainstream,
            "jcrew": .premiumMainstream,
            "coach": .premiumMainstream,
            "michael-kors": .premiumMainstream,
            "kohls": .everydayValue
        ]
        for (retailerID, tier) in expectedTiers {
            XCTAssertEqual(registry.tier(retailerID: retailerID), tier)
        }

        XCTAssertTrue(stores.allSatisfy { $0.commerceDataCapability == .unavailable })
        XCTAssertEqual(registry.linkCapability(retailerID: "amazon"), .approvedAffiliate)
        XCTAssertEqual(registry.store(retailerID: "amazon")?.affiliateTrackingActive, true)
        XCTAssertTrue(registry.store(retailerID: "amazon")?.hasAffiliateTracking == true)
        XCTAssertEqual(registry.linkCapability(retailerID: "ebay"), .approvedAffiliate)
        XCTAssertEqual(registry.store(retailerID: "ebay")?.affiliateTrackingActive, true)
        XCTAssertTrue(registry.store(retailerID: "ebay")?.hasAffiliateTracking == true)
        XCTAssertEqual(registry.commerceDataCapability(retailerID: "amazon"), .unavailable)
        XCTAssertEqual(registry.commerceDataCapability(retailerID: "ebay"), .unavailable)

        let expectedDirectAccess: [String: (String, String)] = [
            "adidas": ("https://www.adidas.com", "https://www.adidas.com/us/search?q={QUERY}"),
            "foot-locker": ("https://www.footlocker.com", "https://www.footlocker.com/search?query={QUERY}"),
            "macys": ("https://www.macys.com", "https://www.macys.com/shop/featured/{QUERY}"),
            "levis": ("https://www.levi.com", "https://www.levi.com/US/en_US/search/{QUERY}"),
            "zara": ("https://www.zara.com", "https://www.zara.com/us/en/search?searchTerm={QUERY}"),
            "hm": ("https://www.hm.com", "https://www.hm.com/en_us/search-results.html?q={QUERY}")
        ]
        for (retailerID, expected) in expectedDirectAccess {
            let store = try XCTUnwrap(registry.store(retailerID: retailerID))
            XCTAssertEqual(store.websiteURL?.absoluteString, expected.0)
            XCTAssertEqual(store.searchURLTemplate, expected.1)
            XCTAssertEqual(store.linkCapability, .linkOnly)
        }

        let expectedLuxuryDestinations: [String: (String, String)] = [
            "gucci": ("gucci.com", "https://www.gucci.com/us/en/"),
            "prada": ("prada.com", "https://www.prada.com/ww/en.html"),
            "burberry": ("burberry.com", "https://int.burberry.com/"),
            "saint-laurent": ("ysl.com", "https://www.ysl.com/en-us"),
            "louis-vuitton": ("louisvuitton.com", "https://us.louisvuitton.com/eng-us/homepage")
        ]
        for (retailerID, expected) in expectedLuxuryDestinations {
            let store = try XCTUnwrap(registry.store(retailerID: retailerID))
            XCTAssertEqual(store.domains, [expected.0])
            XCTAssertEqual(store.websiteURL?.absoluteString, expected.1)
            XCTAssertNil(store.searchURLTemplate)
            XCTAssertEqual(store.tier, .designerLuxury)
            XCTAssertEqual(store.linkCapability, .linkOnly)
            XCTAssertEqual(store.commerceDataCapability, .unavailable)
            XCTAssertEqual(store.affiliateTrackingActive, false)
            XCTAssertFalse(store.hasAffiliateTracking)
        }

        let expectedLuxuryMultiBrandDestinations: [String: (String, String)] = [
            "saks-fifth-avenue": ("saksfifthavenue.com", "https://www.saksfifthavenue.com/"),
            "neiman-marcus": ("neimanmarcus.com", "https://www.neimanmarcus.com/"),
            "bloomingdales": ("bloomingdales.com", "https://www.bloomingdales.com/"),
            "bergdorf-goodman": ("bergdorfgoodman.com", "https://www.bergdorfgoodman.com/"),
            "ssense": ("ssense.com", "https://www.ssense.com/en-us"),
            "mr-porter": ("mrporter.com", "https://www.mrporter.com/en-us/")
        ]
        for (retailerID, expected) in expectedLuxuryMultiBrandDestinations {
            let store = try XCTUnwrap(registry.store(retailerID: retailerID))
            XCTAssertEqual(store.domains, [expected.0])
            XCTAssertEqual(store.websiteURL?.absoluteString, expected.1)
            XCTAssertNil(store.searchURLTemplate)
            XCTAssertEqual(store.tier, .luxuryMultiBrand)
            XCTAssertEqual(store.linkCapability, .linkOnly)
            XCTAssertEqual(store.commerceDataCapability, .unavailable)
            XCTAssertEqual(store.affiliateTrackingActive, false)
            XCTAssertFalse(store.hasAffiliateTracking)
        }
        XCTAssertNil(registry.store(retailerID: "farfetch"))
    }

    func testEveryBundledProductMatchesItsRetailerAndApprovedDestination() throws {
        let stores = try supportedStores()
        let registry = RetailerCatalogRegistry(stores: stores)

        for product in try bundledProducts() {
            let store = try XCTUnwrap(registry.store(retailerID: product.retailerID), product.id)
            XCTAssertEqual(product.retailer.name, store.name, product.id)
            guard case .success = ShoppingRetailerDestinationValidator.validate(
                candidateURL: product.affiliateURL,
                retailer: store
            ) else {
                return XCTFail("Bundled product destination does not match retailer: \(product.id)")
            }
        }
    }

    func testApprovedAmazonAffiliateCatalogAddsStyleMatchTracking() throws {
        let registry = RetailerCatalogRegistry(stores: try supportedStores())
        let amazon = try XCTUnwrap(registry.store(retailerID: "amazon"))
        let products = try bundledProducts().filter { $0.retailerID == "amazon" }

        XCTAssertEqual(amazon.linkCapability, .approvedAffiliate)
        XCTAssertEqual(amazon.affiliateTrackingActive, true)
        XCTAssertTrue(amazon.hasAffiliateTracking)
        XCTAssertTrue((amazon.disclosureText ?? "").localizedCaseInsensitiveContains("commission"))
        XCTAssertFalse(products.isEmpty)
        for product in products {
            let original = try XCTUnwrap(URLComponents(url: product.affiliateURL, resolvingAgainstBaseURL: false), product.id)
            XCTAssertNotNil(original.queryItems?.first(where: { $0.name == "k" })?.value, product.id)
            XCTAssertNil(original.queryItems?.first(where: { $0.name == "tag" }), product.id)

            let outbound = try XCTUnwrap(URLComponents(url: AffiliateLinkBuilder.outboundURL(for: product), resolvingAgainstBaseURL: false), product.id)
            XCTAssertEqual(outbound.queryItems?.first(where: { $0.name == "tag" })?.value, "stylematchpro-20", product.id)
        }
    }

    @MainActor
    func testApprovedAmazonAffiliateProductOpensTrackedDestination() async throws {
        let product = try XCTUnwrap(bundledProducts().first { $0.retailerID == "amazon" })
        let system = FakeShoppingSystemOpener(canOpen: true, completion: true)
        let result = await ShoppingProductOpener(
            approvedBaseURL: productionBaseURL,
            systemOpener: system
        ).open(product, supportedStores: try supportedStores())

        XCTAssertEqual(result, .openAccepted)
        let opened = try XCTUnwrap(system.openedURLs.first)
        let items = URLComponents(url: opened, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first(where: { $0.name == "tag" })?.value, "stylematchpro-20")
        XCTAssertEqual(opened.host, "www.amazon.com")
    }

    func testApprovedEbayStoreUsesTrackedPartnerDestination() throws {
        let registry = RetailerCatalogRegistry(stores: try supportedStores())
        let ebay = try XCTUnwrap(registry.store(retailerID: "ebay"))

        XCTAssertEqual(ebay.linkCapability, .approvedAffiliate)
        XCTAssertEqual(ebay.affiliateNetwork, "eBay Partner Network")
        XCTAssertTrue(ebay.hasAffiliateTracking)

        let direct = try XCTUnwrap(ebay.directAccessURL)
        let directItems = URLComponents(url: direct, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(directItems.first(where: { $0.name == "campid" })?.value, "5339211284")
        XCTAssertEqual(directItems.first(where: { $0.name == "customid" })?.value, "stylematchpro")
        XCTAssertEqual(directItems.first(where: { $0.name == "mkevt" })?.value, "1")

        let search = try XCTUnwrap(ebay.searchURL(for: "white sneakers"))
        let searchItems = URLComponents(url: search, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(searchItems.first(where: { $0.name == "_nkw" })?.value, "white sneakers")
        XCTAssertEqual(searchItems.first(where: { $0.name == "campid" })?.value, "5339211284")
        XCTAssertEqual(search.host, "www.ebay.com")
    }

    func testExpandedStoreDirectoryIncludesNewFashionDestinationsWithoutFalseAffiliateClaims() throws {
        let registry = RetailerCatalogRegistry(stores: try supportedStores())
        let directOnlyIDs = [
            "etsy", "asos", "uniqlo", "gap", "old-navy",
            "abercrombie", "jcrew", "coach", "michael-kors", "kohls"
        ]

        for retailerID in directOnlyIDs {
            let store = try XCTUnwrap(registry.store(retailerID: retailerID), retailerID)
            XCTAssertTrue(store.isEnabled, retailerID)
            XCTAssertEqual(store.linkCapability, .linkOnly, retailerID)
            XCTAssertEqual(store.affiliateTrackingActive, false, retailerID)
            XCTAssertFalse(store.hasAffiliateTracking, retailerID)
            XCTAssertNotNil(store.directAccessURL, retailerID)
        }
    }

    @MainActor
    func testTierResolvedPilotOfficialProductsPassTheSharedOpenerWithoutAffiliateSynthesis() async throws {
        let expectedIDs: Set<String> = [
            "gucci-840330aae801066-g75-sneaker",
            "prada-sc810-re-nylon-shirt",
            "ssense-hope-18999901-regular-fit-shirt",
            "ssense-hope-18998871-gray-short-sleeve-shirt",
            "nike-ah8050-005-air-max-270",
            "adidas-b75807-samba-og",
            "target-54190290-goodfellow-every-wear-tee",
            "levis-005010660-501-original-jeans"
        ]
        let products = try bundledProducts().filter { expectedIDs.contains($0.id) }

        XCTAssertEqual(Set(products.map(\.id)), expectedIDs)
        for product in products {
            let system = FakeShoppingSystemOpener(canOpen: true, completion: true)
            let result = await ShoppingProductOpener(
                approvedBaseURL: productionBaseURL,
                systemOpener: system
            ).open(product, supportedStores: try supportedStores())

            XCTAssertEqual(result, .openAccepted, product.id)
            XCTAssertEqual(system.openedURLs, [product.affiliateURL], product.id)
            XCTAssertFalse(product.affiliateURL.path.hasPrefix("/go/"), product.id)
            XCTAssertNil(URLComponents(url: product.affiliateURL, resolvingAgainstBaseURL: false)?.query, product.id)
        }
    }

    func testOlderDirectoryRecordDefaultsToNoCommerceCapability() throws {
        let legacyRecord = """
        [{
          "id": "legacy-store",
          "name": "Legacy Store",
          "domains": ["legacy.example"],
          "categories": ["clothing"],
          "apiStatus": "pending",
          "isEnabled": true
        }]
        """.data(using: .utf8)!

        let store = try XCTUnwrap(BundledStoreDirectoryProvider.decodeStores(legacyRecord).first)

        XCTAssertNil(store.tier)
        XCTAssertEqual(store.linkCapability, .unavailable)
        XCTAssertEqual(store.commerceDataCapability, .unavailable)
    }

    func testRetailerFoundationDoesNotExpandProductContextOrWorkerProjection() throws {
        let models = try source("StyleMatchAI/StylistChat/StylistChatModels.swift")
        let registry = try source("StyleMatchAI/Shopping/RetailerCatalogRegistry.swift")

        XCTAssertTrue(models.contains("case considering"))
        for prohibitedMarker in ["ShoppingTierPreference", "RetailerLinkCapability", "RetailerCommerceDataCapability", "ShoppingRecommendationLabel"] {
            XCTAssertFalse(models.contains(prohibitedMarker), "Product Context/Worker projection unexpectedly contains \(prohibitedMarker)")
        }
        XCTAssertFalse(registry.contains("URLSession"))
        XCTAssertFalse(registry.contains("Worker"))
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
            "https://fake-macys.com/shop"
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

    func testRetailerDestinationAcceptsRegisteredSubdomainsStructurally() {
        let store = makeStore(domains: ["macys.com"])
        XCTAssertNotNil(try? ShoppingRetailerDestinationValidator.validate(
            candidateURL: URL(string: "https://preview.macys.com/shop")!,
            retailer: store
        ).get())
    }

    @MainActor
    func testOfficialProductDestinationOpensWithoutGatewayOrAffiliateSynthesis() async {
        let directURL = URL(string: "https://www.gucci.com/us/en/pr/product")!
        let product = makeProduct(retailerID: "gucci", retailerName: "Gucci", candidateURL: directURL)
        let system = FakeShoppingSystemOpener(canOpen: true, completion: true)
        let result = await ShoppingProductOpener(
            approvedBaseURL: productionBaseURL,
            systemOpener: system
        ).open(product, supportedStores: [makeStore(id: "gucci", name: "Gucci", domains: ["gucci.com"])])

        XCTAssertEqual(result, .openAccepted)
        XCTAssertEqual(system.nativeOpenCalls, 1)
        XCTAssertEqual(system.openedURLs, [directURL])
        XCTAssertEqual(system.presentedURLs, [])
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

    private func productDestinationFailure(
        product: AffiliateProduct,
        gatewayURL: URL?,
        officialURL: URL?,
        stores: [SupportedStore]
    ) -> ShoppingProductOpenFailure? {
        guard case let .failure(failure) = ShoppingProductDestinationValidator.validate(
            gatewayCandidateURL: gatewayURL,
            officialProductURL: officialURL,
            product: product,
            supportedStores: stores,
            approvedBaseURL: productionBaseURL
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

    private func makeStore(
        id: String = "macys",
        name: String = "Macy's",
        domains: [String],
        enabled: Bool = true
    ) -> SupportedStore {
        SupportedStore(
            id: id,
            name: name,
            domains: domains,
            categories: [.clothing],
            affiliateNetwork: "Impact",
            apiStatus: "approved",
            isEnabled: enabled
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
    private(set) var openedURLs: [URL] = []
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
        openedURLs.append(url)
        return nativeCompletion
    }

    func presentInAppBrowser(_ url: URL) async -> Bool {
        browserPresentationCalls += 1
        presentedURLs.append(url)
        return browserCompletion
    }
}
