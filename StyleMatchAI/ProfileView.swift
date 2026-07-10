import AuthenticationServices
import CoreLocation
import SwiftUI

struct ProfileView: View {
    @Binding var selectedTab: AppTab
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
    @AppStorage("preferredAIAssistant") private var preferredAIAssistant = PreferredAIAssistant.siri.rawValue
    @AppStorage("shareAppContextWithChatGPT") private var shareAppContextWithChatGPT = true
    @AppStorage(VoiceAssistantSettings.enabledKey) private var voiceAssistantEnabled = VoiceAssistantSettings.defaultEnabled
    @AppStorage("voiceStylistDefaultVoiceHintDismissed") private var voiceStylistDefaultVoiceHintDismissed = false
    @AppStorage(VoiceAssistantSettings.speechRateKey) private var voiceAssistantSpeechRate = VoiceAssistantSettings.defaultSpeechRate
    @AppStorage("selectedAppTheme") private var selectedAppTheme = StyleMatchAppTheme.system.rawValue
    @AppStorage("profileLastSavedAt") private var profileLastSavedAt = ""
    @AppStorage("profileNeedsCloudSync") private var profileNeedsCloudSync = false
    @State private var showDeleteDataConfirmation = false
    @State private var showGuestTransferOffer = false
    @State private var isShowingThemeSettings = false
    @State private var isShowingSupport = false
    @State private var showProfileSavedConfirmation = false
    @State private var showUnsavedProfileWarning = false
    @State private var profileDraft = ProfileEditDraft()
    @State private var savedProfileDraft = ProfileEditDraft()
    @State private var hasUnsavedProfileChanges = false
    @State private var hasLoadedProfileDraft = false
    @State private var dataDeletionMessage: String?
    @State private var pantsSizeLastEditSource: PantsSizeEditSource = .manual
    @State private var showsAdditionalMeasurements = false
    @StateObject private var voiceAssistant = VoiceStylistService()

