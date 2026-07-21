import CoreLocation
import SwiftUI
import UIKit
import WeatherKit

struct AIAssistantsView: View {
    @Environment(\.openURL) private var openURL
    @Binding var selectedTab: AppTab
    @AppStorage("shoppingBudget") private var budget = ""
    @AppStorage("sizeProfile") private var sizeProfile = ""
    @AppStorage("shirtSize") private var shirtSize = ""
    @AppStorage("pantsSize") private var pantsSize = ""
    @AppStorage("weather") private var weather = ""
    @AppStorage("weatherCity") private var weatherCity = ""
    @AppStorage("weatherCondition") private var weatherCondition = ""
    @AppStorage("openAIModel") private var openAIModel = "gpt-4o-mini"
    @AppStorage("fitPreference") private var fitPreference = ""
    @AppStorage("profileName") private var name = ""
    @AppStorage("favoriteColors") private var favoriteColors = ""
    @AppStorage("favoriteBrands") private var favoriteBrands = ""
    @AppStorage("stylePreferences") private var stylePreferences = ""
    @AppStorage("occasions") private var occasions = ""
    @AppStorage("plannedOccasion") private var plannedOccasion = ""
    @AppStorage("dressCode") private var dressCode = ""
    @AppStorage("occasionFormality") private var occasionFormality = ""
    @AppStorage("pastPurchases") private var pastPurchases = ""
    @AppStorage("fashionJournalCompliments") private var fashionJournalCompliments = ""
    @AppStorage("favoriteOutfits") private var favoriteOutfits = ""
    @AppStorage("closetInventory") private var closetInventory = ""
    @AppStorage("closetItemsData") private var closetItemsData = Data()
    @AppStorage("outfitScanHistoryData") private var outfitScanHistoryData = Data()
    @AppStorage("wishlistProductNamesData") private var wishlistProductNamesData = Data()
    @AppStorage("shareAppContextWithChatGPT") private var shareAppContextWithChatGPT = true
    @AppStorage("hasSeenAIStylistWelcome") private var hasSeenAIStylistWelcome = false
    @State private var assistantMessage: String?
    @State private var openAIKeyInput = ""
    @State private var livePrompt = ""
    @State private var liveStatus: String?
    @State private var isTestingChatGPT = false
    @State private var openAIKeyIsSaved = false
    @State private var selectedStylistFeatureTitle = "Virtual Closet"
    @State private var cachedClosetItems: [ClosetItem] = []
    @State private var cachedRecentScans: [AIContextStoredScan] = []
    @State private var activePersonalInsight: String?
    @State private var showAdvancedAISections = false
    @StateObject private var liveWeather = StyleWeatherManager()
    @State private var chatMessages: [AIChatMessage] = [
        AIChatMessage(role: .assistant, text: "Hi, I am your Style Match Pro AI stylist. Ask me what to wear, what to buy, how to match colors, or how to improve an outfit.")
    ]

    private var isDeveloperAISettingsVisible: Bool {
        StyleMatchBuildSettings.allowsLocalFounderAPIKey
    }

    private var aiWelcomeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(AppTab.ai.palette.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Welcome to Your AI Stylist!")
                        .font(.title3)
                        .fontWeight(.bold)

                    Text("I learn your wardrobe, sizes, colors, and preferences to provide increasingly personalized outfit recommendations.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                }
            }

            Text("Start by asking a question or scanning an outfit.")
                .font(.subheadline)
                .fontWeight(.semibold)

            HStack(spacing: 10) {
                Button {
                    hasSeenAIStylistWelcome = true
                    livePrompt = "What should I wear today?"
                } label: {
                    Label("Ask a Question", systemImage: "bubble.left.and.bubble.right.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(AppTab.ai.palette.accent)

                Button {
                    hasSeenAIStylistWelcome = true
                    selectedTab = .scan
                } label: {
                    Label("Scan Outfit", systemImage: "camera.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding()
        .appCard(.ai, radius: 18)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PageColorBand(
                        tab: .ai,
                        title: "AI Stylist",
                        subtitle: "Your private designer for what to wear next.",
                        icon: "sparkles"
                    )

                    if !hasSeenAIStylistWelcome {
                        aiWelcomeCard
                    }

                    aiTodayOverview
                    chatGPTAppAwarenessCard

                    if let activePersonalInsight {
                        personalInsightCard(activePersonalInsight)
                    }

                    primaryActionsGrid
                    aiCapabilitySection

                    if let assistantMessage {
                        Label(assistantMessage, systemImage: "checkmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .appCard(.ai, radius: 12)
                    }

                    moreToolsSection
                }
                .padding()
            }
            .scrollContentBackground(.hidden)
            .appScreenBackground(.ai)
            .navigationTitle("AI Stylist")
            .onAppear {
                loadOpenAIKey()
                refreshSavedContextCache()
            }
            .styleMatchOnChange(of: closetItemsData) { _ in refreshSavedContextCache() }
            .styleMatchOnChange(of: outfitScanHistoryData) { _ in refreshSavedContextCache() }
        }
    }

    private var stableAIHome: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Label("AI Stylist", systemImage: "sparkles")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Your personal stylist for outfits, closet help, shopping, and style advice.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
            .padding()
            .appCard(.ai)

            if !hasSeenAIStylistWelcome {
                aiWelcomeCard
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("What would you like to do?")
                    .font(.headline)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    stableActionCard(title: "Ask AI Stylist", subtitle: "Get outfit advice", icon: "bubble.left.and.bubble.right.fill", tint: AppTab.ai.palette.accent) {
                        assistantMessage = "Ask AI Stylist is ready."
                    }

                    stableActionCard(title: "Analyze Outfit", subtitle: "Scan a new look", icon: "camera.viewfinder", tint: AppTab.scan.palette.accent) {
                        selectedTab = .scan
                    }

                    stableActionCard(title: "Virtual Closet", subtitle: "Use saved clothes", icon: "tshirt.fill", tint: AppTab.closet.palette.accent) {
                        selectedTab = .closet
                    }

                    stableActionCard(title: "Smart Shopping", subtitle: "Find missing pieces", icon: "bag.fill", tint: AppTab.shop.palette.accent) {
                        selectedTab = .shop
                    }
                }
            }
            .padding()
            .appCard(.ai)

            if let assistantMessage {
                Label(assistantMessage, systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appCard(.ai, radius: 12)
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("AI Memory", systemImage: "brain.head.profile")
                    .font(.headline)

                Text("The full AI Memory, Fashion Journal, analytics, and assistant settings are temporarily paused while we isolate the crash.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
            .padding()
            .appCard(.ai)
        }
    }

    private func stableActionCard(title: String, subtitle: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(tint)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var aiTodayOverview: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(aiGreetingLine)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                Text("Here is what your stylist sees today.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                overviewMetric(
                    title: "AI Stylist",
                    value: "StyleMatch Pro AI\nPersonalized",
                    icon: "sparkles",
                    tint: AppTab.ai.palette.accent
                ) {
                    activePersonalInsight = "StyleMatch Pro AI uses your saved sizes, closet, weather, favorite colors, budget, and recent scans when Personal Style Memory is on."
                }

                overviewMetric(
                    title: "Style Score",
                    value: currentStyleScoreText,
                    icon: "chart.line.uptrend.xyaxis",
                    tint: AppTab.ai.palette.accent
                ) {
                    activePersonalInsight = styleScoreInsightText
                }
            }

            todaysStyleSummaryCard

            VStack(alignment: .leading, spacing: 8) {
                Label("Today's Outfit Recommendation", systemImage: "sparkles")
                    .font(.headline)

                Text(todaysOutfitRecommendation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)

                HStack(spacing: 10) {
                    Button {
                        startAIStylistAction(
                            title: "Today's Outfit",
                            prompt: "Explain today's outfit recommendation and give me one better option from my closet."
                        )
                    } label: {
                        Label("Ask Why", systemImage: "questionmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .tint(AppTab.ai.palette.accent)

                    Button {
                        selectedTab = .closet
                    } label: {
                        Label("Use Closet", systemImage: "tshirt.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding()
        .appCard(.ai)
    }

    private func overviewMetric(title: String, value: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(tint)

                Text(title)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)

                Label("Tap for insight", systemImage: "sparkle.magnifyingglass")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(tint)
            }
            .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func personalInsightCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(AppTab.ai.palette.accent)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 6) {
                Text("Stylist Insight")
                    .font(.headline)

                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }

            Spacer(minLength: 0)

            Button {
                activePersonalInsight = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss insight")
            .accessibilityHint("Closes this personal insight")
        }
        .padding()
        .appCard(.ai, radius: 14)
    }

    private var todaysStyleSummaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label("Today's Style Summary", systemImage: "sparkles")
                    .font(.headline)

                Spacer()

                Text(liveWeather.isLive ? "Live" : "Saved")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(liveWeather.isLive ? .green : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background((liveWeather.isLive ? Color.green : Color.secondary).opacity(0.12))
                    .clipShape(Capsule())
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                styleSummaryMetric(title: "Weather", value: todaysSummaryWeatherText, icon: "cloud.sun.fill", tint: .cyan) {
                    activePersonalInsight = "Weather matters because the stylist can suggest layers, shoes, and fabrics that match \(todaysSummaryWeatherText)."
                }
                styleSummaryMetric(title: "Recommended Style", value: recommendedStyleSummaryText, icon: "person.fill.checkmark", tint: AppTab.closet.palette.accent) {
                    activePersonalInsight = "Your recommended style is based on your saved occasion, dress code, closet, and favorite style preferences."
                }
                styleSummaryMetric(title: "Closet Match", value: closetMatchSummaryText, icon: "tshirt.fill", tint: AppTab.scan.palette.accent) {
                    activePersonalInsight = "Closet Match estimates how many ready looks your saved wardrobe can support before you need to shop."
                }
                styleSummaryMetric(title: "Shopping Needed", value: shoppingNeededSummaryText, icon: "bag.fill", tint: AppTab.shop.palette.accent) {
                    activePersonalInsight = shoppingNeededSummaryText == "None" ? "No urgent shopping is needed. Your closet has enough to build today's look." : "The stylist sees a possible closet gap and can help you shop only for what improves your outfits."
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTab.ai.palette.accent.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func styleSummaryMetric(title: String, value: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(tint)

                Text(title)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(value)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)

                Text("View insight")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(tint)
            }
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
            .padding(12)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var primaryActionsGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Next Action")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                primaryActionButton(
                    title: "Ask About Today's Outfit",
                    icon: "bubble.left.and.bubble.right.fill",
                    tint: AppTab.ai.palette.accent
                ) {
                    startAIStylistAction(
                        title: "Today's Outfit",
                        prompt: "Tell me what to wear today using my closet, weather, size profile, style preferences, and recent outfit scans."
                    )
                }

                primaryActionButton(
                    title: "Build an Outfit",
                    icon: "tshirt.fill",
                    tint: AppTab.closet.palette.accent
                ) {
                    startAIStylistAction(
                        title: "Build an Outfit",
                        prompt: "Build a complete outfit for me from my saved closet, size profile, budget, weather, and planned occasion."
                    )
                }

                primaryActionButton(
                    title: "Find Matching Clothes",
                    icon: "bag.fill",
                    tint: AppTab.shop.palette.accent
                ) {
                    startAIStylistAction(
                        title: "Find Matching Clothes",
                        prompt: "Find clothes, shoes, and accessories that match my closet, favorite brands, budget, and current style."
                    )
                }

                primaryActionButton(
                    title: "Analyze a New Outfit",
                    icon: "camera.viewfinder",
                    tint: AppTab.scan.palette.accent
                ) {
                    selectedTab = .scan
                }
            }
        }
    }

    private var advancedAIToggle: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("More AI Tools", systemImage: "ellipsis.circle.fill")
                .font(.headline)

            Text("Open memory, planning, analytics, journal, and assistant settings when you need deeper help.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showAdvancedAISections.toggle()
                }
            } label: {
                Label(showAdvancedAISections ? "Hide More Tools" : "Open More Tools", systemImage: showAdvancedAISections ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(AppTab.ai.palette.accent)
        }
        .padding()
        .appCard(.ai)
    }

    private func primaryActionButton(title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(tint)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
            .padding(14)
            .background(Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(tint.opacity(0.25), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var aiCapabilitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Your AI Can Help With", systemImage: "sparkles")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(aiCapabilityItems, id: \.self) { item in
                    aiCapabilityRow(item)
                }
            }
        }
        .padding()
        .appCard(.ai)
    }

