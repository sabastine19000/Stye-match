import XCTest
@testable import StyleMatchPro

final class Build16PaletteTruthTests: XCTestCase {
    private func projectSource(_ relativePath: String, filePath: String = #filePath) throws -> String {
        let root = URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    func testAdaptiveAppearanceUsesApprovedLocalResolverAndSharedPrimitives() throws {
        let source = try projectSource("StyleMatchAI/ContentView.swift")
        let appSource = try projectSource("StyleMatchAI/StyleMatchAIApp.swift")

        XCTAssertTrue(source.contains("enum StyleMatchAppearanceMode"))
        XCTAssertTrue(source.contains("enum StyleMatchAppearanceResolver"))
        XCTAssertTrue(source.contains("enum StyleMatchAdaptiveDecisionEngine"))
        XCTAssertTrue(source.contains("StyleMatchAppTheme.availableThemes.filter"))
        XCTAssertTrue(source.contains("if accessibility.increaseContrast && theme == .premiumPink { return false }"))
        XCTAssertTrue(source.contains("if accessibility.reduceTransparency && theme == .styleMatchAI { return false }"))
        XCTAssertTrue(source.contains("theme: adaptive ?? selected"))
        XCTAssertEqual(source.components(separatedBy: "StyleMatchAppearanceResolver.resolve(").count - 1, 4)
        XCTAssertTrue(appSource.contains("repairStringValue(\"styleMatchAppearanceMode\", allowed: StyleMatchAppearanceMode.allCases.map(\\.rawValue)"))
        XCTAssertFalse(source[source.range(of: "enum StyleMatchAppearanceMode")!.lowerBound..<source.range(of: "private struct AppScreenBackground")!.lowerBound].contains("URLSession"))
    }

    func testAdaptiveAppearancePremiumUIKeepsUserOverrideLocal() throws {
        let source = try projectSource("StyleMatchAI/ProfileView.swift")

        XCTAssertTrue(source.contains("@AppStorage(\"styleMatchAdaptiveThemeLock\")"))
        XCTAssertTrue(source.contains("Section(\"Appearance Mode\")"))
        XCTAssertTrue(source.contains("Current adaptive theme"))
        XCTAssertTrue(source.contains("Keep this theme"))
        XCTAssertTrue(source.contains("Return to Adaptive"))
        XCTAssertTrue(source.contains("adaptiveThemeLocked = true"))
        XCTAssertTrue(source.contains("adaptiveThemeLocked = false"))
        XCTAssertTrue(source.contains("selectedTheme = draftTheme"))
        XCTAssertTrue(source.contains("adaptiveTheme = draftTheme"))
    }

    func testStyleFriendsChatUsesResolvedThemeTokensForReactionAndComposerPresentation() throws {
        let source = try projectSource("StyleMatchAI/StyleFriendsChatUI.swift")

        XCTAssertEqual(source.components(separatedBy: "StyleMatchAppearanceResolver.resolve(").count - 1, 2)
        XCTAssertTrue(source.contains("themeTokens.socialAccent.opacity(0.16)"))
        XCTAssertTrue(source.contains("themeTokens.elevatedCardBackground"))
        XCTAssertTrue(source.contains("themeTokens.cardBackground"))
        XCTAssertTrue(source.contains(".tint(themeTokens.socialAccent)"))
        let composerStart = try XCTUnwrap(source.range(of: "struct FriendChatComposer")).lowerBound
        let composerEnd = try XCTUnwrap(source.range(of: "struct SharedOutfitMessageCard")).lowerBound
        XCTAssertFalse(source[composerStart..<composerEnd].contains("Color(uiColor: .secondarySystemGroupedBackground)"))
    }

    func testResolvedAppearanceAuthorityIsLocalAndShared() throws {
        let source = try projectSource("StyleMatchAI/ContentView.swift")
        let resolverStart = try XCTUnwrap(source.range(of: "enum StyleMatchAppearanceMode"))
        let resolverEnd = try XCTUnwrap(source.range(of: "private struct AppScreenBackground"))
        let resolverSource = source[resolverStart.lowerBound..<resolverEnd.lowerBound]

        XCTAssertTrue(resolverSource.contains("enum StyleMatchAppearanceMode"))
        XCTAssertTrue(resolverSource.contains("enum StyleMatchAppearanceResolver"))
        XCTAssertTrue(resolverSource.contains("case .manual: return .init(theme: selected"))
        XCTAssertTrue(resolverSource.contains("case .system: return .init(theme: .system"))
        XCTAssertTrue(resolverSource.contains("adaptive ?? selected"))
        XCTAssertFalse(resolverSource.contains("URLSession"))
        XCTAssertFalse(resolverSource.contains("OpenAI"))
    }

    func testResolvedAppearancePreservesLegacyManualThemeContract() throws {
        let source = try projectSource("StyleMatchAI/ContentView.swift")
        let appSource = try projectSource("StyleMatchAI/StyleMatchAIApp.swift")
        let profileSource = try projectSource("StyleMatchAI/ProfileView.swift")

        XCTAssertTrue(source.contains("Self(rawValue: rawValue ?? \"\") ?? .manual"))
        XCTAssertTrue(source.contains("let selected = StyleMatchAppTheme(rawValue: selectedThemeRawValue ?? \"\") ?? .system"))
        XCTAssertTrue(source.contains("case .manual: return .init(theme: selected, reasonCode: \"manual_selection\")"))
        for themeCase in [".styleMatchAI", ".system", ".dark", ".blackAMOLED", ".premiumPink", ".blue", ".green", ".light"] {
            XCTAssertTrue(profileSource.contains("case \(themeCase):"), "Missing legacy approved theme \(themeCase)")
        }
        XCTAssertTrue(appSource.contains("repairStringValue(\"styleMatchAppearanceMode\", allowed: StyleMatchAppearanceMode.allCases.map(\\.rawValue), fallback: StyleMatchAppearanceMode.manual.rawValue"))
        XCTAssertTrue(appSource.contains("repairStringValue(\"selectedAppTheme\", allowed: StyleMatchAppTheme.allCases.map(\\.rawValue)"))
    }

    func testLegacySelectedThemeSystemResolvesManualModeNotSystemMode() throws {
        let source = try projectSource("StyleMatchAI/ContentView.swift")

        // The raw string "system" is valid for both authorities. With no mode
        // stored, only StyleMatchAppearanceMode.resolve chooses manual; manual
        // then returns the user's selected theme, which may itself be .system.
        XCTAssertTrue(source.contains("Self(rawValue: rawValue ?? \"\") ?? .manual"))
        XCTAssertTrue(source.contains("case .manual: return .init(theme: selected, reasonCode: \"manual_selection\")"))
        XCTAssertTrue(source.contains("case .system: return .init(theme: .system, reasonCode: \"system_appearance\")"))
    }

    func testResolvedAppearanceModeAndAdaptiveFallbackContracts() throws {
        let source = try projectSource("StyleMatchAI/ContentView.swift")

        XCTAssertTrue(source.contains("case manual, system, adaptive"))
        XCTAssertTrue(source.contains("case .system: return .init(theme: .system"))
        XCTAssertTrue(source.contains("let adaptive = StyleMatchAppTheme(rawValue: adaptiveThemeRawValue ?? \"\")"))
        XCTAssertTrue(source.contains("theme: adaptive ?? selected"))
        XCTAssertTrue(source.contains("reasonCode: adaptive == nil ? \"adaptive_fallback\" : \"adaptive_local\""))
        XCTAssertTrue(source.contains("let selected = StyleMatchAppTheme(rawValue: selectedThemeRawValue ?? \"\") ?? .system"))
    }

    func testThemeEditorKeepsPreviewDraftSeparateFromAppliedTheme() throws {
        let source = try projectSource("StyleMatchAI/ProfileView.swift")

        XCTAssertTrue(source.contains("@State private var draftTheme: String"))
        XCTAssertTrue(source.contains("_draftTheme = State(initialValue: selectedTheme.wrappedValue)"))
        XCTAssertTrue(source.contains("draftTheme = theme.rawValue"))
        XCTAssertTrue(source.contains("selectedTheme = draftTheme"))
        XCTAssertTrue(source.contains("Preview never changes the app until you apply it."))
    }

    func testAllThreeSharedPrimitivesUseTheSameResolverInputs() throws {
        let source = try projectSource("StyleMatchAI/ContentView.swift")
        let resolverCall = "StyleMatchAppearanceResolver.resolve(modeRawValue: appearanceMode, selectedThemeRawValue: selectedAppTheme, adaptiveThemeRawValue: adaptiveTheme).theme"

        let screenStart = try XCTUnwrap(source.range(of: "private struct AppScreenBackground")).lowerBound
        let cardStart = try XCTUnwrap(source.range(of: "private struct AppCardBackground")).lowerBound
        let bandStart = try XCTUnwrap(source.range(of: "struct PageColorBand")).lowerBound
        let contentStart = try XCTUnwrap(source.range(of: "struct ContentView")).lowerBound
        let screenSection = screenStart..<cardStart
        let cardSection = cardStart..<bandStart
        let bandSection = bandStart..<contentStart

        for section in [source[screenSection], source[cardSection], source[bandSection]] {
            XCTAssertTrue(section.contains(resolverCall))
            XCTAssertTrue(section.contains("@AppStorage(\"styleMatchAppearanceMode\")"))
            XCTAssertTrue(section.contains("@AppStorage(\"styleMatchAdaptiveTheme\")"))
        }
    }

    func testResolvedAppearancePersistenceAndSafeFallbacksAreDeviceLocal() throws {
        let contentSource = try projectSource("StyleMatchAI/ContentView.swift")
        let appSource = try projectSource("StyleMatchAI/StyleMatchAIApp.swift")
        let resolverStart = try XCTUnwrap(contentSource.range(of: "enum StyleMatchAppearanceMode"))
        let resolverEnd = try XCTUnwrap(contentSource.range(of: "private struct AppScreenBackground"))
        let resolverSource = contentSource[resolverStart.lowerBound..<resolverEnd.lowerBound]

        XCTAssertEqual(contentSource.components(separatedBy: "@AppStorage(\"styleMatchAppearanceMode\")").count - 1, 4)
        XCTAssertEqual(contentSource.components(separatedBy: "@AppStorage(\"styleMatchAdaptiveTheme\")").count - 1, 4)
        XCTAssertTrue(appSource.contains("fallback: StyleMatchAppearanceMode.manual.rawValue"))
        XCTAssertTrue(resolverSource.contains("Self(rawValue: rawValue ?? \"\") ?? .manual"))
        XCTAssertTrue(resolverSource.contains("StyleMatchAppTheme(rawValue: selectedThemeRawValue ?? \"\") ?? .system"))
        XCTAssertTrue(resolverSource.contains("theme: adaptive ?? selected"))
        XCTAssertFalse(resolverSource.contains("URLSession"))
        XCTAssertFalse(resolverSource.contains("OpenAI"))
        XCTAssertFalse(resolverSource.contains("CloudKit"))
    }

    func testRegionAcceptedScanFeedsOnlyQualifyingCropBoxesIntoPaletteExtraction() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(source.contains("if clothingLabel.confidence >= acceptanceThreshold"))
        XCTAssertTrue(source.contains("qualifyingBoxes.append(candidate.normalizedTopLeftBox)"))
        XCTAssertTrue(source.contains("let paletteBoxes = paletteRegionBoxes("))
        XCTAssertTrue(source.contains("regionBoxes: paletteBoxes"))
        XCTAssertTrue(source.contains("source: .garmentCrop"))
    }

