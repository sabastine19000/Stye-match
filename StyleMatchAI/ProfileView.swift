import AuthenticationServices
import CoreLocation
import SwiftUI

struct ProfileView: View {
    @Binding var selectedTab: AppTab
    private let voiceControlsEnabled: Bool
    @AppStorage("customerAccountMode") private var customerAccountMode = CustomerAccountMode.guest.rawValue
    @AppStorage("customerAccountEmail") private var customerAccountEmail = ""
    @AppStorage("customerAppleUserID") private var customerAppleUserID = ""
    @AppStorage("customerAccountSyncEnabled") private var accountSyncEnabled = false
    @AppStorage("guestDataLinkedToApple") private var guestDataLinkedToApple = false
    @AppStorage("guestDataTransferSummary") private var guestDataTransferSummary = ""
    @AppStorage("profileName") private var name = ""
    @AppStorage("favoriteColors") private var favoriteColors = ""
    @AppStorage("favoriteBrands") private var favoriteBrands = ""
    @AppStorage("favoriteStores") private var favoriteStores = ""
    @AppStorage("shoppingBudget") private var budget = ""
    @AppStorage("styleGoals") private var styleGoals = ""
    @AppStorage("preferredNeutrals") private var preferredNeutrals = ""
    @AppStorage("preferredAccentColors") private var preferredAccentColors = ""
    @AppStorage("comfortPreferences") private var comfortPreferences = ""
    @AppStorage("preferredPantRise") private var preferredPantRise = ""
    @AppStorage("shoppingFocus") private var shoppingFocus = ""
    @AppStorage("preferredShoppingCategories") private var preferredShoppingCategories = ""
    @AppStorage("workSetting") private var workSetting = ""
    @AppStorage("travelFrequency") private var travelFrequency = ""
    @AppStorage("hobbiesActivities") private var hobbiesActivities = ""
    @AppStorage("stylistVoice") private var stylistVoice = ""
    @AppStorage("styleConsultationCompletedAt") private var styleConsultationCompletedAt = ""
    @AppStorage("sizeProfile") private var sizeProfile = ""
    @AppStorage("shirtSize") private var shirtSize = ""
    @AppStorage("pantsSize") private var pantsSize = ""
    @AppStorage("dressSize") private var dressSize = ""
    @AppStorage("sizeCategory") private var sizeCategory = ""
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
    @AppStorage("liveWeatherUpdatedAt") private var liveWeatherUpdatedAt = 0.0
    @AppStorage("pastPurchases") private var pastPurchases = ""
    @AppStorage("favoriteOutfits") private var favoriteOutfits = ""
    @AppStorage("closetInventory") private var closetInventory = ""
    @AppStorage("outfitDislikes") private var outfitDislikes = ""
    @AppStorage("clothingPreferences") private var clothingPreferences = ""
    @AppStorage("outfitScanHistoryData") private var outfitScanHistoryData = Data()
    @AppStorage("closetItemsData") private var closetItemsData = Data()
    @AppStorage("shareAppContextWithChatGPT") private var shareAppContextWithChatGPT = true
    @AppStorage(VoiceAssistantSettings.enabledKey) private var voiceAssistantEnabled = VoiceAssistantSettings.defaultEnabled
    @AppStorage("voiceStylistDefaultVoiceHintDismissed") private var voiceStylistDefaultVoiceHintDismissed = false
    @AppStorage(VoiceAssistantSettings.speechRateKey) private var voiceAssistantSpeechRate = VoiceAssistantSettings.defaultSpeechRate
    @AppStorage("selectedAppTheme") private var selectedAppTheme = StyleMatchAppTheme.system.rawValue
    @AppStorage("profileLastSavedAt") private var profileLastSavedAt = ""
    @AppStorage("profileNeedsCloudSync") private var profileNeedsCloudSync = false
    @State private var showDeleteDataConfirmation = false
    @State private var showGuestTransferOffer = false
    @State private var pendingAppleSignIn: StyleMatchAppleSignInPayload?
    @State private var pendingAppleNonce: String?
    @State private var isAccountRequestInFlight = false
    @State private var isPreparingAccountDeletion = false
    @State private var showSignOutConfirmation = false
    @State private var showDeleteAccountConfirmation = false
    @State private var isShowingThemeSettings = false
    @State private var isShowingSupport = false
    @State private var isShowingSharedLinks = false
    @State private var isShowingStyleConsultation = false
    @State private var showStyleConsultationResetConfirmation = false
    @State private var showProfileSavedConfirmation = false
    @State private var showUnsavedProfileWarning = false
    @State private var profileDraft = ProfileEditDraft()
    @State private var savedProfileDraft = ProfileEditDraft()
    @State private var hasUnsavedProfileChanges = false
    @State private var hasLoadedProfileDraft = false
    @State private var dataDeletionMessage: String?
    @State private var pantsSizeLastEditSource: PantsSizeEditSource = .manual
    @State private var showsAdditionalMeasurements = false
    @State private var showUndertoneHelp = false
    @StateObject private var voiceAssistant = VoiceStylistService()

    init(selectedTab: Binding<AppTab>, voiceControlsEnabled: Bool = true) {
        self._selectedTab = selectedTab
        self.voiceControlsEnabled = voiceControlsEnabled
    }

    private var selectedAccountMode: CustomerAccountMode {
        CustomerAccountMode(rawValue: customerAccountMode) ?? .guest
    }

    private var activeAccountUserID: String {
        StyleMatchAccountNameResolver.clean(customerAppleUserID)
        ?? StyleMatchAccountNameResolver.clean(customerAccountEmail)
        ?? "guest"
    }

    private var resolvedProfileDisplayName: String {
        let storedName = ProfileStore(userId: activeAccountUserID).currentProfile.givenName
        return StyleMatchAccountNameResolver.profileGivenName(from: storedName)
        ?? StyleMatchAccountNameResolver.clean(name)
        ?? ""
    }

    private var resolvedAccountEmail: String {
        StyleMatchAppleCredentialProfileApplier.storedEmail(userID: activeAccountUserID)
        ?? StyleMatchAccountNameResolver.clean(customerAccountEmail)
        ?? ""
    }

    private let shirtSizeOptions = ["XXS", "XS", "S", "M", "L", "XL", "XXL", "2XL", "3XL", "4XL", "5XL", "6XL", "7XL", "8XL"]
    private let womenTopSizeOptions = ["XXS", "XS", "S", "M", "L", "XL", "1X", "2X", "3X", "4X", "5X", "6X"]
    private let womenBottomSizeOptions = ["000", "00"] + (0...34).map { "\($0)" } + ["XXS", "XS", "S", "M", "L", "XL", "1X", "2X", "3X", "4X", "5X", "6X"]
    private let dressSizeOptions = ["000", "00"] + (0...34).map { "\($0)" } + ["XXS", "XS", "S", "M", "L", "XL", "1X", "2X", "3X", "4X", "5X", "6X"]
    private let kidsYouthSizeOptions = ["2T", "3T", "4T", "5", "6", "7", "8", "10", "12", "14", "16", "18", "Youth XS", "Youth S", "Youth M", "Youth L", "Youth XL"]
    private let shoeSizeOptions = (5...18).map { "\($0)" }
    private let womenShoeSizeOptions = ["4", "4.5", "5", "5.5", "6", "6.5", "7", "7.5", "8", "8.5", "9", "9.5", "10", "10.5", "11", "11.5", "12", "13"]
    private let youthShoeSizeOptions = ["Toddler 5", "Toddler 6", "Toddler 7", "Toddler 8", "Toddler 9", "Toddler 10", "Little Kid 11", "Little Kid 12", "Little Kid 13", "Big Kid 1", "Big Kid 2", "Big Kid 3", "Big Kid 4", "Big Kid 5", "Big Kid 6", "Big Kid 7"]
    private let fitPreferenceOptions = ["Slim", "Regular", "Relaxed", "Oversized"]
    private let undertoneOptions = DeclaredUndertone.allCases
    private let styleIdentityOptions = ["Casual", "Business Casual", "Classic", "Minimalist", "Streetwear", "Athletic", "Luxury", "Trend-Focused", "Smart Casual"]
    private let styleGoalOptions = ["Dress more professionally", "Build confidence", "Improve color matching", "Create better everyday outfits", "Build a versatile wardrobe", "Spend more intentionally", "Prepare outfits faster", "Try new styles"]
    private let neutralColorOptions = ["Black", "White", "Gray", "Navy", "Cream", "Tan", "Brown", "Olive"]
    private let accentColorOptions = ["Blue", "Green", "Red", "Burgundy", "Gold", "Silver", "Pink", "Purple"]
    private let pantRiseOptions = ["Low", "Mid", "High", "No preference"]
    private let comfortPreferenceOptions = ["I avoid tight shirts", "I prefer lightweight fabrics", "I prefer longer tops", "I avoid short sleeves", "I avoid shorts", "I prefer stretch fabrics", "I prefer simple patterns", "I avoid bright colors", "I prioritize comfort", "I prefer easy-care clothing"]
    private let shoppingFocusOptions = ["Value-focused", "Balanced", "Luxury-focused"]
    private let shoppingCategoryOptions = ["Tops", "Bottoms", "Shoes", "Accessories", "Outerwear", "Dresses", "Workwear", "Athletic"]
    private let workSettingOptions = ["Remote", "Office", "Hybrid", "Uniform or dress code", "Creative", "Active or outdoors", "Student", "Not applicable"]
    private let travelFrequencyOptions = ["Rarely", "A few times a year", "Monthly", "Often", "No preference"]
    private let stylistVoiceOptions = ["Encouraging Coach", "Luxury Fashion Expert", "Minimalist Consultant", "Trend Advisor", "Straightforward Critic"]
    private let weatherConditionOptions = ["Mild", "Hot", "Cold", "Rainy", "Windy", "Humid", "Sunny"]
    private let occasionFormalityOptions = ["Casual", "Smart casual", "Polished", "Formal", "Travel comfort"]

