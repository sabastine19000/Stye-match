import Foundation
import SwiftUI

enum AIStyleAdvisor {
    static func profile(screen: String, extraContext: String = "") -> StyleMatchStylistProfile {
        let defaults = UserDefaults.standard
        let closetItems = decodedClosetItems(from: defaults.data(forKey: "closetItemsData") ?? Data())
        let recentScans = decodedRecentScans(from: defaults.data(forKey: "outfitScanHistoryData") ?? Data())
        let closetSummary = closetItems.isEmpty
            ? stringValue("closetInventory", fallback: "No closet items saved yet.", defaults: defaults)
            : closetItems.prefix(12).map { "\($0.color) \($0.category) size \($0.size)" }.joined(separator: ", ")
        let scanSummary = recentScans.isEmpty
            ? "No recent scans saved yet."
            : recentScans.prefix(5).map(scanContextSummary).joined(separator: "\n")

        return StyleMatchStylistProfile(
            name: "",
            favoriteColors: stringValue("favoriteColors", fallback: "", defaults: defaults),
            favoriteBrands: stringValue("favoriteBrands", fallback: "", defaults: defaults),
            preferredFit: stringValue("fitPreference", fallback: "", defaults: defaults),
            budget: stringValue("shoppingBudget", fallback: "", defaults: defaults),
            sizeProfile: stringValue("sizeProfile", fallback: "", defaults: defaults),
            stylePreferences: stringValue("stylePreferences", fallback: "", defaults: defaults),
            occasions: stringValue("occasions", fallback: "", defaults: defaults),
            weather: weatherSummary(defaults: defaults),
            weatherPreferences: weatherSummary(defaults: defaults),
            dressCode: dressCodeSummary(defaults: defaults),
            shoppingHabits: shoppingHabitsSummary(defaults: defaults),
            pastOutfitRatings: outfitRatingsSummary(from: recentScans),
            frequentlyWornOutfits: frequentlyWornOutfitsSummary(from: recentScans, defaults: defaults),
            pastPurchases: stringValue("pastPurchases", fallback: "", defaults: defaults),
            favoriteOutfits: stringValue("favoriteOutfits", fallback: "", defaults: defaults),
            closetInventory: closetSummary,
            appContextSharingEnabled: boolValue("shareAppContextWithChatGPT", fallback: true, defaults: defaults),
            appContext: """
            Current Style Match Pro screen: \(screen).
            Recent outfit scans: \(scanSummary)
            Closet count: \(closetItems.count)
            \(extraContext)
            """
        )
    }

    static func ask(
        screen: String,
        messages: [AIChatMessage] = [],
        prompt: String,
        extraContext: String = ""
    ) async throws -> String {
        guard let session = StyleMatchAccountSessionStore.load(), session.expiresAt > Date() else {
            throw AIStyleAdvisorError.missingAPIKey
        }

        let savedModel = UserDefaults.standard.string(forKey: "openAIModel") ?? "gpt-4o-mini"
        let model = savedModel == "gpt-5.5" ? "gpt-4o-mini" : savedModel
        let client = OpenAIStylistClient(apiKey: "", model: model)
        return try await client.askStylist(
            profile: profile(screen: screen, extraContext: extraContext),
            messages: messages,
            question: prompt
        )
    }

    private static func stringValue(_ key: String, fallback: String, defaults: UserDefaults) -> String {
        let value = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? fallback : value
    }

    private static func boolValue(_ key: String, fallback: Bool, defaults: UserDefaults) -> Bool {
        guard defaults.object(forKey: key) != nil else {
            return fallback
        }

        return defaults.bool(forKey: key)
    }

    private static func weatherSummary(defaults: UserDefaults) -> String {
        let city = stringValue("weatherCity", fallback: "", defaults: defaults)
        let weather = stringValue("weather", fallback: "", defaults: defaults)
        let condition = stringValue("weatherCondition", fallback: "", defaults: defaults)
        let parts = [condition, weather, city].filter { !$0.isEmpty }
        return parts.isEmpty ? "No weather saved" : parts.joined(separator: ", ")
    }

    private static func dressCodeSummary(defaults: UserDefaults) -> String {
        [
            stringValue("plannedOccasion", fallback: "", defaults: defaults),
            stringValue("dressCode", fallback: "", defaults: defaults),
            stringValue("occasionFormality", fallback: "", defaults: defaults)
        ]
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
    }