    func testGrayWorldCorrectionRunsBeforeColorNamingAndClampsGains() throws {
        let source = try projectSource("StyleMatchAI/GarmentColorPaletteEngine.swift")
        guard let correction = source.range(of: "let correction = illuminantAwareCorrection("),
              let naming = source.range(of: "let weightedSummary = weightedColorSummary(") else {
            return XCTFail("Expected illuminant-aware correction before palette naming.")
        }

        XCTAssertLessThan(correction.lowerBound, naming.lowerBound)
        XCTAssertTrue(source.contains("min(1.6, max(0.6, target / mean))"))
        XCTAssertTrue(source.contains("whiteBalance=["))
        XCTAssertTrue(source.contains("illuminantReference="))
    }

    func testExtremeGrayWorldGainsAreClamped() {
        let samples = Array(repeating: GarmentPalettePixel(red: 255, green: 1, blue: 1), count: 100)
        let result = GarmentColorPaletteEngine.extractPalette(from: samples, source: .garmentCrop)

        XCTAssertGreaterThanOrEqual(result.debug.whiteBalanceGains.red, 0.6)
        XCTAssertLessThanOrEqual(result.debug.whiteBalanceGains.red, 1.6)
        XCTAssertGreaterThanOrEqual(result.debug.whiteBalanceGains.green, 0.6)
        XCTAssertLessThanOrEqual(result.debug.whiteBalanceGains.green, 1.6)
        XCTAssertGreaterThanOrEqual(result.debug.whiteBalanceGains.blue, 0.6)
        XCTAssertLessThanOrEqual(result.debug.whiteBalanceGains.blue, 1.6)
    }

