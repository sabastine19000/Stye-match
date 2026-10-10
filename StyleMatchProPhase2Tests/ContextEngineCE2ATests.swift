import XCTest
@testable import StyleMatchPro

final class ContextEngineCE2ATests: XCTestCase {
    private let completedAt = Date(timeIntervalSince1970: 1_753_200_000)

    func testCE2A01CasualStyleCanProposeFactoryWorkWithoutChangingStyle() throws {
        let snapshot = try infer(makeInput(
            category: .workUniform,
            occasion: .work,
            environment: "Factory",
            evidence: [.construction, .branding]
        ))

        XCTAssertEqual(snapshot.detectedStyle.value, "Casual")
        XCTAssertEqual(snapshot.outfitPurpose.value, .factoryManufacturing)
        XCTAssertEqual(snapshot.outfitPurpose.confirmationState, .proposed)
        XCTAssertEqual(snapshot.authoritativeScore, 80)
    }

    func testCE2A02CasualStyleCanProposeOfficePurpose() throws {
        let snapshot = try infer(makeInput(
            category: .businessCasual,
            occasion: .work,
            environment: "Office",
            evidence: [.silhouette]
        ))

        XCTAssertEqual(snapshot.detectedStyle.value, "Casual")
        XCTAssertEqual(snapshot.outfitPurpose.value, .businessCasualOffice)
        XCTAssertEqual(snapshot.environmentType.value, .office)
    }

    func testCE2A03WorkAloneDoesNotInventWorkplace() throws {
        let snapshot = try infer(makeInput(
            category: .casualWear,
            occasion: .work,
            evidence: [.silhouette]
        ))

        XCTAssertEqual(snapshot.outfitPurpose.value, .otherUncertain)
        XCTAssertEqual(snapshot.workplaceProfile.value, .otherUncertain)
        XCTAssertEqual(snapshot.workplaceSuitability.level, .uncertain)
    }

    func testCE2A04UniformRequiresConfirmationAtHighConfidence() throws {
        let snapshot = try infer(makeInput(
            category: .workUniform,
            confidence: 0.99,
            occasion: .work,
            evidence: [.construction, .branding]
        ))

        XCTAssertEqual(snapshot.outfitPurpose.value, .factoryManufacturing)
        XCTAssertEqual(snapshot.outfitPurpose.confirmationState, .proposed)
        XCTAssertTrue(snapshot.missingEvidence.contains {
            $0.id == "missing.confirmation.factoryManufacturing"
        })
    }

    func testCE2A05RejectedUniformDoesNotPromoteAlternative() throws {
        let snapshot = try infer(makeInput(
            category: .workUniform,
            occasion: .work,
            evidence: [.construction, .branding],
            rejected: [.factoryManufacturing]
        ))

        XCTAssertEqual(snapshot.outfitPurpose.value, .otherUncertain)
        XCTAssertEqual(snapshot.garmentCategory.value, .workUniform)
        XCTAssertEqual(snapshot.authoritativeScore, 80)
    }

    func testCE2A06FactoryBackgroundAloneDoesNotCreateUniformPurpose() throws {
        let snapshot = try infer(makeInput(
            category: .casualWear,
            occasion: nil,
            environment: "Factory",
            evidence: [.silhouette]
        ))

        XCTAssertEqual(snapshot.environmentType.value, .otherUncertain)
        XCTAssertEqual(snapshot.outfitPurpose.value, .otherUncertain)
    }

    func testCE2A07AmbiguousOCRBecomesGenericPresenceOnly() throws {
        let snapshot = try infer(makeInput(
            category: .otherUncertain,
            evidence: [.visibleText],
            rawSummary: "Alex Example Employee 4107"
        ))
        let encoded = try json(snapshot)

        XCTAssertTrue(snapshot.evidence.contains { $0.kind == .textPresence })
        XCTAssertFalse(encoded.contains("Alex Example"))
        XCTAssertFalse(encoded.contains("4107"))
    }

    func testCE2A08ScrubsProposeHealthcareAndRequireConfirmation() throws {
        let snapshot = try infer(makeInput(
            category: .medicalScrubs,
            occasion: .work,
            evidence: [.construction, .branding]
        ))

        XCTAssertEqual(snapshot.outfitPurpose.value, .healthcare)
        XCTAssertEqual(snapshot.outfitPurpose.confirmationState, .proposed)
        XCTAssertEqual(snapshot.workplaceProfile.value, .healthcare)
        XCTAssertEqual(snapshot.workplaceSuitability.level, .uncertain)
    }

