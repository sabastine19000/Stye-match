import AVFoundation
import ImageIO
import PhotosUI
import SwiftUI
import Vision

struct ScanView: View {
    @Binding var selectedTab: AppTab
    @AppStorage("outfitScanHistoryData") private var outfitScanHistoryData = Data()
    @AppStorage("favoriteColors") private var favoriteColors = ""
    @AppStorage("sizeProfile") private var sizeProfile = ""
    @AppStorage("shirtSize") private var shirtSize = ""
    @AppStorage("pantsSize") private var pantsSize = ""
    @AppStorage("waistSize") private var waistSize = ""
    @AppStorage("inseamLength") private var inseamLength = ""
    @AppStorage("neckSize") private var neckSize = ""
    @AppStorage("sleeveLength") private var sleeveLength = ""
    @AppStorage("shoeSize") private var shoeSize = ""
    @AppStorage("fitPreference") private var fitPreference = ""
    @AppStorage("stylePreferences") private var stylePreferences = ""
    @AppStorage("occasions") private var occasions = ""
    @AppStorage("plannedOccasion") private var plannedOccasion = ""
    @AppStorage("dressCode") private var dressCode = ""
    @AppStorage("occasionFormality") private var occasionFormality = ""
    @AppStorage("weather") private var weather = ""
    @AppStorage("weatherCity") private var weatherCity = ""
    @AppStorage("weatherCondition") private var weatherCondition = ""
    @AppStorage("weatherSource") private var weatherSource = ""
    @AppStorage("weatherFeelsLike") private var weatherFeelsLike = ""
    @AppStorage("weatherRainChance") private var weatherRainChance = ""
    @AppStorage("weatherHumidity") private var weatherHumidity = ""
    @AppStorage("weatherWindSpeed") private var weatherWindSpeed = ""
    @AppStorage("weatherUVIndex") private var weatherUVIndex = ""
    @AppStorage("liveWeatherUpdatedAt") private var liveWeatherUpdatedAt = 0.0
    @AppStorage("openAIModel") private var openAIModel = "gpt-4o-mini"
    @AppStorage("shareAppContextWithChatGPT") private var shareAppContextWithChatGPT = true
    @AppStorage(VoiceAssistantSettings.enabledKey) private var voiceAssistantEnabled = VoiceAssistantSettings.defaultEnabled
    @AppStorage("profileName") private var profileName = ""
    @AppStorage("shoppingBudget") private var budget = ""
    @AppStorage("favoriteBrands") private var favoriteBrands = ""
    @AppStorage("pastPurchases") private var pastPurchases = ""
    @AppStorage("favoriteOutfits") private var favoriteOutfits = ""
    @AppStorage("closetInventory") private var closetInventory = ""
    @AppStorage("closetItemsData") private var closetItemsData = Data()
    @AppStorage("selectedAppTheme") private var selectedAppTheme = StyleMatchAppTheme.system.rawValue
    @AppStorage("selectedThemeIntensity") private var selectedThemeIntensity = 0.42
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: Image?
    @State private var selectedUIImage: UIImage?
    @State private var isShowingCamera = false
    @State private var isPreparingCamera = false
    @State private var isAnalyzing = false
    @State private var result: OutfitAnalysisResult?
    @State private var preparedAnalysis: OutfitAnalysisResult?
    @State private var scanMessage: ScanMessage?
    @State private var activeScanSessionID: UUID?
    @State private var activeScanFingerprint: String?
    @State private var selectedScannerInsight = "Colors"
    @State private var scannerExampleIndex = 0
    @State private var selectedTryNextRecommendation: ClothingRecommendation?
    @State private var isShowingTryNextActions = false
    @State private var isShowingFullAnalysis = false
    @State private var isScoreAnalysisExpanded = false
    @State private var animatedScore = 0
    @State private var resultRevealStep = 0
    @State private var selectedScanHistoryFilter: ScanHistoryFilter = .all
    @State private var pendingRescanTitle: String?
    @State private var currentScanSource: ScanSource = .gallery
    @State private var selectedScanIDs = Set<String>()
    @State private var isEditingScanHistory = false
    @State private var scanPendingDelete: RecentOutfitScore?
    @State private var isShowingDeleteScanConfirmation = false
    @State private var scanPendingRename: RecentOutfitScore?
    @State private var renameText = ""
    @State private var isShowingRenameScanSheet = false
    @State private var isShowingDeleteAllConfirmation = false
    @State private var isShowingScanAIAssist = false
    @State private var scanAIInput = ""
    @State private var scanAIChatMessages: [ScanAIChatMessage] = []
    @State private var isScanAIThinking = false
    @State private var selectedScanOccasion: Occasion = .general
    @State private var dismissedFormalityMismatchSignatures = Set<String>()
    @StateObject private var voiceAssistant = VoiceStylistService()
    
    private var activeTheme: StyleMatchAppTheme {
        StyleMatchAppTheme(rawValue: selectedAppTheme) ?? .system
    }

    private var activeScanPalette: (background: Color, panel: Color, border: Color, cream: Color, muted: Color) {
        activeTheme.scanPalette(intensity: selectedThemeIntensity)
    }

    private var scanBackground: Color { activeScanPalette.background }
    private var scanPanel: Color { activeScanPalette.panel }
    private var scanPanelBorder: Color { activeScanPalette.border }
    private var scanCream: Color { activeScanPalette.cream }
    private var scanMuted: Color { activeScanPalette.muted }

    private func makeAnalysisResult(
        score: Int,
        validation: ScanValidation,
        labels: [DetectedLabel],
        imageQuality: String,
        colorPalette: [String]? = nil,
        colorPaletteMaskingApplied: Bool? = nil,
        colorPaletteMaskTier: String? = nil,
        skinToneStyleNote: String? = nil,
        scoreBreakdown: StyleScoreBreakdown? = nil
    ) -> OutfitAnalysisResult {
        let noveltyStyle = noveltyClothingMatch(in: labels)
        let culturalStyle = noveltyStyle == nil ? traditionalStyleMatch(in: labels, image: selectedUIImage) : nil
        let purposeStyle = noveltyStyle == nil ? clothingPurposeClassification(validation: validation, labels: labels, image: selectedUIImage) : nil
        var detectedItems = detectedClothingItems(from: labels)
        if let noveltyStyle {
            detectedItems.insert(noveltyStyle.garment, at: 0)
            detectedItems = detectedItems.removingDuplicates()
        }
        if let purposeStyle {
            detectedItems.insert(purposeStyle.garment, at: 0)
            detectedItems = detectedItems.removingDuplicates()
        }
        if let culturalStyle {
            detectedItems.insert(culturalStyle.garment, at: 0)
            detectedItems = detectedItems.removingDuplicates()
        }
        let paletteDetection = colorPalette == nil ? selectedUIImage?.garmentColorDetection() : nil
        let resolvedColorPalette = colorPalette ?? paletteDetection?.garmentColors ?? ["Neutral"]
        let environment = detectedEnvironment(from: labels)
        let sceneName = validation.sceneName
        let itemDescription = detectedItems.isEmpty ? sceneName : detectedItems.joined(separator: ", ")
        let fitNote = fitRecommendationNote(for: detectedItems)
        let weatherNote = weatherRecommendationNote(environment: environment)
        let occasionNote = noveltyStyle?.occasionNote ?? purposeStyle?.occasionNote ?? occasionRecommendationNote(environment: environment, culturalStyle: culturalStyle)
        let recommendations = dynamicRecommendations(
            score: score,
            detectedItems: detectedItems,
            colorPalette: resolvedColorPalette,
            environment: environment
        )
        let isUnrecognized = !validation.isAccepted && noveltyStyle == nil && purposeStyle == nil && culturalStyle == nil
        let occasionFit = isUnrecognized ? "Category Uncertain" : (noveltyStyle?.occasionCategory ?? purposeStyle?.occasionCategory ?? culturalStyle?.occasionCategory ?? plannedOccasionSummary(environment: environment))
        let formality = isUnrecognized ? "Unrecognized" : (noveltyStyle?.dressCode ?? purposeStyle?.dressCode ?? culturalStyle?.dressCode ?? (environment == "Business" || environment == "Office" ? "Polished" : "Flexible"))
        let summary = isUnrecognized ? "Style Match Pro could not identify enough reliable clothing detail in this scan. Please retake the photo with the full outfit visible." : (noveltyStyle?.summary ?? purposeStyle?.summary ?? culturalStyle?.summary ?? "This outfit has a strong foundation. The colors feel intentional, the silhouette is balanced, and the fit advice uses your saved size profile for fashion guidance only.")
        let itemConfidences = detectedItemConfidences(for: detectedItems, labels: labels, culturalStyle: culturalStyle)
        let resolvedStyleCategory = isUnrecognized ? "Unrecognized Item" : (noveltyStyle?.styleCategory ?? purposeStyle?.styleCategory ?? culturalStyle?.styleCategory ?? "Casual Wear")
        let calibratedScore = calibratedStyleScore(
            score,
            styleCategory: resolvedStyleCategory,
            evidence: [
                detectedItems.joined(separator: " "),
                occasionFit,
                formality,
                environment,
                sceneName,
                summary
            ].joined(separator: " ")
        )
        let breakdown = scoreBreakdown ?? calculateStyleScore(
            validation: validation,
            labels: labels,
            colorPalette: resolvedColorPalette,
            detectedItems: detectedItems,
            styleCategory: resolvedStyleCategory
        ).breakdown

        return OutfitAnalysisResult(
            score: calibratedScore,
            scoreBreakdown: breakdown.outfitSnapshot,
            colorMatch: "Strong",
            occasionFit: occasionFit,
            styleBalance: resolvedStyleCategory,
            colorHarmony: "\(breakdown.colorHarmony)/25",
            styleCoordination: "\(breakdown.patternBalance + breakdown.fitQuality + breakdown.occasionMatch + breakdown.accessoryUse)/75",
            formality: formality,
            seasonalMatch: weatherLocationText,
            summary: summary,
            outfitDescription: "Detected \(itemDescription.lowercased()) in a \(sceneName.lowercased()) scan.",
            detectedClothingItems: detectedItems,
            colorPalette: resolvedColorPalette,
            colorPaletteMaskingApplied: colorPaletteMaskingApplied ?? paletteDetection?.maskingApplied ?? true,
            colorPaletteMaskTier: colorPaletteMaskTier ?? paletteDetection?.maskTier,
            environment: environment,
            imageQuality: imageQuality,
            skinToneStyleNote: skinToneStyleNote ?? "Style Match Pro uses visible outfit colors for fashion recommendations. It does not identify race, ethnicity, or sensitive personal traits.",
            detectedItemConfidences: itemConfidences,
            suggestions: [
                fitNote,
                weatherNote,
                occasionNote,
                "Add one watch, belt, or simple jewelry piece so the outfit feels finished."
            ],
            recommendations: recommendations
        )
    }

    private func calibratedStyleScore(_ score: Int, styleCategory: String, evidence: String) -> Int {
        let lower = "\(styleCategory) \(evidence)".lowercased()
        var cap = 100

        if lower.contains("children's sleepwear") || lower.contains("kids sleepwear") {
            cap = min(cap, 70)
        } else if lower.contains("sleepwear") || lower.contains("pajama") || lower.contains("robe") || lower.contains("slipper") {
            cap = min(cap, 74)
        } else if lower.contains("loungewear") || lower.contains("indoor wear") || lower.contains("house clothes") {
            cap = min(cap, 78)
        } else if lower.contains("unrecognized item") || lower.contains("category uncertain") || lower.contains("unrecognized") {
            cap = min(cap, 45)
        }

        if isYouthGraphicCasualEvidence(lower) {
            cap = min(cap, 80)
        }

        if isBusinessBlockedByCasualEvidence(lower) {
            cap = min(cap, 84)
        }

        let target = plannedOccasionSummary(environment: detectedEnvironment(from: [])).lowercased()
        if (target.contains("work") || target.contains("office")) && lower.contains("casual") && !lower.contains("business") {
            cap = min(cap, 82)
        }

        return clampedScore(min(score, cap))
    }

    private func dynamicRecommendations(
        score: Int,
        detectedItems: [String],
        colorPalette: [String],
        environment: String
    ) -> [ClothingRecommendation] {
        let paletteText = colorPalette.isEmpty ? favoriteColors : colorPalette.joined(separator: ", ")
        let itemText = detectedItems.isEmpty ? "the visible outfit" : detectedItems.joined(separator: ", ").lowercased()
        if sleepwearOrLoungewearCategory(from: "\(itemText) \(environment.lowercased())") != nil {
            return validatedRecommendations([
                ClothingRecommendation(
                    category: "Comfort",
                    title: "Cozy indoor styling",
                    reason: "This reads as sleepwear or loungewear, so comfort, softness, and home use matter more than business polish.",
                    personalization: "Keep the robe, pajama set, or slippers coordinated for a relaxed bedtime or at-home look."
                ),
                ClothingRecommendation(
                    category: "Fit",
                    title: "Roomy, comfortable fit",
                    reason: "Sleepwear should allow easy movement and feel soft rather than structured or tailored.",
                    personalization: "Choose relaxed sizing and avoid tight layers for bedtime or lounging."
                )
            ], environment: environment)
        }
        if isRuggedCasualEvidence("\(itemText) \(environment.lowercased())") {
            return validatedRecommendations([
                ClothingRecommendation(
                    category: "Footwear",
                    title: "Lean into rugged casual shoes",
                    reason: "The hoodie, plaid or flannel layer, denim, and casual footwear read everyday casual rather than business casual.",
                    personalization: "Clean boots, casual leather sneakers, or trail-inspired shoes will support the outdoor/workwear feel."
                ),
                ClothingRecommendation(
                    category: "Layering",
                    title: "Keep the shacket structured",
                    reason: "A rugged casual outfit looks strongest when the top layer fits cleanly through the shoulders and does not bunch over the hoodie.",
                    personalization: "Use darker denim or a plain tee underneath if you want the plaid layer to look sharper."
                )
            ], environment: environment)
        }
        let needsPolish = score < 88
        let needsOnlyFinish = score >= 92
        let hasPantsSignal = detectedItems.contains { item in
            ["pant", "jean", "short", "trouser"].contains { item.localizedCaseInsensitiveContains($0) }
        }
        let hasShirtSignal = detectedItems.contains { item in
            ["shirt", "top", "hoodie", "sweater", "blouse"].contains { item.localizedCaseInsensitiveContains($0) }
        }

        var recommendations: [ClothingRecommendation] = []

        if needsPolish {
            recommendations.append(
                ClothingRecommendation(
                    category: "Fit",
                    title: "Tighten the cleanest part of the outfit",
                    reason: "A \(score) \(scoreRatingTitle(for: score)) look usually needs one sharper fit detail before changing the whole outfit.",
                    personalization: "Use your saved fit: shirt \(shirtSize), pants \(pantsSize), shoes \(shoeSize), \(fitPreference.lowercased())."
                )
            )
        } else if needsOnlyFinish {
            recommendations.append(
                ClothingRecommendation(
                    category: "Finish",
                    title: "Keep the outfit and add one premium detail",
                    reason: "A \(score) \(scoreRatingTitle(for: score)) look is already strong, so the best upgrade is a small finishing piece instead of a full change.",
                    personalization: isHotWeatherContext
                        ? "Choose a watch, belt, sunglasses, breathable shoe finish, or lightweight accessory that matches \(paletteText)."
                        : "Choose a watch, belt, jacket, or shoe finish that matches \(paletteText)."
                )
            )
        } else {
            recommendations.append(
                ClothingRecommendation(
                    category: "Balance",
                    title: "Improve the top-to-bottom balance",
                    reason: "The outfit is working, but one cleaner color bridge would make \(itemText) feel more intentional.",
                    personalization: "Favorite colors saved: \(favoriteColors). Current palette: \(paletteText)."
                )
            )
        }

        if hasShirtSignal || !hasPantsSignal {
            recommendations.append(
                ClothingRecommendation(
                    category: "Pants",
                    title: needsOnlyFinish ? "Pressed dark denim or tailored chinos" : "Better tapered pants in a neutral color",
                    reason: "A cleaner pant shape can lift the full outfit without fighting the shirt.",
                    personalization: pantsPersonalization
                )
            )
        }

        if hasPantsSignal || !hasShirtSignal {
            recommendations.append(
                ClothingRecommendation(
                    category: "Shirts",
                    title: needsOnlyFinish ? "Crisp shirt in the same color family" : "Sharper shirt with cleaner structure",
                    reason: "A structured shirt improves the outfit line and helps the score feel more trustworthy.",
                    personalization: shirtPersonalization
                )
            )
        }

        recommendations.append(
            ClothingRecommendation(
                category: "Shoes",
                title: shoeRecommendationTitle(score: score, palette: colorPalette, environment: environment),
                reason: shoeRecommendationReason(score: score, environment: environment),
                personalization: "Saved shoe size: \(shoeSize). Match with \(paletteText.lowercased())."
            )
        )

        recommendations.append(
            ClothingRecommendation(
                category: weatherAccessoryRecommendationCategory,
                title: weatherAccessoryRecommendationTitle,
                reason: weatherAccessoryRecommendationReason,
                personalization: "Weather: \(weatherLocationText). Occasion: \(plannedOccasionSummary(environment: environment))."
            )
        )

        return validatedRecommendations(recommendations, environment: environment)
    }

    private var weatherAccessoryRecommendationCategory: String {
        let recommendation = weatherContextRecommendation(environment: result?.environment ?? "Unspecified")
        if !recommendation.canGiveSpecificWeatherClothingAdvice {
            return "Weather Context"
        }
        if isHotWeatherContext {
            return "Hot Weather"
        }

        return weatherCondition.localizedCaseInsensitiveContains("rain") ? "Rain Ready" : "Accessories"
    }

    private var weatherAccessoryRecommendationTitle: String {
        let recommendation = weatherContextRecommendation(environment: result?.environment ?? "Unspecified")
        if !recommendation.canGiveSpecificWeatherClothingAdvice {
            return "Confirm current weather before changing clothes"
        }
        if isHotWeatherContext {
            return "Breathable polish for the heat"
        }

        return weatherCondition.localizedCaseInsensitiveContains("rain") ? "Light rain shell or water-friendly shoes" : "One watch, belt, or simple chain"
    }

    private var weatherAccessoryRecommendationReason: String {
        let recommendation = weatherContextRecommendation(environment: result?.environment ?? "Unspecified")
        if !recommendation.canGiveSpecificWeatherClothingAdvice {
            return recommendation.rationale
        }
        if isHotWeatherContext {
            return recommendation.rationale
        }

        return weatherCondition.localizedCaseInsensitiveContains("rain") ? "The outfit should still work if the weather turns wet without adding unnecessary bulk." : "One controlled detail makes the outfit look styled instead of accidental."
    }

    private func validatedRecommendations(_ recommendations: [ClothingRecommendation], environment: String) -> [ClothingRecommendation] {
        recommendations
            .map { validateRecommendation($0, environment: environment) }
            .removingDuplicates(by: { "\($0.category)-\($0.title)" })
    }

    private func validateRecommendation(_ recommendation: ClothingRecommendation, environment: String) -> ClothingRecommendation {
        let weatherRecommendation = weatherContextRecommendation(environment: environment)
        if !weatherRecommendation.canGiveSpecificWeatherClothingAdvice,
           containsSpecificWeatherAdvice("\(recommendation.category) \(recommendation.title) \(recommendation.reason) \(recommendation.personalization)") {
            return ClothingRecommendation(
                category: "Weather Context",
                title: "Confirm current weather before changing clothes",
                reason: weatherRecommendation.rationale,
                personalization: "Weather confidence is below 90%, so StyleMatch Pro will keep this advice general."
            )
        }

        guard weatherRecommendation.severity.isWarmOrHot else {
            return recommendation
        }

        let combined = "\(recommendation.category) \(recommendation.title) \(recommendation.reason) \(recommendation.personalization)"
        guard containsHeavyLayerAdvice(combined) else {
            return recommendation
        }

        return ClothingRecommendation(
            category: "Hot Weather",
            title: "Breathable polish for the heat",
            reason: "The original layer idea conflicted with \(weatherLocationText). Use a crisp lightweight shirt, breathable pants or shorts when appropriate, clean shoes, sunglasses, a hat, belt, or watch instead.",
            personalization: "Validated against weather, occasion \(plannedOccasionSummary(environment: environment)), favorite colors \(favoriteColors), and saved closet context."
        )
    }

    private func containsHeavyLayerAdvice(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.contains("jacket")
            || lowered.contains("blazer")
            || lowered.contains("coat")
            || lowered.contains("sweater")
            || lowered.contains("shacket")
            || lowered.contains("heavy layer")
            || lowered.contains("structured layer")
    }

    private func containsSpecificWeatherAdvice(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.contains("rain")
            || lowered.contains("snow")
            || lowered.contains("hot")
            || lowered.contains("cold")
            || lowered.contains("humid")
            || lowered.contains("uv")
            || lowered.contains("wind")
            || lowered.contains("umbrella")
            || lowered.contains("linen")
            || lowered.contains("coat")
            || lowered.contains("jacket")
    }

    private func shoeRecommendationTitle(score: Int, palette: [String], environment: String) -> String {
        if score >= 92 {
            return environment == "Business" || environment == "Office" ? "Polished black or dark brown loafers" : "Premium low-profile sneakers"
        }

        if palette.contains(where: { $0.localizedCaseInsensitiveContains("black") || $0.localizedCaseInsensitiveContains("gray") }) {
            return "Black loafers or clean dark sneakers"
        }

        if palette.contains(where: { $0.localizedCaseInsensitiveContains("tan") || $0.localizedCaseInsensitiveContains("green") }) {
            return "Tan loafers or cream sneakers"
        }

        return "Clean sneakers that match the outfit palette"
    }