    private static func shoppingHabitsSummary(defaults: UserDefaults) -> String {
        var parts: [String] = []
        let purchases = stringValue("pastPurchases", fallback: "", defaults: defaults)
        let brands = stringValue("favoriteBrands", fallback: "", defaults: defaults)
        let budget = stringValue("shoppingBudget", fallback: "", defaults: defaults)
        if !budget.isEmpty {
            parts.append("Budget \(budget)")
        }
        if !brands.isEmpty {
            parts.append("favorite brands \(brands)")
        }
        if !purchases.isEmpty {
            parts.append("past purchases \(purchases)")
        }

        return parts.joined(separator: "; ")
    }

    private static func outfitRatingsSummary(from scans: [AIAdvisorStoredScan]) -> String {
        guard !scans.isEmpty else {
            return "No saved outfit ratings yet."
        }

        let average = scans.map(\.score).reduce(0, +) / scans.count
        let best = scans.map(\.score).max() ?? average
        return "\(average)/100 average, \(best)/100 best, \(scans.count) saved scan\(scans.count == 1 ? "" : "s")."
    }

    private static func frequentlyWornOutfitsSummary(from scans: [AIAdvisorStoredScan], defaults: UserDefaults) -> String {
        if let repeated = scans.filter({ $0.scanCount > 1 }).first {
            let items = repeated.analysis?.safeDetectedClothingItems.prefix(3).joined(separator: ", ") ?? "saved outfit"
            return "\(items), scanned \(repeated.scanCount) times."
        }

        return stringValue("favoriteOutfits", fallback: "", defaults: defaults)
    }

    private static func decodedClosetItems(from data: Data) -> [ClosetItem] {
        guard !data.isEmpty,
              let items = try? JSONDecoder().decode([ClosetItem].self, from: data) else {
            return []
        }

        return items
    }

    private static func decodedRecentScans(from data: Data) -> [AIAdvisorStoredScan] {
        guard !data.isEmpty,
              let scans = try? JSONDecoder().decode([String: AIAdvisorStoredScan].self, from: data) else {
            return []
        }

        return scans.values.sorted { $0.firstScannedAt > $1.firstScannedAt }
    }

    private static func scanContextSummary(_ scan: AIAdvisorStoredScan) -> String {
        guard let analysis = scan.analysis else {
            return "- Saved scan: \(scan.score)/100, analysis details unavailable."
        }

        let confidences = analysis.detectedItemConfidences.isEmpty
            ? "No item confidence details saved."
            : analysis.detectedItemConfidences.prefix(6).compactMap { item in
                GarmentLabelMapper.humanReadableTerm(for: item.item).map { "\($0) \(item.confidence)%" }
            }.joined(separator: ", ")

        return """
        - Saved scan: \(scan.score)/100.
          Outfit: \(analysis.outfitDescription)
          Detected clothing: \(analysis.safeDetectedClothingItems.joined(separator: ", "))
          Colors: \(analysis.colorPalette.joined(separator: ", "))
          Occasion/Formality: \(analysis.occasionFit); \(analysis.formality)
          Environment: \(analysis.environment)
          Lighting/Image quality: \(analysis.imageQuality)
          Style notes: \(analysis.summary)
          Confidence: \(confidences)
        """
    }
}

enum AIStyleAdvisorError: LocalizedError {
    case missingAPIKey

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            if StyleMatchBuildSettings.releaseChannel == .customerPublic {
                return "AI account sign-in is not fully connected yet. Choose an AI service in AI Stylist, or use the built-in style guidance for now."
            }
            return "Choose ChatGPT in AI Stylist to make live style advice active."
        }
    }
}

struct AIStyleInsightCard: View {
    let tab: AppTab
    let screen: String
    let title: String
    let prompt: String
    let fallbackAdvice: String
    var extraContext = ""