    func testCE2A09ConstructionWorkwearNeedsIndependentEvidence() throws {
        let snapshot = try infer(makeInput(
            category: .brandedWorkwear,
            occasion: .work,
            environment: "Outdoors",
            evidence: [.construction, .branding]
        ))

        XCTAssertEqual(snapshot.outfitPurpose.value, .construction)
        XCTAssertEqual(snapshot.outfitPurpose.confirmationState, .proposed)
        XCTAssertEqual(snapshot.safetySuitability.level, .uncertain)
    }

    func testCE2A10WeddingDressMeetsThresholdButRemainsProposed() throws {
        let input = makeInput(
            category: .weddingDress,
            confidence: 0.99,
            occasion: .weddingGuest,
            environment: "Event Venue",
            evidence: [.silhouette, .construction, .accessory]
        )
        let snapshot = try infer(input)

        XCTAssertEqual(snapshot.outfitPurpose.value, .weddingDress)
        XCTAssertEqual(snapshot.outfitPurpose.confirmationState, .proposed)
        XCTAssertNotEqual(snapshot.outfitPurpose.confirmationState, .confirmed)
    }

    func testCE2A11CasualDressUsesContextWithoutChangingCategory() throws {
        let snapshot = try infer(makeInput(
            category: .casualDress,
            occasion: .casualDay,
            evidence: [.silhouette]
        ))

        XCTAssertEqual(snapshot.garmentCategory.value, .casualDress)
        XCTAssertEqual(snapshot.outfitPurpose.value, .everydayCasual)
    }

    func testCE2A12AmbiguousOutfitFailsClosed() throws {
        let snapshot = try infer(makeInput(
            category: .otherUncertain,
            occasion: nil,
            evidence: [.uncertainty]
        ))

        XCTAssertEqual(snapshot.outfitPurpose.value, .otherUncertain)
        XCTAssertEqual(snapshot.outfitPurpose.confidence, .unknown)
        XCTAssertTrue(snapshot.missingEvidence.contains { $0.kind == .purpose })
    }

    func testCE2A13ConflictingOccasionDoesNotForcePurpose() throws {
        let snapshot = try infer(makeInput(
            category: .businessFormal,
            occasion: .gym,
            environment: "Gym",
            evidence: [.silhouette]
        ))

        XCTAssertEqual(snapshot.outfitPurpose.value, .otherUncertain)
        XCTAssertEqual(snapshot.occasionCompatibility.level, .uncertain)
    }

    func testCE2A14MissingWeatherIsExplicit() throws {
        let snapshot = try infer(makeInput(
            category: .casualDress,
            occasion: .casualDay
        ))

        XCTAssertEqual(snapshot.weatherSuitability.level, .uncertain)
        XCTAssertTrue(snapshot.missingEvidence.contains { $0.id == "missing.weather" })
    }

    func testCE2A15MissingOccasionIsExplicit() throws {
        let snapshot = try infer(makeInput(
            category: .businessCasual,
            occasion: nil,
            environment: "Office"
        ))

        XCTAssertEqual(snapshot.selectedOccasion.value, .otherUncertain)
        XCTAssertEqual(snapshot.occasionCompatibility.level, .uncertain)
        XCTAssertTrue(snapshot.missingEvidence.contains { $0.id == "missing.occasion" })
    }

    func testCE2A16SameScanConfirmedPurposeWins() throws {
        let input = makeInput(
            category: .casualWear,
            occasion: .work,
            confirmedPurpose: .remoteWork
        )
        let snapshot = try infer(input)

        XCTAssertEqual(snapshot.outfitPurpose.value, .remoteWork)
        XCTAssertEqual(snapshot.outfitPurpose.origin, .userConfirmed)
        XCTAssertEqual(snapshot.outfitPurpose.confirmationState, .confirmed)
        XCTAssertEqual(snapshot.userConfirmedPurpose, .remoteWork)
    }