    private func shoeRecommendationReason(score: Int, environment: String) -> String {
        if score >= 92 {
            return "The outfit is already scoring high, so shoes should refine the look instead of changing its direction."
        }

        if environment == "Business" || environment == "Office" {
            return "A polished shoe makes the outfit feel more intentional for a work setting."
        }

        return "A cleaner shoe choice anchors the outfit and helps the lower half look finished."
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        hero
                        photoPicker

                        if isAnalyzing {
                            analyzingCard
                        }

                        if let scanMessage {
                            messageCard(scanMessage)
                        }

                        if let result {
                            quickResultCard(result)
                                .id("loadedScanResult")
                        }

                        recentScoresCard(scrollProxy: proxy)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 34)
                    .padding(.bottom, 28)
                }
                .scrollContentBackground(.hidden)
                .background(scanBackground.ignoresSafeArea())
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraCaptureView { image, source in
                let scanImage = image.scanSizedImage()
                let rescanTitle = pendingRescanTitle
                invalidateActiveScanSession()
                isPreparingCamera = false
                isAnalyzing = false
                pendingRescanTitle = nil
                selectedItem = nil
                currentScanSource = source
                selectedUIImage = scanImage
                selectedImage = Image(uiImage: scanImage)
                result = nil
                preparedAnalysis = nil
                isShowingFullAnalysis = false
                scanMessage = ScanMessage(
                    title: rescanTitle == nil ? "Photo captured" : "Rescan photo captured",
                    description: rescanTitle == nil ? "Review the photo or run a quick style score." : "Review the updated \(rescanTitle ?? "outfit") photo, then generate a fresh style score.",
                    icon: "camera",
                    isSuccess: true
                )
            }
            .onDisappear {
                isPreparingCamera = false
            }
        }
        .styleMatchOnChange(of: selectedItem) { newItem in
            Task {
                isShowingFullAnalysis = false
                await loadImage(from: newItem)
            }
        }
        .styleMatchOnChange(of: result?.score) { score in
            guard let score else {
                resetResultAnimation()
                scanAIChatMessages.removeAll()
                return
            }

            scanAIChatMessages.removeAll()
            startResultAnimation(to: score)
        }
        .onDisappear {
            voiceAssistant.stop()
        }
        .onReceive(Timer.publish(every: 2.8, on: .main, in: .common).autoconnect()) { _ in
            guard selectedUIImage == nil, !scannerExamples.isEmpty else {
                return
            }

            withAnimation(.easeInOut(duration: 0.35)) {
                scannerExampleIndex = (scannerExampleIndex + 1) % scannerExamples.count
            }
        }
        .confirmationDialog(
            selectedTryNextRecommendation?.title ?? "Try this next",
            isPresented: $isShowingTryNextActions,
            titleVisibility: .visible
        ) {
            Button("Tap to Shop") {
                handleTryNextAction(.shop)
            }

            Button("View Similar") {
                handleTryNextAction(.similar)
            }

            Button("Already in Closet") {
                handleTryNextAction(.closet)
            }

            Button("Ask AI Stylist") {
                handleTryNextAction(.askAI)
            }

            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Choose what you want to do with this recommendation.")
        }
        .confirmationDialog(
            "Delete this scan permanently?",
            isPresented: $isShowingDeleteScanConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let scanPendingDelete {
                    deleteSavedScan(scanPendingDelete)
                }
                scanPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                scanPendingDelete = nil
            }
        } message: {
            Text("This removes the photo, score, analysis, outfit history, and cached data from this phone.")
        }
        .confirmationDialog(
            "This action cannot be undone.",
            isPresented: $isShowingDeleteAllConfirmation,
            titleVisibility: .visible
        ) {
            Button(selectedScanIDs.isEmpty ? "Delete All Scan History" : "Delete Selected Scans", role: .destructive) {
                if selectedScanIDs.isEmpty {
                    deleteAllScanHistory()
                } else {
                    deleteSelectedScans()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(selectedScanIDs.isEmpty ? "Delete all saved scans from this phone?" : "Delete \(selectedScanIDs.count) selected scan\(selectedScanIDs.count == 1 ? "" : "s")?")
        }
        .sheet(isPresented: $isShowingRenameScanSheet) {
            NavigationStack {
                Form {
                    Section("Rename Scan") {
                        TextField("Scan name", text: $renameText)
                    }

                    Section {
                        Button {
                            renamePendingScan()
                        } label: {
                            Label("Save Name", systemImage: "checkmark.circle.fill")
                        }
                        .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .navigationTitle("Rename")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            isShowingRenameScanSheet = false
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingScanAIAssist) {
            if let result {
                scanAIAssistSheet(for: result)
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    selectedTab = .home
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(scanCream)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(scanPanel)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(scanCream.opacity(0.35), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to Home")

                Text("Scan")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(scanMuted)

                Spacer()
            }

            Text("Style Match Pro")
                .font(.system(size: 40, weight: .bold))
                .fontWeight(.bold)
                .foregroundStyle(.white)

            Text("Scan your outfit for instant style recommendations")
                .font(.title3)
                .foregroundStyle(scanMuted)
        }
    }

    private var photoPicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            scannerPanel

            if let result {
                compactScoreBadge(result)

                if isShowingFullAnalysis {
                    resultCard(result)
                }
            }

            if selectedUIImage != nil {
                Button {
                    analyze()
                } label: {
                    Label("Generate Style Score", systemImage: "sparkles")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(scanCream)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(scanPanel)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(scanCream.opacity(0.45), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                .disabled(isAnalyzing)
            }

            if selectedUIImage != nil {
                HStack(spacing: 12) {
                    Button {
                        analyze(forceReanalyze: true)
                    } label: {
                        Label("Reanalyze", systemImage: "arrow.clockwise")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(scanMuted)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(scanPanel.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(isAnalyzing)

                    Button(role: .destructive) {
                        deleteCurrentPhoto()
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.red.opacity(0.95))
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(scanPanel.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(isAnalyzing)
                }
            }
        }
    }

    private var scanSourceControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    startCameraCapture()
                } label: {
                    Label("Camera", systemImage: "camera.fill")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(scanBackground)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(scanCream)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                .disabled(isAnalyzing || isPreparingCamera)

                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label("Gallery", systemImage: "photo.fill")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(scanBackground.opacity(0.35))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(scanPanelBorder, lineWidth: 1.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                .disabled(isAnalyzing || isPreparingCamera)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(scanBackground.opacity(0.18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(scanPanelBorder.opacity(0.7), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var scanOccasionSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What's this for?")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(scanMuted)
                .padding(.horizontal, 18)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Occasion.allCases, id: \.self) { occasion in
                        occasionChip(occasion, title: occasion.displayName)
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }

    private func occasionChip(_ occasion: Occasion, title: String) -> some View {
        let isSelected = selectedScanOccasion == occasion

        return Button {
            selectedScanOccasion = occasion
        } label: {
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .lineLimit(1)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .foregroundStyle(isSelected ? scanBackground : scanCream)
                .background(isSelected ? scanCream : scanBackground.opacity(0.32))
                .overlay(
                    Capsule()
                        .stroke(scanCream.opacity(isSelected ? 0 : 0.28), lineWidth: 1)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isAnalyzing)
    }

    private var scannerPanel: some View {
        VStack(spacing: 12) {
            if let selectedImage {
                ZStack(alignment: .topTrailing) {
                    selectedImage
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 250)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .padding(.horizontal, 16)

                    Button {
                        deleteCurrentPhoto()
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(Color.red)
                            .clipShape(Circle())
                    }
                    .padding(.trailing, 24)
                    .padding(.top, 10)
                }
            } else {
                Button {
                    startCameraCapture()
                } label: {
                    scannerExampleCarousel
                }
                .buttonStyle(.plain)
                .disabled(isAnalyzing || isPreparingCamera)
            }

            VStack(spacing: 12) {
                Text("AI Outfit Scanner")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                Text(selectedUIImage == nil ? "Analyze colors, fit, patterns, accessories and more." : "Review the photo, then generate a personalized style score.")
                    .font(.subheadline)
                    .foregroundStyle(scanMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 22)
            }

            scanSourceControl
            scanOccasionSelector

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(scannerInsightTabs, id: \.self) { tab in
                        scannerTag(tab)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 4)
            }
            .padding(.top, 8)

            scannerInsightCard
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(scanPanel)
        .overlay(
            RoundedRectangle(cornerRadius: 30)
                .stroke(scanPanelBorder, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 30))
    }

    private var scannerExampleCarousel: some View {
        let example = scannerExamples[scannerExampleIndex % scannerExamples.count]

        return VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [example.tint.opacity(0.32), scanBackground.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(scanCream.opacity(0.28), style: StrokeStyle(lineWidth: 2, dash: [8, 7]))
                    )
                    .frame(height: 150)

                VStack(spacing: 9) {
                    Image(systemName: example.icon)
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(scanCream)
                        .frame(width: 76, height: 76)
                        .background(example.tint.opacity(0.24))
                        .clipShape(RoundedRectangle(cornerRadius: 24))

                    VStack(spacing: 4) {
                        Text(example.title)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)

                        Text(example.detail)
                            .font(.caption)
                            .foregroundStyle(scanMuted)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                }
                .padding(.horizontal, 18)
            }
            .id(example.id)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))

            HStack(spacing: 7) {
                ForEach(scannerExamples.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == scannerExampleIndex ? scanCream : scanCream.opacity(0.28))
                        .frame(width: index == scannerExampleIndex ? 28 : 8, height: 7)
                }
            }
        }
        .padding(.horizontal, 18)
    }

    private var scannerExamples: [ScannerExample] {
        [
            ScannerExample(title: "Outfit on a person", detail: "Full-body or mirror photos work best.", icon: "person.fill", tint: .blue),
            ScannerExample(title: "Clothes on a bed", detail: "Lay pieces flat with good lighting.", icon: "bed.double.fill", tint: .purple),
            ScannerExample(title: "Clothes on a hanger", detail: "Hang shirts, jackets, or full looks.", icon: "tshirt.fill", tint: .green),
            ScannerExample(title: "Clothes on a mannequin", detail: "Store displays and styled pieces work.", icon: "person.crop.rectangle", tint: .orange),
            ScannerExample(title: "Clothes on a table", detail: "Show colors, materials, and pairings.", icon: "tablecells.fill", tint: .teal),
            ScannerExample(title: "Clothes in a shopping bag", detail: "Check new pieces before you wear them.", icon: "bag.fill", tint: .pink)
        ]
    }

    private var scannerInsightTabs: [String] {
        [
            "Colors",
            "Patterns",
            "Fit",
            "Accessories",
            "Occasion",
            "Weather",
            "Tips"
        ]
    }

    private func scannerTag(_ text: String) -> some View {
        let isSelected = selectedScannerInsight == text

        return Button {
            selectedScannerInsight = text
        } label: {
            HStack(spacing: 6) {
                Image(systemName: scannerTagIcon(for: text))
                    .font(.caption2)

                Text(text)
                    .font(.caption)
                    .fontWeight(.bold)
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? scanBackground : scanCream)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(isSelected ? scanCream : scanBackground.opacity(0.42))
            .overlay(
                Capsule()
                    .stroke(scanCream.opacity(isSelected ? 0 : 0.35), lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func scannerTagIcon(for text: String) -> String {
        switch text {
        case "Colors":
            return "circle.lefthalf.filled"
        case "Patterns":
            return "circle.grid.cross"
        case "Fit":
            return "ruler"
        case "Accessories":
            return "sparkles"
        case "Occasion":
            return "calendar"
        case "Weather":
            return "cloud.sun.fill"
        case "Tips":
            return "lightbulb.fill"
        default:
            return "circle.fill"
        }
    }

    @ViewBuilder
    private var scannerInsightCard: some View {
        if selectedScannerInsight == "Weather" {
            weatherCompatibilityInsightCard
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(selectedScannerInsight)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(scanCream)

                Text(scannerInsightText)
                    .font(.caption)
                    .foregroundStyle(scanMuted)
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(scanBackground.opacity(0.52))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 22)
        }
    }

    private var weatherCompatibilityInsightCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Weather Compatibility", systemImage: "cloud.sun.fill")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(scanCream)

                Spacer()

                WeatherStylingButton {
                    Label("Live", systemImage: "arrow.clockwise")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(scanCream)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(scanPanel.opacity(0.82))
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 10) {
                weatherCompatibilityMetric(
                    title: "Current Conditions",
                    value: compactCurrentWeatherText
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("Compatibility")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(scanMuted)

                    HStack(spacing: 2) {
                        ForEach(0..<5, id: \.self) { _ in
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(scanCream)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(scanPanel.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Recommendation")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(scanMuted)

                Text(compactWeatherRecommendation)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .lineSpacing(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(scanBackground.opacity(0.52))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 22)
    }

    private func weatherCompatibilityMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(scanMuted)

            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.86)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(scanPanel.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var compactCurrentWeatherText: String {
        "\(compactWeatherTemperature) • \(compactWeatherCondition)"
    }

    private var compactWeatherTemperature: String {
        let combinedWeatherText = "\(weather) \(weatherCondition)"
        let tokens = combinedWeatherText.split { character in
            character == " " || character == "," || character == "•" || character == "\n"
        }
        return tokens.first { $0.contains("°") }.map(String.init) ?? "72°F"
    }

    private var compactWeatherCondition: String {
        let condition = weatherCondition.trimmingCharacters(in: .whitespacesAndNewlines)
        if !condition.isEmpty {
            return condition.replacingOccurrences(of: " weather", with: "", options: .caseInsensitive)
        }

        let savedWeather = weather.trimmingCharacters(in: .whitespacesAndNewlines)
        if savedWeather.isEmpty {
            return "Mild"
        }

        return savedWeather.replacingOccurrences(of: " weather", with: "", options: .caseInsensitive)
    }

    private var compactWeatherRecommendation: String {
        let recommendation = weatherContextRecommendation(environment: result?.environment ?? "Unspecified")
        return "\(recommendation.severity.rawValue): \(recommendation.recommendation) Why: \(recommendation.rationale)"
    }

    private var hasSavedSizeProfileForFitCopy: Bool {
        guard FounderProfileDefaultsMigration.hasIntentionalProfileSave() else { return false }
        return [
            sizeProfile,
            shirtSize,
            pantsSize,
            waistSize,
            inseamLength,
            shoeSize,
            fitPreference
        ].contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var savedSizeProfileSummaryForFitCopy: String {
        let parts = [
            ("shirt", shirtSize),
            ("pants", pantsSize),
            ("waist", waistSize),
            ("inseam", inseamLength),
            ("shoes", shoeSize),
            ("fit", fitPreference)
        ].compactMap { label, value -> String? in
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return clean.isEmpty ? nil : "\(label) \(clean)"
        }
        if !parts.isEmpty { return parts.joined(separator: ", ") }
        let cleanProfile = sizeProfile.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanProfile.isEmpty ? "your saved size profile" : cleanProfile
    }

    private var scannerInsightText: String {
        switch selectedScannerInsight {
        case "Colors":
            if let result {
                let matchingIdeas = isHotWeatherContext ? "matching breathable fabrics and accessories" : "matching layers and accessories"
                let source = result.colorPaletteMaskingApplied ? "Palette found" : "Palette found (full photo)"
                return "\(source): \(result.colorPalette.joined(separator: ", ")). Use this to choose \(matchingIdeas)."
            }
            return "After a scan, this shows the outfit color palette and matching color ideas."
        case "Patterns":
            if let result {
                return "Pattern check uses detected items: \(result.safeDetectedClothingItems.isEmpty ? "outfit" : result.safeDetectedClothingItems.joined(separator: ", ")). Keep one strong pattern as the focus."
            }
            return "After a scan, this checks whether prints, solids, and statement pieces feel balanced."
        case "Fit":
            if let result {
                if hasSavedSizeProfileForFitCopy {
                    return "Current fit score: \(result.score) \(scoreRatingTitle(for: result.score)). Uses your saved size profile: \(savedSizeProfileSummaryForFitCopy)."
                }
                return "Current fit score: \(result.score) \(scoreRatingTitle(for: result.score)). No saved sizes yet; add them in Profile for tailored fit guidance."
            }
            return hasSavedSizeProfileForFitCopy
                ? "After a scan, this uses your saved size profile to explain fit, tailoring, and size-up or size-down suggestions."
                : "After a scan, this checks visible fit. Add your sizes in Profile for tailored size-up or size-down suggestions."
        case "Accessories":
            if let result {
                let footwearVisible = hasVisibleFootwear(in: result)
                let accessory = result.recommendations.first { recommendation in
                    let category = recommendation.category.lowercased()
                    if category.contains("shoe") {
                        return footwearVisible
                    }
                    return ["watches", "handbags", "accessories", "finish"].contains(category)
                }
                let fallback = isHotWeatherContext
                    ? "This outfit can be finished with one clean detail: watch, belt, bag, sunglasses, or hat."
                    : "This outfit can be finished with one clean detail: watch, belt, bag, or weather-appropriate layer."
                return accessory.map { "\($0.title). \($0.reason)" } ?? fallback
            }
            return "After a scan, this suggests the best shoes, watches, bags, belts, and small finishing pieces."
        case "Occasion":
            if let result {
                return "Occasion match: \(result.occasionFit). Formality: \(result.formality). Style Match Pro checks if the look fits work, church, travel, dinner, and events."
            }
            return "After a scan, this checks whether the outfit fits the moment: work, church, travel, date night, gym, wedding, or interview."
        case "Weather":
            if let result {
                return "Weather check: \(weatherLocationText). Seasonal match: \(result.seasonalMatch). \(compactWeatherRecommendation)"
            }
            return "After a scan, this compares the outfit with local weather and suggests practical shoes, accessories, breathable pieces, or warm layers only when needed."
        case "Tips":
            if let result {
                return result.suggestions.first ?? "Try one stronger color bridge, cleaner shoes, or a better-fitting layer to lift the outfit."
            }
            return "After a scan, this gives the fastest next step to improve the outfit without judging the customer."
        default:
            return "Select a scan tool to see personalized outfit feedback."
        }
    }

    private func hasVisibleFootwear(in result: OutfitAnalysisResult) -> Bool {
        let evidence = (
            result.detectedClothingItems.joined(separator: " ") + " " +
            result.outfitDescription + " " +
            result.summary + " " +
            result.recommendations.map { "\($0.category) \($0.title) \($0.reason)" }.joined(separator: " ")
        ).lowercased()

        let footwearTerms = [
            "shoe", "shoes", "sneaker", "sneakers", "loafer", "loafers",
            "boot", "boots", "sandal", "sandals", "slipper", "slippers"
        ]
        return footwearTerms.contains { evidence.contains($0) }
    }

    private var analyzingCard: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(scanCream)
            Text("Analyzing outfit...")
                .fontWeight(.semibold)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(scanPanel)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(scanPanelBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func compactScoreBadge(_ result: OutfitAnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Style score")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(scanMuted)

                    Text("Better match ideas")
                        .font(.headline)
                        .foregroundStyle(.white)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(displayedScore(for: result))")
                        .font(.system(size: 58, weight: .bold, design: .rounded))
                        .foregroundStyle(scanCream)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text("Overall Style Score")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(scanMuted)

                    scoreStars(for: result.score, font: .caption)

                    Text(scoreRatingTitle(for: result.score))
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }

            detectedStyleContextCard(for: result, darkMode: true)

            if let mismatch = formalityMismatch(for: result) {
                formalityMismatchBanner(mismatch, result: result, darkMode: true)
            }

            Divider()
                .overlay(scanPanelBorder)

            if result.score >= 95 {
                highScoreCelebrationCard(result)
            }

            scanResultOccasionPicker(for: result)

            if !result.chatGPTStylistSections.isEmpty {
                chatGPTStylistSectionsCard(result.chatGPTStylistSections, darkMode: true)
            }

            if voiceAssistantEnabled {
                voiceAssistantButton(for: result, darkMode: true)
            }

            Button {
                openScanAIAssist(for: result)
            } label: {
                Label("Ask AI About This Score", systemImage: "bubble.left.and.bubble.right.fill")
                    .font(.headline)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(scanCream)
            .foregroundStyle(scanBackground)

            if FeatureFlags.conversationalStylist,
               let scoreBreakdown = result.scoreBreakdown?.stylistChatSummary {
                NavigationLink {
                    StylistChatView(
                        initialQuestion: "Why did this outfit score \(result.score)?",
                        initialContext: PersonalizationContextBuilder.chatContext(
                            scoreBreakdown: "overall \(result.score)/100; \(scoreBreakdown)"
                        )
                    )
                } label: {
                    Label("Ask the stylist about this score", systemImage: "sparkles")
                        .font(.headline)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTab.ai.palette.accent)
                .foregroundStyle(.white)
            }

            collapsibleAIAnalysis(for: result)
        }
        .padding()
        .background(scanPanel)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(scanPanelBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func scanResultOccasionPicker(for result: OutfitAnalysisResult) -> some View {
        let current = matchingOutfitMemory(for: result)?.occasion ?? currentScanOccasionForContext

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Occasion", systemImage: "calendar")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(scanMuted)

                Spacer()

                Text(current?.displayName ?? "Not tagged")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(scanMuted)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button {
                        updateOccasion(nil, for: result)
                    } label: {
                        Text("Skip")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.vertical, 7)
                            .padding(.horizontal, 10)
                            .foregroundStyle(current == nil ? scanBackground : scanMuted)
                            .background(current == nil ? scanCream : scanBackground.opacity(0.32))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    ForEach(Occasion.allCases.filter(\.isSpecified), id: \.self) { occasion in
                        Button {
                            updateOccasion(occasion, for: result)
                        } label: {
                            Text(occasion.displayName)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .lineLimit(1)
                                .padding(.vertical, 7)
                                .padding(.horizontal, 10)
                                .foregroundStyle(current == occasion ? scanBackground : scanCream)
                                .background(current == occasion ? scanCream : scanBackground.opacity(0.32))
                                .overlay(
                                    Capsule()
                                        .stroke(scanCream.opacity(current == occasion ? 0 : 0.24), lineWidth: 1)
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .background(scanBackground.opacity(0.36))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
    }

    private func updateOccasion(_ occasion: Occasion?, for result: OutfitAnalysisResult) {
        let store = OutfitMemoryStore()
        let memory = ensureOutfitMemory(for: result, store: store)
        store.updateOccasion(for: memory.id, occasion: occasion)
        selectedScanOccasion = occasion ?? .general
        scanMessage = ScanMessage(
            title: occasion == nil ? "Occasion cleared" : "Occasion saved",
            description: occasion.map { "This scan is now tagged for \($0.displayName)." } ?? "This scan no longer has an occasion tag.",
            icon: "calendar",
            isSuccess: true
        )
    }

    private func voiceAssistantButton(for result: OutfitAnalysisResult, darkMode: Bool) -> some View {
        Button {
            if voiceAssistant.isSpeaking {
                voiceAssistant.stop()
            } else {
                voiceAssistant.speak(VoiceScriptBuilder.scanResult(from: result))
            }
        } label: {
            Label(
                voiceAssistant.isSpeaking ? "Stop Voice Summary" : "Listen to Score Summary",
                systemImage: voiceAssistant.isSpeaking ? "speaker.slash.fill" : "speaker.wave.2.fill"
            )
            .font(.subheadline)
            .fontWeight(.bold)
            .frame(maxWidth: .infinity, minHeight: 42)
        }
        .buttonStyle(.bordered)
        .tint(darkMode ? scanCream : AppTab.scan.palette.accent)
        .accessibilityHint("Reads a short personal stylist summary of this scan result aloud.")
    }

    private func speakIfEnabled(_ script: VoiceScript) {
        guard voiceAssistantEnabled else { return }
        voiceAssistant.speak(script)
    }

    private func collapsibleAIAnalysis(for result: OutfitAnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.24)) {
                    isScoreAnalysisExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(isScoreAnalysisExpanded ? "Hide Analysis" : "View Analysis")
                        .font(.subheadline)
                        .fontWeight(.bold)

                    Spacer()

                    Image(systemName: isScoreAnalysisExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .fontWeight(.bold)
                }
                .foregroundStyle(scanCream)
                .padding(12)
                .background(scanBackground.opacity(0.52))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            if isScoreAnalysisExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(analysisCategoryItems(for: result)) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: item.icon)
                                .font(.caption)
                                .foregroundStyle(scanCream)
                                .frame(width: 22)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)

                                Text(item.detail)
                                    .font(.caption)
                                    .foregroundStyle(scanMuted)
                                    .lineLimit(3)
                            }
                        }
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            isShowingFullAnalysis = true
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("View Full Analysis")
                            Image(systemName: "arrow.right")
                        }
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(scanCream)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
                .padding(12)
                .background(scanBackground.opacity(0.38))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .opacity(resultRevealStep >= 3 ? 1 : 0)
        .offset(y: resultRevealStep >= 3 ? 0 : 8)
    }

    private func styleBreakdownBars(for result: OutfitAnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Style Breakdown")
                .font(.headline)

            styleProgressBar(title: "Color Harmony", percent: clampedScore(result.score + 3))
            styleProgressBar(title: "Fit", percent: clampedScore(result.score - 4))
            styleProgressBar(title: "Accessories", percent: clampedScore(result.score - 10))
            styleProgressBar(title: "Weather", percent: clampedScore(result.score))
        }
        .padding(12)
        .background(AppTab.scan.palette.accent.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTab.scan.palette.accent.opacity(0.20), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func styleProgressBar(title: String, percent: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)

                Spacer()

                Text("\(percent)%")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(AppTab.scan.palette.accent)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.10))

                    Capsule()
                        .fill(AppTab.scan.palette.accent)
                        .frame(width: proxy.size.width * CGFloat(percent) / 100)
                }
            }
            .frame(height: 7)
        }
    }

    private func clampedScore(_ score: Int) -> Int {
        min(max(score, 1), 100)
    }

    private func detectedStyleContextCard(for result: OutfitAnalysisResult, darkMode: Bool) -> some View {
        let rankings = styleRankings(for: result)
        let primary = rankings.first ?? StyleRanking(
            name: detectedStyleTitle(for: result),
            confidence: detectedStyleConfidence(for: result),
            reason: "Detected from visible outfit evidence."
        )
        let background = darkMode ? scanBackground.opacity(0.52) : AppTab.scan.palette.accent.opacity(0.10)
        let border = darkMode ? scanPanelBorder : AppTab.scan.palette.accent.opacity(0.20)
        let titleColor = darkMode ? scanMuted : Color.secondary
        let valueColor = darkMode ? Color.white : Color.primary
        let accent = darkMode ? scanCream : AppTab.scan.palette.accent

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Detected Style")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(titleColor)

                    Text(primary.name)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(valueColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 5) {
                    Text("Confidence")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(titleColor)

                    Text("\(primary.confidence)%")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(accent)
                }
            }

            if rankings.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Top style matches")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(titleColor)

                    ForEach(rankings.prefix(3)) { ranking in
                        HStack(spacing: 8) {
                            Text(ranking.name)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(valueColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)

                            Spacer()

                            Text("\(ranking.confidence)%")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(accent)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .background(background)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func detectedStyleTitle(for result: OutfitAnalysisResult) -> String {
        if let topStyle = styleRankings(for: result).first {
            return topStyle.name
        }

        let combined = (
            result.styleBalance + " " +
            result.occasionFit + " " +
            result.formality + " " +
            result.detectedClothingItems.joined(separator: " ") + " " +
            result.environment + " " +
            result.outfitDescription + " " +
            result.summary
        ).lowercased()

        if isUnrecognizedStyleEvidence(combined) {
            return "Unrecognized Item"
        }

        if let sleepwearCategory = sleepwearOrLoungewearCategory(from: combined) {
            return sleepwearCategory
        }

        if hasTraditionalStyleEvidence(combined) {
            return result.styleBalance.localizedCaseInsensitiveContains("traditional") ? result.styleBalance : "Traditional Wear"
        }

        if combined.contains("hoodie") || combined.contains("sneaker") || combined.contains("street") || combined.contains("oversized") {
            return "Streetwear"
        }

        if hasBusinessStyleEvidence(combined) && !isBusinessBlockedByCasualEvidence(combined) {
            return "Business Casual"
        }

        if combined.contains("wedding") || combined.contains("formal") || combined.contains("ceremony") {
            return "Formal"
        }

        if combined.contains("church") || combined.contains("dinner") || combined.contains("event") {
            return "Smart Casual"
        }

        return "Casual"
    }

    private func formalityMismatch(for result: OutfitAnalysisResult) -> FormalityMismatch? {
        guard let mismatch = FormalityMismatchEvaluator.evaluate(
            detectedStyle: detectedStyleTitle(for: result),
            occasion: selectedScanOccasion.canonical
        ) else {
            return nil
        }

        return dismissedFormalityMismatchSignatures.contains(formalityMismatchSignature(for: result, mismatch: mismatch)) ? nil : mismatch
    }

    private func formalityMismatchSignature(for result: OutfitAnalysisResult, mismatch: FormalityMismatch) -> String {
        [
            String(result.score),
            detectedStyleTitle(for: result),
            mismatch.occasion.rawValue,
            mismatch.detectedFormality.rawValue
        ].joined(separator: "|")
    }

    private func formalityMismatchBanner(_ mismatch: FormalityMismatch, result: OutfitAnalysisResult, darkMode: Bool) -> some View {
        let background = darkMode ? Color.orange.opacity(0.14) : Color.orange.opacity(0.10)
        let border = Color.orange.opacity(darkMode ? 0.42 : 0.32)

        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.headline)

            Text(mismatch.message)
                .font(.subheadline)
                .foregroundStyle(darkMode ? scanCream : .primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button {
                dismissedFormalityMismatchSignatures.insert(formalityMismatchSignature(for: result, mismatch: mismatch))
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(darkMode ? scanMuted : .secondary)
                    .padding(6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss occasion warning")
        }
        .padding(12)
        .background(background)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func detectedStyleConfidence(for result: OutfitAnalysisResult) -> Int {
        if let topStyle = styleRankings(for: result).first {
            return topStyle.confidence
        }

        let combined = (
            result.styleBalance + " " +
            result.occasionFit + " " +
            result.formality + " " +
            result.detectedClothingItems.joined(separator: " ") + " " +
            result.environment + " " +
            result.summary
        ).lowercased()
        if isUnrecognizedStyleEvidence(combined) {
            return 35
        }
        if sleepwearOrLoungewearCategory(from: combined) != nil {
            return clampedScore(min(92, max(84, result.score - 2)))
        }

        let itemBoost = min(result.detectedClothingItems.count * 2, 8)
        let qualityBoost = result.imageQuality.localizedCaseInsensitiveContains("clear") ? 2 : 0
        return clampedScore(min(99, max(86, result.score + itemBoost + qualityBoost - 2)))
    }

    private func styleRankings(for result: OutfitAnalysisResult) -> [StyleRanking] {
        let evidence = styleEvidenceText(for: result)
        func ranked(_ rankings: [StyleRanking]) -> [StyleRanking] {
            rankings.sorted { first, second in
                if first.confidence == second.confidence {
                    return first.name < second.name
                }
                return first.confidence > second.confidence
            }
        }

        if isUnrecognizedStyleEvidence(evidence) {
            return ranked([
                StyleRanking(name: "Unrecognized Item", confidence: 35,
                             reason: "The scan did not contain enough reliable clothing evidence for a specific style category."),
                StyleRanking(name: "Casual", confidence: 18, reason: "Casual is possible, but clothing evidence is not reliable enough."),
                StyleRanking(name: "Business Casual", confidence: 0, reason: "Unknown or low-confidence items must not default to business casual.")
            ])
        }

        if let sleepwearCategory = sleepwearOrLoungewearCategory(from: evidence) {
            return ranked([
                StyleRanking(name: sleepwearCategory, confidence: clampedScore(min(96, max(88, result.score))),
                             reason: "Sleepwear, robe, slipper, or indoor comfort signals were detected."),
                StyleRanking(name: "Loungewear", confidence: clampedScore(min(91, max(78, result.score - 5))),
                             reason: "Comfort-focused home clothing is stronger than business styling."),
                StyleRanking(name: "Casual", confidence: 42, reason: "Casual is possible, but sleepwear/loungewear signals are stronger."),
                StyleRanking(name: "Business Casual", confidence: 12, reason: "Sleepwear and slippers block business casual classification.")
            ])
        }

        if hasTraditionalStyleEvidence(evidence) {
            return ranked([
                StyleRanking(name: result.styleBalance.localizedCaseInsensitiveContains("traditional") ? result.styleBalance : "Traditional Wear",
                             confidence: clampedScore(min(98, max(90, result.score + 1))),
                             reason: "Traditional garment features are present."),
                StyleRanking(name: "Cultural Wear", confidence: clampedScore(min(95, max(86, result.score - 2))),
                             reason: "Cultural attire signals are stronger than Western office categories."),
                StyleRanking(name: "Ceremonial Wear", confidence: clampedScore(min(88, max(74, result.score - 8))),
                             reason: "The clothing may fit a cultural event depending on occasion."),
                StyleRanking(name: "Business Casual", confidence: 18, reason: "Traditional clothing should not default to business casual.")
            ])
        }

        if isRuggedCasualEvidence(evidence) {
            let businessCap = businessCasualConfidenceCap(for: evidence)
            return ranked([
                StyleRanking(name: "Casual", confidence: clampedScore(min(98, max(92, result.score + 3))),
                             reason: "Jeans plus hooded, plaid, flannel, or casual top signals point to everyday casual."),
                StyleRanking(name: "Rugged Casual", confidence: clampedScore(min(96, max(88, result.score - 1))),
                             reason: "Plaid/flannel, denim, and boots or casual shoes create a rugged workwear/outdoor feel."),
                StyleRanking(name: "Outdoor Casual", confidence: clampedScore(min(90, max(82, result.score - 6))),
                             reason: "The outfit reads practical and relaxed rather than office-ready."),
                StyleRanking(name: "Smart Casual", confidence: min(35, businessCap + 10),
                             reason: "The look can be cleaned up, but hoodie/flannel plus jeans keeps it casual."),
                StyleRanking(name: "Business Casual", confidence: businessCap,
                             reason: "Business casual is capped low because hoodie/flannel plus jeans lacks business-style anchors.")
            ])
        }

        if isYouthGraphicCasualEvidence(evidence) {
            return ranked([
                StyleRanking(name: "Casual", confidence: clampedScore(min(96, max(88, result.score))),
                             reason: "Graphic, youth, home, relaxed, or everyday clothing signals are stronger than business styling."),
                StyleRanking(name: "Everyday Casual", confidence: clampedScore(min(92, max(80, result.score - 4))),
                             reason: "The visible outfit reads relaxed and practical for normal daily wear."),
                StyleRanking(name: "Loungewear", confidence: clampedScore(min(76, max(45, result.score - 22))),
                             reason: "Home or comfort signals may be present, but visible clothing is not confirmed as sleepwear."),
                StyleRanking(name: "Business Casual", confidence: businessCasualConfidenceCap(for: evidence),
                             reason: "Business casual is capped because no strong business-style anchors were detected.")
            ])
        }

        if hasBusinessStyleEvidence(evidence) && !isBusinessBlockedByCasualEvidence(evidence) {
            let businessConfidence = businessCasualConfidenceCap(for: evidence) == 70
                ? clampedScore(min(70, max(50, result.score - 18)))
                : clampedScore(min(96, max(74, result.score + 1)))
            return ranked([
                StyleRanking(name: "Business Casual", confidence: businessConfidence,
                             reason: "Multiple business-style items are present."),
                StyleRanking(name: "Smart Casual", confidence: clampedScore(min(88, max(68, businessConfidence - 8))),
                             reason: "The outfit may also work as a polished casual look."),
                StyleRanking(name: "Casual", confidence: clampedScore(min(62, max(35, 100 - businessConfidence))),
                             reason: "Casual confidence stays lower when business anchors are visible.")
            ])
        }

        if evidence.contains("hoodie") || evidence.contains("sneaker") || evidence.contains("street") || evidence.contains("oversized") {
            return ranked([
                StyleRanking(name: "Streetwear", confidence: clampedScore(min(94, max(82, result.score - 2))),
                             reason: "Hoodie, sneakers, oversized, or streetwear signals are present."),
                StyleRanking(name: "Casual", confidence: clampedScore(min(92, max(78, result.score - 5))),
                             reason: "The outfit is relaxed and everyday."),
                StyleRanking(name: "Business Casual", confidence: businessCasualConfidenceCap(for: evidence),
                             reason: "Business anchors are not strong enough for a high business casual confidence.")
            ])
        }

        return ranked([
            StyleRanking(name: "Casual", confidence: clampedScore(min(94, max(78, result.score - 2))),
                         reason: "Visible evidence supports a general everyday style."),
            StyleRanking(name: "Smart Casual", confidence: clampedScore(min(72, max(42, result.score - 22))),
                         reason: "Some polish may be possible depending on shoes and accessories."),
            StyleRanking(name: "Business Casual", confidence: businessCasualConfidenceCap(for: evidence),
                         reason: "Business casual requires stronger business-style clothing evidence.")
        ])
    }

    private func styleEvidenceText(for result: OutfitAnalysisResult) -> String {
        (
            result.styleBalance + " " +
            result.occasionFit + " " +
            result.formality + " " +
            result.detectedClothingItems.joined(separator: " ") + " " +
            result.environment + " " +
            result.imageQuality + " " +
            result.outfitDescription + " " +
            result.summary
        ).lowercased()
    }

    private func isUnrecognizedStyleEvidence(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("unrecognized item")
            || lower.contains("category uncertain")
            || lower.contains("unrecognized")
            || lower.contains("could not identify enough reliable clothing detail")
    }

    private func hasTraditionalStyleEvidence(_ text: String) -> Bool {
        let lower = text.lowercased()
        if isYouthGraphicCasualEvidence(lower) || isRuggedCasualEvidence(lower) || sleepwearOrLoungewearCategory(from: lower) != nil {
            return false
        }

        let explicitGarments = [
            "agbada", "senator wear", "isiagu", "buba", "iro", "ankara", "aso oke", "aso-oke",
            "dashiki", "kaftan", "caftan", "kente", "kanzu", "gomesi", "shuka", "habesha",
            "boubou", "djellaba", "gele", "duku", "kimono", "yukata", "hanfu", "qipao",
            "cheongsam", "hanbok", "saree", "sari", "salwar", "sherwani", "kurta", "lehenga",
            "ao dai", "chut thai", "batik", "thobe", "kandura", "dishdasha", "bisht", "abaya",
            "jalabiya", "keffiyeh", "shemagh", "kilt", "lederhosen", "dirndl", "vyshyvanka",
            "flamenco", "charro", "huipil", "pollera", "poncho", "lavalava", "lava-lava",
            "pareo", "korowai", "taovala"
        ]
        let explicitCount = explicitGarments.filter { lower.contains($0) }.count
        guard explicitCount > 0 else { return false }

        let supportCount = traditionalSupportFeatureCount(in: lower)
        return explicitCount >= 1 && supportCount >= 2
    }

    private func isRuggedCasualEvidence(_ text: String) -> Bool {
        let hasDenim = ["jean", "jeans", "denim"].contains { text.contains($0) }
        let hasCasualTop = ["hoodie", "hooded", "flannel", "plaid", "shacket", "overshirt", "casual jacket", "workwear"].contains { text.contains($0) }
        let hasRuggedShoe = ["boot", "boots", "hiking", "work boot", "casual shoe"].contains { text.contains($0) }
        return (hasDenim && hasCasualTop) || (hasDenim && hasRuggedShoe) || (hasCasualTop && hasRuggedShoe)
    }

    private func isYouthGraphicCasualEvidence(_ text: String) -> Bool {
        let childSignal = ["child", "kid", "boy", "girl", "youth", "children"].contains { text.contains($0) }
        let graphicSignal = ["graphic", "cartoon", "character", "printed", "print", "truck", "anime", "marvel", "disney", "pokemon"].contains { text.contains($0) }
        let relaxedBottomSignal = ["patterned pant", "patterned pants", "sweatpant", "sweatpants", "jogger", "joggers", "pajama pant"].contains { text.contains($0) }
        let homeSignal = ["home", "bedroom", "closet", "barefoot", "bare feet", "no shoes", "indoor"].contains { text.contains($0) }
        let casualTopSignal = ["t-shirt", "tee", "long sleeve", "sweatshirt", "hoodie", "graphic shirt", "polo"].contains { text.contains($0) }

        return (childSignal && (graphicSignal || relaxedBottomSignal || homeSignal || casualTopSignal))
            || (graphicSignal && (relaxedBottomSignal || homeSignal || casualTopSignal))
            || (homeSignal && relaxedBottomSignal)
    }

    private func businessStyleSignalCount(in text: String) -> Int {
        let businessTerms = [
            "button-down", "button down", "oxford", "dress shirt", "collared shirt", "polo",
            "chino", "chinos", "dress pant", "dress pants", "trouser", "trousers",
            "blazer", "cardigan", "clean sweater", "loafer", "loafers", "dress shoe",
            "dress shoes"
        ]
        return businessTerms.reduce(0) { count, term in
            text.contains(term) ? count + 1 : count
        }
    }

    private func hasBusinessStyleEvidence(_ text: String) -> Bool {
        businessStyleSignalCount(in: text) >= 2
    }

    private func businessCasualConfidenceCap(for text: String) -> Int {
        let lower = text.lowercased()
        let hasHoodOrFlannel = ["hoodie", "hooded", "flannel", "plaid", "shacket"].contains { lower.contains($0) }
        let hasJeans = ["jean", "jeans", "denim"].contains { lower.contains($0) }
        let hasGraphicYouthOrHome = isYouthGraphicCasualEvidence(lower)

        if hasGraphicYouthOrHome {
            return 15
        }
        if hasHoodOrFlannel && hasJeans {
            return 15
        }
        if hasHoodOrFlannel || hasJeans {
            return min(40, businessStyleSignalCount(in: lower) >= 2 ? 40 : 25)
        }
        return businessStyleSignalCount(in: lower) >= 2 ? 96 : 70
    }

    private func isBusinessBlockedByCasualEvidence(_ text: String) -> Bool {
        let lower = text.lowercased()
        if sleepwearOrLoungewearCategory(from: lower) != nil { return true }
        if isYouthGraphicCasualEvidence(lower) { return true }
        if isRuggedCasualEvidence(lower) { return true }
        let hasCasualBlocker = ["hoodie", "hooded", "flannel", "shacket", "graphic", "cartoon", "character", "barefoot", "slipper"].contains { lower.contains($0) }
        return hasCasualBlocker && businessStyleSignalCount(in: lower) < 2
    }

    private func sleepwearOrLoungewearCategory(from text: String) -> String? {
        let sleepTerms = ["children's sleepwear", "kids sleepwear", "pajama", "pyjama", "sleepwear", "nightgown", "robe", "bathrobe", "fleece robe", "plush robe", "slipper", "house shoe", "sleep sock"]
        if sleepTerms.contains(where: { text.contains($0) }) {
            if ["child", "kid", "girl", "boy", "children"].contains(where: { text.contains($0) }) {
                return "Children's Sleepwear"
            }
            return "Sleepwear"
        }

        let loungeTerms = ["loungewear", "lounge set", "house clothes", "homewear", "indoor outfit", "fuzzy slipper", "plush robe", "blanket hoodie"]
        if loungeTerms.contains(where: { text.contains($0) }) {
            return "Loungewear"
        }

        if let contextualCategory = contextualSleepwearSetCategory(from: text) {
            return contextualCategory
        }

        return nil
    }

    private func contextualSleepwearSetCategory(from text: String) -> String? {
        let homeOrYouthSignals = [
            "bedroom", "bed", "blanket", "pillow", "home", "house", "indoor",
            "child", "kid", "girl", "boy", "children", "youth", "toy"
        ].filter { text.contains($0) }.count
        let matchingSetSignals = [
            "matching set", "coordinated set", "two-piece", "two piece",
            "matching top and bottom", "top and bottom", "matching outfit",
            "shirt and pants set", "pants set"
        ].filter { text.contains($0) }.count
        let comfortPatternSignals = [
            "stripe", "striped", "red and white", "pink and white", "pink red",
            "pastel", "soft", "loose", "barefoot"
        ].filter { text.contains($0) }.count

        guard homeOrYouthSignals > 0, matchingSetSignals > 0, comfortPatternSignals > 0 else {
            return nil
        }

        if ["child", "kid", "girl", "boy", "children", "youth", "toy"].contains(where: { text.contains($0) }) {
            return "Children's Sleepwear"
        }

        return "Sleepwear"
    }

    private func chatGPTStylistSectionsCard(_ sections: [ChatGPTStylistSection], darkMode: Bool) -> some View {
        let background = darkMode ? scanBackground.opacity(0.44) : AppTab.ai.palette.accent.opacity(0.08)
        let border = darkMode ? scanPanelBorder : AppTab.ai.palette.accent.opacity(0.20)
        let titleColor = darkMode ? Color.white : Color.primary
        let bodyColor = darkMode ? scanMuted : Color.secondary
        let accent = darkMode ? scanCream : AppTab.ai.palette.accent

        return VStack(alignment: .leading, spacing: 12) {
            Label(sections.contains(where: { $0.title == "Personal Stylist Intelligence" }) ? "Personal Stylist Intelligence" : "ChatGPT Pro Stylist", systemImage: "sparkles")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(accent)

            ForEach(sections.prefix(7)) { section in
                VStack(alignment: .leading, spacing: 4) {
                    if section.title != "Personal Stylist Intelligence" {
                        Text(section.title)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(titleColor)
                    }

                    Text(section.body)
                        .font(.caption)
                        .foregroundStyle(bodyColor)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .background(background)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func scanAIAssistSheet(for analysis: OutfitAnalysisResult) -> some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            scanAIContextHeader(analysis)

                            ForEach(Array(scanAIChatMessages.enumerated()), id: \.element.id) { index, message in
                                if shouldShowScanAITimestamp(at: index) {
                                    Text(scanAITimestampText(for: message.createdAt))
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 4)
                                }

                                scanAIChatBubble(message, analysis: analysis)
                                    .id(message.id)
                            }

                            if isScanAIThinking {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("ChatGPT is reading this scan...")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 4)
                                .id("scan-ai-thinking")
                            }
                        }
                        .padding()
                    }
                    .styleMatchOnChange(of: scanAIChatMessages.count) { _ in
                        guard let id = scanAIChatMessages.last?.id else { return }
                        withAnimation(.easeInOut(duration: 0.22)) {
                            proxy.scrollTo(id, anchor: .bottom)
                        }
                    }
                }

                Divider()

                VStack(spacing: 10) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(scanAIAssistPrompts, id: \.self) { prompt in
                                Button(prompt) {
                                    sendScanAIMessage(prompt, analysis: analysis)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(isScanAIThinking)
                            }
                        }
                        .padding(.horizontal)
                    }

                    HStack(spacing: 10) {
                        TextField("Ask about this outfit...", text: $scanAIInput, axis: .vertical)
                            .lineLimit(1...4)
                            .textFieldStyle(.roundedBorder)

                        Button {
                            sendScanAIMessage(scanAIInput, analysis: analysis)
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 34))
                        }
                        .disabled(isScanAIThinking || scanAIInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal)
                }
                .padding(.top, 10)
                .padding(.bottom, 12)
                .background(.ultraThinMaterial)
            }
            .background(scanBackground.ignoresSafeArea())
            .navigationTitle("AI Assist")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") {
                        scanAIChatMessages.removeAll()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        isShowingScanAIAssist = false
                    }
                }
            }
        }
    }

    private func scanAIContextHeader(_ analysis: OutfitAnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("StyleMatch Pro AI Assist", systemImage: "sparkles")
                .font(.title3)
                .fontWeight(.bold)

            Text("ChatGPT can read this scan result, explain the score, and answer follow-up questions. StyleMatch Pro still owns the score.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(analysis.score)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(scoreRatingTitle(for: analysis.score))
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text(detectedStyleTitle(for: analysis))
                        .font(.headline)
                    Text(analysis.safeDetectedClothingItems.prefix(4).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding()
        .appCard(.scan, radius: 16)
    }

    private func scanAIChatBubble(_ message: ScanAIChatMessage, analysis: OutfitAnalysisResult) -> some View {
        HStack {
            if message.role == .customer {
                Spacer(minLength: 42)
            }

            VStack(alignment: message.role == .customer ? .trailing : .leading, spacing: 6) {
                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(message.role == .customer ? scanBackground : .primary)
                    .lineSpacing(2)

                HStack(spacing: 8) {
                    if message.isEdited {
                        Text("Edited")
                            .font(.caption2)
                            .foregroundStyle(message.role == .customer ? scanBackground.opacity(0.72) : .secondary)
                    }

                    if let failedPrompt = message.failedPrompt, !failedPrompt.isEmpty {
                        Button("Retry") {
                            retryFailedScanAIMessage(message, analysis: analysis)
                        }
                        .font(.caption)
                        .fontWeight(.bold)
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .disabled(isScanAIThinking)
                    }
                }
            }
            .padding(12)
            .background(message.role == .customer ? scanCream : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))


            if message.role == .assistant {
                Spacer(minLength: 42)
            }
        }
    }

    private var scanAIAssistPrompts: [String] {
        [
            "Why did I get this score?",
            "How can I improve it?",
            "What is the weakest part?",
            "Would white shoes help?",
            "Is this business casual?",
            "Explain color harmony.",
            "Design a custom garment."
        ]
    }

    private func openScanAIAssist(for analysis: OutfitAnalysisResult) {
        if scanAIChatMessages.isEmpty {
            scanAIChatMessages.append(
                ScanAIChatMessage(
                    role: .assistant,
                    text: "I can see this StyleMatch Pro scan: \(analysis.score)/100, \(scoreRatingTitle(for: analysis.score)). Ask why you got this score, what to improve, or what shoes/accessories would work."
                )
            )
        }
        isShowingScanAIAssist = true
    }

    private func sendScanAIMessage(_ rawText: String, analysis: OutfitAnalysisResult) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard !isScanAIThinking else { return }

        scanAIInput = ""
        scanAIChatMessages.append(ScanAIChatMessage(role: .customer, text: text))
        isScanAIThinking = true
        let conversation = activeScanAIConversationHistory()

        Task {
            await requestScanAIReply(for: text, analysis: analysis, conversation: conversation, retryAttempt: 0)
        }
    }

    private func requestScanAIReply(
        for text: String,
        analysis: OutfitAnalysisResult,
        conversation: [AIChatMessage],
        retryAttempt: Int
    ) async {
        do {
            let reply = try await aiReplyForScanMessage(text, analysis: analysis, conversation: conversation)
            await MainActor.run {
                scanAIChatMessages.append(ScanAIChatMessage(role: .assistant, text: reply))
                isScanAIThinking = false
            }
        } catch {
            logScanAIChatFailure(error, prompt: text, retryAttempt: retryAttempt)

            if retryAttempt == 0 {
                try? await Task.sleep(nanoseconds: 750_000_000)
                await requestScanAIReply(for: text, analysis: analysis, conversation: conversation, retryAttempt: 1)
                return
            }

            await MainActor.run {
                let reason = scanAIFailureReason(error)
                let fallbackReply = localScanAIReply(for: text, analysis: analysis, failureReason: reason)
                scanAIChatMessages.append(
                    ScanAIChatMessage(
                        role: .assistant,
                        text: fallbackReply,
                        failedPrompt: text,
                        failureReason: reason
                    )
                )
                isScanAIThinking = false
            }
        }
    }

    private func aiReplyForScanMessage(_ message: String, analysis: OutfitAnalysisResult, conversation: [AIChatMessage]) async throws -> String {
        if isDesignIdeaRequest(message) {
            return try await generateDesignIdea(for: analysis, userRequest: message)
        }

        return try await askChatGPTAboutCurrentScan(message: message, analysis: analysis, conversation: conversation)
    }

    private func activeScanAIConversationHistory() -> [AIChatMessage] {
        scanAIChatMessages
            .filter { $0.failedPrompt == nil }
            .suffix(24)
            .map { item in
                AIChatMessage(
                    role: item.role == .customer ? .customer : .assistant,
                    text: item.text,
                    createdAt: item.createdAt,
                    edited: item.isEdited,
                    editedAt: item.editedAt
                )
            }
    }

    private func retryFailedScanAIMessage(_ message: ScanAIChatMessage, analysis: OutfitAnalysisResult) {
        guard let prompt = message.failedPrompt, !isScanAIThinking else { return }
        scanAIChatMessages.removeAll { $0.id == message.id }
        isScanAIThinking = true
        let conversation = activeScanAIConversationHistory()

        Task {
            await requestScanAIReply(for: prompt, analysis: analysis, conversation: conversation, retryAttempt: 0)
        }
    }

    private func shouldShowScanAITimestamp(at index: Int) -> Bool {
        guard scanAIChatMessages.indices.contains(index) else { return false }
        guard index > 0 else { return true }
        let previous = scanAIChatMessages[index - 1].createdAt
        return scanAIChatMessages[index].createdAt.timeIntervalSince(previous) > 10 * 60
    }

    private func scanAITimestampText(for date: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "h:mm a"
        } else {
            formatter.dateFormat = "MMM d, h:mm a"
        }
        return formatter.string(from: date)
    }

    private func logScanAIChatFailure(_ error: Error, prompt: String, retryAttempt: Int) {
        #if DEBUG
        print("[Scan AI Assist] failure=\(scanAIFailureReason(error)); retryAttempt=\(retryAttempt); promptLength=\(prompt.count); detail=\(error.localizedDescription)")
        #endif
    }

    private func scanAIFailureReason(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return "timeout"
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .secureConnectionFailed:
                return "network"
            case .cancelled:
                return "cancelled"
            default:
                return "url_error_\(urlError.code.rawValue)"
            }
        }

        if let stylistError = error as? OpenAIStylistError {
            switch stylistError {
            case .missingAPIKey:
                return "missing_api_key"
            case .invalidResponse:
                return "invalid_response"
            case .emptyOutput:
                return "empty_output"
            case .api(let message):
                let lower = message.lowercased()
                if lower.contains("unsupported parameter") || lower.contains("max_tokens") || lower.contains("max_completion_tokens") {
                    return "api_parameter"
                }
                if lower.contains("model") && (lower.contains("not supported") || lower.contains("does not exist") || lower.contains("not found")) {
                    return "api_model"
                }
                if lower.contains("rate") || lower.contains("429") {
                    return "rate_limit"
                }
                if lower.contains("sign in") || lower.contains("401") {
                    return "api_auth"
                }
                if lower.contains("quota") || lower.contains("billing") || lower.contains("payment") || lower.contains("insufficient") {
                    return "api_billing"
                }
                return "api_error"
            }
        }

        if error is DecodingError {
            return "parse_error"
        }

        return "unknown"
    }

    private func localScanAIReply(for message: String, analysis: OutfitAnalysisResult, failureReason: String) -> String {
        let lower = message.lowercased()
        let connectionNote = scanAIConnectionNote(for: failureReason)

        if lower.contains("why") || lower.contains("score") {
            return "\(localScoreExplanation(for: analysis))\n\n\(connectionNote)"
        }

        if lower.contains("improve") || lower.contains("better") || lower.contains("fix") {
            return "\(localImprovementAdvice(for: analysis))\n\n\(connectionNote)"
        }

        if lower.contains("shoe") || lower.contains("accessor") || lower.contains("belt") || lower.contains("watch") {
            return "\(localAccessoryAdvice(for: analysis))\n\n\(connectionNote)"
        }

        return "\(localScoreExplanation(for: analysis))\n\n\(localImprovementAdvice(for: analysis))\n\n\(connectionNote)"
    }

    private func localScoreExplanation(for analysis: OutfitAnalysisResult) -> String {
        let breakdown = styleScoreBreakdown(from: analysis)
        let style = detectedStyleTitle(for: analysis)
        let colors = analysis.colorPalette.isEmpty ? "the detected garment colors" : analysis.colorPalette.joined(separator: ", ")
        let items = analysis.safeDetectedClothingItems.isEmpty ? "the visible clothing" : analysis.safeDetectedClothingItems.prefix(4).joined(separator: ", ")

        return """
        StyleMatch Pro gave this outfit \(analysis.score)/100, which is \(scoreRatingTitle(for: analysis.score)). The scan reads as \(style) based on \(items). The strongest points are color harmony (\(breakdown.colorHarmony)/25), pattern balance (\(breakdown.patternBalance)/20), and fit (\(breakdown.fitQuality)/25). The palette found was \(colors), which keeps the outfit coordinated. Occasion match scored \(breakdown.occasionMatch)/20, and accessories scored \(breakdown.accessoryUse)/10 because the scan did not find many finishing pieces.
        """
    }

    private func localImprovementAdvice(for analysis: OutfitAnalysisResult) -> String {
        let firstSuggestion = analysis.suggestions.first ?? "Add one polished finishing piece and make sure the fit is clean on body."
        let secondSuggestion = analysis.suggestions.dropFirst().first ?? "Keep the colors coordinated, but use shoes or a light layer to make the outfit feel more intentional."

        return """
        To improve it, start with this: \(firstSuggestion) Also consider: \(secondSuggestion)
        """
    }

    private func localAccessoryAdvice(for analysis: OutfitAnalysisResult) -> String {
        let style = detectedStyleTitle(for: analysis).lowercased()
        let colors = Set(analysis.colorPalette.map { $0.lowercased() })
        let shoeColor = colors.contains("black") || colors.contains("charcoal") ? "black or charcoal" : "clean white, black, or neutral"

        return """
        For this \(style) outfit, use \(shoeColor) sneakers or casual loafers depending on how polished you want it to feel. A simple black belt, silver watch, or low-profile bracelet would lift the accessory score without changing the outfit's casual direction.
        """
    }

    private func scanAIConnectionNote(for reason: String) -> String {
        "Live ChatGPT is temporarily unavailable in this chat (\(reason)). This answer used the completed StyleMatch Pro scan facts; the score was not changed."
    }

    private func scanAIFailureMessage(for reason: String) -> String {
        switch reason {
        case "missing_api_key":
            return "AI Assist needs ChatGPT activated first. Open AI settings, save your OpenAI key, then try again."
        case "api_auth":
            return "AI Assist could not sign in with the saved ChatGPT key. Recheck the key in AI settings and try again."
        case "api_model":
            return "AI Assist reached ChatGPT, but this model is not available for the saved account. Switch the ChatGPT model in AI settings or update the app build."
        case "api_parameter":
            return "AI Assist reached ChatGPT, but this installed build is using an outdated request setting. Install the latest StyleMatch Pro build and try again."
        case "rate_limit":
            return "AI Assist reached ChatGPT, but the account is rate-limited right now. Try again shortly."
        case "api_billing":
            return "AI Assist reached ChatGPT, but the saved account is blocked by billing or quota. Check the OpenAI account and try again."
        case "cancelled":
            return "AI Assist stopped before ChatGPT finished responding. Try again and keep the app open."
        case "timeout", "network":
            return "AI Assist could not reach ChatGPT from this network. Check the connection and try again."
        default:
            return "AI Assist could not connect to ChatGPT right now. Try again, or recheck ChatGPT setup in AI settings."
        }
    }

    private func isDesignIdeaRequest(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("design")
            || lowered.contains("custom garment")
            || lowered.contains("custom attire")
            || lowered.contains("tailor")
            || lowered.contains("manufacturer")
            || lowered.contains("manufacture")
            || lowered.contains("produce")
            || lowered.contains("make me")
    }

    private func askChatGPTAboutCurrentScan(
        message: String,
        analysis: OutfitAnalysisResult,
        conversation: [AIChatMessage]
    ) async throws -> String {
        guard let savedKey = OpenAIKeychain.loadAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !savedKey.isEmpty else {
            throw OpenAIStylistError.missingAPIKey
        }

        let structuredFacts = structuredOutfitFacts(for: analysis)
        let profile = StyleMatchStylistProfile(
            name: profileName,
            favoriteColors: favoriteColors,
            favoriteBrands: favoriteBrands,
            preferredFit: fitPreference,
            budget: budget,
            sizeProfile: sizeProfile,
            stylePreferences: stylePreferences,
            occasions: activeScanOccasionText(environment: analysis.environment),
            weather: weatherLocationText,
            weatherPreferences: weatherLocationText,
            dressCode: activeScanOccasionText(environment: analysis.environment),
            shoppingHabits: "Budget \(budget); favorite brands \(favoriteBrands); past purchases \(pastPurchases).",
            pastOutfitRatings: "Current scan \(analysis.score)/100. StyleMatch Pro controls the score.",
            frequentlyWornOutfits: favoriteOutfits,
            pastPurchases: pastPurchases,
            favoriteOutfits: favoriteOutfits,
            closetInventory: closetInventory,
            appContextSharingEnabled: true,
            appContext: """
            Current screen: Scan result AI Assist.
            The customer is viewing this exact outfit analysis.
            ChatGPT must use this structured analysis as screen awareness and must not create, change, or override any score.

            Current outfit analysis JSON:
            \(structuredFacts)
            """
        )

        let question = """
        Previous outfit analysis:
        \(structuredFacts)

        User question:
        \(message)

        Answer as StyleMatch Pro's Personal AI Stylist.
        Give specific, actionable recommendations.
        Include actual brand names, price ranges, stores, product types, or closet-item ideas when relevant.
        Keep the response conversational, not JSON, because this is a chat follow-up.
        Do not ask the customer to repeat the score, clothing, colors, lighting, weather, or detected items.
        Do not generate a new score. Explain the existing StyleMatch Pro score only.
        Use garment_colors/colorDetection only for colors and ignore background colors.
        If the previous analysis says a style is casual, rugged casual, sleepwear, traditional wear, or another non-business category, do not call it business casual.
        Keep the answer friendly, direct, professional, fashion-focused, and practical.
        """

        let client = OpenAIStylistClient(apiKey: savedKey, model: openAIModel)
        return try await client.askStylist(profile: profile, messages: conversation, question: question)
    }

    private func generateDesignIdea(for analysis: OutfitAnalysisResult, userRequest: String) async throws -> String {
        guard let savedKey = OpenAIKeychain.loadAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !savedKey.isEmpty else {
            throw OpenAIStylistError.missingAPIKey
        }

        let detectedAttributes = lockedDetectedAttributes(from: analysis)
        let userPrefs = DesignIdeaUserPreferences(
            favoriteColors: favoriteColors,
            favoriteBrands: favoriteBrands,
            preferredFit: fitPreference,
            budget: budget,
            sizeProfile: sizeProfile,
            stylePreferences: stylePreferences,
            occasions: activeScanOccasionText(environment: analysis.environment),
            closetInventory: closetInventory,
            userRequest: userRequest
        )

        let profile = StyleMatchStylistProfile(
            name: profileName,
            favoriteColors: favoriteColors,
            favoriteBrands: favoriteBrands,
            preferredFit: fitPreference,
            budget: budget,
            sizeProfile: sizeProfile,
            stylePreferences: stylePreferences,
            occasions: activeScanOccasionText(environment: analysis.environment),
            weather: weatherLocationText,
            weatherPreferences: weatherLocationText,
            dressCode: activeScanOccasionText(environment: analysis.environment),
            shoppingHabits: "Budget \(budget); favorite brands \(favoriteBrands); past purchases \(pastPurchases).",
            pastOutfitRatings: "Current scan \(analysis.score)/100. StyleMatch Pro controls the score.",
            frequentlyWornOutfits: favoriteOutfits,
            pastPurchases: pastPurchases,
            favoriteOutfits: favoriteOutfits,
            closetInventory: closetInventory,
            appContextSharingEnabled: true,
            appContext: "Custom garment design idea request from scan AI Assist. Occasion context: \(activeScanOccasionText(environment: analysis.environment)). This feature suggests attire concepts only and must not change the outfit score."
        )

        let client = OpenAIStylistClient(apiKey: savedKey, model: openAIModel)
        let response = try await client.askStylist(
            profile: profile,
            messages: [],
            question: buildDesignIdeaPrompt(detectedAttributes: detectedAttributes, userPrefs: userPrefs)
        )

        if let designIdea = parseDesignIdea(from: response) {
            return formatDesignIdea(designIdea)
        }

        return designIdeaFallback(for: analysis, userRequest: userRequest)
    }

    private func buildDesignIdeaPrompt(detectedAttributes: DetectedStyleAttributes, userPrefs: DesignIdeaUserPreferences) -> String {
        let stylistProfile = ProfileStore().currentProfile
        let outfitMemories = OutfitMemoryStore().memories
        let personalStylistMemorySection = PersonalizationContextBuilder.promptSection(
            title: "PERSONAL STYLIST MEMORY (read-only design personalization context; do not create or change scan scores)",
            profile: stylistProfile,
            recentMemories: outfitMemories,
            currentOccasion: currentScanOccasionForContext
        )

        return """
        You are a fashion designer assistant helping a user design a custom garment to be produced, tailored, printed, or manufactured.

        Based on this user's detected style profile and preferences, suggest a custom attire design concept.
        Use the personal stylist context to respect stated color, fit, brand, budget, and size preferences.
        Avoid repeating patterns, fits, colors, or garment ideas from recently disliked outfit memories when the context provides them.
        Reference the user's budget range when suggesting fabrics, construction details, or alternatives.
        If the personal stylist context has no outfit memories yet, use profile-only preferences and do not pretend memory exists.
        Use the occasion in USER PREFERENCES as a filter and hint. For a wedding or formal event, suggest elevated fabrics, layers, and finishing details; for casual or travel, suggest comfortable and practical pieces. Combine occasion with PERSONAL STYLIST MEMORY rather than replacing it.

        DETECTED STYLE PROFILE:
        \(jsonString(detectedAttributes))

        USER PREFERENCES:
        \(jsonString(userPrefs))

        \(personalStylistMemorySection)

        Return ONLY valid JSON:
        {
          "design_concept": "string - overall concept description",
          "garment_type": "string (e.g. shirt, jacket, dress)",
          "suggested_colors": ["color1", "color2"],
          "suggested_fabric": "string",
          "suggested_pattern": "string or 'solid'",
          "fit_style": "string (e.g. slim, relaxed, tailored)",
          "design_notes": "string - specific details for a tailor/manufacturer to follow",
          "estimated_price_range": "string"
        }
        """
    }

    private func parseDesignIdea(from response: String) -> CustomGarmentDesignIdea? {
        let cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let jsonText: String
        if let start = cleaned.firstIndex(of: "{"),
           let end = cleaned.lastIndex(of: "}"),
           start <= end {
            jsonText = String(cleaned[start...end])
        } else {
            jsonText = cleaned
        }

        guard let data = jsonText.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode(CustomGarmentDesignIdea.self, from: data)
    }

    private func formatDesignIdea(_ idea: CustomGarmentDesignIdea) -> String {
        let colors = safeDesignColors(idea.suggestedColors)

        return """
        Custom design concept: \(idea.designConcept)

        Garment: \(idea.garmentType)
        Colors: \(colors)
        Fabric: \(idea.suggestedFabric)
        Pattern: \(idea.suggestedPattern)
        Fit: \(idea.fitStyle)
        Estimated price: \(idea.estimatedPriceRange)

        Tailor/manufacturer notes: \(idea.designNotes)
        """
    }

    private func safeDesignColors(_ suggestedColors: [String]) -> String {
        let dislikedColors = Set(
            ProfileStore().currentProfile.dislikedColors
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )

        let filtered = suggestedColors.filter { color in
            let normalized = color.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !normalized.isEmpty && !dislikedColors.contains(normalized)
        }

        return filtered.isEmpty ? "profile-safe preferred colors" : filtered.joined(separator: ", ")
    }

    private func designIdeaFallback(for analysis: OutfitAnalysisResult, userRequest: String) -> String {
        let colors = analysis.colorPalette.prefix(3).joined(separator: ", ")
        let style = detectedStyleTitle(for: analysis)
        let request = userRequest.trimmingCharacters(in: .whitespacesAndNewlines)

        return """
        Custom design concept: \(request.isEmpty ? "Personalized StyleMatch Pro garment" : request)

        Garment: \(analysis.safeDetectedClothingItems.first ?? "versatile wardrobe piece")
        Colors: \(colors.isEmpty ? "neutral" : colors)
        Fabric: comfortable seasonal fabric
        Pattern: \(inferredPatternFacts(for: analysis).first ?? "solid")
        Fit: \(fitPreference)
        Estimated price: \(budget)

        Tailor/manufacturer notes: Keep the design aligned with \(style), the saved StyleMatch Pro score of \(analysis.score)/100, and the user's saved size profile. This fallback was generated because the AI design JSON could not be parsed safely.
        """
    }

    private func displayedScore(for result: OutfitAnalysisResult) -> Int {
        min(animatedScore, result.score)
    }

    private func resetResultAnimation() {
        animatedScore = 0
        resultRevealStep = 0
        isScoreAnalysisExpanded = false
    }

    private func startResultAnimation(to finalScore: Int) {
        resetResultAnimation()

        let keyframes = [
            0,
            max(12, Int(Double(finalScore) * 0.16)),
            Int(Double(finalScore) * 0.42),
            Int(Double(finalScore) * 0.80),
            finalScore
        ]

        for (index, score) in keyframes.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.16) {
                withAnimation(.easeOut(duration: 0.18)) {
                    animatedScore = min(score, finalScore)
                    resultRevealStep = max(resultRevealStep, index + 1)
                }
            }
        }

        for step in 6...8 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * 0.12) {
                withAnimation(.easeOut(duration: 0.24)) {
                    resultRevealStep = max(resultRevealStep, step)
                }
            }
        }
    }

    private func highScoreCelebrationCard(_ result: OutfitAnalysisResult) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(scanBackground)
                .frame(width: 46, height: 46)
                .background(scanCream)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("Excellent Outfit!")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                Text("Top 5%")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(scanCream)
            }

            Spacer()

            Button {
                saveHighScoreFavorite(result)
            } label: {
                Text(isHighScoreFavoriteSaved(result) ? "Saved" : "Save to Favorites")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(scanBackground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(scanCream)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isHighScoreFavoriteSaved(result))
        }
        .padding(12)
        .background(scanCream.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(scanCream.opacity(0.38), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func highScoreFavoriteTitle(for result: OutfitAnalysisResult) -> String {
        let palette = result.colorPalette
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !["Neutral", "Dark", "Light"].contains($0) }

        let item = result.detectedClothingItems
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        return [palette, item, "Top 5% Outfit"]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    private func isHighScoreFavoriteSaved(_ result: OutfitAnalysisResult) -> Bool {
        favoriteOutfits
            .lowercased()
            .contains(highScoreFavoriteTitle(for: result).lowercased())
    }

    private func saveHighScoreFavorite(_ result: OutfitAnalysisResult) {
        let favoriteTitle = highScoreFavoriteTitle(for: result)
        guard !isHighScoreFavoriteSaved(result) else {
            return
        }

        let trimmedFavorites = favoriteOutfits.trimmingCharacters(in: .whitespacesAndNewlines)
        favoriteOutfits = trimmedFavorites.isEmpty ? favoriteTitle : "\(trimmedFavorites), \(favoriteTitle)"
        scanMessage = ScanMessage(
            title: "Saved to Favorites",
            description: "\(favoriteTitle) was added to your favorite outfits so your AI Stylist can remember it.",
            icon: "heart.fill",
            isSuccess: true
        )
    }

    private func scoreExplanationBullets(for result: OutfitAnalysisResult) -> [String] {
        var explanations: [String] = []
        let paletteText = scorePaletteDescription(for: result)
        let detectedText = result.detectedClothingItems.joined(separator: " ").lowercased()

        if result.score >= 84 {
            explanations.append("The \(paletteText) palette creates strong visual balance.")
        } else {
            explanations.append("The \(paletteText) palette is close, but one clearer color anchor would make it stronger.")
        }

        if result.score >= 80 {
            explanations.append("The outfit proportions feel balanced and easy to wear.")
        } else {
            let sharperAnchor = isHotWeatherContext ? "belt, breathable shoe, or crisp lightweight shirt" : "weather-appropriate layer, belt, or shoe choice"
            explanations.append("The proportions need one sharper anchor, like a cleaner \(sharperAnchor).")
        }

        let recommendationText = result.recommendations
            .map { "\($0.category) \($0.title) \($0.reason)" }
            .joined(separator: " ")
            .lowercased()

        if recommendationText.contains("shoe") || result.detectedClothingItems.contains(where: { $0.localizedCaseInsensitiveContains("shoe") }) {
            explanations.append("The shoe color blends well with the outfit, but a brighter sneaker would create more contrast.")
        } else {
            explanations.append("One intentional accessory, like a watch, belt, or clean bag, would make the outfit feel more styled.")
        }

        if recommendationText.contains("shirt") || detectedText.contains("shirt") || detectedText.contains("top") {
            explanations.append("The oversized shirt gives a relaxed streetwear aesthetic while still leaving room for a cleaner fit.")
        } else {
            explanations.append("The fit reads relaxed and wearable; one cleaner layer would make the silhouette sharper.")
        }

        return Array(explanations.prefix(4))
    }

    private func scorePaletteDescription(for result: OutfitAnalysisResult) -> String {
        let colors = result.colorPalette
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .prefix(2)

        if colors.count == 2 {
            return colors.joined(separator: " and ")
        }

        if let color = colors.first {
            return color
        }

        return "main color"
    }

    private func scoreExplanationIcon(for explanation: String) -> String {
        let lowered = explanation.lowercased()

        if lowered.contains("color") || lowered.contains("palette") {
            return "🎨"
        }

        if lowered.contains("proportion") {
            return "👕"
        }

        if lowered.contains("shoe") {
            return "👟"
        }

        if lowered.contains("shirt") || lowered.contains("fit") || lowered.contains("oversized") {
            return "📏"
        }

        if lowered.contains("accessory") {
            return "⌚"
        }

        return "✨"
    }

    private func analysisCategoryItems(for result: OutfitAnalysisResult) -> [AnalysisCategoryItem] {
        let paletteText = result.colorPalette.prefix(3).joined(separator: ", ")
        let fitDetail = scoreExplanationBullets(for: result).first { $0.localizedCaseInsensitiveContains("fit") || $0.localizedCaseInsensitiveContains("shirt") } ?? "Fit is reviewed using your saved size profile and visible proportions."
        let accessoryDetail = result.recommendations.first { recommendation in
            let category = recommendation.category.lowercased()
            return category.contains("shoe") || category.contains("accessor") || category.contains("watch") || category.contains("bag") || category.contains("finish")
        }.map { "\($0.title). \($0.reason)" } ?? "One intentional accessory can make the outfit feel more finished."
        let improvementDetail = result.suggestions.first ?? "Try one cleaner color bridge, sharper shoes, or a better-fitting layer."

        return [
            AnalysisCategoryItem(
                title: "Colors",
                icon: "paintpalette.fill",
                detail: "Palette detected: \(paletteText.isEmpty ? "balanced neutral tones" : paletteText). \(scoreExplanationBullets(for: result).first ?? "The colors work together cleanly.")"
            ),
            AnalysisCategoryItem(
                title: "Patterns",
                icon: "circle.grid.cross.fill",
                detail: "Patterns and solids read balanced; keep one statement texture or print as the main focus."
            ),
            AnalysisCategoryItem(
                title: "Fit",
                icon: "ruler.fill",
                detail: fitDetail
            ),
            AnalysisCategoryItem(
                title: "Accessories",
                icon: "sparkles",
                detail: accessoryDetail
            ),
            AnalysisCategoryItem(
                title: "Occasion",
                icon: "calendar",
                detail: "\(result.occasionFit). The outfit reads \(detectedStyleTitle(for: result).lowercased()) with \(result.formality.lowercased()) formality."
            ),
            AnalysisCategoryItem(
                title: "Weather",
                icon: "cloud.sun.fill",
                detail: compactWeatherRecommendation.replacingOccurrences(of: "\n", with: " ")
            ),
            AnalysisCategoryItem(
                title: "Improvement Tips",
                icon: "lightbulb.fill",
                detail: improvementDetail
            )
        ]
    }

    private func messageCard(_ message: ScanMessage) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: message.icon)
                .font(.title3)
                .foregroundStyle(message.isSuccess ? .green : .orange)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(message.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(message.description)
                    .foregroundStyle(scanMuted)
                    .lineSpacing(4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(scanPanel)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(scanPanelBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func resultCard(_ result: OutfitAnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(displayedScore(for: result))")
                        .font(.system(size: 88, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTab.scan.palette.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text("Overall Style Score")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)

                    scoreStars(for: result.score, font: .title3)

                    Text(scoreRatingTitle(for: result.score))
                        .font(.title3)
                        .fontWeight(.bold)
                }

                Spacer()
            }
            .padding(.bottom, 2)

            detectedStyleContextCard(for: result, darkMode: false)

            if let mismatch = formalityMismatch(for: result) {
                formalityMismatchBanner(mismatch, result: result, darkMode: false)
            }

            Text(result.summary)
                .foregroundStyle(.primary)
                .lineSpacing(4)

            if !result.chatGPTStylistSections.isEmpty {
                chatGPTStylistSectionsCard(result.chatGPTStylistSections, darkMode: false)
            }

            styleBreakdownBars(for: result)

            Divider()

            metricRow(title: "Color Match", value: result.colorMatch, icon: "paintpalette")
            metricRow(title: "Occasion Fit", value: result.occasionFit, icon: "calendar")
            metricRow(title: "Style Balance", value: result.styleBalance, icon: "scale.3d")
            metricRow(title: "Color Harmony", value: result.colorHarmony, icon: "circle.hexagongrid")
            metricRow(title: "Style Coordination", value: result.styleCoordination, icon: "slider.horizontal.3")
            metricRow(title: "Formality", value: result.formality, icon: "briefcase")
            metricRow(title: "Seasonal Match", value: result.seasonalMatch, icon: "cloud.sun")
            metricRow(title: "Environment", value: result.environment, icon: "mappin.and.ellipse")
            metricRow(title: "Image Quality", value: result.imageQuality, icon: "camera.metering.center.weighted")

            VStack(alignment: .leading, spacing: 10) {
                Text("Detected Details")
                    .font(.headline)

                Text(result.outfitDescription)
                    .foregroundStyle(.secondary)

                if !result.safeDetectedClothingItems.isEmpty {
                    Text("Items: \(result.safeDetectedClothingItems.joined(separator: ", "))")
                        .foregroundStyle(.secondary)
                }

                detectedItemsConfidenceCard(for: result)

                Text("Palette: \(result.colorPalette.joined(separator: ", "))")
                    .foregroundStyle(.secondary)

                Text(result.skinToneStyleNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Suggestions")
                    .font(.headline)

                ForEach(result.suggestions, id: \.self) { suggestion in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .padding(.top, 2)
                        Text(suggestion)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("AI Clothing Recommendations")
                    .font(.headline)

                ForEach(result.recommendations) { recommendation in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(recommendation.category)
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }

                        Text(recommendation.title)
                            .fontWeight(.semibold)

                        Text(recommendation.reason)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Label(recommendation.personalization, systemImage: "person.crop.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .appCard(.scan, radius: 14)
                }
            }
        }
        .padding()
        .appCard(.scan, radius: 18)
    }

    private func detectedItemsConfidenceCard(for result: OutfitAnalysisResult) -> some View {
        let rows = confidenceRows(for: result)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Detected Items")
                .font(.subheadline)
                .fontWeight(.bold)

            ForEach(rows) { row in
                HStack(spacing: 10) {
                    Image(systemName: detectedItemIcon(for: row.item))
                        .font(.caption)
                        .foregroundStyle(AppTab.scan.palette.accent)
                        .frame(width: 22)

                    Text(row.item)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.10))

                            Capsule()
                                .fill(AppTab.scan.palette.accent)
                                .frame(width: proxy.size.width * CGFloat(row.confidence) / 100)
                        }
                    }
                    .frame(height: 6)

                    Text("\(row.confidence)%")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }
            }
        }
        .padding(12)
        .background(AppTab.scan.palette.accent.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTab.scan.palette.accent.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func confidenceRows(for result: OutfitAnalysisResult) -> [DetectedItemConfidence] {
        if !result.detectedItemConfidences.isEmpty {
            let sanitized = result.detectedItemConfidences.prefix(6).compactMap { confidence -> DetectedItemConfidence? in
                guard let item = GarmentLabelMapper.humanReadableTerm(for: confidence.item) else {
                    return nil
                }
                return DetectedItemConfidence(item: item, confidence: confidence.confidence)
            }
            if !sanitized.isEmpty {
                return sanitized
            }
        }

        return result.safeDetectedClothingItems
            .prefix(6)
            .enumerated()
            .map { index, item in
                DetectedItemConfidence(item: item, confidence: max(82, 99 - index * 3))
            }
    }

    private func detectedItemIcon(for item: String) -> String {
        let lowered = item.lowercased()

        if lowered.contains("shoe") || lowered.contains("sneaker") || lowered.contains("loafer") {
            return "shoeprints.fill"
        }

        if lowered.contains("pant") || lowered.contains("jean") || lowered.contains("trouser") || lowered.contains("chino") {
            return "figure.stand"
        }

        if lowered.contains("watch") {
            return "applewatch"
        }

        if lowered.contains("bag") {
            return "bag.fill"
        }

        if lowered.contains("hat") || lowered.contains("cap") {
            return "graduationcap.fill"
        }

        if lowered.contains("shirt") || lowered.contains("top") || lowered.contains("jacket") || lowered.contains("dress") || lowered.contains("clothing") {
            return "tshirt.fill"
        }

        return "sparkles"
    }

    private func quickResultCard(_ result: OutfitAnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Try this next")
                .font(.headline)
                .foregroundStyle(.white)

            ForEach(Array(result.recommendations.prefix(3).enumerated()), id: \.element.id) { index, recommendation in
                tryNextRecommendationRow(recommendation)
                    .opacity(resultRevealStep >= 6 + index ? 1 : 0)
                    .offset(y: resultRevealStep >= 6 + index ? 0 : 10)
            }

            Divider()
                .opacity(resultRevealStep >= 8 ? 1 : 0)

            Text(result.suggestions.first ?? "Add one sharper piece to make the outfit feel more complete.")
                .font(.subheadline)
                .foregroundStyle(scanMuted)
                .opacity(resultRevealStep >= 8 ? 1 : 0)
                .offset(y: resultRevealStep >= 8 ? 0 : 8)
        }
        .padding()
        .background(scanPanel)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(scanPanelBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func tryNextRecommendationRow(_ recommendation: ClothingRecommendation) -> some View {
        Button {
            selectedTryNextRecommendation = recommendation
            isShowingTryNextActions = true
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: recommendationIcon(for: recommendation.category))
                    .font(.headline)
                    .foregroundStyle(scanCream)
                    .frame(width: 38, height: 38)
                    .background(scanCream.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(recommendation.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Text(tryNextActionLabel(for: recommendation))
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(scanCream)
                }

                Spacer()

                Image(systemName: "chevron.right.circle.fill")
                    .font(.title3)
                    .foregroundStyle(scanCream.opacity(0.9))
            }
            .padding(10)
            .background(scanBackground.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(scanPanelBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func tryNextActionLabel(for recommendation: ClothingRecommendation) -> String {
        if recommendationLooksInCloset(recommendation) {
            return "Already in Closet"
        }

        let category = recommendation.category.lowercased()
        if category.contains("shoe") || category.contains("jacket") || category.contains("watch") || category.contains("handbag") || category.contains("finish") {
            return "Tap to Shop"
        }

        return "View Similar"
    }

    private func recommendationLooksInCloset(_ recommendation: ClothingRecommendation) -> Bool {
        let closetText = closetInventory.lowercased()
        guard !closetText.isEmpty else {
            return false
        }

        let terms = (recommendation.title + " " + recommendation.category)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { term in
                term.count > 3 && !["with", "that", "look", "outfit", "clean", "style", "match", "finish"].contains(term)
            }

        return terms.contains { closetText.contains($0) }
    }

    private func handleTryNextAction(_ action: TryNextAction) {
        guard let recommendation = selectedTryNextRecommendation else {
            return
        }

        let title: String
        let description: String
        let icon: String

        switch action {
        case .shop:
            title = "Shopping idea ready"
            description = "Look for \(recommendation.title.lowercased()) in Smart Shopping. Style Match Pro will use your budget, closet, and favorite brands."
            icon = "bag"
        case .similar:
            title = "Similar items suggested"
            description = "Use this as a guide: \(recommendation.reason)"
            icon = "rectangle.grid.2x2"
        case .closet:
            title = "Closet match noted"
            description = "Style Match Pro will treat \(recommendation.title.lowercased()) as something you may already own when giving outfit ideas."
            icon = "tshirt"
        case .askAI:
            title = "Ask AI Stylist"
            description = "Ask your AI Stylist how to use \(recommendation.title.lowercased()) with your saved sizes, budget, and closet."
            icon = "sparkles"
        }

        scanMessage = ScanMessage(
            title: title,
            description: description,
            icon: icon,
            isSuccess: true
        )
    }

    private func recentScoresCard(scrollProxy: ScrollViewProxy) -> some View {
        let scans = recentStoredScans
        let filteredScans = scans.filter { scan in
            selectedScanHistoryFilter.includes(scan, favoriteOutfits: favoriteOutfits)
        }

        return VStack(alignment: .leading, spacing: 14) {
            styleProgressOverTimeCard(scans)

            HStack {
                Label("Recent outfit scores", systemImage: "clock")
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                if !scans.isEmpty {
                    Button(isEditingScanHistory ? "Done" : "Edit") {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                            isEditingScanHistory.toggle()
                            if !isEditingScanHistory {
                                selectedScanIDs.removeAll()
                            }
                        }
                    }
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(scanCream)
                }

                Text("\(scans.count)/20")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(scanMuted)
            }

            scanHistoryFilterBar

            if isEditingScanHistory && !scans.isEmpty {
                HStack(spacing: 10) {
                    Text("\(selectedScanIDs.count) selected")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(scanMuted)

                    Spacer()

                    Button("Select All") {
                        selectedScanIDs = Set(filteredScans.map(\.id))
                    }
                    .font(.caption)
                    .foregroundStyle(scanCream)

                    Button("Delete Selected", role: .destructive) {
                        isShowingDeleteAllConfirmation = true
                    }
                    .font(.caption)
                    .disabled(selectedScanIDs.isEmpty)

                    Button("Delete All", role: .destructive) {
                        selectedScanIDs.removeAll()
                        isShowingDeleteAllConfirmation = true
                    }
                    .font(.caption)
                }
                .padding(10)
                .background(scanPanel)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if scans.isEmpty {
                Text("Your recent scans will appear here after you analyze photos.")
                    .font(.subheadline)
                    .foregroundStyle(scanMuted)
            } else if filteredScans.isEmpty {
                Text("No \(selectedScanHistoryFilter.title.lowercased()) scans yet.")
                    .font(.subheadline)
                    .foregroundStyle(scanMuted)
            } else {
                ForEach(filteredScans) { scan in
                    recentScoreRow(scan, scrollProxy: scrollProxy)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.98)), removal: .opacity.combined(with: .move(edge: .trailing))))
                }
            }
        }
        .padding()
        .background(Color.clear)
    }

    private func styleProgressOverTimeCard(_ scans: [RecentOutfitScore]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Style Progress", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)
                .foregroundStyle(.white)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                progressOverTimeMetric(title: "Average Score", value: averageScoreText(from: scans), icon: "sum")
                progressOverTimeMetric(title: "Highest Score", value: highestScoreText(from: scans), icon: "star.fill")
                progressOverTimeMetric(title: "Outfits Scanned", value: outfitsScannedText(from: scans), icon: "camera.fill")
                progressOverTimeMetric(title: "Closet Items", value: scanClosetItemCountText, icon: "tshirt.fill")
            }
        }
        .padding()
        .background(scanPanel)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(scanPanelBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func progressOverTimeMetric(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(scanCream)

            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(scanMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 94, alignment: .topLeading)
        .padding(12)
        .background(scanBackground.opacity(0.48))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func averageScoreText(from scans: [RecentOutfitScore]) -> String {
        guard !scans.isEmpty else {
            return "88"
        }

        let total = scans.map(\.score).reduce(0, +)
        return "\(Int((Double(total) / Double(scans.count)).rounded()))"
    }

    private func highestScoreText(from scans: [RecentOutfitScore]) -> String {
        guard let highest = scans.map(\.score).max() else {
            return "96"
        }

        return "\(highest)"
    }

    private func outfitsScannedText(from scans: [RecentOutfitScore]) -> String {
        guard !scans.isEmpty else {
            return "347"
        }

        let totalScans = scans.map(\.scanCount).reduce(0, +)
        return "\(max(totalScans, scans.count))"
    }

    private var scanClosetItemCountText: String {
        guard !closetItemsData.isEmpty,
              let items = try? JSONDecoder().decode([ClosetItem].self, from: closetItemsData),
              !items.isEmpty else {
            return "148"
        }

        return "\(items.count)"
    }

    private var scanHistoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ScanHistoryFilter.allCases) { filter in
                    Button {
                        selectedScanHistoryFilter = filter
                    } label: {
                        Text(filter.title)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(selectedScanHistoryFilter == filter ? scanBackground : scanCream)
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selectedScanHistoryFilter == filter ? scanCream : scanPanel)
                            .overlay(
                                Capsule()
                                    .stroke(scanCream.opacity(0.34), lineWidth: 1)
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func recentScoreRow(_ scan: RecentOutfitScore, scrollProxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                if isEditingScanHistory {
                    toggleScanSelection(scan)
                } else {
                    openSavedScan(scan, scrollProxy: scrollProxy)
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    if isEditingScanHistory {
                        Image(systemName: selectedScanIDs.contains(scan.id) ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(selectedScanIDs.contains(scan.id) ? scanCream : scanMuted)
                            .padding(.top, 16)
                    }

                    recentScanThumbnail(scan)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(scan.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        Text(scan.dateText)
                            .font(.caption)
                            .foregroundStyle(scanMuted)

                        Text(scan.styleContextText)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(scanCream.opacity(0.9))
                            .lineLimit(1)

                        if let occasionText = scan.occasionText {
                            Label(occasionText, systemImage: "calendar")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(scanMuted)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(scan.score)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(scanCream)

                        Text(scan.scoreRatingTitle)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(scanMuted)
                            .lineLimit(1)

                        scoreStars(for: scan.score, font: .caption2)
                    }

                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title3)
                        .foregroundStyle(scanCream.opacity(0.9))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.35)
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                            isEditingScanHistory = true
                            selectedScanIDs.insert(scan.id)
                        }
                    }
            )

            Divider()
                .overlay(scanPanelBorder)

            if !isEditingScanHistory {
                savedScanOccasionRow(scan)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    scanHistoryActionButton(title: "Open", icon: "folder") {
                        openSavedScan(scan, scrollProxy: scrollProxy)
                    }

                    scanHistoryActionButton(title: "Compare", icon: "arrow.left.arrow.right") {
                        compareSavedScan(scan)
                    }

                    scanHistoryActionButton(title: "Rescan", icon: "camera.viewfinder") {
                        rescanSavedScan(scan)
                    }

                    ShareLink(item: scan.shareText) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(scanCream)
                            .lineLimit(1)
                            .minimumScaleFactor(0.74)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(scanBackground.opacity(0.48))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    scanHistoryActionButton(title: scan.isFavorite(in: favoriteOutfits) ? "Favorited" : "Favorite", icon: scan.isFavorite(in: favoriteOutfits) ? "heart.fill" : "heart") {
                        toggleFavoriteScan(scan)
                    }

                    scanHistoryActionButton(title: "Rename", icon: "pencil") {
                        beginRename(scan)
                    }

                    scanHistoryActionButton(title: "Delete", icon: "trash") {
                        confirmDelete(scan)
                    }

                    scanHistoryActionButton(title: "More", icon: "ellipsis") {
                        duplicateSavedScan(scan)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(scanPanel)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(scanPanelBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            Button("Open") { openSavedScan(scan, scrollProxy: scrollProxy) }
            Button("Compare") { compareSavedScan(scan) }
            Button("Rescan") { rescanSavedScan(scan) }
            Button(scan.isFavorite(in: favoriteOutfits) ? "Remove Favorite" : "Favorite") { toggleFavoriteScan(scan) }
            Button("Rename") { beginRename(scan) }
            Button("Move to Closet") { moveScanToCloset(scan) }
            Button("Duplicate") { duplicateSavedScan(scan) }
            Button("Export") { exportSavedScan(scan) }
            Button("Delete", role: .destructive) { confirmDelete(scan) }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                confirmDelete(scan)
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                toggleFavoriteScan(scan)
            } label: {
                Label("Favorite", systemImage: "heart.fill")
            }
            .tint(.pink)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                exportSavedScan(scan)
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .tint(.blue)

            Button {
                beginRename(scan)
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.orange)
        }
    }

    private func savedScanOccasionRow(_ scan: RecentOutfitScore) -> some View {
        Menu {
            Button("Clear occasion") {
                updateSavedScanOccasion(nil, for: scan)
            }

            ForEach(Occasion.allCases.filter(\.isSpecified), id: \.self) { occasion in
                Button(occasion.displayName) {
                    updateSavedScanOccasion(occasion, for: scan)
                }
            }
        } label: {
            HStack(spacing: 10) {
                Label("Occasion", systemImage: "calendar")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(scanCream)

                Spacer()

                Text(scan.occasionText ?? "Add tag")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(scan.occasionText == nil ? scanMuted : scanCream.opacity(0.9))
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(scanMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(scanBackground.opacity(0.38))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Adds or changes the occasion tag for this saved scan.")
    }

    private func scanHistoryActionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(scanCream)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(scanBackground.opacity(0.48))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func scoreRatingTitle(for score: Int) -> String {
        switch score {
        case 92...100:
            return "Excellent Match"
        case 86...91:
            return "Strong Match"
        case 78...85:
            return "Good Match"
        case 65...77:
            return "Style Tune-Up"
        default:
            return "Needs Styling"
        }
    }

    private func scoreStarCount(for score: Int) -> Int {
        switch score {
        case 92...100:
            return 5
        case 84...91:
            return 4
        case 72...83:
            return 3
        case 60...71:
            return 2
        default:
            return 1
        }
    }

    private func scoreStars(for score: Int, font: Font) -> some View {
        let filledStars = scoreStarCount(for: score)

        return HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { index in
                Image(systemName: index <= filledStars ? "star.fill" : "star")
            }
        }
        .font(font)
        .foregroundStyle(scanCream)
        .accessibilityLabel("\(filledStars) out of 5 stars")
    }

    @ViewBuilder
    private func recentScanThumbnail(_ scan: RecentOutfitScore) -> some View {
        ZStack {
            if let image = scan.thumbnailImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [scanCream.opacity(0.28), scanPanelBorder.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Image(systemName: "camera.fill")
                    .font(.title3)
                    .foregroundStyle(scanCream)
            }
        }
        .frame(width: 58, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(scanPanelBorder, lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    private func openSavedScan(_ scan: RecentOutfitScore, scrollProxy: ScrollViewProxy) {
        invalidateActiveScanSession()
        selectedItem = nil
        selectedImage = nil
        selectedUIImage = nil
        isAnalyzing = false
        isPreparingCamera = false
        result = scan.analysis
        preparedAnalysis = scan.analysis
        ensureOutfitMemory(for: scan.analysis)
        isShowingFullAnalysis = false
        scanMessage = ScanMessage(
            title: "Saved score opened",
            description: "This previous outfit score is now open above.",
            icon: "clock",
            isSuccess: true
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeInOut(duration: 0.25)) {
                scrollProxy.scrollTo("loadedScanResult", anchor: .top)
            }
        }
    }

    private func updateSavedScanOccasion(_ occasion: Occasion?, for scan: RecentOutfitScore) {
        var history = loadScanHistory()
        guard var stored = history[scan.id] else {
            updateOccasion(occasion, for: scan.analysis)
            return
        }

        stored.occasion = occasion?.canonical
        history[scan.id] = stored
        saveScanHistory(history)
        updateOccasion(occasion, for: scan.analysis)
    }

    private func compareSavedScan(_ scan: RecentOutfitScore) {
        guard let currentScore = result?.score else {
            invalidateActiveScanSession()
            result = scan.analysis
            preparedAnalysis = scan.analysis
            ensureOutfitMemory(for: scan.analysis)
            isShowingFullAnalysis = false
            scanMessage = ScanMessage(
                title: "Comparison ready",
                description: "\(scan.title) is saved as \(scan.score) \(scoreRatingTitle(for: scan.score)). Scan or open another outfit to compare score changes.",
                icon: "arrow.left.arrow.right",
                isSuccess: true
            )
            return
        }

        let difference = scan.score - currentScore
        let direction = difference == 0 ? "the same as" : difference > 0 ? "\(difference) points higher than" : "\(abs(difference)) points lower than"
        scanMessage = ScanMessage(
            title: "Outfit comparison",
            description: "\(scan.title) is \(direction) the currently open outfit. Saved: \(scan.score) \(scoreRatingTitle(for: scan.score)); current: \(currentScore) \(scoreRatingTitle(for: currentScore)).",
            icon: "arrow.left.arrow.right",
            isSuccess: true
        )
    }

    private func matchingOutfitMemory(for analysis: OutfitAnalysisResult) -> OutfitMemory? {
        let signature = outfitMemorySignature(for: analysis)
        return OutfitMemoryStore().memories.first { memory in
            outfitMemorySignature(for: memory) == signature
        }
    }

    @discardableResult
    private func ensureOutfitMemory(for analysis: OutfitAnalysisResult, store: OutfitMemoryStore = OutfitMemoryStore()) -> OutfitMemory {
        let signature = outfitMemorySignature(for: analysis)
        let scanID = UUID().uuidString
        let garmentRecords = ItemFingerprintMatcher.records(from: analysis, scanID: scanID)
        if let existing = store.memories.first(where: { outfitMemorySignature(for: $0) == signature }) {
            return store.mergeGarmentRecords(garmentRecords, into: existing.id) ?? existing
        }

        let profile = ProfileStore().currentProfile
        let memory = OutfitMemory(
            id: UUID(),
            userId: profile.userId,
            scanDate: Date(),
            detectedGarments: analysis.safeDetectedClothingItems,
            colors: analysis.colorPalette,
            detectedStyle: detectedStyleTitle(for: analysis),
            styleScore: analysis.score,
            occasion: selectedScanOccasion.canonical,
            wasWorn: nil,
            wasLiked: nil,
            feedbackTimestamp: nil,
            dislikeReason: nil,
            wouldWearAgain: nil,
            receivedCompliments: nil,
            isFavorite: false,
            timesWorn: 0,
            garmentRecords: garmentRecords
        )
        store.addOrMergeScan(memory)
        ProfileStore().updateProfile(from: memory)
        return memory
    }

    private func outfitMemorySignature(for analysis: OutfitAnalysisResult) -> String {
        outfitMemorySignature(
            score: analysis.score,
            style: detectedStyleTitle(for: analysis),
            garments: analysis.safeDetectedClothingItems,
            colors: analysis.colorPalette
        )
    }

    private func outfitMemorySignature(for memory: OutfitMemory) -> String {
        outfitMemorySignature(
            score: memory.styleScore,
            style: memory.detectedStyle,
            garments: memory.detectedGarments,
            colors: memory.colors
        )
    }

    private func outfitMemorySignature(score: Int, style: String, garments: [String], colors: [String]) -> String {
        let garmentKey = garments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .sorted()
            .joined(separator: "|")
        let colorKey = colors
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .sorted()
            .joined(separator: "|")
        return "\(score)|\(style.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(garmentKey)|\(colorKey)"
    }

    private func rescanSavedScan(_ scan: RecentOutfitScore) {
        pendingRescanTitle = scan.title
        startCameraCapture()
    }

    private func toggleScanSelection(_ scan: RecentOutfitScore) {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            if selectedScanIDs.contains(scan.id) {
                selectedScanIDs.remove(scan.id)
            } else {
                selectedScanIDs.insert(scan.id)
            }
        }
    }

    private func confirmDelete(_ scan: RecentOutfitScore) {
        scanPendingDelete = scan
        isShowingDeleteScanConfirmation = true
    }

    private func deleteSavedScan(_ scan: RecentOutfitScore) {
        var history = loadScanHistory()
        history.removeValue(forKey: scan.id)
        saveScanHistory(history)
        selectedScanIDs.remove(scan.id)

        if result?.score == scan.score && result?.outfitDescription == scan.analysis.outfitDescription {
            invalidateActiveScanSession()
            result = nil
            preparedAnalysis = nil
        }

        scanMessage = ScanMessage(
            title: "Scan deleted",
            description: "\(scan.title) was removed from scan history, including its photo thumbnail, score, analysis, and cached data.",
            icon: "trash",
            isSuccess: true
        )
    }

    private func deleteSelectedScans() {
        var history = loadScanHistory()
        selectedScanIDs.forEach { history.removeValue(forKey: $0) }
        saveScanHistory(history)
        let deletedCount = selectedScanIDs.count
        selectedScanIDs.removeAll()
        isEditingScanHistory = false
        scanMessage = ScanMessage(
            title: "Selected scans deleted",
            description: "\(deletedCount) scan\(deletedCount == 1 ? "" : "s") were removed permanently from this phone.",
            icon: "trash",
            isSuccess: true
        )
    }

    private func deleteAllScanHistory() {
        invalidateActiveScanSession()
        outfitScanHistoryData = Data()
        selectedScanIDs.removeAll()
        isEditingScanHistory = false
        result = nil
        preparedAnalysis = nil
        scanMessage = ScanMessage(
            title: "Scan history cleared",
            description: "All saved scan photos, scores, analysis, outfit history, and cached data were removed from this phone.",
            icon: "trash",
            isSuccess: true
        )
    }

    private func beginRename(_ scan: RecentOutfitScore) {
        scanPendingRename = scan
        renameText = scan.title
        isShowingRenameScanSheet = true
    }

    private func renamePendingScan() {
        guard let scanPendingRename else { return }
        var history = loadScanHistory()
        guard var stored = history[scanPendingRename.id] else { return }
        stored.customTitle = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        history[scanPendingRename.id] = stored
        saveScanHistory(history)
        scanMessage = ScanMessage(
            title: "Scan renamed",
            description: "Saved scan is now named \(stored.customTitle ?? scanPendingRename.title).",
            icon: "pencil",
            isSuccess: true
        )
        self.scanPendingRename = nil
        isShowingRenameScanSheet = false
    }

    private func toggleFavoriteScan(_ scan: RecentOutfitScore) {
        let title = scan.title
        var favorites = favoriteOutfits
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if scan.isFavorite(in: favoriteOutfits) {
            favorites.removeAll { $0.localizedCaseInsensitiveCompare(title) == .orderedSame }
            scanMessage = ScanMessage(title: "Favorite removed", description: "\(title) was removed from favorite outfits.", icon: "heart", isSuccess: true)
        } else {
            favorites.append(title)
            scanMessage = ScanMessage(title: "Saved to favorites", description: "\(title) was added to favorite outfits.", icon: "heart.fill", isSuccess: true)
        }

        favoriteOutfits = favorites.removingDuplicates().joined(separator: ", ")
    }

    private func duplicateSavedScan(_ scan: RecentOutfitScore) {
        var history = loadScanHistory()
        guard var stored = history[scan.id] else { return }
        stored.customTitle = "\(scan.title) Copy"
        stored.scanCount = max(1, stored.scanCount)
        history["\(scan.id)-copy-\(UUID().uuidString.prefix(8))"] = stored
        saveScanHistory(history)
        scanMessage = ScanMessage(title: "Scan duplicated", description: "\(scan.title) was duplicated in scan history.", icon: "doc.on.doc", isSuccess: true)
    }

    private func moveScanToCloset(_ scan: RecentOutfitScore) {
        let existing = closetInventory.trimmingCharacters(in: .whitespacesAndNewlines)
        closetInventory = existing.isEmpty ? scan.title : "\(existing), \(scan.title)"
        scanMessage = ScanMessage(title: "Moved to closet", description: "\(scan.title) was added to your closet notes for future outfit recommendations.", icon: "tshirt", isSuccess: true)
    }

    private func exportSavedScan(_ scan: RecentOutfitScore) {
        scanMessage = ScanMessage(title: "Export ready", description: scan.shareText, icon: "square.and.arrow.up", isSuccess: true)
    }

    private func recommendationIcon(for category: String) -> String {
        switch category.lowercased() {
        case "shoes":
            return "shoeprints.fill"
        case "shirts":
            return "tshirt"
        case "pants":
            return "figure.walk"
        case "jackets":
            return "person.crop.square"
        case "watches":
            return "applewatch"
        case "handbags":
            return "bag"
        default:
            return "sparkles"
        }
    }

    private var shirtPersonalization: String {
        var parts = ["Saved shirt size: \(shirtSize)"]
        if let neck = cleanOptionalSize(neckSize) {
            parts.append("neck \(neck)")
        }
        if let sleeve = cleanOptionalSize(sleeveLength) {
            parts.append("sleeve \(sleeve)")
        }
        parts.append("preferred fit: \(fitPreference.lowercased())")
        return parts.joined(separator: "; ") + "."
    }

    private var pantsPersonalization: String {
        "Saved pants size: \(pantsSize); waist \(waistSize); inseam \(inseamLength); preferred fit: \(fitPreference.lowercased())."
    }

    private var weatherLocationText: String {
        let city = weatherCity.trimmingCharacters(in: .whitespacesAndNewlines)
        let condition = weatherCondition.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedWeather = weather.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = savedWeather.isEmpty ? condition : "\(condition), \(savedWeather)"
        return city.isEmpty ? base : "\(base) in \(city)"
    }

    private var currentWeatherTemperature: Int? {
        let source = "\(weather) \(weatherCondition) \(weatherFeelsLike)"
        guard let match = source.range(of: #"[-+]?\d{2,3}"#, options: .regularExpression) else {
            return nil
        }
        return Int(source[match])
    }

    private var currentFeelsLikeTemperature: Int? {
        let source = weatherFeelsLike.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = source.range(of: #"[-+]?\d{2,3}"#, options: .regularExpression) else {
            return nil
        }
        return Int(source[match])
    }

    private var isHotWeatherContext: Bool {
        let snapshot = weatherContextSnapshot(environment: result?.environment ?? "Unspecified")
        if snapshot.severity.isWarmOrHot {
            return true
        }

        let context = "\(weather) \(weatherCondition) \(weatherLocationText) \(weatherFeelsLike)".lowercased()
        return context.contains("hot")
            || context.contains("humid")
            || context.contains("heat")
            || context.contains("swelter")
    }

    private var isColdWeatherContext: Bool {
        let snapshot = weatherContextSnapshot(environment: result?.environment ?? "Unspecified")
        if snapshot.severity.isColdOrFreezing {
            return true
        }

        let context = "\(weather) \(weatherCondition) \(weatherLocationText) \(weatherFeelsLike)".lowercased()
        return context.contains("cold")
            || context.contains("snow")
            || context.contains("chilly")
            || context.contains("freezing")
    }

    private var currentSeasonText: String {
        let month = Calendar.current.component(.month, from: Date())
        switch month {
        case 12, 1, 2: return "Winter"
        case 3, 4, 5: return "Spring"
        case 6, 7, 8: return "Summer"
        default: return "Fall"
        }
    }

    private var currentTimeOfDayText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Morning"
        case 12..<17: return "Afternoon"
        case 17..<21: return "Evening"
        default: return "Night"
        }
    }

    private func weatherContextSnapshot(environment: String) -> WeatherContextSnapshot {
        let occasion = activeScanOccasionText(environment: environment)
        let activity = WeatherContextEngine.inferActivity(occasion: occasion, environment: environment)
        let location = weatherCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? weatherLocationText : weatherCity
        return WeatherContextSnapshot(
            airTemperature: currentWeatherTemperature,
            feelsLikeTemperature: currentFeelsLikeTemperature,
            humidityPercent: firstInteger(in: weatherHumidity),
            rainChancePercent: firstInteger(in: weatherRainChance),
            windMph: firstInteger(in: weatherWindSpeed),
            uvIndex: firstInteger(in: weatherUVIndex),
            condition: weatherCondition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? weather : weatherCondition,
            locationText: location,
            activity: activity,
            region: WeatherContextEngine.inferRegion(locationText: location),
            season: currentSeasonText,
            timeOfDay: currentTimeOfDayText,
            confidence: weatherConfidenceScore()
        )
    }

    private func weatherContextRecommendation(environment: String) -> WeatherContextRecommendation {
        WeatherContextEngine.recommendation(for: weatherContextSnapshot(environment: environment))
    }

    private func weatherConfidenceScore() -> Int {
        var confidence = currentWeatherTemperature == nil && currentFeelsLikeTemperature == nil ? 70 : 95
        let source = weatherSource.lowercased()
        if source.contains("live") || source.contains("weatherkit") {
            confidence = max(confidence, 95)
        } else if source.contains("saved") {
            confidence = min(confidence, 88)
        }

        if liveWeatherUpdatedAt > 0 {
            let age = Date().timeIntervalSince1970 - liveWeatherUpdatedAt
            if age > 4 * 60 * 60 {
                confidence -= 10
            }
        }

        return min(100, max(0, confidence))
    }

    private func firstInteger(in text: String) -> Int? {
        guard let match = text.range(of: #"[-+]?\d{1,3}"#, options: .regularExpression) else {
            return nil
        }
        return Int(text[match])
    }

    private func fitRecommendationNote(for detectedItems: [String]) -> String {
        let items = detectedItems.isEmpty ? "the visible outfit" : detectedItems.joined(separator: ", ").lowercased()
        if hasSavedSizeProfileForFitCopy {
            return "Fit check: using your saved size profile (\(savedSizeProfileSummaryForFitCopy)), review \(items) for pulling, extra bunching, dragging hems, or sleeves that pass the wrist. If needed, size up, size down, tailor the inseam, adjust the waist, or shorten the sleeve."
        }
        return "Fit check: no saved sizes yet. Review \(items) for pulling, extra bunching, dragging hems, or sleeves that pass the wrist. Add your sizes in Profile for tailored fit guidance."
    }

    private func weatherRecommendationNote(environment: String) -> String {
        let recommendation = weatherContextRecommendation(environment: environment)
        return "Weather check: \(weatherLocationText). Severity: \(recommendation.severity.rawValue). \(recommendation.recommendation) Why: \(recommendation.rationale)"
    }

    private func occasionRecommendationNote(environment: String, culturalStyle: TraditionalStyleMatch? = nil) -> String {
        if let culturalStyle {
            return "Occasion check: Style category is \(culturalStyle.styleCategory), occasion is \(culturalStyle.occasionCategory), and dress code is \(culturalStyle.dressCode). Evaluate color harmony, fabric presentation, fit, layering, and respectful accessories rather than Western casual/formal rules."
        }

        let occasionText = plannedOccasionSummary(environment: environment)
        let lowered = occasionText.lowercased()

        if lowered.contains("work") || lowered.contains("office") || environment == "Office" || environment == "Business" {
            if isHotWeatherContext {
                return "Occasion check: for \(occasionText), keep it polished in the heat with clean shoes, a sharper lightweight shirt, a belt, or a watch instead of adding a jacket."
            }
            return "Occasion check: for \(occasionText), keep the outfit polished with clean shoes, a sharper shirt, and a belt or jacket if the setting is professional."
        }

        if lowered.contains("church") || lowered.contains("dinner") || lowered.contains("event") || lowered.contains("date") {
            return "Occasion check: for \(occasionText), choose one dressier piece so the outfit feels intentional without looking overdone."
        }

        if lowered.contains("travel") || lowered.contains("vacation") || lowered.contains("trip") {
            return "Occasion check: for \(occasionText), prioritize comfortable shoes, easy layers, and pieces from your closet that can be repeated."
        }

        return "Occasion check: for \(occasionText.isEmpty ? "your plans" : occasionText), match the outfit's formality to the setting and keep one piece as the visual focus."
    }

    private func plannedOccasionSummary(environment: String) -> String {
        let plan = plannedOccasion.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = dressCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let formality = occasionFormality.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = occasions.trimmingCharacters(in: .whitespacesAndNewlines)
        let occasion = plan.isEmpty ? (fallback.isEmpty ? environment : fallback) : plan
        let details = [code, formality].filter { !$0.isEmpty }

        guard !details.isEmpty else {
            return occasion
        }

        return "\(occasion), \(details.joined(separator: ", "))"
    }

    private func activeScanOccasionText(environment: String) -> String {
        if let selected = selectedScanOccasion.canonical {
            return selected.displayName
        }

        return plannedOccasionSummary(environment: environment)
    }

    private var currentScanOccasionForContext: Occasion? {
        selectedScanOccasion.canonical
    }

    private func occasionHonestyInstruction(for analysis: OutfitAnalysisResult) -> String {
        guard let mismatch = FormalityMismatchEvaluator.evaluate(
            detectedStyle: detectedStyleTitle(for: analysis),
            occasion: currentScanOccasionForContext
        ) else {
            return "- No deterministic occasion conflict was detected. Use the existing score and facts as provided."
        }

        return "- Deterministic occasion conflict: \(mismatch.message) Address this mismatch honestly and helpfully; do not praise this outfit as a strong fit for \(mismatch.occasion.displayName) unless the provided facts support that."
    }

    private func cleanOptionalSize(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func metricRow(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 26)
                .foregroundStyle(AppTab.scan.palette.accent)

            Text(title)
                .fontWeight(.semibold)

            Spacer()

            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
    }

    private func loadImage(from item: PhotosPickerItem?) async {
        invalidateActiveScanSession()
        result = nil
        scanMessage = nil
        selectedUIImage = nil
        preparedAnalysis = nil
        isShowingFullAnalysis = false

        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data) else {
            return
        }

        let scanImage = uiImage.scanSizedImage()
        currentScanSource = .gallery
        selectedUIImage = scanImage
        selectedImage = Image(uiImage: scanImage)
        preparedAnalysis = nil
    }

    private func deleteCurrentPhoto() {
        invalidateActiveScanSession()
        selectedItem = nil
        selectedImage = nil
        selectedUIImage = nil
        result = nil
        preparedAnalysis = nil
        isAnalyzing = false
        isPreparingCamera = false
        isShowingFullAnalysis = false
        scanMessage = ScanMessage(
            title: "Photo removed",
            description: "The selected scan photo was removed from this screen. Your photo library was not changed.",
            icon: "trash",
            isSuccess: true
        )
    }

    private func startCameraCapture() {
        guard !isAnalyzing && !isPreparingCamera else {
            scanMessage = ScanMessage(
                title: "Camera is preparing",
                description: "Wait one moment before taking another photo.",
                icon: "hourglass",
                isSuccess: false
            )
            return
        }

        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            scanMessage = ScanMessage(
                title: "Camera unavailable",
                description: "This device does not have a camera available. Run the app on your physical iPhone or choose a photo from your library instead.",
                icon: "camera.badge.ellipsis",
                isSuccess: false
            )
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            prepareNewCameraSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        prepareNewCameraSession()
                    } else {
                        scanMessage = ScanMessage(
                            title: "Camera permission is off",
                            description: "Open iPhone Settings, find Style Match Pro, and turn Camera on. Then come back and tap Take Photo again.",
                            icon: "camera.badge.exclamationmark",
                            isSuccess: false
                        )
                    }
                }
            }
        case .denied, .restricted:
            scanMessage = ScanMessage(
                title: "Camera permission is off",
                description: "Open iPhone Settings, find Style Match Pro, and turn Camera on. Then come back and tap Take Photo again.",
                icon: "camera.badge.exclamationmark",
                isSuccess: false
            )
        @unknown default:
            scanMessage = ScanMessage(
                title: "Camera permission unknown",
                description: "Restart the app and try Take Photo again. If it still fails, choose Pick Photo for now.",
                icon: "camera.badge.questionmark",
                isSuccess: false
            )
        }
    }

    private func prepareNewCameraSession() {
        invalidateActiveScanSession()
        isAnalyzing = false
        selectedItem = nil
        result = nil
        scanMessage = nil
        isPreparingCamera = false
        isShowingCamera = true
    }

    private func analyze(forceReanalyze: Bool = false) {
        invalidateActiveScanSession()
        result = nil
        scanMessage = nil
        isAnalyzing = true
        isShowingFullAnalysis = false
        speakIfEnabled(VoiceScriptBuilder.scanStarted())

        guard let selectedUIImage else {
            isAnalyzing = false
            let message = ScanMessage(
                title: "Choose a photo first",
                description: "Pick a person, outfit, or clothing item before running Style Match Pro.",
                icon: "photo",
                isSuccess: false
            )
            scanMessage = message
            speakIfEnabled(VoiceScriptBuilder.scanFailed(title: message.title, description: message.description))
            return
        }

        let scanSessionID = UUID()
        activeScanSessionID = scanSessionID
        let imageToAnalyze = selectedUIImage
        let scanSource = currentScanSource
        DispatchQueue.global(qos: .userInitiated).async {
            let validation = validateFashionImage(imageToAnalyze)

            DispatchQueue.main.async {
                guard activeScanSessionID == scanSessionID,
                      selectedUIImage === imageToAnalyze else {
                    return
                }

                guard validation.isAccepted else {
                    logScanDebug(
                        source: scanSource,
                        validation: validation,
                        labels: validation.labels,
                        fingerprint: "rejected",
                        cacheSource: "rejected"
                    )
                    preparedAnalysis = nil
                    result = nil
                    let message = ScanMessage(
                        title: validation.rejectionTitle,
                        description: validation.rejectionMessage,
                        icon: validation.rejectionIcon,
                        isSuccess: false
                    )
                    scanMessage = message
                    speakIfEnabled(VoiceScriptBuilder.scanFailed(title: message.title, description: message.description))
                    isAnalyzing = false
                    return
                }

                let labels = validation.labels
                let qualityDescription = validation.qualityDescription
                let fingerprint = normalizedOutfitFingerprint(
                    for: imageToAnalyze,
                    validation: validation,
                    labels: labels,
                    colorPalette: imageToAnalyze.garmentColorPalette()
                )
                activeScanFingerprint = fingerprint
                logScanDebug(
                    source: scanSource,
                    validation: validation,
                    labels: labels,
                    fingerprint: fingerprint,
                    cacheSource: forceReanalyze ? "reanalyze" : "pending"
                )

                let savedResult = savedScan(
                    for: imageToAnalyze,
                    validation: validation,
                    labels: labels,
                    scanSource: scanSource,
                    fingerprint: fingerprint,
                    forceReanalyze: forceReanalyze
                )
                let analysis = savedResult.analysis
                let displayAnalysis = analysisWithPersonalStylistIntelligence(analysis)

                preparedAnalysis = displayAnalysis
                result = displayAnalysis
                ensureOutfitMemory(for: analysis)
                let confidence = confidenceLevel(for: validation, labels: labels)
                let message = ScanMessage(
                    title: confidence == .low ? "Clearer photo recommended" : savedResult.title(defaultNewTitle: "Outfit score saved", repeatTitle: "Previous score restored"),
                    description: "\(confidence.label) confidence. Source: \(savedResult.isRepeat ? "saved analysis" : "new scan"). \(qualityDescription) \(confidence.customerGuidance) \(savedResult.message)",
                    icon: savedResult.isRepeat ? "clock.arrow.circlepath" : "checkmark.seal",
                    isSuccess: true
                )
                scanMessage = message
                isAnalyzing = false
                speakIfEnabled(VoiceScriptBuilder.scanResult(from: displayAnalysis))

                if !savedResult.isRepeat {
                    requestChatGPTRecommendationUpgrade(
                        for: displayAnalysis,
                        scanSessionID: scanSessionID,
                        fingerprint: fingerprint
                    )
                }
            }
        }
    }

    private func instantAnalysis(for image: UIImage) -> OutfitAnalysisResult {
        let validation = validateFashionImage(image)
        let labels = validation.labels.isEmpty ? prototypeLabels(for: image) : validation.labels
        let colorDetection = image.garmentColorDetection()
        let colorPalette = colorDetection.garmentColors
        let styleScore = calculateStyleScore(
            validation: validation,
            labels: labels,
            colorPalette: colorPalette,
            detectedItems: detectedClothingItems(from: labels),
            styleCategory: detectedStyleCategorySignal(validation: validation, labels: labels)
        )

        return makeAnalysisResult(
            score: styleScore.total,
            validation: validation,
            labels: labels,
            imageQuality: validation.qualityDescription,
            colorPalette: colorPalette,
            colorPaletteMaskingApplied: colorDetection.maskingApplied,
            colorPaletteMaskTier: colorDetection.maskTier,
            skinToneStyleNote: image.skinToneStyleNote(),
            scoreBreakdown: styleScore.breakdown
        )
    }

    private func validateFashionImage(_ image: UIImage) -> ScanValidation {
        let detectedAttributes = detectGarmentAttributes(for: image)

        #if DEBUG
        debugLogScanGateInputs(image: image, detectedAttributes: detectedAttributes)
        #endif

        if let qualityIssue = detectedAttributes.qualityIssue {
            #if DEBUG
            print("[ScanGate] FAIL: imageQuality - \(qualityIssue.rawValue)")
            print("[ScanGate] VERDICT: poorQuality(\(qualityIssue.rawValue)); thresholds: averageBrightness<35 tooDark, averageBrightness>226 tooBright, contrast<28 lowContrast, contrast<38 with image larger than 600x600 blurry")
            #endif
            return .poorQuality(qualityIssue)
        }

        guard detectedAttributes.canAnalyze else {
            #if DEBUG
            print("[ScanGate] FAIL: analyzableSignal - labels=\(detectedAttributes.labels.count), hasHuman=\(detectedAttributes.hasHuman)")
            print("[ScanGate] VERDICT: unknown; threshold requires qualityIssue=nil and at least one classifier label or human signal")
            #endif
            return .unknown
        }

        let labels = detectedAttributes.labels
        let hasHuman = detectedAttributes.hasHuman
        let clothingConfidence = clothingConfidence(in: labels)
        let rejectedLabel = strongestRejectedLabel(in: labels)
        let sceneMatch = clothingSceneMatch(in: labels)
        let hasSleepwearEvidence = hasSleepwearLabelEvidence(in: labels)
        let directClothingLabel = labels.first { label in
            clothingTerms.contains { label.identifier.localizedCaseInsensitiveContains($0) }
        }

        if hasHuman {
            var personLabels = labels
            personLabels.insert(DetectedLabel(identifier: "person wearing outfit", confidence: 0.88), at: 0)
            if clothingConfidence < 0.28 {
                personLabels.insert(DetectedLabel(identifier: "clothing", confidence: 0.58), at: min(1, personLabels.count))
            }
            #if DEBUG
            print("[ScanGate] PASS: personDetection - hasHuman=true, clothingConfidence=\(String(format: "%.3f", clothingConfidence)), clothing assist threshold=0.28")
            print("[ScanGate] VERDICT: acceptedPerson")
            #endif
            return .acceptedPerson(Array(personLabels.prefix(12)))
        }

        #if DEBUG
        print("[ScanGate] FAIL: personDetection - no accepted human rectangle, face, or person-context classifier label")
        #endif

        if let sceneMatch, clothingConfidence >= 0.24 {
            #if DEBUG
            print("[ScanGate] PASS: clothingScene - scene=\(sceneMatch.scene.rawValue), label=\(sceneMatch.label), clothingConfidence=\(String(format: "%.3f", clothingConfidence)), threshold>=0.24")
            print("[ScanGate] VERDICT: acceptedClothingScene(\(sceneMatch.scene.rawValue))")
            #endif
            return .acceptedClothingScene(sceneMatch.scene, sceneMatch.label, Array(labels.prefix(12)))
        }

        #if DEBUG
        if sceneMatch == nil {
            print("[ScanGate] FAIL: clothingScene - no clothing label plus accepted flat-lay/display scene term")
        } else {
            print("[ScanGate] FAIL: clothingScene - clothingConfidence=\(String(format: "%.3f", clothingConfidence)) below threshold>=0.24 for scene=\(sceneMatch?.scene.rawValue ?? "none")")
        }
        #endif

        if hasSleepwearEvidence {
            if let sceneMatch {
                #if DEBUG
                print("[ScanGate] PASS: sleepwearScene - scene=\(sceneMatch.scene.rawValue), label=\(sceneMatch.label)")
                print("[ScanGate] VERDICT: acceptedClothingScene(\(sceneMatch.scene.rawValue)) via sleepwear evidence")
                #endif
                return .acceptedClothingScene(sceneMatch.scene, sceneMatch.label, Array(labels.prefix(12)))
            }
            #if DEBUG
            print("[ScanGate] PASS: sleepwearEvidence - no scene required")
            print("[ScanGate] VERDICT: acceptedClothing(Sleepwear)")
            #endif
            return .acceptedClothing("Sleepwear", Array(labels.prefix(12)))
        }

        #if DEBUG
        print("[ScanGate] FAIL: sleepwearEvidence - no sleepwear/loungewear label evidence")
        #endif

        if let clothingLabel = directClothingLabel, clothingConfidence >= 0.30 {
            #if DEBUG
            print("[ScanGate] PASS: directClothing - label=\(clothingLabel.identifier), confidence=\(String(format: "%.3f", clothingLabel.confidence)), bestClothingConfidence=\(String(format: "%.3f", clothingConfidence)), threshold>=0.30")
            print("[ScanGate] VERDICT: acceptedClothing(\(clothingLabel.identifier))")
            #endif
            return .acceptedClothing(clothingLabel.identifier, Array(labels.prefix(12)))
        }

        #if DEBUG
        if let directClothingLabel {
            print("[ScanGate] FAIL: directClothing - label=\(directClothingLabel.identifier), confidence=\(String(format: "%.3f", directClothingLabel.confidence)), bestClothingConfidence=\(String(format: "%.3f", clothingConfidence)) below threshold>=0.30")
        } else {
            print("[ScanGate] FAIL: directClothing - no classifier label matched clothing terms")
        }
        #endif

        if let rejectedLabel {
            if flatLayRegionScene(in: labels) != nil {
                #if DEBUG
                print("[ScanGate] REGION-BEFORE-REJECT: attempting regions before rejectedLabel=\(rejectedLabel)")
                #endif
                if let regionValidation = regionClothingValidation(
                    for: image,
                    wholeImageLabels: labels
                ) {
                    return regionValidation
                }
            }

            #if DEBUG
            print("[ScanGate] FAIL: rejectedLabel - \(rejectedLabel), threshold>=0.32")
            print("[ScanGate] VERDICT: rejected(\(rejectedLabel))")
            #endif
            return .rejected(rejectedLabel)
        }

        if let regionValidation = regionClothingValidation(
            for: image,
            wholeImageLabels: labels
        ) {
            return regionValidation
        }

        #if DEBUG
        print("[ScanGate] VERDICT: unknown; thresholds: scene clothingConfidence>=0.24, direct clothingConfidence>=0.30, rejectedLabel>=0.32, humanOrFace confidence>0.35, personContext label>=0.18")
        #endif
        return .unknown
    }

    #if DEBUG
    private func debugLogScanGateInputs(image: UIImage, detectedAttributes: GarmentAttributeDetection) {
        let labelsText = detectedAttributes.labels
            .prefix(5)
            .map { "\($0.identifier)=\(String(format: "%.3f", $0.confidence))" }
            .joined(separator: ", ")
        print("[ScanGate] INPUT: size=\(Int(image.size.width))x\(Int(image.size.height)), labelsTop5=[\(labelsText)], hasHuman=\(detectedAttributes.hasHuman), qualityIssue=\(detectedAttributes.qualityIssue?.rawValue ?? "none")")
        image.debugLogScanGateMaskDiagnostics()
    }
    #endif

    private func detectGarmentAttributes(for image: UIImage) -> GarmentAttributeDetection {
        if let qualityIssue = image.qualityIssue() {
            return GarmentAttributeDetection(qualityIssue: qualityIssue, labels: [], hasHuman: false)
        }

        guard let cgImage = image.fastVisionCGImage() else {
            return GarmentAttributeDetection(qualityIssue: nil, labels: [], hasHuman: false)
        }

        var labels = classifyImage(cgImage).map {
            DetectedLabel(identifier: $0.identifier, confidence: $0.confidence)
        }
        labels.sort { $0.confidence > $1.confidence }

        return GarmentAttributeDetection(
            qualityIssue: nil,
            labels: Array(labels.prefix(12)),
            hasHuman: detectsPersonSignal(in: cgImage, labels: labels)
        )
    }

    private func savedScan(
        for image: UIImage,
        validation: ScanValidation,
        labels: [DetectedLabel],
        scanSource: ScanSource,
        fingerprint: String,
        forceReanalyze: Bool
    ) -> SavedScanResult {
        var history = loadScanHistory()

        if let storedScan = history[fingerprint],
           !forceReanalyze,
           let cachedAnalysis = storedScan.analysis {
            logScanDebug(source: scanSource, validation: validation, labels: labels, fingerprint: fingerprint, cacheSource: "saved analysis")
            return SavedScanResult(
                analysis: cachedAnalysis,
                isRepeat: true,
                isForced: false,
                message: "Loaded from saved analysis. This outfit was already scanned, so Style Match Pro kept the saved \(storedScan.score) \(scoreRatingTitle(for: storedScan.score)) score instead of rescoring it."
            )
        }

        let colorDetection = image.garmentColorDetection()
        let colorPalette = colorDetection.garmentColors
        let styleScore = calculateStyleScore(
            validation: validation,
            labels: labels,
            colorPalette: colorPalette,
            detectedItems: detectedClothingItems(from: labels),
            styleCategory: detectedStyleCategorySignal(validation: validation, labels: labels)
        )
        let analysis = makeAnalysisResult(
            score: styleScore.total,
            validation: validation,
            labels: labels,
            imageQuality: validation.qualityDescription,
            colorPalette: colorPalette,
            colorPaletteMaskingApplied: colorDetection.maskingApplied,
            colorPaletteMaskTier: colorDetection.maskTier,
            skinToneStyleNote: image.skinToneStyleNote(),
            scoreBreakdown: styleScore.breakdown
        )
        let storedScan = StoredOutfitScan(
            score: analysis.score,
            analysis: analysis,
            firstScannedAt: Date(),
            scanCount: 1,
            thumbnailData: image.scanThumbnailData(),
            occasion: selectedScanOccasion.canonical
        )
        history[fingerprint] = storedScan
        saveScanHistory(history)
        logScanDebug(source: scanSource, validation: validation, labels: labels, fingerprint: fingerprint, cacheSource: forceReanalyze ? "reanalyze new score" : "new local score")

        return SavedScanResult(
            analysis: analysis,
            isRepeat: false,
            isForced: forceReanalyze,
            message: forceReanalyze
                ? "You asked Style Match Pro to refresh this outfit, so it updated the saved analysis while keeping scoring consistent for the same clothes."
                : "Style Match Pro saved this outfit analysis as \(analysis.score) \(scoreRatingTitle(for: analysis.score)) on this iPhone. If the customer opens this scan again, the app pulls this saved result unless the outfit is new."
        )
    }

    private func cachedScan(for image: UIImage) -> SavedScanResult? {
        let fingerprint = fastOutfitFingerprint(for: image)
        let history = loadScanHistory()

        guard let storedScan = history[fingerprint],
              let cachedAnalysis = storedScan.analysis else {
            return nil
        }

        return SavedScanResult(
            analysis: cachedAnalysis,
            isRepeat: true,
            isForced: false,
            message: "This outfit was already scanned, so Style Match Pro opened the saved \(storedScan.score) \(scoreRatingTitle(for: storedScan.score)) result from this iPhone without sending it for a new AI score."
        )
    }

    private func analysisWithPersonalStylistIntelligence(_ analysis: OutfitAnalysisResult) -> OutfitAnalysisResult {
        let message = deterministicPersonalStylistMessage(for: analysis)
        guard !message.isEmpty else {
            return analysis
        }

        let unifiedBody = message.sections
            .map { section in
                "\(section.title): \(section.body)"
            }
            .joined(separator: " ")
        let section = ChatGPTStylistSection(
            title: "Personal Stylist Intelligence",
            body: unifiedBody
        )
        let existingSections = analysis.chatGPTStylistSections
            .filter { $0.title != "Personal Stylist Intelligence" }
        return analysis.replacingChatGPTStylistSections([section] + existingSections)
    }

    private func deterministicPersonalStylistMessage(for analysis: OutfitAnalysisResult) -> PersonalStylistMessage {
        let weatherRecommendation: WeatherContextRecommendation?
        if FeatureFlags.weatherAdviceEnabled {
            weatherRecommendation = weatherContextRecommendation(environment: analysis.environment)
        } else {
            weatherRecommendation = nil
        }

        let dealMatches: [PersonalStylistDealMatch]
        if FeatureFlags.saleMatchingEnabled {
            dealMatches = deterministicDealMatches(for: analysis)
        } else {
            dealMatches = []
        }

        let input = PersonalStylistEngineInput(
            score: analysis.score,
            scoreTier: scoreRatingTitle(for: analysis.score),
            scoreBreakdown: analysis.scoreBreakdown,
            detectedGarments: analysis.safeDetectedClothingItems,
            colors: analysis.colorPalette,
            detectedStyle: detectedStyleTitle(for: analysis),
            occasion: activeScanOccasionText(environment: analysis.environment),
            weather: weatherAdvisorAdvice(for: analysis),
            legacyWeather: weatherRecommendation,
            memories: OutfitMemoryStore().memories,
            profile: ProfileStore().currentProfile,
            dealMatches: dealMatches
        )
        return PersonalStylistEngine.compose(
            input: input,
            weatherAdviceEnabled: FeatureFlags.weatherAdviceEnabled,
            saleMatchingEnabled: FeatureFlags.saleMatchingEnabled
        )
    }

    private func deterministicPersonalStylistPhrasingContext(for analysis: OutfitAnalysisResult) -> PersonalStylistEngineContext {
        let weatherRecommendation: WeatherContextRecommendation?
        if FeatureFlags.weatherAdviceEnabled {
            weatherRecommendation = weatherContextRecommendation(environment: analysis.environment)
        } else {
            weatherRecommendation = nil
        }

        let dealMatches: [PersonalStylistDealMatch]
        if FeatureFlags.saleMatchingEnabled {
            dealMatches = deterministicDealMatches(for: analysis)
        } else {
            dealMatches = []
        }

        let input = PersonalStylistEngineInput(
            score: analysis.score,
            scoreTier: scoreRatingTitle(for: analysis.score),
            scoreBreakdown: analysis.scoreBreakdown,
            detectedGarments: analysis.safeDetectedClothingItems,
            colors: analysis.colorPalette,
            detectedStyle: detectedStyleTitle(for: analysis),
            occasion: activeScanOccasionText(environment: analysis.environment),
            weather: weatherAdvisorAdvice(for: analysis),
            legacyWeather: weatherRecommendation,
            memories: OutfitMemoryStore().memories,
            profile: ProfileStore().currentProfile,
            dealMatches: dealMatches
        )
        return PersonalStylistEngine.context(
            input: input,
            weatherAdviceEnabled: FeatureFlags.weatherAdviceEnabled,
            saleMatchingEnabled: FeatureFlags.saleMatchingEnabled
        )
    }

    private func weatherAdvisorAdvice(for analysis: OutfitAnalysisResult) -> WeatherAdvisorAdvice? {
        guard FeatureFlags.weatherAdviceEnabled else {
            return nil
        }

        let snapshot = weatherContextSnapshot(environment: analysis.environment)
        return WeatherAdvisor.advice(for: WeatherAdvisorInput(
            feelsLikeTemperature: snapshot.effectiveTemperature,
            humidityPercent: snapshot.humidityPercent,
            rainChancePercent: snapshot.rainChancePercent,
            windMph: snapshot.windMph,
            uvIndex: snapshot.uvIndex,
            condition: snapshot.condition,
            confidence: snapshot.confidence,
            detectedGarments: analysis.safeDetectedClothingItems,
            activity: snapshot.activity,
            citySummary: weatherLocationText
        ))
    }

    private func deterministicDealMatches(for analysis: OutfitAnalysisResult) -> [PersonalStylistDealMatch] {
        // Sale matching is built as an async service but dormant by default.
        // Keep the scan path inert until a future enabled caller can await an approved DealProvider.
        []
    }

    private func requestChatGPTRecommendationUpgrade(
        for analysis: OutfitAnalysisResult,
        scanSessionID: UUID,
        fingerprint: String
    ) {
        guard let savedKey = OpenAIKeychain.loadAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !savedKey.isEmpty else {
            return
        }

        let client = OpenAIStylistClient(apiKey: savedKey, model: openAIModel)
        let structuredFacts = structuredOutfitFacts(for: analysis)
        let phrasingContext = deterministicPersonalStylistPhrasingContext(for: analysis)
        let enginePromptContext = PersonalizationContextBuilder.buildPersonalStylistEnginePromptContext(phrasingContext)
        #if DEBUG
        print("[StyleMatch PersonalStylist Context Debug]\n\(enginePromptContext)")
        #endif
        let profile = StyleMatchStylistProfile(
            name: "StyleMatch Customer",
            favoriteColors: favoriteColors,
            favoriteBrands: favoriteBrands,
            preferredFit: fitPreference,
            budget: budget,
            sizeProfile: sizeProfile,
            stylePreferences: stylePreferences,
            occasions: activeScanOccasionText(environment: analysis.environment),
            weather: weatherLocationText,
            weatherPreferences: weatherLocationText,
            dressCode: activeScanOccasionText(environment: analysis.environment),
            shoppingHabits: "Budget \(budget); favorite brands \(favoriteBrands); past purchases \(pastPurchases).",
            pastOutfitRatings: "Current scan \(analysis.score)/100; use saved scan history when available.",
            frequentlyWornOutfits: favoriteOutfits,
            pastPurchases: pastPurchases,
            favoriteOutfits: favoriteOutfits,
            closetInventory: closetInventory,
            appContextSharingEnabled: shareAppContextWithChatGPT,
            appContext: """
            Current screen: Scan result.
            StyleMatch AI score: \(analysis.score)/100. ChatGPT must not change this score.
            Personal Stylist Intelligence context:
            \(enginePromptContext)
            Structured outfit facts:
            \(structuredFacts)
            """
        )

        let question = buildScoreExplanationPrompt(
            analysis: analysis,
            structuredFacts: structuredFacts
        )

        Task {
            do {
                let advice = try await client.askStylist(profile: profile, question: question)
                await MainActor.run {
                    applyChatGPTRecommendation(
                        advice,
                        to: analysis,
                        scanSessionID: scanSessionID,
                        fingerprint: fingerprint
                    )
                }
            } catch {
                #if DEBUG
                print("[Scan ChatGPT Upgrade] \(error.localizedDescription)")
                #endif
                await MainActor.run {
                    guard activeScanSessionID == scanSessionID,
                          activeScanFingerprint == fingerprint else {
                        return
                    }
                    scanMessage = ScanMessage(
                        title: "Fast score ready",
                        description: "StyleMatch Pro saved the score. AI styling notes are temporarily unavailable, so you can still use the local scan result or try Ask AI again.",
                        icon: "sparkles",
                        isSuccess: false
                    )
                }
            }
        }
    }

    private func buildStylistAnalysisPrompt(structuredFacts: String, analysis: OutfitAnalysisResult) -> String {
        """
        \(stylistSystemPrompt)

        CONTEXT FOR THIS SCAN:
        Location: \(weatherCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "unknown" : weatherCity)
        Weather: \(weatherCondition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "unknown" : weatherCondition), \(weatherTemperatureForPrompt)°F
        Occasion: \(activeScanOccasionText(environment: analysis.environment))
        User style preferences: \(stylePreferences.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "not specified" : stylePreferences)

        Computer Vision Fact Layer:
        \(structuredFacts)

        StyleMatch Fashion Knowledge Database:
        \(FashionKnowledgeBase.summary)

        Important:
        - StyleMatch Pro already calculated the score before this AI request.
        - The score value must stay \(analysis.score).
        - Explain the score using scoreBreakdown.
        - Do not invent score components or recalculate the score.

        \(analysisSchema(for: analysis.score))
        """
    }

    private func buildScoreExplanationPrompt(analysis: OutfitAnalysisResult, structuredFacts: String) -> String {
        let detectedAttributes = lockedDetectedAttributes(from: analysis)
        let scoreResult = lockedStyleScoreResult(from: analysis)
        let context = StyleScoreContext(
            occasion: activeScanOccasionText(environment: analysis.environment),
            weather: weatherLocationText,
            temperature: currentWeatherTemperature.map { "\($0)°F" } ?? "unknown",
            feelsLike: currentFeelsLikeTemperature.map { "\($0)°F" } ?? cleanWeatherFact(weatherFeelsLike),
            humidity: cleanWeatherFact(weatherHumidity),
            rainChance: cleanWeatherFact(weatherRainChance),
            wind: cleanWeatherFact(weatherWindSpeed),
            uvIndex: cleanWeatherFact(weatherUVIndex),
            season: currentSeasonText,
            timeOfDay: currentTimeOfDayText
        )
        let weatherGuardrails = weatherStylingGuardrails()
        let stylistProfile = ProfileStore().currentProfile
        let outfitMemories = OutfitMemoryStore().memories
        let personalStylistMemorySection = PersonalizationContextBuilder.promptSection(
            title: "PERSONAL STYLIST MEMORY",
            profile: stylistProfile,
            recentMemories: outfitMemories,
            currentOccasion: currentScanOccasionForContext
        )
        let phrasingContext = deterministicPersonalStylistPhrasingContext(for: analysis)
        let occasionHonesty = occasionHonestyInstruction(for: analysis)

        return """
        You are StyleMatch AI's Personal Stylist. A rules-based scoring engine has already calculated this outfit's score. Your job is ONLY to explain WHY this score was given and offer improvement advice. Do not recalculate or contradict the score.

        SCORE DATA (already final, do not change):
        \(jsonString(scoreResult))

        DETECTED OUTFIT ATTRIBUTES:
        \(jsonString(detectedAttributes))

        CONTEXT:
        \(jsonString(context))

        PERSONAL STYLIST INTELLIGENCE CONTEXT (computed deterministically on device; reword only, do not add facts):
        \(PersonalizationContextBuilder.buildPersonalStylistEnginePromptContext(phrasingContext))

        WEATHER STYLING RULES:
        \(weatherGuardrails)

        OCCASION HONESTY RULES:
        \(occasionHonesty)

        VISION CONFIDENCE RULES:
        - Every detected item has its own confidence in FULL STRUCTURED SCAN FACTS.
        - If an item confidence is below 85%, do not state it as certain. Use language like "I may have detected..." or "I'm not completely certain."
        - Use only the garment terms provided by StyleMatch Pro; never echo internal labels like Textile, Apparel, Clothing, Fabric, or Person Wearing Outfit, and never invent garment names.
        - Never recommend an item because you guessed it from the background, room, furniture, hanger, bed, floor, shopping bag, or non-worn object.
        - Treat clothing, colors, patterns, accessories, footwear, and surroundings as separate checks. If any check is uncertain, say it is uncertain.
        - If detected_style or outfitCategory is "Unrecognized Item" or occasion is "Category Uncertain", say StyleMatch Pro could not identify enough clothing detail and ask for a clearer scan. Do not invent a dress code, occasion, garment, or score rationale.
        - If detected_style or outfitCategory is Sleepwear or Loungewear, describe it as sleepwear/loungewear for home comfort. Do not call it workwear, professional, office-ready, polished business, or business casual.

        RECOMMENDATION VALIDATION:
        Before writing each tip, validate it against weather, season, occasion, user preferences, budget, closet, saved sizes, and visible garment confidence. If the tip conflicts with any of those facts, replace it with a practical alternative.

        AI PHRASING RULE:
        \(StylistMessageComposer.aiPhrasingInstruction)
        You may only reference facts explicitly provided in the context object.
        Do not invent weather conditions, garments, colors, dates, prices, or deals.
        Do not modify or reinterpret the score.
        Keep the message under 4 sentences, warm and specific.

        REASONING GUARDRAIL:
        Before returning JSON, silently self-check:
        - Would a professional stylist actually recommend this?
        - Does it make sense for today's weather, season, and time of day?
        - Am I recommending an item I did not detect or the user did not save?
        - Is there enough confidence to make this statement?
        - Did I avoid impossible, contradictory, duplicate, hallucinated, or weather-conflicting advice?

        The numeric score above is fixed and must not be recalculated, corrected, downgraded, upgraded, or contradicted. Use the user's style profile below only to personalize how you explain the score and improvement tips, not to change the score or score breakdown.

        \(personalStylistMemorySection)

        FULL STRUCTURED SCAN FACTS:
        \(structuredFacts)

        Explain in plain, encouraging language why this outfit received this score, referencing the actual breakdown categories: color harmony, pattern balance, fit, occasion match, and accessories. Give 2-3 specific improvement tips that pass the recommendation validation and reasoning guardrail. Every sentence must trace to SCORE DATA, DETECTED OUTFIT ATTRIBUTES, CONTEXT, PERSONAL STYLIST INTELLIGENCE CONTEXT, PERSONAL STYLIST MEMORY, or FULL STRUCTURED SCAN FACTS. If a fact is missing, omit it silently. Return ONLY valid JSON:

        {
          "score_reasoning": "string",
          "strengths": "string",
          "improvement_tips": ["tip1", "tip2", "tip3"]
        }
        """
    }

    private func weatherStylingGuardrails() -> String {
        let context = weatherLocationText.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayContext = context.isEmpty ? "unknown weather" : context
        let recommendation = weatherContextRecommendation(environment: result?.environment ?? "Unspecified")
        if !recommendation.canGiveSpecificWeatherClothingAdvice {
            return """
            - Current weather context is \(displayContext).
            - Weather severity is \(recommendation.severity.rawValue), but weather confidence is below 90%.
            - Do not make specific weather clothing recommendations. Keep advice general until current weather is confirmed.
            - Rationale: \(recommendation.rationale)
            - Regional context: \(recommendation.regionalNote)
            """
        }

        if recommendation.severity.isWarmOrHot {
            return """
            - Current weather is \(displayContext), which should be treated as hot-weather styling.
            - Severity: \(recommendation.severity.rawValue). Effective temperature: \(recommendation.effectiveTemperature.map { "\($0)°F" } ?? "unknown").
            - Use feels-like temperature over air temperature when both are available.
            - Do not recommend a jacket, blazer, coat, sweater, shacket, structured layer, or heavy layer unless the customer explicitly asks for one or the weather context says cold.
            - For polish in hot weather, recommend breathable fabrics, lighter colors, clean shoes, a belt, watch, sunglasses, moisture-friendly grooming, or a lightweight short-sleeve/linen/cotton shirt.
            - If the occasion is work or smart casual, replace blazer/jacket advice with lightweight polish: crisp shirt, tailored lightweight pants, clean sneakers or loafers, belt, and watch.
            - Rationale: \(recommendation.rationale)
            - Regional context: \(recommendation.regionalNote)
            """
        }

        return """
        - Use the current weather context: \(displayContext).
        - Severity: \(recommendation.severity.rawValue). Effective temperature: \(recommendation.effectiveTemperature.map { "\($0)°F" } ?? "unknown").
        - Use feels-like temperature over air temperature when both are available.
        - Only recommend jackets, blazers, coats, sweaters, or heavy layers when the weather and occasion make them practical.
        - Never recommend jackets solely because it is evening or nighttime if the feels-like temperature remains warm.
        - Rationale: \(recommendation.rationale)
        - Regional context: \(recommendation.regionalNote)
        """
    }

    private func cleanWeatherFact(_ value: String) -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "unknown" : cleaned
    }

    private func jsonString<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    private func lockedDetectedAttributes(from analysis: OutfitAnalysisResult) -> DetectedStyleAttributes {
        DetectedStyleAttributes(
            colors: analysis.colorPalette.map { $0.lowercased() },
            patterns: inferredPatternFacts(for: analysis)
                .filter { !$0.localizedCaseInsensitiveContains("solid") && !$0.localizedCaseInsensitiveContains("low-pattern") },
            fitAssessment: analysis.suggestions.first(where: { $0.localizedCaseInsensitiveContains("fit") }) ?? analysis.imageQuality,
            detectedStyle: detectedStyleTitle(for: analysis),
            accessories: inferredAccessoryFacts(for: analysis)
        )
    }

    private func lockedStyleScoreResult(from analysis: OutfitAnalysisResult) -> StyleScoreResult {
        let breakdown = styleScoreBreakdown(from: analysis)
        return StyleScoreResult(total: clampedScore(analysis.score), breakdown: breakdown, tier: scoreRatingTitle(for: analysis.score))
    }

    private func styleScoreBreakdown(from analysis: OutfitAnalysisResult) -> StyleScoreBreakdown {
        if let saved = analysis.scoreBreakdown {
            return StyleScoreBreakdown(
                colorHarmony: clampedComponent(saved.colorHarmony, max: 25),
                patternBalance: clampedComponent(saved.patternBalance, max: 20),
                fitQuality: clampedComponent(saved.fitQuality, max: 25),
                occasionMatch: clampedComponent(saved.occasionMatch, max: 20),
                accessoryUse: clampedComponent(saved.accessoryUse, max: 10)
            )
        }

        let color = clampedComponent(firstScoreNumber(in: analysis.colorHarmony) ?? 15, max: 25)
        let styleCoordination = clampedComponent(firstScoreNumber(in: analysis.styleCoordination) ?? 45, max: 75)
        let pattern = min(20, styleCoordination / 4)
        let fit = min(25, styleCoordination / 3)
        let occasion = min(20, max(0, styleCoordination - pattern - fit - 5))
        let accessories = min(10, max(0, styleCoordination - pattern - fit - occasion))

        return StyleScoreBreakdown(
            colorHarmony: color,
            patternBalance: pattern,
            fitQuality: fit,
            occasionMatch: occasion,
            accessoryUse: accessories
        )
    }

    private func firstScoreNumber(in text: String) -> Int? {
        guard let match = text.range(of: #"\d+"#, options: .regularExpression) else {
            return nil
        }

        return Int(text[match])
    }

    private func clampedComponent(_ value: Int, max: Int) -> Int {
        Swift.min(max, Swift.max(0, value))
    }

    private var stylistSystemPrompt: String {
        """
        You are StyleMatch AI's Personal AI Stylist, a professional fashion consultant with expertise equivalent to a celebrity stylist, image consultant, and dress-code expert combined.

        Your expertise covers color theory, dress codes, fit and tailoring, pattern and texture combinations, occasion appropriateness, weather, cultural context, current trends, timeless style principles, and budget-conscious recommendations.

        Tone:
        Speak like a knowledgeable, encouraging friend who happens to be a professional stylist. Be direct and specific, never generic. Avoid vague praise. Always explain why a recommendation works.

        Critical accuracy rules:
        1. Only describe what is actually visible in the image or provided in StyleMatch Pro structured facts.
        2. Distinguish garments worn on the body from background/environment.
        3. Ignore walls, furniture, doors, floors, cabinets, appliances, and objects not worn on the body.
        4. For colors, use colorDetection.garment_colors only.
        5. If image quality, lighting, or angle makes something unclear, say it is unclear rather than guessing.
        6. Do not comment on physical appearance beyond fit and styling.
        7. Use outfitCategory and styleRankings from structured facts as the source of truth for style naming.
        8. If cultural or traditional attire is detected, name the clothing respectfully and do not label it casual by default.
        9. If structured facts show hoodie, hooded flannel, plaid shacket, jeans, work boots, hiking boots, or rugged casual evidence, describe the outfit as Casual, Rugged Casual, Outdoor Casual, or Everyday Casual.
        10. Do not say business casual, suitable for work, office, or professional setting unless outfitCategory or the top style ranking is Business Casual and at least two business-style items are present.
        11. Weather practicality is mandatory: in hot, humid, warm, or 80°F+ weather, do not recommend jackets, blazers, coats, sweaters, shackets, structured layers, or heavy layers unless the user explicitly asks for one.
        12. Never guess clothing. If item confidence is below 85%, describe it as uncertain and do not build recommendations around it.
        13. Before finalizing, validate every recommendation against weather, season, occasion, user preferences, budget, closet, saved sizes, and visible garment confidence.
        14. If outfitCategory is Unrecognized Item or the occasion is Category Uncertain, state that the scan could not identify enough clothing detail and ask for a clearer photo; do not invent a style label or rationale.
        15. If outfitCategory or the top style ranking is Sleepwear or Loungewear, explain it as sleepwear/loungewear only and never make it sound professional, office-ready, or business casual.
        """
    }

    private func analysisSchema(for score: Int) -> String {
        """
        Return ONLY valid JSON in this exact format, no markdown and no text outside the JSON:

        {
          "detected_garments": ["item1", "item2"],
          "garment_colors": ["color1", "color2"],
          "detected_style": "string (e.g. Business Casual, Streetwear, Athleisure)",
          "style_confidence": 0-100,
          "fit_assessment": "string describing fit",
          "patterns": ["pattern1"],
          "stylematch_score": \(score),
          "score_reasoning": "string",
          "strengths": "string",
          "improvement_tips": ["tip1", "tip2", "tip3"],
          "occasion_match": "string",
          "weather_match": "string",
          "follow_up_question": "string"
        }
        """
    }

    private var weatherTemperatureForPrompt: String {
        let source = "\(weather) \(weatherCondition)"
        if let match = source.range(of: #"[-+]?\d{2,3}"#, options: .regularExpression) {
            return String(source[match])
        }
        return "unknown"
    }

    private func structuredOutfitFacts(for analysis: OutfitAnalysisResult) -> String {
        let colorDetection = selectedUIImage?.garmentColorDetection()
        let palette = analysis.colorPalette
        let scoreResult = lockedStyleScoreResult(from: analysis)
        let fingerprint = selectedUIImage.map {
            let validation = validateFashionImage($0)
            let labels = validation.labels
            return normalizedOutfitFingerprint(for: $0, validation: validation, labels: labels, colorPalette: palette)
        } ?? "saved-result"
        let payload = OutfitFactPayload(
            scanSource: currentScanSource.rawValue,
            normalized: true,
            detectedItems: analysis.safeDetectedClothingItems,
            itemConfidence: analysis.detectedItemConfidences.map { item in
                OutfitFactPayload.ItemConfidence(item: item.item, confidence: Double(item.confidence) / 100)
            },
            colors: analysis.colorPalette,
            colorDetection: OutfitFactPayload.GarmentColorFact(
                garmentColors: analysis.colorPalette,
                confidence: colorDetection?.confidence ?? 72,
                notes: colorDetection?.notes ?? "Garment colors came from the saved scan palette; background colors were not used as clothing facts."
            ),
            patterns: inferredPatternFacts(for: analysis),
            fabricsAndTextures: inferredFabricFacts(for: analysis),
            shoes: analysis.safeDetectedClothingItems.filter { $0.localizedCaseInsensitiveContains("shoe") || $0.localizedCaseInsensitiveContains("sneaker") || $0.localizedCaseInsensitiveContains("loafer") },
            accessories: inferredAccessoryFacts(for: analysis),
            outfitCategory: detectedStyleTitle(for: analysis),
            styleRankings: styleRankings(for: analysis),
            occasion: analysis.occasionFit,
            weather: weatherLocationText,
            weatherSource: weatherSource,
            feelsLike: weatherFeelsLike,
            rainChance: weatherRainChance,
            humidity: weatherHumidity,
            windSpeed: weatherWindSpeed,
            uvIndex: weatherUVIndex,
            lastUpdated: weatherLastUpdatedFact,
            environment: analysis.environment,
            lighting: analysis.imageQuality,
            scanType: scanTypeFact(for: analysis),
            styleScore: analysis.score,
            scoreBreakdown: scoreResult.breakdown,
            scoreTier: scoreRatingTitle(for: analysis.score),
            scoreOwner: "StyleMatch AI scoring logic",
            outfitFingerprint: fingerprint,
            culturalAwareness: culturalAwarenessFact(for: analysis),
            confidence: Double(detectedStyleConfidence(for: analysis)) / 100,
            guardrails: [
                "Facts only in the Computer Vision layer.",
                "ChatGPT explains and improves but does not control the score.",
                "Do not infer race, ethnicity, nationality, religion, age, gender, or identity.",
                "Do not guess brands unless high confidence evidence is provided.",
                "Do not label traditional clothing casual by default.",
                "Do not call hoodie, hooded flannel, plaid shacket, jeans, boots, or rugged casual outfits business casual unless at least two business-style items are detected.",
                "If styleRankings show Casual or Rugged Casual first, describe the outfit as everyday casual, rugged casual, or outdoor casual and avoid work/business wording.",
                "If outfitCategory is Sleepwear or Loungewear, explain it as home comfort clothing and avoid business/work/professional wording.",
                "If outfitCategory is Unrecognized Item or occasion is Category Uncertain, say the scan did not identify enough clothing detail and ask for a clearer photo.",
                "Ask for a better image if lighting or clothing visibility is unreliable."
            ]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload),
              let text = String(data: data, encoding: .utf8) else {
            return "Detected items: \(analysis.safeDetectedClothingItems.joined(separator: ", ")); colors: \(analysis.colorPalette.joined(separator: ", ")); score: \(analysis.score)/100."
        }

        return text
    }

    private func inferredPatternFacts(for analysis: OutfitAnalysisResult) -> [String] {
        let combined = (analysis.outfitDescription + " " + analysis.detectedClothingItems.joined(separator: " ")).lowercased()
        let patterns = ["solid", "stripe", "plaid", "check", "floral", "print", "ankara", "kente", "embroidery", "pattern"]
        let matches = patterns.filter { combined.contains($0) }
        return matches.isEmpty ? ["solid or low-pattern appearance"] : matches
    }

    private func inferredFabricFacts(for analysis: OutfitAnalysisResult) -> [String] {
        let combined = (analysis.outfitDescription + " " + analysis.detectedClothingItems.joined(separator: " ") + " " + analysis.summary).lowercased()
        let fabrics = ["denim", "cotton", "linen", "leather", "wool", "silk", "ankara", "aso oke", "kente", "embroidered", "knit"]
        let matches = fabrics.filter { combined.contains($0) }
        return matches.isEmpty ? ["fabric not confidently detected"] : matches
    }

    private func inferredAccessoryFacts(for analysis: OutfitAnalysisResult) -> [String] {
        let terms = ["watch", "belt", "bag", "hat", "cap", "jewelry", "chain", "scarf", "head wrap", "gele", "shemagh", "keffiyeh"]
        return analysis.detectedClothingItems.filter { item in
            terms.contains { item.localizedCaseInsensitiveContains($0) }
        }
    }

    private func scanTypeFact(for analysis: OutfitAnalysisResult) -> String {
        let description = analysis.outfitDescription.lowercased()
        if description.contains("person") || description.contains("worn") {
            return "person wearing clothes"
        }
        if description.contains("mannequin") { return "mannequin" }
        if description.contains("hanger") { return "hanger" }
        if description.contains("bed") { return "clothes on bed" }
        if description.contains("table") { return "clothes on table" }
        if description.contains("floor") { return "clothes on floor" }
        if description.contains("bag") { return "clothes in shopping bag" }
        return "visible clothing scan"
    }

    private var weatherLastUpdatedFact: String {
        guard liveWeatherUpdatedAt > 0 else {
            return "not available"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd h:mm a"
        return formatter.string(from: Date(timeIntervalSince1970: liveWeatherUpdatedAt))
    }

    private func culturalAwarenessFact(for analysis: OutfitAnalysisResult) -> String {
        let combined = (analysis.styleBalance + " " + analysis.summary + " " + analysis.detectedClothingItems.joined(separator: " ")).lowercased()
        if combined.contains("traditional") || combined.contains("cultural") || combined.contains("agbada") || combined.contains("dashiki") || combined.contains("kaftan") || combined.contains("kente") || combined.contains("sari") || combined.contains("kimono") || combined.contains("hanbok") || combined.contains("abaya") {
            return "Traditional or cultural attire may be present. Evaluate with cultural clothing rules and avoid western casual defaults."
        }
        return "No specific traditional attire confidence above threshold."
    }

    private func applyChatGPTRecommendation(
        _ advice: String,
        to analysis: OutfitAnalysisResult,
        scanSessionID: UUID,
        fingerprint: String
    ) {
        let trimmedAdvice = advice
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sections = parseChatGPTStylistSections(from: advice, lockedScore: analysis.score)

        guard !trimmedAdvice.isEmpty || !sections.isEmpty else {
            return
        }

        let firstTip = sections.first(where: { $0.title == "Improvement Tips" })?.body ?? trimmedAdvice
        let chatGPTRecommendation = ClothingRecommendation(
            category: "ChatGPT",
            title: firstTip,
            reason: "ChatGPT used structured scan facts, weather, occasion, style memory, and the StyleMatch fashion rules.",
            personalization: "Generated for this outfit only, not copied from another scan."
        )
        let updatedRecommendations = [chatGPTRecommendation] + analysis.recommendations.prefix(4)
        let preservedLocalSections = analysis.chatGPTStylistSections
            .filter { $0.title == "Personal Stylist Intelligence" }
        let finalSections = (preservedLocalSections + sections)
            .removingDuplicateStylistSections()
        let updatedAnalysis = analysis
            .replacingRecommendations(Array(updatedRecommendations))
            .replacingChatGPTStylistSections(finalSections)

        guard activeScanSessionID == scanSessionID,
              activeScanFingerprint == fingerprint else {
            return
        }

        result = updatedAnalysis
        preparedAnalysis = updatedAnalysis
        saveChatGPTUpgrade(updatedAnalysis, fingerprint: fingerprint)
        scanMessage = ScanMessage(
            title: "ChatGPT stylist analysis ready",
            description: "ChatGPT used the structured scan facts to explain the score and suggest improvements.",
            icon: "sparkles",
            isSuccess: true
        )
    }

    private func parseChatGPTStylistSections(from response: String, lockedScore: Int) -> [ChatGPTStylistSection] {
        if let jsonSections = parseChatGPTStylistJSONSections(from: response, lockedScore: lockedScore), !jsonSections.isEmpty {
            return sanitizeScoreSections(jsonSections, lockedScore: lockedScore)
        }

        let expectedTitles = [
            "Outfit Summary",
            "Why This Score",
            "Strengths",
            "Improvement Tips",
            "Occasion Match",
            "Weather Match",
            "Ask AI Stylist"
        ]
        var sections: [ChatGPTStylistSection] = []
        var currentTitle: String?
        var currentLines: [String] = []

        func flushSection() {
            guard let currentTitle else { return }
            let body = currentLines
                .joined(separator: " ")
                .replacingOccurrences(of: "  ", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                sections.append(ChatGPTStylistSection(title: currentTitle, body: body))
            }
        }

        for rawLine in response.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if let title = expectedTitles.first(where: { line.localizedCaseInsensitiveCompare("\($0):") == .orderedSame || line.localizedCaseInsensitiveCompare($0) == .orderedSame }) {
                flushSection()
                currentTitle = title
                currentLines = []
            } else {
                currentLines.append(line.trimmingCharacters(in: CharacterSet(charactersIn: "-•* ")))
            }
        }

        flushSection()

        if sections.isEmpty {
            return sanitizeScoreSections(
                [ChatGPTStylistSection(title: "Outfit Summary", body: response.trimmingCharacters(in: .whitespacesAndNewlines))],
                lockedScore: lockedScore
            )
        }

        return sanitizeScoreSections(sections, lockedScore: lockedScore)
    }

    private func sanitizeScoreSections(_ sections: [ChatGPTStylistSection], lockedScore: Int) -> [ChatGPTStylistSection] {
        sections.map { section in
            let scoreSanitizedBody = sanitizeScoreMentions(section.body, lockedScore: lockedScore)
            return ChatGPTStylistSection(
                title: section.title,
                body: sanitizeWeatherLayerAdvice(scoreSanitizedBody, sectionTitle: section.title)
            )
        }
    }

    private func sanitizeWeatherLayerAdvice(_ text: String, sectionTitle: String) -> String {
        guard isHotWeatherContext else {
            return text
        }

        let lowerTitle = sectionTitle.lowercased()
        let shouldSanitize = lowerTitle.contains("improvement")
            || lowerTitle.contains("weather")
            || lowerTitle.contains("occasion")
            || lowerTitle.contains("why")
            || lowerTitle.contains("strength")
            || lowerTitle.contains("summary")
        guard shouldSanitize else {
            return text
        }

        let hotWeatherAlternative = "For \(weatherLocationText), skip jackets, blazers, and heavy layers; add polish with breathable fabric, clean shoes, a belt, a watch, sunglasses, or a crisp lightweight shirt."
        let layerPattern = #"(?i)(^|(?<=[.!?])\s*)[^.!?]*(jacket|blazer|coat|sweater|shacket|heavy layer|structured layer)[^.!?]*[.!?]?"#
        guard let regex = try? NSRegularExpression(pattern: layerPattern) else {
            return text
        }

        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let sanitized = regex.stringByReplacingMatches(
            in: text,
            range: fullRange,
            withTemplate: " \(hotWeatherAlternative)"
        )
        return sanitized
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sanitizeScoreMentions(_ text: String, lockedScore: Int) -> String {
        var sanitized = text
        let patterns = [
            #"\b\d{1,3}\s*/\s*100\b"#,
            #"(?i)\bscore\s+(of\s+)?\d{1,3}\b"#,
            #"(?i)\breceived\s+(a\s+)?\d{1,3}\b"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(sanitized.startIndex..<sanitized.endIndex, in: sanitized)
            if pattern.contains("/\\s*100") {
                sanitized = regex.stringByReplacingMatches(
                    in: sanitized,
                    range: range,
                    withTemplate: "\(lockedScore)/100"
                )
            } else if pattern.localizedCaseInsensitiveContains("received") {
                sanitized = regex.stringByReplacingMatches(
                    in: sanitized,
                    range: range,
                    withTemplate: "received \(lockedScore)"
                )
            } else {
                sanitized = regex.stringByReplacingMatches(
                    in: sanitized,
                    range: range,
                    withTemplate: "score \(lockedScore)"
                )
            }
        }

        return sanitized
    }

    private func parseChatGPTStylistJSONSections(from response: String, lockedScore: Int) -> [ChatGPTStylistSection]? {
        let cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let jsonText: String
        if let start = cleaned.firstIndex(of: "{"),
           let end = cleaned.lastIndex(of: "}"),
           start <= end {
            jsonText = String(cleaned[start...end])
        } else {
            jsonText = cleaned
        }

        guard let data = jsonText.data(using: .utf8) else {
            return nil
        }

        guard let decoded = try? JSONDecoder().decode(StylistJSONAnalysis.self, from: data) else {
            if let scoreExplanation = try? JSONDecoder().decode(StylistScoreExplanation.self, from: data) {
                let tipsText = scoreExplanation.improvementTips.isEmpty
                    ? "No extra changes are needed from the current scan."
                    : scoreExplanation.improvementTips.prefix(3).joined(separator: " ")
                return [
                    ChatGPTStylistSection(title: "Why This Score", body: "\(lockedScore)/100. \(scoreExplanation.scoreReasoning)"),
                    ChatGPTStylistSection(title: "Strengths", body: scoreExplanation.strengths),
                    ChatGPTStylistSection(title: "Improvement Tips", body: tipsText)
                ].filter { !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            }
            return nil
        }

        let garmentText = decoded.detectedGarments.isEmpty
            ? "Visible garments were not clear enough for the AI stylist to list confidently."
            : decoded.detectedGarments.joined(separator: ", ")
        let paletteText = decoded.garmentColors.isEmpty
            ? "Garment colors were unclear."
            : decoded.garmentColors.joined(separator: ", ")
        let patternText = decoded.patterns.isEmpty
            ? "No clear pattern was detected."
            : decoded.patterns.joined(separator: ", ")
        let scoreReasoning = "\(lockedScore)/100. \(decoded.scoreReasoning)"
        let tipsText = decoded.improvementTips.isEmpty
            ? "No extra changes are needed from the current scan."
            : decoded.improvementTips.joined(separator: " ")

        return [
            ChatGPTStylistSection(title: "Detected Garments", body: garmentText),
            ChatGPTStylistSection(title: "Color Palette", body: paletteText),
            ChatGPTStylistSection(title: "Detected Style", body: "\(decoded.detectedStyle) with \(decoded.styleConfidence)% confidence."),
            ChatGPTStylistSection(title: "Fit Assessment", body: decoded.fitAssessment),
            ChatGPTStylistSection(title: "Patterns & Texture", body: patternText),
            ChatGPTStylistSection(title: "Why This Score", body: scoreReasoning),
            ChatGPTStylistSection(title: "Strengths", body: decoded.strengths),
            ChatGPTStylistSection(title: "Occasion Match", body: decoded.occasionMatch),
            ChatGPTStylistSection(title: "Weather Match", body: decoded.weatherMatch),
            ChatGPTStylistSection(title: "Improvement Tips", body: tipsText),
            ChatGPTStylistSection(title: "Ask AI Stylist", body: decoded.followUpQuestion)
        ].filter { !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func saveChatGPTUpgrade(_ analysis: OutfitAnalysisResult, fingerprint: String) {
        guard let selectedUIImage else {
            return
        }

        var history = loadScanHistory()
        let existing = history[fingerprint]
        history[fingerprint] = StoredOutfitScan(
            score: analysis.score,
            analysis: analysis,
            firstScannedAt: existing?.firstScannedAt ?? Date(),
            scanCount: existing?.scanCount ?? 1,
            thumbnailData: existing?.thumbnailData ?? selectedUIImage.scanThumbnailData(),
            customTitle: existing?.customTitle,
            occasion: existing?.occasion?.canonical ?? selectedScanOccasion.canonical
        )
        saveScanHistory(history)
    }

    private func invalidateActiveScanSession() {
        activeScanSessionID = nil
        activeScanFingerprint = nil
    }

    private func fastOutfitFingerprint(for image: UIImage) -> String {
        let widthBucket = Int(image.size.width / 80)
        let heightBucket = Int(image.size.height / 80)
        return "fast-\(widthBucket)x\(heightBucket)-\(image.outfitIdentitySignature())"
    }

    private func normalizedOutfitFingerprint(
        for image: UIImage,
        validation: ScanValidation,
        labels: [DetectedLabel],
        colorPalette: [String]
    ) -> String {
        let scanType = validation.arrangementFingerprint.normalizedForFingerprint
        let clothing = detectedClothingItems(from: labels)
            .map(\.normalizedForFingerprint)
            .removingDuplicates()
            .sorted()
            .prefix(8)
            .joined(separator: ".")
        let colors = colorPalette
            .map(\.normalizedForFingerprint)
            .removingDuplicates()
            .sorted()
            .prefix(5)
            .joined(separator: ".")
        let patternSignal = inferredStablePatternSignal(from: labels)
        let accessories = labels
            .map(\.identifier)
            .filter { label in
                ["watch", "belt", "bag", "hat", "jewelry", "scarf", "tie", "shoe", "sneaker", "loafer", "boot"].contains { label.localizedCaseInsensitiveContains($0) }
            }
            .map(\.normalizedForFingerprint)
            .removingDuplicates()
            .sorted()
            .prefix(5)
            .joined(separator: ".")
        let category = detectedStyleCategorySignal(validation: validation, labels: labels)
        let fabric = inferredFabricSignal(from: labels)
        return [
            "outfit-v3-classifier-calibrated",
            scanType,
            clothing.isEmpty ? "clothing" : clothing,
            colors.isEmpty ? "neutral" : colors,
            patternSignal,
            accessories.isEmpty ? "no-accessory" : accessories,
            category,
            fabric
        ].joined(separator: "|")
    }

    private func inferredStablePatternSignal(from labels: [DetectedLabel]) -> String {
        let text = labels.map(\.identifier).joined(separator: " ").lowercased()
        let patterns = ["solid", "stripe", "plaid", "check", "floral", "print", "pattern", "embroidery", "ankara", "kente", "aso oke"]
        let matches = patterns.filter { text.contains($0) }
        return matches.isEmpty ? "low-pattern" : matches.map(\.normalizedForFingerprint).joined(separator: ".")
    }

    private func inferredFabricSignal(from labels: [DetectedLabel]) -> String {
        let text = labels.map(\.identifier).joined(separator: " ").lowercased()
        let fabrics = ["denim", "cotton", "linen", "leather", "wool", "silk", "knit", "fabric", "textile", "lace"]
        let matches = fabrics.filter { text.contains($0) }
        return matches.isEmpty ? "fabric-unknown" : matches.map(\.normalizedForFingerprint).joined(separator: ".")
    }

    private func detectedStyleCategorySignal(validation: ScanValidation, labels: [DetectedLabel]) -> String {
        let text = labels.map(\.identifier).joined(separator: " ").lowercased()
        guard validation.isAccepted else {
            return "unrecognized"
        }
        if let noveltyStyle = noveltyClothingMatch(in: labels) {
            return noveltyStyle.styleCategory.normalizedForFingerprint
        }
        if let sleepwearCategory = sleepwearOrLoungewearCategory(from: text) {
            return sleepwearCategory.normalizedForFingerprint
        }
        if traditionalStyleMatch(in: labels, image: nil) != nil {
            return "traditional"
        }
        if text.contains("suit") || text.contains("blazer") || text.contains("formal") {
            return "formal"
        }
        if text.contains("sport") || text.contains("gym") || text.contains("athletic") {
            return "athletic"
        }
        if text.contains("jeans") || text.contains("t-shirt") || text.contains("sneaker") {
            return "casual"
        }
        return validation.sceneName.normalizedForFingerprint
    }

    private func confidenceLevel(for validation: ScanValidation, labels: [DetectedLabel]) -> OutfitConfidenceLevel {
        guard validation.isAccepted else {
            return .low
        }

        let bestClothing = clothingConfidence(in: labels)
        let bestLabel = labels.map(\.confidence).max() ?? 0
        let confidence = max(bestClothing, bestLabel)

        if confidence >= 0.72 {
            return .high
        }
        if confidence >= 0.38 {
            return .medium
        }
        return .low
    }

    private func logScanDebug(
        source: ScanSource,
        validation: ScanValidation,
        labels: [DetectedLabel],
        fingerprint: String,
        cacheSource: String
    ) {
        #if DEBUG
        print(scanDebugLog(
            source: source,
            validation: validation,
            labels: labels,
            fingerprint: fingerprint,
            cacheSource: cacheSource
        ))
        #endif
    }

    private func scanDebugLog(
        source: ScanSource,
        validation: ScanValidation,
        labels: [DetectedLabel],
        fingerprint: String,
        cacheSource: String
    ) -> String {
        let qualityScore = validation.qualityScore
        let confidence = confidenceLevel(for: validation, labels: labels)
        let detectedCount = detectedClothingItems(from: labels).prefix(8).count
        let reason = validation.isAccepted ? cacheSource : validation.rejectionTitle
        let fingerprintToken = abs(fingerprint.hashValue % 100_000)

        return """
        [StyleMatch Scan Debug] source=\(source.rawValue); normalized=true; quality=\(qualityScore); confidence=\(confidence.label); fingerprintToken=\(fingerprintToken); scoreSource=\(cacheSource); detectedCount=\(detectedCount); reason=\(reason)
        """
    }

    private func scoreFingerprint(for image: UIImage, validation: ScanValidation, labels: [DetectedLabel], colorPalette: [String]) -> String {
        let palette = colorPalette
            .map(\.normalizedForFingerprint)
            .sorted()
            .joined(separator: ".")
        let clothingSignal = detectedClothingItems(from: labels)
            .map(\.normalizedForFingerprint)
            .removingDuplicates()
            .prefix(5)
            .joined(separator: ".")
        let stableClothingSignal = clothingSignal.isEmpty ? "style-scan" : clothingSignal

        return "\(validation.arrangementFingerprint)-\(stableClothingSignal)-\(palette)"
    }

    private func prototypeLabels(for image: UIImage) -> [DetectedLabel] {
        [
            DetectedLabel(identifier: "outfit", confidence: 0.98),
            DetectedLabel(identifier: "clothing", confidence: 0.96),
            DetectedLabel(identifier: "fashion", confidence: 0.94)
        ]
    }

    private func outfitFingerprint(for image: UIImage, validation: ScanValidation) -> String {
        let colorSignature = image.colorSignature()
        let arrangement = validation.arrangementFingerprint
        let labelSignature = validation.labels
            .prefix(8)
            .map { $0.identifier.normalizedForFingerprint }
            .removingDuplicates()
            .joined(separator: ".")

        switch validation {
        case .acceptedPerson:
            return "person-\(arrangement)-\(labelSignature)-\(colorSignature)"
        case .acceptedClothing(let label, _):
            return "clothing-\(arrangement)-\(label.normalizedForFingerprint)-\(labelSignature)-\(colorSignature)"
        case .acceptedClothingScene(let scene, let label, _):
            return "\(scene.rawValue)-\(arrangement)-\(label.normalizedForFingerprint)-\(labelSignature)-\(colorSignature)"
        case .poorQuality(let issue):
            return "poor-quality-\(issue.rawValue)-\(colorSignature)"
        case .rejected(let label):
            return "rejected-\(label.normalizedForFingerprint)-\(colorSignature)"
        case .unknown:
            return "unknown-\(colorSignature)"
        }
    }

    private func calculateStyleScore(
        validation: ScanValidation,
        labels: [DetectedLabel],
        colorPalette: [String],
        detectedItems: [String],
        styleCategory: String
    ) -> StyleScoreResult {
        let attributes = detectGarmentAttributes(
            validation: validation,
            labels: labels,
            colorPalette: colorPalette,
            detectedItems: detectedItems,
            styleCategory: styleCategory
        )
        #if DEBUG
        print("[StyleMatch Score Debug] attributes style=\(attributes.detectedStyle); colors=\(attributes.colors); patterns=\(attributes.patterns); fit=\(attributes.fitAssessment); accessories=\(attributes.accessories)")
        #endif
        let result = calculateStyleScore(detectedAttributes: attributes)
        #if DEBUG
        print("[StyleMatch Score Debug] result total=\(result.total); tier=\(result.tier); breakdown=color:\(result.breakdown.colorHarmony), pattern:\(result.breakdown.patternBalance), fit:\(result.breakdown.fitQuality), occasion:\(result.breakdown.occasionMatch), accessories:\(result.breakdown.accessoryUse)")
        #endif
        return result
    }

    private func detectGarmentAttributes(
        validation: ScanValidation,
        labels: [DetectedLabel],
        colorPalette: [String],
        detectedItems: [String],
        styleCategory: String
    ) -> DetectedStyleAttributes {
        DetectedStyleAttributes(
            colors: colorPalette.map { $0.lowercased() },
            patterns: inferredStablePatternSignal(from: labels)
                .components(separatedBy: ".")
                .filter { !$0.isEmpty && $0 != "low-pattern" },
            fitAssessment: fitAssessmentSignal(validation: validation, labels: labels, detectedItems: detectedItems),
            detectedStyle: styleCategory,
            accessories: detectedAccessories(from: labels, detectedItems: detectedItems)
        )
    }

    private func calculateStyleScore(detectedAttributes attributes: DetectedStyleAttributes) -> StyleScoreResult {
        let breakdown = scoreComponents(attributes: attributes)
        let rawTotal =
            breakdown.colorHarmony +
            breakdown.patternBalance +
            breakdown.fitQuality +
            breakdown.accessoryUse
        let total = clampedScore(Int(round(Double(rawTotal) / 80.0 * 100.0)))

        return StyleScoreResult(total: total, breakdown: breakdown, tier: scoreRatingTitle(for: total))
    }

    private func scoreComponents(attributes: DetectedStyleAttributes) -> StyleScoreBreakdown {
        StyleScoreBreakdown(
            colorHarmony: scoreColorHarmony(attributes.colors),
            patternBalance: scorePatterns(attributes.patterns),
            fitQuality: scoreFit(attributes.fitAssessment),
            // Occasion is explanation-only; never a score input.
            occasionMatch: 0,
            accessoryUse: scoreAccessories(attributes.accessories)
        )
    }

    private func scoreColorHarmony(_ colors: [String]) -> Int {
        let normalized = colors.map { $0.lowercased() }.removingDuplicates()
        let neutrals = ["black", "white", "gray", "grey", "navy", "beige", "tan", "brown", "charcoal", "cream", "denim"]
        let hasOnlyNeutrals = !normalized.isEmpty && normalized.allSatisfy { color in
            neutrals.contains { color.contains($0) }
        }
        let twoColorMax = normalized.count <= 3
        let tooManyCompetingColors = normalized.count >= 5

        var score = 15
        if hasOnlyNeutrals { score += 5 }
        if twoColorMax { score += 5 }
        if tooManyCompetingColors { score -= 5 }
        if normalized.contains("navy") && (normalized.contains("white") || normalized.contains("tan") || normalized.contains("brown")) { score += 2 }
        return min(25, max(8, score))
    }

    private func scorePatterns(_ patterns: [String]) -> Int {
        let filtered = patterns
            .filter { !$0.localizedCaseInsensitiveContains("solid") && !$0.localizedCaseInsensitiveContains("low-pattern") }
            .removingDuplicates()
        if filtered.isEmpty { return 20 }
        if filtered.count == 1 { return 18 }
        return 10
    }

    private func scoreFit(_ fitAssessment: String) -> Int {
        let lowered = fitAssessment.lowercased()
        let goodFitTerms = ["tailored", "fitted", "well-fitted", "proper", "balanced", "clean fit", "regular"]
        let poorFitTerms = ["too tight", "too loose", "oversized", "bunching", "dragging", "unclear", "poor"]
        if goodFitTerms.contains(where: { lowered.contains($0) }) { return 25 }
        if poorFitTerms.contains(where: { lowered.contains($0) }) { return 14 }
        return 18
    }

    private func scoreAccessories(_ accessories: [String]) -> Int {
        accessories.isEmpty ? 5 : 10
    }

    private func fitAssessmentSignal(validation: ScanValidation, labels: [DetectedLabel], detectedItems: [String]) -> String {
        let text = (labels.map(\.identifier) + detectedItems).joined(separator: " ").lowercased()
        if text.contains("oversized") || text.contains("baggy") { return "oversized" }
        if text.contains("tailored") || text.contains("suit") || text.contains("blazer") { return "tailored" }
        if text.contains("robe") || text.contains("sleepwear") || text.contains("loungewear") { return "relaxed" }
        if validation.qualityScore < 80 { return "unclear" }
        return "regular balanced fit"
    }

    private func detectedAccessories(from labels: [DetectedLabel], detectedItems: [String]) -> [String] {
        let terms = ["watch", "belt", "bag", "hat", "cap", "jewelry", "chain", "scarf", "tie", "sunglasses"]
        return (labels.map(\.identifier) + detectedItems).filter { item in
            terms.contains { item.localizedCaseInsensitiveContains($0) }
        }.removingDuplicates()
    }

    private func loadScanHistory() -> [String: StoredOutfitScan] {
        guard !outfitScanHistoryData.isEmpty,
              let history = try? JSONDecoder().decode([String: StoredOutfitScan].self, from: outfitScanHistoryData) else {
            return [:]
        }

        return history
    }

    private func saveScanHistory(_ history: [String: StoredOutfitScan]) {
        let limitedHistory = Dictionary(
            uniqueKeysWithValues: history
                .sorted { $0.value.firstScannedAt > $1.value.firstScannedAt }
                .prefix(20)
                .map { ($0.key, $0.value) }
        )

        guard let data = try? JSONEncoder().encode(limitedHistory) else {
            return
        }

        outfitScanHistoryData = data
    }

    private var recentStoredScans: [RecentOutfitScore] {
        loadScanHistory()
            .compactMap { fingerprint, storedScan in
                guard let analysis = storedScan.analysis else {
                    return nil
                }

                return RecentOutfitScore(
                    id: fingerprint,
                    score: storedScan.score,
                    analysis: analysis,
                    firstScannedAt: storedScan.firstScannedAt,
                    scanCount: storedScan.scanCount,
                    thumbnailData: storedScan.thumbnailData,
                    customTitle: storedScan.customTitle,
                    occasion: storedScan.occasion
                )
            }
            .sorted { $0.firstScannedAt > $1.firstScannedAt }
            .prefix(20)
            .map { $0 }
    }

    private func detectsPersonSignal(in cgImage: CGImage, labels: [DetectedLabel]) -> Bool {
        if detectsHumanRectangle(in: cgImage) || detectsFace(in: cgImage) {
            return true
        }

        let personContextTerms = [
            "person",
            "people",
            "human",
            "portrait",
            "face",
            "head",
            "body",
            "torso",
            "arm",
            "hand",
            "leg"
        ]

        return labels.contains { label in
            label.confidence >= 0.18 && personContextTerms.contains { term in
                label.identifier.localizedCaseInsensitiveContains(term)
            }
        }
    }

    private func detectsHumanRectangle(in cgImage: CGImage) -> Bool {
        let request = VNDetectHumanRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)

        do {
            try handler.perform([request])
            let results = request.results ?? []
            #if DEBUG
            let confidences = results
                .map { String(format: "%.3f", $0.confidence) }
                .joined(separator: ", ")
            print("[ScanGate] personDetection humanRectangles count=\(results.count), confidences=[\(confidences)], threshold>0.35")
            #endif
            return results.contains { $0.confidence > 0.35 }
        } catch {
            #if DEBUG
            print("[ScanGate] personDetection humanRectangles error=\(error.localizedDescription), threshold>0.35")
            #endif
            return false
        }
    }

    private func detectsFace(in cgImage: CGImage) -> Bool {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)

        do {
            try handler.perform([request])
            let results = request.results ?? []
            #if DEBUG
            let confidences = results
                .map { String(format: "%.3f", $0.confidence) }
                .joined(separator: ", ")
            print("[ScanGate] personDetection faces count=\(results.count), confidences=[\(confidences)], threshold>0.35")
            #endif
            return results.contains { $0.confidence > 0.35 }
        } catch {
            #if DEBUG
            print("[ScanGate] personDetection faces error=\(error.localizedDescription), threshold>0.35")
            #endif
            return false
        }
    }

    private func classifyImage(_ cgImage: CGImage) -> [VNClassificationObservation] {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)

        do {
            try handler.perform([request])
            let results = request.results ?? []
            #if DEBUG
            let topFive = results
                .sorted { $0.confidence > $1.confidence }
                .prefix(5)
                .map { "\($0.identifier)=\(String(format: "%.3f", $0.confidence))" }
                .joined(separator: ", ")
            print("[StyleMatch Vision Debug] top5: \(topFive)")
            #endif
            return results.filter { observation in
                observation.confidence > 0.15 || isSleepwearObservationWorthKeeping(observation)
            }
        } catch {
            #if DEBUG
            print("[StyleMatch Vision Debug] image classification failed: \(error.localizedDescription)")
            #endif
            return []
        }
    }

    private func isSleepwearObservationWorthKeeping(_ observation: VNClassificationObservation) -> Bool {
        guard observation.confidence >= 0.05 else {
            return false
        }

        let identifier = observation.identifier.lowercased()
        let sleepwearLabels = [
            "pajama", "pyjama", "sleepwear", "nightwear", "nightgown",
            "robe", "bathrobe", "housecoat", "slipper", "slippers",
            "house shoe", "sleep sock"
        ]
        return sleepwearLabels.contains { identifier.contains($0) }
    }

    private func clothingConfidence(in labels: [DetectedLabel]) -> Float {
        labels.reduce(Float(0)) { best, label in
            let isClothing = clothingTerms.contains { term in
                label.identifier.localizedCaseInsensitiveContains(term)
            }
            return isClothing ? max(best, label.confidence) : best
        }
    }

    private func regionClothingValidation(
        for image: UIImage,
        wholeImageLabels: [DetectedLabel]
    ) -> ScanValidation? {
        guard let cgImage = image.fastVisionCGImage() else {
            #if DEBUG
            print("[ScanGate] REGION-VERDICT: unavailable - no CGImage")
            #endif
            return nil
        }

        let scene = flatLayRegionScene(in: wholeImageLabels)
        let acceptanceThreshold: Float = scene == nil ? 0.30 : 0.24
        let candidates = scanRegionCandidates(in: cgImage)
        var strongestMatch: RegionClothingMatch?

        for (index, candidate) in candidates.enumerated() {
            guard let croppedImage = crop(cgImage, to: candidate.normalizedTopLeftBox) else {
                continue
            }

            let regionLabels = classifyImage(croppedImage)
                .map { DetectedLabel(identifier: $0.identifier, confidence: $0.confidence) }
                .sorted { $0.confidence > $1.confidence }

            #if DEBUG
            let topThree = regionLabels
                .prefix(3)
                .map { "\($0.identifier)=\(String(format: "%.3f", $0.confidence))" }
                .joined(separator: ", ")
            print("[ScanGate] REGION: crop=\(index + 1), source=\(candidate.source), box=\(formattedRegionBox(candidate.normalizedTopLeftBox)), top3=[\(topThree)]")
            #endif

            guard let clothingLabel = regionLabels.first(where: { label in
                clothingTerms.contains { term in
                    label.identifier.localizedCaseInsensitiveContains(term)
                }
            }) else {
                continue
            }

            if strongestMatch == nil || clothingLabel.confidence > (strongestMatch?.label.confidence ?? 0) {
                strongestMatch = RegionClothingMatch(label: clothingLabel, labels: regionLabels)
            }
        }

        guard let strongestMatch,
              strongestMatch.label.confidence >= acceptanceThreshold else {
            #if DEBUG
            let bestConfidence = strongestMatch?.label.confidence ?? 0
            print("[ScanGate] REGION-VERDICT: noMatch - candidates=\(candidates.count), bestClothingConfidence=\(String(format: "%.3f", bestConfidence)), threshold>=\(String(format: "%.2f", acceptanceThreshold)), scene=\(scene?.rawValue ?? "none")")
            #endif
            return nil
        }

        let acceptedLabels = mergedRegionLabels(
            regionLabels: strongestMatch.labels,
            wholeImageLabels: wholeImageLabels
        )

        #if DEBUG
        print("[ScanGate] REGION-VERDICT: accepted - label=\(strongestMatch.label.identifier), confidence=\(String(format: "%.3f", strongestMatch.label.confidence)), threshold>=\(String(format: "%.2f", acceptanceThreshold)), scene=\(scene?.rawValue ?? "none")")
        #endif

        if let scene {
            return .acceptedClothingScene(
                scene,
                strongestMatch.label.identifier,
                acceptedLabels
            )
        }
        return .acceptedClothing(strongestMatch.label.identifier, acceptedLabels)
    }

    private func scanRegionCandidates(in cgImage: CGImage, limit: Int = 6) -> [ScanRegionCandidate] {
        let foregroundCandidates = foregroundSubjectRegionCandidates(in: cgImage, limit: limit)
        let objectnessCandidates = objectnessRegionCandidates(in: cgImage, limit: 3)
        let baseCandidates = foregroundCandidates + objectnessCandidates
        let subdividedCandidates = baseCandidates.flatMap(subdividedRegionCandidates)
        let deduplicated = deduplicatedRegionCandidates(baseCandidates + subdividedCandidates)
        return Array(deduplicated.prefix(limit))
    }

    private func foregroundSubjectRegionCandidates(in cgImage: CGImage, limit: Int) -> [ScanRegionCandidate] {
        guard #available(iOS 17.0, *), limit > 0 else {
            return []
        }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)

        do {
            try handler.perform([request])
            guard let observation = request.results?.first else {
                return []
            }

            return observation.allInstances.prefix(limit).compactMap { instance in
                guard let mask = try? observation.generateScaledMaskForImage(
                    forInstances: IndexSet(integer: instance),
                    from: handler
                ),
                let box = normalizedTopLeftBoundingBox(in: mask, threshold: 96) else {
                    return nil
                }
                return ScanRegionCandidate(
                    source: "foregroundSubject",
                    normalizedTopLeftBox: expandedRegionBox(box)
                )
            }
        } catch {
            #if DEBUG
            print("[ScanGate] REGION: foregroundSubject error=\(error.localizedDescription)")
            #endif
            return []
        }
    }

    private func objectnessRegionCandidates(in cgImage: CGImage, limit: Int) -> [ScanRegionCandidate] {
        guard limit > 0 else {
            return []
        }

        let request = VNGenerateObjectnessBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)

        do {
            try handler.perform([request])
            guard let salientObjects = request.results?.first?.salientObjects else {
                return []
            }

            return salientObjects.prefix(limit).map { observation in
                let visionBox = observation.boundingBox
                let topLeftBox = CGRect(
                    x: visionBox.minX,
                    y: 1 - visionBox.maxY,
                    width: visionBox.width,
                    height: visionBox.height
                )
                return ScanRegionCandidate(
                    source: "objectness",
                    normalizedTopLeftBox: expandedRegionBox(topLeftBox)
                )
            }
        } catch {
            #if DEBUG
            print("[ScanGate] REGION: objectness error=\(error.localizedDescription)")
            #endif
            return []
        }
    }

    private func subdividedRegionCandidates(_ candidate: ScanRegionCandidate) -> [ScanRegionCandidate] {
        let box = candidate.normalizedTopLeftBox
        guard box.width * box.height > 0.60 else {
            return []
        }

        let halves: [CGRect]
        if box.width >= box.height {
            let halfWidth = box.width / 2
            halves = [
                CGRect(x: box.minX, y: box.minY, width: halfWidth, height: box.height),
                CGRect(x: box.minX + halfWidth, y: box.minY, width: halfWidth, height: box.height)
            ]
        } else {
            let halfHeight = box.height / 2
            halves = [
                CGRect(x: box.minX, y: box.minY, width: box.width, height: halfHeight),
                CGRect(x: box.minX, y: box.minY + halfHeight, width: box.width, height: halfHeight)
            ]
        }

        return halves.map {
            ScanRegionCandidate(source: "subdivided", normalizedTopLeftBox: $0)
        }
    }

    private func deduplicatedRegionCandidates(
        _ candidates: [ScanRegionCandidate],
        overlapThreshold: CGFloat = 0.8
    ) -> [ScanRegionCandidate] {
        var result: [ScanRegionCandidate] = []

        for candidate in candidates {
            if let duplicateIndex = result.firstIndex(where: {
                regionIntersectionOverUnion(
                    candidate.normalizedTopLeftBox,
                    $0.normalizedTopLeftBox
                ) > overlapThreshold
            }) {
                let candidateArea = candidate.normalizedTopLeftBox.width * candidate.normalizedTopLeftBox.height
                let existingArea = result[duplicateIndex].normalizedTopLeftBox.width
                    * result[duplicateIndex].normalizedTopLeftBox.height
                if candidateArea < existingArea {
                    result[duplicateIndex] = candidate
                }
            } else {
                result.append(candidate)
            }
        }

        return result
    }

    private func regionIntersectionOverUnion(_ first: CGRect, _ second: CGRect) -> CGFloat {
        let intersection = first.intersection(second)
        guard !intersection.isNull, !intersection.isEmpty else {
            return 0
        }

        let intersectionArea = intersection.width * intersection.height
        let unionArea = first.width * first.height
            + second.width * second.height
            - intersectionArea
        return unionArea > 0 ? intersectionArea / unionArea : 0
    }

    private func normalizedTopLeftBoundingBox(
        in pixelBuffer: CVPixelBuffer,
        threshold: UInt8
    ) -> CGRect? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1

        for y in 0..<height {
            for x in 0..<width where bytes[y * bytesPerRow + x] > threshold {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard maxX >= minX, maxY >= minY else {
            return nil
        }

        return CGRect(
            x: CGFloat(minX) / CGFloat(width),
            y: CGFloat(minY) / CGFloat(height),
            width: CGFloat(maxX - minX + 1) / CGFloat(width),
            height: CGFloat(maxY - minY + 1) / CGFloat(height)
        )
    }

    private func expandedRegionBox(_ box: CGRect) -> CGRect {
        let expanded = box.insetBy(dx: -box.width * 0.08, dy: -box.height * 0.08)
        return expanded.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    private func crop(_ cgImage: CGImage, to normalizedTopLeftBox: CGRect) -> CGImage? {
        let pixelBox = CGRect(
            x: normalizedTopLeftBox.minX * CGFloat(cgImage.width),
            y: normalizedTopLeftBox.minY * CGFloat(cgImage.height),
            width: normalizedTopLeftBox.width * CGFloat(cgImage.width),
            height: normalizedTopLeftBox.height * CGFloat(cgImage.height)
        )
        .integral
        .intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))

        guard pixelBox.width >= 2, pixelBox.height >= 2 else {
            return nil
        }
        return cgImage.cropping(to: pixelBox)
    }

    private func flatLayRegionScene(in labels: [DetectedLabel]) -> ClothingScanScene? {
        if labels.contains(where: { label in mannequinTerms.contains { label.identifier.localizedCaseInsensitiveContains($0) } }) {
            return .mannequin
        }
        if labels.contains(where: { label in hangerTerms.contains { label.identifier.localizedCaseInsensitiveContains($0) } }) {
            return .hanger
        }
        if labels.contains(where: { label in bedTerms.contains { label.identifier.localizedCaseInsensitiveContains($0) } }) {
            return .bed
        }
        if labels.contains(where: { label in tableTerms.contains { label.identifier.localizedCaseInsensitiveContains($0) } }) {
            return .table
        }
        if labels.contains(where: { label in floorTerms.contains { label.identifier.localizedCaseInsensitiveContains($0) } }) {
            return .floor
        }
        return nil
    }

    private func mergedRegionLabels(
        regionLabels: [DetectedLabel],
        wholeImageLabels: [DetectedLabel]
    ) -> [DetectedLabel] {
        var seen = Set<String>()
        return (regionLabels + wholeImageLabels)
            .sorted { $0.confidence > $1.confidence }
            .filter { seen.insert($0.identifier.lowercased()).inserted }
            .prefix(12)
            .map { $0 }
    }

    #if DEBUG
    private func formattedRegionBox(_ box: CGRect) -> String {
        String(
            format: "(x=%.3f,y=%.3f,w=%.3f,h=%.3f)",
            box.minX,
            box.minY,
            box.width,
            box.height
        )
    }
    #endif

    private func strongestRejectedLabel(in labels: [DetectedLabel]) -> String? {
        let strongRejected = labels.first { label in
            label.confidence >= 0.32 && rejectedTerms.contains { term in
                label.identifier.localizedCaseInsensitiveContains(term)
            }
        }

        return strongRejected?.identifier
    }

    private func traditionalStyleMatch(in labels: [DetectedLabel], image: UIImage?) -> TraditionalStyleMatch? {
        guard noveltyClothingMatch(in: labels) == nil else {
            return nil
        }

        let labelText = labels.map(\.identifier).joined(separator: " ").lowercased()

        if let rule = traditionalClothingRules.first(where: { rule in
            rule.terms.contains { labelText.contains($0.lowercased()) }
        }) {
            let strongestRuleConfidence = labels
                .filter { label in
                    rule.terms.contains { label.identifier.localizedCaseInsensitiveContains($0) }
                }
                .map(\.confidence)
                .max() ?? 0
            let supportingFeatureCount = traditionalSupportFeatureCount(in: labelText)
            let hasExplicitGarmentLabel = strongestRuleConfidence >= 0.55
            let hasMultipleTraditionalFeatures = supportingFeatureCount >= 2

            guard hasExplicitGarmentLabel || hasMultipleTraditionalFeatures else {
                return nil
            }

            let confidence: Float = hasExplicitGarmentLabel && hasMultipleTraditionalFeatures ? 0.96 : 0.91

            return TraditionalStyleMatch(
                garment: rule.garment,
                styleCategory: rule.styleCategory,
                occasionCategory: rule.occasionCategory,
                dressCode: rule.dressCode,
                confidence: confidence,
                summary: "Detected \(rule.garment). Confidence: \(Int((confidence * 100).rounded()))%. Style category: \(rule.styleCategory). Occasion: \(rule.occasionCategory). Dress code: \(rule.dressCode). Style Match Pro evaluates visible clothing details such as fabric, pattern, embroidery, neckline, sleeves, silhouette, layering, headwear, color harmony, fit, and accessories. It does not infer race, ethnicity, nationality, religion, age, gender, or identity."
            )
        }

        guard let image,
              shouldUseAfricanTraditionalFallback(labels: labels, image: image) else {
            return nil
        }

        return TraditionalStyleMatch(
            garment: "African Traditional Wear",
            styleCategory: "Cultural Wear",
            occasionCategory: inferredTraditionalOccasion(),
            dressCode: "Formal Traditional",
            confidence: 0.91,
            summary: "Detected African traditional wear from multiple visible clothing signals: textile color, pattern density, garment structure, and occasion context. Confidence: 91%. Style category: Cultural Wear. Occasion: \(inferredTraditionalOccasion()). Dress code: Formal Traditional. Style Match Pro evaluates fabric presentation, pattern balance, color harmony, fit, layering, headwear, accessories, and overall coordination. It does not infer race, ethnicity, nationality, religion, age, gender, or identity."
        )
    }

    private func shouldUseAfricanTraditionalFallback(labels: [DetectedLabel], image: UIImage) -> Bool {
        guard noveltyClothingMatch(in: labels) == nil else {
            return false
        }

        let labelText = labels.map(\.identifier).joined(separator: " ").lowercased()
        let hasAcceptedClothingContext = labelText.contains("person")
            || labelText.contains("clothing")
            || labelText.contains("apparel")
            || labelText.contains("fashion")
            || labelText.contains("dress")
            || labelText.contains("shirt")
            || labelText.contains("robe")
            || labelText.contains("gown")
            || labelText.contains("fabric")
            || labelText.contains("textile")
            || labelText.contains("suit")
        let contextText = "\(plannedOccasion) \(dressCode) \(occasionFormality) \(occasions) \(stylePreferences)".lowercased()
        let userTraditionalContext = ["traditional", "native", "african", "nigerian", "wedding", "ceremony", "cultural", "heritage"].contains { contextText.contains($0) }
        let textileScore = image.traditionalTextileSignalScore()
        let supportCount = traditionalSupportFeatureCount(in: labelText)

        return hasAcceptedClothingContext && textileScore >= 8 && userTraditionalContext && supportCount >= 1
    }

    private func noveltyClothingMatch(in labels: [DetectedLabel]) -> NoveltyClothingMatch? {
        let labelText = labels.map(\.identifier).joined(separator: " ").lowercased()
        let ruleMatches = noveltyClothingRules.compactMap { rule -> (rule: NoveltyClothingRule, score: Int, confidence: Float)? in
            let matchedTerms = rule.terms.filter { labelText.contains($0) }
            let confidence = labels
                .filter { label in rule.terms.contains { label.identifier.localizedCaseInsensitiveContains($0) } }
                .map(\.confidence)
                .max() ?? (matchedTerms.isEmpty ? 0 : 0.62)
            let score = matchedTerms.count * 2 + Int((confidence * 10).rounded())
            guard score > 0 else { return nil }
            return (rule, score, confidence)
        }

        guard let best = ruleMatches.sorted(by: { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.confidence > rhs.confidence
            }
            return lhs.score > rhs.score
        }).first else {
            return nil
        }

        let confidence = max(best.confidence, best.score >= 7 ? 0.92 : 0.84)
        return NoveltyClothingMatch(
            garment: best.rule.garment,
            styleCategory: best.rule.styleCategory,
            occasionCategory: best.rule.occasionCategory,
            dressCode: best.rule.dressCode,
            confidence: min(confidence, 0.98),
            occasionNote: "Occasion check: this reads as \(best.rule.styleCategory.lowercased()), so Style Match Pro recommends it for home, themed events, sleepwear, cozy lounging, or playful casual settings instead of formal or traditional occasions.",
            summary: "Detected \(best.rule.garment). Style category: \(best.rule.styleCategory). This classification takes priority over Traditional Wear because the scan includes novelty, sleepwear, character, plush, robe, slipper, costume, or loungewear signals. Style Match Pro avoids guessing cultural attire unless confidence is at least 90% and multiple traditional garment features are visible."
        )
    }

    private func clothingPurposeClassification(validation: ScanValidation, labels: [DetectedLabel], image: UIImage?) -> ClothingPurposeMatch? {
        let labelText = labels.map(\.identifier).joined(separator: " ").lowercased()
        let sceneText = "\(validation.sceneName) \(validation.arrangementFingerprint) \(detectedEnvironment(from: labels))".lowercased()
        let contextText = "\(labelText) \(sceneText)"
        let imageSleepwearBoost = image?.sleepwearVisualSignalScore() ?? 0

        let sleepwearTerms = [
            "pajama", "pyjama", "sleepwear", "nightwear", "nightgown", "sleep shirt",
            "sleep set", "matching sleep", "robe", "bathrobe", "fleece robe", "plush robe",
            "morning robe", "housecoat", "slipper", "slippers", "fuzzy slipper",
            "plush slipper", "bedroom slipper", "house shoe", "sleep sock", "flannel pajama",
            "flannel pajamas", "pajama flannel"
        ]
        let loungeTerms = [
            "loungewear", "lounge set", "house clothes", "indoor wear", "homewear",
            "blanket hoodie", "fuzzy slipper", "plush robe", "plush slipper"
        ]
        let childTerms = [
            "child", "kid", "girl", "boy", "children", "toddler", "youth", "young person",
            "children's room", "kids room", "toy"
        ]
        let bedroomTerms = [
            "bedroom", "bathroom", "bed", "blanket", "pillow", "dresser", "closet",
            "children's room", "kids room", "home"
        ]
        let matchingSetTerms = [
            "matching set", "coordinated set", "two-piece", "two piece",
            "matching top and bottom", "top and bottom", "matching outfit",
            "shirt and pants set", "pants set"
        ]
        let comfortPatternTerms = [
            "stripe", "striped", "red and white", "pink and white", "pink red",
            "pastel", "soft", "loose", "barefoot"
        ]

        let sleepMatches = sleepwearTerms.filter { contextText.contains($0) }.count
        let loungeMatches = loungeTerms.filter { contextText.contains($0) }.count
        let childMatches = childTerms.filter { contextText.contains($0) }.count
        let bedroomMatches = bedroomTerms.filter { contextText.contains($0) }.count
        let matchingSetMatches = matchingSetTerms.filter { contextText.contains($0) }.count
        let comfortPatternMatches = comfortPatternTerms.filter { contextText.contains($0) }.count
        let contextualSleepwearSetSignal = (childMatches > 0 || bedroomMatches > 0)
            && (matchingSetMatches > 0 || imageSleepwearBoost >= 5)
            && (comfortPatternMatches > 0 || imageSleepwearBoost >= 5)
        let visualHomeSleepwearSignal = imageSleepwearBoost >= 6 && (childMatches > 0 || bedroomMatches > 0)
        let hasStrongSleepwearSignal = sleepMatches >= 1 || contextualSleepwearSetSignal || visualHomeSleepwearSignal
        let hasIndoorComfortSignal = loungeMatches >= 1
            || contextualSleepwearSetSignal
            || visualHomeSleepwearSignal
            || (imageSleepwearBoost >= 5 && bedroomMatches > 0)

        if hasStrongSleepwearSignal || (hasIndoorComfortSignal && childMatches > 0) {
            let category = childMatches > 0 ? "Children's Sleepwear" : (sleepMatches > 0 || contextualSleepwearSetSignal || visualHomeSleepwearSignal ? "Sleepwear" : "Indoor Wear")
            let confidence = min(0.94, Float(0.78 + Double(sleepMatches + loungeMatches + bedroomMatches + childMatches + matchingSetMatches + comfortPatternMatches) * 0.04 + Double(imageSleepwearBoost) * 0.01))
            return ClothingPurposeMatch(
                garment: category,
                styleCategory: category,
                occasionCategory: childMatches > 0 ? "Kids Sleepwear or Home Comfort" : "Home, Sleepwear, or Loungewear",
                dressCode: "Sleepwear",
                confidence: max(confidence, 0.84),
                occasionNote: "Occasion check: this reads as \(category.lowercased()), so StyleMatch Pro keeps it in home, bedtime, or relaxed indoor settings instead of business, office, smart casual, or formal categories.",
                summary: childMatches > 0
                    ? "This appears to be children's sleepwear or home loungewear. The soft robe, pajama-style pieces, indoor setting, or slipper signals point to comfort and relaxing at home, not business casual."
                    : "This appears to be sleepwear, loungewear, or indoor wear. Soft fabric, robe, slipper, pajama, or home-environment signals take priority over business or formal styling."
            )
        }

        if hasIndoorComfortSignal && (loungeMatches > 0 || bedroomMatches > 0) {
            return ClothingPurposeMatch(
                garment: "Loungewear",
                styleCategory: "Loungewear",
                occasionCategory: "Home or Casual Comfort",
                dressCode: "Relaxed",
                confidence: 0.84,
                occasionNote: "Occasion check: this reads as loungewear or indoor wear, so StyleMatch Pro avoids business, professional, formal, or office labels.",
                summary: "This appears to be loungewear or indoor wear. The home setting and comfort-focused clothing signals make relaxed styling more realistic than business or formal styling."
            )
        }

        let athleticTerms = ["athletic", "sportswear", "gym", "workout", "running", "training", "jersey"]
        if athleticTerms.contains(where: { contextText.contains($0) }) {
            return ClothingPurposeMatch(
                garment: "Athletic Wear",
                styleCategory: "Athletic Wear",
                occasionCategory: "Gym, Training, or Casual Sport",
                dressCode: "Athletic",
                confidence: 0.88,
                occasionNote: "Occasion check: this reads as athletic wear, so recommendations should focus on movement, comfort, and sport styling.",
                summary: "This appears to be athletic wear. StyleMatch Pro evaluates comfort, color coordination, shoe pairing, and activity fit rather than business formality."
            )
        }

        let uniformTerms = ["uniform", "scrub", "medical", "school uniform", "work uniform"]
        if uniformTerms.contains(where: { contextText.contains($0) }) {
            return ClothingPurposeMatch(
                garment: "Uniform",
                styleCategory: contextText.contains("scrub") ? "Medical Scrubs" : "Uniform",
                occasionCategory: "Work, School, or Service Uniform",
                dressCode: "Uniform",
                confidence: 0.88,
                occasionNote: "Occasion check: this reads as a uniform, so styling advice should respect the purpose and dress requirements.",
                summary: "This appears to be uniform-related clothing. StyleMatch Pro evaluates neatness, fit, comfort, and appropriate accessories rather than casual or formal labels."
            )
        }

        if isRuggedCasualEvidence(contextText) {
            return ClothingPurposeMatch(
                garment: "Rugged Casual",
                styleCategory: "Rugged Casual",
                occasionCategory: "Everyday Casual",
                dressCode: "Casual",
                confidence: contextText.contains("boot") ? 0.93 : 0.90,
                occasionNote: "Occasion check: this reads as rugged casual or outdoor casual, so StyleMatch Pro keeps business casual confidence low unless clear business-style pieces are visible.",
                summary: "This appears to be a rugged casual everyday outfit. The hooded, plaid, flannel, denim, or casual footwear signals create a relaxed outdoor/workwear casual look rather than a business casual look."
            )
        }

        return nil
    }

    private func traditionalSupportFeatureCount(in text: String) -> Int {
        let supportTerms = [
            "embroidery", "embroidered", "woven", "textile", "fabric", "pattern", "ceremonial",
            "heritage", "traditional", "native", "ankara", "aso oke", "kente", "head wrap",
            "headwrap", "gele", "duku", "robe", "kaftan", "agbada", "dashiki", "sari", "saree",
            "kimono", "hanbok", "thobe", "abaya", "kilt", "dirndl", "huipil"
        ]
        return supportTerms.reduce(0) { count, term in
            text.contains(term) ? count + 1 : count
        }
    }

    private var noveltyClothingRules: [NoveltyClothingRule] {
        [
            NoveltyClothingRule(garment: "Character Clothing", terms: ["hello kitty", "kitty", "disney", "pokemon", "pokémon", "marvel", "dc comics", "anime", "cartoon", "character", "mascot", "graphic character"], styleCategory: "Character Clothing", occasionCategory: "Playful Casual", dressCode: "Novelty Casual"),
            NoveltyClothingRule(garment: "Onesie", terms: ["onesie", "one-piece pajamas", "one piece pajama", "romper pajama", "jumpsuit pajama"], styleCategory: "Onesie", occasionCategory: "Sleepwear or Loungewear", dressCode: "Loungewear"),
            NoveltyClothingRule(garment: "Sleepwear", terms: ["pajama", "pyjama", "sleepwear", "nightwear", "sleep shirt", "sleep set", "matching sleepwear"], styleCategory: "Sleepwear", occasionCategory: "Home or Sleepwear", dressCode: "Sleepwear"),
            NoveltyClothingRule(garment: "Loungewear", terms: ["loungewear", "lounge set", "robe", "bathrobe", "blanket hoodie", "plush robe", "fuzzy slipper", "house shoe"], styleCategory: "Loungewear", occasionCategory: "Home or Casual Comfort", dressCode: "Relaxed"),
            NoveltyClothingRule(garment: "Costume or Novelty Wear", terms: ["costume", "cosplay", "animal costume", "unicorn", "bear hoodie", "bunny hoodie", "animal ears", "cat ears", "hood with ears", "plush hoodie"], styleCategory: "Novelty Wear", occasionCategory: "Themed Event or Playful Casual", dressCode: "Novelty Casual"),
            NoveltyClothingRule(garment: "Fuzzy Slippers", terms: ["slipper", "slippers", "fuzzy slipper", "plush slipper", "house shoe"], styleCategory: "Loungewear", occasionCategory: "Home or Sleepwear", dressCode: "Relaxed")
        ]
    }

    private func inferredTraditionalOccasion() -> String {
        let contextText = "\(plannedOccasion) \(dressCode) \(occasionFormality) \(occasions)".lowercased()

        if contextText.contains("wedding") {
            return "Traditional Wedding"
        }
        if contextText.contains("church") || contextText.contains("religious") {
            return "Religious Celebration"
        }
        if contextText.contains("festival") || contextText.contains("celebration") {
            return "Cultural Festival"
        }
        if contextText.contains("graduation") {
            return "Graduation"
        }
        if contextText.contains("ceremony") || contextText.contains("formal") {
            return "Ceremony"
        }

        return "Cultural Celebration"
    }

    private var traditionalClothingRules: [TraditionalClothingRule] {
        [
            TraditionalClothingRule(garment: "Traditional Nigerian Agbada", terms: ["agbada"], styleCategory: "Traditional Wear", occasionCategory: "Traditional Nigerian Wear"),
            TraditionalClothingRule(garment: "Senator Wear", terms: ["senator wear", "senator suit"], styleCategory: "Heritage Wear", occasionCategory: "Traditional Wear"),
            TraditionalClothingRule(garment: "Isiagu", terms: ["isiagu"], styleCategory: "Heritage Wear", occasionCategory: "Traditional Wear"),
            TraditionalClothingRule(garment: "Buba and Iro", terms: ["buba", "iro", "buba and iro"], styleCategory: "Traditional Wear", occasionCategory: "Traditional Wear"),
            TraditionalClothingRule(garment: "Ankara", terms: ["ankara", "wax print", "african print"], styleCategory: "Cultural Wear", occasionCategory: "Cultural Celebration"),
            TraditionalClothingRule(garment: "Aso Oke", terms: ["aso oke", "aso-oke"], styleCategory: "Ceremonial Wear", occasionCategory: "Traditional Wedding"),
            TraditionalClothingRule(garment: "Dashiki", terms: ["dashiki"], styleCategory: "Cultural Wear", occasionCategory: "Cultural Wear"),
            TraditionalClothingRule(garment: "Kaftan", terms: ["kaftan", "caftan"], styleCategory: "Traditional Wear", occasionCategory: "Traditional Wear"),
            TraditionalClothingRule(garment: "Boubou", terms: ["boubou"], styleCategory: "Traditional Wear", occasionCategory: "Ceremonial Wear"),
            TraditionalClothingRule(garment: "Grand Boubou", terms: ["grand boubou"], styleCategory: "Cultural Formal Wear", occasionCategory: "Ceremony"),
            TraditionalClothingRule(garment: "Moroccan Djellaba", terms: ["djellaba", "jellaba"], styleCategory: "Traditional Wear", occasionCategory: "Traditional Wear"),
            TraditionalClothingRule(garment: "Traditional African Head Wrap", terms: ["gele", "duku", "head wrap", "headwrap"], styleCategory: "Traditional Accessory", occasionCategory: "Traditional Wear"),
            TraditionalClothingRule(garment: "Kente", terms: ["kente"], styleCategory: "Heritage Wear", occasionCategory: "Ceremonial Wear"),
            TraditionalClothingRule(garment: "Kanzu", terms: ["kanzu"], styleCategory: "Traditional Wear", occasionCategory: "Religious or Ceremonial Attire"),
            TraditionalClothingRule(garment: "Gomesi", terms: ["gomesi"], styleCategory: "Traditional Wear", occasionCategory: "Ceremonial Wear"),
            TraditionalClothingRule(garment: "Shuka", terms: ["shuka", "maasai shuka"], styleCategory: "Heritage Wear", occasionCategory: "Cultural Wear"),
            TraditionalClothingRule(garment: "Habesha Kemis", terms: ["habesha kemis", "habesha dress"], styleCategory: "Traditional Wear", occasionCategory: "Ceremonial Wear"),
            TraditionalClothingRule(garment: "Kimono", terms: ["kimono"], styleCategory: "Traditional Wear", occasionCategory: "Ceremonial Wear"),
            TraditionalClothingRule(garment: "Yukata", terms: ["yukata"], styleCategory: "Festival Wear", occasionCategory: "Festival Wear"),
            TraditionalClothingRule(garment: "Hanfu", terms: ["hanfu"], styleCategory: "Traditional Wear", occasionCategory: "Heritage Wear"),
            TraditionalClothingRule(garment: "Qipao / Cheongsam", terms: ["qipao", "cheongsam"], styleCategory: "Traditional Wear", occasionCategory: "Evening or Ceremonial Wear"),
            TraditionalClothingRule(garment: "Hanbok", terms: ["hanbok"], styleCategory: "Traditional Wear", occasionCategory: "Ceremonial Wear"),
            TraditionalClothingRule(garment: "Saree", terms: ["saree", "sari"], styleCategory: "Traditional Wear", occasionCategory: "Wedding Traditional Wear"),
            TraditionalClothingRule(garment: "Salwar Kameez", terms: ["salwar kameez", "shalwar kameez"], styleCategory: "Traditional Wear", occasionCategory: "Traditional Wear"),
            TraditionalClothingRule(garment: "Sherwani", terms: ["sherwani"], styleCategory: "Wedding Traditional Wear", occasionCategory: "Wedding Traditional Wear"),
            TraditionalClothingRule(garment: "Kurta Pajama", terms: ["kurta pajama", "kurta pyjama", "kurta"], styleCategory: "Traditional Wear", occasionCategory: "Traditional Wear"),
            TraditionalClothingRule(garment: "Lehenga", terms: ["lehenga"], styleCategory: "Wedding Traditional Wear", occasionCategory: "Wedding Traditional Wear"),
            TraditionalClothingRule(garment: "Ao Dai", terms: ["ao dai", "aodai"], styleCategory: "National Dress", occasionCategory: "Ceremonial Wear"),
            TraditionalClothingRule(garment: "Chut Thai", terms: ["chut thai"], styleCategory: "National Dress", occasionCategory: "Ceremonial Wear"),
            TraditionalClothingRule(garment: "Batik Clothing", terms: ["batik"], styleCategory: "Heritage Wear", occasionCategory: "Cultural Wear"),
            TraditionalClothingRule(garment: "Traditional Indonesian Clothing", terms: ["kebaya", "sarong", "songket", "indonesian traditional clothing"], styleCategory: "National Dress", occasionCategory: "Ceremonial Wear"),
            TraditionalClothingRule(garment: "Thobe", terms: ["thobe", "thoab"], styleCategory: "Traditional Wear", occasionCategory: "Traditional Wear"),
            TraditionalClothingRule(garment: "Kandura", terms: ["kandura"], styleCategory: "Traditional Wear", occasionCategory: "Traditional Wear"),
            TraditionalClothingRule(garment: "Dishdasha", terms: ["dishdasha"], styleCategory: "Traditional Wear", occasionCategory: "Traditional Wear"),
            TraditionalClothingRule(garment: "Bisht", terms: ["bisht"], styleCategory: "Ceremonial Wear", occasionCategory: "Ceremonial Wear"),
            TraditionalClothingRule(garment: "Abaya", terms: ["abaya"], styleCategory: "Traditional Wear", occasionCategory: "Religious Attire"),
            TraditionalClothingRule(garment: "Jalabiya", terms: ["jalabiya", "jellabiya"], styleCategory: "Traditional Wear", occasionCategory: "Traditional Wear"),
            TraditionalClothingRule(garment: "Keffiyeh", terms: ["keffiyeh", "keffiyah"], styleCategory: "Traditional Accessory", occasionCategory: "Cultural Wear"),
            TraditionalClothingRule(garment: "Shemagh", terms: ["shemagh"], styleCategory: "Traditional Accessory", occasionCategory: "Cultural Wear"),
            TraditionalClothingRule(garment: "Scottish Kilt", terms: ["kilt"], styleCategory: "National Dress", occasionCategory: "Ceremonial Wear"),
            TraditionalClothingRule(garment: "Lederhosen", terms: ["lederhosen"], styleCategory: "Festival Wear", occasionCategory: "Festival Wear"),
            TraditionalClothingRule(garment: "Dirndl", terms: ["dirndl"], styleCategory: "Festival Wear", occasionCategory: "Festival Wear"),
            TraditionalClothingRule(garment: "Vyshyvanka", terms: ["vyshyvanka", "embroidered shirt"], styleCategory: "Heritage Wear", occasionCategory: "National Dress"),
            TraditionalClothingRule(garment: "Flamenco Dress", terms: ["flamenco dress", "flamenco"], styleCategory: "Cultural Wear", occasionCategory: "Festival Wear"),
            TraditionalClothingRule(garment: "Native American Regalia", terms: ["native american regalia", "regalia"], styleCategory: "Ceremonial Wear", occasionCategory: "Ceremonial Wear"),
            TraditionalClothingRule(garment: "Charro Suit", terms: ["charro suit", "charro"], styleCategory: "Heritage Wear", occasionCategory: "Ceremonial Wear"),
            TraditionalClothingRule(garment: "Huipil", terms: ["huipil"], styleCategory: "Heritage Wear", occasionCategory: "Traditional Wear"),
            TraditionalClothingRule(garment: "Pollera", terms: ["pollera"], styleCategory: "Traditional Wear", occasionCategory: "Festival Wear"),
            TraditionalClothingRule(garment: "Poncho", terms: ["poncho"], styleCategory: "Traditional Wear", occasionCategory: "Traditional Wear"),
            TraditionalClothingRule(garment: "Traditional Andean Clothing", terms: ["andean clothing", "andean", "chullo"], styleCategory: "Heritage Wear", occasionCategory: "Cultural Wear"),
            TraditionalClothingRule(garment: "Lava-lava", terms: ["lava-lava", "lavalava"], styleCategory: "Traditional Wear", occasionCategory: "Cultural Wear"),
            TraditionalClothingRule(garment: "Pareo", terms: ["pareo"], styleCategory: "Traditional Wear", occasionCategory: "Cultural Wear"),
            TraditionalClothingRule(garment: "Maori Traditional Garments", terms: ["maori cloak", "korowai", "maori garment"], styleCategory: "Ceremonial Wear", occasionCategory: "Ceremonial Wear"),
            TraditionalClothingRule(garment: "Samoan Ceremonial Clothing", terms: ["samoan ceremonial", "samoan traditional clothing", "ie toga"], styleCategory: "Ceremonial Wear", occasionCategory: "Ceremony"),
            TraditionalClothingRule(garment: "Tongan Ceremonial Clothing", terms: ["tongan ceremonial", "tongan traditional clothing", "taovala"], styleCategory: "Ceremonial Wear", occasionCategory: "Ceremony"),
            TraditionalClothingRule(garment: "Pacific Ceremonial Dress", terms: ["pacific ceremonial dress", "pacific traditional dress"], styleCategory: "Ceremonial Wear", occasionCategory: "Ceremonial Wear")
        ]
    }

    private func clothingSceneMatch(in labels: [DetectedLabel]) -> ClothingSceneMatch? {
        let clothingLabel = labels.first { label in
            clothingTerms.contains { label.identifier.localizedCaseInsensitiveContains($0) }
        }

        guard let clothingLabel else {
            return nil
        }

        if labels.contains(where: { label in mannequinTerms.contains { label.identifier.localizedCaseInsensitiveContains($0) } }) {
            return ClothingSceneMatch(scene: .mannequin, label: clothingLabel.identifier)
        }

        if labels.contains(where: { label in hangerTerms.contains { label.identifier.localizedCaseInsensitiveContains($0) } }) {
            return ClothingSceneMatch(scene: .hanger, label: clothingLabel.identifier)
        }

        if labels.contains(where: { label in bedTerms.contains { label.identifier.localizedCaseInsensitiveContains($0) } }) {
            return ClothingSceneMatch(scene: .bed, label: clothingLabel.identifier)
        }

        if labels.contains(where: { label in bagTerms.contains { label.identifier.localizedCaseInsensitiveContains($0) } }) {
            return ClothingSceneMatch(scene: .bag, label: clothingLabel.identifier)
        }

        if labels.contains(where: { label in tableTerms.contains { label.identifier.localizedCaseInsensitiveContains($0) } }) {
            return ClothingSceneMatch(scene: .table, label: clothingLabel.identifier)
        }

        if labels.contains(where: { label in floorTerms.contains { label.identifier.localizedCaseInsensitiveContains($0) } }) {
            return ClothingSceneMatch(scene: .floor, label: clothingLabel.identifier)
        }

        if labels.contains(where: { label in shoppingDisplayTerms.contains { label.identifier.localizedCaseInsensitiveContains($0) } }) {
            return ClothingSceneMatch(scene: .shoppingDisplay, label: clothingLabel.identifier)
        }

        return nil
    }

    private func detectedClothingItems(from labels: [DetectedLabel]) -> [String] {
        let standardItems = labels
            .filter { label in
                clothingTerms.contains { label.identifier.localizedCaseInsensitiveContains($0) }
            }
            .compactMap { GarmentLabelMapper.humanReadableTerm(for: $0.identifier) }
            .removingDuplicates()
            .prefix(8)
            .map { $0 }

        if let noveltyStyle = noveltyClothingMatch(in: labels) {
            return ([noveltyStyle.garment] + standardItems)
                .removingDuplicates()
                .prefix(8)
                .map { $0 }
        }

        guard let culturalStyle = traditionalStyleMatch(in: labels, image: nil) else {
            return standardItems
        }

        return ([culturalStyle.garment] + standardItems)
            .removingDuplicates()
            .prefix(8)
            .map { $0 }
    }

    private func detectedItemConfidences(for items: [String], labels: [DetectedLabel], culturalStyle: TraditionalStyleMatch?) -> [DetectedItemConfidence] {
        items
            .prefix(8)
            .enumerated()
            .map { index, item in
                let itemKey = item.lowercased()
                let matchedConfidence = labels
                    .filter { label in
                        let labelKey = label.identifier.lowercased()
                        return labelKey.contains(itemKey) || itemKey.contains(labelKey)
                    }
                    .map(\.confidence)
                    .max()

                let confidence: Int
                if let culturalStyle, culturalStyle.garment.localizedCaseInsensitiveCompare(item) == .orderedSame {
                    confidence = Int((culturalStyle.confidence * 100).rounded())
                } else if let matchedConfidence {
                    confidence = Int((matchedConfidence * 100).rounded())
                } else {
                    confidence = max(72, 82 - index * 2)
                }

                return DetectedItemConfidence(item: item, confidence: min(max(confidence, 72), 99))
            }
    }

    private func detectedEnvironment(from labels: [DetectedLabel]) -> String {
        let environmentRules: [(String, [String])] = [
            ("Home", ["home", "bedroom", "living room", "kitchen", "house"]),
            ("Office", ["office", "desk", "conference room", "workplace"]),
            ("Closet", ["closet", "wardrobe", "clothing rack"]),
            ("Bedroom", ["bedroom", "bed", "dresser"]),
            ("Store", ["store", "shop", "retail", "boutique"]),
            ("Dressing Room", ["dressing room", "fitting room", "mirror"]),
            ("Church", ["church", "chapel", "sanctuary"]),
            ("Wedding", ["wedding", "bride", "groom", "banquet"]),
            ("Party", ["party", "club", "celebration"]),
            ("School", ["school", "classroom", "campus"]),
            ("Gym", ["gym", "fitness", "exercise"]),
            ("Beach", ["beach", "sand", "ocean", "swim"]),
            ("Business", ["business", "suit", "formal", "meeting"]),
            ("Casual", ["casual", "jeans", "sneaker", "t-shirt"]),
            ("Outdoor", ["outdoor", "park", "street", "sidewalk"]),
            ("Parking Garage", ["parking", "garage"])
        ]

        for rule in environmentRules {
            if labels.contains(where: { label in rule.1.contains { label.identifier.localizedCaseInsensitiveContains($0) } }) {
                return rule.0
            }
        }

        return "Unspecified"
    }

    private var clothingTerms: [String] {
        [
            "clothing",
            "apparel",
            "shirt",
            "t-shirt",
            "polo",
            "top",
            "pants",
            "trousers",
            "jeans",
            "dress",
            "skirt",
            "suit",
            "blazer",
            "jacket",
            "coat",
            "shoe",
            "footwear",
            "sneaker",
            "boot",
            "loafer",
            "heel",
            "sandal",
            "hat",
            "cap",
            "belt",
            "bag",
            "handbag",
            "purse",
            "watch",
            "accessory",
            "uniform",
            "fashion",
            "fabric",
            "textile",
            "laundry",
            "wardrobe",
            "closet",
            "outfit",
            "garment",
            "sweater",
            "hoodie",
            "shorts",
            "blouse",
            "tie",
            "scarf",
            "sock",
            "bra",
            "underwear",
            "pajama",
            "pyjama",
            "sleepwear",
            "nightwear",
            "nightgown",
            "robe",
            "bathrobe",
            "housecoat",
            "slipper",
            "slippers",
            "bedroom slipper",
            "house shoe",
            "fuzzy slipper",
            "plush slipper",
            "loungewear",
            "onesie",
            "clothes"
        ] + traditionalClothingRules.flatMap(\.terms)
    }

    private func hasSleepwearLabelEvidence(in labels: [DetectedLabel]) -> Bool {
        sleepwearOrLoungewearCategory(from: labels.map(\.identifier).joined(separator: " ")) != nil
    }

    private var mannequinTerms: [String] {
        [
            "mannequin",
            "dummy",
            "dress form",
            "display"
        ]
    }

    private var hangerTerms: [String] {
        [
            "hanger",
            "coat hanger",
            "clothes hanger",
            "rack",
            "clothing rack"
        ]
    }

    private var bedTerms: [String] {
        [
            "bed",
            "mattress",
            "blanket",
            "sheet",
            "bedroom"
        ]
    }

    private var bagTerms: [String] {
        [
            "bag",
            "shopping bag",
            "handbag",
            "suitcase",
            "luggage",
            "duffel",
            "backpack",
            "tote"
        ]
    }

    private var tableTerms: [String] {
        [
            "table",
            "desk",
            "countertop",
            "surface",
            "flat lay",
            "flatlay"
        ]
    }

    private var floorTerms: [String] {
        [
            "floor",
            "rug",
            "carpet",
            "tile",
            "wood floor"
        ]
    }

    private var shoppingDisplayTerms: [String] {
        [
            "store",
            "shop",
            "retail",
            "display",
            "showcase",
            "product",
            "catalog",
            "boutique",
            "shelf",
            "rack"
        ]
    }

    private var rejectedTerms: [String] {
        [
            "animal",
            "dog",
            "cat",
            "bird",
            "car",
            "vehicle",
            "truck",
            "motorcycle",
            "bicycle",
            "tree",
            "plant",
            "flower",
            "landscape",
            "mountain",
            "sky",
            "water",
            "food",
            "building",
            "furniture",
            "wall",
            "empty room",
            "room",
            "chair",
            "sofa",
            "couch",
            "cabinet",
            "television",
            "computer",
            "phone"
        ]
    }
}

