import XCTest
@testable import StyleMatchPro

final class Build16PaletteTruthTests: XCTestCase {
    private func projectSource(_ relativePath: String, filePath: String = #filePath) throws -> String {
        let root = URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
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
        XCTAssertTrue(source.contains("confidenceLevel: analysis.colorPaletteConfidence.rawValue"))
        XCTAssertTrue(source.contains("Do not assert specific garment colors"))
    }

    func testExactFingerprintReusesStoredDeterministicInputsWithMigrationSafeDecode() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")

        XCTAssertTrue(source.contains("let storedInputs = exactStoredScan?.deterministicInputs"))
        XCTAssertTrue(source.contains("let colorPalette = storedInputs?.colorPalette ?? colorDetection.garmentColors"))
        XCTAssertTrue(source.contains("let scoringLabels = storedInputs?.labels ?? labels"))
        XCTAssertTrue(source.contains("decodeIfPresent(StoredDeterministicScorerInputs.self"))
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
        XCTAssertTrue(source.contains("garmentCrop sampling=skipped reason=noUsableForegroundIntersection"))
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
        XCTAssertTrue(candidateBody.contains("strongCoverage="))
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
        XCTAssertTrue(source.contains("candidatesRanked=["))
        XCTAssertTrue(source.contains("familyShares=["))
        XCTAssertTrue(source.contains("disagreement=\\(selection.disagreement)"))
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

        XCTAssertTrue(source.contains("garmentCrop sampling=skipped reason=noUsableForegroundIntersection"))
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
        XCTAssertTrue(source.contains("paletteRegionDiscovery=flatLayAlways"))
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
        XCTAssertEqual(reflectedBlue.palette.first, "light blue")
        XCTAssertTrue(reflectedBlue.debug.illuminantReference.contains("bright-region"))
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

    func testScanPassesFlatLayBorderSamplesIntoIlluminantCalibration() throws {
        let source = try projectSource("StyleMatchAI/ScanView.swift")
        XCTAssertTrue(source.contains("let backgroundSamples = prefersPersonMask ? [] : paletteBackgroundSamples"))
        XCTAssertTrue(source.contains("illuminantReferenceSamples: backgroundSamples"))
        XCTAssertTrue(source.contains("namingCalibration="))
    }
}