    func testCE2A17RepeatedInferenceIsByteDeterministic() throws {
        let input = makeInput(
            category: .businessCasual,
            occasion: .work,
            environment: "Office",
            evidence: [.silhouette, .branding]
        )
        let first = try infer(input)
        let second = try infer(input)

        XCTAssertEqual(first, second)
        XCTAssertEqual(try encoded(first), try encoded(second))
    }

    func testCE2A18ScoreNeverMutates() throws {
        for score in [0, 74, 80, 100] {
            let snapshot = try infer(makeInput(score: score))
            XCTAssertEqual(snapshot.authoritativeScore, score)
        }
    }

    func testCE2A19BreakdownNeverMutates() throws {
        let breakdown = OutfitScoreBreakdown(
            colorHarmony: 25,
            patternBalance: 20,
            fitQuality: 13,
            occasionMatch: 6,
            accessoryUse: 6
        )
        let snapshot = try infer(makeInput(breakdown: breakdown))

        XCTAssertEqual(snapshot.authoritativeBreakdown, breakdown)
    }

    func testCE2A20SourceBoundaryContainsNoPersistenceWrites() throws {
        let sources = try ce2aSourceContents()
        let forbidden = [
            "UserDefaults", "FileManager", "Keychain", "CoreData",
            "NSManagedObject", ".write(", "setValue(", "synchronize()"
        ]
        for source in sources {
            for token in forbidden {
                XCTAssertFalse(source.contains(token), "CE2A contains \(token)")
            }
        }
    }

    func testCE2A21RawOCRBrandAndIdentityNeverEnterSnapshot() throws {
        let snapshot = try infer(makeInput(
            category: .brandedWorkwear,
            occasion: .work,
            evidence: [.visibleText, .branding],
            rawSummary: "Alex Example Northwind Textiles Badge 4107"
        ))
        let output = try json(snapshot)

        XCTAssertFalse(output.contains("Alex Example"))
        XCTAssertFalse(output.contains("Northwind"))
        XCTAssertFalse(output.contains("4107"))
        XCTAssertTrue(output.contains("raw text is not retained"))
    }

    func testCE2A22LegacyAdapterRemainsCompatible() throws {
        let analysis = makeAnalysis(
            category: .businessCasual,
            occasionLabel: "Work"
        )
        let before = try encoded(analysis)
        let legacy = LegacyContextAdapter.adapt(
            scanID: "legacy",
            completedAt: completedAt,
            analysis: analysis
        )

        XCTAssertEqual(try encoded(analysis), before)
        XCTAssertTrue(legacy.provenance.legacyFallbackUsed)
        XCTAssertEqual(legacy.outfitPurpose.value, .otherUncertain)
    }

    func testCE2A23StyleLabelsDoNotBecomeEnvironment() throws {
        for value in ["Business", "Casual", "Formal", "Professional", "Work"] {
            let snapshot = try infer(makeInput(environment: value))
            XCTAssertEqual(snapshot.environmentType.value, .otherUncertain)
        }
    }

    func testCE2A24BrandingAloneCannotEstablishPurpose() throws {
        let snapshot = try infer(makeInput(
            category: .brandedWorkwear,
            occasion: nil,
            evidence: [.branding]
        ))

        XCTAssertEqual(snapshot.outfitPurpose.value, .otherUncertain)
    }

    func testCE2A25OccasionAloneCannotEstablishPurpose() throws {
        for occasion in [Occasion.work, .weddingGuest, .gym] {
            let snapshot = try infer(makeInput(
                category: .otherUncertain,
                occasion: occasion,
                evidence: []
            ))
            XCTAssertEqual(snapshot.outfitPurpose.value, .otherUncertain)
        }
    }

    func testCE2A26CompetingCandidatesRemainUncertainInStableOrder() throws {
        let input = makeInput(
            category: .bridesmaidDress,
            occasion: .weddingGuest,
            environment: "Event Venue",
            evidence: [.silhouette, .branding]
        )
        let evidence = try infer(input).evidence
        let resolution = PurposeClassifier.resolve(
            input: input,
            environment: .eventVenue,
            evidence: evidence
        )

        XCTAssertEqual(resolution.value.value, .otherUncertain)
        XCTAssertEqual(resolution.candidates.map(\.purpose), [.weddingGuest, .weddingParty])
    }