private struct CameraCaptureView: UIViewControllerRepresentable {
    let onImageCaptured: (UIImage, ScanSource) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.modalPresentationStyle = .fullScreen
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onImageCaptured: onImageCaptured, dismiss: dismiss)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImageCaptured: (UIImage, ScanSource) -> Void
        let dismiss: DismissAction

        init(onImageCaptured: @escaping (UIImage, ScanSource) -> Void, dismiss: DismissAction) {
            self.onImageCaptured = onImageCaptured
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage else {
                dismiss()
                return
            }

            let source: ScanSource = picker.cameraDevice == .front ? .cameraFront : .cameraBack
            dismiss()
            onImageCaptured(image, source)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}

private struct ScanMessage {
    let title: String
    let description: String
    let icon: String
    let isSuccess: Bool
}

private enum TryNextAction {
    case shop
    case similar
    case closet
    case askAI
}

private enum ScanHistoryFilter: String, CaseIterable, Identifiable {
    case all
    case favorites
    case business
    case casual
    case formal
    case travel
    case saved

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .favorites:
            return "Favorites"
        case .business:
            return "Business"
        case .casual:
            return "Casual"
        case .formal:
            return "Formal"
        case .travel:
            return "Travel"
        case .saved:
            return "Saved"
        }
    }

    func includes(_ scan: RecentOutfitScore, favoriteOutfits: String) -> Bool {
        switch self {
        case .all:
            return true
        case .saved:
            return scan.scanCount >= 1
        case .favorites:
            return scan.isFavorite(in: favoriteOutfits)
        case .business:
            return scan.occasion?.canonical == .work || scan.matchesAny(["business", "office", "work", "meeting", "professional", "polished"])
        case .casual:
            return scan.occasion?.canonical == .casualDay || scan.matchesAny(["casual", "weekend", "sneaker", "jeans", "everyday"])
        case .formal:
            let occasion = scan.occasion?.canonical
            return occasion == .weddingGuest || occasion == .businessFormal || occasion == .specialEvent || scan.matchesAny(["formal", "wedding", "suit", "church", "interview", "dress"])
        case .travel:
            return scan.occasion?.canonical == .travel || scan.matchesAny(["travel", "airport", "luggage", "trip", "vacation"])
        }
    }
}