    var body: some View {
        NavigationStack {
            Form {
                profileOverviewSections
                stylePreferenceSections
                personalizationAndPrivacySections
                dataControlAndSettingsSections
            }
            .scrollContentBackground(.hidden)
            .appScreenBackground(.profile)
            .tint(AppTab.profile.palette.accent)
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        attemptProfileExit()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .accessibilityLabel("Back to Home")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveProfileDraft()
                    }
                    .fontWeight(.semibold)
                    .disabled(!hasUnsavedProfileChanges)
                }
            }
            .onAppear {
                updateSizeProfileSummary()
                loadProfileDraftIfNeeded()
            }
            .alert("Profile saved successfully.", isPresented: $showProfileSavedConfirmation) {
                Button("OK", role: .cancel) {
                }
            } message: {
                Text(accountSyncEnabled ? "Saved locally and marked for account sync when cloud sync is available." : "Saved locally on this phone.")
            }
            .modifier(ProfileAccountConfirmationModifier(
                showSignOutConfirmation: $showSignOutConfirmation,
                showDeleteAccountConfirmation: $showDeleteAccountConfirmation,
                isPreparingAccountDeletion: $isPreparingAccountDeletion,
                signOut: signOut
            ))
            .confirmationDialog(
                "Reset Style Consultation?",
                isPresented: $showStyleConsultationResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset Style Consultation", role: .destructive) {
                    resetStyleConsultation()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This clears optional consultation answers only. Saved scans, account data, closet items, shopping data, and outfit scores stay unchanged.")
            }
            .confirmationDialog(
                "You have unsaved profile changes.",
                isPresented: $showUnsavedProfileWarning,
                titleVisibility: .visible
            ) {
                Button("Save Profile") {
                    saveProfileDraft()
                    selectedTab = .home
                }

                Button("Leave Without Saving", role: .destructive) {
                    loadProfileDraft(force: true)
                    selectedTab = .home
                }

                Button("Cancel", role: .cancel) {
                }
            } message: {
                Text("Save your profile so StyleMatch Pro can use the latest sizes, colors, budget, occasions, and shopping preferences.")
            }
            .confirmationDialog(
                "Delete saved Style Match Pro data?",
                isPresented: $showDeleteDataConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Saved Data", role: .destructive) {
                    deleteSavedData()
                }
                Button("Cancel", role: .cancel) {
                }
            } message: {
                Text("This removes saved account choice, profile, assistant choice, closet inventory, style preferences, and scan history from this phone.")
            }
            .confirmationDialog(
                "Transfer Guest Data?",
                isPresented: $showGuestTransferOffer,
                titleVisibility: .visible
            ) {
                Button("Transfer My Guest Data") {
                    completePendingAppleSignIn(transferGuestData: true)
                }

                Button("Continue Without Transfer") {
                    completePendingAppleSignIn(transferGuestData: false)
                }
            } message: {
                Text("StyleMatch Pro can keep your local scan history, favorites, closet, style preferences, and profile information with your Apple sign-in.")
            }
            .sheet(isPresented: $isShowingThemeSettings) {
                ThemeSettingsView(selectedTheme: $selectedAppTheme)
            }
            .sheet(isPresented: $isShowingSupport) {
                SupportView(selectedTab: $selectedTab)
            }
            .sheet(isPresented: $isShowingSharedLinks) {
                ShareableScoreCardManagerView()
            }
            .sheet(isPresented: $isShowingStyleConsultation) {
                StyleConsultationSheet(
                    draft: $profileDraft,
                    styleIdentityOptions: styleIdentityOptions,
                    styleGoalOptions: styleGoalOptions,
                    fitPreferenceOptions: fitPreferenceOptions,
                    undertoneOptions: undertoneOptions,
                    neutralColorOptions: neutralColorOptions,
                    accentColorOptions: accentColorOptions,
                    pantRiseOptions: pantRiseOptions,
                    comfortPreferenceOptions: comfortPreferenceOptions,
                    shoppingFocusOptions: shoppingFocusOptions,
                    shoppingCategoryOptions: shoppingCategoryOptions,
                    workSettingOptions: workSettingOptions,
                    travelFrequencyOptions: travelFrequencyOptions,
                    stylistVoiceOptions: stylistVoiceOptions,
                    markDirty: updateProfileDirtyState,
                    complete: completeStyleConsultation,
                    skip: {
                        isShowingStyleConsultation = false
                    }
                )
            }
            .sheet(isPresented: $showUndertoneHelp) {
                NavigationStack {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Color Undertone")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("This is optional. Choose Not sure or leave it blank if you do not want to provide it.")
                            .foregroundStyle(.secondary)

                        Label("Vein check: blue or purple can suggest cool; green can suggest warm; a mix can suggest neutral.", systemImage: "hand.raised")
                        Label("Jewelry check: silver often suits cool, gold often suits warm, and both can suit neutral.", systemImage: "sparkles")
                        Label("Use what feels accurate. StyleMatch Pro treats this as your preference, not a fact about your identity.", systemImage: "person.crop.circle.badge.checkmark")

                        Spacer()
                    }
                    .padding()
                    .navigationTitle("How do I know?")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                showUndertoneHelp = false
                            }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    @ViewBuilder
    private var profileOverviewSections: some View {
        AnyView(profileHeaderSection)
        AnyView(accountSection)
        AnyView(personalInformationSection)
        AnyView(aiStylistSettingsSection)
        AnyView(personalStyleProfileSection)
        AnyView(voiceAssistantSection)
    }

    private var profileHeaderSection: some View {
        Section {
            PageColorBand(
                tab: .profile,
                title: "Profile",
                subtitle: "Pink profile space for sizes, weather, and preferences.",
                icon: "person.fill"
            )
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    private var personalInformationSection: some View {
        Section("Personal Information") {
            profileInfoRow("Name", cleanValue(resolvedProfileDisplayName, fallback: "Not set"), icon: "person.fill")
            profileInfoRow("Email", cleanValue(resolvedAccountEmail, fallback: "Hidden or not shared"), icon: "envelope.fill")
            profileInfoRow("Account Type", selectedAccountMode.accountStatusTitle, icon: accountIcon)
            profileInfoRow("Preferred Weather City", cleanValue(weatherCity, fallback: "Not set"), icon: "mappin.and.ellipse")

            Label("Private tokens, passwords, API keys, and developer credentials are not shown in StyleMatch Pro.", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var aiStylistSettingsSection: some View {
        Section("AI Stylist Settings") {
            profileInfoRow("StyleMatch Pro AI Stylist", "Powered by StyleMatch Pro AI", icon: "sparkles")

            Button {
                selectedTab = .ai
            } label: {
                Label("Ask My Stylist", systemImage: "bubble.left.and.bubble.right.fill")
            }

            Toggle("Personal Style Memory", isOn: $shareAppContextWithChatGPT)

            Text("StyleMatch Pro uses your saved preferences to provide more personalized outfit recommendations.")
                .font(.caption)
                .foregroundStyle(.secondary)

            profileInfoRow("AI Confidence", "\(aiConfidence)%", icon: "checkmark.seal.fill")
            profileInfoRow("Profile Completeness", "\(profileCompleteness)%", icon: "person.crop.circle.badge.checkmark")
            profileInfoRow("Saved Scans", "\(savedScanCount)", icon: "photo.stack")
            profileInfoRow(
                "Closet Items",
                "\(closetItemCount)",
                icon: "tshirt.fill",
                accessibilityLabel: "Open Virtual Closet, \(closetItemCount) \(closetItemCount == 1 ? "item" : "items")"
            ) {
                selectedTab = .closet
            }
        }
    }

    @ViewBuilder
    private var personalStyleProfileSection: some View {
        Section("Personal Style Profile") {
            NavigationLink {
                StyleDNAScreen(
                    draft: profileDraft,
                    consultationCompletedAt: styleConsultationCompletedAt,
                    edit: { isShowingStyleConsultation = true },
                    reset: resetStyleConsultation
                )
            } label: {
                Label("Style DNA", systemImage: "person.crop.rectangle.stack")
            }

            Button {
                isShowingStyleConsultation = true
            } label: {
                Label(styleConsultationCompletedAt.isEmpty ? "Start Style Consultation" : "Edit Style Consultation", systemImage: "person.text.rectangle")
            }

            if !styleConsultationCompletedAt.isEmpty {
                Button(role: .destructive) {
                    showStyleConsultationResetConfirmation = true
                } label: {
                    Label("Reset Style Consultation", systemImage: "arrow.counterclockwise")
                }
            }

            Text("Optional. Teach your stylist what you like, what feels comfortable, and how you shop. You can skip, finish later, edit, or reset it anytime.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var voiceAssistantSection: some View {
        Section("Voice Assistant") {
            if voiceControlsEnabled {
                Toggle("Speak outfit guidance", isOn: $voiceAssistantEnabled)

                if voiceAssistantEnabled,
                   voiceAssistant.isUsingDefaultQualityVoice,
                   !voiceStylistDefaultVoiceHintDismissed {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("For a smoother voice, download an enhanced voice in iPhone Settings > Accessibility > Spoken Content > Voices.", systemImage: "speaker.wave.2.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Got it") {
                            voiceStylistDefaultVoiceHintDismissed = true
                        }
                        .font(.caption)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Voice pace")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Slider(value: $voiceAssistantSpeechRate, in: 0.75...1.1, step: 0.05)
                    Text("Brief foreground voice summaries for scan results, scan issues, and profile saves. This does not run in the background.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    if voiceAssistant.isSpeaking {
                        voiceAssistant.stop()
                    } else {
                        voiceAssistant.previewVoice()
                    }
                } label: {
                    Label(voiceAssistant.isSpeaking ? "Stop Preview" : "Preview Voice", systemImage: voiceAssistant.isSpeaking ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }
                .disabled(!voiceAssistantEnabled)

                if let playbackError = voiceAssistant.playbackErrorMessage {
                    Label(playbackError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Voice playback error. \(playbackError)")
                }
            } else {
                Label("Voice controls disabled for launch diagnosis", systemImage: "speaker.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var stylePreferenceSections: some View {
                    Section("Style Profile") {
                    profileDraftField("Name", text: draftBinding(\.name), prompt: "Your display name")
                    profileDraftField("Favorite Colors", text: draftBinding(\.favoriteColors), prompt: "Black, navy, white")
                    profileDraftField("Favorite Brands", text: draftBinding(\.favoriteBrands), prompt: "e.g. favorite brands")
                    profileDraftField("Favorite Stores", text: draftBinding(\.favoriteStores), prompt: "Macy's, Target, Nordstrom")
                    profileDraftField("Budget Range", text: draftBinding(\.budget), prompt: "$50 - $200")
                    profileDraftField("Style Preference", text: draftBinding(\.stylePreferences), prompt: "Classic, streetwear, minimal")
                    profileDraftField("Occasions", text: draftBinding(\.occasions), prompt: "e.g. work, travel, dinner")
                    profileDraftField("Outfit Dislikes", text: draftBinding(\.outfitDislikes), prompt: "Too tight, loud colors, heavy layers")
                    profileDraftField("Clothing Preferences", text: draftBinding(\.clothingPreferences), prompt: "Comfortable shoes, clean fits")
                    profileDraftField("Past Purchases", text: draftBinding(\.pastPurchases), prompt: "e.g. recent clothing purchases")
                    profileDraftField("Favorite Outfits", text: draftBinding(\.favoriteOutfits), prompt: "e.g. your favorite go-to outfit")
                    profileDraftField("Closet Inventory", text: draftBinding(\.closetInventory), prompt: "e.g. closet staples")
                }

                Section("Color & Fit") {
                    Picker("Color undertone (optional)", selection: draftBinding(\.declaredUndertone)) {
                        Text("Not provided").tag("")
                        ForEach(undertoneOptions, id: \.rawValue) { undertone in
                            Text(undertone.displayName).tag(undertone.rawValue)
                        }
                    }

                    Button {
                        showUndertoneHelp = true
                    } label: {
                        Label("How do I know?", systemImage: "info.circle")
                    }

                    Picker("Preferred fit", selection: draftBinding(\.fitPreference)) {
                        Text("Not provided").tag("")
                        ForEach(optionsIncludingCurrent(fitPreferenceOptions, current: profileDraft.fitPreference), id: \.self) { fit in
                            Text(fit).tag(fit)
                        }
                    }

                    Button(role: .destructive) {
                        clearColorAndFitProfile()
                    } label: {
                        Label("Clear Color & Fit", systemImage: "xmark.circle")
                    }
                    .disabled(profileDraft.declaredUndertone.isEmpty && profileDraft.fitPreference.isEmpty)

                    Label("Optional. Used only for fashion color and fit suggestions. If saved, these preferences may be included in AI styling requests; they are never used to identify race, ethnicity, or sensitive traits, and they never change your outfit score.", systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Weather Planning") {
                    profileInfoRow("Live Weather Status", weatherStatusText, icon: "cloud.sun.fill")
                    profileInfoRow("Location Permission", locationPermissionText, icon: "location.fill")
                    profileInfoRow("Last Updated", weatherLastUpdatedText, icon: "clock.fill")

                    TextField("Weather city", text: $weatherCity)
                        .textInputAutocapitalization(.words)
                    TextField("Weather", text: $weather)

                    Picker("Weather condition", selection: $weatherCondition) {
                        Text("Not set").tag("")
                        ForEach(optionsIncludingCurrent(weatherConditionOptions, current: weatherCondition), id: \.self) { condition in
                            Text(condition).tag(condition)
                        }
                    }

                    WeatherStylingButton {
                        Label("Refresh Weather", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    WeatherStylingButton {
                        Label("Change Weather City", systemImage: "mappin.and.ellipse")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Label("Manual city and live weather are used for outfit suggestions. If location is off, save a city for weather-based outfit advice.", systemImage: "location")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Occasion Styling") {
                    TextField("Planned occasion", text: $plannedOccasion)
                        .textInputAutocapitalization(.words)
                    TextField("Dress code", text: $dressCode)
                        .textInputAutocapitalization(.words)

                    Picker("Formality", selection: $occasionFormality) {
                        Text("Not set").tag("")
                        ForEach(optionsIncludingCurrent(occasionFormalityOptions, current: occasionFormality), id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }

                    Label("Used to match outfit formality, comfort, color, weather, and closet pieces to the event.", systemImage: "calendar.badge.checkmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                    Section("Size Profile") {
                    Picker("Size category", selection: sizeCategoryBinding()) {
                        Text("Not set").tag("")
                        ForEach(SizeProfileCategory.allCases) { category in
                            Text(category.rawValue).tag(category.rawValue)
                        }
                    }

                    sizeFields(for: selectedDraftSizeCategory)

                    sizeProfileSummaryCard(for: profileDraft)

                    Label("Saved privately on this phone and used only for fit, sizing, and clothing recommendations.", systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
    }

    @ViewBuilder
    private var personalizationAndPrivacySections: some View {
                    Section("Personalization") {
                    Text("Style Match Pro now saves your preferred AI assistant, colors, brands, budget, sizes, past purchases, favorite outfits, weather, occasions, and closet inventory before suggesting anything new.")
                        .foregroundStyle(.secondary)
                }

                profileCompletenessSection

                    Section("Your Privacy") {
                    Text("Your data stays on your device whenever possible. Cloud AI is used only when needed. You control your information.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    privacyPromiseRow("Data stays on your device whenever possible.")
                    privacyPromiseRow("Cloud AI is used only when needed.")
                    privacyPromiseRow("You control your information.")
                    privacyPromiseRow("Delete your data anytime.")
                    privacyPromiseRow("You can turn Personal Style Memory off at any time.")
                    }
    }

    @ViewBuilder
    private var dataControlAndSettingsSections: some View {
                    Section("Data Control") {
                    Text(StyleMatchPrivacyMode.deletionRule)
                        .foregroundStyle(.secondary)

                    Button {
                        isShowingSharedLinks = true
                    } label: {
                        Label("Manage Shared Links", systemImage: "link")
                    }

                    Button {
                        outfitScanHistoryData = Data()
                        dataDeletionMessage = "Scan history was cleared from this phone."
                    } label: {
                        Label("Clear Scan History", systemImage: "photo.stack")
                    }

                    Button {
                        clearAIMemory()
                    } label: {
                        Label("Clear AI Memory", systemImage: "brain.head.profile")
                    }

                    Button {
                        shareAppContextWithChatGPT = false
                        dataDeletionMessage = "Personal Style Memory is off."
                    } label: {
                        Label("Turn Off Personal Style Memory", systemImage: "pause.circle")
                    }

                    Button {
                        dataDeletionMessage = "Export Data will be available when backup and cloud sync features are connected."
                    } label: {
                        Label("Export Data", systemImage: "square.and.arrow.up")
                    }

                    Button(role: .destructive) {
                        showDeleteDataConfirmation = true
                    } label: {
                        Label("Delete My Saved Data", systemImage: "trash")
                    }

                    if let dataDeletionMessage {
                        Text(dataDeletionMessage)
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    }
                }

                Section("App Settings") {
                    profileInfoRow("Notifications", "Available in a future update", icon: "bell.fill")

                    Button {
                        isShowingThemeSettings = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "paintpalette.fill")
                                .foregroundStyle(AppTab.profile.palette.accent)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Theme")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)

                                Text(activeTheme.title)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    profileInfoRow("Subscription", "Not active", icon: "crown.fill")
                    profileInfoRow("App Version", appVersionText, icon: "info.circle.fill")

                    Button {
                        dataDeletionMessage = "Terms of Use will open here when the public release page is connected."
                    } label: {
                        Label("Terms of Use", systemImage: "doc.text")
                    }

                    Button {
                        dataDeletionMessage = "Privacy Policy will open here when the public release page is connected."
                    } label: {
                        Label("Privacy Policy", systemImage: "hand.raised.fill")
                    }

                    Button {
                        isShowingSupport = true
                    } label: {
                        Label("Contact Support", systemImage: "questionmark.circle.fill")
                    }
                }

                Section {
                    Button {
                        saveProfileDraft()
                    } label: {
                        Label("Save Profile", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasUnsavedProfileChanges)

                    Text(profileSaveStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                    Section {
                    Color.clear
                        .frame(height: 180)
                        .accessibilityHidden(true)
                    }
                    .listRowBackground(Color.clear)
    }

    private var profileCompletenessSection: some View {
        Section("Profile Completeness") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("\(profileCompleteness)% Complete")
                        .font(.title2)
                        .fontWeight(.bold)

                    Spacer()
                }

                ProgressView(value: Double(profileCompleteness), total: 100)
                    .tint(AppTab.profile.palette.accent)

                if missingProfileFields.isEmpty {
                    Label("Your profile is ready for personalized recommendations.", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    Text("Missing:")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)

                    ForEach(missingProfileFields, id: \.self) { field in
                        Label(field, systemImage: "square")
                            .font(.subheadline)
                    }
                }

                Text("Completing these improves recommendations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var accountSection: some View {
        ProfileAccountSection(
            selectedAccountMode: selectedAccountMode,
            accountStatusTitle: accountStatusTitle,
            accountIcon: accountIcon,
            accountSyncEnabled: $accountSyncEnabled,
            guestDataLinkedToApple: guestDataLinkedToApple,
            guestDataTransferSummary: guestDataTransferSummary,
            isAccountRequestInFlight: isAccountRequestInFlight,
            isPreparingAccountDeletion: $isPreparingAccountDeletion,
            showSignOutConfirmation: $showSignOutConfirmation,
            showDeleteAccountConfirmation: $showDeleteAccountConfirmation,
            prepareAppleRequest: prepareAppleRequest,
            handleAppleSignIn: handleAppleSignIn,
            handleDeletionAuthorization: handleDeletionAuthorization,
            cancelDeletionAuthorization: {
                pendingAppleNonce = nil
            }
        )
    }

    private var activeTheme: StyleMatchAppTheme {
        StyleMatchAppTheme(rawValue: selectedAppTheme) ?? .system
    }

    private var selectedDraftSizeCategory: SizeProfileCategory {
        SizeProfileCategory.resolved(from: profileDraft.sizeCategory)
    }

    private var profileDraftSizeSummary: String {
        summaryText(for: profileDraft)
    }

    private var profileSaveStatusText: String {
        if hasUnsavedProfileChanges {
            return "You have unsaved changes. Tap Save Profile before leaving."
        }

        guard !profileLastSavedAt.isEmpty else {
            return "Tap Save Profile after editing so your stylist, closet, shopping, and size recommendations use the latest information."
        }

        let syncText = accountSyncEnabled
            ? (profileNeedsCloudSync ? "Saved locally and ready to sync when cloud sync is available." : "Saved locally and sync-ready.")
            : "Saved locally on this phone."
        return "\(syncText) Last saved: \(formattedProfileSavedDate)."
    }

    private var formattedProfileSavedDate: String {
        guard let date = ISO8601DateFormatter().date(from: profileLastSavedAt) else {
            return "recently"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var accountIcon: String {
        switch selectedAccountMode {
        case .guest:
            return "person"
        case .apple:
            return "apple.logo"
        case .email:
            return "envelope"
        }
    }

    private var accountStatusTitle: String {
        switch selectedAccountMode {
        case .guest:
            return "Guest Mode Active"
        case .apple:
            return "Signed in with Apple"
        case .email:
            return "Account"
        }
    }

    private enum PantsMeasurementField {
        case waist
        case inseam
    }

    private func draftBinding(_ keyPath: WritableKeyPath<ProfileEditDraft, String>) -> Binding<String> {
        Binding {
            profileDraft[keyPath: keyPath]
        } set: { newValue in
            profileDraft[keyPath: keyPath] = newValue
            updateProfileDirtyState()
        }
    }

    private func sizeCategoryBinding() -> Binding<String> {
        Binding {
            profileDraft.sizeCategory
        } set: { newValue in
            let previousCategory = SizeProfileCategory.resolvedIfSet(from: profileDraft.sizeCategory)
            profileDraft.sizeCategory = newValue
            let newCategory = SizeProfileCategory.resolvedIfSet(from: newValue)
            if previousCategory != newCategory {
                resetSizeFieldsForCategorySwitch()
            } else {
                profileDraft.reconcileGeneratedPantsSize()
            }
            updateProfileDirtyState()
        }
    }

    private func resetSizeFieldsForCategorySwitch() {
        profileDraft.shirtSize = ""
        profileDraft.pantsSize = ""
        profileDraft.dressSize = ""
        profileDraft.waistSize = ""
        profileDraft.inseamLength = ""
        profileDraft.neckSize = ""
        profileDraft.sleeveLength = ""
        profileDraft.shoeSize = ""
        profileDraft.fitPreference = ""
        pantsSizeLastEditSource = .manual
        showsAdditionalMeasurements = false
    }

    private func pantsMeasurementBinding(
        _ keyPath: WritableKeyPath<ProfileEditDraft, String>,
        field: PantsMeasurementField
    ) -> Binding<String> {
        Binding {
            profileDraft[keyPath: keyPath]
        } set: { newValue in
            switch field {
            case .waist:
                applyManualPantsWaist(newValue)
            case .inseam:
                applyManualPantsInseam(newValue)
            }
        }
    }

    private func applyPantsSizePickerSelection(_ selection: String) {
        var state = PantsSizeFieldState(
            pantsSize: profileDraft.pantsSize,
            waistSize: profileDraft.waistSize,
            inseamLength: profileDraft.inseamLength,
            lastEditSource: pantsSizeLastEditSource
        )
        state.applyPickerSelection(selection)
        profileDraft.pantsSize = state.pantsSize
        profileDraft.waistSize = state.waistSize
        profileDraft.inseamLength = state.inseamLength
        pantsSizeLastEditSource = state.lastEditSource
        updateProfileDirtyState()
    }

    private func applyManualPantsWaist(_ value: String) {
        var state = PantsSizeFieldState(
            pantsSize: profileDraft.pantsSize,
            waistSize: profileDraft.waistSize,
            inseamLength: profileDraft.inseamLength,
            lastEditSource: pantsSizeLastEditSource
        )
        state.applyManualWaist(value)
        profileDraft.pantsSize = state.pantsSize
        profileDraft.waistSize = state.waistSize
        profileDraft.inseamLength = state.inseamLength
        pantsSizeLastEditSource = state.lastEditSource
        updateProfileDirtyState()
    }

    private func applyManualPantsInseam(_ value: String) {
        var state = PantsSizeFieldState(
            pantsSize: profileDraft.pantsSize,
            waistSize: profileDraft.waistSize,
            inseamLength: profileDraft.inseamLength,
            lastEditSource: pantsSizeLastEditSource
        )
        state.applyManualInseam(value)
        profileDraft.pantsSize = state.pantsSize
        profileDraft.waistSize = state.waistSize
        profileDraft.inseamLength = state.inseamLength
        pantsSizeLastEditSource = state.lastEditSource
        updateProfileDirtyState()
    }

    private func logPantsPickerChange(_ newValue: String) {
        #if DEBUG
        let measurements = PantsSizeSync.measurements(from: newValue)
        let parsedWaist = measurements?.waist ?? "nil"
        let parsedInseam = measurements?.inseam ?? "nil"
        print("[ProfilePantsSize] PICKER changed pantsSize='\(newValue)' waist='\(profileDraft.waistSize)' inseam='\(profileDraft.inseamLength)' parsedWaist='\(parsedWaist)' parsedInseam='\(parsedInseam)' source='\(pantsSizeLastEditSource.rawValue)'")
        #endif
    }

    private func profileDraftField(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)

            TextField(prompt, text: text, axis: .vertical)
                .textInputAutocapitalization(.words)
                .lineLimit(1...3)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func sizeFields(for category: SizeProfileCategory) -> some View {
        switch category {
        case .men:
            Picker("Men's shirt size", selection: draftBinding(\.shirtSize)) {
                Text("Clear").tag("")
                ForEach(optionsIncludingCurrent(shirtSizeOptions, current: profileDraft.shirtSize), id: \.self) { size in
                    Text(size).tag(size)
                }
            }

            profileDraftField("Waist", text: pantsMeasurementBinding(\.waistSize, field: .waist), prompt: "e.g. 36")
                .keyboardType(.numbersAndPunctuation)
            profileDraftField("Inseam / Length", text: pantsMeasurementBinding(\.inseamLength, field: .inseam), prompt: "e.g. 32")
                .keyboardType(.numbersAndPunctuation)
            generatedPantsSizeRow(for: profileDraft)

            DisclosureGroup("Additional Measurements", isExpanded: $showsAdditionalMeasurements) {
                profileDraftField("Neck Size", text: draftBinding(\.neckSize), prompt: "Optional")
                    .keyboardType(.numbersAndPunctuation)
                profileDraftField("Sleeve Length", text: draftBinding(\.sleeveLength), prompt: "Optional")
                    .keyboardType(.numbersAndPunctuation)
            }

            Picker("Men's shoe size", selection: draftBinding(\.shoeSize)) {
                Text("Clear").tag("")
                ForEach(optionsIncludingCurrent(shoeSizeOptions, current: profileDraft.shoeSize), id: \.self) { size in
                    Text(size).tag(size)
                }
            }

            fitPicker
        case .women:
            Picker("Women's top size", selection: draftBinding(\.shirtSize)) {
                Text("Clear").tag("")
                ForEach(optionsIncludingCurrent(womenTopSizeOptions, current: profileDraft.shirtSize), id: \.self) { size in
                    Text(size).tag(size)
                }
            }

            Picker("Women's bottoms size", selection: draftBinding(\.pantsSize)) {
                Text("Clear").tag("")
                ForEach(optionsIncludingCurrent(womenBottomSizeOptions, current: profileDraft.pantsSize), id: \.self) { size in
                    Text(size).tag(size)
                }
            }

            Picker("Dress size", selection: draftBinding(\.dressSize)) {
                Text("Clear").tag("")
                ForEach(optionsIncludingCurrent(dressSizeOptions, current: profileDraft.dressSize), id: \.self) { size in
                    Text(size).tag(size)
                }
            }

            Picker("Women's shoe size", selection: draftBinding(\.shoeSize)) {
                Text("Clear").tag("")
                ForEach(optionsIncludingCurrent(womenShoeSizeOptions, current: profileDraft.shoeSize), id: \.self) { size in
                    Text(size).tag(size)
                }
            }

            fitPicker
        case .unisex:
            Picker("Unisex top size", selection: draftBinding(\.shirtSize)) {
                Text("Clear").tag("")
                ForEach(optionsIncludingCurrent(shirtSizeOptions, current: profileDraft.shirtSize), id: \.self) { size in
                    Text(size).tag(size)
                }
            }

            profileDraftField("Waist", text: pantsMeasurementBinding(\.waistSize, field: .waist), prompt: "Optional")
                .keyboardType(.numbersAndPunctuation)
            profileDraftField("Inseam / Length", text: pantsMeasurementBinding(\.inseamLength, field: .inseam), prompt: "Optional")
                .keyboardType(.numbersAndPunctuation)
            generatedPantsSizeRow(for: profileDraft)

            Picker("Shoe size", selection: draftBinding(\.shoeSize)) {
                Text("Clear").tag("")
                ForEach(optionsIncludingCurrent(shoeSizeOptions, current: profileDraft.shoeSize), id: \.self) { size in
                    Text(size).tag(size)
                }
            }

            fitPicker
        case .kidsYouth:
            Picker("Kids / youth top size", selection: draftBinding(\.shirtSize)) {
                Text("Clear").tag("")
                ForEach(optionsIncludingCurrent(kidsYouthSizeOptions, current: profileDraft.shirtSize), id: \.self) { size in
                    Text(size).tag(size)
                }
            }

            Picker("Kids / youth bottoms size", selection: draftBinding(\.pantsSize)) {
                Text("Clear").tag("")
                ForEach(optionsIncludingCurrent(kidsYouthSizeOptions, current: profileDraft.pantsSize), id: \.self) { size in
                    Text(size).tag(size)
                }
            }

            Picker("Kids / youth shoe size", selection: draftBinding(\.shoeSize)) {
                Text("Clear").tag("")
                ForEach(optionsIncludingCurrent(youthShoeSizeOptions, current: profileDraft.shoeSize), id: \.self) { size in
                    Text(size).tag(size)
                }
            }

            fitPicker

            Label("Kids/Youth sizing is ready for later family profile support. Keep this private and update only when needed.", systemImage: "person.2.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func generatedPantsSizeRow(for draft: ProfileEditDraft) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Generated Pants Size")
                .foregroundStyle(.primary)
            Spacer()
            Text(draft.generatedPantsDisplay ?? "Add waist and inseam")
                .foregroundStyle(draft.generatedPantsDisplay == nil ? .secondary : .primary)
                .fontWeight(draft.generatedPantsDisplay == nil ? .regular : .semibold)
        }
        .accessibilityElement(children: .combine)
    }

    private func sizeProfileSummaryCard(for draft: ProfileEditDraft) -> some View {
        let rows = draft.sizeSummaryRows
        return VStack(alignment: .leading, spacing: 12) {
            Text("Your Size Profile")
                .font(.headline)
            if rows.isEmpty {
                Text("No sizes saved yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Add only the sizes you want StyleMatch Pro to remember.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.label)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(row.value)
                            .fontWeight(.semibold)
                            .multilineTextAlignment(.trailing)
                    }
                    .font(.subheadline)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var fitPicker: some View {
        Picker("Preferred fit", selection: draftBinding(\.fitPreference)) {
            Text("Clear").tag("")
            ForEach(optionsIncludingCurrent(fitPreferenceOptions, current: profileDraft.fitPreference), id: \.self) { fit in
                Text(fit).tag(fit)
            }
        }
    }

    private func optionsIncludingCurrent(_ options: [String], current: String) -> [String] {
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !options.contains(trimmed) else {
            return options
        }
        return [trimmed] + options
    }

    private var missingProfileFields: [String] {
        var fields: [String] = []

        if neckSize.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields.append("Neck Size")
        }

        if sleeveLength.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields.append("Sleeve Length")
        }

        if favoriteStores.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields.append("Favorite Stores")
        }

        if weatherCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields.append("Location")
        }

        return fields
    }

    private var profileCompleteness: Int {
        ProfileStore.profileCompletenessPercentage(ProfileStore().currentProfile)
    }

    private var savedScanCount: Int {
        guard !outfitScanHistoryData.isEmpty,
              let history = try? JSONDecoder().decode([String: ProfileStoredScan].self, from: outfitScanHistoryData) else {
            return 0
        }

        return history.count
    }

    private var closetItemCount: Int {
        guard !closetItemsData.isEmpty,
              let items = try? JSONDecoder().decode([ClosetItem].self, from: closetItemsData) else {
            return 0
        }

        return items.count
    }

    private var aiConfidence: Int {
        min(98, 82 + min(savedScanCount, 8) + min(closetItemCount, 8) + (shareAppContextWithChatGPT ? 4 : 0))
    }

    private var weatherStatusText: String {
        weatherSource.localizedCaseInsensitiveContains("live") ? "Live weather active" : "Showing saved weather"
    }

    private var locationPermissionText: String {
        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return "Allowed"
        case .denied, .restricted:
            return "Off"
        case .notDetermined:
            return "Ask when needed"
        @unknown default:
            return "Unknown"
        }
    }

    private var weatherLastUpdatedText: String {
        guard liveWeatherUpdatedAt > 0 else {
            return "Not updated yet"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: liveWeatherUpdatedAt))
    }

    private var appVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Beta"
        return "\(version) (\(build))"
    }

    private func cleanValue(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    @ViewBuilder
    private func profileInfoRow(
        _ title: String,
        _ value: String,
        icon: String,
        accessibilityLabel: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        let content = HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(AppTab.profile.palette.accent)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(3)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())

        if let action {
            Button(action: action) {
                content
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel ?? "\(title), \(value)")
            .accessibilityAddTraits(.isButton)
        } else {
            content
        }
    }

    private func privacyPromiseRow(_ text: String) -> some View {
        Label {
            Text(text)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }

    private func useGuestMode(message: String = "Guest mode is active. Your data stays on this phone.") {
        AccountScopedStorage.switchUser(
            from: AccountScopedStorage.activePresentationUserID(),
            to: "guest",
            transferSourceData: false
        )
        customerAccountMode = CustomerAccountMode.guest.rawValue
        customerAccountEmail = ""
        customerAppleUserID = ""
        accountSyncEnabled = false
        guestDataLinkedToApple = false
        guestDataTransferSummary = ""
        loadProfileDraft(force: true)
        dataDeletionMessage = message
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                dataDeletionMessage = "Apple sign-in did not return a valid account. Please try again."
                return
            }

            guard let nonce = pendingAppleNonce else {
                dataDeletionMessage = StyleMatchAccountError.authorizationIncomplete.localizedDescription
                return
            }
            let payload = StyleMatchAppleSignInPayload(
                userID: credential.user,
                email: credential.email,
                givenName: credential.fullName?.givenName,
                familyName: credential.fullName?.familyName,
                sourceUserID: AccountScopedStorage.activePresentationUserID()
            )

            pendingAppleNonce = nil
            isAccountRequestInFlight = true
            Task {
                do {
                    let session = try await StyleMatchAccountClient().exchange(
                        authorizationCode: credential.authorizationCode,
                        identityToken: credential.identityToken,
                        nonce: nonce
                    )
                    try StyleMatchAccountSessionStore.save(session)
                    if payload.sourceUserID == "guest",
                       hasTransferableGuestData,
                       !AccountScopedStorage.hasUserData(for: payload.userID) {
                        pendingAppleSignIn = payload
                        showGuestTransferOffer = true
                    } else {
                        completeAppleSignIn(payload, transferGuestData: false)
                    }
                    dataDeletionMessage = "Signed in with Apple. Your account session is protected."
                } catch {
                    StyleMatchAccountSessionStore.delete()
                    dataDeletionMessage = (error as? StyleMatchAccountError)?.localizedDescription
                        ?? StyleMatchAccountError.serviceUnavailable.localizedDescription
                }
                isAccountRequestInFlight = false
            }
        case .failure:
            pendingAppleNonce = nil
            isAccountRequestInFlight = false
            dataDeletionMessage = StyleMatchAccountError.authorizationIncomplete.localizedDescription
        }
    }

    private func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        do {
            let nonce = try StyleMatchAppleNonce.make()
            pendingAppleNonce = nonce
            request.nonce = StyleMatchAppleNonce.hash(nonce)
            dataDeletionMessage = nil
        } catch {
            pendingAppleNonce = nil
            dataDeletionMessage = StyleMatchAccountError.authorizationIncomplete.localizedDescription
        }
    }

    private func signOut() {
        let accountSession = StyleMatchAccountSessionStore.load()
        isAccountRequestInFlight = true
        Task {
            var remoteSessionClosed = true
            if let accountSession {
                do {
                    try await StyleMatchAccountClient().signOut(session: accountSession)
                } catch {
                    remoteSessionClosed = false
                }
            }
            StyleMatchAccountSessionStore.delete()
            useGuestMode(
                message: remoteSessionClosed
                    ? "You’re signed out. Your Apple account data remains separate on this phone."
                    : "You’re signed out on this phone. The previous server session will expire automatically."
            )
            isAccountRequestInFlight = false
        }
    }

    private func handleDeletionAuthorization(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let nonce = pendingAppleNonce else {
                dataDeletionMessage = StyleMatchAccountError.authorizationIncomplete.localizedDescription
                return
            }
            guard PersonalStylistStorage.normalizedUserID(credential.user)
                    == PersonalStylistStorage.normalizedUserID(customerAppleUserID) else {
                pendingAppleNonce = nil
                dataDeletionMessage = "Use the same Apple account that is currently connected to StyleMatch Pro."
                return
            }

            pendingAppleNonce = nil
            isAccountRequestInFlight = true
            Task {
                do {
                    let session = try await StyleMatchAccountClient().exchange(
                        authorizationCode: credential.authorizationCode,
                        identityToken: credential.identityToken,
                        nonce: nonce
                    )
                    try StyleMatchAccountSessionStore.save(session)
                    try await StyleMatchAccountClient().deleteAccount(session: session)
                    StyleMatchAccountSessionStore.delete()
                    isPreparingAccountDeletion = false
                    deleteSavedData()
                    dataDeletionMessage = "Your StyleMatch Pro account and saved data were deleted."
                } catch {
                    dataDeletionMessage = (error as? StyleMatchAccountError)?.localizedDescription
                        ?? StyleMatchAccountError.serviceUnavailable.localizedDescription
                }
                isAccountRequestInFlight = false
            }
        case .failure:
            pendingAppleNonce = nil
            isAccountRequestInFlight = false
            dataDeletionMessage = StyleMatchAccountError.authorizationIncomplete.localizedDescription
        }
    }

    private var hasTransferableGuestData: Bool {
        !outfitScanHistoryData.isEmpty
        || !closetItemsData.isEmpty
        || LoginWelcomeProfileData.hasIntentionalProfileValues(
            favoriteOutfits: favoriteOutfits,
            stylePreferences: stylePreferences,
            favoriteColors: favoriteColors,
            profileName: name
        )
    }

    private func completePendingAppleSignIn(transferGuestData: Bool) {
        guard let pendingAppleSignIn else { return }
        completeAppleSignIn(pendingAppleSignIn, transferGuestData: transferGuestData)
        self.pendingAppleSignIn = nil
    }

    private func completeAppleSignIn(_ payload: StyleMatchAppleSignInPayload, transferGuestData: Bool) {
        var transferred: [String] = []

        if transferGuestData, !outfitScanHistoryData.isEmpty {
            transferred.append("scan history")
        }

        let hasIntentionalProfileSave = FounderProfileDefaultsMigration.hasIntentionalProfileSave()

        if transferGuestData, hasIntentionalProfileSave,
           cleanOptional(favoriteOutfits) != nil {
            transferred.append("favorites")
        }

        if transferGuestData, !closetItemsData.isEmpty {
            transferred.append("closet")
        }

        if transferGuestData, hasIntentionalProfileSave,
           cleanOptional(stylePreferences) != nil || cleanOptional(favoriteColors) != nil {
            transferred.append("style preferences")
        }

        if transferGuestData, hasIntentionalProfileSave,
           StyleMatchAccountNameResolver.profileGivenName(from: name) != nil {
            transferred.append("profile")
        }

        AccountScopedStorage.switchUser(
            from: payload.sourceUserID,
            to: payload.userID,
            transferSourceData: transferGuestData
        )
        customerAccountMode = CustomerAccountMode.apple.rawValue
        customerAppleUserID = payload.userID
        accountSyncEnabled = true

        let restoredLocalName = UserDefaults.standard.string(forKey: "profileName")
        let appliedProfile = StyleMatchAppleCredentialProfileApplier.applyAppleCredential(
            userID: payload.userID,
            email: payload.email,
            appleGivenName: payload.givenName,
            appleFamilyName: payload.familyName,
            localDisplayName: restoredLocalName
        )
        logProfileNameEvent(
            stage: "sign-in",
            source: appliedProfile.source,
            appleNameProvided: payload.givenName != nil || payload.familyName != nil,
            localNamePresent: StyleMatchAccountNameResolver.clean(restoredLocalName) != nil,
            storedNamePresent: appliedProfile.givenName != nil
        )

        customerAccountEmail = appliedProfile.email ?? ""
        name = appliedProfile.displayName ?? restoredLocalName ?? ""

        guestDataLinkedToApple = true
        if transferGuestData {
            guestDataTransferSummary = transferred.isEmpty
                ? "Apple sign-in is active. No guest style data needed to be transferred."
                : "Transferred guest \(transferred.joined(separator: ", ")) to Apple sign-in on this device."
        } else if payload.sourceUserID == "guest" {
            guestDataTransferSummary = "Apple sign-in is active. Local guest data remains separate on this iPhone."
        } else {
            guestDataTransferSummary = "Apple sign-in is active. This account's saved data is now loaded."
        }
        loadProfileDraft(force: true)
        dataDeletionMessage = guestDataTransferSummary
    }

    private func attemptProfileExit() {
        if hasUnsavedProfileChanges {
            showUnsavedProfileWarning = true
        } else {
            selectedTab = .home
        }
    }

    private func loadProfileDraftIfNeeded() {
        guard !hasLoadedProfileDraft else { return }
        loadProfileDraft(force: true)
        hasLoadedProfileDraft = true
    }

    private func loadProfileDraft(force: Bool = false) {
        guard force || !hasUnsavedProfileChanges else { return }
        restoreProfileNameForDraftLoad()
        let draft = currentStoredProfileDraft()
        profileDraft = draft
        savedProfileDraft = draft
        pantsSizeLastEditSource = .manual
        hasUnsavedProfileChanges = false
    }

    private func restoreProfileNameForDraftLoad() {
        let profileStore = ProfileStore(userId: activeAccountUserID)
        let resolvedName = StyleMatchAccountNameResolver.resolveStoredProfileThenLocal(
            storedProfileGivenName: profileStore.currentProfile.givenName,
            localDisplayName: name
        )
        logProfileNameEvent(
            stage: "draft-load",
            source: resolvedName.source,
            appleNameProvided: false,
            localNamePresent: StyleMatchAccountNameResolver.clean(name) != nil,
            storedNamePresent: profileStore.currentProfile.givenName != nil
        )
        if let displayName = resolvedName.displayName,
           StyleMatchAccountNameResolver.clean(name) != displayName {
            name = displayName
        }
    }

    private func currentStoredProfileDraft() -> ProfileEditDraft {
        var draft = ProfileEditDraft(
            name: name,
            favoriteColors: favoriteColors,
            favoriteBrands: favoriteBrands,
            favoriteStores: favoriteStores,
            budget: budget,
            styleGoals: styleGoals,
            stylePreferences: stylePreferences,
            occasions: occasions,
            outfitDislikes: outfitDislikes,
            clothingPreferences: clothingPreferences,
            pastPurchases: pastPurchases,
            favoriteOutfits: favoriteOutfits,
            closetInventory: closetInventory,
            declaredUndertone: ProfileStore(userId: activeAccountUserID).currentProfile.declaredUndertone?.rawValue ?? "",
            preferredNeutrals: preferredNeutrals,
            preferredAccentColors: preferredAccentColors,
            comfortPreferences: comfortPreferences,
            preferredPantRise: preferredPantRise,
            shoppingFocus: shoppingFocus,
            preferredShoppingCategories: preferredShoppingCategories,
            workSetting: workSetting,
            travelFrequency: travelFrequency,
            hobbiesActivities: hobbiesActivities,
            stylistVoice: stylistVoice,
            sizeCategory: sizeCategory,
            shirtSize: shirtSize,
            pantsSize: pantsSize,
            dressSize: dressSize,
            waistSize: waistSize,
            inseamLength: inseamLength,
            neckSize: neckSize,
            sleeveLength: sleeveLength,
            shoeSize: shoeSize,
            fitPreference: fitPreference
        )
        draft.reconcileGeneratedPantsSize()
        return draft
    }

    private func updateProfileDirtyState() {
        hasUnsavedProfileChanges = profileDraft != savedProfileDraft
    }

    private func saveProfileDraft() {
        var draft = profileDraft
        draft.normalize()
        draft.reconcileGeneratedPantsSize()
        let profileStoreForName = ProfileStore(userId: activeAccountUserID)
        draft.name = StyleMatchAccountNameResolver.mergeDraftName(
            draft.name,
            storedProfileGivenName: profileStoreForName.currentProfile.givenName
        )
        logProfileNameEvent(
            stage: "save",
            source: StyleMatchAccountNameResolver.clean(draft.name) == nil ? .unavailable : .localDisplayName,
            appleNameProvided: false,
            localNamePresent: StyleMatchAccountNameResolver.clean(draft.name) != nil,
            storedNamePresent: profileStoreForName.currentProfile.givenName != nil
        )
        logPantsSave(draft)

        name = draft.name
        favoriteColors = draft.favoriteColors
        favoriteBrands = draft.favoriteBrands
        favoriteStores = draft.favoriteStores
        budget = draft.budget
        styleGoals = draft.styleGoals
        stylePreferences = draft.stylePreferences
        occasions = draft.occasions
        outfitDislikes = draft.outfitDislikes
        clothingPreferences = draft.clothingPreferences
        pastPurchases = draft.pastPurchases
        favoriteOutfits = draft.favoriteOutfits
        closetInventory = draft.closetInventory
        preferredNeutrals = draft.preferredNeutrals
        preferredAccentColors = draft.preferredAccentColors
        comfortPreferences = draft.comfortPreferences
        preferredPantRise = draft.preferredPantRise
        shoppingFocus = draft.shoppingFocus
        preferredShoppingCategories = draft.preferredShoppingCategories
        workSetting = draft.workSetting
        travelFrequency = draft.travelFrequency
        hobbiesActivities = draft.hobbiesActivities
        stylistVoice = draft.stylistVoice
        sizeCategory = draft.sizeCategory
        shirtSize = draft.shirtSize
        pantsSize = draft.pantsSize
        dressSize = draft.dressSize
        waistSize = draft.waistSize
        inseamLength = draft.inseamLength
        neckSize = draft.neckSize
        sleeveLength = draft.sleeveLength
        shoeSize = draft.shoeSize
        fitPreference = draft.fitPreference
        sizeProfile = summaryText(for: draft)
        profileLastSavedAt = ISO8601DateFormatter().string(from: Date())
        profileNeedsCloudSync = accountSyncEnabled
        syncPersonalStylistProfile(from: draft)

        let savedDraft = currentStoredProfileDraft()
        profileDraft = savedDraft
        savedProfileDraft = savedDraft
        pantsSizeLastEditSource = .manual
        hasUnsavedProfileChanges = false
        dataDeletionMessage = accountSyncEnabled
            ? "Profile saved locally and marked for account sync when cloud sync is available."
            : "Profile saved locally on this phone."
        showProfileSavedConfirmation = true
        if voiceControlsEnabled, voiceAssistantEnabled {
            voiceAssistant.speak(VoiceScriptBuilder.profileSaved())
        }
    }

    private func logPantsSave(_ draft: ProfileEditDraft) {
        #if DEBUG
        print("[ProfilePantsSize] SAVE pantsSize='\(draft.pantsSize)' waist='\(draft.waistSize)' inseam='\(draft.inseamLength)' source='\(pantsSizeLastEditSource.rawValue)'")
        #endif
    }


    private func logProfileNameEvent(
        stage: String,
        source: StyleMatchAccountNameResolver.Source,
        appleNameProvided: Bool,
        localNamePresent: Bool,
        storedNamePresent: Bool
    ) {
        #if DEBUG
        print("[ProfileName] \(stage) source=\(source.rawValue) appleNameProvided=\(appleNameProvided) localNamePresent=\(localNamePresent) storedNamePresent=\(storedNamePresent)")
        #endif
    }

    private func syncPersonalStylistProfile(from draft: ProfileEditDraft) {
        let store = ProfileStore(userId: activeAccountUserID)
        var profile = store.currentProfile
        profile.givenName = StyleMatchAccountNameResolver.profileGivenName(from: draft.name) ?? profile.givenName
        profile.favoriteColors = splitProfileList(draft.favoriteColors)
        profile.dislikedColors = splitProfileList(draft.outfitDislikes)
        profile.favoriteBrands = splitProfileList(draft.favoriteBrands)
        profile.declaredUndertone = DeclaredUndertone.fromProfileInput(draft.declaredUndertone)
        profile.preferredFit = FitPreference.fromProfileInput(draft.fitPreference)
        profile.styleGoals = splitProfileList(draft.styleGoals)
        profile.preferredNeutrals = splitProfileList(draft.preferredNeutrals)
        profile.preferredAccentColors = splitProfileList(draft.preferredAccentColors)
        profile.comfortPreferences = splitProfileList(draft.comfortPreferences)
        profile.preferredPantRise = cleanOptional(draft.preferredPantRise) ?? ""
        profile.shoppingFocus = cleanOptional(draft.shoppingFocus) ?? ""
        profile.preferredShoppingCategories = splitProfileList(draft.preferredShoppingCategories)
        profile.workSetting = cleanOptional(draft.workSetting) ?? ""
        profile.travelFrequency = cleanOptional(draft.travelFrequency) ?? ""
        profile.hobbiesActivities = splitProfileList(draft.hobbiesActivities)
        profile.stylistVoice = cleanOptional(draft.stylistVoice) ?? ""
        profile.budgetRange = budgetRange(from: draft.budget)
        profile.climate = cleanOptional(weatherCondition) ?? ""
        profile.workDressCode = cleanOptional(dressCode) ?? ""
        profile.clothingSizes = ClothingSizes(
            shirtSize: cleanOptional(draft.shirtSize),
            pantSize: cleanOptional(draft.pantsSize),
            shoeSize: cleanOptional(draft.shoeSize),
            jacketSize: nil,
            dressSize: cleanOptional(draft.dressSize)
        )
        profile.lastUpdatedAt = Date()
        store.currentProfile = profile
        store.save()
    }

    private func summaryText(for draft: ProfileEditDraft) -> String {
        let rows = draft.sizeSummaryRows
        guard !rows.isEmpty else { return "No sizes saved yet" }
        return rows.map { "\($0.label): \($0.value)" }.joined(separator: "; ")
    }

    private func splitProfileList(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func cleanOptional(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func budgetRange(from text: String) -> BudgetRange {
        let values = text
            .components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted)
            .compactMap(Double.init)
        guard let first = values.first else {
            return .neutral
        }
        let minPrice = first
        let maxPrice = values.dropFirst().first ?? first
        let tier: String
        switch maxPrice {
        case 0..<75:
            tier = "Budget"
        case 75..<250:
            tier = "Mid"
        default:
            tier = "Premium"
        }
        return BudgetRange(minPrice: minPrice, maxPrice: maxPrice, preferredTier: tier)
    }

    private func deleteSavedData() {
        PrivacyDataManager.shared.deleteAllLocalCustomerData()
        customerAccountMode = CustomerAccountMode.guest.rawValue
        customerAccountEmail = ""
        customerAppleUserID = ""
        accountSyncEnabled = false
        name = ""
        favoriteColors = ""
        favoriteBrands = ""
        favoriteStores = ""
        budget = ""
        styleGoals = ""
        sizeProfile = ""
        sizeCategory = ""
        stylePreferences = ""
        occasions = ""
        plannedOccasion = ""
        dressCode = ""
        occasionFormality = ""
        weather = ""
        weatherCity = ""
        weatherCondition = ""
        weatherSource = ""
        pastPurchases = ""
        favoriteOutfits = ""
        closetInventory = ""
        preferredNeutrals = ""
        preferredAccentColors = ""
        comfortPreferences = ""
        preferredPantRise = ""
        shoppingFocus = ""
        preferredShoppingCategories = ""
        workSetting = ""
        travelFrequency = ""
        hobbiesActivities = ""
        stylistVoice = ""
        styleConsultationCompletedAt = ""
        shareAppContextWithChatGPT = false
        outfitDislikes = ""
        clothingPreferences = ""
        shirtSize = ""
        pantsSize = ""
        dressSize = ""
        waistSize = ""
        inseamLength = ""
        neckSize = ""
        sleeveLength = ""
        shoeSize = ""
        fitPreference = ""
        profileLastSavedAt = ""
        profileNeedsCloudSync = false
        loadProfileDraft(force: true)
        dataDeletionMessage = "Saved data was deleted from this phone."
    }

    private func clearAIMemory() {
        shareAppContextWithChatGPT = false
        favoriteColors = ""
        favoriteBrands = ""
        favoriteStores = ""
        budget = ""
        styleGoals = ""
        stylePreferences = ""
        occasions = ""
        favoriteOutfits = ""
        outfitDislikes = ""
        clothingPreferences = ""
        preferredNeutrals = ""
        preferredAccentColors = ""
        comfortPreferences = ""
        preferredPantRise = ""
        shoppingFocus = ""
        preferredShoppingCategories = ""
        workSetting = ""
        travelFrequency = ""
        hobbiesActivities = ""
        stylistVoice = ""
        styleConsultationCompletedAt = ""
        loadProfileDraft(force: true)
        dataDeletionMessage = "Personal Style Memory was cleared and turned off."
    }

    private func clearColorAndFitProfile() {
        profileDraft.declaredUndertone = ""
        profileDraft.fitPreference = ""
        updateProfileDirtyState()
    }

    private func completeStyleConsultation() {
        styleConsultationCompletedAt = ISO8601DateFormatter().string(from: Date())
        saveProfileDraft()
        isShowingStyleConsultation = false
    }

    private func resetStyleConsultation() {
        profileDraft.styleGoals = ""
        profileDraft.declaredUndertone = ""
        profileDraft.preferredNeutrals = ""
        profileDraft.preferredAccentColors = ""
        profileDraft.comfortPreferences = ""
        profileDraft.preferredPantRise = ""
        profileDraft.shoppingFocus = ""
        profileDraft.preferredShoppingCategories = ""
        profileDraft.workSetting = ""
        profileDraft.travelFrequency = ""
        profileDraft.hobbiesActivities = ""
        profileDraft.stylistVoice = ""
        styleConsultationCompletedAt = ""
        saveProfileDraft()
    }

    private func updateSizeProfileSummary() {
        sizeProfile = summaryText(for: currentStoredProfileDraft())
    }
}

private struct StyleConsultationSheet: View {
    @Binding var draft: ProfileEditDraft
    let styleIdentityOptions: [String]
    let styleGoalOptions: [String]
    let fitPreferenceOptions: [String]
    let undertoneOptions: [DeclaredUndertone]
    let neutralColorOptions: [String]
    let accentColorOptions: [String]
    let pantRiseOptions: [String]
    let comfortPreferenceOptions: [String]
    let shoppingFocusOptions: [String]
    let shoppingCategoryOptions: [String]
    let workSettingOptions: [String]
    let travelFrequencyOptions: [String]
    let stylistVoiceOptions: [String]
    let markDirty: () -> Void
    let complete: () -> Void
    let skip: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var focusedStep: StyleConsultationStep?
    @State private var step: StyleConsultationStep = .welcome

    private enum StyleConsultationStep: Int, CaseIterable, Identifiable {
        case welcome
        case styleIdentity
        case fitProfile
        case colorProfile
        case comfortProfile
        case shoppingProfile
        case lifestyleProfile
        case stylistVoice

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .welcome: "Welcome"
            case .styleIdentity: "Style Identity"
            case .fitProfile: "Fit Profile"
            case .colorProfile: "Color Profile"
            case .comfortProfile: "Comfort Profile"
            case .shoppingProfile: "Shopping Profile"
            case .lifestyleProfile: "Lifestyle Profile"
            case .stylistVoice: "Stylist Voice"
            }
        }

        var progressText: String {
            "Step \(rawValue + 1) of \(Self.allCases.count)"
        }

        var previous: StyleConsultationStep? {
            Self.allCases.first { $0.rawValue == rawValue - 1 }
        }

        var next: StyleConsultationStep? {
            Self.allCases.first { $0.rawValue == rawValue + 1 }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                stepHeader
                stepContent
                stepNavigation
            }
            .navigationTitle(step.title)
            .onAppear {
                focusedStep = step
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        skip()
                    }
                    .accessibilityHint("Closes the optional style consultation. Unsaved changes remain in your profile draft.")
                }
            }
        }
    }

    @ViewBuilder
    private var stepHeader: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(step.progressText)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Text("Optional. Skip anytime, finish later, or edit from Profile.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityFocused($focusedStep, equals: step)
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            Section {
                Text("Welcome to Your Style Consultation")
                    .font(.title2)
                    .fontWeight(.bold)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("Teach your stylist what you like, what feels comfortable, and how you shop. Your answers personalize advice and shopping recommendations only.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                StyleProfilePromiseView()
            }
        case .styleIdentity:
            Section("Style Identity") {
                Text("Choose the styles and goals that feel useful right now. You can leave anything blank.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                multiSelectGrid(options: styleIdentityOptions, keyPath: \.stylePreferences, accessibilityGroup: "style identity")
                multiSelectGrid(options: styleGoalOptions, keyPath: \.styleGoals, accessibilityGroup: "style goals")
            }
        case .fitProfile:
            Section("Fit Profile") {
                Picker("Preferred fit", selection: binding(\.fitPreference)) {
                    Text("Not provided").tag("")
                    ForEach(fitPreferenceOptions, id: \.self) { Text($0).tag($0) }
                }
                profileValueRow("Shirt size", draft.shirtSize)
                profileValueRow("Waist", draft.waistSize)
                profileValueRow("Inseam", draft.inseamLength)
                profileValueRow("Shoe size", draft.shoeSize)
                profileValueRow("Sleeve length", draft.sleeveLength)
                profileValueRow("Neck size", draft.neckSize)
                Picker("Preferred pant rise", selection: binding(\.preferredPantRise)) {
                    Text("Not provided").tag("")
                    ForEach(pantRiseOptions, id: \.self) { Text($0).tag($0) }
                }
                Text("Sizes come from your existing Size Profile so measurements stay in one place.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .colorProfile:
            Section("Color Profile") {
                profileDraftTextField("Favorite colors", keyPath: \.favoriteColors, prompt: "Navy, white, olive")
                profileDraftTextField("Avoided colors", keyPath: \.outfitDislikes, prompt: "Neon, bright orange")
                multiSelectGrid(options: neutralColorOptions, keyPath: \.preferredNeutrals, accessibilityGroup: "preferred neutrals")
                multiSelectGrid(options: accentColorOptions, keyPath: \.preferredAccentColors, accessibilityGroup: "preferred accent colors")
                Picker("Optional self-selected undertone", selection: binding(\.declaredUndertone)) {
                    Text("Not provided").tag("")
                    ForEach(undertoneOptions, id: \.rawValue) { undertone in
                        Text(undertone.displayName).tag(undertone.rawValue)
                    }
                }
                Text("Self-selected only. StyleMatch Pro does not estimate or infer undertone from images.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Color groups are optional and editable. If a color belongs in more than one group for you, keep both and adjust later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .comfortProfile:
            Section("Comfort Profile") {
                Text("Select practical fit and comfort notes your stylist should respect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                multiSelectGrid(options: comfortPreferenceOptions, keyPath: \.comfortPreferences, accessibilityGroup: "comfort preferences")
            }
        case .shoppingProfile:
            Section("Shopping Profile") {
                profileDraftTextField("Favorite brands", keyPath: \.favoriteBrands, prompt: "Nike, Ralph Lauren, Levi's")
                profileDraftTextField("Preferred retailers", keyPath: \.favoriteStores, prompt: "Macy's, Target, Nordstrom")
                profileDraftTextField("Budget range", keyPath: \.budget, prompt: "$50 - $200")
                Picker("Shopping preference", selection: binding(\.shoppingFocus)) {
                    Text("Not provided").tag("")
                    ForEach(shoppingFocusOptions, id: \.self) { Text($0).tag($0) }
                }
                multiSelectGrid(options: shoppingCategoryOptions, keyPath: \.preferredShoppingCategories, accessibilityGroup: "shopping categories")
            }
        case .lifestyleProfile:
            Section("Lifestyle Profile") {
                Picker("Work setting", selection: binding(\.workSetting)) {
                    Text("Not provided").tag("")
                    ForEach(workSettingOptions, id: \.self) { Text($0).tag($0) }
                }
                Text("Typical climate is managed in Weather Planning so location and climate stay in one place.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                profileDraftTextField("Common occasions", keyPath: \.occasions, prompt: "Work, travel, dinner")
                Picker("Travel frequency", selection: binding(\.travelFrequency)) {
                    Text("Not provided").tag("")
                    ForEach(travelFrequencyOptions, id: \.self) { Text($0).tag($0) }
                }
                profileDraftTextField("Hobbies or activities", keyPath: \.hobbiesActivities, prompt: "Gym, church, travel")
                Text("Keep this broad. Do not include sensitive employment details or precise location.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .stylistVoice:
            Section("Stylist Voice") {
                Picker("Stylist voice", selection: binding(\.stylistVoice)) {
                    Text("Not provided").tag("")
                    ForEach(stylistVoiceOptions, id: \.self) { Text($0).tag($0) }
                }
                Text("Stored for future coaching tone. This phase does not rewrite the AI assistant personality system.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var stepNavigation: some View {
        Section {
            navigationButtons
                .controlSize(.large)
                .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder
    private var navigationButtons: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 12) {
                backButton
                primaryNavigationButton
            }
        } else {
            HStack(spacing: 12) {
                backButton
                primaryNavigationButton
            }
        }
    }

    @ViewBuilder
    private var backButton: some View {
        if let previous = step.previous {
            Button("Back") {
                move(to: previous)
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            .accessibilityHint("Returns to the previous consultation step.")
        }
    }

    private var primaryNavigationButton: some View {
        Button(step.next == nil ? "Save" : "Continue") {
            if let next = step.next {
                move(to: next)
            } else {
                complete()
            }
        }
        .buttonStyle(.borderedProminent)
        .frame(maxWidth: .infinity)
        .accessibilityHint(step.next == nil ? "Saves the consultation and returns to Profile." : "Moves to the next consultation step.")
    }

    private func move(to nextStep: StyleConsultationStep) {
        step = nextStep
        focusedStep = nextStep
    }

    private func binding(_ keyPath: WritableKeyPath<ProfileEditDraft, String>) -> Binding<String> {
        Binding {
            draft[keyPath: keyPath]
        } set: { newValue in
            draft[keyPath: keyPath] = newValue
            markDirty()
        }
    }

    private func profileDraftTextField(_ title: String, keyPath: WritableKeyPath<ProfileEditDraft, String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
            TextField(prompt, text: binding(keyPath), axis: .vertical)
                .textInputAutocapitalization(.words)
                .lineLimit(1...3)
        }
        .padding(.vertical, 4)
    }

    private func profileValueRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Not set" : value)
                .foregroundStyle(.secondary)
        }
    }

    private func multiSelectGrid(options: [String], keyPath: WritableKeyPath<ProfileEditDraft, String>, accessibilityGroup: String) -> some View {
        let selected = selectedValues(for: keyPath)
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(options, id: \.self) { option in
                Button {
                    toggle(option, keyPath: keyPath)
                } label: {
                    Label(option, systemImage: selected.contains(option) ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 44, alignment: .leading)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(selected.contains(option) ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityLabel("\(option), \(accessibilityGroup)")
                .accessibilityValue(selected.contains(option) ? "Selected" : "Not selected")
                .accessibilityAddTraits(selected.contains(option) ? .isSelected : [])
                .accessibilityHint("Double tap to select or remove this preference.")
            }
        }
        .padding(.vertical, 4)
    }

    private func selectedValues(for keyPath: WritableKeyPath<ProfileEditDraft, String>) -> Set<String> {
        Set(draft[keyPath: keyPath]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
    }

    private func toggle(_ option: String, keyPath: WritableKeyPath<ProfileEditDraft, String>) {
        var values = selectedValues(for: keyPath)
        if values.contains(option) {
            values.remove(option)
        } else {
            values.insert(option)
        }
        draft[keyPath: keyPath] = values.sorted().joined(separator: ", ")
        markDirty()
    }
}

private struct StyleDNAScreen: View {
    let draft: ProfileEditDraft
    let consultationCompletedAt: String
    let edit: () -> Void
    let reset: () -> Void
    @State private var showResetConfirmation = false

    var body: some View {
        List {
            Section {
                Text("Style DNA summarizes only the preferences you have provided. Empty sections stay marked as unanswered, and these preferences personalize advice only; they do not change outfit scores.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                StyleProfilePromiseView()
            }

            styleDNASection(
                title: "Style Identity",
                icon: "sparkles",
                rows: [
                    ("Selected styles", draft.stylePreferences),
                    ("Primary goals", draft.styleGoals)
                ]
            )

            styleDNASection(
                title: "Preferred Fit",
                icon: "tshirt.fill",
                rows: [
                    ("Fit", draft.fitPreference),
                    ("Pant rise", draft.preferredPantRise),
                    ("Shirt size", draft.shirtSize),
                    ("Waist", draft.waistSize),
                    ("Inseam", draft.inseamLength),
                    ("Shoe size", draft.shoeSize),
                    ("Sleeve length", draft.sleeveLength),
                    ("Neck size", draft.neckSize)
                ]
            )

            styleDNASection(
                title: "Color Palette",
                icon: "paintpalette.fill",
                rows: [
                    ("Favorite colors", draft.favoriteColors),
                    ("Avoided colors", draft.outfitDislikes),
                    ("Preferred neutrals", draft.preferredNeutrals),
                    ("Preferred accents", draft.preferredAccentColors),
                    ("Self-selected undertone", undertoneDisplayName)
                ]
            )

            styleDNASection(
                title: "Comfort Preferences",
                icon: "hand.thumbsup.fill",
                rows: [
                    ("Comfort notes", draft.comfortPreferences)
                ]
            )

            styleDNASection(
                title: "Favorite Brands",
                icon: "tag.fill",
                rows: [
                    ("Brands", draft.favoriteBrands),
                    ("Retailers", draft.favoriteStores)
                ]
            )

            styleDNASection(
                title: "Budget",
                icon: "creditcard.fill",
                rows: [
                    ("Budget range", draft.budget),
                    ("Shopping preference", draft.shoppingFocus),
                    ("Shopping categories", draft.preferredShoppingCategories)
                ]
            )

            styleDNASection(
                title: "Lifestyle Preferences",
                icon: "calendar.badge.clock",
                rows: [
                    ("Work setting", draft.workSetting),
                    ("Common occasions", draft.occasions),
                    ("Travel frequency", draft.travelFrequency),
                    ("Hobbies or activities", draft.hobbiesActivities)
                ]
            )

            styleDNASection(
                title: "Stylist Voice",
                icon: "quote.bubble.fill",
                rows: [
                    ("Voice", draft.stylistVoice)
                ]
            )

            styleDNASection(
                title: "Consultation Status",
                icon: "checkmark.seal.fill",
                rows: [
                    ("Status", consultationStatus)
                ]
            )

            Section {
                Button(role: .destructive) {
                    showResetConfirmation = true
                } label: {
                    Label("Reset Style DNA", systemImage: "arrow.counterclockwise")
                }
                .accessibilityLabel("Reset Style DNA")
                .accessibilityHint("Clears optional Style DNA answers after confirmation.")
            } footer: {
                Text("Reset clears only your optional consultation answers. Saved scans and outfit scores stay unchanged.")
            }
        }
        .navigationTitle("Style DNA")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Reset Style DNA?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Style DNA", role: .destructive) {
                reset()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears optional Style DNA answers only. Saved scans, account data, closet items, shopping data, and outfit scores stay unchanged.")
        }
    }

    private var undertoneDisplayName: String {
        DeclaredUndertone.fromProfileInput(draft.declaredUndertone)?.displayName ?? ""
    }

    private var consultationStatus: String {
        consultationCompletedAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "Completed"
    }

    private func styleDNASection(title: String, icon: String, rows: [(String, String)]) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: icon)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Edit", action: edit)
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Edit \(title)")
                        .accessibilityHint("Opens the Style Consultation flow so you can update this section.")
                }

                ForEach(rows, id: \.0) { row in
                    StyleDNARow(label: row.0, value: row.1)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct StyleProfilePromiseView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(.primary)
                    .accessibilityHidden(true)
                Text("Your Style, Your Rules")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
            }
            Text("Your profile is optional. It personalizes advice, recommendations, and style coaching. It never changes how your outfits are objectively scored.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

private struct StyleDNARow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            if trimmedValue.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "circle.dashed")
                        .accessibilityHidden(true)
                    Text("Not answered yet")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(label), not answered yet")
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .accessibilityHidden(true)
                    Text(trimmedValue)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.subheadline)
                .foregroundStyle(.primary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(label), user confirmed, \(trimmedValue)")
            }
        }
    }

    private var trimmedValue: String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ProfileAccountConfirmationModifier: ViewModifier {
    @Binding var showSignOutConfirmation: Bool
    @Binding var showDeleteAccountConfirmation: Bool
    @Binding var isPreparingAccountDeletion: Bool
    let signOut: () -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Sign out of StyleMatch Pro?",
                isPresented: $showSignOutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive, action: signOut)
                Button("Cancel", role: .cancel) {
                }
            } message: {
                Text("Your Apple account data will stay saved on this phone. Guest data remains separate.")
            }
            .confirmationDialog(
                "Delete your StyleMatch Pro account?",
                isPresented: $showDeleteAccountConfirmation,
                titleVisibility: .visible
            ) {
                Button("Continue to Apple Confirmation", role: .destructive) {
                    isPreparingAccountDeletion = true
                }
                Button("Cancel", role: .cancel) {
                }
            } message: {
                Text("This permanently revokes StyleMatch Pro’s Sign in with Apple token and deletes your account, profile, closet, scans, saved AI context, and shopping data. This cannot be undone.")
            }
    }
}

private struct ProfileAccountSection: View {
    let selectedAccountMode: CustomerAccountMode
    let accountStatusTitle: String
    let accountIcon: String
    @Binding var accountSyncEnabled: Bool
    let guestDataLinkedToApple: Bool
    let guestDataTransferSummary: String
    let isAccountRequestInFlight: Bool
    @Binding var isPreparingAccountDeletion: Bool
    @Binding var showSignOutConfirmation: Bool
    @Binding var showDeleteAccountConfirmation: Bool
    let prepareAppleRequest: (ASAuthorizationAppleIDRequest) -> Void
    let handleAppleSignIn: (Result<ASAuthorization, Error>) -> Void
    let handleDeletionAuthorization: (Result<ASAuthorization, Error>) -> Void
    let cancelDeletionAuthorization: () -> Void

    var body: some View {
        Section("Account") {
            Label(accountStatusTitle, systemImage: accountIcon)
                .font(.headline)

            Text(selectedAccountMode.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if selectedAccountMode == .guest {
                guestControls
            } else {
                appleControls
            }

            if isAccountRequestInFlight {
                ProgressView("Updating your account…")
            }
        }
    }

    private var guestControls: some View {
        Group {
            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.fullName, .email]
                prepareAppleRequest(request)
            } onCompletion: { result in
                handleAppleSignIn(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .disabled(isAccountRequestInFlight)

            Text("You are using StyleMatch Pro as a guest. Sign in with Apple to save your profile, closet, favorites, and scan history.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var appleControls: some View {
        Toggle("Enable cloud sync when available", isOn: $accountSyncEnabled)

        Text(accountSyncEnabled ? "Cloud sync will be used only for account features like wishlist, closet backup, and order history." : "Sync is off. StyleMatch Pro keeps profile and scan data on this phone.")
            .font(.subheadline)
            .foregroundStyle(.secondary)

        Label("Signed in with Apple. Your profile can be saved and synced when cloud sync is available.", systemImage: "checkmark.seal.fill")
            .font(.subheadline)
            .foregroundStyle(.green)

        if !guestDataTransferSummary.isEmpty {
            Label(guestDataTransferSummary, systemImage: guestDataLinkedToApple ? "checkmark.shield" : "iphone")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Button {
            showSignOutConfirmation = true
        } label: {
            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
        }

        Button(role: .destructive) {
            showDeleteAccountConfirmation = true
        } label: {
            Label("Delete Account", systemImage: "person.crop.circle.badge.minus")
        }

        if isPreparingAccountDeletion {
            deletionAuthorizationControls
        }
    }

    private var deletionAuthorizationControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Confirm with Apple to permanently delete your StyleMatch Pro account.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = []
                prepareAppleRequest(request)
            } onCompletion: { result in
                handleDeletionAuthorization(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .disabled(isAccountRequestInFlight)

            Button("Cancel Account Deletion", role: .cancel) {
                isPreparingAccountDeletion = false
                cancelDeletionAuthorization()
            }
        }
    }
}

private enum SizeProfileCategory: String, CaseIterable, Identifiable {
    case men = "Men"
    case women = "Women"
    case unisex = "Unisex / Prefer not to say"
    case kidsYouth = "Kids/Youth"

    var id: String { rawValue }

    static func resolved(from storedValue: String) -> SizeProfileCategory {
        let trimmed = storedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.caseInsensitiveCompare("Unisex") == .orderedSame {
            return .unisex
        }
        return SizeProfileCategory(rawValue: trimmed) ?? .men
    }

    static func resolvedIfSet(from storedValue: String) -> SizeProfileCategory? {
        let trimmed = storedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.caseInsensitiveCompare("Unisex") == .orderedSame {
            return .unisex
        }
        return SizeProfileCategory(rawValue: trimmed)
    }
}

private struct ProfileEditDraft: Equatable {
    var name = ""
    var favoriteColors = ""
    var favoriteBrands = ""
    var favoriteStores = ""
    var budget = ""
    var styleGoals = ""
    var stylePreferences = ""
    var occasions = ""
    var outfitDislikes = ""
    var clothingPreferences = ""
    var pastPurchases = ""
    var favoriteOutfits = ""
    var closetInventory = ""
    var declaredUndertone = ""
    var preferredNeutrals = ""
    var preferredAccentColors = ""
    var comfortPreferences = ""
    var preferredPantRise = ""
    var shoppingFocus = ""
    var preferredShoppingCategories = ""
    var workSetting = ""
    var travelFrequency = ""
    var hobbiesActivities = ""
    var stylistVoice = ""
    var sizeCategory = ""
    var shirtSize = ""
    var pantsSize = ""
    var dressSize = ""
    var waistSize = ""
    var inseamLength = ""
    var neckSize = ""
    var sleeveLength = ""
    var shoeSize = ""
    var fitPreference = ""

    mutating func normalize() {
        name = normalized(name, fallback: "")
        favoriteColors = normalized(favoriteColors, fallback: "")
        favoriteBrands = normalized(favoriteBrands, fallback: "")
        favoriteStores = normalized(favoriteStores, fallback: "")
        budget = normalized(budget, fallback: "")
        styleGoals = normalized(styleGoals, fallback: "")
        stylePreferences = normalized(stylePreferences, fallback: "")
        occasions = normalized(occasions, fallback: "")
        outfitDislikes = normalized(outfitDislikes, fallback: "")
        clothingPreferences = normalized(clothingPreferences, fallback: "")
        pastPurchases = normalized(pastPurchases, fallback: "")
        favoriteOutfits = normalized(favoriteOutfits, fallback: "")
        closetInventory = normalized(closetInventory, fallback: "")
        declaredUndertone = DeclaredUndertone.fromProfileInput(declaredUndertone)?.rawValue ?? ""
        preferredNeutrals = normalized(preferredNeutrals, fallback: "")
        preferredAccentColors = normalized(preferredAccentColors, fallback: "")
        comfortPreferences = normalized(comfortPreferences, fallback: "")
        preferredPantRise = normalized(preferredPantRise, fallback: "")
        shoppingFocus = normalized(shoppingFocus, fallback: "")
        preferredShoppingCategories = normalized(preferredShoppingCategories, fallback: "")
        workSetting = normalized(workSetting, fallback: "")
        travelFrequency = normalized(travelFrequency, fallback: "")
        hobbiesActivities = normalized(hobbiesActivities, fallback: "")
        stylistVoice = normalized(stylistVoice, fallback: "")
        sizeCategory = SizeProfileCategory.resolvedIfSet(from: sizeCategory)?.rawValue ?? ""
        shirtSize = normalized(shirtSize, fallback: "")
        pantsSize = normalized(pantsSize, fallback: "")
        dressSize = normalized(dressSize, fallback: "")
        waistSize = normalized(waistSize, fallback: "")
        inseamLength = normalized(inseamLength, fallback: "")
        neckSize = normalized(neckSize, fallback: "")
        sleeveLength = normalized(sleeveLength, fallback: "")
        shoeSize = normalized(shoeSize, fallback: "")
        fitPreference = normalized(fitPreference, fallback: "")
    }

    mutating func reconcileGeneratedPantsSize() {
        normalize()
        let category = SizeProfileCategory.resolvedIfSet(from: sizeCategory)
        switch category {
        case .men, .unisex:
            let values = PantsSizeSync.reconciledValues(
                pantsSize: pantsSize,
                waistSize: waistSize,
                inseamLength: inseamLength,
                category: category?.rawValue ?? sizeCategory
            )
            pantsSize = values.pantsSize
            waistSize = values.waistSize
            inseamLength = values.inseamLength
        case .women, .kidsYouth:
            waistSize = ""
            inseamLength = ""
            neckSize = ""
            sleeveLength = ""
        case nil:
            if !waistSize.isEmpty || !inseamLength.isEmpty || PantsSizeSync.measurements(from: pantsSize) != nil {
                let values = PantsSizeSync.reconciledValues(
                    pantsSize: pantsSize,
                    waistSize: waistSize,
                    inseamLength: inseamLength,
                    category: SizeProfileCategory.men.rawValue
                )
                pantsSize = values.pantsSize
                waistSize = values.waistSize
                inseamLength = values.inseamLength
            }
        }
    }

    var generatedPantsDisplay: String? {
        PantsSizeSync.displayValue(waist: waistSize, inseam: inseamLength)
    }

    var sizeSummaryRows: [(label: String, value: String)] {
        var rows: [(String, String)] = []
        let category = SizeProfileCategory.resolvedIfSet(from: sizeCategory)
        if let category {
            rows.append(("Category", category.rawValue))
        }
        if !shirtSize.isEmpty {
            rows.append((category == .women ? "Top" : "Shirt", shirtSize))
        }
        switch category {
        case .men, .unisex:
            if let generatedPantsDisplay {
                rows.append(("Pants", generatedPantsDisplay))
            }
        case .women, .kidsYouth:
            if !pantsSize.isEmpty {
                rows.append((category == .kidsYouth ? "Bottoms" : "Bottoms", pantsSize))
            }
        case nil:
            if let generatedPantsDisplay {
                rows.append(("Pants", generatedPantsDisplay))
            } else if !pantsSize.isEmpty {
                rows.append(("Bottoms", pantsSize))
            }
        }
        if category == .women, !dressSize.isEmpty {
            rows.append(("Dress", dressSize))
        }
        if !shoeSize.isEmpty {
            rows.append(("Shoes", shoeSize))
        }
        if !fitPreference.isEmpty {
            rows.append(("Preferred Fit", fitPreference))
        }
        return rows
    }

    private func normalized(_ text: String, fallback: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

private struct ProfileStoredScan: Codable {
    let score: Int
    let firstScannedAt: Date
}

enum StyleMatchAppTheme: String, CaseIterable, Identifiable {
    case styleMatchAI
    case system
    case light
    case dark
    case premiumPink
    case purple
    case blue
    case green
    case blackAMOLED

    var id: String { rawValue }

    var title: String {
        switch self {
        case .styleMatchAI:
            return "StyleMatch AI Theme"
        case .system:
            return "System Default"
        case .light:
            return "Light Theme"
        case .dark:
            return "Dark Theme"
        case .premiumPink:
            return "Pink Theme"
        case .purple:
            return "Purple Theme"
        case .blue:
            return "Blue Theme"
        case .green:
            return "Green Theme"
        case .blackAMOLED:
            return "Black AMOLED Theme"
        }
    }

    var detail: String {
        switch self {
        case .styleMatchAI:
            return "Electric violet, fashion pink, mint, amber, coral, and gold."
        case .system:
            return "Follows your iPhone display setting."
        case .light:
            return "Keeps StyleMatch Pro bright and clean."
        case .dark:
            return "Uses a darker premium interface."
        case .premiumPink:
            return "Uses a pink premium mood across every screen."
        case .purple:
            return "Uses a rich AI-stylist purple across every screen."
        case .blue:
            return "Uses a clean blue premium look across every screen."
        case .green:
            return "Uses a polished green closet-inspired theme."
        case .blackAMOLED:
            return "Uses a true-black premium look for OLED screens."
        }
    }

    var icon: String {
        switch self {
        case .styleMatchAI:
            return "wand.and.stars"
        case .system:
            return "iphone"
        case .light:
            return "sun.max.fill"
        case .dark:
            return "moon.fill"
        case .premiumPink:
            return "sparkles"
        case .purple:
            return "sparkle.magnifyingglass"
        case .blue:
            return "cloud.sun.fill"
        case .green:
            return "leaf.fill"
        case .blackAMOLED:
            return "circle.lefthalf.filled"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system, .styleMatchAI:
            return nil
        case .light, .premiumPink, .purple, .blue, .green:
            return .light
        case .dark, .blackAMOLED:
            return .dark
        }
    }

    func palette(for tab: AppTab) -> AppPalette {
        switch self {
        case .styleMatchAI:
            return AppPalette(
                start: Color(hex: 0x0F0F14),
                middle: Color(hex: 0x6C5CE7),
                end: Color(hex: 0xFF6B9D),
                accent: Color(hex: 0x6C5CE7),
                card: Color(.systemBackground)
            )
        case .system:
            return tab.palette
        case .light:
            return AppPalette(
                start: Color(hex: 0xF6F1E8),
                middle: Color(hex: 0xEED9B5),
                end: Color(hex: 0xFFFFFF),
                accent: Color(hex: 0xB9832F),
                card: Color(.systemBackground)
            )
        case .dark:
            return AppPalette(
                start: Color(hex: 0x080812),
                middle: Color(hex: 0x171727),
                end: Color(hex: 0x2C2C3A),
                accent: Color(hex: 0xEED9B5),
                card: Color(.systemBackground)
            )
        case .premiumPink:
            return AppPalette(
                start: Color(hex: 0x4B1139),
                middle: Color(hex: 0xC2185B),
                end: Color(hex: 0xFFC1E3),
                accent: Color(hex: 0xD81B60),
                card: Color(.systemBackground)
            )
        case .purple:
            return AppPalette(
                start: Color(hex: 0x1B0B3A),
                middle: Color(hex: 0x6C3DFF),
                end: Color(hex: 0xD7C7FF),
                accent: Color(hex: 0x7C4DFF),
                card: Color(.systemBackground)
            )
        case .blue:
            return AppPalette(
                start: Color(hex: 0x062B55),
                middle: Color(hex: 0x0077FF),
                end: Color(hex: 0xA7E7FF),
                accent: Color(hex: 0x008CFF),
                card: Color(.systemBackground)
            )
        case .green:
            return AppPalette(
                start: Color(hex: 0x063B2A),
                middle: Color(hex: 0x00A86B),
                end: Color(hex: 0xB7F2D0),
                accent: Color(hex: 0x00A86B),
                card: Color(.systemBackground)
            )
        case .blackAMOLED:
            return AppPalette(
                start: Color.black,
                middle: Color(hex: 0x080808),
                end: Color(hex: 0x151515),
                accent: Color(hex: 0xFFD93D),
                card: Color(hex: 0x080808)
            )
        }
    }

    func scanPalette(intensity: Double = 0.42) -> (background: Color, panel: Color, border: Color, cream: Color, muted: Color) {
        let palette = palette(for: .scan)
        let normalizedIntensity = max(0.18, min(intensity, 0.82))
        switch self {
        case .styleMatchAI:
            return (
                Color(hex: 0x0F0F14),
                Color(hex: 0x1A1A22),
                Color(hex: 0x6C5CE7).opacity(0.30 + normalizedIntensity * 0.22),
                Color(hex: 0xFF6B9D),
                Color(hex: 0x9A9AA5)
            )
        case .blackAMOLED:
            return (.black, Color(hex: 0x080808), Color(hex: 0x2A2A2A), palette.accent, Color(hex: 0xB8B8B8))
        case .dark:
            return (palette.start, palette.middle.opacity(0.95), Color(hex: 0x3A3A4D), palette.accent, Color(hex: 0xA7A5B6))
        case .premiumPink:
            return (
                Color(hex: 0x160A12),
                Color(hex: 0x2A1722),
                Color(hex: 0x7A5265).opacity(0.45 + normalizedIntensity * 0.22),
                Color(hex: 0xF4C8DA),
                Color(hex: 0xD9C3CE)
            )
        case .purple:
            return (
                Color(hex: 0x120A24),
                Color(hex: 0x24163F),
                Color(hex: 0x7C4DFF).opacity(0.30 + normalizedIntensity * 0.20),
                Color(hex: 0xD7C7FF),
                Color(hex: 0xD2C8EA)
            )
        case .blue:
            return (
                Color(hex: 0x07182C),
                Color(hex: 0x112B46),
                Color(hex: 0x008CFF).opacity(0.28 + normalizedIntensity * 0.20),
                Color(hex: 0xBDEBFF),
                Color(hex: 0xC4D9E8)
            )
        case .green:
            return (
                Color(hex: 0x071D16),
                Color(hex: 0x113629),
                Color(hex: 0x00A86B).opacity(0.28 + normalizedIntensity * 0.20),
                Color(hex: 0xB7F2D0),
                Color(hex: 0xC5DDCE)
            )
        default:
            return (Color(hex: 0x10101C), Color(hex: 0x1B1B2F), Color(hex: 0x36334F), Color(hex: 0xEED9B5), Color(hex: 0xA7A5B6))
        }
    }
}

private struct ThemeSettingsView: View {
    @Binding var selectedTheme: String
    @Environment(\.dismiss) private var dismiss
    @AppStorage("selectedThemeIntensity") private var selectedThemeIntensity = 0.42
    @State private var draftTheme: String
    @State private var draftIntensity: Double

    init(selectedTheme: Binding<String>) {
        _selectedTheme = selectedTheme
        _draftTheme = State(initialValue: selectedTheme.wrappedValue)
        _draftIntensity = State(initialValue: 0.42)
    }

    private var currentTheme: StyleMatchAppTheme {
        StyleMatchAppTheme(rawValue: selectedTheme) ?? .system
    }

    private var previewTheme: StyleMatchAppTheme {
        StyleMatchAppTheme(rawValue: draftTheme) ?? .system
    }

    private var previewPalette: AppPalette {
        previewTheme.palette(for: .profile)
    }

    private var appliedTheme: StyleMatchAppTheme {
        StyleMatchAppTheme(rawValue: selectedTheme) ?? .system
    }

    private var appliedPalette: AppPalette {
        appliedTheme.palette(for: .profile)
    }

    private var isPreviewingBlackAMOLED: Bool {
        previewTheme == .blackAMOLED
    }

    private var hasPendingChanges: Bool {
        draftTheme != selectedTheme || abs(draftIntensity - selectedThemeIntensity) > 0.01
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    themePreviewCard
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    .listRowBackground(Color.clear)
                }

                Section("Choose Theme To Preview") {
                    ForEach(StyleMatchAppTheme.allCases) { theme in
                        themeChoiceRow(theme)
                    }
                }

                Section("Tweak Before Applying") {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Theme Strength")
                                .font(.headline)
                            Spacer()
                            Text("\(Int(draftIntensity * 100))%")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundStyle(previewPalette.accent)
                        }

                        Slider(value: $draftIntensity, in: 0.18...0.82, step: 0.01)
                            .tint(previewPalette.accent)

                        HStack(spacing: 8) {
                            Text("Soft")
                            Spacer()
                            Text("Bold")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Text("Lower strength keeps the app cleaner. Higher strength makes the selected color stronger.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    applyThemeButton
                }

                Section {
                    Text("Preview lets you tweak the look before it changes the full app. Tap Apply Theme when it feels right.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .appScreenBackground(.profile)
            .navigationTitle("Theme")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                applyThemeFooter
            }
            .onAppear {
                draftTheme = selectedTheme
                draftIntensity = selectedThemeIntensity
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(appliedTheme.preferredColorScheme)
    }

    private func themeChoiceRow(_ theme: StyleMatchAppTheme) -> some View {
        let palette = theme.palette(for: .profile)
        let isPreviewed = previewTheme == theme
        let isApplied = appliedTheme == theme

        return Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                draftTheme = theme.rawValue
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: theme.icon)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(palette.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(theme.title)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if isApplied {
                            Text("Applied")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(appliedPalette.accent)
                                .clipShape(Capsule())
                            }

                    }

                    Text(theme.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: isPreviewed ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isPreviewed ? palette.accent : .secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var applyThemeButton: some View {
        Button {
            applyTheme()
        } label: {
            HStack {
                Image(systemName: hasPendingChanges ? "checkmark.circle.fill" : "checkmark.seal.fill")
                Text(hasPendingChanges ? "Apply \(previewTheme.title)" : "\(appliedTheme.title) Applied")
                    .fontWeight(.bold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(hasPendingChanges ? previewPalette.accent : Color.green)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(!hasPendingChanges)
        .opacity(hasPendingChanges ? 1 : 0.88)
    }

    private var applyThemeFooter: some View {
        VStack(spacing: 8) {
            applyThemeButton
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 4)
        }
        .background(.ultraThinMaterial)
    }

    private func applyTheme() {
        withAnimation(.easeInOut(duration: 0.22)) {
            selectedTheme = draftTheme
            selectedThemeIntensity = draftIntensity
        }
    }

    private var themePreviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: previewTheme.icon)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(previewPalette.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Theme Preview")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("\(previewTheme.title) • \(Int(draftIntensity * 100))% strength")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("Currently applied: \(appliedTheme.title)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(appliedPalette.accent)
                }

                Spacer()
            }

            HStack(spacing: 10) {
                previewPill("Scan", systemImage: "camera.viewfinder")
                previewPill("AI", systemImage: "sparkles")
                previewPill("Profile", systemImage: "person.crop.circle.fill")
            }

            RoundedRectangle(cornerRadius: 18)
                .fill(
                    isPreviewingBlackAMOLED
                    ? AnyShapeStyle(Color.black)
                    : AnyShapeStyle(
                        LinearGradient(
                            colors: [
                                previewPalette.start.opacity(0.14 + draftIntensity * 0.22),
                                previewPalette.middle.opacity(0.08 + draftIntensity * 0.16),
                                previewPalette.end.opacity(0.10 + draftIntensity * 0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
                .frame(height: 84)
                .overlay(
                    VStack(spacing: 6) {
                        Text("Sample Card")
                            .font(.headline)
                            .foregroundStyle(isPreviewingBlackAMOLED ? .white : .primary)
                        Text("This is how the theme will feel before applying.")
                            .font(.caption)
                            .foregroundStyle(isPreviewingBlackAMOLED ? Color(hex: 0xB8B8B8) : .secondary)
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(previewPalette.accent.opacity(0.24 + draftIntensity * 0.32), lineWidth: 1)
                )
        }
        .padding()
        .background(isPreviewingBlackAMOLED ? Color(hex: 0x080808) : Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(previewPalette.accent.opacity(0.34), lineWidth: 1)
        )
    }

    private func previewPill(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption)
            .fontWeight(.bold)
            .foregroundStyle(previewPalette.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(previewPalette.accent.opacity(0.08 + draftIntensity * 0.10))
            .clipShape(Capsule())
    }
}

private struct SupportView: View {
    @Binding var selectedTab: AppTab
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PageColorBand(
                        tab: .profile,
                        title: "Contact Support",
                        subtitle: "Get help with scans, account access, shopping, or feedback.",
                        icon: "questionmark.circle.fill"
                    )
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    .listRowBackground(Color.clear)
                }

                Section("Support") {
                    Button {
                        selectedTab = .ai
                        dismiss()
                    } label: {
                        Label("Chat with AI Stylist", systemImage: "bubble.left.and.bubble.right.fill")
                    }

                    if let supportURL = URL(string: "mailto:hello@goodnessoflifeandfun.com?subject=StyleMatch%20Pro%20Support") {
                        Link(destination: supportURL) {
                            Label("Email Support", systemImage: "envelope.fill")
                        }
                    }

                    NavigationLink {
                        SupportFAQView()
                    } label: {
                        Label("FAQ", systemImage: "questionmark.circle.fill")
                    }

                    if let bugURL = URL(string: "mailto:hello@goodnessoflifeandfun.com?subject=StyleMatch%20Pro%20Bug%20Report") {
                        Link(destination: bugURL) {
                            Label("Report a Bug", systemImage: "ladybug.fill")
                        }
                    }

                    if let feedbackURL = URL(string: "mailto:hello@goodnessoflifeandfun.com?subject=StyleMatch%20Pro%20Beta%20Feedback") {
                        Link(destination: feedbackURL) {
                            Label("Send Feedback", systemImage: "bubble.left.and.bubble.right.fill")
                        }
                    }
                }

                Section("App") {
                    Label("StyleMatch Pro \(appVersion)", systemImage: "info.circle.fill")
                }
            }
            .scrollContentBackground(.hidden)
            .appScreenBackground(.profile)
            .navigationTitle("Support")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var appVersion: String {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            return ""
        }
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "" : "Version \(trimmed)"
    }
}

private struct SupportFAQView: View {
    var body: some View {
        List {
            Section("Scans") {
                Text("For the clearest result, photograph the full outfit in even lighting with the clothing unobstructed.")
                Text("Saved scans keep their original score and analysis until you delete them.")
            }
            Section("Accounts") {
                Text("Sign out keeps your Apple account data on the server. Delete Account revokes the Apple token and removes your saved StyleMatch data.")
            }
            Section("Shopping") {
                Text("Retailer links open outside StyleMatch Pro. Prices and availability can change at the retailer.")
            }
        }
        .navigationTitle("FAQ")
        .navigationBarTitleDisplayMode(.inline)
    }
}