    func testCE2A27UnknownFutureContractValuesFailClosed() throws {
        let origin = try JSONDecoder().decode(
            ContextValueOrigin.self,
            from: Data(#""futureOrigin""#.utf8)
        )
        let field = try JSONDecoder().decode(
            ContextProvenanceField.self,
            from: Data(#""futureField""#.utf8)
        )

        XCTAssertEqual(origin, .unknown)
        XCTAssertEqual(field, .outfitPurpose)
    }

    func testCE2A28InvalidInputsReturnTypedFailures() throws {
        XCTAssertEqual(
            failure(makeInput(scanID: "   ")),
            .invalidScanIdentity
        )
        XCTAssertEqual(
            failure(makeInput(score: 101)),
            .invalidScore
        )
        XCTAssertEqual(
            failure(makeInput(confidence: .nan)),
            .nonFiniteConfidence
        )
        let mismatch = makeInput(
            confirmedPurpose: .remoteWork,
            confirmationScanID: "different-scan"
        )
        XCTAssertEqual(failure(mismatch), .mismatchedPurposeConfirmation)
    }

    func testCE2A29FiniteConfidenceIsBoundedAndProvenanceIsCorrect() throws {
        let snapshot = try infer(makeInput(
            category: .businessCasual,
            confidence: 2,
            occasion: .work,
            environment: "Office",
            evidence: [.silhouette]
        ))

        XCTAssertLessThanOrEqual(snapshot.garmentCategory.confidence.value, 1)
        XCTAssertTrue(snapshot.provenance.entries.contains {
            $0.field == .garmentCategory && $0.source == .scanAuthoritative
        })
        XCTAssertTrue(snapshot.provenance.entries.contains {
            $0.field == .outfitPurpose && $0.source == .runtimeInferred
        })
        XCTAssertFalse(snapshot.provenance.legacyFallbackUsed)
    }

    func testCE2A30SuitabilityMetricsRemainIndependent() throws {
        let snapshot = try infer(makeInput(
            category: .workUniform,
            occasion: .work,
            evidence: [.construction, .branding],
            weather: makeWeather()
        ))

        XCTAssertEqual(snapshot.occasionCompatibility.level, .moderate)
        XCTAssertEqual(snapshot.workplaceSuitability.level, .uncertain)
        XCTAssertEqual(snapshot.weatherSuitability.level, .moderate)
        XCTAssertEqual(snapshot.safetySuitability.level, .uncertain)
        XCTAssertEqual(snapshot.authoritativeScore, 80)
    }

    func testCE2A31NoProductionConsumerAdoptsEngine() throws {
        let root = repositoryRoot().appendingPathComponent("StyleMatchAI")
        let files = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil
        )
        var references: [String] = []
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift",
                  !url.path.contains("/ContextEngine/") else {
                continue
            }
            let source = try String(contentsOf: url, encoding: .utf8)
            if source.contains("OutfitContextEngine") {
                references.append(url.lastPathComponent)
            }
        }
        XCTAssertEqual(references, [])
    }

    func testCE2A32PerformanceAndEncodedSizeStayBounded() throws {
        let input = makeInput(
            category: .workUniform,
            occasion: .work,
            environment: "Outdoors",
            evidence: [.silhouette, .construction, .visibleText, .branding],
            weather: makeWeather()
        )
        let start = Date.timeIntervalSinceReferenceDate
        var snapshot: OutfitContextSnapshot?
        for _ in 0..<1_000 {
            snapshot = try infer(input)
        }
        let elapsed = Date.timeIntervalSinceReferenceDate - start
        let value = try XCTUnwrap(snapshot)

        XCTAssertLessThan(elapsed / 1_000, 0.020)
        XCTAssertLessThan(try encoded(value).count, 16 * 1_024)
    }

    private func infer(
        _ input: ContextInferenceInput
    ) throws -> OutfitContextSnapshot {
        try OutfitContextEngine.infer(from: input).get()
    }

    private func failure(
        _ input: ContextInferenceInput
    ) -> ContextInferenceFailure? {
        if case .failure(let failure) = OutfitContextEngine.infer(from: input) {
            return failure
        }
        return nil
    }