private enum ScanSource: String {
    case cameraFront = "front_camera"
    case cameraBack = "back_camera"
    case gallery = "gallery"
}

private enum OutfitConfidenceLevel: Equatable {
    case high
    case medium
    case low

    var label: String {
        switch self {
        case .high:
            return "High"
        case .medium:
            return "Medium"
        case .low:
            return "Low"
        }
    }

    var fingerprintBucket: String {
        switch self {
        case .high:
            return "high"
        case .medium:
            return "medium"
        case .low:
            return "low"
        }
    }

    var customerGuidance: String {
        switch self {
        case .high:
            return "The outfit signal is strong."
        case .medium:
            return "The outfit is visible, but better lighting or a clearer full-body frame can improve reliability."
        case .low:
            return "We need a clearer outfit image for accurate scoring. Try better lighting, less background clutter, and the full outfit in frame."
        }
    }
}

private enum ScanValidation {
    case acceptedPerson([DetectedLabel])
    case acceptedClothing(String, [DetectedLabel])
    case acceptedClothingScene(ClothingScanScene, String, [DetectedLabel])
    case poorQuality(ImageQualityIssue)
    case rejected(String)
    case unknown

    var labels: [DetectedLabel] {
        switch self {
        case .acceptedPerson(let labels),
             .acceptedClothing(_, let labels),
             .acceptedClothingScene(_, _, let labels):
            return labels
        case .poorQuality, .rejected, .unknown:
            return []
        }
    }