    private var selectedAssistant: PreferredAIAssistant {
        PreferredAIAssistant(rawValue: preferredAIAssistant) ?? .siri
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
    private let fitPreferenceOptions = ["Slim", "Regular", "Relaxed", "Oversized", "Tailored"]
    private let weatherConditionOptions = ["Mild", "Hot", "Cold", "Rainy", "Windy", "Humid", "Sunny"]
    private let occasionFormalityOptions = ["Casual", "Smart casual", "Polished", "Formal", "Travel comfort"]

    var body: some View {
        NavigationStack {
            Form {
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

                Section("Account") {
                    Label(accountStatusTitle, systemImage: accountIcon)
                        .font(.headline)

                    Text(selectedAccountMode.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if selectedAccountMode == .guest {
                        SignInWithAppleButton(.continue) { request in
                            request.requestedScopes = [.fullName, .email]
                        } onCompletion: { result in
                            handleAppleSignIn(result)
                        }
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        Text("You are using StyleMatch Pro as a guest. Sign in with Apple to save your profile, closet, favorites, and scan history.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if selectedAccountMode == .apple {
                        Toggle("Enable cloud sync when available", isOn: $accountSyncEnabled)

                        Text(accountSyncEnabled ? "Cloud sync will be used only for account features like wishlist, closet backup, and order history." : "Sync is off. Style Match Pro keeps profile and scan data on this phone.")
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
                        // Manage Account screen deferred to 1.6 — data actions live in the Data & Privacy section below.
                        Button {
                            useGuestMode()
                        } label: {
                            Label("Use Guest Mode on This Phone", systemImage: "person")
                        }
                    }

                }

                Section("Personal Information") {
                    profileInfoRow("Name", cleanValue(resolvedProfileDisplayName, fallback: "Not set"), icon: "person.fill")
                    profileInfoRow("Email", cleanValue(resolvedAccountEmail, fallback: "Hidden or not shared"), icon: "envelope.fill")
                    profileInfoRow("Account Type", selectedAccountMode.accountStatusTitle, icon: accountIcon)
                    profileInfoRow("Preferred Weather City", cleanValue(weatherCity, fallback: "Not set"), icon: "mappin.and.ellipse")
                    profileInfoRow("Preferred AI Assistant", selectedAssistant.rawValue, icon: "sparkles")

                    Label("Private tokens, passwords, API keys, and developer credentials are not shown in StyleMatch Pro.", systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if FeatureGate.shared.isCustomerVisible(.aiAssistantChoice) {
                    Section("AI Assistant") {
                        Picker("Choose assistant", selection: $preferredAIAssistant) {
                            ForEach(PreferredAIAssistant.allCases) { assistant in
                                Text(assistant.rawValue).tag(assistant.rawValue)
                            }
                        }

                        Label(selectedAssistant.description, systemImage: "sparkles")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("AI Stylist Settings") {
                    profileInfoRow("StyleMatch Pro AI Stylist", "Powered by ChatGPT", icon: "sparkles")

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
                    profileInfoRow("Closet Items", "\(closetItemCount)", icon: "tshirt.fill")
                }

                Section("Voice Assistant") {
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
                }

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

                Section("Weather Planning") {
                    profileInfoRow("Live Weather Status", weatherStatusText, icon: "cloud.sun.fill")
                    profileInfoRow("Location Permission", locationPermissionText, icon: "location.fill")
                    profileInfoRow("Last Updated", weatherLastUpdatedText, icon: "clock.fill")

                    TextField("Weather city", text: $weatherCity)
                        .textInputAutocapitalization(.words)
                    TextField("Weather", text: $weather)

                    Picker("Weather condition", selection: $weatherCondition) {
                        ForEach(weatherConditionOptions, id: \.self) { condition in
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
                        ForEach(occasionFormalityOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }

                    Label("Used to match outfit formality, comfort, color, weather, and closet pieces to the event.", systemImage: "calendar.badge.checkmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Size Profile") {
                    Picker("Size category", selection: sizeCategoryBinding()) {
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

                Section("Personalization") {
                    Text("Style Match Pro now saves your preferred AI assistant, colors, brands, budget, sizes, past purchases, favorite outfits, weather, occasions, and closet inventory before suggesting anything new.")
                        .foregroundStyle(.secondary)
                }

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

                Section("Data Control") {
                    Text(StyleMatchPrivacyMode.deletionRule)
                        .foregroundStyle(.secondary)

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
                    transferGuestDataToApple()
                }

                Button("Continue Without Transfer") {
                    guestDataTransferSummary = "Apple sign-in is active. Local guest data was kept on this iPhone."
                    dataDeletionMessage = guestDataTransferSummary
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
        }
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
                ForEach(optionsIncludingCurrent(shoeSizeOptions, current: profileDraft.shoeSize), id: \.self) { size in
                    Text(size).tag(size)
                }
            }

            fitPicker
        case .women:
            Picker("Women's top size", selection: draftBinding(\.shirtSize)) {
                ForEach(optionsIncludingCurrent(womenTopSizeOptions, current: profileDraft.shirtSize), id: \.self) { size in
                    Text(size).tag(size)
                }
            }

            Picker("Women's bottoms size", selection: draftBinding(\.pantsSize)) {
                ForEach(optionsIncludingCurrent(womenBottomSizeOptions, current: profileDraft.pantsSize), id: \.self) { size in
                    Text(size).tag(size)
                }
            }

            Picker("Dress size", selection: draftBinding(\.dressSize)) {
                ForEach(optionsIncludingCurrent(dressSizeOptions, current: profileDraft.dressSize), id: \.self) { size in
                    Text(size).tag(size)
                }
            }

            Picker("Women's shoe size", selection: draftBinding(\.shoeSize)) {
                ForEach(optionsIncludingCurrent(womenShoeSizeOptions, current: profileDraft.shoeSize), id: \.self) { size in
                    Text(size).tag(size)
                }
            }

            fitPicker
        case .unisex:
            Picker("Unisex top size", selection: draftBinding(\.shirtSize)) {
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
                ForEach(optionsIncludingCurrent(shoeSizeOptions, current: profileDraft.shoeSize), id: \.self) { size in
                    Text(size).tag(size)
                }
            }

            fitPicker
        case .kidsYouth:
            Picker("Kids / youth top size", selection: draftBinding(\.shirtSize)) {
                ForEach(optionsIncludingCurrent(kidsYouthSizeOptions, current: profileDraft.shirtSize), id: \.self) { size in
                    Text(size).tag(size)
                }
            }

            Picker("Kids / youth bottoms size", selection: draftBinding(\.pantsSize)) {
                ForEach(optionsIncludingCurrent(kidsYouthSizeOptions, current: profileDraft.pantsSize), id: \.self) { size in
                    Text(size).tag(size)
                }
            }

            Picker("Kids / youth shoe size", selection: draftBinding(\.shoeSize)) {
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
            ForEach(fitPreferenceOptions, id: \.self) { fit in
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

    private func profileInfoRow(_ title: String, _ value: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(AppTab.profile.palette.accent)
                .frame(width: 24)

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

    private func useGuestMode() {
        customerAccountMode = CustomerAccountMode.guest.rawValue
        customerAccountEmail = ""
        customerAppleUserID = ""
        name = ""
        accountSyncEnabled = false
        guestDataLinkedToApple = false
        guestDataTransferSummary = ""
        dataDeletionMessage = "Guest mode is active. Your data stays on this phone."
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        let wasGuest = selectedAccountMode == .guest

        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                dataDeletionMessage = "Apple sign-in did not return a valid account. Please try again."
                return
            }

            let signedInUserID = credential.user
            customerAccountMode = CustomerAccountMode.apple.rawValue
            customerAppleUserID = signedInUserID
            accountSyncEnabled = true

            let appliedProfile = StyleMatchAppleCredentialProfileApplier.applyAppleCredential(
                userID: signedInUserID,
                email: credential.email,
                appleGivenName: credential.fullName?.givenName,
                appleFamilyName: credential.fullName?.familyName,
                localDisplayName: name
            )
            logProfileNameEvent(
                stage: "sign-in",
                source: appliedProfile.source,
                appleNameProvided: credential.fullName?.givenName != nil || credential.fullName?.familyName != nil,
                localNamePresent: StyleMatchAccountNameResolver.clean(name) != nil,
                storedNamePresent: appliedProfile.givenName != nil
            )

            if let email = appliedProfile.email {
                customerAccountEmail = email
            }
            if let displayName = appliedProfile.displayName {
                name = displayName
            }

            if wasGuest && hasTransferableGuestData {
                showGuestTransferOffer = true
            } else {
                guestDataLinkedToApple = true
                guestDataTransferSummary = "Apple sign-in is active. New style data will be saved to this account when sync is available."
                dataDeletionMessage = "Signed in with Apple. Your Apple account is connected for Style Match Pro."
            }
        case .failure(let error):
            dataDeletionMessage = "Apple sign-in was not completed: \(error.localizedDescription)"
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

    private func transferGuestDataToApple() {
        var transferred: [String] = []

        if !outfitScanHistoryData.isEmpty {
            transferred.append("scan history")
        }

        let hasIntentionalProfileSave = FounderProfileDefaultsMigration.hasIntentionalProfileSave()

        if hasIntentionalProfileSave,
           cleanOptional(favoriteOutfits) != nil {
            transferred.append("favorites")
        }

        if !closetItemsData.isEmpty {
            transferred.append("closet")
        }

        if hasIntentionalProfileSave,
           cleanOptional(stylePreferences) != nil || cleanOptional(favoriteColors) != nil {
            transferred.append("style preferences")
        }

        if hasIntentionalProfileSave,
           StyleMatchAccountNameResolver.profileGivenName(from: name) != nil {
            transferred.append("profile")
        }

        guestDataLinkedToApple = true
        guestDataTransferSummary = transferred.isEmpty
            ? "Apple sign-in is active. New style data will be saved to this account when sync is available."
            : "Transferred guest \(transferred.joined(separator: ", ")) to Apple sign-in on this device."
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
            stylePreferences: stylePreferences,
            occasions: occasions,
            outfitDislikes: outfitDislikes,
            clothingPreferences: clothingPreferences,
            pastPurchases: pastPurchases,
            favoriteOutfits: favoriteOutfits,
            closetInventory: closetInventory,
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
        stylePreferences = draft.stylePreferences
        occasions = draft.occasions
        outfitDislikes = draft.outfitDislikes
        clothingPreferences = draft.clothingPreferences
        pastPurchases = draft.pastPurchases
        favoriteOutfits = draft.favoriteOutfits
        closetInventory = draft.closetInventory
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

        let savedDraft = currentStoredProfileDraft()
        profileDraft = savedDraft
        savedProfileDraft = savedDraft
        pantsSizeLastEditSource = .manual
        hasUnsavedProfileChanges = false
        syncPersonalStylistProfile(from: draft)
        dataDeletionMessage = accountSyncEnabled
            ? "Profile saved locally and marked for account sync when cloud sync is available."
            : "Profile saved locally on this phone."
        showProfileSavedConfirmation = true
        if voiceAssistantEnabled {
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
        profile.preferredFit = FitPreference.fromProfileInput(draft.fitPreference)
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
        FounderProfileDefaultsMigration.clearProfilePreferenceDefaults()
        customerAccountMode = CustomerAccountMode.guest.rawValue
        customerAccountEmail = ""
        customerAppleUserID = ""
        accountSyncEnabled = false
        name = ""
        favoriteColors = ""
        favoriteBrands = ""
        favoriteStores = ""
        budget = ""
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
        preferredAIAssistant = PreferredAIAssistant.siri.rawValue
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
        stylePreferences = ""
        occasions = ""
        favoriteOutfits = ""
        outfitDislikes = ""
        clothingPreferences = ""
        loadProfileDraft(force: true)
        dataDeletionMessage = "Personal Style Memory was cleared and turned off."
    }

    private func updateSizeProfileSummary() {
        sizeProfile = summaryText(for: currentStoredProfileDraft())
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
    var stylePreferences = ""
    var occasions = ""
    var outfitDislikes = ""
    var clothingPreferences = ""
    var pastPurchases = ""
    var favoriteOutfits = ""
    var closetInventory = ""
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
        stylePreferences = normalized(stylePreferences, fallback: "")
        occasions = normalized(occasions, fallback: "")
        outfitDislikes = normalized(outfitDislikes, fallback: "")
        clothingPreferences = normalized(clothingPreferences, fallback: "")
        pastPurchases = normalized(pastPurchases, fallback: "")
        favoriteOutfits = normalized(favoriteOutfits, fallback: "")
        closetInventory = normalized(closetInventory, fallback: "")
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
                        subtitle: "Get help with scans, TestFlight, account access, or beta feedback.",
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

                    Label("Live Chat (future)", systemImage: "message.fill")
                        .foregroundStyle(.secondary)

                    Label("Speak with a Stylist (future)", systemImage: "phone.fill")
                        .foregroundStyle(.secondary)

                    Button {
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
                            Label("Send Beta Feedback", systemImage: "bubble.left.and.bubble.right.fill")
                        }
                    }
                }

                Section("Before Public Release") {
                    Label("This build is for TestFlight/internal testing only.", systemImage: "testtube.2")
                    Label("Public release should wait until Apple approves version 1.1.", systemImage: "clock.fill")
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
}