    private var aiCapabilityItems: [String] {
        [
            "Outfit Recommendations",
            "Closet Organization",
            "Shopping Advice",
            "Travel Packing",
            "Wedding Outfits",
            "Interview Clothing",
            "Seasonal Styling",
            "Color Matching"
        ]
    }

    private func aiCapabilityRow(_ title: String) -> some View {
        Button {
            startAIStylistAction(
                title: title,
                prompt: "Help me with \(title.lowercased()) using my closet, scans, sizes, budget, weather, and style preferences."
            )
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTab.ai.palette.accent)

                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .padding(.horizontal, 10)
            .background(AppTab.ai.palette.accent.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var stylistHub: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("More Tools", systemImage: "ellipsis.circle")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 12)], spacing: 12) {
                ForEach(moreToolFeatures) { feature in
                    Button {
                        selectStylistFeature(feature)
                    } label: {
                        stylistFeatureCard(feature)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .appCard(.ai)
    }

    private var moreToolsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            liveChatGPTPanel
            aiStyleMemoryPanel
            stylistHub
            selectedStylistFeaturePanel
            customerAIServiceAccessPanel
        }
    }

    private var chatGPTAppAwarenessCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "eye.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(AppTab.ai.palette.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text("StyleMatch Pro AI Awareness")
                        .font(.title3)
                        .fontWeight(.bold)

                    Text("Let StyleMatch Pro AI use your StyleMatch Pro profile, closet, saved scores, sizes, weather, budget, and shopping memory.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                }
            }

            Toggle(isOn: $shareAppContextWithChatGPT) {
                Text(shareAppContextWithChatGPT ? "App Awareness On" : "App Awareness Off")
                    .font(.headline)
            }
            .tint(AppTab.ai.palette.accent)

            appContextPreview

            HStack(spacing: 10) {
                Button {
                    livePrompt = "What do you know about my Style Match Pro profile, closet, sizes, weather, budget, and scan history?"
                    assistantMessage = "StyleMatch Pro AI awareness question is ready."
                } label: {
                    Label("Test Awareness", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(AppTab.ai.palette.accent)

                Button {
                    livePrompt = "Build today's outfit using my Style Match Pro closet, sizes, weather, favorite colors, favorite brands, and recent scan scores."
                    assistantMessage = "Today's outfit prompt is ready."
                } label: {
                    Label("Build Outfit", systemImage: "tshirt.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding()
        .appCard(.ai)
    }

    private var aiStyleMemoryPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "brain.head.profile")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(AppTab.ai.palette.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Style Memory")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Style Match Pro remembers your style privately so the AI can improve recommendations over time.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Memory strength")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(styleMemoryStrength)%")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(AppTab.ai.palette.accent)
                }

                ProgressView(value: Double(styleMemoryStrength), total: 100)
                    .tint(AppTab.ai.palette.accent)
            }

            aiKnowsChecklist

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(styleMemoryItems) { item in
                    styleMemoryTile(item)
                }
            }

            HStack(spacing: 10) {
                Button {
                    activePersonalInsight = styleMemorySummary
                } label: {
                    Label("Reveal Memory", systemImage: "eye.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(AppTab.ai.palette.accent)

                Button {
                    selectedTab = .profile
                } label: {
                    Label("Update Style", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

            Label("The AI uses this for fit, outfit, shopping, and weather recommendations without asking the same questions again.", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
        }
        .padding()
        .appCard(.ai)
    }

    private var aiKnowsChecklist: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("AI Knows", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(AppTab.ai.palette.accent)

            VStack(alignment: .leading, spacing: 10) {
                aiKnowsRow(title: "\(aiKnowsClosetCountText) Closet Items")
                aiKnowsRow(title: "Shirt Size: \(shirtSizeDisplayText)")
                aiKnowsRow(title: "Pants: \(pantsSizeDisplayText)")
                aiKnowsRow(title: "Favorite Colors: \(favoriteColorsDisplayText)")
                aiKnowsRow(title: "Budget: \(budgetDisplayText)")
                aiKnowsRow(title: "Preferred Style: \(preferredStyleDisplayText)")
            }
        }
        .padding(12)
        .background(AppTab.ai.palette.accent.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTab.ai.palette.accent.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func aiKnowsRow(title: String) -> some View {
        Label(title, systemImage: "checkmark.circle.fill")
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineLimit(2)
            .minimumScaleFactor(0.84)
    }

    private func styleMemoryTile(_ item: StyleMemoryItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: item.icon)
                .font(.headline)
                .foregroundStyle(item.tint)

            Text(item.title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Text(item.value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var customerAIServiceAccessPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("StyleMatch Pro AI Stylist", systemImage: "sparkles")
                .font(.headline)

            Text("StyleMatch Pro manages AI routing securely, so customers do not need third-party AI accounts, API keys, or provider setup inside the app.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(4)

            activeAssistantSummary
            connectedServicesCard

            Label("AI access is private and server-managed.", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .appCard(.ai)
    }

    private var connectedServicesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Secure AI Routing", systemImage: "checkmark.shield.fill")
                .font(.headline)
                .foregroundStyle(AppTab.ai.palette.accent)

            VStack(alignment: .leading, spacing: 6) {
                Text("Powered by StyleMatch Pro AI")
                    .font(.subheadline)
                    .fontWeight(.bold)

                Text("Provider and model choices are handled securely by StyleMatch Pro.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
        }
        .padding(12)
        .background(AppTab.ai.palette.accent.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTab.ai.palette.accent.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var activeAssistantSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(AppTab.ai.palette.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Stylist")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)

                    Text("StyleMatch Pro AI")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Ready to style today's outfit")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                }

                Spacer()
            }

            VStack(spacing: 10) {
                aiStylistActionButton("Ask About Today's Outfit", icon: "bubble.left.and.bubble.right.fill") {
                    startAIStylistAction(
                        title: "Today's Outfit",
                        prompt: "Tell me what to wear today using my closet, weather, size profile, style preferences, and recent outfit scans."
                    )
                }

                aiStylistActionButton("Build an Outfit", icon: "tshirt.fill") {
                    startAIStylistAction(
                        title: "Build an Outfit",
                        prompt: "Build a complete outfit for me from my saved closet, size profile, budget, weather, and planned occasion."
                    )
                }

                aiStylistActionButton("Find Matching Clothes", icon: "bag.fill") {
                    startAIStylistAction(
                        title: "Find Matching Clothes",
                        prompt: "Find clothes, shoes, and accessories that match my closet, favorite brands, budget, and current style."
                    )
                }

                aiStylistActionButton("Analyze a New Outfit", icon: "camera.viewfinder") {
                    selectedTab = .scan
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func aiStylistActionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.headline)

                Text(title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, 18)
            .background(Color.black)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func stylistFeatureCard(_ feature: StylistFeature) -> some View {
        let isSelected = feature.title == selectedStylistFeatureTitle

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: feature.icon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? .white : AppTab.ai.palette.accent)

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right.circle")
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? .white : .secondary)
            }

            Text(feature.title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(isSelected ? .white : .primary)
                .lineLimit(2)
                .minimumScaleFactor(0.86)

            Text(feature.detail)
                .font(.caption)
                .foregroundStyle(isSelected ? .white.opacity(0.86) : .secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .padding(12)
        .background(isSelected ? AppTab.ai.palette.accent : Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var selectedStylistFeaturePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(selectedStylistFeatureTitle, systemImage: selectedStylistFeature.icon)
                .font(.headline)

            Text(actionText(for: selectedStylistFeature))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(4)

            if selectedStylistFeatureTitle == "Outfit Planning" {
                outfitPlanningDashboard
            }

            if selectedStylistFeatureTitle == "Style Progress Reports" {
                styleProgressDashboard
            }

            if selectedStylistFeatureTitle == "Fashion Analytics" {
                fashionAnalyticsDashboard
            }

            if selectedStylistFeatureTitle == "Fashion Journal" {
                fashionJournalDashboard
            }

            if selectedStylistFeatureTitle == "Virtual Closet" {
                virtualClosetFeatureCard
            }

            HStack(spacing: 10) {
                Button {
                    prepareAssistantPrompt(for: selectedStylistFeature)
                } label: {
                    Label("Ask AI Stylist", systemImage: "bubble.left.and.bubble.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(AppTab.ai.palette.accent)

                Button {
                    assistantMessage = quickResult(for: selectedStylistFeature)
                } label: {
                    Label("Quick View", systemImage: "bolt")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding()
        .appCard(.ai)
    }

    private var virtualClosetFeatureCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "tshirt.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(AppTab.closet.palette.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Virtual Closet")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Your wardrobe is ready for outfit building.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                virtualClosetStat(title: "Items", value: virtualClosetItemCountText, icon: "tshirt.fill")
                virtualClosetStat(title: "Favorite Outfits", value: virtualClosetFavoriteCountText, icon: "heart.fill")
                virtualClosetStat(title: "Categories", value: virtualClosetCategoryCountText, icon: "square.grid.2x2.fill")
                virtualClosetStat(title: "Last Updated", value: "Today", icon: "clock.fill")
            }

            HStack(spacing: 10) {
                Button {
                    selectedTab = .closet
                } label: {
                    Label("Open Closet", systemImage: "folder.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(AppTab.closet.palette.accent)

                Button {
                    assistantMessage = quickResult(for: selectedStylistFeature)
                } label: {
                    Label("Quick View", systemImage: "bolt.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding(12)
        .background(AppTab.closet.palette.accent.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTab.closet.palette.accent.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func virtualClosetStat(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(AppTab.closet.palette.accent)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var outfitPlanningDashboard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Personal Outfit Plan", systemImage: "calendar.badge.clock")
                    .font(.headline)

                Spacer()

                Text(weatherLocationText)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTab.ai.palette.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Text("Built from your saved closet, calendar-style occasions, weather, size profile, and style preferences.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(outfitPlanningMoments) { moment in
                    outfitPlanningCard(moment)
                }
            }

            HStack(spacing: 10) {
                Button {
                    startAIStylistAction(
                        title: "Outfit Plan",
                        prompt: "Build my best outfit plan for today, tomorrow, weekend, work, date night, travel, wedding, interview, gym, and church."
                    )
                } label: {
                    Label("Build Plan", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(AppTab.ai.palette.accent)

                Button {
                    selectedTab = .scan
                } label: {
                    Label("Scan Look", systemImage: "camera.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func outfitPlanningCard(_ moment: OutfitPlanMoment) -> some View {
        Button {
            startAIStylistAction(
                title: moment.title,
                prompt: "Build a \(moment.title.lowercased()) outfit for me. Use this recommendation as the starting point: \(moment.recommendation)"
            )
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Image(systemName: moment.icon)
                        .font(.headline)
                        .foregroundStyle(moment.tint)

                    Spacer()

                    Text(moment.when)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(moment.title)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                Text(moment.recommendation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)

                Label("Plan this", systemImage: "chevron.right.circle.fill")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(moment.tint)
            }
            .frame(maxWidth: .infinity, minHeight: 158, alignment: .topLeading)
            .padding(10)
            .background(Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(moment.tint.opacity(0.22), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var styleProgressDashboard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label("Style Progress", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)

                Spacer()

                Text("\(decodedRecentScans.count) scans")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTab.ai.palette.accent)
            }

            Text("Your style statistics update from scans, closet saves, wishlist activity, favorite brands, and shopping choices.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                progressGraphCard(
                    title: "Weekly Style Score",
                    value: "\(averageStyleScore)",
                    subtitle: "Last \(weeklyStyleValues.count) scans",
                    icon: "chart.line.uptrend.xyaxis",
                    tint: .blue,
                    values: weeklyStyleValues
                )

                progressGraphCard(
                    title: "Confidence Score",
                    value: "\(confidenceScore)",
                    subtitle: "Score + closet readiness",
                    icon: "bolt.heart.fill",
                    tint: .green,
                    values: confidenceValues
                )

                progressGraphCard(
                    title: "Color Matching",
                    value: "\(colorMatchingScore)",
                    subtitle: topColorText,
                    icon: "paintpalette.fill",
                    tint: .purple,
                    values: colorMatchingValues
                )

                progressGraphCard(
                    title: "Wardrobe Growth",
                    value: "\(decodedClosetItems.count)",
                    subtitle: "Saved closet pieces",
                    icon: "tshirt.fill",
                    tint: .teal,
                    values: wardrobeGrowthValues
                )

                progressGraphCard(
                    title: "Money Saved",
                    value: "Not tracked",
                    subtitle: "StyleMatch does not estimate spending",
                    icon: "dollarsign.circle.fill",
                    tint: .orange,
                    values: moneySavedValues
                )

                progressGraphCard(
                    title: "Shopping History",
                    value: "\(shoppingHistoryCount)",
                    subtitle: "Wishlist + shop actions",
                    icon: "bag.fill",
                    tint: .pink,
                    values: shoppingHistoryValues
                )
            }

            HStack(alignment: .top, spacing: 10) {
                progressListCard(
                    title: "Favorite Brands",
                    icon: "tag.fill",
                    rows: favoriteBrandRows,
                    fallback: "Add brands in Profile or Closet."
                )

                progressListCard(
                    title: "Most Worn Pieces",
                    icon: "star.fill",
                    rows: mostWornPieceRows,
                    fallback: "Save and scan outfits to rank pieces."
                )
            }

            HStack(spacing: 10) {
                Button {
                    startAIStylistAction(
                        title: "Style Progress",
                        prompt: "Review my style progress and tell me the next three actions to improve my average outfit score."
                    )
                } label: {
                    Label("Improve Score", systemImage: "arrow.up.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(AppTab.ai.palette.accent)

                Button {
                    activePersonalInsight = "Your progress combines saved scans, score trends, closet growth, favorite brands, and most worn pieces."
                } label: {
                    Label("What Changed?", systemImage: "chart.line.uptrend.xyaxis")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func progressGraphCard(title: String, value: String, subtitle: String, icon: String, tint: Color, values: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                Spacer()
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .lineLimit(2)
                .minimumScaleFactor(0.82)

            miniBarGraph(values, tint: tint)
                .frame(height: 42)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
        .padding(10)
        .background(Color(.systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(tint.opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func miniBarGraph(_ values: [Double], tint: Color) -> some View {
        let safeValues = values.isEmpty ? [0] : values
        let maxValue = max(safeValues.max() ?? 100, 1)

        return GeometryReader { proxy in
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(safeValues.enumerated()), id: \.offset) { _, value in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(tint.opacity(0.78))
                        .frame(height: max(7, proxy.size.height * CGFloat(value / maxValue)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    private func progressListCard(title: String, icon: String, rows: [(name: String, value: String)], fallback: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .fontWeight(.bold)
                .lineLimit(2)
                .minimumScaleFactor(0.82)

            if rows.isEmpty {
                Text(fallback)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            } else {
                ForEach(rows.prefix(5), id: \.name) { row in
                    HStack(spacing: 8) {
                        Text(row.name)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        Text(row.value)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 152, alignment: .topLeading)
        .padding(10)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var fashionAnalyticsDashboard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label("AI Insights", systemImage: "sparkles")
                    .font(.headline)

                Spacer()

                Text("\(decodedClosetItems.count) pieces")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTab.ai.palette.accent)
            }

            Text("Personal stylist observations from your colors, categories, brands, occasions, closet gaps, and shopping habits.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            VStack(spacing: 10) {
                ForEach(fashionInsightRows) { insight in
                    fashionInsightCard(insight)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                progressGraphCard(
                    title: "Color Habits",
                    value: "\(topClosetColorPercent)%",
                    subtitle: topClosetColorInsight,
                    icon: "paintpalette.fill",
                    tint: .blue,
                    values: colorHabitValues
                )

                progressGraphCard(
                    title: "Closet Balance",
                    value: "\(casualWardrobePercent)%",
                    subtitle: "Casual wardrobe",
                    icon: "square.grid.2x2.fill",
                    tint: .purple,
                    values: closetBalanceValues
                )

                progressGraphCard(
                    title: "Shoe Count",
                    value: "\(shoeCount)",
                    subtitle: "Saved shoes",
                    icon: "shoe.2.fill",
                    tint: .teal,
                    values: shoeCountValues
                )

                progressGraphCard(
                    title: "Brand Focus",
                    value: favoriteBrandValueText,
                    subtitle: favoriteBrandInsight,
                    icon: "tag.fill",
                    tint: .orange,
                    values: brandFocusValues
                )
            }

            HStack(spacing: 10) {
                Button {
                    startAIStylistAction(
                        title: "AI Insights",
                        prompt: "Explain my fashion analytics and give me three practical ways to improve my wardrobe."
                    )
                } label: {
                    Label("Explain Insights", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(AppTab.ai.palette.accent)

                Button {
                    selectedTab = .shop
                } label: {
                    Label("Fill Gaps", systemImage: "bag.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var fashionJournalDashboard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label("AI Fashion Journal", systemImage: "book.closed.fill")
                    .font(.headline)

                Spacer()

                Text("\(fashionJournalEntries.count) entries")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTab.ai.palette.accent)
            }

            Text("Review outfits worn, scores, favorite combinations, compliments, purchases, seasonal trends, and improvement over time.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                fashionJournalMetric(title: "Outfits Worn", value: "\(fashionJournalOutfitsWornCount)", icon: "figure.walk", tint: .blue)
                fashionJournalMetric(title: "Average Score", value: fashionJournalAverageScoreText, icon: "star.fill", tint: .yellow)
                fashionJournalMetric(title: "Best Score", value: fashionJournalBestScoreText, icon: "crown.fill", tint: .orange)
                fashionJournalMetric(title: "Improvement", value: fashionJournalImprovementText, icon: "chart.line.uptrend.xyaxis", tint: .green)
            }

            fashionJournalTimeline
            fashionJournalNotes
            fashionJournalTrendCard

            HStack(spacing: 10) {
                Button {
                    startAIStylistAction(
                        title: "Fashion Journal",
                        prompt: "Review my fashion journal and tell me how my style has evolved, what I should repeat, and what I should improve next."
                    )
                } label: {
                    Label("Review Journey", systemImage: "book.closed.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(AppTab.ai.palette.accent)

                Button {
                    selectedTab = .scan
                } label: {
                    Label("Add Outfit", systemImage: "camera.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func fashionJournalMetric(title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(tint)

            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.74)

            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .padding(10)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var fashionJournalTimeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Style Journey", systemImage: "clock.arrow.circlepath")
                .font(.subheadline)
                .fontWeight(.bold)

            if fashionJournalEntries.isEmpty {
                Text("Scan outfits to automatically build your journal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                    .padding(10)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                ForEach(fashionJournalEntries.prefix(5)) { entry in
                    fashionJournalEntryRow(entry)
                }
            }
        }
    }

    private func fashionJournalEntryRow(_ entry: FashionJournalEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let image = entry.thumbnailImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        AppTab.ai.palette.accent.opacity(0.14)
                        Image(systemName: entry.icon)
                            .font(.title3)
                            .foregroundStyle(AppTab.ai.palette.accent)
                    }
                }
            }
            .frame(width: 58, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.title)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .lineLimit(2)

                    Spacer()

                    Text("\(entry.score)")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(AppTab.ai.palette.accent)
                }

                Text("\(entry.dateText) • \(entry.ratingTitle)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Text(entry.combination)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var fashionJournalNotes: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Personal Notes", systemImage: "square.and.pencil")
                .font(.subheadline)
                .fontWeight(.bold)

            TextField("Compliments received, favorite reactions, or style wins", text: $fashionJournalCompliments, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)

            TextField("Shopping purchases to remember", text: $pastPurchases, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
        }
        .padding(10)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var fashionJournalTrendCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Seasonal Trends", systemImage: "leaf.fill")
                .font(.subheadline)
                .fontWeight(.bold)

            HStack(spacing: 10) {
                journalTrendPill(title: "Season", value: fashionJournalSeasonText, icon: "calendar")
                journalTrendPill(title: "Favorite Combo", value: fashionJournalFavoriteCombinationText, icon: "heart.fill")
            }

            Text(fashionJournalEvolutionText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
        }
        .padding(10)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func journalTrendPill(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(AppTab.ai.palette.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.caption)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AppTab.ai.palette.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func fashionInsightCard(_ insight: FashionInsight) -> some View {
        Button {
            activePersonalInsight = "\(insight.title) \(insight.detail)"
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: insight.icon)
                    .font(.headline)
                    .foregroundStyle(insight.tint)
                    .frame(width: 30, height: 30)
                    .background(insight.tint.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(insight.title)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(insight.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)

                    Text("Tap for stylist note")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(insight.tint)
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var stylistFeatures: [StylistFeature] {
        [
            StylistFeature(title: "Virtual Closet", icon: "tshirt", detail: "Saved wardrobe, sizes, and closet matching."),
            StylistFeature(title: "Outfit Planning", icon: "calendar.badge.clock", detail: "Plan today, tomorrow, weekends, events, and trips."),
            StylistFeature(title: "Shopping", icon: "bag", detail: "Find missing pieces around \(budget)."),
            StylistFeature(title: "Wishlist", icon: "heart", detail: "Save pieces and revisit them before buying."),
            StylistFeature(title: "Budget Tracking", icon: "dollarsign.circle", detail: "Keep recommendations inside your spend range."),
            StylistFeature(title: "Wardrobe Organization", icon: "square.grid.2x2", detail: "Group clothing by type, color, size, and occasion."),
            StylistFeature(title: "Travel Packing", icon: "suitcase", detail: "Pack outfits from your closet for trips."),
            StylistFeature(title: "Calendar Planning", icon: "calendar", detail: "Plan looks ahead for important dates."),
            StylistFeature(title: "Weather Recommendations", icon: "cloud.sun", detail: "Adjust outfits for \(weatherLocationText.lowercased())."),
            StylistFeature(title: "Retail Shopping", icon: "storefront", detail: "Shop trusted retailer options."),
            StylistFeature(title: "Order Tracking", icon: "shippingbox", detail: "Track shopping orders when retailer connection is active."),
            StylistFeature(title: "Fashion Analytics", icon: "chart.bar", detail: "AI insights on colors, brands, gaps, habits, and wardrobe balance."),
            StylistFeature(title: "Fashion Journal", icon: "book.closed", detail: "Review outfits worn, scores, favorite combinations, compliments, purchases, seasonal trends, and progress over time."),
            StylistFeature(title: "Style Progress Reports", icon: "chart.line.uptrend.xyaxis", detail: "Weekly scores, closet growth, savings, brands, and most-worn pieces."),
            StylistFeature(title: "Size Profile", icon: "ruler", detail: sizeProfileDisplayText)
        ]
    }

    private var moreToolFeatures: [StylistFeature] {
        stylistFeatures.filter { feature in
            !["Virtual Closet", "Shopping", "Retail Shopping"].contains(feature.title)
        }
    }

    private var selectedStylistFeature: StylistFeature {
        stylistFeatures.first { $0.title == selectedStylistFeatureTitle } ?? stylistFeatures[0]
    }

    private var displayFirstName: String {
        StyleMatchGreetingBuilder.firstName(from: name) ?? ""
    }

    private var timeGreeting: String {
        StyleMatchGreetingBuilder.periodGreeting()
    }

    private var aiGreetingLine: String {
        StyleMatchGreetingBuilder.greetingLine(storedName: name)
    }

    private var currentStyleScoreText: String {
        guard let score = decodedRecentScans.first?.score else {
            return "--"
        }

        return "\(score)"
    }

    private var styleScoreInsightText: String {
        guard let scan = decodedRecentScans.first else {
            return "Scan an outfit to get your first style score and improvement notes."
        }

        let rating = scoreRatingTitle(for: scan.score)
        let itemText = scan.analysis?.safeDetectedClothingItems.prefix(2).joined(separator: " and ") ?? "your saved outfit"
        let suggestion = scan.analysis?.suggestions.first ?? "Try one small improvement, then rescan to compare."
        return "Your latest outfit scored \(scan.score), which is \(rating.lowercased()). Style Match Pro noticed \(itemText). Next move: \(suggestion)"
    }

    private var todaysOutfitRecommendation: String {
        if let scan = decodedRecentScans.first,
           let recommendation = scan.analysis?.recommendations.first {
            return "\(recommendation.title). \(recommendation.reason)"
        }

        let cityText = weatherCity.trimmingCharacters(in: .whitespacesAndNewlines)
        let weatherText = cityText.isEmpty ? weatherCondition : "\(weatherCondition) in \(cityText)"
        return "Start with \(closetInventory.lowercased()). Keep the look \(occasionFormality.lowercased()) for \(plannedOccasion.lowercased()), and adjust for \(weatherText.lowercased())."
    }

    private var weeklyStyleValues: [Double] {
        let scores = decodedRecentScans.prefix(7).map { Double($0.score) }.reversed()
        let values = Array(scores)
        return values
    }

    private var averageStyleScore: Int {
        roundedAverage(weeklyStyleValues)
    }

    private var confidenceScore: Int {
        guard !weeklyStyleValues.isEmpty else { return 0 }
        return min(100, max(50, averageStyleScore + min(decodedClosetItems.count, 10)))
    }

    private var confidenceValues: [Double] {
        weeklyStyleValues.enumerated().map { index, value in
            min(100, value + Double(index + 1))
        }
    }

    private var colorMatchingValues: [Double] {
        let values = decodedRecentScans.prefix(7).compactMap { scan -> Double? in
            if let colorHarmony = scan.analysis?.colorHarmony {
                return Double(scoreNumber(from: colorHarmony))
            }
            return Double(max(50, scan.score - 3))
        }.reversed()

        let result = Array(values)
        return result
    }

    private var colorMatchingScore: Int {
        roundedAverage(colorMatchingValues)
    }

    private var wardrobeGrowthValues: [Double] {
        let count = decodedClosetItems.count
        guard count > 0 else { return [] }
        return (1...5).map { step in
            Double(max(1, (count * step) / 5))
        }
    }

    private var moneySavedEstimate: Int {
        0
    }

    private var moneySavedValues: [Double] {
        []
    }

    private var shoppingHistoryCount: Int {
        decodedWishlistProductNames.count + decodedRecentScans.count
    }

    private var shoppingHistoryValues: [Double] {
        let count = shoppingHistoryCount
        guard count > 0 else { return [] }
        return (1...5).map { Double(max(1, (count * $0) / 5)) }
    }

    private var topColorText: String {
        let topColor = rankedCounts(decodedClosetItems.map(\.color)).first?.name
        return topColor.map { "Top color: \($0)" } ?? "Palette from scans"
    }

    private var topBrandText: String {
        let topBrand = favoriteBrandRows.first?.name
        return topBrand.map { "Top brand: \($0)" } ?? "Saved brands"
    }

    private var todaysSummaryWeatherText: String {
        if let summary = liveWeather.summaryText {
            return summary
        }

        let text = weatherLocationText
            .replacingOccurrences(of: "Mild weather", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,"))

        return text.isEmpty ? "83°F" : text
    }

    private var recommendedStyleSummaryText: String {
        let plan = plannedOccasionSummary
        if plan.localizedCaseInsensitiveContains("work")
            || plan.localizedCaseInsensitiveContains("business")
            || dressCode.localizedCaseInsensitiveContains("casual") {
            return "Business Casual"
        }

        let style = stylePreferences
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).capitalized }
            .first { !$0.isEmpty }

        return style ?? "Business Casual"
    }

    private var closetMatchSummaryText: String {
        let readyOutfits = max(12, min(99, decodedClosetItems.count / 2))
        return "\(readyOutfits) Outfits Ready"
    }

    private var shoppingNeededSummaryText: String {
        if decodedWishlistProductNames.isEmpty && !winterJacketInsight.localizedCaseInsensitiveContains("lacks") {
            return "None"
        }

        if !decodedWishlistProductNames.isEmpty {
            return "\(decodedWishlistProductNames.count) Saved"
        }

        return "Jacket"
    }

    private var fashionInsightRows: [FashionInsight] {
        [
            FashionInsight(
                title: topClosetColorInsight,
                detail: "Style Match Pro notices repeated colors so your stylist can suggest better variety.",
                icon: "paintpalette.fill",
                tint: .blue
            ),
            FashionInsight(
                title: "You own \(shoeCount) pair\(shoeCount == 1 ? "" : "s") of shoes.",
                detail: shoeCount == 0 ? "Add shoes to your closet so outfits can include better pairings." : "Shoes are used to improve outfit finish, weather fit, and occasion matching.",
                icon: "shoe.2.fill",
                tint: .teal
            ),
            FashionInsight(
                title: rareGreenInsight,
                detail: "Rare colors are useful for accent pieces, but they can also reveal closet gaps.",
                icon: "leaf.fill",
                tint: .green
            ),
            FashionInsight(
                title: winterJacketInsight,
                detail: "This helps weather recommendations feel practical, especially in colder months.",
                icon: "wind.snow",
                tint: .cyan
            ),
            FashionInsight(
                title: blackShirtInsight,
                detail: "Repeating one item type too much can make outfits feel similar.",
                icon: "tshirt.fill",
                tint: .black
            ),
            FashionInsight(
                title: favoriteBrandInsight,
                detail: "Favorite brands can guide smarter shopping without making the closet feel random.",
                icon: "tag.fill",
                tint: .orange
            ),
            FashionInsight(
                title: "Your wardrobe is \(casualWardrobePercent)% casual.",
                detail: "Occasion balance helps the app know when to suggest work, formal, travel, or church pieces.",
                icon: "chart.pie.fill",
                tint: .purple
            )
        ]
    }

    private var topClosetColorInsight: String {
        guard let color = rankedCounts(decodedClosetItems.map(\.color)).first?.name else {
            return "Add closet items to reveal color habits."
        }
        return "You wear \(color.lowercased()) \(topClosetColorPercent)% of the time."
    }

    private var topClosetColorName: String {
        rankedCounts(decodedClosetItems.map(\.color)).first?.name ?? "No colors yet"
    }

    private var topClosetColorPercent: Int {
        guard let count = rankedCounts(decodedClosetItems.map(\.color)).first?.count,
              decodedClosetItems.isEmpty == false else {
            return 0
        }
        return percent(count: count, total: decodedClosetItems.count)
    }

    private var shoeCount: Int {
        decodedClosetItems.filter { $0.category == "Shoes" }.count
    }

    private var rareGreenInsight: String {
        let greenCount = decodedClosetItems.filter { $0.color.localizedCaseInsensitiveContains("green") }.count
        if greenCount == 0 {
            return "You rarely wear green."
        }

        return "Green appears in \(percent(count: greenCount, total: max(decodedClosetItems.count, 1)))% of your closet."
    }

    private var winterJacketInsight: String {
        let winterJackets = decodedClosetItems.filter { item in
            item.category == "Jacket" && (
                item.notes.localizedCaseInsensitiveContains("winter")
                || item.notes.localizedCaseInsensitiveContains("coat")
                || item.color.localizedCaseInsensitiveContains("black")
                || item.color.localizedCaseInsensitiveContains("navy")
            )
        }

        return winterJackets.isEmpty ? "Your closet lacks winter jackets." : "You have \(winterJackets.count) winter-ready jacket\(winterJackets.count == 1 ? "" : "s")."
    }

    private var blackShirtInsight: String {
        let shirts = decodedClosetItems.filter { $0.category == "Shirt" }
        let blackShirts = shirts.filter { $0.color.localizedCaseInsensitiveContains("black") }

        if blackShirts.count >= 3 || percent(count: blackShirts.count, total: max(shirts.count, 1)) >= 50 {
            return "You buy too many black shirts."
        }

        return "Black shirts are \(percent(count: blackShirts.count, total: max(shirts.count, 1)))% of your shirts."
    }

    private var favoriteBrandInsight: String {
        "Your favorite brand is \(favoriteBrandName)."
    }

    private var favoriteBrandName: String {
        favoriteBrandRows.first?.name ?? favoriteBrands.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? "Not set"
    }

    private var favoriteBrandValueText: String {
        String(favoriteBrandName.prefix(8))
    }

    private var casualWardrobePercent: Int {
        let casualWords = ["Everyday", "Casual", "Travel", "Gym", "Weekend", "Dinner"]
        let casualCount = decodedClosetItems.filter { item in
            casualWords.contains { item.occasion.localizedCaseInsensitiveContains($0) }
        }.count

        return decodedClosetItems.isEmpty ? 0 : percent(count: casualCount, total: decodedClosetItems.count)
    }

    private var colorHabitValues: [Double] {
        let rows = rankedCounts(decodedClosetItems.map(\.color)).prefix(5).map { Double($0.count) }
        return rows
    }

    private var closetBalanceValues: [Double] {
        let rows = rankedCounts(decodedClosetItems.map(\.occasion)).prefix(5).map { Double($0.count) }
        return rows
    }

    private var virtualClosetItemCountText: String {
        "\(decodedClosetItems.count)"
    }

    private var virtualClosetFavoriteCountText: String {
        let favorites = favoriteOutfits
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return "\(favorites.count)"
    }

    private var virtualClosetCategoryCountText: String {
        let categories = Set(
            decodedClosetItems
                .map(\.category)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )

        return "\(categories.count)"
    }

    private var shoeCountValues: [Double] {
        let count = shoeCount
        guard count > 0 else { return [] }
        return (1...5).map { Double(max(1, count * $0 / 5)) }
    }

    private var brandFocusValues: [Double] {
        let rows = favoriteBrandRows.prefix(5).compactMap { Double($0.value.replacingOccurrences(of: "x", with: "")) }
        return rows
    }

    private var favoriteBrandRows: [(name: String, value: String)] {
        let profileBrands = favoriteBrands
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let closetBrands = decodedClosetItems.map(\.brand).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return rankedCounts(profileBrands + closetBrands).map { ($0.name, "\($0.count)x") }
    }

    private var mostWornPieceRows: [(name: String, value: String)] {
        let itemRows = decodedClosetItems.prefix(5).map { item in
            ("\(item.color) \(item.name)", item.occasion)
        }

        if !itemRows.isEmpty {
            return itemRows
        }

        return decodedRecentScans.prefix(5).map { scan in
            ("Scan \(scan.score) \(scoreRatingTitle(for: scan.score))", "\(scan.scanCount)x")
        }
    }

    private func scoreRatingTitle(for score: Int) -> String {
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

    private var fashionJournalEntries: [FashionJournalEntry] {
        decodedRecentScans.map { scan in
            FashionJournalEntry(
                score: scan.score,
                analysis: scan.analysis,
                firstScannedAt: scan.firstScannedAt,
                scanCount: scan.scanCount,
                thumbnailData: scan.thumbnailData
            )
        }
    }

    private var fashionJournalOutfitsWornCount: Int {
        max(decodedRecentScans.reduce(0) { $0 + max(1, $1.scanCount) }, decodedRecentScans.count)
    }

    private var fashionJournalAverageScoreText: String {
        let scores = fashionJournalEntries.map(\.score)
        guard !scores.isEmpty else {
            return "--"
        }

        return "\(scores.reduce(0, +) / scores.count)"
    }

    private var fashionJournalBestScoreText: String {
        guard let best = fashionJournalEntries.map(\.score).max() else {
            return "--"
        }

        return "\(best)"
    }

    private var fashionJournalImprovementText: String {
        let chronologicalScores = fashionJournalEntries
            .sorted { $0.firstScannedAt < $1.firstScannedAt }
            .map(\.score)
        guard let first = chronologicalScores.first,
              let last = chronologicalScores.last,
              chronologicalScores.count > 1 else {
            return "New"
        }

        let change = last - first
        if change > 0 {
            return "+\(change)"
        }
        if change < 0 {
            return "\(change)"
        }
        return "Steady"
    }

    private var fashionJournalSeasonText: String {
        let month = Calendar.current.component(.month, from: Date())
        switch month {
        case 12, 1, 2:
            return "Winter"
        case 3...5:
            return "Spring"
        case 6...8:
            return "Summer"
        default:
            return "Fall"
        }
    }

    private var fashionJournalFavoriteCombinationText: String {
        if let entry = fashionJournalEntries.first {
            return entry.shortCombination
        }

        let savedFavorite = favoriteOutfits.trimmingCharacters(in: .whitespacesAndNewlines)
        return savedFavorite.isEmpty ? "Scan first" : savedFavorite
    }

    private var fashionJournalEvolutionText: String {
        let compliments = fashionJournalCompliments.trimmingCharacters(in: .whitespacesAndNewlines)
        let purchases = pastPurchases.trimmingCharacters(in: .whitespacesAndNewlines)
        let scoreText = fashionJournalAverageScoreText == "--" ? "No score trend yet" : "Average style score \(fashionJournalAverageScoreText)"
        let complimentText = compliments.isEmpty ? "Add compliments or style wins when they happen." : "Compliments: \(compliments)."
        let purchaseText = purchases.isEmpty ? "Purchases will appear here when saved." : "Purchases: \(purchases)."

        return "\(scoreText). \(complimentText) \(purchaseText)"
    }

    private var decodedWishlistProductNames: [String] {
        guard !wishlistProductNamesData.isEmpty,
              let productNames = try? JSONDecoder().decode([String].self, from: wishlistProductNamesData) else {
            return []
        }

        return productNames
    }

    private func roundedAverage(_ values: [Double]) -> Int {
        guard !values.isEmpty else {
            return 0
        }

        return Int((values.reduce(0, +) / Double(values.count)).rounded())
    }

    private func percent(count: Int, total: Int) -> Int {
        guard total > 0 else {
            return 0
        }

        return Int((Double(count) / Double(total) * 100).rounded())
    }

    private func scoreNumber(from text: String) -> Int {
        let digits = text.prefix { $0.isNumber }
        return Int(String(digits)) ?? 75
    }

    private func rankedCounts(_ values: [String]) -> [(name: String, count: Int)] {
        Dictionary(grouping: values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }, by: { $0 })
            .map { (name: $0.key, count: $0.value.count) }
            .sorted {
                if $0.count == $1.count {
                    return $0.name < $1.name
                }
                return $0.count > $1.count
            }
    }

    private var outfitPlanningMoments: [OutfitPlanMoment] {
        [
            OutfitPlanMoment(
                title: "Today's Outfit",
                when: shortDateLabel(daysFromToday: 0),
                icon: "sun.max.fill",
                tint: .orange,
                recommendation: planRecommendation(for: "today", occasion: plannedOccasionSummary, tone: occasionFormality)
            ),
            OutfitPlanMoment(
                title: "Tomorrow",
                when: shortDateLabel(daysFromToday: 1),
                icon: "calendar",
                tint: .blue,
                recommendation: planRecommendation(for: "tomorrow", occasion: nextOccasion(after: plannedOccasionSummary), tone: "Smart casual")
            ),
            OutfitPlanMoment(
                title: "Weekend",
                when: "Sat-Sun",
                icon: "sparkles",
                tint: .purple,
                recommendation: planRecommendation(for: "the weekend", occasion: hasSavedOccasion("Weekend") ? "Weekend" : "Casual", tone: "Relaxed")
            ),
            OutfitPlanMoment(
                title: "Work",
                when: calendarSignal(for: "Work"),
                icon: "briefcase.fill",
                tint: .brown,
                recommendation: planRecommendation(for: "work", occasion: "Work", tone: "Polished")
            ),
            OutfitPlanMoment(
                title: "Date Night",
                when: calendarSignal(for: "Date Night"),
                icon: "heart.fill",
                tint: .pink,
                recommendation: planRecommendation(for: "date night", occasion: "Date Night", tone: "Confident")
            ),
            OutfitPlanMoment(
                title: "Travel",
                when: calendarSignal(for: "Travel"),
                icon: "suitcase.fill",
                tint: .teal,
                recommendation: planRecommendation(for: "travel", occasion: "Travel", tone: "Comfortable")
            ),
            OutfitPlanMoment(
                title: "Wedding",
                when: calendarSignal(for: "Wedding"),
                icon: "camera.aperture",
                tint: .indigo,
                recommendation: planRecommendation(for: "a wedding", occasion: "Wedding", tone: "Formal")
            ),
            OutfitPlanMoment(
                title: "Interview",
                when: calendarSignal(for: "Interview"),
                icon: "person.text.rectangle.fill",
                tint: .cyan,
                recommendation: planRecommendation(for: "an interview", occasion: "Interview", tone: "Sharp")
            ),
            OutfitPlanMoment(
                title: "Gym",
                when: calendarSignal(for: "Gym"),
                icon: "figure.strengthtraining.traditional",
                tint: .green,
                recommendation: planRecommendation(for: "the gym", occasion: "Gym", tone: "Performance")
            ),
            OutfitPlanMoment(
                title: "Church",
                when: calendarSignal(for: "Church"),
                icon: "building.columns.fill",
                tint: .mint,
                recommendation: planRecommendation(for: "church", occasion: "Church", tone: "Respectful")
            )
        ]
    }

    private func planRecommendation(for timeFrame: String, occasion: String, tone: String) -> String {
        let weatherText = weatherPlanAdvice.lowercased()
        let closetText = compactClosetSummary.lowercased()
        let sizeText = sizeProfileInlineText
        return "For \(timeFrame), choose a \(tone.lowercased()) \(occasion.lowercased()) look using \(closetText). Adjust for \(weatherText). Fit uses \(sizeText)."
    }

    private var weatherPlanAdvice: String {
        let condition = weatherCondition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? weather : weatherCondition
        let lower = condition.lowercased()

        if lower.contains("rain") {
            return "\(condition): add covered shoes and a jacket"
        }
        if lower.contains("cold") || lower.contains("winter") {
            return "\(condition): add layers"
        }
        if lower.contains("hot") || lower.contains("humid") || lower.contains("summer") {
            return "\(condition): choose breathable pieces"
        }
        if lower.contains("wind") {
            return "\(condition): secure layers and avoid loose pieces"
        }

        return "\(condition): keep the outfit balanced"
    }

    private func shortDateLabel(daysFromToday: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: daysFromToday, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private func calendarSignal(for occasion: String) -> String {
        if plannedOccasion.localizedCaseInsensitiveContains(occasion) || hasSavedOccasion(occasion) {
            return "Planned"
        }

        return "Ready"
    }

    private func hasSavedOccasion(_ occasion: String) -> Bool {
        occasions.localizedCaseInsensitiveContains(occasion)
    }

    private func nextOccasion(after current: String) -> String {
        let savedOccasions = occasions
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return savedOccasions.first { !$0.localizedCaseInsensitiveContains(current) } ?? current
    }

    private func selectStylistFeature(_ feature: StylistFeature) {
        selectedStylistFeatureTitle = feature.title
        assistantMessage = "\(feature.title) selected."
    }

    private func prepareAssistantPrompt(for feature: StylistFeature) {
        livePrompt = prompt(for: feature)
        assistantMessage = "\(feature.title) is ready. Send the prepared message to StyleMatch Pro AI."
    }

    private func startAIStylistAction(title: String, prompt: String) {
        livePrompt = prompt
        assistantMessage = "\(title) is ready. StyleMatch Pro AI can help with this."
    }

    private func actionText(for feature: StylistFeature) -> String {
        switch feature.title {
        case "Virtual Closet":
            return "Track closet growth, favorite outfits, categories, and outfit-ready pieces in one place."
        case "Outfit Planning":
            return "Plan a complete outfit for \(plannedOccasionSummary.lowercased()) using your closet, weather, budget, and size profile."
        case "Shopping", "Retail Shopping":
            return "Find missing pieces that match your style, size profile, and budget."
        case "Wishlist":
            return "Save items you are considering before you buy, then compare what fits your closet."
        case "Budget Tracking":
            return "Keep outfit and shopping ideas inside your saved budget: \(budget)."
        case "Wardrobe Organization":
            return "Organize clothes by type, color, size, brand, and occasion."
        case "Travel Packing":
            return "Build a packing list using clothes you already saved in your closet."
        case "Calendar Planning":
            return "Plan outfits ahead for upcoming days and events."
        case "Weather Recommendations":
            return "Adjust your outfit for \(weatherLocationText.lowercased()) and keep the look practical."
        case "Order Tracking":
            return "Track shopping orders once retailer connections are active."
        case "Fashion Analytics":
            return "Review AI insights about what you wear most, what you rarely wear, closet gaps, repeated buying habits, favorite brands, and wardrobe balance."
        case "Fashion Journal":
            return "Review your style journey: outfits worn, saved scores, favorite combinations, compliments, purchases, seasonal trends, and improvement over time."
        case "Style Progress Reports":
            return "See your style statistics with graphs for weekly score, confidence, color matching, wardrobe growth, savings, shopping history, brands, and most-worn pieces."
        case "Size Profile":
            let trimmed = sizeProfile.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? "No sizes saved yet. Add sizes in Profile for better recommendations."
                : "Use saved sizes for recommendations: \(trimmed)."
        default:
            return feature.detail
        }
    }

    private func prompt(for feature: StylistFeature) -> String {
        switch feature.title {
        case "Virtual Closet":
            return "Use my virtual closet and size profile to suggest a complete outfit from what I already own."
        case "Outfit Planning":
            return "Plan outfits for today, tomorrow, weekend, work, date night, travel, wedding, interview, gym, and church using my calendar-style occasions, weather, size profile, closet, and budget."
        case "Shopping", "Retail Shopping":
            return "Recommend missing clothing pieces I should shop for based on my closet, size profile, and budget."
        case "Wishlist":
            return "Help me decide what fashion items are worth adding to my wishlist."
        case "Budget Tracking":
            return "Help me build a stylish outfit while staying inside my saved budget."
        case "Wardrobe Organization":
            return "Help me organize my wardrobe and identify what categories or colors I am missing."
        case "Travel Packing":
            return "Create a travel packing outfit plan using my closet, weather, and style preferences."
        case "Calendar Planning":
            return "Help me plan outfits for upcoming events on my calendar."
        case "Weather Recommendations":
            return "Recommend an outfit for \(weatherLocationText) using my closet, size profile, and style preferences."
        case "Order Tracking":
            return "Tell me how order tracking should work for my fashion purchases in this app."
        case "Fashion Analytics":
            return "Analyze my fashion habits like a personal stylist. Tell me what colors I wear most, what I rarely wear, closet gaps, repeated buying habits, favorite brands, and wardrobe balance."
        case "Fashion Journal":
            return "Review my AI Fashion Journal. Summarize my outfits worn, style scores, favorite combinations, compliments, shopping purchases, seasonal trends, and how my wardrobe has evolved over time."
        case "Style Progress Reports":
            return "Create a statistics-based style progress report using weekly score, confidence score, color matching, wardrobe growth, money saved, shopping history, favorite brands, and most-worn pieces."
        case "Size Profile":
            return sizeProfile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Help me set up my size profile before recommending shirt, pants, and shoe sizes."
                : "Use my saved size profile to recommend the right shirt, pants, and shoe sizes."
        default:
            return "Help me with \(feature.title.lowercased())."
        }
    }

    private func quickResult(for feature: StylistFeature) -> String {
        switch feature.title {
        case "Virtual Closet":
            return "Virtual Closet is using: \(compactClosetSummary)."
        case "Outfit Planning":
            return "Outfit Planning is ready for today, tomorrow, weekend, work, date night, travel, wedding, interview, gym, and church using \(weatherLocationText) and \(compactClosetSummary)."
        case "Budget Tracking":
            return "Current budget range: \(budget)."
        case "Weather Recommendations":
            return "Current weather context: \(weatherLocationText)."
        case "Fashion Analytics":
            return "Fashion Analytics: \(fashionInsightRows.map { $0.title }.joined(separator: " "))"
        case "Fashion Journal":
            return "Fashion Journal: \(fashionJournalOutfitsWornCount) outfits, average score \(fashionJournalAverageScoreText), best score \(fashionJournalBestScoreText), improvement \(fashionJournalImprovementText)."
        case "Style Progress Reports":
            return "Style stats: weekly score \(averageStyleScore), confidence \(confidenceScore), color matching \(colorMatchingScore), wardrobe \(decodedClosetItems.count) pieces. Spending savings are not tracked."
        case "Size Profile":
            let trimmed = sizeProfile.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? "No sizes saved yet."
                : "Saved size profile: \(trimmed)."
        default:
            return "\(feature.title) is ready. Tap Ask AI Stylist for personalized help."
        }
    }

    private var liveChatGPTPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Ask StyleMatch Pro AI Stylist", systemImage: "bubble.left.and.bubble.right")
                .font(.headline)

            Text("StyleMatch Pro AI can use your profile, closet, sizes, weather, shopping habits, and saved scan scores when app awareness is on.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(4)

            if isDeveloperAISettingsVisible {
                SecureField("Founder beta access key", text: $openAIKeyInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.password)

                Text("Model: \(openAIModel)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("Response speed", selection: $openAIModel) {
                    Text("Fast").tag("gpt-4o-mini")
                    Text("Balanced").tag("gpt-4o")
                    Text("Best").tag("gpt-4.1")
                }
                .pickerStyle(.segmented)

                HStack(spacing: 10) {
                    Button {
                        saveOpenAIKey()
                    } label: {
                        Label("Save Access", systemImage: "checkmark.seal")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button(role: .destructive) {
                        deleteOpenAIKey()
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            } else if !openAIKeyIsSaved {
                Label("StyleMatch Pro AI access is managed securely. Developer setup is hidden in public builds.", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle(isOn: $shareAppContextWithChatGPT) {
                Label("App awareness", systemImage: "eye")
            }
            .font(.subheadline)

            if shareAppContextWithChatGPT {
                appContextPreview
            }

            conversationStartersCard

            chatTranscript

            chatInputBar

            if let liveStatus {
                Text(liveStatus)
                    .font(.subheadline)
                    .foregroundStyle(liveStatus.localizedCaseInsensitiveContains("error") ? .red : .secondary)
            }

            if liveStatus?.localizedCaseInsensitiveContains("billing") == true
                || liveStatus?.localizedCaseInsensitiveContains("credits") == true
                || liveStatus?.localizedCaseInsensitiveContains("rate limit") == true {
                Label("StyleMatch Pro AI needs attention before it can answer here. Try again later.", systemImage: "creditcard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .appCard(.ai)
    }

    private var conversationStartersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Try asking", systemImage: "lightbulb.fill")
                .font(.subheadline)
                .fontWeight(.bold)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                ForEach(conversationStarters, id: \.self) { starter in
                    Button {
                        livePrompt = starter
                    } label: {
                        Text(starter)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppTab.ai.palette.accent)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(.horizontal, 10)
                            .background(AppTab.ai.palette.accent.opacity(0.09))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(AppTab.ai.palette.accent.opacity(0.22), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var conversationStarters: [String] {
        [
            "What should I wear today?",
            "Build a work outfit.",
            "Match these shoes.",
            "Improve my style score.",
            "Pack for a weekend trip.",
            "Find a jacket that matches my closet."
        ]
    }

    private var appContextPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("StyleMatch Pro AI can use", systemImage: "checkmark.shield")
                .font(.subheadline)
                .fontWeight(.semibold)

            Text(appContextPreviewText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var chatTranscript: some View {
        VStack(spacing: 10) {
            ForEach(Array(chatMessages.suffix(12))) { message in
                chatBubble(message)
            }

            if isTestingChatGPT {
                HStack {
                    ProgressView()
                    Text("StyleMatch Pro AI is typing...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func chatBubble(_ message: AIChatMessage) -> some View {
        HStack {
            if message.role == .customer {
                Spacer(minLength: 34)
            }

            VStack(alignment: message.role == .customer ? .trailing : .leading, spacing: 6) {
                Text(message.text)
                    .font(.body)
                    .foregroundStyle(message.role == .customer ? .white : .primary)
                    .lineSpacing(4)

                if message.role == .customer, message.isEdited {
                    Text("Edited")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .padding(12)
            .background(message.role == .customer ? AppTab.ai.palette.accent : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))

            if message.role == .assistant {
                Spacer(minLength: 34)
            }
        }
    }

    private var chatInputBar: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message StyleMatch Pro AI", text: $livePrompt, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)

                Button {
                    sendChatGPTMessage()
                } label: {
                    if isTestingChatGPT {
                        ProgressView()
                            .frame(width: 44, height: 44)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .frame(width: 44, height: 44)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTab.ai.palette.accent)
                .disabled(isTestingChatGPT || !openAIKeyIsSaved || livePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Send AI message")
                .accessibilityHint("Sends your message to StyleMatch Pro AI")

                Button {
                    chatMessages = [
                        AIChatMessage(role: .assistant, text: "Chat cleared. What would you like help with next?")
                    ]
                    liveStatus = nil
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .accessibilityLabel("Clear chat")
                .accessibilityHint("Clears the current AI chat messages")
            }
        }
    }

    private func loadOpenAIKey() {
        openAIKeyInput = OpenAIKeychain.loadAPIKey() ?? ""
        openAIKeyIsSaved = !openAIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if openAIModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || openAIModel == "gpt-5.5" {
            openAIModel = "gpt-4o-mini"
        }
        if openAIKeyIsSaved {
            liveStatus = "StyleMatch Pro AI access is ready on this phone."
        }
    }

    private func saveOpenAIKey() {
        do {
            try OpenAIKeychain.saveAPIKey(openAIKeyInput)
            openAIKeyInput = OpenAIKeychain.loadAPIKey() ?? openAIKeyInput
            openAIKeyIsSaved = !openAIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            liveStatus = "StyleMatch Pro AI access is ready."
        } catch {
            liveStatus = "Could not save your AI access key: \(error.localizedDescription)"
        }
    }

    private func deleteOpenAIKey() {
        do {
            try OpenAIKeychain.deleteAPIKey()
            openAIKeyInput = ""
            openAIKeyIsSaved = false
            liveStatus = "StyleMatch Pro AI access was removed from this phone."
        } catch {
            liveStatus = "Could not remove StyleMatch Pro AI access: \(error.localizedDescription)"
        }
    }

    private func testChatGPT() {
        sendChatGPTMessage()
    }

    private func sendChatGPTMessage() {
        let prompt = livePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            liveStatus = "Type a message before sending."
            return
        }

        let savedKey = openAIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !savedKey.isEmpty else {
            liveStatus = "Add the founder access key before sending."
            return
        }

        isTestingChatGPT = true
        livePrompt = ""
        liveStatus = "Getting a fast answer..."

        chatMessages.append(AIChatMessage(role: .customer, text: prompt))
        trimChatMessages()
        let conversationAfterSend = activeMainChatConversationHistory()
        sendChatGPTPrompt(prompt, apiKey: savedKey, conversationHistory: conversationAfterSend)
    }

    private func sendChatGPTPrompt(_ prompt: String, apiKey: String, conversationHistory: [AIChatMessage]) {
        let client = OpenAIStylistClient(apiKey: apiKey, model: openAIModel)
        let profile = StyleMatchStylistProfile(
            name: name,
            favoriteColors: favoriteColors,
            favoriteBrands: favoriteBrands,
            preferredFit: fitPreference,
            budget: budget,
            sizeProfile: sizeProfile,
            stylePreferences: stylePreferences,
            occasions: occasions,
            weather: weather,
            weatherPreferences: weatherLocationText,
            dressCode: plannedOccasionSummary,
            shoppingHabits: shoppingHabitsSummary,
            pastOutfitRatings: pastOutfitRatingsSummary,
            frequentlyWornOutfits: frequentlyWornOutfitsSummary,
            pastPurchases: pastPurchases,
            favoriteOutfits: favoriteOutfits,
            closetInventory: closetInventory,
            appContextSharingEnabled: shareAppContextWithChatGPT,
            appContext: shareAppContextWithChatGPT ? fastAppContextSummary : "App context sharing is off. Use only the customer message and manually provided profile fields."
        )

        Task {
            do {
                let advice = try await client.askStylist(
                    profile: profile,
                    messages: clientHistory(from: conversationHistory, currentPrompt: prompt),
                    question: prompt
                )
                await MainActor.run {
                    chatMessages.append(AIChatMessage(role: .assistant, text: advice))
                    trimChatMessages()
                    liveStatus = "StyleMatch Pro AI replied."
                    isTestingChatGPT = false
                }
            } catch {
                await MainActor.run {
                    liveStatus = "AI Stylist is having trouble connecting right now. Please try again."
                    chatMessages.append(AIChatMessage(role: .assistant, text: "AI Stylist is having trouble connecting right now. Please try again."))
                    trimChatMessages()
                    isTestingChatGPT = false
                }
            }
        }
    }

    private func activeMainChatConversationHistory() -> [AIChatMessage] {
        Array(chatMessages.suffix(24))
    }

    private func clientHistory(from conversationHistory: [AIChatMessage], currentPrompt: String) -> [AIChatMessage] {
        var history = conversationHistory
        if let last = history.last,
           last.role == .customer,
           last.text.trimmingCharacters(in: .whitespacesAndNewlines) == currentPrompt {
            history.removeLast()
        }
        return history
    }

    private func trimChatMessages() {
        guard chatMessages.count > 20 else {
            return
        }

        chatMessages.removeFirst(chatMessages.count - 20)
    }

    private var appContextPreviewText: String {
        let closetCount = decodedClosetItems.count
        let scanCount = decodedRecentScans.count
        return "Profile, sizes, budget, weather, \(closetCount) closet item\(closetCount == 1 ? "" : "s"), and \(scanCount) recent scan\(scanCount == 1 ? "" : "s")."
    }

    private var appContextSummary: String {
        """
        Current Style Match Pro screen: AI Stylist chat.
        Privacy: Customer allowed app context sharing for this StyleMatch Pro AI message.

        Closet items:
        \(closetSummary)

        Recent scan history:
        \(scanHistorySummary)

        Styling rules:
        - Check existing closet pieces before recommending new purchases.
        - Stay inside budget when possible: \(budget).
        - \(sizeProfileContextRule)
        - Respect preferred fit: \(fitPreference).
        - Use weather context: \(weatherLocationText).
        - Match occasion: \(plannedOccasionSummary).
        - Prefer customer brands/colors when they fit the outfit.
        - Style memory: \(styleMemorySummary)
        """
    }

    private var fastAppContextSummary: String {
        """
        Screen: AI Stylist chat. App context sharing is on.
        Closet: \(compactClosetSummary)
        Recent outfit scores: \(compactScanHistorySummary)
        Wardrobe intelligence: \(wardrobeIntelligenceSummary)
        Style progress: \(styleProgressForAI)
        Wishlist and shopping: \(wishlistSummaryForAI)
        Style memory: \(styleMemorySummary)
        Privacy rules: use outfit/profile facts only for styling. Do not infer race, ethnicity, nationality, religion, age, gender, identity, or body judgment.
        Styling rules: use closet first, explain why, respect \(sizeProfileInlineText), fit \(fitPreference), budget \(budget), weather \(weatherLocationText), occasion \(plannedOccasionSummary), favorite colors \(favoriteColors), and favorite brands \(favoriteBrands).
        """
    }

    private var styleMemoryItems: [StyleMemoryItem] {
        [
            StyleMemoryItem(title: "Favorite colors", value: cleanMemoryValue(favoriteColors, fallback: topColorText), icon: "paintpalette.fill", tint: .purple),
            StyleMemoryItem(title: "Favorite brands", value: cleanMemoryValue(favoriteBrands, fallback: topBrandText), icon: "tag.fill", tint: .blue),
            StyleMemoryItem(title: "Preferred fit", value: cleanMemoryValue(fitPreference, fallback: "Not set"), icon: "person.crop.rectangle", tint: .green),
            StyleMemoryItem(title: "Budget", value: cleanMemoryValue(budget, fallback: "Not set"), icon: "dollarsign.circle.fill", tint: .orange),
            StyleMemoryItem(title: "Weather", value: cleanMemoryValue(weatherLocationText, fallback: "Not set"), icon: "cloud.sun.fill", tint: .cyan),
            StyleMemoryItem(title: "Dress code", value: cleanMemoryValue(plannedOccasionSummary, fallback: "Not set"), icon: "checkmark.seal.fill", tint: .mint),
            StyleMemoryItem(title: "Shopping habits", value: shoppingHabitsSummary, icon: "bag.fill", tint: AppTab.shop.palette.accent),
            StyleMemoryItem(title: "Past ratings", value: pastOutfitRatingsSummary, icon: "chart.line.uptrend.xyaxis", tint: AppTab.ai.palette.accent),
            StyleMemoryItem(title: "Worn often", value: frequentlyWornOutfitsSummary, icon: "repeat.circle.fill", tint: .pink)
        ]
    }

    private var aiKnowsClosetCountText: String {
        "\(decodedClosetItems.count)"
    }

    private var sizeProfileDisplayText: String {
        let trimmed = sizeProfile.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No sizes saved yet" : trimmed
    }

    private var sizeProfileInlineText: String {
        let trimmed = sizeProfile.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "no saved size profile yet" : trimmed.lowercased()
    }

    private var sizeProfileContextRule: String {
        let trimmed = sizeProfile.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No saved size profile yet." : "Respect size profile: \(trimmed)."
    }

    private var shirtSizeDisplayText: String {
        let trimmed = shirtSize.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed.uppercased() {
        case "XS":
            return "Extra Small"
        case "S":
            return "Small"
        case "M":
            return "Medium"
        case "L":
            return "Large"
        case "XL":
            return "XL"
        case "XXL", "2XL":
            return "XXL"
        default:
            return trimmed.isEmpty ? "No shirt size saved" : trimmed
        }
    }

    private var pantsSizeDisplayText: String {
        let trimmed = pantsSize
            .replacingOccurrences(of: "Men ", with: "")
            .replacingOccurrences(of: "Women ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmed.isEmpty {
            return trimmed
        }

        if let range = sizeProfile.range(of: #"(\d{2})\s*[Ww]?\s*[xX]\s*(\d{2})"#, options: .regularExpression) {
            return String(sizeProfile[range])
                .replacingOccurrences(of: "W", with: "")
                .replacingOccurrences(of: "w", with: "")
                .replacingOccurrences(of: " ", with: "")
        }

        return "No pants size saved"
    }

    private var favoriteColorsDisplayText: String {
        let colors = favoriteColors
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).capitalized }
            .filter { !$0.isEmpty }
            .prefix(2)

        return colors.isEmpty ? "Not set" : colors.joined(separator: ", ")
    }

    private var budgetDisplayText: String {
        let trimmed = budget.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Not set" : trimmed.replacingOccurrences(of: " - ", with: "-")
    }

    private var preferredStyleDisplayText: String {
        let styleText = stylePreferences
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).capitalized }
            .first { !$0.isEmpty }

        if let styleText {
            return styleText
        }

        let dressCodeText = dressCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return dressCodeText.isEmpty ? "Business Casual" : dressCodeText.capitalized
    }

    private var styleMemoryStrength: Int {
        let filledCount = styleMemoryItems.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        let activityBoost = min(20, decodedClosetItems.count * 2 + decodedRecentScans.count * 4)
        return min(100, 38 + filledCount * 5 + activityBoost)
    }

    private var styleMemorySummary: String {
        """
        favorite colors \(cleanMemoryValue(favoriteColors, fallback: topColorText)); favorite brands \(cleanMemoryValue(favoriteBrands, fallback: topBrandText)); preferred fit \(fitPreference); budget \(budget); weather preferences \(weatherLocationText); dress code \(plannedOccasionSummary); shopping habits \(shoppingHabitsSummary); past outfit ratings \(pastOutfitRatingsSummary); frequently worn outfits \(frequentlyWornOutfitsSummary).
        """
    }

    private var shoppingHabitsSummary: String {
        let wishlistCount = decodedWishlistProductNames.count
        let purchases = pastPurchases.trimmingCharacters(in: .whitespacesAndNewlines)
        let brands = favoriteBrands.trimmingCharacters(in: .whitespacesAndNewlines)

        if wishlistCount > 0 {
            return "\(wishlistCount) wishlist item\(wishlistCount == 1 ? "" : "s"); prefers \(brands.isEmpty ? "saved brands" : brands)."
        }

        if !purchases.isEmpty {
            return "Recent buys: \(purchases)."
        }

        return "Closet-first, budget-aware shopping."
    }

    private var pastOutfitRatingsSummary: String {
        let scans = decodedRecentScans
        guard !scans.isEmpty else {
            return "No ratings yet"
        }

        let average = scans.map(\.score).reduce(0, +) / scans.count
        let highScore = scans.map(\.score).max() ?? average
        return "\(average) avg, \(highScore) best, \(scans.count) saved"
    }

    private var frequentlyWornOutfitsSummary: String {
        if let repeatedScan = decodedRecentScans.first(where: { $0.scanCount > 1 }) {
            let items = repeatedScan.analysis?.safeDetectedClothingItems.prefix(3).joined(separator: ", ") ?? "saved outfit"
            return "\(items), scanned \(repeatedScan.scanCount)x"
        }

        let savedFavorite = favoriteOutfits.trimmingCharacters(in: .whitespacesAndNewlines)
        if !savedFavorite.isEmpty {
            return savedFavorite
        }

        return compactClosetSummary
    }

    private func cleanMemoryValue(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private var weatherLocationText: String {
        let city = weatherCity.trimmingCharacters(in: .whitespacesAndNewlines)
        let condition = weatherCondition.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedWeather = weather.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = savedWeather.isEmpty ? condition : "\(condition), \(savedWeather)"
        return city.isEmpty ? base : "\(base) in \(city)"
    }

    private var plannedOccasionSummary: String {
        let plan = plannedOccasion.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = dressCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let formality = occasionFormality.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = occasions.trimmingCharacters(in: .whitespacesAndNewlines)
        let occasion = plan.isEmpty ? (fallback.isEmpty ? "your next occasion" : fallback) : plan
        let details = [code, formality].filter { !$0.isEmpty }
        return details.isEmpty ? occasion : "\(occasion), \(details.joined(separator: ", "))"
    }

    private var closetSummary: String {
        let items = decodedClosetItems
        guard !items.isEmpty else {
            return "No detailed closet items saved yet. Use closet inventory text: \(closetInventory)."
        }

        return items.prefix(20).map { item in
            "- \(item.name), \(item.category), \(item.color), size \(item.size), brand \(item.brand.isEmpty ? "not saved" : item.brand), occasion \(item.occasion), notes: \(item.notes.isEmpty ? "none" : item.notes)"
        }.joined(separator: "\n")
    }

    private var compactClosetSummary: String {
        let items = decodedClosetItems
        guard !items.isEmpty else {
            return closetInventory
        }

        return items.prefix(8).map { item in
            "\(item.color) \(item.name) \(item.size)"
        }.joined(separator: ", ")
    }

    private var scanHistorySummary: String {
        let scans = decodedRecentScans
        guard !scans.isEmpty else {
            return "No completed outfit scan history saved yet."
        }

        return scans.prefix(5).map { scan in
            let analysis = scan.analysis
            let suggestions = analysis?.suggestions.prefix(3).joined(separator: "; ") ?? "No suggestions saved."
            let items = analysis?.safeDetectedClothingItems.prefix(5).joined(separator: ", ") ?? "No item labels saved."
            return "- Score \(scan.score)/100, scanned \(scan.scanCount) time\(scan.scanCount == 1 ? "" : "s"), items: \(items), summary: \(analysis?.summary ?? "No summary saved."), suggestions: \(suggestions)"
        }.joined(separator: "\n")
    }

    private var compactScanHistorySummary: String {
        let scans = decodedRecentScans
        guard !scans.isEmpty else {
            return "none yet"
        }

        return scans.prefix(2).map { scan in
            "\(scan.score)/100"
        }.joined(separator: ", ")
    }

    private var wardrobeIntelligenceSummary: String {
        let items = decodedClosetItems
        guard !items.isEmpty else {
            return "Manual closet inventory: \(closetInventory)."
        }

        let categoryCounts = Dictionary(grouping: items, by: \.category)
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }
            .prefix(4)
            .map { "\($0.0): \($0.1)" }
            .joined(separator: ", ")
        let colorCounts = Dictionary(grouping: items, by: \.color)
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }
            .prefix(4)
            .map { "\($0.0): \($0.1)" }
            .joined(separator: ", ")
        let brandCounts = Dictionary(grouping: items.filter { !$0.brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, by: \.brand)
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }
            .prefix(3)
            .map { "\($0.0): \($0.1)" }
            .joined(separator: ", ")

        return "\(items.count) closet items. Categories: \(categoryCounts). Colors: \(colorCounts). Brands: \(brandCounts.isEmpty ? "not enough saved brand data" : brandCounts)."
    }

    private var styleProgressForAI: String {
        let scans = decodedRecentScans
        guard !scans.isEmpty else {
            return "No saved scan scores yet."
        }

        let scores = scans.map(\.score)
        let average = scores.reduce(0, +) / max(scores.count, 1)
        let highest = scores.max() ?? average
        let latest = scores.first ?? average
        return "\(scans.count) saved scans. Latest \(latest)/100. Average \(average)/100. Highest \(highest)/100."
    }

    private var wishlistSummaryForAI: String {
        guard !wishlistProductNamesData.isEmpty,
              let productNames = try? JSONDecoder().decode([String].self, from: wishlistProductNamesData),
              !productNames.isEmpty else {
            return "No wishlist items saved yet. Recommend shopping only when it clearly improves the outfit."
        }

        return "Wishlist: \(productNames.prefix(8).joined(separator: ", ")). Use these before suggesting unrelated products."
    }

    private var decodedClosetItems: [ClosetItem] {
        cachedClosetItems
    }

    private var decodedRecentScans: [AIContextStoredScan] {
        cachedRecentScans
    }

    private func refreshSavedContextCache() {
        if !closetItemsData.isEmpty,
           let items = try? JSONDecoder().decode([ClosetItem].self, from: closetItemsData) {
            cachedClosetItems = items
        } else {
            cachedClosetItems = []
        }

        guard !outfitScanHistoryData.isEmpty,
              let history = try? JSONDecoder().decode([String: AIContextStoredScan].self, from: outfitScanHistoryData) else {
            cachedRecentScans = []
            return
        }

        cachedRecentScans = Array(history.values.sorted { $0.firstScannedAt > $1.firstScannedAt }.prefix(20))
    }
}

private struct StylistFeature: Identifiable {
    var id: String { title }
    let title: String
    let icon: String
    let detail: String
}

private struct AIContextStoredScan: Codable {
    let score: Int
    let analysis: OutfitAnalysisResult?
    let firstScannedAt: Date
    let scanCount: Int
    let thumbnailData: Data?

    init(score: Int, analysis: OutfitAnalysisResult?, firstScannedAt: Date, scanCount: Int, thumbnailData: Data? = nil) {
        self.score = score
        self.analysis = analysis
        self.firstScannedAt = firstScannedAt
        self.scanCount = scanCount
        self.thumbnailData = thumbnailData
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        score = try container.decodeIfPresent(Int.self, forKey: .score) ?? 0
        analysis = try container.decodeIfPresent(OutfitAnalysisResult.self, forKey: .analysis)
        firstScannedAt = try container.decodeIfPresent(Date.self, forKey: .firstScannedAt) ?? Date()
        scanCount = max(1, try container.decodeIfPresent(Int.self, forKey: .scanCount) ?? 1)

        let decodedThumbnail = try container.decodeIfPresent(Data.self, forKey: .thumbnailData)
        thumbnailData = (decodedThumbnail?.count ?? 0) <= 500_000 ? decodedThumbnail : nil
    }
}

private struct FashionJournalEntry: Identifiable {
    let id = UUID()
    let score: Int
    let analysis: OutfitAnalysisResult?
    let firstScannedAt: Date
    let scanCount: Int
    let thumbnailData: Data?

    var title: String {
        let description = analysis?.outfitDescription.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !description.isEmpty {
            return description
        }

        if let firstItem = analysis?.safeDetectedClothingItems.first,
           let firstColor = analysis?.colorPalette.first {
            return "\(firstColor.capitalized) \(firstItem.capitalized)"
        }

        return "Saved Outfit"
    }

    var combination: String {
        let items = analysis?.safeDetectedClothingItems
            .prefix(3)
            .map { $0.capitalized }
            .joined(separator: ", ") ?? ""
        let colors = analysis?.colorPalette
            .prefix(3)
            .map { $0.capitalized }
            .joined(separator: ", ") ?? ""

        if !items.isEmpty && !colors.isEmpty {
            return "\(items) • \(colors)"
        }
        if !items.isEmpty {
            return items
        }
        return analysis?.summary ?? "Saved style score"
    }

    var shortCombination: String {
        let items = analysis?.safeDetectedClothingItems
            .prefix(2)
            .map { $0.capitalized }
            .joined(separator: " + ") ?? ""
        return items.isEmpty ? "Saved looks" : items
    }

    var dateText: String {
        Self.formatter.string(from: firstScannedAt)
    }

    var ratingTitle: String {
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

    var icon: String {
        if title.localizedCaseInsensitiveContains("shoe") {
            return "shoe.2.fill"
        }
        if title.localizedCaseInsensitiveContains("suit") || title.localizedCaseInsensitiveContains("formal") {
            return "person.fill.checkmark"
        }
        return "tshirt.fill"
    }

    var thumbnailImage: UIImage? {
        guard let thumbnailData else {
            return nil
        }

        return UIImage(data: thumbnailData)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()
}

private struct OutfitPlanMoment: Identifiable {
    let id = UUID()
    let title: String
    let when: String
    let icon: String
    let tint: Color
    let recommendation: String
}

private struct FashionInsight: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let icon: String
    let tint: Color
}

private struct StyleMemoryItem: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let icon: String
    let tint: Color
}

private final class StyleWeatherManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var summaryText: String?
    @Published var isLive = false

    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    func refresh() {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.requestLocation()
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            isLive = false
        @unknown default:
            isLive = false
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        default:
            isLive = false
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            return
        }

        Task {
            await loadWeather(for: location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.isLive = false
        }
    }

    private func loadWeather(for location: CLLocation) async {
        do {
            let weather = try await WeatherService.shared.weather(for: location)
            let temperature = weather.currentWeather.temperature.converted(to: .fahrenheit).value
            let roundedTemperature = Int(temperature.rounded())
            let condition = weather.currentWeather.condition.description.capitalized

            await MainActor.run {
                summaryText = "\(roundedTemperature)°F \(condition)"
                isLive = true
            }
        } catch {
            await MainActor.run {
                isLive = false
            }
        }
    }
}