    var sceneName: String {
        switch self {
        case .acceptedPerson:
            return "Person Wearing Clothes"
        case .acceptedClothing:
            return "Clothing Item"
        case .acceptedClothingScene(let scene, _, _):
            return scene.displayName
        case .poorQuality:
            return "Low Quality Photo"
        case .rejected:
            return "Unsupported Photo"
        case .unknown:
            return "Unknown Photo"
        }
    }

    var arrangementFingerprint: String {
        switch self {
        case .acceptedPerson:
            return "worn"
        case .acceptedClothing:
            return "item"
        case .acceptedClothingScene(let scene, _, _):
            return scene.rawValue
        case .poorQuality(let issue):
            return issue.rawValue
        case .rejected:
            return "rejected"
        case .unknown:
            return "unknown"
        }
    }

    var isAccepted: Bool {
        switch self {
        case .acceptedPerson, .acceptedClothing, .acceptedClothingScene:
            return true
        case .poorQuality, .rejected, .unknown:
            return false
        }
    }

    var qualityDescription: String {
        switch self {
        case .acceptedPerson:
            return "Source: local detection. Person wearing clothing detected with clear enough image quality."
        case .acceptedClothing(let label, _):
            return "Source: local detection. Clothing detected: \(label)."
        case .acceptedClothingScene(let scene, let label, _):
            return "Source: local detection. \(scene.displayName) detected with visible clothing: \(label)."
        case .poorQuality(let issue):
            return issue.message
        case .rejected(let label):
            return "Unsupported image detected: \(label)."
        case .unknown:
            return "No reliable clothing signal detected."
        }
    }