    private func makeInput(
        scanID: String = "scan-ce2a",
        score: Int = 80,
        breakdown: OutfitScoreBreakdown? = OutfitScoreBreakdown(
            colorHarmony: 25,
            patternBalance: 20,
            fitQuality: 13,
            occasionMatch: 6,
            accessoryUse: 6
        ),
        category: OutfitCategory = .otherUncertain,
        confidence: Double = 0.95,
        occasion: Occasion? = nil,
        environment: String = "Home",
        evidence: [OutfitClassificationEvidence.Kind] = [],
        rawSummary: String = "Generic evidence",
        weather: WeatherContextReference? = nil,
        confirmedPurpose: OutfitPurpose? = nil,
        confirmationScanID: String = "scan-ce2a",
        rejected: Set<OutfitPurpose> = []
    ) -> ContextInferenceInput {
        let analysis = makeAnalysis(
            score: score,
            breakdown: breakdown,
            category: category,
            confidence: confidence,
            occasionLabel: occasion?.rawValue,
            environment: environment,
            evidence: evidence,
            rawSummary: rawSummary
        )
        return ContextInferenceInput(
            scanID: scanID,
            completedAt: completedAt,
            analysis: analysis,
            selectedOccasion: occasion,
            weather: weather,
            confirmedPurpose: confirmedPurpose.map {
                ContextPurposeConfirmation(
                    scanID: confirmationScanID,
                    purpose: $0
                )
            },
            rejectedPurposeIDs: rejected
        )
    }

    private func makeAnalysis(
        score: Int = 80,
        breakdown: OutfitScoreBreakdown? = OutfitScoreBreakdown(
            colorHarmony: 25,
            patternBalance: 20,
            fitQuality: 13,
            occasionMatch: 6,
            accessoryUse: 6
        ),
        category: OutfitCategory,
        confidence: Double = 0.95,
        occasionLabel: String?,
        environment: String = "Home",
        evidence: [OutfitClassificationEvidence.Kind] = [.silhouette],
        rawSummary: String = "Generic evidence"
    ) -> OutfitAnalysisResult {
        let classification = OutfitClassificationResult(
            primaryCategory: category,
            secondaryCategories: [],
            confidence: confidence,
            confidenceLevel: confidence >= 0.82 ? .high : (confidence >= 0.55 ? .medium : .low),
            evidence: evidence.map {
                OutfitClassificationEvidence(
                    kind: $0,
                    summary: rawSummary,
                    confidence: confidence
                )
            },
            detectedText: ["Alex Example", "Badge 4107"],
            detectedBranding: ["Northwind Textiles"],
            selectedOccasion: occasionLabel,
            occasionCompatibility: occasionLabel == nil ? .uncertain : .compatible,
            userConfirmedCategory: nil,
            scoringProfile: .uncertain
        )
        return OutfitAnalysisResult(
            score: score,
            scoreBreakdown: breakdown,
            colorMatch: "Coordinated",
            occasionFit: occasionLabel ?? "Unspecified",
            styleBalance: "Casual",
            colorHarmony: "Strong",
            styleCoordination: "Strong",
            formality: "Casual",
            seasonalMatch: "Warm weather",
            summary: "Completed scan",
            outfitDescription: "Outfit",
            detectedClothingItems: ["shirt", "pants"],
            colorPalette: ["gray"],
            environment: environment,
            imageQuality: "Clear",
            outfitClassification: classification,
            suggestions: [],
            recommendations: []
        )
    }

    private func makeWeather() -> WeatherContextReference {
        WeatherContextReference(
            observedAt: completedAt,
            airTemperature: 82,
            feelsLikeTemperature: 86,
            humidityPercent: 76,
            rainChancePercent: 10,
            windMph: 4,
            uvIndex: 5,
            condition: "Partly cloudy",
            confidence: ContextConfidence(value: 0.9, level: .high)
        )
    }

    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private func json<T: Encodable>(_ value: T) throws -> String {
        try XCTUnwrap(String(data: encoded(value), encoding: .utf8))
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func ce2aSourceContents() throws -> [String] {
        let directory = repositoryRoot()
            .appendingPathComponent("StyleMatchAI/ContextEngine")
        let names = [
            "ContextInferenceInput.swift",
            "PurposeClassifier.swift",
            "WorkplaceProfileClassifier.swift",
            "SuitabilityEvaluator.swift",
            "ContextInferenceValidator.swift",
            "OutfitContextEngine.swift"
        ]
        return try names.map {
            try String(
                contentsOf: directory.appendingPathComponent($0),
                encoding: .utf8
            )
        }
    }
}