    @State private var advice: String?
    @State private var isLoading = false
    @State private var statusText: String?
    @State private var isShowingChat = false
    @State private var isSendingMessage = false
    @State private var chatInput = ""
    @State private var messages: [AIInsightChatMessage] = []
    @AppStorage("aiInsightConversationData") private var aiInsightConversationData = Data()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: "sparkles")
                .font(.headline)

            Text(advice ?? fallbackAdvice)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(4)

            if let statusText {
                Label(statusText, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                openStylistChat()
            } label: {
                Label("Chat with Stylist", systemImage: "bubble.left.and.bubble.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isLoading)
        }
        .padding()
        .appCard(tab)
        .sheet(isPresented: $isShowingChat) {
            stylistChatSheet
        }
    }

    private var stylistChatSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if messages.isEmpty {
                                chatWelcomeCard
                            }

                            ForEach(messages) { message in
                                chatBubble(message)
                                    .id(message.id)
                            }

                            if isSendingMessage {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Stylist is thinking...")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 4)
                                .id("stylist-thinking")
                            }
                        }
                        .padding()
                    }
                    .styleMatchOnChange(of: messages.count) { _ in
                        guard let id = messages.last?.id else { return }
                        withAnimation(.easeInOut(duration: 0.22)) {
                            proxy.scrollTo(id, anchor: .bottom)
                        }
                    }
                }

                Divider()

                VStack(spacing: 10) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(starterPrompts, id: \.self) { starter in
                                Button(starter) {
                                    sendChatMessage(starter)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(isSendingMessage)
                            }
                        }
                        .padding(.horizontal)
                    }

                    HStack(spacing: 10) {
                        TextField("Ask your stylist...", text: $chatInput, axis: .vertical)
                            .lineLimit(1...4)
                            .textFieldStyle(.roundedBorder)

                        Button {
                            sendChatMessage(chatInput)
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 34))
                                .frame(width: 44, height: 44)
                        }
                        .disabled(isSendingMessage || chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Send stylist message")
                        .accessibilityHint("Sends your question to the stylist")
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                }
                .padding(.top, 10)
                .background(.ultraThinMaterial)
            }
            .appScreenBackground(tab)
            .navigationTitle("AI Stylist Chat")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") {
                        messages.removeAll()
                        saveMessages()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        isShowingChat = false
                    }
                }
            }
        }
    }

    private var chatWelcomeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("StyleMatch Pro AI Stylist", systemImage: "sparkles")
                .font(.title2)
                .fontWeight(.bold)

            Text("Ask questions like a real client: what to wear, what matches your closet, how to improve a score, what to buy, or how to dress for an event.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            Text(advice ?? fallbackAdvice)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(5)
        }
        .padding()
        .appCard(tab)
    }

    private func chatBubble(_ message: AIInsightChatMessage) -> some View {
        HStack {
            if message.role == .client {
                Spacer(minLength: 42)
            }

            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(message.role == .client ? .white : .primary)
                .padding(12)
                .background(message.role == .client ? tab.palette.accent : Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))

            if message.role == .stylist {
                Spacer(minLength: 42)
            }
        }
    }

    private var starterPrompts: [String] {
        [
            "Read my latest style score.",
            "What should I wear today?",
            "Build from my closet.",
            "What am I missing?",
            "Improve this score.",
            "What shoes match?",
            "Dress me for work."
        ]
    }

    private func openStylistChat() {
        loadMessages()
        if messages.isEmpty {
            messages.append(
                AIInsightChatMessage(
                    role: .stylist,
                    text: "Hi, I’m your StyleMatch Pro AI Stylist. Ask me what to wear, what matches your closet, what to buy next, or how to improve your style score."
                )
            )
            saveMessages()
        }
        isShowingChat = true
    }

    private func sendChatMessage(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let displayedHistory = messages.map { message in
            AIInsightConversationEntry(
                role: message.role == .client ? .user : .assistant,
                content: message.text
            )
        }

        let structuredRequest: AIInsightStructuredRequest
        do {
            structuredRequest = try AIInsightStructuredHistoryBuilder.build(
                displayedMessages: displayedHistory,
                latestPrompt: text
            )
        } catch {
            #if DEBUG
            print("[AI Insight Chat] \(error.localizedDescription)")
            #endif
            return
        }

        chatInput = ""
        messages.append(AIInsightChatMessage(role: .client, text: text))
        isSendingMessage = true
        statusText = "ChatGPT is writing your styling answer."
        saveMessages()

        Task {
            do {
                let response = try await liveStylistReply(structuredRequest)
                await MainActor.run {
                    if !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        messages.append(AIInsightChatMessage(role: .stylist, text: response))
                    }
                    statusText = "ChatGPT personalized this for you."
                    isSendingMessage = false
                    saveMessages()
            }
        } catch {
            #if DEBUG
            print("[AI Insight Chat] \(error.localizedDescription)")
            #endif
            await MainActor.run {
                messages.append(
                    AIInsightChatMessage(
                            role: .stylist,
                            text: "AI Stylist is having trouble connecting right now. Please try again."
                        )
                    )
                    statusText = nil
                    isSendingMessage = false
                    saveMessages()
                }
            }
        }
    }

    private var chatContext: String {
        return """
        Current card context: \(title)
        Current feature prompt: \(prompt)
        Extra app context: \(extraContext)
        """
    }

    private func liveStylistReply(_ request: AIInsightStructuredRequest) async throws -> String {
        let history = request.history.map { entry in
            AIChatMessage(
                role: entry.role == .user ? .customer : .assistant,
                text: entry.content
            )
        }
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await AIStyleAdvisor.ask(
                    screen: screen,
                    messages: history,
                    prompt: request.latestPrompt,
                    extraContext: chatContext
                )
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 20_000_000_000)
                throw AIInsightChatTimeout()
            }

            guard let result = try await group.next() else {
                throw AIInsightChatTimeout()
            }
            group.cancelAll()
            return result
        }
    }

    private func loadMessages() {
        guard !aiInsightConversationData.isEmpty,
              let decoded = try? JSONDecoder().decode([AIInsightChatMessage].self, from: aiInsightConversationData) else {
            return
        }
        messages = decoded.filter { !isLegacyPresetStylistMessage($0) }
        if messages.count != decoded.count {
            saveMessages()
        }
    }

    private func saveMessages() {
        guard let data = try? JSONEncoder().encode(Array(messages.suffix(80))) else { return }
        aiInsightConversationData = data
    }

    private func isLegacyPresetStylistMessage(_ message: AIInsightChatMessage) -> Bool {
        guard message.role == .stylist else { return false }
        return message.text.contains("I’d build from your strongest base")
            || message.text.contains("Instant stylist guidance is active")
            || message.text.contains("Tell me the occasion and I’ll tune it")
    }

    private func localStylistReply(to text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("shoe") {
            return "For this look, start with clean white sneakers for a relaxed score boost, or black loafers if you want it to read more polished for work or dinner."
        }
        if lower.contains("missing") || lower.contains("closet") {
            return "From your closet context, build around the white shirt first. The strongest missing anchor pieces are dark denim or navy trousers, clean shoes, and a belt."
        }
        if lower.contains("score") || lower.contains("improve") {
            return "To improve the score, keep the white shirt, sharpen the fit, add one anchor piece on the bottom, and finish with shoes that create clean contrast."
        }
        if lower.contains("work") {
            return "For work, use the white shirt with navy trousers or dark denim, black belt, and loafers. Keep accessories simple so it feels polished instead of busy."
        }
        return "I’d build from your strongest base: white shirt, navy or dark denim, black belt, and clean shoes. Tell me the occasion and I’ll tune it for work, church, dinner, travel, or casual."
    }

    private func askDesigner() {
        isLoading = true
        statusText = "Using your private profile, closet, sizes, weather, and recent scans."

        Task {
            do {
                let response = try await AIStyleAdvisor.ask(
                    screen: screen,
                    prompt: prompt,
                    extraContext: extraContext
                )
                await MainActor.run {
                    advice = response
                    statusText = "ChatGPT personalized this for you."
                    isLoading = false
                }
            } catch {
                #if DEBUG
                print("[AI Designer] \(error.localizedDescription)")
                #endif
                await MainActor.run {
                    advice = fallbackAdvice
                    statusText = "AI Stylist is having trouble connecting right now. Showing saved guidance."
                    isLoading = false
                }
            }
        }
    }
}

private struct AIInsightChatMessage: Identifiable, Codable {
    enum Role: String, Codable {
        case client
        case stylist
    }

    let id: UUID
    let role: Role
    let text: String

    init(id: UUID = UUID(), role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

private struct AIInsightChatTimeout: Error {
}

private struct AIAdvisorStoredScan: Decodable {
    let score: Int
    let analysis: OutfitAnalysisResult?
    let firstScannedAt: Date
    let scanCount: Int

    private enum CodingKeys: String, CodingKey {
        case score
        case analysis
        case firstScannedAt
        case scanCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        score = try container.decode(Int.self, forKey: .score)
        analysis = try container.decodeIfPresent(OutfitAnalysisResult.self, forKey: .analysis)
        firstScannedAt = try container.decode(Date.self, forKey: .firstScannedAt)
        scanCount = try container.decodeIfPresent(Int.self, forKey: .scanCount) ?? 1
    }
}