    var qualityScore: Int {
        switch self {
        case .acceptedPerson:
            return 92
        case .acceptedClothing:
            return 88
        case .acceptedClothingScene:
            return 84
        case .poorQuality:
            return 35
        case .rejected:
            return 20
        case .unknown:
            return 30
        }
    }

    var rejectionTitle: String {
        switch self {
        case .poorQuality:
            return "Please retake the photo"
        case .rejected:
            return "No outfit detected"
        case .unknown:
            return "Try a clearer outfit photo"
        case .acceptedPerson, .acceptedClothing, .acceptedClothingScene:
            return "Ready to score"
        }
    }

    var rejectionMessage: String {
        switch self {
        case .poorQuality(let issue):
            return "We need a clearer outfit image for accurate scoring. \(issue.message)"
        case .rejected:
            return "Style Match Pro could not find visible clothing. Please scan clothes on a person, hanger, bed, table, floor, mannequin, or shopping bag."
        case .unknown:
            return "We need a clearer outfit image for accurate scoring. Please include the full outfit or the clothing item clearly in frame."
        case .acceptedPerson, .acceptedClothing, .acceptedClothingScene:
            return qualityDescription
        }
    }

    var rejectionIcon: String {
        switch self {
        case .poorQuality:
            return "camera.metering.unknown"
        case .rejected:
            return "xmark.seal"
        case .unknown:
            return "camera.viewfinder"
        case .acceptedPerson, .acceptedClothing, .acceptedClothingScene:
            return "checkmark.seal"
        }
    }
}