    func testLowConfidencePaletteUsesHonestCopyAndWithholdsColorsFromAIContext() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(source.contains("Colors were hard to read in this photo"))
        XCTAssertTrue(source.contains("colors: analysis.colorPaletteConfidence == .confident ? analysis.colorPalette : []"))
        XCTAssertTrue(source.contains("confidenceLevel: analysis.colorPaletteConfidence.userFacingLabel"))
        XCTAssertTrue(source.contains("Do not assert specific garment colors"))
    }

    func testExactFingerprintReusesStoredDeterministicInputsWithMigrationSafeDecode() throws {
        let scanSource = try projectSource("StyleMatchAI/ScanView.swift")
        let persistenceSource = try projectSource("StyleMatchAI/ScanAuthority/StoredOutfitScan.swift")

        XCTAssertTrue(scanSource.contains("let storedInputs = exactStoredScan?.deterministicInputs"))
        XCTAssertTrue(scanSource.contains("let colorPalette = storedInputs?.colorPalette ?? colorDetection.garmentColors"))
        XCTAssertTrue(scanSource.contains("let scoringLabels = storedInputs?.labels ?? labels"))
        XCTAssertTrue(persistenceSource.contains("decodeIfPresent(StoredDeterministicScorerInputs.self, forKey: .deterministicInputs)"))
    }

    func testStyleMemoryRequiresExactOutfitFingerprint() throws {
        let recallSource = try projectSource("StyleMatchAI/PersonalStylist/OutfitRecallService.swift")
        let modelSource = try projectSource("StyleMatchAI/PersonalStylist/StylistProfileModels.swift")

        XCTAssertTrue(recallSource.contains("guard let fingerprint = cleanOptional(context.outfitFingerprint)"))
        XCTAssertTrue(recallSource.contains("ScanImageIdentity.isExactMatch("))
        XCTAssertTrue(modelSource.contains("outfitFingerprint = try container.decodeIfPresent(String.self"))
        XCTAssertTrue(modelSource.contains("imageDigest = try container.decodeIfPresent(String.self"))
    }

    func testRecallRejectsDifferentFingerprintEvenWhenGarmentFactsMatch() {
        var memory = OutfitMemory(
            id: UUID(),
            userId: "palette-truth-user",
            scanDate: Date(),
            detectedGarments: ["shirt"],
            colors: ["blue"],
            detectedStyle: "Casual",
            styleScore: 82,
            occasion: .casual,
            wasWorn: true,
            wasLiked: true,
            feedbackTimestamp: nil,
            dislikeReason: nil,
            wouldWearAgain: true,
            receivedCompliments: nil,
            isFavorite: false,
            timesWorn: 1
        )
        memory.outfitFingerprint = "outfit-v4|scan-a"
        memory.imageDigest = "digest-a"

        let fact = OutfitRecallService.recallFact(
            for: OutfitRecallScanContext(
                detectedGarments: ["shirt"],
                colors: ["blue"],
                detectedStyle: "Casual",
                outfitFingerprint: "outfit-v4|scan-b",
                imageDigest: "digest-a"
            ),
            memories: [memory]
        )

        XCTAssertNil(fact)
    }

    func testPortraitOversizedRegionUsesPixelHeightAndSplitsTopBottom() throws {
        let box = CGRect(x: 0, y: 0.08, width: 1, height: 0.841)
        let halves = GarmentRegionGeometry.subdividedBoxes(
            of: box,
            imageSize: CGSize(width: 675, height: 900)
        )

        XCTAssertEqual(halves.count, 2)
        XCTAssertEqual(halves[0].width, 1, accuracy: 0.0001)
        XCTAssertEqual(halves[0].height, 0.4205, accuracy: 0.0001)
        XCTAssertEqual(halves[1].minY, box.minY + 0.4205, accuracy: 0.0001)
    }

    func testGarmentCropSamplingRequiresErodedForegroundIntersection() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(source.contains("foregroundMask.includedCount >= GarmentColorPaletteEngine.minimumGarmentPixelCount"))
        XCTAssertTrue(source.contains("strongForegroundMask = rawForegroundMask?.adaptivelyErodedStrongMask()"))
        XCTAssertTrue(source.contains("guard let foregroundMask,"))
        XCTAssertFalse(source.contains("centerCropMask(width: width, height: height, fraction: 0.60)"))
    }

    func testPaleTintNamingPreservesBlueAndPinkWithoutMisnamingGray() {
        XCTAssertEqual(GarmentColorPaletteEngine.everydayGarmentColorName(for: .init(red: 170, green: 200, blue: 215)), "light blue")
        XCTAssertEqual(GarmentColorPaletteEngine.everydayGarmentColorName(for: .init(
            red: 220,
            green: 185,
            blue: 195,
            isStrongForegroundEvidence: true
        )), "blush")
        XCTAssertEqual(GarmentColorPaletteEngine.everydayGarmentColorName(for: .init(red: 190, green: 190, blue: 190)), "gray")
    }

    func testAdaptiveStrongMaskDegradesWithoutCollapsingFragmentedEvidence() {
        var included = Array(repeating: false, count: 20 * 20)
        for y in stride(from: 2, to: 18, by: 2) {
            for x in stride(from: 2, to: 18, by: 2) {
                included[y * 20 + x] = true
            }
        }
        let mask = GarmentRegionMask(width: 20, height: 20, included: included, tier: .saliencyCrop)
        let strong = mask.adaptivelyErodedStrongMask()

        XCTAssertNotNil(strong)
        XCTAssertGreaterThan(strong?.includedCount ?? 0, 0)
        XCTAssertLessThanOrEqual(strong?.includedCount ?? 0, mask.includedCount)
    }

    func testEveryMaskedPaletteSourcePropagatesAdaptiveStrongEvidence() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        let candidateFunction = try XCTUnwrap(source.range(of: "private func maskedGarmentPaletteCandidates"))
        let cropFunction = try XCTUnwrap(source.range(of: "private func garmentCropPaletteSamples"))
        let candidateBody = source[candidateFunction.lowerBound..<cropFunction.lowerBound]

        XCTAssertTrue(candidateBody.contains("rawMask.adaptivelyErodedStrongMask()"))
        XCTAssertTrue(candidateBody.contains("strongForegroundMask: strongForegroundMask"))
        XCTAssertFalse(candidateBody.contains("strongCoverage="))
    }

    func testUnsupportedChromaticFamilyCannotDethroneEvidencedNeutralLeader() {
        let unsupportedRed = Array(repeating: GarmentPalettePixel(red: 205, green: 45, blue: 50), count: 700)
        let evidencedGray = Array(repeating: GarmentPalettePixel(
            red: 120,
            green: 120,
            blue: 120,
            isStrongForegroundEvidence: true
        ), count: 500)
        let result = GarmentColorPaletteEngine.extractPalette(
            from: unsupportedRed + evidencedGray,
            source: .saliencyCrop,
            confidenceEvidenceSatisfied: true
        )

        XCTAssertEqual(FashionColorFamilyCatalog.family(for: result.palette.first ?? ""), "neutral")
        XCTAssertTrue(result.debug.leadershipDecision.contains("demoted unsupported family"))
    }

    func testSaturationTransitionBlendsNeutralAndChromaticSharesWithoutChangingStrongColors() {
        let heather = FashionColorCatalog.nameContributions(
            red: 95,
            green: 100,
            blue: 120,
            hasSpatialEvidence: true
        )
        let royalBlue = FashionColorCatalog.nameContributions(
            red: 45,
            green: 78,
            blue: 180,
            hasSpatialEvidence: true
        )
        let red = FashionColorCatalog.nameContributions(
            red: 205,
            green: 45,
            blue: 50,
            hasSpatialEvidence: true
        )

        XCTAssertEqual(heather.count, 2)
        XCTAssertEqual(heather.reduce(0) { $0 + $1.weight }, 1, accuracy: 0.0001)
        XCTAssertEqual(royalBlue, [.init(name: "royal blue", weight: 1)])
        XCTAssertEqual(red, [.init(name: "red", weight: 1)])
    }

    func testBrightWarmNeutralNeedsSpatialEvidenceToBecomeBlush() {
        let warmWhite = GarmentPalettePixel(red: 220, green: 185, blue: 195)
        let blushGarment = GarmentPalettePixel(
            red: 220,
            green: 185,
            blue: 195,
            isStrongForegroundEvidence: true
        )

        XCTAssertTrue(["white", "ivory"].contains(GarmentColorPaletteEngine.everydayGarmentColorName(for: warmWhite)))
        XCTAssertEqual(GarmentColorPaletteEngine.everydayGarmentColorName(for: blushGarment), "blush")
    }

    func testHeatherFamilyIsStableAcrossNoisePerturbedRuns() {
        let variants: [(UInt8, UInt8, UInt8)] = [
            (95, 100, 120), (94, 100, 121), (95, 99, 121), (98, 101, 121)
        ]
        let palettes = variants.map { red, green, blue in
            let darkThreads = Array(repeating: GarmentPalettePixel(
                red: red,
                green: green,
                blue: blue,
                isStrongForegroundEvidence: true
            ), count: 500)
            let paleThreads = Array(repeating: GarmentPalettePixel(
                red: 120,
                green: 120,
                blue: 125,
                isStrongForegroundEvidence: true
            ), count: 500)
            return GarmentColorPaletteEngine.extractPalette(
                from: darkThreads + paleThreads,
                source: .garmentCrop,
                confidenceEvidenceSatisfied: true
            ).palette.first.map(FashionColorFamilyCatalog.family(for:))
        }

        XCTAssertEqual(Set(palettes.compactMap { $0 }).count, 1)
    }

    func testMaroonAndRoyalBlueGarmentsStillLeadWithEvidence() {
        for (pixel, expectedFamily) in [
            (GarmentPalettePixel(red: 82, green: 32, blue: 42, isStrongForegroundEvidence: true), "red"),
            (GarmentPalettePixel(red: 45, green: 78, blue: 180, isStrongForegroundEvidence: true), "blue")
        ] {
            let result = GarmentColorPaletteEngine.extractPalette(
                from: Array(repeating: pixel, count: 700),
                source: .garmentCrop,
                confidenceEvidenceSatisfied: true
            )
            XCTAssertEqual(FashionColorFamilyCatalog.family(for: result.palette.first ?? ""), expectedFamily)
        }
    }

    func testGrayWorldCorrectionDoesNotNeutralizePaleBlueMajority() {
        let samples = Array(repeating: GarmentPalettePixel(red: 170, green: 200, blue: 215), count: 100)
        let result = GarmentColorPaletteEngine.extractPalette(from: samples, source: .garmentCrop)

        XCTAssertTrue(result.palette.contains("light blue"), "A genuinely pale-blue majority must remain light blue after correction.")
        XCTAssertLessThan(abs(result.debug.whiteBalanceGains.red - 1), 0.05)
        XCTAssertLessThan(abs(result.debug.whiteBalanceGains.blue - 1), 0.05)
    }

    func testFifteenPercentTintClusterSurvivesNeutralMajority() {
        let neutral = Array(repeating: GarmentPalettePixel(red: 110, green: 110, blue: 110), count: 85)
        let blue = Array(repeating: GarmentPalettePixel(red: 120, green: 170, blue: 205), count: 15)
        let result = GarmentColorPaletteEngine.extractPalette(from: neutral + blue, source: .garmentCrop)

        XCTAssertTrue(result.palette.contains { $0.contains("blue") })
        XCTAssertTrue(result.debug.clusters.contains { $0.name.contains("blue") && $0.share >= 0.15 })
    }

    func testFashionColorCatalogCoversRequiredAnchorsAndAlwaysNamesRGB() {
        let names = Set(FashionColorCatalog.anchors.map(\.name))
        let required = [
            "white", "cream", "beige", "tan", "brown", "gray", "charcoal", "black",
            "navy", "blue", "light blue", "teal", "green", "olive", "yellow", "mustard",
            "orange", "rust", "red", "burgundy", "pink", "blush", "purple", "lavender", "denim"
        ]

        XCTAssertGreaterThanOrEqual(FashionColorCatalog.anchors.count, 40)
        XCTAssertTrue(Set(required).isSubset(of: names))
        XCTAssertFalse(FashionColorCatalog.nearestName(red: 1, green: 2, blue: 3).isEmpty)
        XCTAssertFalse(FashionColorCatalog.nearestName(red: 254, green: 253, blue: 252).isEmpty)
    }

    func testFashionColorCatalogEvidenceColors() {
        XCTAssertEqual(FashionColorCatalog.nearestName(red: 170, green: 200, blue: 215), "light blue")
        XCTAssertTrue(["black", "charcoal"].contains(FashionColorCatalog.nearestName(red: 48, green: 49, blue: 52)))
        XCTAssertEqual(FashionColorCatalog.nearestName(red: 128, green: 128, blue: 128), "gray")
        XCTAssertEqual(FashionColorCatalog.nearestName(red: 190, green: 155, blue: 110), "tan")
    }

    func testRegionPaletteMergesEveryQualifyingCropAndSubdividedSibling() throws {
        let scanSource = try projectSource("StyleMatchAI/ScanView.swift")
        XCTAssertTrue(scanSource.contains("qualifyingBoxes.append(contentsOf: candidate.relatedPaletteBoxes)"))
        XCTAssertTrue(scanSource.contains("relatedPaletteBoxes: halves.filter { $0 != half }"))
        XCTAssertTrue(scanSource.contains("let cropSamples = regionBoxes.compactMap"))
        XCTAssertTrue(scanSource.contains("GarmentCropContributionBalancer.balance(cropSamples)"))
        XCTAssertFalse(scanSource.contains("regionBoxes.prefix(6).flatMap"))

        let pantsCrop = Array(repeating: GarmentPalettePixel(red: 35, green: 36, blue: 40), count: 700)
        let shirtCrop = Array(repeating: GarmentPalettePixel(red: 170, green: 200, blue: 215), count: 300)
        let merged = GarmentColorPaletteEngine.extractPalette(
            from: pantsCrop + shirtCrop,
            source: .garmentCrop,
            allowsSkinExclusion: false
        )

        XCTAssertTrue(merged.palette.contains { $0.contains("blue") }, "A qualifying shirt crop must survive the pants-dominant merged sample.")
        XCTAssertTrue(merged.debug.clusters.contains { $0.name.contains("blue") && $0.count >= 300 })
    }

    func testPaletteTierQualityGateSkipsSmallTierAndUsesLargestLowConfidenceFallback() {
        func candidate(samples: Int, tier: GarmentMaskTier) -> GarmentPaletteSampleCandidate {
            GarmentPaletteSampleCandidate(
                samples: [],
                tier: tier,
                source: tier == .foregroundSubject ? .foregroundSubject : .personSegmentation,
                maskingApplied: true,
                garmentSampleCount: samples
            )
        }

        let qualified = GarmentPaletteSourceSelector.select([
            candidate(samples: 128, tier: .foregroundSubject),
            candidate(samples: 5_483, tier: .personSegmentation)
        ])
        XCTAssertEqual(qualified.candidate?.tier, .personSegmentation)
        XCTAssertTrue(qualified.metQualityBar)

        let fallback = GarmentPaletteSourceSelector.select([
            candidate(samples: 128, tier: .foregroundSubject),
            candidate(samples: 420, tier: .personSegmentation)
        ])
        XCTAssertEqual(fallback.candidate?.garmentSampleCount, 420)
        XCTAssertFalse(fallback.metQualityBar)
    }

    func testSkinExclusionIsInertWhenNoHumanWasDetected() {
        let flatLaySamples = Array(repeating: GarmentPalettePixel(
            red: 180,
            green: 120,
            blue: 90,
            isInsidePersonMask: true,
            isLikelySkinZone: true
        ), count: 600)

        let flatLay = GarmentColorPaletteEngine.extractPalette(
            from: flatLaySamples,
            source: .garmentCrop,
            allowsSkinExclusion: false
        )
        let worn = GarmentColorPaletteEngine.extractPalette(
            from: flatLaySamples,
            source: .personSegmentation,
            allowsSkinExclusion: true
        )

        XCTAssertEqual(flatLay.debug.skinReferenceSamples, 0)
        XCTAssertEqual(flatLay.debug.garmentSamples, 600)
        XCTAssertGreaterThan(worn.debug.skinReferenceSamples, 0)
        XCTAssertEqual(worn.debug.garmentSamples, 0)
    }

    func testPaletteSourceSelectorRanksAllQualifiedCandidatesBySamplesReliabilityAndAgreement() {
        func candidate(
            samples: Int,
            source: GarmentPaletteSource,
            tier: GarmentMaskTier,
            families: [String: Double]
        ) -> GarmentPaletteSampleCandidate {
            GarmentPaletteSampleCandidate(
                samples: [],
                tier: tier,
                source: source,
                maskingApplied: true,
                garmentSampleCount: samples,
                familyShares: families
            )
        }

        let selection = GarmentPaletteSourceSelector.select([
            candidate(samples: 600, source: .garmentCrop, tier: .foregroundSubject, families: ["brown": 0.8]),
            candidate(samples: 1_200, source: .personSegmentation, tier: .personSegmentation, families: ["blue": 0.7]),
            candidate(samples: 1_100, source: .foregroundSubject, tier: .foregroundSubject, families: ["blue": 0.6])
        ])

        XCTAssertEqual(selection.candidate?.source, .personSegmentation)
        XCTAssertEqual(selection.rankedCandidates.count, 3)
        XCTAssertTrue(selection.metQualityBar)
    }

    func testColorFamiliesAggregateBeforeFifteenPercentRetention() throws {
        let aggregated = FashionColorFamilyCatalog.aggregatedCounts([
            "gray": 85,
            "light blue": 8,
            "denim": 7
        ])

        XCTAssertEqual(aggregated["blue"]?.count, 15)
        XCTAssertEqual(aggregated["blue"]?.representative, "light blue")

        let source = try projectSource("StyleMatchAI/GarmentColorPaletteEngine.swift")
        guard let aggregation = source.range(of: "let familyCounts = FashionColorFamilyCatalog.aggregatedWeights"),
              let retention = source[aggregation.lowerBound...].range(of: "share >= minimumRetainedClusterShare") else {
            return XCTFail("Expected family aggregation before the retention cutoff.")
        }
        XCTAssertLessThan(aggregation.lowerBound, retention.lowerBound)
    }

    func testGarmentCropContributionBalancingPreventsLargeCropFromDrowningSmallCrop() {
        let largeCrop = Array(repeating: GarmentPalettePixel(red: 30, green: 30, blue: 32), count: 1_000)
        let smallCrop = Array(repeating: GarmentPalettePixel(red: 170, green: 200, blue: 215), count: 200)
        let balanced = GarmentCropContributionBalancer.balance([largeCrop, smallCrop])

        XCTAssertEqual(balanced.rawSampleCount, 1_200)
        XCTAssertEqual(balanced.samples.count, 400)
        XCTAssertEqual(balanced.samples.filter { $0.blue > 150 && $0.blue > $0.red }.count, 200)
    }

    func testCredibleSourceDisagreementForcesLowConfidenceAndIsLogged() throws {
        let first = GarmentPaletteSampleCandidate(
            samples: [],
            tier: .foregroundSubject,
            source: .garmentCrop,
            maskingApplied: true,
            garmentSampleCount: 800,
            familyShares: ["blue": 0.8]
        )
        let second = GarmentPaletteSampleCandidate(
            samples: [],
            tier: .personSegmentation,
            source: .personSegmentation,
            maskingApplied: true,
            garmentSampleCount: 900,
            familyShares: ["brown": 0.7]
        )

        XCTAssertTrue(GarmentPaletteSourceSelector.select([first, second]).disagreement)

        let source = try projectSource("StyleMatchAI/ScanView.swift")
        XCTAssertTrue(source.contains("forceLowConfidence: !selection.hasConfidenceEvidence"))
        XCTAssertFalse(source.contains("candidatesRanked=["))
        XCTAssertFalse(source.contains("familyShares=["))
        XCTAssertFalse(source.contains("disagreement=\\(selection.disagreement)"))
    }

    func testTealTurquoiseAndAquaAggregateIntoBlueFamily() {
        XCTAssertEqual(FashionColorFamilyCatalog.family(for: "teal"), "blue")
        XCTAssertEqual(FashionColorFamilyCatalog.family(for: "turquoise"), "blue")
        XCTAssertEqual(FashionColorFamilyCatalog.family(for: "aqua"), "blue")
        XCTAssertEqual(FashionColorFamilyCatalog.aggregatedCounts([
            "light blue": 37,
            "teal": 111,
            "gray": 505
        ])["blue"]?.count, 148)
    }

    func testBackgroundDownWeightingProtectsGrayGarmentOnGrayBedding() {
        let tanBorder = Array(repeating: GarmentPalettePixel(red: 190, green: 155, blue: 110, x: 0.02, y: 0.5), count: 600)
        let grayGarment = Array(repeating: GarmentPalettePixel(
            red: 125,
            green: 125,
            blue: 125,
            x: 0.5,
            y: 0.5,
            isStrongForegroundEvidence: true
        ), count: 600)
        let result = GarmentColorPaletteEngine.extractPalette(
            from: tanBorder + grayGarment,
            source: .saliencyCrop,
            backgroundFamilyShares: ["brown": 0.75, "neutral": 0.25],
            confidenceEvidenceSatisfied: true,
            confidenceReason: "test corroboration"
        )

        XCTAssertTrue(result.palette.contains("gray"), "Central gray garment evidence must survive even when the bedding is also gray.")
        XCTAssertGreaterThan(result.debug.downWeightedSamples, 0)
        XCTAssertGreaterThanOrEqual(result.debug.garmentSamples, 500)
    }

    func testMasklessGarmentCropIsSkippedInsteadOfSamplingCenterSixtyPercent() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(source.contains("foregroundMask.includedCount >= GarmentColorPaletteEngine.minimumGarmentPixelCount"))
        XCTAssertFalse(source.contains("garmentCrop sampling=center60"))
        XCTAssertFalse(source.contains("private func centerCropMask("))
    }

    func testBrownPantsSurviveWhileTanWallInSameFamilyIsDownWeighted() {
        let tanWall = Array(repeating: GarmentPalettePixel(
            red: 190,
            green: 155,
            blue: 110,
            x: 0.5,
            y: 0.5
        ), count: 600)
        let brownPants = Array(repeating: GarmentPalettePixel(
            red: 105,
            green: 72,
            blue: 48,
            x: 0.5,
            y: 0.75,
            isStrongForegroundEvidence: true
        ), count: 600)
        let result = GarmentColorPaletteEngine.extractPalette(
            from: tanWall + brownPants,
            source: .garmentCrop,
            backgroundFamilyShares: ["brown": 0.75],
            confidenceEvidenceSatisfied: true,
            confidenceReason: "test foreground evidence"
        )

        XCTAssertTrue(result.palette.contains { FashionColorFamilyCatalog.family(for: $0) == "brown" })
        let protectedBrown = result.debug.clusterWeightDecisions.first {
            FashionColorFamilyCatalog.family(for: $0.name) == "brown" &&
                $0.foregroundConcentration >= 0.35 && !$0.downWeighted
        }
        let downWeightedTan = result.debug.clusterWeightDecisions.first {
            FashionColorFamilyCatalog.family(for: $0.name) == "brown" &&
                $0.foregroundConcentration < 0.35 && $0.downWeighted
        }
        XCTAssertNotNil(protectedBrown, "Strong eroded-foreground evidence must preserve genuinely brown pants.")
        XCTAssertNotNil(downWeightedTan, "Weak foreground concentration must dethrone the tan wall.")
        XCTAssertTrue(result.debug.debugDescription.contains("foregroundConcentration="))
    }

    func testFlatLayPaletteRegionDiscoveryRunsAfterAcceptanceWithoutChangingGate() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        XCTAssertTrue(source.contains("private func paletteRegionBoxes("))
        XCTAssertTrue(source.contains("guard !validation.isPersonScan else"))
        XCTAssertFalse(source.contains("paletteRegionDiscovery=flatLayAlways"))
        XCTAssertTrue(source.contains("let paletteBoxes = paletteRegionBoxes("))
    }

    func testConfidenceRequiresCorroborationOrStrongStandaloneEvidence() {
        let first = GarmentPaletteSampleCandidate(
            samples: [], tier: .saliencyCrop, source: .saliencyCrop,
            maskingApplied: true, garmentSampleCount: 1_000, familyShares: ["blue": 0.7]
        )
        let second = GarmentPaletteSampleCandidate(
            samples: [], tier: .foregroundSubject, source: .foregroundSubject,
            maskingApplied: true, garmentSampleCount: 900, familyShares: ["blue": 0.6]
        )
        let corroborated = GarmentPaletteSourceSelector.select([first, second])
        XCTAssertTrue(corroborated.winnerIsCorroborated)
        XCTAssertTrue(corroborated.hasConfidenceEvidence)

        let strong = GarmentPaletteSampleCandidate(
            samples: [], tier: .foregroundSubject, source: .garmentCrop,
            maskingApplied: true, garmentSampleCount: 1_500, familyShares: ["blue": 0.7]
        )
        let standalone = GarmentPaletteSourceSelector.select([strong])
        XCTAssertTrue(standalone.winnerIsStrongStandalone)
        XCTAssertTrue(standalone.hasConfidenceEvidence)
    }

    func testDarkDenimUnderShadePrefersBlueFamilyButTrueBlackStaysNeutral() {
        let denim = Array(repeating: GarmentPalettePixel(
            red: 70,
            green: 76,
            blue: 94,
            isStrongForegroundEvidence: true
        ), count: 700)
        let denimResult = GarmentColorPaletteEngine.extractPalette(
            from: denim,
            source: .garmentCrop,
            confidenceEvidenceSatisfied: true
        )
        XCTAssertEqual(FashionColorFamilyCatalog.family(for: denimResult.palette.first ?? ""), "blue")
        XCTAssertTrue(denimResult.debug.namingCalibrationDecisions.contains { $0.contains("darkChromaticPreference=") })

        let black = Array(repeating: GarmentPalettePixel(
            red: 25,
            green: 25,
            blue: 28,
            isStrongForegroundEvidence: true
        ), count: 700)
        let blackResult = GarmentColorPaletteEngine.extractPalette(
            from: black,
            source: .garmentCrop,
            confidenceEvidenceSatisfied: true
        )
        XCTAssertEqual(FashionColorFamilyCatalog.family(for: blackResult.palette.first ?? ""), "neutral")
    }

    func testBrightRegionIlluminantCorrectsWarmBrownOliveAndPinkReflectedBlue() {
        func palette(
            garment: (UInt8, UInt8, UInt8),
            reference: (UInt8, UInt8, UInt8)
        ) -> (palette: [String], debug: GarmentPaletteDebugSnapshot) {
            let samples = Array(repeating: GarmentPalettePixel(
                red: garment.0,
                green: garment.1,
                blue: garment.2,
                isStrongForegroundEvidence: true
            ), count: 700)
            let borderPositions = [(0.04, 0.50), (0.96, 0.50), (0.50, 0.04), (0.50, 0.96)]
            let references = borderPositions.flatMap { x, y in
                Array(repeating: GarmentPalettePixel(
                    red: reference.0,
                    green: reference.1,
                    blue: reference.2,
                    x: x,
                    y: y,
                    isInsidePersonMask: false
                ), count: 25)
            }
            let result = GarmentColorPaletteEngine.extractPalette(
                from: samples,
                source: .garmentCrop,
                illuminantReferenceSamples: references,
                confidenceEvidenceSatisfied: true
            )
            return (result.palette, result.debug)
        }

        let brown = palette(garment: (125, 75, 48), reference: (230, 190, 155))
        XCTAssertEqual(brown.palette.first, "brown")
        XCTAssertFalse(brown.palette.contains("chocolate"))

        let olive = palette(garment: (160, 145, 55), reference: (230, 190, 155))
        XCTAssertEqual(olive.palette.first, "olive")
        XCTAssertEqual(FashionColorFamilyCatalog.family(for: olive.palette.first ?? ""), "green")

        let reflectedBlue = palette(garment: (180, 165, 205), reference: (230, 175, 200))
        XCTAssertGreaterThanOrEqual(FashionColorCatalog.saturation(red: 180, green: 165, blue: 205), 0.08)
        XCTAssertEqual(reflectedBlue.palette.first, "light blue")
        XCTAssertTrue(reflectedBlue.debug.illuminantReference.contains("bright-region"))
    }

    func testPreCorrectionNeutralityGuardKeepsGrayTeeNeutralUnderAcceptedWarmReference() {
        let warmReference = [(0.04, 0.50), (0.96, 0.50), (0.50, 0.04), (0.50, 0.96)].flatMap { x, y in
            Array(repeating: GarmentPalettePixel(
                red: 227,
                green: 206,
                blue: 172,
                x: x,
                y: y,
                isInsidePersonMask: false
            ), count: 25)
        }

        for gray in [150, 165] {
            let samples = Array(repeating: GarmentPalettePixel(
                red: UInt8(gray),
                green: UInt8(gray),
                blue: UInt8(gray),
                isStrongForegroundEvidence: true
            ), count: 700)
            let result = GarmentColorPaletteEngine.extractPalette(
                from: samples,
                source: .garmentCrop,
                illuminantReferenceSamples: warmReference,
                confidenceEvidenceSatisfied: true
            )

            XCTAssertTrue(result.debug.illuminantReference.contains("bright-region accepted"))
            XCTAssertEqual(
                FashionColorFamilyCatalog.family(for: result.palette.first ?? ""),
                "neutral",
                "Gray \(gray) should not become blue after accepted warm correction."
            )
        }
    }

    func testPreCorrectionNeutralityGuardMatchesFullAndFastFamilyPaths() {
        let warmReference = [(0.04, 0.50), (0.96, 0.50), (0.50, 0.04), (0.50, 0.96)].flatMap { x, y in
            Array(repeating: GarmentPalettePixel(
                red: 227,
                green: 206,
                blue: 172,
                x: x,
                y: y,
                isInsidePersonMask: false
            ), count: 25)
        }
        let samples = Array(repeating: GarmentPalettePixel(
            red: 150,
            green: 150,
            blue: 150,
            isStrongForegroundEvidence: true
        ), count: 700)
        let full = GarmentColorPaletteEngine.colorFamilyShares(
            in: samples,
            allowsSkinExclusion: false,
            source: .garmentCrop,
            illuminantReferenceSamples: warmReference
        )
        let fast = GarmentColorPaletteEngine.fastCandidateFamilyShares(
            in: samples,
            allowsSkinExclusion: false,
            illuminantReferenceSamples: warmReference
        )

        XCTAssertEqual(
            GarmentPaletteSourceSelector.credibleFamilies(from: full),
            GarmentPaletteSourceSelector.credibleFamilies(from: fast)
        )
        XCTAssertEqual(full.max(by: { $0.value < $1.value })?.key, "neutral")
        XCTAssertEqual(fast.max(by: { $0.value < $1.value })?.key, "neutral")
    }

    func testPreCorrectionNeutralityGuardDocumentsUltraPaleBlueBoundary() {
        let guarded = FashionColorCatalog.namingEvaluation(
            red: 136,
            green: 149,
            blue: 169,
            hasSpatialEvidence: true,
            preCorrectionSaturation: 0.079
        )

        XCTAssertEqual(
            FashionColorFamilyCatalog.family(for: guarded.contributions.first?.name ?? ""),
            "neutral"
        )
    }

    func testGreenDominantBrightReferenceFallsBackAndKeepsOliveGreen() {
        let olive = Array(repeating: GarmentPalettePixel(
            red: 160,
            green: 145,
            blue: 55,
            isStrongForegroundEvidence: true
        ), count: 700)
        let borderPositions = [(0.04, 0.50), (0.96, 0.50), (0.50, 0.04), (0.50, 0.96)]
        let greenDominantReference = borderPositions.flatMap { x, y in
            Array(repeating: GarmentPalettePixel(
                red: 192,
                green: 224,
                blue: 213,
                x: x,
                y: y,
                isInsidePersonMask: false
            ), count: 25)
        }

        let result = GarmentColorPaletteEngine.extractPalette(
            from: olive,
            source: .garmentCrop,
            illuminantReferenceSamples: greenDominantReference,
            confidenceEvidenceSatisfied: true
        )

        XCTAssertEqual(FashionColorFamilyCatalog.family(for: result.palette.first ?? ""), "green")
        XCTAssertFalse(result.palette.contains("mustard"))
        XCTAssertTrue(result.debug.illuminantReference.contains("green-dominant reference"))
        XCTAssertTrue(result.debug.illuminantReference.contains("fallback=garment-gray-world"))
    }

    func testCorroboratedWarmReferenceStillKeepsOliveInGreenFamily() {
        let olive = Array(repeating: GarmentPalettePixel(
            red: 160,
            green: 145,
            blue: 55,
            isStrongForegroundEvidence: true
        ), count: 700)
        let warmReference = [(0.04, 0.50), (0.96, 0.50), (0.50, 0.04), (0.50, 0.96)].flatMap { x, y in
            Array(repeating: GarmentPalettePixel(
                red: 230,
                green: 190,
                blue: 155,
                x: x,
                y: y,
                isInsidePersonMask: false
            ), count: 25)
        }
        let result = GarmentColorPaletteEngine.extractPalette(
            from: olive,
            source: .garmentCrop,
            illuminantReferenceSamples: warmReference,
            confidenceEvidenceSatisfied: true
        )

        XCTAssertEqual(result.palette.first, "olive")
        XCTAssertTrue(result.debug.illuminantReference.contains("bright-region accepted"))
    }

    func testCorroboratedWarmReferenceKeepsBrownOutOfChocolate() {
        let brown = Array(repeating: GarmentPalettePixel(
            red: 125,
            green: 75,
            blue: 48,
            isStrongForegroundEvidence: true
        ), count: 700)
        let warmReference = [(0.04, 0.50), (0.96, 0.50), (0.50, 0.04), (0.50, 0.96)].flatMap { x, y in
            Array(repeating: GarmentPalettePixel(
                red: 230,
                green: 190,
                blue: 155,
                x: x,
                y: y,
                isInsidePersonMask: false
            ), count: 25)
        }
        let result = GarmentColorPaletteEngine.extractPalette(
            from: brown,
            source: .garmentCrop,
            illuminantReferenceSamples: warmReference,
            confidenceEvidenceSatisfied: true
        )

        XCTAssertEqual(result.palette.first, "brown")
        XCTAssertFalse(result.palette.contains("chocolate"))
    }

    func testUnsupportedBlueCastLightGrayStaysNeutralInTransitionBand() {
        let gray = Array(repeating: GarmentPalettePixel(
            red: 170,
            green: 180,
            blue: 190
        ), count: 700)
        let result = GarmentColorPaletteEngine.extractPalette(
            from: gray,
            source: .saliencyCrop,
            confidenceEvidenceSatisfied: true
        )

        XCTAssertEqual(FashionColorFamilyCatalog.family(for: result.palette.first ?? ""), "neutral")
    }

    func testForegroundEvidencePreservesGenuinePaleBlue() {
        let paleBlue = Array(repeating: GarmentPalettePixel(
            red: 170,
            green: 200,
            blue: 215,
            isStrongForegroundEvidence: true
        ), count: 700)
        let result = GarmentColorPaletteEngine.extractPalette(
            from: paleBlue,
            source: .saliencyCrop,
            confidenceEvidenceSatisfied: true
        )

        XCTAssertEqual(result.palette.first, "light blue")
    }

    func testStructuredOutfitFactsUsesCompletedAnalysisPaletteWithoutSecondExtraction() throws {
        let scanSource = try projectSource("StyleMatchAI/ScanView.swift")
        let functionStart = try XCTUnwrap(scanSource.range(of: "private func structuredOutfitFacts(for analysis:"))
        let functionTail = scanSource[functionStart.lowerBound...]
        let functionEnd = try XCTUnwrap(functionTail.range(of: "\n    private func", options: [], range: functionTail.index(after: functionStart.lowerBound)..<functionTail.endIndex))
        let body = functionTail[..<functionEnd.lowerBound]

        XCTAssertFalse(body.contains("garmentColorDetection()"))
        XCTAssertTrue(body.contains("garmentColors: analysis.colorPaletteConfidence == .confident ? analysis.colorPalette : []"))
        XCTAssertTrue(body.contains("confidence: analysis.colorPaletteDetectionConfidence"))
        XCTAssertTrue(body.contains("? analysis.colorPaletteNotes"))
    }

    func testNamingCalibrationProtectsEstablishedColorWins() {
        let cases: [((UInt8, UInt8, UInt8), String)] = [
            ((235, 205, 55), "yellow"),
            ((225, 120, 45), "orange"),
            ((25, 42, 78), "navy"),
            ((82, 32, 42), "maroon"),
            ((14, 14, 16), "black"),
            ((112, 72, 45), "brown"),
            ((125, 125, 125), "gray")
        ]
        for (rgb, expected) in cases {
            XCTAssertEqual(
                FashionColorCatalog.nearestName(red: rgb.0, green: rgb.1, blue: rgb.2),
                expected,
                "Expected \(rgb) to remain \(expected)."
            )
        }
    }

    func testMemoizedCandidateFamilyNamingCoversRepresentativeFamilies() {
        let cases: [(UInt8, UInt8, UInt8)] = [
            (255, 255, 255),
            (150, 150, 150),
            (48, 49, 52),
            (95, 100, 120),
            (190, 155, 110),
            (140, 126, 112),
            (45, 78, 180),
            (172, 208, 226),
            (50, 145, 75),
            (115, 112, 55),
            (235, 205, 55),
            (225, 120, 45),
            (205, 45, 50),
            (225, 125, 165),
            (112, 65, 150)
        ]

        for rgb in cases {
            let fullFamily = FashionColorCatalog.nameContributions(
                red: rgb.0,
                green: rgb.1,
                blue: rgb.2,
                hasSpatialEvidence: false
            )
            .reduce(into: [String: Double]()) { result, contribution in
                result[FashionColorFamilyCatalog.family(for: contribution.name), default: 0] += contribution.weight
            }
            .max {
                if $0.value == $1.value { return $0.key > $1.key }
                return $0.value < $1.value
            }?.key

            XCTAssertEqual(
                GarmentColorPaletteEngine.fastCandidateFamily(red: rgb.0, green: rgb.1, blue: rgb.2),
                fullFamily,
                "Expected \(rgb) to match full family naming."
            )
        }
    }

    func testMemoizedCandidateFamilyNamingDoesNotCollapseOliveToBrown() {
        XCTAssertEqual(
            GarmentColorPaletteEngine.fastCandidateFamily(red: 115, green: 112, blue: 55),
            "green"
        )
        XCTAssertEqual(
            GarmentColorPaletteEngine.fastCandidateFamily(red: 112, green: 72, blue: 45),
            "brown"
        )
    }

    func testFastCandidateFamilySharesMemoizesRepeatedCorrectedColors() {
        let memo = GarmentColorPaletteEngine.CandidateFamilyMemo()
        let fixture = Array(repeating: GarmentPalettePixel(
            red: 115,
            green: 112,
            blue: 55,
            isStrongForegroundEvidence: true
        ), count: 2)

        _ = GarmentColorPaletteEngine.fastCandidateFamilyShares(
            in: fixture,
            allowsSkinExclusion: false,
            memo: memo
        )

        XCTAssertEqual(memo.evaluationCount, 1)
    }

    func testFastCandidateFamilyMemoSeparatesPreCorrectionNeutralState() {
        let memo = GarmentColorPaletteEngine.CandidateFamilyMemo()
        let warmReference = [(0.04, 0.50), (0.96, 0.50), (0.50, 0.04), (0.50, 0.96)].flatMap { x, y in
            Array(repeating: GarmentPalettePixel(
                red: 227,
                green: 206,
                blue: 172,
                x: x,
                y: y,
                isInsidePersonMask: false
            ), count: 25)
        }

        let guarded = GarmentColorPaletteEngine.fastCandidateFamilyShares(
            in: [GarmentPalettePixel(red: 150, green: 150, blue: 150, isStrongForegroundEvidence: true)],
            allowsSkinExclusion: false,
            illuminantReferenceSamples: warmReference,
            memo: memo
        )
        let unguarded = GarmentColorPaletteEngine.fastCandidateFamilyShares(
            in: [GarmentPalettePixel(red: 135, green: 147, blue: 173, isStrongForegroundEvidence: true)],
            allowsSkinExclusion: false,
            memo: memo
        )

        XCTAssertEqual(memo.evaluationCount, 2)
        XCTAssertEqual(guarded.max(by: { $0.value < $1.value })?.key, "neutral")
        XCTAssertEqual(unguarded.max(by: { $0.value < $1.value })?.key, "blue")
    }

    func testFastCandidateFamilySharesPreserveCredibleSetForFixture() {
        let fixture = Array(repeating: GarmentPalettePixel(
            red: 115,
            green: 112,
            blue: 55,
            isStrongForegroundEvidence: true
        ), count: 640)
        + Array(repeating: GarmentPalettePixel(
            red: 235,
            green: 205,
            blue: 55,
            isStrongForegroundEvidence: true
        ), count: 260)
        + Array(repeating: GarmentPalettePixel(
            red: 238,
            green: 225,
            blue: 190,
            isStrongForegroundEvidence: true
        ), count: 80)

        let full = GarmentColorPaletteEngine.colorFamilyShares(
            in: fixture,
            allowsSkinExclusion: false,
            source: .garmentCrop
        )
        let fast = GarmentColorPaletteEngine.fastCandidateFamilyShares(
            in: fixture,
            allowsSkinExclusion: false
        )

        XCTAssertEqual(
            GarmentPaletteSourceSelector.credibleFamilies(from: full),
            GarmentPaletteSourceSelector.credibleFamilies(from: fast)
        )
    }

    func testFastCandidateSharesPreserveSelectorOutcomeForCorroboratedWarmBandFixture() {
        let oliveCrop = Array(repeating: GarmentPalettePixel(
            red: 115,
            green: 112,
            blue: 55,
            isStrongForegroundEvidence: true
        ), count: 900)
        let oliveForeground = Array(repeating: GarmentPalettePixel(
            red: 160,
            green: 145,
            blue: 55,
            isStrongForegroundEvidence: true
        ), count: 760)
        let yellowSaliency = Array(repeating: GarmentPalettePixel(
            red: 235,
            green: 205,
            blue: 55,
            isStrongForegroundEvidence: true
        ), count: 620)

        assertFastCandidateSelectionMatchesFull([
            (.foregroundSubject, .garmentCrop, oliveCrop),
            (.foregroundSubject, .foregroundSubject, oliveForeground),
            (.saliencyCrop, .saliencyCrop, yellowSaliency)
        ])
    }

    func testFastCandidateSharesPreserveSelectorOutcomeForDisagreementFixture() {
        let blue = Array(repeating: GarmentPalettePixel(
            red: 45,
            green: 78,
            blue: 180,
            isStrongForegroundEvidence: true
        ), count: 900)
        let brown = Array(repeating: GarmentPalettePixel(
            red: 112,
            green: 72,
            blue: 45,
            isStrongForegroundEvidence: true
        ), count: 850)

        let selections = assertFastCandidateSelectionMatchesFull([
            (.foregroundSubject, .foregroundSubject, blue),
            (.personSegmentation, .personSegmentation, brown)
        ])
        XCTAssertTrue(selections.full.disagreement)
        XCTAssertEqual(selections.full.confidenceReason, "credible sources disagree")
    }

    func testScanPassesFlatLayBorderSamplesIntoIlluminantCalibration() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        XCTAssertTrue(source.contains("let backgroundSamples = prefersPersonMask ? [] : paletteBackgroundSamples"))
        XCTAssertTrue(source.contains("illuminantReferenceSamples: backgroundSamples"))
        XCTAssertFalse(source.contains("namingCalibration="))
    }

    #if DEBUG
    func testStructuredPaletteDiagnosticIsObservationalAndRetainsEveryCandidate() throws {
        let blue = Array(repeating: GarmentPalettePixel(
            red: 35,
            green: 70,
            blue: 170,
            isStrongForegroundEvidence: true
        ), count: 1_600)
        let red = Array(repeating: GarmentPalettePixel(
            red: 190,
            green: 45,
            blue: 50,
            isStrongForegroundEvidence: true
        ), count: 300)
        let candidates = [
            GarmentPaletteSampleCandidate(
                samples: blue,
                tier: .foregroundSubject,
                source: .foregroundSubject,
                maskingApplied: true,
                garmentSampleCount: blue.count,
                familyShares: ["blue": 1]
            ),
            GarmentPaletteSampleCandidate(
                samples: red,
                tier: .saliencyCrop,
                source: .saliencyCrop,
                maskingApplied: true,
                garmentSampleCount: red.count,
                familyShares: ["red": 1]
            )
        ]
        let selection = GarmentPaletteSourceSelector.select(candidates)
        let extraction = GarmentColorPaletteEngine.extractPalette(
            from: blue,
            source: .foregroundSubject,
            allowsSkinExclusion: false,
            confidenceSampleCount: blue.count,
            confidenceEvidenceSatisfied: true,
            confidenceReason: selection.confidenceReason
        )
        let paletteBeforeDiagnostics = extraction.palette
        let confidenceBeforeDiagnostics = extraction.confidence
        let finalPaletteBeforeDiagnostics = extraction.debug.finalPalette

        let record = GarmentPaletteDiagnosticRecord.make(
            candidates: candidates,
            selection: selection,
            extraction: extraction,
            chosenSource: .foregroundSubject,
            maskTier: .foregroundSubject,
            flatLayRegionDiscoveryRan: true,
            timestamp: Date(timeIntervalSince1970: 1_725_000_000),
            recordID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        )
        let encoded = try GarmentPaletteDiagnosticRecord.encodedData(for: record)
        let decoded = try JSONDecoder.paletteDiagnosticDecoder.decode(
            GarmentPaletteDiagnosticRecord.self,
            from: encoded
        )

        XCTAssertEqual(decoded, record)
        XCTAssertEqual(record.candidatesRanked.count, 2)
        XCTAssertEqual(record.candidatesRanked.first?.rank, 1)
        XCTAssertEqual(record.candidatesRanked.last?.selectorDisposition, "notRankedBelowMinimumSampleThreshold")
        XCTAssertEqual(record.chosenSource, GarmentPaletteSource.foregroundSubject.rawValue)
        XCTAssertEqual(record.maskCropType, GarmentMaskTier.foregroundSubject.rawValue)
        XCTAssertTrue(record.flatLayRegionDiscoveryRan)
        XCTAssertFalse(record.clusterRetentionDecisions.isEmpty)
        XCTAssertEqual(extraction.palette, paletteBeforeDiagnostics)
        XCTAssertEqual(extraction.confidence, confidenceBeforeDiagnostics)
        XCTAssertEqual(extraction.debug.finalPalette, finalPaletteBeforeDiagnostics)
    }

    func testPaletteDiagnosticChannelIsDebugOnlyAndDoesNotWeakenScanViewGuard() throws {
        let paletteSource = try projectSource("StyleMatchAI/GarmentColorPaletteEngine.swift")
        let scanSource = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(paletteSource.contains("#if DEBUG\nstruct GarmentPaletteDiagnosticRecord"))
        XCTAssertTrue(paletteSource.contains("StyleMatchDiagnostics"))
        XCTAssertTrue(paletteSource.contains("Palette"))
        XCTAssertTrue(paletteSource.contains("isExcludedFromBackup = true"))
        XCTAssertTrue(paletteSource.contains("maximumRecordCount = 40"))
        XCTAssertTrue(paletteSource.contains("maximumStoredBytes = 2 * 1_024 * 1_024"))
        XCTAssertFalse(scanSource.contains("candidatesRanked=["))
        XCTAssertFalse(scanSource.contains("familyShares=["))
        XCTAssertFalse(scanSource.contains("disagreement=\\("))
    }

    func testPaletteDiagnosticChannelBoundsRetentionAndSupportsExplicitDebugClear() throws {
        let fileManager = FileManager.default
        let documentsDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("palette-diagnostic-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: documentsDirectory) }
        try fileManager.createDirectory(at: documentsDirectory, withIntermediateDirectories: true)

        for index in 0..<(GarmentPaletteDiagnosticChannel.maximumRecordCount + 7) {
            let record = GarmentPaletteDiagnosticRecord(
                schemaVersion: GarmentPaletteDiagnosticRecord.currentSchemaVersion,
                recordID: UUID(),
                timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
                chosenSource: GarmentPaletteSource.garmentCrop.rawValue,
                candidatesRanked: [],
                clusterRetentionDecisions: [],
                finalPalette: ["navy", "red"],
                confidence: 72,
                confidenceLevel: GarmentPaletteConfidence.confident.rawValue,
                confidenceReason: "test fixture",
                maskCropType: GarmentMaskTier.foregroundSubject.rawValue,
                flatLayRegionDiscoveryRan: true
            )
            GarmentPaletteDiagnosticChannel.record(
                record,
                in: documentsDirectory,
                fileManager: fileManager
            )
        }

        let diagnosticsRoot = documentsDirectory
            .appendingPathComponent("StyleMatchDiagnostics", isDirectory: true)
        let paletteDirectory = diagnosticsRoot
            .appendingPathComponent("Palette", isDirectory: true)
        let files = try fileManager.contentsOfDirectory(
            at: paletteDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        )
        let storedBytes = try files.reduce(into: 0) { total, url in
            total += try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        }

        XCTAssertLessThanOrEqual(files.count, GarmentPaletteDiagnosticChannel.maximumRecordCount)
        XCTAssertLessThanOrEqual(storedBytes, GarmentPaletteDiagnosticChannel.maximumStoredBytes)
        #if os(iOS)
        XCTAssertEqual(
            try diagnosticsRoot.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup,
            true
        )
        #else
        // Host SwiftPM runs on macOS, where backup exclusion is intentionally
        // not a filesystem guarantee; iOS device coverage owns that assertion.
        XCTAssertNotNil(try diagnosticsRoot.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup)
        #endif

        GarmentPaletteDiagnosticChannel.clear(
            in: documentsDirectory,
            fileManager: fileManager
        )
        XCTAssertFalse(fileManager.fileExists(atPath: diagnosticsRoot.path))
    }

    func testPaletteDiagnosticSchemaCannotContainRawPrivateInputs() throws {
        let record = GarmentPaletteDiagnosticRecord(
            schemaVersion: GarmentPaletteDiagnosticRecord.currentSchemaVersion,
            recordID: UUID(),
            timestamp: Date(timeIntervalSince1970: 1_725_000_000),
            chosenSource: GarmentPaletteSource.garmentCrop.rawValue,
            candidatesRanked: [],
            clusterRetentionDecisions: [],
            finalPalette: ["navy", "red"],
            confidence: 72,
            confidenceLevel: GarmentPaletteConfidence.confident.rawValue,
            confidenceReason: "credible sources agree",
            maskCropType: GarmentMaskTier.foregroundSubject.rawValue,
            flatLayRegionDiscoveryRan: true
        )
        let json = String(
            decoding: try GarmentPaletteDiagnosticRecord.encodedData(for: record),
            as: UTF8.self
        ).lowercased()

        for forbiddenKey in [
            "rawimage", "imagebytes", "ocrtext", "prompt", "username",
            "employer", "preciselocation", "profile"
        ] {
            XCTAssertFalse(json.contains(forbiddenKey))
        }
    }
    #endif

    @discardableResult
    private func assertFastCandidateSelectionMatchesFull(
        _ fixtures: [(tier: GarmentMaskTier, source: GarmentPaletteSource, samples: [GarmentPalettePixel])],
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> (
        full: GarmentPaletteSourceSelector.Selection,
        fast: GarmentPaletteSourceSelector.Selection
    ) {
        let fastMemo = GarmentColorPaletteEngine.CandidateFamilyMemo()
        let fullCandidates = fixtures.map { fixture in
            GarmentPaletteSampleCandidate(
                samples: fixture.samples,
                tier: fixture.tier,
                source: fixture.source,
                maskingApplied: true,
                garmentSampleCount: fixture.samples.count,
                familyShares: GarmentColorPaletteEngine.colorFamilyShares(
                    in: fixture.samples,
                    allowsSkinExclusion: false,
                    source: fixture.source
                )
            )
        }
        let fastCandidates = fixtures.map { fixture in
            GarmentPaletteSampleCandidate(
                samples: fixture.samples,
                tier: fixture.tier,
                source: fixture.source,
                maskingApplied: true,
                garmentSampleCount: fixture.samples.count,
                familyShares: GarmentColorPaletteEngine.fastCandidateFamilyShares(
                    in: fixture.samples,
                    allowsSkinExclusion: false,
                    memo: fastMemo
                )
            )
        }

        let full = GarmentPaletteSourceSelector.select(fullCandidates)
        let fast = GarmentPaletteSourceSelector.select(fastCandidates)
        XCTAssertEqual(fast.candidate?.source, full.candidate?.source, file: file, line: line)
        XCTAssertEqual(fast.candidate?.tier, full.candidate?.tier, file: file, line: line)
        XCTAssertEqual(fast.disagreement, full.disagreement, file: file, line: line)
        XCTAssertEqual(fast.confidenceReason, full.confidenceReason, file: file, line: line)
        return (full, fast)
    }
}

#if DEBUG
private extension JSONDecoder {
    static var paletteDiagnosticDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
#endif