private enum ClothingScanScene: String {
    case mannequin
    case hanger
    case bed
    case bag
    case table
    case floor
    case shoppingDisplay

    var displayName: String {
        switch self {
        case .mannequin:
            return "Mannequin"
        case .hanger:
            return "Hanger"
        case .bed:
            return "Clothes on Bed"
        case .bag:
            return "Clothes in Bag"
        case .table:
            return "Clothes on Table"
        case .floor:
            return "Clothes on Floor"
        case .shoppingDisplay:
            return "Shopping Display"
        }
    }

    var icon: String {
        switch self {
        case .mannequin:
            return "person"
        case .hanger:
            return "tshirt"
        case .bed:
            return "bed.double"
        case .bag:
            return "bag"
        case .table:
            return "tablecells"
        case .floor:
            return "square.grid.3x3"
        case .shoppingDisplay:
            return "storefront"
        }
    }
}

private struct DetectedLabel: Codable {
    let identifier: String
    let confidence: Float
}

private struct ClothingSceneMatch {
    let scene: ClothingScanScene
    let label: String
}

private struct TraditionalClothingRule {
    let garment: String
    let terms: [String]
    let styleCategory: String
    let occasionCategory: String
    let dressCode: String

    init(garment: String, terms: [String], styleCategory: String, occasionCategory: String, dressCode: String = "Formal Traditional") {
        self.garment = garment
        self.terms = terms
        self.styleCategory = styleCategory
        self.occasionCategory = occasionCategory
        self.dressCode = dressCode
    }
}

private struct TraditionalStyleMatch {
    let garment: String
    let styleCategory: String
    let occasionCategory: String
    let dressCode: String
    let confidence: Float
    let summary: String
}

private struct NoveltyClothingMatch {
    let garment: String
    let styleCategory: String
    let occasionCategory: String
    let dressCode: String
    let confidence: Float
    let occasionNote: String
    let summary: String
}

private struct ClothingPurposeMatch {
    let garment: String
    let styleCategory: String
    let occasionCategory: String
    let dressCode: String
    let confidence: Float
    let occasionNote: String
    let summary: String
}

private struct NoveltyClothingRule {
    let garment: String
    let terms: [String]
    let styleCategory: String
    let occasionCategory: String
    let dressCode: String
}

private struct StyleRanking: Identifiable, Encodable {
    let id = UUID()
    let name: String
    let confidence: Int
    let reason: String

    enum CodingKeys: String, CodingKey {
        case name
        case confidence
        case reason
    }
}

private struct StylistJSONAnalysis: Decodable {
    let detectedGarments: [String]
    let garmentColors: [String]
    let detectedStyle: String
    let styleConfidence: Int
    let fitAssessment: String
    let patterns: [String]
    let scoreReasoning: String
    let strengths: String
    let occasionMatch: String
    let weatherMatch: String
    let improvementTips: [String]
    let followUpQuestion: String

    enum CodingKeys: String, CodingKey {
        case detectedGarments = "detected_garments"
        case garmentColors = "garment_colors"
        case detectedStyle = "detected_style"
        case styleConfidence = "style_confidence"
        case fitAssessment = "fit_assessment"
        case patterns
        case scoreReasoning = "score_reasoning"
        case strengths
        case occasionMatch = "occasion_match"
        case weatherMatch = "weather_match"
        case improvementTips = "improvement_tips"
        case followUpQuestion = "follow_up_question"
    }
}

private struct StylistScoreExplanation: Decodable {
    let scoreReasoning: String
    let strengths: String
    let improvementTips: [String]

    enum CodingKeys: String, CodingKey {
        case scoreReasoning = "score_reasoning"
        case strengths
        case improvementTips = "improvement_tips"
    }
}

private struct StyleScoreResult: Encodable {
    let total: Int
    let breakdown: StyleScoreBreakdown
    let tier: String
}

private struct StyleScoreBreakdown: Encodable {
    let colorHarmony: Int
    let patternBalance: Int
    let fitQuality: Int
    let occasionMatch: Int
    let accessoryUse: Int

    var outfitSnapshot: OutfitScoreBreakdown {
        OutfitScoreBreakdown(
            colorHarmony: colorHarmony,
            patternBalance: patternBalance,
            fitQuality: fitQuality,
            occasionMatch: occasionMatch,
            accessoryUse: accessoryUse
        )
    }
}

private struct DetectedStyleAttributes: Encodable {
    let colors: [String]
    let patterns: [String]
    let fitAssessment: String
    let detectedStyle: String
    let accessories: [String]

    enum CodingKeys: String, CodingKey {
        case colors
        case patterns
        case fitAssessment = "fit_assessment"
        case detectedStyle = "detected_style"
        case accessories
    }
}

private typealias GarmentAttributes = DetectedStyleAttributes

private struct ScoreModifier: Encodable {
    let value: Int
    let isMismatch: Bool
    let reason: String
}

private enum GarmentFormality: Int {
    case veryCasual
    case casual
    case smartCasual
    case businessCasual
    case formal
}

private func formalityAdjustment(attributes: GarmentAttributes, occasion: Occasion?) -> ScoreModifier {
    guard let occasion else {
        return ScoreModifier(value: 0, isMismatch: false, reason: "No specific occasion selected.")
    }

    let formality = inferredGarmentFormality(from: attributes)
    let warning: (mismatch: Bool, reason: String)

    switch occasion {
    case .wedding, .weddingGuest:
        switch formality {
        case .veryCasual:
            warning = (true, "This reads as very casual for a wedding. Consider a dressier layer, polished shoes, or sharper accessories.")
        case .casual:
            warning = (true, "This reads as pretty casual for a wedding. Consider adding a more elevated piece.")
        case .smartCasual:
            warning = (false, "Smart casual can work for relaxed weddings, but elevated accessories may help.")
        case .businessCasual, .formal:
            warning = (false, "The outfit formality fits a wedding or dressy event.")
        }
    case .formalEvent, .businessFormal, .specialEvent:
        switch formality {
        case .veryCasual:
            warning = (true, "This reads as very casual for a formal event. A more polished outfit would fit the occasion better.")
        case .casual:
            warning = (true, "This reads as casual for a formal event. Consider dressier clothing or refined shoes.")
        case .smartCasual:
            warning = (true, "Smart casual may still be too relaxed for a formal event.")
        case .businessCasual:
            warning = (false, "Business casual is close, but a formal event may need sharper finishing.")
        case .formal:
            warning = (false, "The outfit formality fits a formal event.")
        }
    case .work:
        switch formality {
        case .veryCasual:
            warning = (true, "This reads as very casual for work. A cleaner top, chinos, or polished shoes would make it more work-ready.")
        case .casual:
            warning = (true, "This reads as casual for work. Add one polished piece if your workplace expects business casual.")
        case .smartCasual:
            warning = (false, "Smart casual is usually appropriate for many workplaces.")
        case .businessCasual, .formal:
            warning = (false, "The outfit formality fits a work setting.")
        }
    case .dateNight:
        switch formality {
        case .veryCasual:
            warning = (true, "This reads very casual for date night. One elevated piece could make it feel more intentional.")
        case .casual:
            warning = (false, "Casual can work for relaxed date plans.")
        case .smartCasual, .businessCasual, .formal:
            warning = (false, "The outfit has enough polish for date night.")
        }
    case .travel:
        switch formality {
        case .veryCasual, .casual:
            warning = (false, "Casual comfort fits travel well.")
        case .smartCasual, .businessCasual:
            warning = (false, "The outfit can work for travel if it remains comfortable.")
        case .formal:
            warning = (false, "Formal clothing may be less comfortable for travel.")
        }
    case .casual, .casualDay, .party:
        switch formality {
        case .veryCasual, .casual:
            warning = (false, "The outfit formality fits a casual setting.")
        case .smartCasual, .businessCasual, .formal:
            warning = (false, "The outfit is dressier than required, but still wearable casually.")
        }
    case .gym, .loungewear, .general, .other:
        warning = (false, "No special formality warning for this occasion.")
    }

    return ScoreModifier(
        value: 0,
        isMismatch: warning.mismatch,
        reason: warning.reason
    )
}

private func inferredGarmentFormality(from attributes: GarmentAttributes) -> GarmentFormality {
    let evidence = (
        [attributes.detectedStyle, attributes.fitAssessment] +
        attributes.patterns +
        attributes.accessories
    )
    .joined(separator: " ")
    .lowercased()

    if evidence.containsAny(["black tie", "formal", "suit", "tuxedo", "gown", "ceremonial", "traditional wedding"]) {
        return .formal
    }

    if evidence.containsAny(["business casual", "office", "work", "oxford", "polo", "chino", "loafers", "cardigan", "blazer"]) {
        return .businessCasual
    }

    if evidence.containsAny(["smart casual", "elevated casual", "tailored", "button-down", "button down", "dress shoe"]) {
        return .smartCasual
    }

    if evidence.containsAny(["pajama", "sleepwear", "robe", "slipper", "onesie", "loungewear", "hoodie", "graphic", "fleece", "plush"]) {
        return .veryCasual
    }

    if evidence.containsAny(["casual", "rugged", "outdoor", "streetwear", "jeans", "denim", "sneaker", "boot", "flannel"]) {
        return .casual
    }

    return .casual
}

private struct GarmentAttributeDetection {
    let qualityIssue: ImageQualityIssue?
    let labels: [DetectedLabel]
    let hasHuman: Bool

    var canAnalyze: Bool {
        qualityIssue == nil && (!labels.isEmpty || hasHuman)
    }
}

private struct ScanRegionCandidate {
    let source: String
    let normalizedTopLeftBox: CGRect
}

private struct RegionClothingMatch {
    let label: DetectedLabel
    let labels: [DetectedLabel]
}

private struct StyleScoreContext: Encodable {
    let occasion: String
    let weather: String
    let temperature: String
    let feelsLike: String
    let humidity: String
    let rainChance: String
    let wind: String
    let uvIndex: String
    let season: String
    let timeOfDay: String
}

private struct DesignIdeaUserPreferences: Encodable {
    let favoriteColors: String
    let favoriteBrands: String
    let preferredFit: String
    let budget: String
    let sizeProfile: String
    let stylePreferences: String
    let occasions: String
    let closetInventory: String
    let userRequest: String

    enum CodingKeys: String, CodingKey {
        case favoriteColors = "favorite_colors"
        case favoriteBrands = "favorite_brands"
        case preferredFit = "preferred_fit"
        case budget
        case sizeProfile = "size_profile"
        case stylePreferences = "style_preferences"
        case occasions
        case closetInventory = "closet_inventory"
        case userRequest = "user_request"
    }
}

private struct CustomGarmentDesignIdea: Decodable {
    let designConcept: String
    let garmentType: String
    let suggestedColors: [String]
    let suggestedFabric: String
    let suggestedPattern: String
    let fitStyle: String
    let designNotes: String
    let estimatedPriceRange: String

    enum CodingKeys: String, CodingKey {
        case designConcept = "design_concept"
        case garmentType = "garment_type"
        case suggestedColors = "suggested_colors"
        case suggestedFabric = "suggested_fabric"
        case suggestedPattern = "suggested_pattern"
        case fitStyle = "fit_style"
        case designNotes = "design_notes"
        case estimatedPriceRange = "estimated_price_range"
    }
}

private struct ScannerExample: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let icon: String
    let tint: Color
}

private struct AnalysisCategoryItem: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let detail: String
}

private struct OutfitFactPayload: Encodable {
    let scanSource: String
    let normalized: Bool
    let detectedItems: [String]
    let itemConfidence: [ItemConfidence]
    let colors: [String]
    let colorDetection: GarmentColorFact
    let patterns: [String]
    let fabricsAndTextures: [String]
    let shoes: [String]
    let accessories: [String]
    let outfitCategory: String
    let styleRankings: [StyleRanking]
    let occasion: String
    let weather: String
    let weatherSource: String
    let feelsLike: String
    let rainChance: String
    let humidity: String
    let windSpeed: String
    let uvIndex: String
    let lastUpdated: String
    let environment: String
    let lighting: String
    let scanType: String
    let styleScore: Int
    let scoreBreakdown: StyleScoreBreakdown
    let scoreTier: String
    let scoreOwner: String
    let outfitFingerprint: String
    let culturalAwareness: String
    let confidence: Double
    let guardrails: [String]

    struct ItemConfidence: Encodable {
        let item: String
        let confidence: Double
    }

    struct GarmentColorFact: Encodable {
        let garmentColors: [String]
        let confidence: Int
        let notes: String

        enum CodingKeys: String, CodingKey {
            case garmentColors = "garment_colors"
            case confidence
            case notes
        }
    }
}

private struct ScanAIChatMessage: Identifiable {
    enum Role {
        case customer
        case assistant
    }

    let id: UUID
    let role: Role
    var text: String
    let createdAt: Date
    var edited: Bool
    var editedAt: Date?
    var failedPrompt: String?
    var failureReason: String?

    var isEdited: Bool {
        edited || editedAt != nil
    }

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        createdAt: Date = Date(),
        edited: Bool = false,
        editedAt: Date? = nil,
        failedPrompt: String? = nil,
        failureReason: String? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.edited = edited || editedAt != nil
        self.editedAt = editedAt
        self.failedPrompt = failedPrompt
        self.failureReason = failureReason
    }
}

private struct StoredOutfitScan: Codable {
    let score: Int
    let analysis: OutfitAnalysisResult?
    let firstScannedAt: Date
    var scanCount: Int
    let thumbnailData: Data?
    var customTitle: String?
    var occasion: Occasion?

    init(score: Int, analysis: OutfitAnalysisResult?, firstScannedAt: Date, scanCount: Int, thumbnailData: Data? = nil, customTitle: String? = nil, occasion: Occasion? = nil) {
        self.score = score
        self.analysis = analysis
        self.firstScannedAt = firstScannedAt
        self.scanCount = scanCount
        self.thumbnailData = thumbnailData
        self.customTitle = customTitle
        self.occasion = occasion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        score = try container.decode(Int.self, forKey: .score)
        analysis = try container.decodeIfPresent(OutfitAnalysisResult.self, forKey: .analysis)
        firstScannedAt = try container.decode(Date.self, forKey: .firstScannedAt)
        scanCount = try container.decodeIfPresent(Int.self, forKey: .scanCount) ?? 1
        thumbnailData = try container.decodeIfPresent(Data.self, forKey: .thumbnailData)
        customTitle = try container.decodeIfPresent(String.self, forKey: .customTitle)
        if let occasionLabel = try container.decodeIfPresent(String.self, forKey: .occasion) {
            occasion = (Occasion(rawValue: occasionLabel) ?? Occasion(label: occasionLabel))?.canonical
        } else {
            occasion = nil
        }
    }
}

private struct RecentOutfitScore: Identifiable {
    let id: String
    let score: Int
    let analysis: OutfitAnalysisResult
    let firstScannedAt: Date
    let scanCount: Int
    let thumbnailData: Data?
    let customTitle: String?
    let occasion: Occasion?

    var title: String {
        if let customTitle,
           !customTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return customTitle
        }

        if let occasionTitle {
            return occasionTitle
        }

        if let itemTitle {
            return itemTitle
        }

        if let color = primaryColor {
            return "\(color) Weekend Look"
        }

        return "Weekend Look"
    }

    var dateText: String {
        Self.formatter.string(from: firstScannedAt)
    }

    var thumbnailImage: UIImage? {
        guard let thumbnailData else {
            return nil
        }

        return UIImage(data: thumbnailData)
    }

    var scoreRatingTitle: String {
        switch score {
        case 92...100:
            return "Excellent"
        case 86...91:
            return "Strong"
        case 78...85:
            return "Good"
        case 65...77:
            return "Tune-Up"
        default:
            return "Improve"
        }
    }

    var shareText: String {
        """
        Style Match Pro Scan
        \(title)
        Score: \(score) \(scoreRatingTitle)
        Style: \(styleContextText)
        Occasion: \(occasionText ?? "Not specified")
        Date: \(dateText)
        Try this next: \(analysis.recommendations.first?.title ?? analysis.suggestions.first ?? "Improve one detail and scan again.")
        """
    }

    var occasionText: String? {
        occasion?.displayName
    }

    var styleContextText: String {
        let text = searchableText
        if text.contains("traditional wedding") || text.contains("wedding traditional") {
            return "Wedding Traditional Wear"
        }
        if text.contains("ceremonial wear") || text.contains("ceremony") || text.contains("regalia") {
            return "Ceremonial Wear"
        }
        if text.contains("festival wear") || text.contains("festival") {
            return "Festival Wear"
        }
        if text.contains("heritage wear") || text.contains("national dress") {
            return "Heritage Wear"
        }
        if text.contains("traditional wear") || text.contains("cultural wear") || text.contains("religious attire") {
            return "Traditional Wear"
        }
        if text.contains("church") {
            return "Church"
        }
        if text.contains("airport") || text.contains("travel") {
            return "Travel"
        }
        if text.contains("wedding") {
            return "Wedding"
        }
        if text.contains("date") || text.contains("dinner") {
            return "Date Night"
        }
        if text.contains("gym") || text.contains("workout") {
            return "Gym"
        }
        if text.contains("children's sleepwear") || text.contains("kids sleepwear") {
            return "Children's Sleepwear"
        }
        if text.contains("pajama") || text.contains("pyjama") || text.contains("sleepwear") || text.contains("robe") || text.contains("slipper") {
            return "Sleepwear"
        }
        if text.contains("loungewear") || text.contains("indoor wear") || text.contains("house clothes") {
            return "Loungewear"
        }
        if text.contains("business") || text.contains("office") || text.contains("work") || text.contains("meeting") || text.contains("polished") {
            return "Business Casual"
        }
        if text.contains("casual") || text.contains("sneaker") || text.contains("jeans") {
            return "Casual"
        }

        let occasion = analysis.occasionFit.trimmingCharacters(in: .whitespacesAndNewlines)
        if !occasion.isEmpty {
            return occasion
        }

        return "Category Uncertain"
    }

    func matchesAny(_ terms: [String]) -> Bool {
        let text = searchableText + " " + title.lowercased() + " " + styleContextText.lowercased()
        return terms.contains { text.contains($0) }
    }

    func isFavorite(in favoriteOutfits: String) -> Bool {
        let favorites = favoriteOutfits.lowercased()
        guard !favorites.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        if favorites.contains(title.lowercased()) {
            return true
        }

        let usefulTerms = (title + " " + styleContextText)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { term in
                term.count > 3 && !["outfit", "look", "style", "match", "scan"].contains(term)
            }

        return usefulTerms.contains { favorites.contains($0) }
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return formatter
    }()

    private var occasionTitle: String? {
        let text = searchableText
        let color = primaryColor

        if text.contains("airport") || text.contains("travel") || text.contains("luggage") {
            return "Airport Travel Outfit"
        }
        if text.contains("church") || text.contains("chapel") || text.contains("sanctuary") {
            return "Church Outfit"
        }
        if text.contains("wedding") {
            return "Wedding Outfit"
        }
        if text.contains("date") || text.contains("dinner") {
            return "Date Night"
        }
        if text.contains("winter") || text.contains("cold") || text.contains("coat") {
            return "Winter Layers"
        }
        if text.contains("summer") || text.contains("hot") || text.contains("beach") {
            return "Summer Casual"
        }
        if text.contains("children's sleepwear") || text.contains("kids sleepwear") || text.contains("pajama") || text.contains("pyjama") || text.contains("sleepwear") || text.contains("robe") || text.contains("slipper") {
            return "Cozy Sleepwear"
        }
        if text.contains("loungewear") || text.contains("indoor wear") || text.contains("house clothes") {
            return "Loungewear"
        }
        if text.contains("business") || text.contains("office") || text.contains("meeting") || text.contains("formal") {
            return [color, "Business Outfit"].compactMap { $0 }.joined(separator: " ")
        }
        if text.contains("casual") || text.contains("sneaker") || text.contains("jeans") || text.contains("t-shirt") {
            return text.contains("weekend") ? "Weekend Look" : "Summer Casual"
        }

        return nil
    }

    private var itemTitle: String? {
        let text = searchableText
        let color = primaryColor

        if text.contains("suit") {
            return [color, "Suit"].compactMap { $0 }.joined(separator: " ")
        }
        if text.contains("blazer") {
            return [color, "Blazer Look"].compactMap { $0 }.joined(separator: " ")
        }
        if text.contains("polo") {
            return [color, "Polo Outfit"].compactMap { $0 }.joined(separator: " ")
        }
        if text.contains("dress") {
            return [color, "Dress Outfit"].compactMap { $0 }.joined(separator: " ")
        }
        if text.contains("jacket") {
            return [color, "Jacket Outfit"].compactMap { $0 }.joined(separator: " ")
        }

        return nil
    }

    private var primaryColor: String? {
        let genericColors = Set(["Neutral", "Dark", "Light", "Color", "Colors"])
        return analysis.colorPalette
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).capitalized }
            .first { !$0.isEmpty && !genericColors.contains($0) }
    }

    private var searchableText: String {
        (
            analysis.outfitDescription + " " +
            analysis.detectedClothingItems.joined(separator: " ") + " " +
            analysis.environment + " " +
            analysis.occasionFit + " " +
            analysis.formality + " " +
            analysis.seasonalMatch + " " +
            analysis.summary
        ).lowercased()
    }
}

private struct SavedScanResult {
    let analysis: OutfitAnalysisResult
    let isRepeat: Bool
    let isForced: Bool
    let message: String

    func title(defaultNewTitle: String, repeatTitle: String) -> String {
        if isForced {
            return "Outfit reanalyzed"
        }

        return isRepeat ? repeatTitle : defaultNewTitle
    }
}

private enum ImageQualityIssue: String {
    case tooDark
    case tooBright
    case lowContrast
    case blurry

    var message: String {
        switch self {
        case .tooDark:
            return "The photo looks underexposed. Please retake it in brighter lighting before scoring."
        case .tooBright:
            return "The photo looks overexposed. Please retake it away from harsh direct light before scoring."
        case .lowContrast:
            return "The photo does not have enough visible detail. Please retake it with clearer lighting and contrast."
        case .blurry:
            return "The photo looks blurry. Please retake it with the clothing in focus before scoring."
        }
    }
}

private extension String {
    var normalizedForFingerprint: String {
        lowercased()
            .filter { $0.isLetter || $0.isNumber }
            .prefix(24)
            .description
    }

    func containsAny(_ terms: [String]) -> Bool {
        terms.contains { contains($0) }
    }
}

private extension Sequence where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

private extension Sequence {
    func removingDuplicates<Key: Hashable>(by key: (Element) -> Key) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert(key($0)).inserted }
    }
}

private extension OutfitAnalysisResult {
    func replacingRecommendations(_ recommendations: [ClothingRecommendation]) -> OutfitAnalysisResult {
        OutfitAnalysisResult(
            score: score,
            colorMatch: colorMatch,
            occasionFit: occasionFit,
            styleBalance: styleBalance,
            colorHarmony: colorHarmony,
            styleCoordination: styleCoordination,
            formality: formality,
            seasonalMatch: seasonalMatch,
            summary: summary,
            outfitDescription: outfitDescription,
            detectedClothingItems: detectedClothingItems,
            colorPalette: colorPalette,
            colorPaletteMaskingApplied: colorPaletteMaskingApplied,
            colorPaletteMaskTier: colorPaletteMaskTier,
            environment: environment,
            imageQuality: imageQuality,
            skinToneStyleNote: skinToneStyleNote,
            detectedItemConfidences: detectedItemConfidences,
            chatGPTStylistSections: chatGPTStylistSections,
            suggestions: suggestions,
            recommendations: recommendations
        )
    }

    func replacingChatGPTStylistSections(_ sections: [ChatGPTStylistSection]) -> OutfitAnalysisResult {
        OutfitAnalysisResult(
            score: score,
            colorMatch: colorMatch,
            occasionFit: occasionFit,
            styleBalance: styleBalance,
            colorHarmony: colorHarmony,
            styleCoordination: styleCoordination,
            formality: formality,
            seasonalMatch: seasonalMatch,
            summary: summary,
            outfitDescription: outfitDescription,
            detectedClothingItems: detectedClothingItems,
            colorPalette: colorPalette,
            colorPaletteMaskingApplied: colorPaletteMaskingApplied,
            colorPaletteMaskTier: colorPaletteMaskTier,
            environment: environment,
            imageQuality: imageQuality,
            skinToneStyleNote: skinToneStyleNote,
            detectedItemConfidences: detectedItemConfidences,
            chatGPTStylistSections: sections,
            suggestions: suggestions,
            recommendations: recommendations
        )
    }
}

private extension UIImage {
    #if DEBUG
    func debugLogScanGateMaskDiagnostics(width: Int = 80, height: Int = 100) {
        guard let cgImage else {
            print("[ScanGate] maskDiagnostics unavailable - no CGImage")
            return
        }

        debugLogForegroundSubjectMask(cgImage: cgImage, width: width, height: height)
        debugLogPersonSegmentationMask(cgImage: cgImage, width: width, height: height)
        debugLogSaliencyMask(cgImage: cgImage)
    }

    private func debugLogForegroundSubjectMask(cgImage: CGImage, width: Int, height: Int) {
        guard #available(iOS 17.0, *) else {
            print("[ScanGate] mask foregroundSubject unavailable - requires iOS 17")
            return
        }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: cgImagePropertyOrientation)

        do {
            try handler.perform([request])
            guard let observation = request.results?.first else {
                print("[ScanGate] mask foregroundSubject instances=0, coverage=0.0%, thresholdByte>96")
                return
            }

            let instances = observation.allInstances
            if instances.isEmpty {
                print("[ScanGate] mask foregroundSubject instances=0, coverage=0.0%, thresholdByte>96")
                return
            }

            let maskBuffer = try observation.generateScaledMaskForImage(
                forInstances: instances,
                from: handler
            )
            let coverage = debugMaskCoverage(maskBuffer, width: width, height: height, threshold: 96)
            print("[ScanGate] mask foregroundSubject instances=\(instances.count), coverage=\(String(format: "%.1f", coverage * 100))%, thresholdByte>96")
        } catch {
            print("[ScanGate] mask foregroundSubject error=\(error.localizedDescription), thresholdByte>96")
        }
    }

    private func debugLogPersonSegmentationMask(cgImage: CGImage, width: Int, height: Int) {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: cgImagePropertyOrientation)

        do {
            try handler.perform([request])
            guard let maskBuffer = request.results?.first?.pixelBuffer else {
                print("[ScanGate] mask personSegmentation result=none, coverage=0.0%, thresholdByte>96")
                return
            }

            let coverage = debugMaskCoverage(maskBuffer, width: width, height: height, threshold: 96)
            print("[ScanGate] mask personSegmentation result=1, coverage=\(String(format: "%.1f", coverage * 100))%, thresholdByte>96")
        } catch {
            print("[ScanGate] mask personSegmentation error=\(error.localizedDescription), thresholdByte>96")
        }
    }

    private func debugLogSaliencyMask(cgImage: CGImage) {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: cgImagePropertyOrientation)

        do {
            try handler.perform([request])
            guard let observation = request.results?.first,
                  let salientObjects = observation.salientObjects,
                  !salientObjects.isEmpty else {
                print("[ScanGate] mask saliency objects=0, unionCoverage=0.0%")
                return
            }

            let unionBox = salientObjects
                .map(\.boundingBox)
                .reduce(CGRect.null) { partial, rect in
                    partial.isNull ? rect : partial.union(rect)
                }
                .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))

            let coverage = max(0, Double(unionBox.width * unionBox.height))
            print("[ScanGate] mask saliency objects=\(salientObjects.count), unionCoverage=\(String(format: "%.1f", coverage * 100))%")
        } catch {
            print("[ScanGate] mask saliency error=\(error.localizedDescription)")
        }
    }

    private func debugMaskCoverage(_ pixelBuffer: CVPixelBuffer, width: Int, height: Int, threshold: UInt8) -> Double {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return 0
        }

        let maskWidth = CVPixelBufferGetWidth(pixelBuffer)
        let maskHeight = CVPixelBufferGetHeight(pixelBuffer)
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var included = 0
        let total = max(1, width * height)

        for y in 0..<height {
            for x in 0..<width {
                let maskX = min(maskWidth - 1, max(0, Int((Double(x) / Double(max(1, width - 1))) * Double(maskWidth - 1))))
                let maskY = min(maskHeight - 1, max(0, Int((Double(y) / Double(max(1, height - 1))) * Double(maskHeight - 1))))
                if bytes[maskY * stride + maskX] > threshold {
                    included += 1
                }
            }
        }

        return Double(included) / Double(total)
    }
    #endif

    func sleepwearVisualSignalScore() -> Int {
        let palette = garmentColorPalette().map { $0.lowercased() }
        var score = 0
        let hasPinkOrRed = palette.contains(where: { $0.contains("pink") || $0.contains("red") })
        let hasLightSleepwearColor = palette.contains(where: { ["cream", "white", "pastel"].contains($0) || $0.contains("cream") || $0.contains("white") || $0.contains("pastel") })
        if hasPinkOrRed {
            score += 2
        }
        if hasLightSleepwearColor {
            score += 1
        }
        if hasPinkOrRed && hasLightSleepwearColor {
            score += 2
        }
        score += redPinkStripeSignalScore()
        if outfitIdentitySignature().contains("soft") {
            score += 1
        }
        return score
    }

    private func redPinkStripeSignalScore() -> Int {
        let width = 18
        let height = 24
        let samples = sampledRGB(width: width, height: height)
        guard samples.count == width * height else {
            return 0
        }

        var redPinkColumns = [Bool]()
        var lightColumns = [Bool]()

        for x in 0..<width {
            var redPinkCount = 0
            var lightCount = 0

            for y in 0..<height {
                let pixel = samples[y * width + x]
                let red = Int(pixel.red)
                let green = Int(pixel.green)
                let blue = Int(pixel.blue)

                if red > 120, red > green + 18, red > blue + 8 {
                    redPinkCount += 1
                }

                let brightness = red + green + blue
                if brightness > 590, abs(red - green) < 60, abs(green - blue) < 80 {
                    lightCount += 1
                }
            }

            redPinkColumns.append(Double(redPinkCount) / Double(height) > 0.18)
            lightColumns.append(Double(lightCount) / Double(height) > 0.28)
        }

        let redPinkColumnCount = redPinkColumns.filter { $0 }.count
        let lightColumnCount = lightColumns.filter { $0 }.count
        var alternationCount = 0
        for index in 1..<width {
            let changesRedPinkState = redPinkColumns[index] != redPinkColumns[index - 1]
            let hasRedPinkColumn = redPinkColumns[index] || redPinkColumns[index - 1]
            let hasLightColumn = lightColumns[index] || lightColumns[index - 1]
            if changesRedPinkState && hasRedPinkColumn && hasLightColumn {
                alternationCount += 1
            }
        }

        if redPinkColumnCount >= 2, lightColumnCount >= 2, alternationCount >= 2 {
            return 2
        }

        if redPinkColumnCount >= 2, lightColumnCount >= 2 {
            return 1
        }

        return 0
    }

    func scanSizedImage(maxSide: CGFloat = 900) -> UIImage {
        let largestSide = max(size.width, size.height)
        guard largestSide > maxSide else {
            return self
        }

        let scale = maxSide / largestSide
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    func scanThumbnailData(maxSide: CGFloat = 180) -> Data? {
        let largestSide = max(size.width, size.height)
        let scale = largestSide > 0 ? min(1, maxSide / largestSide) : 1
        let targetSize = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let thumbnail = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }

        return thumbnail.jpegData(compressionQuality: 0.72)
    }

    func qualityIssue() -> ImageQualityIssue? {
        let samples = sampledRGB(width: 16, height: 16)
        guard !samples.isEmpty else {
            return nil
        }

        let brightnessValues = samples.map { (Double($0.red) + Double($0.green) + Double($0.blue)) / 3.0 }
        let averageBrightness = brightnessValues.reduce(0, +) / Double(brightnessValues.count)
        let minBrightness = brightnessValues.min() ?? averageBrightness
        let maxBrightness = brightnessValues.max() ?? averageBrightness
        let contrast = maxBrightness - minBrightness

        if averageBrightness < 35 {
            return .tooDark
        }

        if averageBrightness > 226 {
            return .tooBright
        }

        if contrast < 28 {
            return .lowContrast
        }

        if contrast < 38 && size.width > 600 && size.height > 600 {
            return .blurry
        }

        return nil
    }

    func normalizedLightingBucket() -> String {
        let samples = sampledRGB(width: 12, height: 12)
        guard !samples.isEmpty else {
            return "unknown"
        }

        let brightnessValues = samples.map { (Double($0.red) + Double($0.green) + Double($0.blue)) / 3.0 }
        let averageBrightness = brightnessValues.reduce(0, +) / Double(brightnessValues.count)
        let contrast = (brightnessValues.max() ?? averageBrightness) - (brightnessValues.min() ?? averageBrightness)

        if averageBrightness < 55 { return "dark" }
        if averageBrightness > 210 { return "bright" }
        if contrast < 34 { return "flat" }
        if contrast > 150 { return "high-contrast" }
        return "balanced"
    }

    func garmentColorPalette() -> [String] {
        garmentColorDetection().garmentColors
    }

    func garmentColorDetection() -> GarmentColorDetection {
        let start = CFAbsoluteTimeGetCurrent()
        let maskedSamples = maskedGarmentPaletteSamples(width: 80, height: 100)
        if maskedSamples.tier == .couldNotIsolateGarment {
            let latencyMs = Int(((CFAbsoluteTimeGetCurrent() - start) * 1000).rounded())
            #if DEBUG
            print("[StyleMatch Color Debug] maskTier=\(maskedSamples.tier.rawValue), maskingApplied=false, palette latencyMs=\(latencyMs); all tiers failed")
            #endif
            return GarmentColorDetection(
                garmentColors: [],
                confidence: 0,
                notes: "Couldn't isolate the outfit from the background. Try retaking the photo with the outfit filling more of the frame.",
                maskingApplied: false,
                maskTier: maskedSamples.tier.rawValue
            )
        }

        let extraction = GarmentColorPaletteEngine.extractPalette(from: maskedSamples.samples)
        let finalColors = extraction.palette
        let confidence = extraction.confidence
        let noteColors = finalColors.joined(separator: ", ")
        let latencyMs = Int(((CFAbsoluteTimeGetCurrent() - start) * 1000).rounded())

        #if DEBUG
        print("[StyleMatch Color Debug] maskTier=\(maskedSamples.tier.rawValue), maskingApplied=\(maskedSamples.maskingApplied), palette latencyMs=\(latencyMs); \(extraction.debug.debugDescription)")
        #endif

        let sourceNote = maskedSamples.maskingApplied
            ? "Colors came from masked garment-region pixels only"
            : "Couldn’t isolate the outfit from the background"

        return GarmentColorDetection(
            garmentColors: finalColors,
            confidence: confidence,
            notes: "\(sourceNote): \(noteColors).",
            maskingApplied: maskedSamples.maskingApplied,
            maskTier: maskedSamples.tier.rawValue
        )
    }

    private func validatedGarmentColors(_ colors: [String]) -> [String] {
        GarmentColorPaletteEngine.validatedGarmentColors(colors)
    }

    private func maskedGarmentPaletteSamples(width: Int, height: Int) -> MaskedGarmentPaletteSamples {
        guard let cgImage,
              let rgbBytes = renderedRGBBytes(width: width, height: height) else {
            return failedPaletteSamples(width: width, height: height)
        }

        let mask = GarmentRegionMasker.tieredMask(
            width: width,
            height: height,
            foregroundSubject: {
                try self.foregroundSubjectMask(cgImage: cgImage, width: width, height: height)
            },
            personSegmentation: {
                try self.personSegmentationMask(cgImage: cgImage, width: width, height: height)
            },
            saliencyCrop: {
                try self.saliencyCropMask(cgImage: cgImage, width: width, height: height)
            }
        ).eroded(radius: 1)

        return MaskedGarmentPaletteSamples(
            samples: paletteSamples(width: width, height: height, rgbBytes: rgbBytes, mask: mask),
            tier: mask.tier,
            maskingApplied: mask.maskingApplied
        )
    }

    private func foregroundSubjectMask(cgImage: CGImage, width: Int, height: Int) throws -> GarmentRegionMask? {
        guard #available(iOS 17.0, *) else {
            return nil
        }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: cgImagePropertyOrientation)
        try handler.perform([request])
        guard let observation = request.results?.first,
              !observation.allInstances.isEmpty else {
            return nil
        }

        let maskBuffer = try observation.generateScaledMaskForImage(
            forInstances: observation.allInstances,
            from: handler
        )
        return pixelBufferMask(maskBuffer, width: width, height: height, tier: .foregroundSubject, threshold: 96)
    }

    private func personSegmentationMask(cgImage: CGImage, width: Int, height: Int) throws -> GarmentRegionMask? {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: cgImagePropertyOrientation)
        try handler.perform([request])
        guard let mask = request.results?.first?.pixelBuffer else {
            return nil
        }
        return pixelBufferMask(mask, width: width, height: height, tier: .personSegmentation, threshold: 96)
    }

    private func saliencyCropMask(cgImage: CGImage, width: Int, height: Int) throws -> GarmentRegionMask? {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: cgImagePropertyOrientation)
        try handler.perform([request])
        guard let observation = request.results?.first,
              let salientObjects = observation.salientObjects,
              !salientObjects.isEmpty else {
            return nil
        }

        let unionBox = salientObjects
            .map(\.boundingBox)
            .reduce(CGRect.null) { partial, rect in
                partial.isNull ? rect : partial.union(rect)
            }
            .insetBy(dx: -0.02, dy: -0.02)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))

        guard !unionBox.isNull, unionBox.width > 0, unionBox.height > 0 else {
            return nil
        }

        var included = Array(repeating: false, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let normalizedX = Double(x) / Double(max(1, width - 1))
                let normalizedYFromTop = Double(y) / Double(max(1, height - 1))
                let visionY = 1.0 - normalizedYFromTop
                if unionBox.contains(CGPoint(x: CGFloat(normalizedX), y: CGFloat(visionY))) {
                    included[y * width + x] = true
                }
            }
        }
        return GarmentRegionMask(width: width, height: height, included: included, tier: .saliencyCrop)
    }

    private func pixelBufferMask(_ pixelBuffer: CVPixelBuffer, width: Int, height: Int, tier: GarmentMaskTier, threshold: UInt8) -> GarmentRegionMask? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        let maskWidth = CVPixelBufferGetWidth(pixelBuffer)
        let maskHeight = CVPixelBufferGetHeight(pixelBuffer)
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var included = Array(repeating: false, count: width * height)

        for y in 0..<height {
            for x in 0..<width {
                let maskX = min(maskWidth - 1, max(0, Int((Double(x) / Double(max(1, width - 1))) * Double(maskWidth - 1))))
                let maskY = min(maskHeight - 1, max(0, Int((Double(y) / Double(max(1, height - 1))) * Double(maskHeight - 1))))
                included[y * width + x] = bytes[maskY * stride + maskX] > threshold
            }
        }

        return GarmentRegionMask(width: width, height: height, included: included, tier: tier)
    }

    private func paletteSamples(width: Int, height: Int, rgbBytes: [UInt8], mask: GarmentRegionMask) -> [GarmentPalettePixel] {
        guard rgbBytes.count >= width * height * 4 else {
            return []
        }

        var samples: [GarmentPalettePixel] = []
        samples.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                let rgbIndex = (y * width + x) * 4
                let normalizedX = Double(x) / Double(max(1, width - 1))
                let normalizedY = Double(y) / Double(max(1, height - 1))
                let isIncluded = mask.contains(x: x, y: y)
                samples.append(
                    GarmentPalettePixel(
                        red: rgbBytes[rgbIndex],
                        green: rgbBytes[rgbIndex + 1],
                        blue: rgbBytes[rgbIndex + 2],
                        x: normalizedX,
                        y: normalizedY,
                        isInsidePersonMask: isIncluded,
                        isLikelySkinZone: isIncluded && likelyExposedSkinZone(x: normalizedX, y: normalizedY)
                    )
                )
            }
        }
        return samples
    }

    private func failedPaletteSamples(width: Int, height: Int) -> MaskedGarmentPaletteSamples {
        let mask = GarmentRegionMask.couldNotIsolate(width: width, height: height)
        return MaskedGarmentPaletteSamples(
            samples: [],
            tier: mask.tier,
            maskingApplied: false
        )
    }

    private var cgImagePropertyOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }

    private func renderedRGBBytes(width: Int, height: Int) -> [UInt8]? {
        guard let cgImage else {
            return nil
        }

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return bytes
    }

    private func likelyExposedSkinZone(x: Double, y: Double) -> Bool {
        let upperFaceOrNeck = y < 0.24 && x > 0.32 && x < 0.68
        let sideArmZone = y > 0.24 && y < 0.82 && (x < 0.26 || x > 0.74)
        let lowerHandZone = y > 0.58 && y < 0.92 && (x < 0.34 || x > 0.66)
        return upperFaceOrNeck || sideArmZone || lowerHandZone
    }

    private func sampledGarmentRGB(width: Int, height: Int) -> [RGBPixel] {
        let samples = garmentSamplingCrops().flatMap { crop in
            sampledRGB(in: crop, width: width, height: height)
        }
        let zoneWidth = width
        let zoneHeight = height
        let centerWeightedSamples = samples.enumerated().compactMap { index, pixel -> RGBPixel? in
            let localIndex = index % max(1, zoneWidth * zoneHeight)
            let x = localIndex % zoneWidth
            let y = localIndex / zoneWidth
            let normalizedX = Double(x) / Double(max(1, zoneWidth - 1))
            let normalizedY = Double(y) / Double(max(1, zoneHeight - 1))
            let isOuterEdge = normalizedX < 0.08 || normalizedX > 0.92 || normalizedY < 0.04 || normalizedY > 0.96
            let isFaceHeavyZone = normalizedY < 0.13 && normalizedX > 0.30 && normalizedX < 0.70
            guard !isOuterEdge && !isFaceHeavyZone else {
                return nil
            }
            return pixel
        }

        return centerWeightedSamples.isEmpty ? samples : centerWeightedSamples
    }

    private func garmentSamplingCrops() -> [CGRect] {
        [
            CGRect(x: 0.32, y: 0.20, width: 0.36, height: 0.28),
            CGRect(x: 0.33, y: 0.46, width: 0.34, height: 0.26),
            CGRect(x: 0.36, y: 0.70, width: 0.28, height: 0.12)
        ]
    }

    private func everydayGarmentColorName(for pixel: RGBPixel) -> String? {
        let red = Int(pixel.red)
        let green = Int(pixel.green)
        let blue = Int(pixel.blue)
        let maxValue = max(red, green, blue)
        let minValue = min(red, green, blue)
        let spread = maxValue - minValue
        let brightness = (red + green + blue) / 3

        if brightness < 28 { return "black" }
        if brightness < 62 && spread < 28 { return "charcoal" }
        if brightness > 222 && spread < 34 { return "white" }
        if spread < 20 {
            if brightness < 80 { return "black" }
            if brightness < 118 { return "charcoal" }
            if brightness > 190 { return "white" }
            return "gray"
        }

        if blue > red + 22 && blue > green + 12 {
            return brightness < 88 ? "navy" : "blue"
        }

        if green > red + 12 && green > blue + 8 {
            if red > 70 && blue < 105 && brightness < 150 { return "olive" }
            return "green"
        }

        if red > green + 24 && red > blue + 24 {
            if red > 165 && green > 112 && blue < 85 { return "orange" }
            if red > 165 && green > 78 && blue > 100 { return "pink" }
            if brightness < 95 && blue > 48 { return "maroon" }
            if brightness < 100 { return "burgundy" }
            return "red"
        }

        if red > green && green > blue {
            if brightness < 92 { return "brown" }
            if red > 184 && green > 152 && blue > 112 { return "beige" }
            if red > 180 && green > 150 && blue < 112 { return "khaki" }
            if red > 190 && green > 168 && blue < 105 { return "yellow" }
            if red > 142 && green > 100 && blue < 105 { return "tan" }
            return "brown"
        }

        if red > 120 && blue > 100 && green < 120 {
            return "purple"
        }

        return nil
    }

    func traditionalTextileSignalScore() -> Int {
        let samples = sampledRGB(width: 8, height: 8)
        guard samples.count > 8 else {
            return 0
        }

        let colorFamilies = samples.map { pixel -> String in
            let red = Int(pixel.red)
            let green = Int(pixel.green)
            let blue = Int(pixel.blue)
            let maxValue = max(red, green, blue)
            let minValue = min(red, green, blue)

            if maxValue < 45 { return "black" }
            if minValue > 210 { return "white" }
            if maxValue - minValue < 24 { return "neutral" }
            if red > green + 30 && red > blue + 30 { return "red" }
            if green > red + 25 && green > blue + 25 { return "green" }
            if blue > red + 25 && blue > green + 25 { return "blue" }
            if red > 155 && green > 110 && blue < 105 { return "gold" }
            if red > 125 && blue > 100 && green < 125 { return "purple" }
            return "mixed"
        }

        let uniqueColors = Set(colorFamilies).count
        let brightness = samples.map { (Int($0.red) + Int($0.green) + Int($0.blue)) / 3 }
        let contrast = (brightness.max() ?? 0) - (brightness.min() ?? 0)
        let saturatedCount = samples.filter { pixel in
            let red = Int(pixel.red)
            let green = Int(pixel.green)
            let blue = Int(pixel.blue)
            return max(red, green, blue) - min(red, green, blue) > 55
        }.count
        let saturationRatio = Double(saturatedCount) / Double(samples.count)

        var edgeChanges = 0
        for index in 1..<samples.count {
            let previous = samples[index - 1]
            let current = samples[index]
            let delta = abs(Int(previous.red) - Int(current.red))
                + abs(Int(previous.green) - Int(current.green))
                + abs(Int(previous.blue) - Int(current.blue))
            if delta > 95 {
                edgeChanges += 1
            }
        }

        var score = 0
        if uniqueColors >= 5 { score += 3 }
        if contrast > 115 { score += 2 }
        if saturationRatio > 0.34 { score += 2 }
        if edgeChanges >= 14 { score += 2 }
        if colorFamilies.contains("gold") || colorFamilies.contains("purple") || colorFamilies.contains("mixed") { score += 1 }

        return score
    }

    func skinToneStyleNote() -> String {
        let samples = sampledRGB(width: 12, height: 12)
        let skinLikePixels = samples.filter { pixel in
            let red = Int(pixel.red)
            let green = Int(pixel.green)
            let blue = Int(pixel.blue)
            let brightness = (red + green + blue) / 3

            return brightness > 55
                && brightness < 235
                && red >= green
                && green >= blue - 8
                && red - blue > 18
                && red - green < 95
        }

        guard !skinLikePixels.isEmpty else {
            return "No clear visible skin color was needed. Style Match Pro keeps skin-aware styling limited to fashion color harmony only."
        }

        let redAverage = skinLikePixels.map { Double($0.red) }.reduce(0, +) / Double(skinLikePixels.count)
        let greenAverage = skinLikePixels.map { Double($0.green) }.reduce(0, +) / Double(skinLikePixels.count)
        let blueAverage = skinLikePixels.map { Double($0.blue) }.reduce(0, +) / Double(skinLikePixels.count)
        let warmth = redAverage - blueAverage
        let undertone: String
        let recommendation: String

        if warmth > 60 && greenAverage > blueAverage + 20 {
            undertone = "warm"
            recommendation = "earth tones, cream, olive, camel, gold, and warm navy"
        } else if blueAverage + 12 > greenAverage {
            undertone = "cool"
            recommendation = "white, charcoal, black, silver, navy, blue, and jewel tones"
        } else {
            undertone = "neutral"
            recommendation = "black, white, denim, soft gray, navy, and balanced accent colors"
        }

        return "Visible skin color is used only for fashion color harmony. The app detected a \(undertone) styling direction and recommends \(recommendation). It does not identify race, ethnicity, or sensitive traits."
    }

    func colorSignature() -> String {
        let samples = sampledRGB(width: 4, height: 4)

        guard !samples.isEmpty else {
            return "no-image"
        }

        return samples.map { pixel in
            let red = pixel.red / 32
            let green = pixel.green / 32
            let blue = pixel.blue / 32
            return "\(red)\(green)\(blue)"
        }
        .joined(separator: "-")
    }

    func outfitIdentitySignature() -> String {
        let samples = sampledRGB(width: 6, height: 6)

        guard !samples.isEmpty else {
            return "no-image"
        }

        let colorBuckets = samples.map { pixel in
            let red = pixel.red / 24
            let green = pixel.green / 24
            let blue = pixel.blue / 24
            let brightness = (Int(pixel.red) + Int(pixel.green) + Int(pixel.blue)) / 48
            return "\(red)\(green)\(blue)\(brightness)"
        }

        return colorBuckets.joined(separator: ".")
    }

    func fastVisionCGImage(maxSide: CGFloat = 720) -> CGImage? {
        let largestSide = max(size.width, size.height)
        guard largestSide > maxSide else {
            return cgImage
        }

        let scale = maxSide / largestSide
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }.cgImage
    }

    private func sampledRGB(in normalizedCrop: CGRect, width: Int, height: Int) -> [RGBPixel] {
        guard let cgImage else {
            return sampledRGB(width: width, height: height)
        }

        let boundedCrop = normalizedCrop
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !boundedCrop.isNull, boundedCrop.width > 0, boundedCrop.height > 0 else {
            return sampledRGB(width: width, height: height)
        }

        let pixelRect = CGRect(
            x: CGFloat(cgImage.width) * boundedCrop.origin.x,
            y: CGFloat(cgImage.height) * boundedCrop.origin.y,
            width: CGFloat(cgImage.width) * boundedCrop.width,
            height: CGFloat(cgImage.height) * boundedCrop.height
        ).integral

        guard let croppedImage = cgImage.cropping(to: pixelRect) else {
            return sampledRGB(width: width, height: height)
        }

        let cropUIImage = UIImage(cgImage: croppedImage, scale: scale, orientation: imageOrientation)
        return cropUIImage.sampledRGB(width: width, height: height)
    }

    private func sampledRGB(width: Int, height: Int) -> [RGBPixel] {
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)
        let thumbnail = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }

        guard let cgImage = thumbnail.cgImage else {
            return []
        }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return []
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        return stride(from: 0, to: pixels.count, by: 4).map { index in
            RGBPixel(red: pixels[index], green: pixels[index + 1], blue: pixels[index + 2])
        }
    }
}

private extension Array where Element == ChatGPTStylistSection {
    func removingDuplicateStylistSections() -> [ChatGPTStylistSection] {
        var seen = Set<String>()
        return filter { section in
            seen.insert(section.title.lowercased()).inserted
        }
    }
}

private struct RGBPixel {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
}

private struct MaskedGarmentPaletteSamples {
    let samples: [GarmentPalettePixel]
    let tier: GarmentMaskTier
    let maskingApplied: Bool
}

private struct GarmentColorDetection {
    let garmentColors: [String]
    let confidence: Int
    let notes: String
    let maskingApplied: Bool
    let maskTier: String?

    static let aiPrompt = """
    You are analyzing a photo to detect clothing colors ONLY.

    STRICT RULES:
    1. Ignore all background elements: walls, doors, cabinets, furniture, floors, appliances, and any objects not worn on the body.
    2. Only analyze pixels that belong to clothing items actually worn by the person: shirt, jacket, pants, shoes, hat, accessories.
    3. If a color could plausibly come from the background instead of the garment, exclude it.
    4. Identify the PRIMARY garment colors as they would be described in everyday language, such as tan, brown, olive, navy, black, white, or gray, not photography color-theory terms.
    5. Do not guess or hallucinate a color that is not clearly visible on the clothing itself.

    Return ONLY valid JSON in this exact format:
    {
      "garment_colors": ["color1", "color2"],
      "confidence": 0-100,
      "notes": "one sentence explanation of what garments these colors came from"
    }

    Do not include any text outside the JSON object.
    """
}
