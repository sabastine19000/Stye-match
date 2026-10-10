import AuthenticationServices
import CoreLocation
import EventKit
import Foundation
import SwiftUI

private struct ProfileSectionTopPreferenceKey: PreferenceKey {
    static var defaultValue: [ProfileNavigationSection: CGFloat] = [:]
    static func reduce(value: inout [ProfileNavigationSection: CGFloat], nextValue: () -> [ProfileNavigationSection: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

private struct ProfileSectionActivationAnchor: ViewModifier {
    let section: ProfileNavigationSection
    func body(content: Content) -> some View {
        content.background(GeometryReader { proxy in
            Color.clear.preference(
                key: ProfileSectionTopPreferenceKey.self,
                value: [section: proxy.frame(in: .global).minY]
            )
        })
    }
}

private extension View {
    func profileSectionActivationAnchor(_ section: ProfileNavigationSection) -> some View {
        modifier(ProfileSectionActivationAnchor(section: section))
    }
}
#if canImport(UIKit)
import UIKit
#endif

struct ProfileView: View {
    @Binding var selectedTab: AppTab
    @Environment(\.openURL) private var openURL
    private let voiceControlsEnabled: Bool
    private let bottomOverlayClearance: CGFloat
    private let onOpenContextualStylist: (StylistProfileContextProjection) -> Void
    private static let privacyPolicyURL = URL(string: "https://stylematchpro.com/privacy")
    private static let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
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
    @AppStorage("preferredPantFit") private var preferredPantFit = PantFitPreference.unset.displayName
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
    @ObservedObject private var weatherAuthority = WeatherKitAuthority.shared
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
    @AppStorage("selectedThemeIntensity") private var selectedThemeIntensity = 0.42
    @AppStorage("profileLastSavedAt") private var profileLastSavedAt = ""
    @AppStorage("profileNeedsCloudSync") private var profileNeedsCloudSync = false
    @State private var showDeleteDataConfirmation = false
    @State private var showClearScanHistoryConfirmation = false
    @State private var showClearAIMemoryConfirmation = false
    @State private var isShowingAIMemoryManager = false
    @State private var showGuestTransferOffer = false
    @State private var pendingAppleSignIn: StyleMatchAppleSignInPayload?
    @State private var pendingAppleNonce: String?
    @State private var isAccountRequestInFlight = false
    @State private var isReconnectingBackendSession = false
    @State private var isPreparingAccountDeletion = false
    @State private var showSignOutConfirmation = false
    @State private var showDeleteAccountConfirmation = false
    @State private var isShowingThemeSettings = false
    @State private var isShowingSupport = false
    @State private var isShowingSharedLinks = false
    @State private var isShowingStyleFriends = false
    @AppStorage(StyleFriendsHomeSearchRoute.storageKey) private var pendingStyleFriendsHomeSearchRoute = ""
    @State private var styleFriendsHomeSearchRoute: StyleFriendsHomeSearchRoute?
    @State private var isShowingStyleConsultation = false
    @State private var showStyleConsultationResetConfirmation = false
    @State private var showProfileSavedConfirmation = false
    @State private var showUnsavedProfileWarning = false
    @State private var pendingSizeCategoryChange: ProfileSizeCategoryChange?
    @State private var showSizeCategoryChangeConfirmation = false
    @State private var profileDraft = ProfileEditDraft()
    @State private var savedProfileDraft = ProfileEditDraft()
    @State private var hasUnsavedProfileChanges = false
    @State private var hasLoadedProfileDraft = false
    @State private var dataDeletionMessage: String?
    @State private var personalStyleMemoryFeedback: String?
    @State private var voiceAssistantFeedback: String?
    @State private var calendarAwarenessState: CalendarAwarenessState = .off
    @State private var showCalendarConsentExplanation = false
    @State private var pantsSizeLastEditSource: PantsSizeEditSource = .manual
    @State private var showsAdditionalMeasurements = false
    @State private var profileNavigationSearchText = ""
    @State private var selectedProfileNavigationSection: ProfileNavigationSection = .overview
    @State private var isPersonalStyleExpanded = false
    @State private var isVoiceAssistantExpanded = false
    @State private var isStyleProfileExpanded = false
    @State private var isColorFitExpanded = false
    @State private var isWeatherPlanningExpanded = false
    @State private var isOccasionStylingExpanded = false
    @State private var isSizeProfileExpanded = false
    @State private var isStyleFriendsExpanded = false
    @State private var isPrivacyExpanded = false

    private var profileSavedConfirmationMessage: String {
        accountSyncEnabled
            ? "Saved locally and marked for account sync when cloud sync is available."
            : "Saved locally on this phone."
    }
    @State private var showUndertoneHelp = false
    @StateObject private var voiceAssistant = VoiceStylistService()
    @StateObject private var aiMemoryStore = AIPersistentMemoryStore()
    @StateObject private var aiTransmissionConsent = AITransmissionConsentStore.shared
    @State private var isShowingAITransmissionPrivacy = false

    init(
        selectedTab: Binding<AppTab>,
        voiceControlsEnabled: Bool = true,
        bottomOverlayClearance: CGFloat = 0,
        onOpenContextualStylist: @escaping (StylistProfileContextProjection) -> Void = { _ in }
    ) {
        PantFitPreference.migrateDefaultsIfNeeded()
        UserDefaults.standard.set(
            PantRisePreference.normalized(UserDefaults.standard.string(forKey: "preferredPantRise")),
            forKey: "preferredPantRise"
        )
        self._selectedTab = selectedTab
        self.voiceControlsEnabled = voiceControlsEnabled
        self.bottomOverlayClearance = bottomOverlayClearance
        self.onOpenContextualStylist = onOpenContextualStylist
    }

    private var effectiveVoiceControlsEnabled: Bool {
        #if DEBUG
        voiceControlsEnabled
        #else
        true
        #endif
    }

    private var selectedAccountMode: CustomerAccountMode {
        CustomerAccountMode(rawValue: customerAccountMode) ?? .guest
    }

    private var hasValidBackendSession: Bool {
        guard let session = StyleMatchAccountSessionStore.load() else { return false }
        return session.expiresAt > Date()
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
    private let pantFitOptions = PantFitPreference.options
    private let declaredUndertoneChoices = DeclaredUndertone.allCases
    private let styleIdentityOptions = ["Casual", "Business Casual", "Classic", "Minimalist", "Streetwear", "Athletic", "Luxury", "Trend-Focused", "Smart Casual"]
    private let styleGoalOptions = ["Dress more professionally", "Build confidence", "Improve color matching", "Create better everyday outfits", "Build a versatile wardrobe", "Spend more intentionally", "Prepare outfits faster", "Try new styles"]
    private let neutralColorOptions = ["Black", "White", "Gray", "Navy", "Cream", "Tan", "Brown", "Olive"]
    private let accentColorOptions = ["Blue", "Green", "Red", "Burgundy", "Gold", "Silver", "Pink", "Purple"]
    private let pantRiseOptions = PantRisePreference.options
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
            ScrollViewReader { proxy in
                ProfileFormSections(
                    identity: profileIdentitySections,
                    guidance: profileGuidanceSections,
                    preferences: profilePreferenceSections,
                    dataControls: profileDataControlSections
                )
                .safeAreaInset(edge: .top, spacing: 0) {
                    ProfileNavigationControls(
                        searchText: $profileNavigationSearchText,
                        selectedSection: $selectedProfileNavigationSection,
                        scrollTo: { section in
                            selectedProfileNavigationSection = section
                            expandProfileDisclosure(for: section)
                            if section == .styleFriends {
                                // Style Friends is a destination, not merely a
                                // Profile settings anchor. A tap from Profile
                                // search or the section chip should open it
                                // immediately instead of landing on Account.
                                styleFriendsHomeSearchRoute = .styleFriends
                                isShowingStyleFriends = true
                            } else if section == .aiMemory {
                                isShowingAIMemoryManager = true
                            } else {
                                withAnimation(.easeInOut) {
                                    proxy.scrollTo(section, anchor: .top)
                                }
                            }
                        }
                    )
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: bottomOverlayClearance)
                }
                .onPreferenceChange(ProfileSectionTopPreferenceKey.self) { tops in
                    // A fixed line below the sticky navigation avoids flicker while two
                    // adjacent sections are partially visible.
                    let activationLine: CGFloat = 210
                    let crossed = tops.filter { $0.value <= activationLine }
                    let active = crossed.max { $0.value < $1.value }?.key
                        ?? tops.min { $0.value < $1.value }?.key
                    guard let active, active != selectedProfileNavigationSection else { return }
                    selectedProfileNavigationSection = active
                }
            .scrollContentBackground(.hidden)
            .appScreenBackground(.profile)
            .tint(AppTab.profile.palette.accent)
            .navigationTitle("Profile")
            .toolbar {
                profileNavigationToolbar
            }
            .onAppear {
                updateSizeProfileSummary()
                loadProfileDraftIfNeeded()
                loadCalendarAwarenessState()
                consumeStyleFriendsHomeSearchRoute()
            }
            .onChange(of: pendingStyleFriendsHomeSearchRoute) { _ in
                consumeStyleFriendsHomeSearchRoute()
            }
            .onChange(of: activeAccountUserID) { _ in
                loadCalendarAwarenessState()
            }
            .modifier(ProfileSavedConfirmationModifier(
                isPresented: $showProfileSavedConfirmation,
                message: profileSavedConfirmationMessage
            ))
            .alert("Enable Calendar Context?", isPresented: $showCalendarConsentExplanation) {
                Button("Continue") {
                    enableCalendarContext()
                }
                Button("Not Now", role: .cancel) {}
            } message: {
                Text("KigoStylist will ask for calendar read access only after you continue. It keeps no calendar events, titles, notes, attendees, locations, or identifiers. It uses only a short-lived local occasion summary to improve outfit suggestions.")
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
            .modifier(ProfileUnsavedChangesConfirmationModifier(
                isPresented: $showUnsavedProfileWarning,
                saveAndLeave: {
                    saveProfileDraft()
                    selectedTab = .home
                },
                leaveWithoutSaving: {
                    loadProfileDraft(force: true)
                    selectedTab = .home
                }
            ))
            .modifier(ProfileSizeCategoryChangeConfirmationModifier(
                isPresented: $showSizeCategoryChangeConfirmation,
                message: pendingSizeCategoryChange?.confirmationMessage
                    ?? "Your saved size details will remain unchanged.",
                confirmChange: {
                    applyPendingSizeCategoryChange()
                },
                cancelChange: {
                    pendingSizeCategoryChange = nil
                }
            ))
            .confirmationDialog(
                "Delete saved KigoStylist data?",
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
            .modifier(ProfileClearScanHistoryConfirmationModifier(
                isPresented: $showClearScanHistoryConfirmation,
                clearScanHistory: {
                    outfitScanHistoryData = Data()
                    dataDeletionMessage = "Scan history was cleared from this phone."
                }
            ))
            .modifier(ProfileClearAIMemoryConfirmationModifier(
                isPresented: $showClearAIMemoryConfirmation,
                clearAIMemory: clearAIMemory
            ))
            .modifier(ProfileGuestTransferConfirmationModifier(
                isPresented: $showGuestTransferOffer,
                transferGuestData: {
                    completePendingAppleSignIn(transferGuestData: true)
                },
                continueWithoutTransfer: {
                    completePendingAppleSignIn(transferGuestData: false)
                }
            ))
            .sheet(isPresented: $isShowingThemeSettings) {
                ThemeSettingsView(selectedTheme: $selectedAppTheme, selectedThemeIntensity: $selectedThemeIntensity)
            }
            .sheet(isPresented: $isShowingSupport) {
                StyleMatchSupportView(onOpenAccountDeletion: {
                    isShowingSupport = false
                    DispatchQueue.main.async {
                        showDeleteAccountConfirmation = true
                    }
                })
            }
            .sheet(isPresented: $isShowingSharedLinks) {
                ShareableScoreCardManagerView {
                    isShowingSharedLinks = false
                    selectedTab = .scan
                }
            }
            .sheet(isPresented: $isShowingStyleFriends) {
                StyleFriendsView(
                    homeSearchRoute: styleFriendsHomeSearchRoute,
                    onCreateShareCard: {
                        isShowingStyleFriends = false
                        DispatchQueue.main.async {
                            selectedTab = .scan
                        }
                    }
                )
            }
            .sheet(isPresented: $isShowingAIMemoryManager, onDismiss: {
                if selectedProfileNavigationSection == .aiMemory {
                    selectedProfileNavigationSection = .overview
                }
            }) {
                AIMemoryManagementView(store: aiMemoryStore)
            }
            .sheet(isPresented: $isShowingAITransmissionPrivacy) {
                AITransmissionConsentSettingsView(consentStore: aiTransmissionConsent)
            }
            .sheet(isPresented: $isShowingStyleConsultation) {
                StyleConsultationSheet(
                    draft: $profileDraft,
                    styleIdentityOptions: styleIdentityOptions,
                    styleGoalOptions: styleGoalOptions,
                    pantFitOptions: pantFitOptions,
                    pantRiseOptions: pantRiseOptions,
                    declaredUndertoneChoices: declaredUndertoneChoices,
                    neutralColorOptions: neutralColorOptions,
                    accentColorOptions: accentColorOptions,
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
                UndertoneHelpSheet(isPresented: $showUndertoneHelp)
            }
            }
        }
    }

    private func consumeStyleFriendsHomeSearchRoute() {
        guard let route = StyleFriendsHomeSearchRoute(rawValue: pendingStyleFriendsHomeSearchRoute) else { return }
        pendingStyleFriendsHomeSearchRoute = ""
        styleFriendsHomeSearchRoute = route
        isShowingStyleFriends = true
    }

    private func expandProfileDisclosure(for section: ProfileNavigationSection) {
        switch section {
        case .style:
            isPersonalStyleExpanded = true
            isStyleProfileExpanded = true
        case .voice:
            isVoiceAssistantExpanded = true
        case .weather:
            isWeatherPlanningExpanded = true
        case .occasion:
            isOccasionStylingExpanded = true
        case .sizes:
            isSizeProfileExpanded = true
        case .styleFriends:
            isStyleFriendsExpanded = true
        case .privacy:
            isPrivacyExpanded = true
        default:
            break
        }
    }

    private var profileIdentitySections: AnyView {
        AnyView(Group {
            AnyView(profileHeaderSection)
            AnyView(accountSection)
            AnyView(personalInformationSection)
        })
    }

    private var profileGuidanceSections: AnyView {
        AnyView(Group {
            AnyView(aiStylistSettingsSection)
            AnyView(personalStyleProfileSection)
            AnyView(voiceAssistantSection)
        })
    }

    private var profilePreferenceSections: AnyView {
        AnyView(Group {
            AnyView(stylePreferenceSections)
            AnyView(personalizationAndPrivacySections)
        })
    }

    private var profileDataControlSections: AnyView {
        AnyView(dataControlAndSettingsSections)
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

            Label("Private tokens, passwords, API keys, and developer credentials are not shown in KigoStylist.", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var aiStylistSettingsSection: some View {
        Section("AI Stylist Settings") {
            profileInfoRow("KigoStylist AI Stylist", "Powered by KigoStylist AI", icon: "sparkles")

            Button {
                onOpenContextualStylist(profileStylistContextProjection)
            } label: {
                Label("Ask My Stylist", systemImage: "bubble.left.and.bubble.right.fill")
            }
            .accessibilityHint("Opens AI Stylist with the selected Profile preferences for this request.")

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
        .id(ProfileNavigationSection.overview)
        .profileSectionActivationAnchor(.overview)
    }

    private var profileStylistContextProjection: StylistProfileContextProjection {
        StylistProfileContextProjection(
            stylePreferences: profileDraft.stylePreferences,
            styleGoals: profileDraft.styleGoals,
            preferredFit: profileDraft.fitPreference,
            sizeCategory: profileDraft.sizeCategory,
            workplaceCategory: StylistConversationRouter.explicitWorkplaceEnvironment(in: profileDraft.workSetting)
        )
    }

    @ViewBuilder
    private var personalStyleProfileSection: some View {
        Section {
            DisclosureGroup("Personal Style Profile", isExpanded: $isPersonalStyleExpanded) {
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
        .id(ProfileNavigationSection.style)
        .profileSectionActivationAnchor(.style)
    }

    @ViewBuilder
    private var voiceAssistantSection: some View {
        Section {
            DisclosureGroup("Voice Assistant", isExpanded: $isVoiceAssistantExpanded) {
            if effectiveVoiceControlsEnabled {
                StyleMatchToggleRow(
                    title: "Speak outfit guidance",
                    description: "Brief foreground voice summaries for scan results, scan issues, and profile saves. This does not run in the background.",
                    isOn: voiceAssistantEnabledBinding,
                    feedback: voiceAssistantFeedback,
                    accessibilityHint: "Controls spoken outfit guidance."
                )

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
                    Text("Adjust the pace for spoken summaries.")
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
                #if DEBUG
                Label("Voice controls disabled for launch diagnosis", systemImage: "speaker.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                #endif
            }
            }
        }
        .id(ProfileNavigationSection.voice)
        .profileSectionActivationAnchor(.voice)
    }

    @ViewBuilder
    private var stylePreferenceSections: some View {
                Section {
                    DisclosureGroup("Style Profile", isExpanded: $isStyleProfileExpanded) {
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
                }
                .id(ProfileNavigationSection.style)

                Section {
                    DisclosureGroup("Color & Fit", isExpanded: $isColorFitExpanded) {
                    Picker("Color undertone (optional)", selection: draftBinding(\.declaredUndertone)) {
                        Text("Not provided").tag("")
                        ForEach(declaredUndertoneChoices, id: \.rawValue) { undertone in
                            Text(undertone.displayName).tag(undertone.rawValue)
                        }
                    }

                    Button {
                        showUndertoneHelp = true
                    } label: {
                        Label("How do I know?", systemImage: "info.circle")
                    }

                    Picker("Preferred Pant Fit", selection: draftBinding(\.preferredPantFit)) {
                        ForEach(pantFitOptions, id: \.self) { fit in
                            Text(fit).tag(fit)
                        }
                    }

                    Picker("Preferred Pant Rise", selection: draftBinding(\.preferredPantRise)) {
                        ForEach(pantRiseOptions, id: \.self) { rise in
                            Text(rise).tag(rise)
                        }
                    }

                    Button(role: .destructive) {
                        clearColorAndFitProfile()
                    } label: {
                        Label("Clear Color & Fit", systemImage: "xmark.circle")
                    }
                    .disabled(
                        profileDraft.declaredUndertone.isEmpty
                            && !PantFitPreference.fromProfileInput(profileDraft.preferredPantFit).isSet
                            && profileDraft.preferredPantRise == "No Preference"
                    )

                    Label("Optional. Used only for fashion color and fit suggestions. If saved, these preferences may be included in AI styling requests; they are never used to identify race, ethnicity, or sensitive traits, and they never change your outfit score.", systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Section {
                    DisclosureGroup("Weather Planning", isExpanded: $isWeatherPlanningExpanded) {
                    profileInfoRow("Live Weather Status", weatherStatusText, icon: "cloud.sun.fill")
                    profileInfoRow("Location Permission", locationPermissionText, icon: "location.fill")
                    profileInfoRow("Last Updated", weatherLastUpdatedText, icon: "clock.fill")

                    WeatherStylingButton {
                        Label("Manage WeatherKit Weather", systemImage: "cloud.sun.fill")
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
                }
                .id(ProfileNavigationSection.weather)
                .profileSectionActivationAnchor(.weather)

                Section {
                    DisclosureGroup("Occasion Styling", isExpanded: $isOccasionStylingExpanded) {
                    TextField("Planned occasion", text: plannedOccasionBinding)
                        .textInputAutocapitalization(.words)
                        .accessibilityLabel(StyleMatchAccessibilityText.profileFieldLabel(title: "Planned occasion", isRequired: false))
                        .accessibilityValue(StyleMatchAccessibilityText.profileFieldValue(text: plannedOccasion))
                    TextField("Dress code", text: dressCodeBinding)
                        .textInputAutocapitalization(.words)
                        .accessibilityLabel(StyleMatchAccessibilityText.profileFieldLabel(title: "Dress code", isRequired: false))
                        .accessibilityValue(StyleMatchAccessibilityText.profileFieldValue(text: dressCode))

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
                }
                .id(ProfileNavigationSection.occasion)
                .profileSectionActivationAnchor(.occasion)

                    Section {
                        DisclosureGroup("Size Profile", isExpanded: $isSizeProfileExpanded) {
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
                    .id(ProfileNavigationSection.sizes)
                    .profileSectionActivationAnchor(.sizes)
    }

    @ViewBuilder
    private var personalizationAndPrivacySections: some View {
                    Section("Personalization") {
                    Text("KigoStylist now saves your preferred AI assistant, colors, brands, budget, sizes, past purchases, favorite outfits, weather, occasions, and closet inventory before suggesting anything new.")
                        .foregroundStyle(.secondary)
                }

                profileCompletenessSection

                    Section {
                        DisclosureGroup("Style Friends", isExpanded: $isStyleFriendsExpanded) {
                    Button {
                        isShowingStyleFriends = true
                    } label: {
                        Label("Open Style Friends", systemImage: "person.2.fill")
                    }
                    .accessibilityLabel("Open Style Friends")
                    .accessibilityHint("Opens Friends-only outfit sharing, friend requests, and your social style profile.")

                    Text("Connect with friends, share outfits, and manage your social style profile.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        }
                    }
                    .id(ProfileNavigationSection.styleFriends)
                    .profileSectionActivationAnchor(.styleFriends)

                    Section {
                        DisclosureGroup("Your Privacy", isExpanded: $isPrivacyExpanded) {
                    Text("Your data stays on your device whenever possible. Cloud AI is used only when needed. You control your information.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("These are KigoStylist privacy commitments. Manage your actual data controls below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    privacyPromiseRow("Data stays on your device whenever possible.")
                    privacyPromiseRow("Cloud AI is used only when needed.")
                    privacyPromiseRow("You control your information.")
                    privacyPromiseRow("Delete your data anytime.")
                    privacyPromiseRow("You can turn Personal Style Memory off at any time.")
                        }
                    }
                    .id(ProfileNavigationSection.privacy)
                    .profileSectionActivationAnchor(.privacy)
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
                    .accessibilityLabel("Manage Shared Links")
                    .accessibilityHint("Opens your active and revoked shared outfit links.")

                    Button {
                        isShowingStyleFriends = true
                    } label: {
                        Label("Style Friends", systemImage: "person.2.fill")
                    }
                    .accessibilityLabel("Style Friends")
                    .accessibilityHint("Opens Friends-only outfit sharing, friend requests, and your social style profile.")

                    Button {
                        showClearScanHistoryConfirmation = true
                    } label: {
                        Label("Clear Scan History", systemImage: "photo.stack")
                    }
                    .accessibilityLabel("Clear Scan History")
                    .accessibilityHint("Shows a confirmation before removing saved scan history from this phone.")

                    Button {
                        isShowingAIMemoryManager = true
                    } label: {
                        HStack(spacing: 12) {
                            Label("AI Memory", systemImage: "brain")
                            Spacer(minLength: 12)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Manage AI Memory")
                    .accessibilityHint("Manage remembered preferences and AI memory.")

                    Button {
                        aiTransmissionConsent.refresh()
                        isShowingAITransmissionPrivacy = true
                    } label: {
                        HStack(spacing: 12) {
                            Label("AI Processing Consent", systemImage: "network.badge.shield.half.filled")
                            Spacer(minLength: 12)
                            Text(aiTransmissionConsent.state.displayName)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("AI Processing Consent, \(aiTransmissionConsent.state.displayName)")
                    .accessibilityHint("Review or change your current AI-processing consent.")

                    Button {
                        showClearAIMemoryConfirmation = true
                    } label: {
                        Label("Clear AI Memory", systemImage: "brain.head.profile")
                    }
                    .accessibilityLabel("Clear AI Memory")
                    .accessibilityHint("Shows a confirmation before removing local Personal Style Memory.")

                    StyleMatchToggleRow(
                        title: "Personal Style Memory",
                        description: shareAppContextWithChatGPT
                            ? "KigoStylist can use saved preferences and assistant context for future assistance."
                            : "Turning this off stops future use of Personal Style Memory. Clear AI Memory removes existing saved Personal Style Memory.",
                        isOn: personalStyleMemoryBinding,
                        feedback: personalStyleMemoryFeedback,
                        accessibilityHint: "Turning this off does not delete existing memory. Use Clear AI Memory to remove it."
                    )

                    Button(role: .destructive) {
                        showDeleteDataConfirmation = true
                    } label: {
                        Label("Delete My Saved Data", systemImage: "trash")
                    }
                    .accessibilityLabel("Delete My Saved Data")
                    .accessibilityHint("Shows a confirmation before deleting saved data from this phone.")

                    if let dataDeletionMessage {
                        Text(dataDeletionMessage)
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    }
                }

                Section("App Settings") {
                    calendarContextSettings

                    profileInfoRow("Notifications", "Coming Soon", icon: "bell.slash.fill")
                        .opacity(0.6)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Notifications")
                        .accessibilityValue("Coming Soon, unavailable")

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
                    profileInfoRow("App Version", appVersionText, icon: "info.circle.fill")

                    Button {
                        guard let termsOfUseURL = Self.termsOfUseURL else {
                            dataDeletionMessage = "Terms of Use is unavailable. Please try again later."
                            return
                        }

                        dataDeletionMessage = nil
                        openURL(termsOfUseURL) { accepted in
                            if !accepted {
                                dataDeletionMessage = "Unable to open Terms of Use in your browser. Please try again later."
                            }
                        }
                    } label: {
                        Label("Terms of Use", systemImage: "doc.text")
                    }
                    .accessibilityLabel("Terms of Use, link, opens in browser")
                    .accessibilityAddTraits(.isLink)

                    Button {
                        guard let privacyPolicyURL = Self.privacyPolicyURL else {
                            dataDeletionMessage = "Privacy Policy is unavailable. Please try again later."
                            return
                        }

                        dataDeletionMessage = nil
                        openURL(privacyPolicyURL) { accepted in
                            if !accepted {
                                dataDeletionMessage = "Unable to open Privacy Policy in your browser. Please try again later."
                            }
                        }
                    } label: {
                        Label("Privacy Policy", systemImage: "hand.raised.fill")
                    }
                    .accessibilityLabel("Privacy Policy, link, opens in browser")
                    .accessibilityAddTraits(.isLink)

                    Button {
                        isShowingSupport = true
                    } label: {
                        Label("AI Customer Service", systemImage: "questionmark.circle.fill")
                    }
                    .accessibilityHint("Opens automated KigoStylist support using approved support information.")
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
            hasValidBackendSession: hasValidBackendSession,
            isReconnectingBackendSession: $isReconnectingBackendSession,
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
        .id(ProfileNavigationSection.account)
        .profileSectionActivationAnchor(.account)
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
            let change = ProfileSizeCategoryChange.plan(
                currentCategory: profileDraft.sizeCategory,
                fields: profileDraft.sizeFieldValues,
                requestedCategory: newValue
            )
            guard change.requiresConfirmation else {
                applySizeCategoryChange(change)
                return
            }

            pendingSizeCategoryChange = change
            showSizeCategoryChangeConfirmation = true
        }
    }

    private func applyPendingSizeCategoryChange() {
        guard let pendingSizeCategoryChange else { return }
        applySizeCategoryChange(pendingSizeCategoryChange)
        self.pendingSizeCategoryChange = nil
    }

    private func applySizeCategoryChange(_ change: ProfileSizeCategoryChange) {
        profileDraft.applySizeCategoryChange(change)
        pantsSizeLastEditSource = .manual
        showsAdditionalMeasurements = false
        updateProfileDirtyState()
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
        _ = newValue
    }

    private func profileDraftField(
        _ title: String,
        text: Binding<String>,
        prompt: String,
        isRequired: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)

            TextField(prompt, text: text, axis: .vertical)
                .textInputAutocapitalization(.words)
                .lineLimit(1...3)
                .accessibilityLabel(StyleMatchAccessibilityText.profileFieldLabel(title: title, isRequired: isRequired))
                .accessibilityValue(StyleMatchAccessibilityText.profileFieldValue(text: text.wrappedValue))
                .accessibilityHint(isRequired ? "This field must be completed before saving." : "This field is optional.")
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
            pantRisePicker
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
            pantRisePicker
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
            pantRisePicker
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
            pantRisePicker

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
                Text("Add only the sizes you want KigoStylist to remember.")
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
        Picker("Preferred Pant Fit", selection: draftBinding(\.preferredPantFit)) {
            ForEach(pantFitOptions, id: \.self) { fit in
                Text(fit).tag(fit)
            }
        }
    }

    private var pantRisePicker: some View {
        Picker("Preferred Pant Rise", selection: draftBinding(\.preferredPantRise)) {
            ForEach(pantRiseOptions, id: \.self) { rise in
                Text(rise).tag(rise)
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

    private var weather: String { weatherAuthority.snapshot.map { "\($0.temperatureFahrenheit)°F" } ?? "" }
    private var weatherCity: String { weatherAuthority.snapshot?.locationName ?? "" }
    private var weatherCondition: String { weatherAuthority.snapshot?.condition ?? "" }

    private var weatherStatusText: String {
        weatherAuthority.snapshot == nil ? "Weather unavailable" : "WeatherKit weather active"
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
        guard let observedAt = weatherAuthority.snapshot?.observedAt else {
            return "Not updated yet"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: observedAt)
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
        HStack(spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            Text(text)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Privacy commitment: \(text)")
        .accessibilityHint("Informational statement. Manage available data controls below.")
        .accessibilityRemoveTraits(.isButton)
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
            StyleMatchAppleSignInDiagnosticBuffer.record(.appleAuthorizationResult)
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                dataDeletionMessage = "Apple sign-in did not return a valid account. Please try again."
                return
            }

            guard let nonce = pendingAppleNonce else {
                dataDeletionMessage = StyleMatchAccountError.authorizationIncomplete.localizedDescription
                return
            }
            if isReconnectingBackendSession,
               PersonalStylistStorage.normalizedUserID(credential.user)
                != PersonalStylistStorage.normalizedUserID(customerAppleUserID) {
                pendingAppleNonce = nil
                isReconnectingBackendSession = false
                dataDeletionMessage = "Use the same Apple account that is currently connected to KigoStylist."
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
            isReconnectingBackendSession = false
            isAccountRequestInFlight = true
            Task {
                do {
                    StyleMatchAppleSignInDiagnosticBuffer.record(.requestDispatched)
                    let session = try await StyleMatchAccountClient().exchange(
                        authorizationCode: credential.authorizationCode,
                        identityToken: credential.identityToken,
                        nonce: nonce,
                        appleSubject: credential.user
                    )
                    try StyleMatchAccountSessionStore.save(session)
                    StyleMatchAppleSignInDiagnosticBuffer.record(.responseReceived)
                    StyleMatchAppleSignInDiagnosticBuffer.record(.sessionSaved)
                    StyleMatchAppleSignInDiagnosticBuffer.record(.uiObserverUpdated)
                    StyleMatchAccountSessionDiagnostics.log(stage: "apple_exchange_succeeded")
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
                    StyleMatchAppleSignInDiagnosticBuffer.record(.responseReceived)
                    StyleMatchAccountSessionStore.delete()
                    StyleMatchAccountSessionDiagnostics.log(stage: "apple_exchange_failed")
                    dataDeletionMessage = (error as? StyleMatchAccountError)?.localizedDescription
                        ?? StyleMatchAccountError.serviceUnavailable.localizedDescription
                }
                isAccountRequestInFlight = false
            }
        case .failure:
            StyleMatchAppleSignInDiagnosticBuffer.record(.appleAuthorizationResult)
            pendingAppleNonce = nil
            isReconnectingBackendSession = false
            isAccountRequestInFlight = false
            dataDeletionMessage = StyleMatchAccountError.authorizationIncomplete.localizedDescription
        }
    }

    private func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        do {
            StyleMatchAppleSignInDiagnosticBuffer.begin()
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
            // This follows an explicit owner logout completion, never a
            // transient refresh/network failure. Only the confirmed account's
            // opaque journal scope is removed.
            if let accountSession,
               let account = accountSession.accountID ?? accountSession.appleSubject,
               let environment = accountSession.endpointHost,
               let tag = try? StyleFriendsDMOperationJournal.shared.accountEnvironmentTag(account: account, environment: environment) {
                try? StyleFriendsDMOperationJournal.shared.deleteAll(accountEnvironmentTag: tag)
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

    private func loadCalendarAwarenessState() {
        calendarAwarenessState = CalendarAwarenessPreferenceStore.state(for: activeAccountUserID)
    }

    private var calendarContextSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Calendar Context", systemImage: "calendar")
                .font(.headline)
            Text(CalendarAwarenessPreferenceStore.supportingText(for: calendarAwarenessState))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if calendarAwarenessState == .on {
                Button("Refresh Calendar Context") { refreshCalendarContextState() }
                Button("Disable Calendar Context", role: .destructive) {
                    CalendarAwarenessPreferenceStore.set(.off, for: activeAccountUserID)
                    calendarAwarenessState = .off
                }
            } else {
                Button("Enable Calendar Context") { showCalendarConsentExplanation = true }
            }

            Button("Disconnect Calendar Context", role: .destructive) {
                CalendarAwarenessPreferenceStore.clear(for: activeAccountUserID)
                calendarAwarenessState = .off
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func enableCalendarContext() {
        Task {
            let access = EventKitCalendarContextAccess()
            let status = access.authorizationStatus
            let granted: Bool
            if status == .notDetermined {
                granted = (try? await access.requestReadAccess()) == true
            } else {
                granted = calendarReadAccessAvailable(status)
            }
            await MainActor.run {
                calendarAwarenessState = calendarState(for: access.authorizationStatus, granted: granted)
                CalendarAwarenessPreferenceStore.set(calendarAwarenessState, for: activeAccountUserID)
            }
        }
    }

    private func refreshCalendarContextState() {
        let status = EventKitCalendarContextAccess().authorizationStatus
        calendarAwarenessState = calendarState(for: status, granted: calendarReadAccessAvailable(status))
        CalendarAwarenessPreferenceStore.set(calendarAwarenessState, for: activeAccountUserID)
    }

    private func calendarState(for status: EKAuthorizationStatus, granted: Bool) -> CalendarAwarenessState {
        if granted { return .on }
        switch status {
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .permissionRequired
        case .fullAccess: return .on
        case .writeOnly: return .unavailable
        case .authorized: return .on
        @unknown default: return .unavailable
        }
    }

    private func calendarReadAccessAvailable(_ status: EKAuthorizationStatus) -> Bool {
        if #available(iOS 17.0, *) {
            return status == .fullAccess
        }
        return status == .authorized
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
                dataDeletionMessage = "Use the same Apple account that is currently connected to KigoStylist."
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
                    if let account = session.accountID ?? session.appleSubject,
                       let environment = session.endpointHost,
                       let tag = try? StyleFriendsDMOperationJournal.shared.accountEnvironmentTag(account: account, environment: environment) {
                        try? StyleFriendsDMOperationJournal.shared.deleteAll(accountEnvironmentTag: tag)
                    }
                    StyleMatchAccountSessionStore.delete()
                    isPreparingAccountDeletion = false
                    deleteSavedData()
                    dataDeletionMessage = "Your KigoStylist account and saved data were permanently deleted. If you return later, you can create a new account, but deleted data will not be restored."
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
            preferredPantFit: preferredPantFit,
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
        preferredPantFit = draft.preferredPantFit
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
        if effectiveVoiceControlsEnabled, voiceAssistantEnabled {
            voiceAssistant.speak(VoiceScriptBuilder.profileSaved())
        }
    }

    private func logPantsSave(_ draft: ProfileEditDraft) {
        _ = draft
    }


    private func logProfileNameEvent(
        stage: String,
        source: StyleMatchAccountNameResolver.Source,
        appleNameProvided: Bool,
        localNamePresent: Bool,
        storedNamePresent: Bool
    ) {
        _ = stage
        _ = source
        _ = appleNameProvided
        _ = localNamePresent
        _ = storedNamePresent
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
        profile.preferredPantFit = PantFitPreference.fromProfileInput(draft.preferredPantFit)
        profile.styleGoals = splitProfileList(draft.styleGoals)
        profile.preferredNeutrals = splitProfileList(draft.preferredNeutrals)
        profile.preferredAccentColors = splitProfileList(draft.preferredAccentColors)
        profile.comfortPreferences = splitProfileList(draft.comfortPreferences)
        profile.preferredPantRise = draft.preferredPantRise == "No Preference" ? "" : draft.preferredPantRise
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

    private var plannedOccasionBinding: Binding<String> {
        Binding(
            get: { plannedOccasion },
            set: { plannedOccasion = StyleMatchInputBounds.profileFreeText($0) }
        )
    }

    private var dressCodeBinding: Binding<String> {
        Binding(
            get: { dressCode },
            set: { dressCode = StyleMatchInputBounds.profileFreeText($0) }
        )
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
        pastPurchases = ""
        favoriteOutfits = ""
        closetInventory = ""
        preferredNeutrals = ""
        preferredAccentColors = ""
        comfortPreferences = ""
        preferredPantRise = ""
        preferredPantFit = PantFitPreference.unset.displayName
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
        guard aiMemoryStore.clearAll() else {
            dataDeletionMessage = "AI Memory could not be cleared. Your saved memories were kept."
            return
        }
        shareAppContextWithChatGPT = false
        AIMemoryTemporaryContext.clear()
        dataDeletionMessage = "AI Memory was cleared and turned off. Your profile, closet, and scan history were not changed."
    }

    private var personalStyleMemoryBinding: Binding<Bool> {
        Binding(
            get: { shareAppContextWithChatGPT },
            set: { newValue in
                let previousValue = shareAppContextWithChatGPT
                shareAppContextWithChatGPT = newValue

                guard UserDefaults.standard.object(forKey: "shareAppContextWithChatGPT") as? Bool == newValue else {
                    shareAppContextWithChatGPT = previousValue
                    personalStyleMemoryFeedback = "Personal Style Memory could not be updated."
                    announceToggleFeedback(personalStyleMemoryFeedback)
                    return
                }

                personalStyleMemoryFeedback = newValue
                    ? "Personal Style Memory is on."
                    : "Personal Style Memory is off. Clear AI Memory removes existing saved Personal Style Memory."
                announceToggleFeedback(personalStyleMemoryFeedback)
            }
        )
    }

    private var voiceAssistantEnabledBinding: Binding<Bool> {
        Binding(
            get: { voiceAssistantEnabled },
            set: { newValue in
                let previousValue = voiceAssistantEnabled
                voiceAssistantEnabled = newValue

                guard UserDefaults.standard.object(forKey: VoiceAssistantSettings.enabledKey) as? Bool == newValue else {
                    voiceAssistantEnabled = previousValue
                    voiceAssistantFeedback = "Speak outfit guidance could not be updated."
                    announceToggleFeedback(voiceAssistantFeedback)
                    return
                }

                voiceAssistantFeedback = newValue
                    ? "Speak outfit guidance is on."
                    : "Speak outfit guidance is off."
                announceToggleFeedback(voiceAssistantFeedback)
            }
        )
    }

    private func announceToggleFeedback(_ feedback: String?) {
        #if canImport(UIKit)
        UIAccessibility.post(notification: .announcement, argument: feedback)
        #endif
    }

    private func clearColorAndFitProfile() {
        profileDraft.declaredUndertone = ""
        profileDraft.preferredPantFit = PantFitPreference.unset.displayName
        profileDraft.preferredPantRise = "No Preference"
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
        profileDraft.preferredPantRise = "No Preference"
        profileDraft.preferredPantFit = PantFitPreference.unset.displayName
        profileDraft.shoppingFocus = ""
        profileDraft.preferredShoppingCategories = ""
        profileDraft.workSetting = ""
        profileDraft.travelFrequency = ""
        profileDraft.hobbiesActivities = ""
        profileDraft.stylistVoice = ""
        styleConsultationCompletedAt = ""
        saveProfileDraft()
    }

    private var profileNavigationToolbar: ProfileNavigationToolbar {
        ProfileNavigationToolbar(
            hasUnsavedChanges: hasUnsavedProfileChanges,
            goBack: attemptProfileExit,
            save: saveProfileDraft
        )
    }

    private func updateSizeProfileSummary() {
        sizeProfile = summaryText(for: currentStoredProfileDraft())
    }
}

private extension AITransmissionConsentState {
    var displayName: String {
        switch self {
        case .undecided: "Not decided"
        case .accepted: "Allowed"
        case .declined: "Not allowed"
        }
    }
}

private struct AITransmissionConsentSettingsView: View {
    @ObservedObject var consentStore: AITransmissionConsentStore
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingDisclosure = false

    var body: some View {
        NavigationStack {
            List {
                Section("AI transmission") {
                    Text("Status")
                    Text(consentStore.state.displayName)
                        .foregroundStyle(.secondary)
                    Text("This setting controls future network requests for AI features. Review the current consent before AI requests can be sent. It does not delete local scans, Profile data, Closet items, or AI Memory.")
                        .foregroundStyle(.secondary)
                }
                Section {
                    if consentStore.state == .accepted {
                        Button("Revoke AI transmission permission", role: .destructive) {
                            consentStore.revoke()
                        }
                        .accessibilityHint("Stops future AI network requests without deleting local data.")
                    } else {
                        Button("Review AI Processing Consent") {
                            isShowingDisclosure = true
                        }
                        .accessibilityHint("Reviews the disclosure before allowing AI network requests.")
                    }
                }
            }
            .navigationTitle("AI Processing Consent")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { consentStore.refresh() }
            .sheet(isPresented: $isShowingDisclosure) {
                AITransmissionConsentDisclosureView(
                    consentStore: consentStore,
                    recordCurrentConsent: {
                        do {
                            try await AIProcessingConsentService().acceptCurrentConsent()
                            consentStore.accept()
                            return true
                        } catch {
                            return false
                        }
                    },
                    agreeAndContinue: {},
                    decline: {}
                )
            }
        }
    }
}

private enum ProfileNavigationSection: String, CaseIterable, Identifiable, Hashable {
    case overview
    case account
    case style
    case aiMemory
    case sizes
    case voice
    case weather
    case occasion
    case styleFriends
    case privacy

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .account: return "Account"
        case .style: return "Style"
        case .aiMemory: return "AI Memory"
        case .sizes: return "Sizes"
        case .voice: return "Voice"
        case .weather: return "Weather"
        case .occasion: return "Occasion"
        case .styleFriends: return "Style Friends"
        case .privacy: return "Privacy"
        }
    }

    var searchTerms: [String] {
        switch self {
        case .overview:
            return ["overview", "ai confidence", "saved scans", "closet"]
        case .account:
            return ["account", "apple", "cloud sync", "sync", "email"]
        case .style:
            return ["style", "style dna", "consultation", "brands", "stores", "budget", "colors", "color"]
        case .aiMemory:
            return ["ai memory", "memory", "remember", "forget", "preferences", "corrections"]
        case .sizes:
            return ["size", "shirt", "pants", "waist", "inseam", "shoe", "fit", "rise", "measurements"]
        case .voice:
            return ["voice", "assistant", "speak"]
        case .weather:
            return ["weather", "city", "location"]
        case .occasion:
            return ["occasion", "dress code", "formality"]
        case .styleFriends:
            return ["style friends", "friends", "social", "sharing", "shared looks"]
        case .privacy:
            return ["privacy", "memory", "data", "delete", "shared links"]
        }
    }

    private func normalizedSearchValue(_ value: String) -> String {
        value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    func matches(searchText: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return false }

        let normalizedQuery = normalizedSearchValue(query)
        let candidates = [title] + searchTerms
        return candidates.contains { candidate in
            let lowered = candidate.lowercased()
            let normalizedCandidate = normalizedSearchValue(candidate)
            return lowered.contains(query)
                || query.contains(lowered)
                || normalizedCandidate.contains(normalizedQuery)
                || normalizedQuery.contains(normalizedCandidate)
        }
    }
}

private struct ProfileNavigationControls: View {
    @Binding var searchText: String
    @Binding var selectedSection: ProfileNavigationSection
    let scrollTo: (ProfileNavigationSection) -> Void
    @FocusState private var isSearchFocused: Bool
    @AppStorage("selectedAppTheme") private var selectedAppTheme = StyleMatchAppTheme.system.rawValue
    @AppStorage("styleMatchAppearanceMode") private var appearanceMode = StyleMatchAppearanceMode.manual.rawValue
    @AppStorage("styleMatchAdaptiveTheme") private var adaptiveTheme = ""

    private var themeTokens: StyleMatchThemeTokens {
        StyleMatchAppearanceResolver.resolve(
            modeRawValue: appearanceMode,
            selectedThemeRawValue: selectedAppTheme,
            adaptiveThemeRawValue: adaptiveTheme
        ).theme.tokens(for: .profile)
    }

    private var matchingSections: [ProfileNavigationSection] {
        ProfileNavigationSection.allCases.filter { $0.matches(searchText: searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search profile settings", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($isSearchFocused)
                .onSubmit {
                    navigateToBestSearchMatch(using: nil)
                }
                .onChange(of: searchText) { newValue in
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard trimmed.count >= 4 else { return }
                    let matches = ProfileNavigationSection.allCases.filter { $0.matches(searchText: trimmed) }
                    if matches.count == 1 {
                        navigateToSearchMatch(matches[0], using: nil)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(themeTokens.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel("Search profile settings")

            ScrollViewReader { navigationProxy in
                VStack(alignment: .leading, spacing: 10) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(ProfileNavigationSection.allCases, id: \.self) { section in
                                let isSelected = selectedSection == section
                                let selectionBackground: Color = isSelected
                                    ? themeTokens.accent
                                    : themeTokens.cardBackground.opacity(0.72)
                                let selectionForeground: Color = isSelected
                                    ? .white
                                    : themeTokens.primaryText
                                Button {
                                    select(section, using: navigationProxy)
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(section.title)
                                            .fixedSize(horizontal: true, vertical: false)
                                        if isSelected {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.bold))
                                                .accessibilityHidden(true)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .frame(minHeight: 44)
                                    .background(selectionBackground, in: Capsule())
                                    .foregroundStyle(selectionForeground)
                                }
                                .id(section)
                                .accessibilityLabel(section.title)
                                .accessibilityValue(isSelected ? "Selected" : "Not selected")
                                .accessibilityAddTraits(isSelected ? .isSelected : [])
                            }
                        }
                    }
                    .onAppear {
                        scrollToSelectedSection(navigationProxy, section: selectedSection, animated: false)
                    }
                    .onChange(of: selectedSection) { section in
                        scrollToSelectedSection(navigationProxy, section: section)
                    }

                    if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            if matchingSections.isEmpty {
                                Text("No matching profile settings")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4)
                            } else {
                                ForEach(matchingSections) { section in
                                    Button {
                                        select(section, using: navigationProxy)
                                    } label: {
                                        Label(section.title, systemImage: "arrow.down.right.circle")
                                            .font(.subheadline)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 5)
                                    }
                                    .accessibilityLabel("Go to \(section.title) profile settings")
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(themeTokens.elevatedCardBackground)
    }

    private func scrollToSelectedSection(
        _ proxy: ScrollViewProxy,
        section: ProfileNavigationSection,
        animated: Bool = true
    ) {
        if animated {
            withAnimation(.easeInOut) {
                proxy.scrollTo(section, anchor: .leading)
            }
        } else {
            proxy.scrollTo(section, anchor: .leading)
        }
    }

    private func navigateToBestSearchMatch(using proxy: ScrollViewProxy?) {
        let matches = matchingSections
        guard let section = matches.first else { return }
        navigateToSearchMatch(section, using: proxy)
    }

    private func navigateToSearchMatch(_ section: ProfileNavigationSection, using proxy: ScrollViewProxy?) {
        isSearchFocused = false
        searchText = ""
        selectedSection = section
        if let proxy {
            scrollToSelectedSection(proxy, section: section)
        }
        scrollTo(section)
    }

    private func select(_ section: ProfileNavigationSection, using proxy: ScrollViewProxy) {
        navigateToSearchMatch(section, using: proxy)
    }
}

private struct ProfileFormSections: View {
    let identity: AnyView
    let guidance: AnyView
    let preferences: AnyView
    let dataControls: AnyView

    var body: some View {
        Form {
            identity
            guidance
            preferences
            dataControls
        }
    }
}

private struct ProfileNavigationToolbar: ToolbarContent {
    let hasUnsavedChanges: Bool
    let goBack: () -> Void
    let save: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: goBack) {
                Label("Back", systemImage: "chevron.left")
            }
            .accessibilityLabel("Back to Home")
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button("Save", action: save)
                .fontWeight(.semibold)
                .disabled(!hasUnsavedChanges)
        }
    }
}

private struct UndertoneHelpSheet: View {
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Color Undertone")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("This is optional. Choose Not sure or leave it blank if you do not want to provide it.")
                    .foregroundStyle(.secondary)

                Label("Vein check: blue or purple can suggest cool; green can suggest warm; a mix can suggest neutral.", systemImage: "hand.raised")
                Label("Jewelry check: silver often suits cool, gold often suits warm, and both can suit neutral.", systemImage: "sparkles")
                Label("Use what feels accurate. KigoStylist treats this as your preference, not a fact about your identity.", systemImage: "person.crop.circle.badge.checkmark")

                Spacer()
            }
            .padding()
            .navigationTitle("How do I know?")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct StyleConsultationSheet: View {
    @Binding var draft: ProfileEditDraft
    let styleIdentityOptions: [String]
    let styleGoalOptions: [String]
    let pantFitOptions: [String]
    let pantRiseOptions: [String]
    let declaredUndertoneChoices: [DeclaredUndertone]
    let neutralColorOptions: [String]
    let accentColorOptions: [String]
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

    private let shirtSizeOptions = ["XXS", "XS", "S", "M", "L", "XL", "XXL", "2XL", "3XL", "4XL", "5XL", "6XL", "7XL", "8XL"]
    private let shoeSizeOptions = ["4", "4.5", "5", "5.5", "6", "6.5", "7", "7.5", "8", "8.5", "9", "9.5", "10", "10.5", "11", "11.5", "12", "13", "14", "15", "16", "17", "18"]

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
                Picker("Preferred Pant Fit", selection: binding(\.preferredPantFit)) {
                    ForEach(pantFitOptions, id: \.self) { Text($0).tag($0) }
                }
                Picker("Shirt Size", selection: binding(\.shirtSize)) {
                    Text("Choose size").tag("")
                    ForEach(optionsIncludingCurrent(shirtSizeOptions, current: draft.shirtSize), id: \.self) { Text($0).tag($0) }
                }
                measurementField("Waist", keyPath: \.waistSize, prompt: "Add measurement")
                measurementField("Inseam", keyPath: \.inseamLength, prompt: "Add measurement")
                Picker("Shoe Size", selection: binding(\.shoeSize)) {
                    Text("Choose size").tag("")
                    ForEach(optionsIncludingCurrent(shoeSizeOptions, current: draft.shoeSize), id: \.self) { Text($0).tag($0) }
                }
                measurementField("Sleeve Length", keyPath: \.sleeveLength, prompt: "Add measurement")
                measurementField("Neck Size", keyPath: \.neckSize, prompt: "Add measurement")
                Picker("Preferred Pant Rise", selection: binding(\.preferredPantRise)) {
                    ForEach(pantRiseOptions, id: \.self) { Text($0).tag($0) }
                }
                Text("Waist and inseam determine pant sizing. You can update every measurement here or later from Profile.")
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
                    ForEach(declaredUndertoneChoices, id: \.rawValue) { undertone in
                        Text(undertone.displayName).tag(undertone.rawValue)
                    }
                }
                Text("Self-selected only. KigoStylist does not estimate or infer undertone from images.")
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
            draft[keyPath: keyPath] = StyleMatchInputBounds.profileFreeText(newValue)
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
                .accessibilityLabel(StyleMatchAccessibilityText.profileFieldLabel(title: title, isRequired: false))
                .accessibilityValue(StyleMatchAccessibilityText.profileFieldValue(text: draft[keyPath: keyPath]))
                .accessibilityHint("This Style DNA field is optional.")
        }
        .padding(.vertical, 4)
    }

    private func measurementField(
        _ title: String,
        keyPath: WritableKeyPath<ProfileEditDraft, String>,
        prompt: String
    ) -> some View {
        LabeledContent(title) {
            TextField(prompt, text: binding(keyPath))
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel(title)
                .accessibilityHint("Enter this optional measurement.")
        }
    }

    private func optionsIncludingCurrent(_ options: [String], current: String) -> [String] {
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !options.contains(trimmed) else { return options }
        return [trimmed] + options
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
                title: "Fit Profile",
                icon: "tshirt.fill",
                rows: [
                    ("Pant fit", draft.preferredPantFit),
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
                "Sign out of KigoStylist?",
                isPresented: $showSignOutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive, action: signOut)
                Button("Cancel", role: .cancel) {
                }
            } message: {
                Text("Your account and data remain available when you return. Guest data remains separate.")
            }
            .confirmationDialog(
                "Delete your KigoStylist account?",
                isPresented: $showDeleteAccountConfirmation,
                titleVisibility: .visible
            ) {
                Button("Continue to Apple Confirmation", role: .destructive) {
                    isPreparingAccountDeletion = true
                }
                Button("Cancel", role: .cancel) {
                }
            } message: {
                Text("Your account and associated data will be permanently deleted according to our retention policy. If you return later, you can create a new KigoStylist account, but permanently deleted data will not be restored.")
            }
    }
}

private struct ProfileUnsavedChangesConfirmationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let saveAndLeave: () -> Void
    let leaveWithoutSaving: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "You have unsaved profile changes.",
            isPresented: $isPresented,
            titleVisibility: .visible
        ) {
            Button("Save Profile", action: saveAndLeave)
            Button("Leave Without Saving", role: .destructive, action: leaveWithoutSaving)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Save your profile so KigoStylist can use the latest sizes, colors, budget, occasions, and shopping preferences.")
        }
    }
}

private struct ProfileSavedConfirmationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let message: String

    func body(content: Content) -> some View {
        content.alert("Profile saved successfully.", isPresented: $isPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message)
        }
    }
}

private struct ProfileSizeCategoryChangeConfirmationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let message: String
    let confirmChange: () -> Void
    let cancelChange: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Clear incompatible size details?",
            isPresented: $isPresented,
            titleVisibility: .visible
        ) {
            Button("Change Category and Clear Listed Fields", role: .destructive, action: confirmChange)
            Button("Cancel", role: .cancel, action: cancelChange)
        } message: {
            Text(message)
        }
    }
}

private struct AIMemoryManagementView: View {
    @ObservedObject var store: AIPersistentMemoryStore
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingAddMemory = false
    @State private var isShowingRememberedMemories = false
    @State private var showClearAllConfirmation = false
    @State private var feedback: String?

    var body: some View {
        NavigationStack {
            List {
                AIMemoryIntroductionSection()
                AIMemorySummarySection(count: activeMemories.count) {
                    isShowingRememberedMemories = true
                }
                AIMemoryListSections(memories: activeMemories, store: store, feedback: $feedback)
                AIMemoryAddMemorySection(isShowingAddMemory: $isShowingAddMemory)
                AIMemoryTemporaryContextSection(feedback: $feedback)
                AIMemoryControlsSection(showClearAllConfirmation: $showClearAllConfirmation)
                AIMemoryFeedbackSection(feedback: feedback)
            }
            .navigationTitle("AI Memory")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $isShowingAddMemory) {
                AIMemoryAddView(store: store, reviewMemories: {
                    isShowingAddMemory = false
                    DispatchQueue.main.async { self.isShowingRememberedMemories = true }
                }) { message in
                    feedback = message
                    isShowingAddMemory = false
                }
            }
            .sheet(isPresented: $isShowingRememberedMemories) {
                AIMemoryRememberedMemoriesView(store: store, feedback: $feedback) {
                    isShowingRememberedMemories = false
                    DispatchQueue.main.async { self.isShowingAddMemory = true }
                }
            }
            .modifier(AIMemoryClearAllConfirmationModifier(
                isPresented: $showClearAllConfirmation,
                store: store,
                feedback: $feedback
            ))
        }
    }

    private var activeMemories: [AIPersistentMemory] { store.activeMemories() }
}

private struct AIMemoryIntroductionSection: View {
    var body: some View {
        Section {
            Text("KigoStylist can remember preferences you choose to save so your styling advice becomes more personal.")
            Text("You control what is remembered. Viewing a screen or scanning an outfit does not automatically create a memory.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AIMemorySummarySection: View {
    let count: Int
    let showRememberedContent: () -> Void

    var body: some View {
        Section("Remembered") {
            Button(action: showRememberedContent) {
                HStack(spacing: 12) {
                    Text("Memories")
                    Spacer(minLength: 12)
                    Text(countDescription)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remembered memories, \(countDescription)")
            .accessibilityHint("Shows your saved AI memories.")
        }
    }

    private var countDescription: String { "\(count.formatted()) \(count == 1 ? "memory" : "memories")" }
}

private struct AIMemoryRememberedMemoriesView: View {
    @ObservedObject var store: AIPersistentMemoryStore
    @Binding var feedback: String?
    let addMemory: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Preferences and corrections you’ve chosen to let KigoStylist remember.")
                        .foregroundStyle(.secondary)
                }
                Section("Remembered") {
                    LabeledContent("Memories") {
                        Text("\(activeMemories.count.formatted()) \(activeMemories.count == 1 ? "memory" : "memories")")
                            .foregroundStyle(.secondary)
                    }
                }
                AIMemoryListSections(memories: activeMemories, store: store, feedback: $feedback)
                if activeMemories.isEmpty {
                    Section {
                        Button("Add a Memory", action: addMemory)
                            .frame(minHeight: 44)
                            .accessibilityHint("Opens the existing Add a Memory form.")
                    }
                }
            }
            .navigationTitle("Remembered Memories")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var activeMemories: [AIPersistentMemory] { store.activeMemories() }
}

private struct AIMemoryListSections: View {
    let memories: [AIPersistentMemory]
    @ObservedObject var store: AIPersistentMemoryStore
    @Binding var feedback: String?

    var body: some View {
        if memories.isEmpty {
            AIMemoryEmptyStateSection()
        } else {
            AIMemoryCategorySections(memories: memories, store: store, feedback: $feedback)
        }
    }
}

private struct AIMemoryEmptyStateSection: View {
    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Nothing remembered yet", systemImage: "brain")
                    .font(.headline)
                Text("You can ask KigoStylist to remember preferences such as your favorite colors, fit preferences, or work clothing needs.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
    }
}

private struct AIMemoryCategorySections: View {
    let memories: [AIPersistentMemory]
    @ObservedObject var store: AIPersistentMemoryStore
    @Binding var feedback: String?

    var body: some View {
        ForEach(AIPersistentMemoryCategory.allCases, id: \.self) { category in
            AIMemoryCategorySection(
                category: category,
                memories: memories.filter { $0.category == category },
                store: store,
                feedback: $feedback
            )
        }
    }
}

private struct AIMemoryCategorySection: View {
    let category: AIPersistentMemoryCategory
    let memories: [AIPersistentMemory]
    @ObservedObject var store: AIPersistentMemoryStore
    @Binding var feedback: String?

    var body: some View {
        if !memories.isEmpty {
            Section(category.displayName) {
                ForEach(memories) { memory in
                    NavigationLink {
                        AIMemoryDetailView(memory: memory, store: store, feedback: $feedback)
                    } label: {
                        AIMemoryRow(memory: memory)
                    }
                    .accessibilityLabel("\(category.displayName): \(memory.value.displayValue)")
                    .accessibilityHint("Opens memory details and actions.")
                }
                Button("Forget \(category.displayName)", role: .destructive) {
                    feedback = store.forget(category: category)
                        ? "\(category.displayName) memories were cleared."
                        : "\(category.displayName) memories could not be cleared."
                }
            }
        }
    }
}

private struct AIMemoryAddMemorySection: View {
    @Binding var isShowingAddMemory: Bool

    var body: some View {
        Section {
            Button { isShowingAddMemory = true } label: {
                Label("Add a Memory", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .accessibilityHint("Choose a category and save a preference you want KigoStylist to remember.")
        }
    }
}

private struct AIMemoryTemporaryContextSection: View {
    @Binding var feedback: String?
    private let successFeedback = "Temporary AI context cleared. Your saved AI memories were kept."

    var body: some View {
        Section {
            Button("Clear Temporary AI Context") {
                AIMemoryTemporaryContext.clear()
                feedback = successFeedback
                announceSuccess()
            }
            .accessibilityHint("Clears temporary screen and conversation context. Saved AI memories are kept.")
        } header: {
            Text("Context controls")
        } footer: {
            Text("Clears temporary screen and conversation context. Saved AI memories are kept.")
        }
    }

    private func announceSuccess() {
        #if canImport(UIKit)
        UIAccessibility.post(notification: .announcement, argument: successFeedback)
        #endif
    }
}

private struct AIMemoryControlsSection: View {
    @Binding var showClearAllConfirmation: Bool

    var body: some View {
        Section("Memory Controls") {
            Button("Clear All AI Memories", role: .destructive) {
                showClearAllConfirmation = true
            }
        }
    }
}

private struct AIMemoryFeedbackSection: View {
    let feedback: String?

    var body: some View {
        if let feedback {
            Section {
                Text(feedback)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(feedback)
            }
        }
    }
}

private struct AIMemoryClearAllConfirmationModifier: ViewModifier {
    @Binding var isPresented: Bool
    @ObservedObject var store: AIPersistentMemoryStore
    @Binding var feedback: String?

    func body(content: Content) -> some View {
        content.confirmationDialog("Clear All AI Memories?", isPresented: $isPresented, titleVisibility: .visible) {
            Button("Clear AI Memories", role: .destructive) {
                feedback = store.clearAll()
                    ? "AI memories were cleared. Your profile, saved scans, closet items, favorites, and account were kept."
                    : "AI memories could not be cleared. Your saved memories were kept."
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes preferences and corrections saved in AI Memory. It does not delete your Profile, Saved Scans, Closet items, favorites, or account.")
        }
    }
}

private struct AIMemoryRow: View {
    let memory: AIPersistentMemory

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(memory.value.displayValue)
            Text(memory.explainWhy)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("Updated \(memory.updatedAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct AIMemoryAddView: View {
    @ObservedObject var store: AIPersistentMemoryStore
    let reviewMemories: () -> Void
    let didRemember: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var category: AIPersistentMemoryCategory = .stylePreferences
    @State private var text = ""
    @FocusState private var isMemoryTextFocused: Bool
    @State private var isShowingCapacityAlert = false
    @State private var isShowingSaveFailureAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Add a Memory") {
                    Picker("Category", selection: $category) {
                        ForEach(addableCategories, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $text)
                            .focused($isMemoryTextFocused)
                            .font(.body)
                            .frame(minHeight: 88)
                            .contentShape(Rectangle())
                            .simultaneousGesture(TapGesture().onEnded {
                                isMemoryTextFocused = true
                            })

                        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("I prefer black shoes for work")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 9)
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityLabel("Memory text")
                    .accessibilityHint("Enter a preference you want KigoStylist to remember.")
                    Text("Example: I prefer black shoes for work.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add a Memory")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Remember") {
                        switch store.rememberResult(category: category, text: text) {
                        case let .saved(memory):
                            didRemember("Remembered: \(memory.value.displayValue)")
                        case .capacityReached:
                            isShowingCapacityAlert = true
                        case .failed:
                            isShowingSaveFailureAlert = true
                        }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("AI Memory is full", isPresented: $isShowingCapacityAlert) {
                Button("Review Memories") { reviewMemories() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You already have \(AIMemoryPolicy.maximumActiveMemories.formatted()) saved AI memories. Review or forget memories you no longer need before adding another.")
            }
            .alert("Unable to save AI Memory", isPresented: $isShowingSaveFailureAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This memory was not saved. Please try again.")
            }
        }
    }

    private var addableCategories: [AIPersistentMemoryCategory] { AIPersistentMemoryCategory.allCases.filter { $0 != .referencedOutfits } }
}

private struct AIMemoryDetailView: View {
    let memory: AIPersistentMemory
    @ObservedObject var store: AIPersistentMemoryStore
    @Binding var feedback: String?
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false
    @State private var text = ""
    @State private var showForgetConfirmation = false
    @State private var isShowingMemoryExplanation = false

    var body: some View {
        Form {
            Section("Memory") {
                AIMemoryDetailCardAction(
                    value: memory.value.displayValue,
                    accessibilityLabel: "Edit remembered preference",
                    accessibilityHint: "Opens the editor for this remembered preference.",
                    action: beginEditing
                )
            }
            Section("Category") {
                AIMemoryDetailCardAction(
                    value: memory.category.displayName,
                    accessibilityLabel: "Edit memory category",
                    accessibilityHint: "Opens the editor for this memory.",
                    action: beginEditing
                )
            }
            Section("Why KigoStylist remembers this") {
                AIMemoryDetailCardAction(
                    value: memory.explainWhy,
                    accessibilityLabel: "Explain why KigoStylist remembers this",
                    accessibilityHint: "Explains why this preference is remembered.",
                    action: showWhy
                )
            }
            Section {
                Button("Edit Memory", action: beginEditing)
                    .frame(minHeight: 44)
                Button("Explain Why", action: showWhy)
                    .frame(minHeight: 44)
                Button("Forget Memory", role: .destructive) { showForgetConfirmation = true }
                    .frame(minHeight: 44)
            }
        }
        .navigationTitle("Memory Details")
        .sheet(isPresented: $isEditing) {
            NavigationStack {
                Form { Section("Edit Memory") { TextField("Memory", text: $text, axis: .vertical); Text(memory.category.displayName).font(.footnote).foregroundStyle(.secondary) } }
                    .navigationTitle("Edit Memory")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { isEditing = false } }
                        ToolbarItem(placement: .confirmationAction) { Button("Save Changes") { if let updated = store.edit(memory, text: text) { feedback = "Updated: \(updated.value.displayValue)"; isEditing = false; dismiss() } }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                    }
            }
        }
        .sheet(isPresented: $isShowingMemoryExplanation) {
            AIMemoryExplanationView(
                memory: memory,
                editMemory: editFromExplanation,
                forgetMemory: forgetFromExplanation
            )
        }
        .confirmationDialog("Forget this memory?", isPresented: $showForgetConfirmation, titleVisibility: .visible) {
            Button("Forget Memory", role: .destructive) {
                if store.forget(memory.id) {
                    feedback = "Memory forgotten."
                    dismiss()
                } else {
                    feedback = "Memory could not be forgotten."
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func beginEditing() {
        text = memory.value.displayValue
        isEditing = true
    }

    private func showWhy() {
        isShowingMemoryExplanation = true
    }

    private func editFromExplanation() {
        isShowingMemoryExplanation = false
        DispatchQueue.main.async { self.beginEditing() }
    }

    private func forgetFromExplanation() {
        isShowingMemoryExplanation = false
        DispatchQueue.main.async { self.showForgetConfirmation = true }
    }
}

private struct AIMemoryExplanationView: View {
    let memory: AIPersistentMemory
    let editMemory: () -> Void
    let forgetMemory: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Memory") { Text(memory.value.displayValue) }
                Section("Category") { Text(memory.category.displayName) }
                Section("Why it’s remembered") { Text(memory.explainWhy) }
                Section("How it helps") { Text(memory.explainHowItHelps) }
                Section("Your control") {
                    Text("You can edit or forget this memory at any time.")
                }
                Section {
                    Button("Edit Memory", action: editMemory)
                        .frame(minHeight: 44)
                    Button("Forget Memory", role: .destructive, action: forgetMemory)
                        .frame(minHeight: 44)
                }
            }
            .navigationTitle("Why KigoStylist remembers this")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct AIMemoryDetailCardAction: View {
    let value: String
    let accessibilityLabel: String
    let accessibilityHint: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(value)
                    .foregroundStyle(.primary)
                Spacer(minLength: 12)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }
}

private struct ProfileClearAIMemoryConfirmationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let clearAIMemory: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Clear AI memory?",
            isPresented: $isPresented,
            titleVisibility: .visible
        ) {
            Button("Clear AI Memory", role: .destructive, action: clearAIMemory)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes locally saved AI Memory and turns it off. It does not delete your profile, closet, scan history, or shopping records.")
        }
    }
}

private struct ProfileClearScanHistoryConfirmationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let clearScanHistory: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Clear scan history?",
            isPresented: $isPresented,
            titleVisibility: .visible
        ) {
            Button("Clear Scan History", role: .destructive, action: clearScanHistory)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes saved scan history from this phone. It does not change your profile, closet, or account data.")
        }
    }
}

private struct ProfileGuestTransferConfirmationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let transferGuestData: () -> Void
    let continueWithoutTransfer: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Transfer Guest Data?",
            isPresented: $isPresented,
            titleVisibility: .visible
        ) {
            Button("Transfer My Guest Data", action: transferGuestData)
            Button("Continue Without Transfer", action: continueWithoutTransfer)
        } message: {
            Text("KigoStylist can keep your local scan history, favorites, closet, style preferences, and profile information with your Apple sign-in.")
        }
    }
}

private struct ProfileAccountIdentityCard: View {
    let title: String
    let detail: String
    let icon: String
    let isAppleAccount: Bool
    let hasValidBackendSession: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(ProfilePremiumPalette.cream)
                .frame(width: 42, height: 42)
                .background(ProfilePremiumPalette.cream.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(isAppleAccount
                     ? (hasValidBackendSession ? "Apple authorized • Backend session active" : "Apple authorized • Backend session expired")
                     : "Local profile")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isAppleAccount && hasValidBackendSession ? .green : .secondary)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(ProfilePremiumPalette.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(ProfilePremiumPalette.cream.opacity(0.30), lineWidth: 1) }
    }
}

private enum ProfilePremiumPalette {
    static let cream = Color(red: 0.98, green: 0.84, blue: 0.52)
    static let cardBackground = Color.black.opacity(0.26)
}

struct StyleMatchToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool
    let feedback: String?
    let accessibilityHint: String
    var isDisabled = false

    private var stateTitle: String {
        if isDisabled { return "Not active" }
        return isOn ? "On" : "Off"
    }

    private var stateColor: Color {
        if isDisabled { return ProfilePremiumPalette.cream }
        return isOn ? .green : .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            control

            if let feedback {
                feedbackText(feedback)
            }
        }
        .padding(16)
        .background(ProfilePremiumPalette.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isDisabled ? ProfilePremiumPalette.cream.opacity(0.38) : ProfilePremiumPalette.cream.opacity(0.32), lineWidth: 1)
        }
    }

    @ViewBuilder private var control: some View {
        if isDisabled {
            disabledControl
        } else {
            enabledControl
        }
    }

    private var disabledControl: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: "icloud.slash").font(.headline)
                Text(stateTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(stateColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(ProfilePremiumPalette.cream.opacity(0.14), in: Capsule())
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(title)
                    .accessibilityValue("Not active in this build.")
                    .accessibilityHint(accessibilityHint)
                Text(description).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "icloud.fill")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(ProfilePremiumPalette.cream.opacity(0.78))
                .accessibilityHidden(true)
        }
    }

    private var enabledControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(title, isOn: $isOn)
            Text(description).font(.caption).foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(title)
                .accessibilityValue(isOn ? "On" : "Off")
                .accessibilityHint(accessibilityHint)
        }
    }

    private func feedbackText(_ feedback: String) -> some View {
        Text(feedback)
            .font(.caption)
            .foregroundStyle(isDisabled ? Color.secondary : Color.green)
            .accessibilityAddTraits(.isStaticText)
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
    let hasValidBackendSession: Bool
    @Binding var isReconnectingBackendSession: Bool
    @Binding var isPreparingAccountDeletion: Bool
    @Binding var showSignOutConfirmation: Bool
    @Binding var showDeleteAccountConfirmation: Bool
    let prepareAppleRequest: (ASAuthorizationAppleIDRequest) -> Void
    let handleAppleSignIn: (Result<ASAuthorization, Error>) -> Void
    let handleDeletionAuthorization: (Result<ASAuthorization, Error>) -> Void
    let cancelDeletionAuthorization: () -> Void
    @State private var cloudSyncPreferenceFeedback: String?
    @State private var ownerValidationCloudSyncStatus: CloudSyncStatus?
    @State private var isCloudSyncLifecycleInFlight = false
    @State private var hasRequestedInboundLifecycle = false

    var body: some View {
        Section("Account") {
            ProfileAccountIdentityCard(
                title: accountStatusTitle,
                detail: selectedAccountMode.description,
                icon: accountIcon,
                isAppleAccount: selectedAccountMode == .apple,
                hasValidBackendSession: hasValidBackendSession
            )

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
                isReconnectingBackendSession = false
                request.requestedScopes = [.fullName, .email]
                prepareAppleRequest(request)
            } onCompletion: { result in
                handleAppleSignIn(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .disabled(isAccountRequestInFlight)

            Text("You are using KigoStylist as a guest. Sign in with Apple to save your profile, closet, favorites, and scan history.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var appleControls: some View {
        let presentation = CloudSyncPresentation(
            status: ownerValidationCloudSyncStatus
                ?? CloudSyncProductContract.preActivationStatus(isSwitchOn: accountSyncEnabled)
        )

        StyleMatchToggleRow(
            title: "Cloud Sync",
            description: CloudSyncProductContract.customerControlsEnabled
                ? presentation.detail
                : CloudSyncProductContract.preActivationOnDetail,
            isOn: cloudSyncPreferenceBinding,
            feedback: cloudSyncPreferenceFeedback,
            accessibilityHint: CloudSyncIdentityBoundary.v1.customerFacingDescription,
            isDisabled: !CloudSyncProductContract.customerControlsEnabled
        )
        .task(id: accountSyncEnabled) {
            hydratePersistedInboundFailureIfPresent()
            guard accountSyncEnabled,
                  CloudSyncOwnerValidationConfiguration.runtime.allowsInboundDiagnosticReconciliation,
                  !hasRequestedInboundLifecycle,
                  !isCloudSyncLifecycleInFlight else { return }
            hasRequestedInboundLifecycle = true
            await reconcileInboundAtLifecycleBoundary()
        }

        if CloudSyncProductContract.customerControlsEnabled && accountSyncEnabled {
            Button {
                guard !isCloudSyncLifecycleInFlight, CloudSyncRuntimeGate.begin() else {
                    cloudSyncPreferenceFeedback = "Cloud Sync is already in progress."
                    return
                }
                ownerValidationCloudSyncStatus = .syncing
                isCloudSyncLifecycleInFlight = true
                cloudSyncPreferenceFeedback = "Syncing eligible data with your private iCloud database…"
                Task { @MainActor in
                    defer {
                        CloudSyncRuntimeGate.end()
                        isCloudSyncLifecycleInFlight = false
                    }
                    let result = await CloudSyncOwnerLifecycle.live().enableAndValidate()
                    guard accountSyncEnabled else { return }
                    let outcome = result.inbound ?? result.validation
                    ownerValidationCloudSyncStatus = outcome.status
                    cloudSyncPreferenceFeedback = ownerValidationFeedback(for: outcome)
                    announceCloudSyncPreferenceFeedback()
                }
            } label: {
                Label(isCloudSyncLifecycleInFlight ? "Syncing…" : "Sync Now", systemImage: "arrow.triangle.2.circlepath.icloud")
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.borderedProminent)
            .tint(ProfilePremiumPalette.cream)
            .foregroundStyle(.black)
            .disabled(isCloudSyncLifecycleInFlight)
        }

        VStack(alignment: .leading, spacing: 12) {
            Label(
                CloudSyncProductContract.customerControlsEnabled ? "Data synced with iCloud" : "Data eligible for future Cloud Sync",
                systemImage: "externaldrive.connected.to.line.below"
            )
                .font(.headline)
            Text(CloudSyncIdentityBoundary.v1.customerFacingDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(CloudSyncProductContract.customerControlsEnabled
                 ? CloudSyncProductContract.futureOffAndDeletionDetail
                 : CloudSyncProductContract.preActivationConsentDetail)
                .font(.caption.weight(.semibold))

            ForEach(CloudSyncProductContract.eligibleCustomerData, id: \.self) { category in
                Label(category, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
        }
        .padding(16)
        .background(ProfilePremiumPalette.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(ProfilePremiumPalette.cream.opacity(0.27), lineWidth: 1)
        }

        if !hasValidBackendSession {
            Text("Your Apple account is connected, but secure AI and account services need a renewed session.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            SignInWithAppleButton(.continue) { request in
                isReconnectingBackendSession = true
                request.requestedScopes = []
                prepareAppleRequest(request)
            } onCompletion: { result in
                handleAppleSignIn(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .disabled(isAccountRequestInFlight)
            .accessibilityLabel("Reconnect KigoStylist with Apple")
        }

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
            Text("Confirm with Apple to permanently delete your KigoStylist account.")
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

    private var cloudSyncPreferenceBinding: Binding<Bool> {
        Binding(
            get: { accountSyncEnabled },
            set: { newValue in
                let previousValue = accountSyncEnabled
                accountSyncEnabled = newValue

                guard UserDefaults.standard.object(forKey: "customerAccountSyncEnabled") as? Bool == newValue else {
                    accountSyncEnabled = previousValue
                    cloudSyncPreferenceFeedback = "Cloud Sync preference could not be updated. No data is syncing today."
                    announceCloudSyncPreferenceFeedback()
                    return
                }

                cloudSyncPreferenceFeedback = newValue
                    ? (CloudSyncProductContract.customerControlsEnabled
                        ? "Cloud Sync is on. Preparing a private iCloud synchronization…"
                        : CloudSyncProductContract.preActivationOnDetail)
                    : "Cloud Sync is off. No data is syncing today."
                ownerValidationCloudSyncStatus = newValue ? nil : .off
                if !newValue { hasRequestedInboundLifecycle = false }
                announceCloudSyncPreferenceFeedback()

                guard newValue, CloudSyncOwnerValidationConfiguration.runtime.isEnabled else {
                    return
                }
                guard CloudSyncRuntimeGate.begin() else {
                    cloudSyncPreferenceFeedback = "Cloud Sync is already in progress."
                    return
                }

                ownerValidationCloudSyncStatus = .syncing
                isCloudSyncLifecycleInFlight = true
                hasRequestedInboundLifecycle = true
                cloudSyncPreferenceFeedback = "Syncing eligible data with your private iCloud database. Local data remains available."
                Task { @MainActor in
                    defer {
                        CloudSyncRuntimeGate.end()
                        isCloudSyncLifecycleInFlight = false
                    }
                    let result = await CloudSyncOwnerLifecycle.live().enableAndValidate()
                    guard accountSyncEnabled else { return }
                    let outcome = result.inbound ?? result.validation
                    ownerValidationCloudSyncStatus = outcome.status
                    cloudSyncPreferenceFeedback = ownerValidationFeedback(for: outcome)
                    announceCloudSyncPreferenceFeedback()
                }
            }
        )
    }

    @MainActor
    private func reconcileInboundAtLifecycleBoundary() async {
        guard CloudSyncRuntimeGate.begin() else { return }
        isCloudSyncLifecycleInFlight = true
        let stored = CloudSyncOperationalStateStore(scope: CloudSyncProductContract.runtimeScope).load()
        ownerValidationCloudSyncStatus = stored.status == .off ? .syncing : stored.status
        let lifecycle = CloudSyncOwnerLifecycle.live()
        let outcome: CloudSyncOwnerValidationOutcome
        if CloudSyncOwnerValidationConfiguration.runtime.isOwnerBetaBuild {
            let result = await lifecycle.enableAndValidate()
            outcome = result.inbound ?? result.validation
        } else {
            outcome = await lifecycle.reconcileOnLifecycleBoundary(isEnabled: accountSyncEnabled)
        }
        guard accountSyncEnabled else {
            CloudSyncRuntimeGate.end()
            isCloudSyncLifecycleInFlight = false
            return
        }
        ownerValidationCloudSyncStatus = outcome.status
        cloudSyncPreferenceFeedback = CloudSyncInboundDiagnosticPresentation.feedback(
            for: CloudSyncOperationalStateStore(scope: CloudSyncProductContract.runtimeScope).inboundFailureCategory()
        ) ?? ownerValidationFeedback(for: outcome)
        CloudSyncRuntimeGate.end()
        isCloudSyncLifecycleInFlight = false
        announceCloudSyncPreferenceFeedback()
    }

    private func hydratePersistedInboundFailureIfPresent() {
        // OwnerBeta 18049 uses its own operational-state scope, so legacy
        // Build 18036-18038 diagnostics cannot leak into this acceptance lane.
        // Builds without an authorized inbound runtime still clear presentation
        // state rather than surfacing a stale failure.
        guard CloudSyncOwnerValidationConfiguration.runtime.allowsInboundDiagnosticReconciliation else {
            ownerValidationCloudSyncStatus = nil
            cloudSyncPreferenceFeedback = nil
            return
        }
        guard accountSyncEnabled,
              let feedback = CloudSyncInboundDiagnosticPresentation.feedback(
                for: CloudSyncOperationalStateStore(scope: CloudSyncProductContract.runtimeScope).inboundFailureCategory()
              ) else { return }
        ownerValidationCloudSyncStatus = .needsAttention
        cloudSyncPreferenceFeedback = feedback
    }

    private func ownerValidationFeedback(for outcome: CloudSyncOwnerValidationOutcome) -> String {
        switch outcome {
        case .disabled:
            return CloudSyncProductContract.preActivationOnDetail
        case .off:
            return CloudSyncProductContract.preActivationOffDetail
        case .syncing:
            return "Cloud Sync is in progress."
        case .upToDate:
            return "Cloud Sync is up to date for this iCloud account."
        case .offline:
            return "Cloud Sync is offline. Local data remains available and will retry when iCloud is reachable."
        case let .needsAttention(diagnostic):
            return diagnostic.ownerMessage
        }
    }

    private func announceCloudSyncPreferenceFeedback() {
        #if canImport(UIKit)
        UIAccessibility.post(notification: .announcement, argument: cloudSyncPreferenceFeedback)
        #endif
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
    var preferredPantRise = "No Preference"
    var preferredPantFit = PantFitPreference.unset.displayName
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
        preferredPantRise = PantRisePreference.normalized(preferredPantRise)
        preferredPantFit = PantFitPreference.migratedValue(
            currentValue: preferredPantFit,
            legacyOverallFit: fitPreference
        )
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
        let pantFit = PantFitPreference.fromProfileInput(preferredPantFit)
        if pantFit.isSet {
            rows.append(("Preferred Pant Fit", pantFit.displayName))
        }
        if preferredPantRise != "No Preference" {
            rows.append(("Preferred Pant Rise", preferredPantRise))
        }
        return rows
    }

    var sizeFieldValues: ProfileSizeFieldValues {
        ProfileSizeFieldValues(
            shirtSize: shirtSize,
            pantsSize: pantsSize,
            dressSize: dressSize,
            waistSize: waistSize,
            inseamLength: inseamLength,
            neckSize: neckSize,
            sleeveLength: sleeveLength,
            shoeSize: shoeSize
        )
    }

    mutating func applySizeCategoryChange(_ change: ProfileSizeCategoryChange) {
        var fields = sizeFieldValues
        change.apply(to: &fields)
        sizeCategory = change.requestedCategory
        shirtSize = fields.shirtSize
        pantsSize = fields.pantsSize
        dressSize = fields.dressSize
        waistSize = fields.waistSize
        inseamLength = fields.inseamLength
        neckSize = fields.neckSize
        sleeveLength = fields.sleeveLength
        shoeSize = fields.shoeSize
        reconcileGeneratedPantsSize()
    }

    private func normalized(_ text: String, fallback: String) -> String {
        let trimmed = StyleMatchInputBounds.profileFreeText(text)
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

    /// Curated customer choices. All legacy identifiers remain decodable so a
    /// device-local preference from an earlier supported build stays safe.
    static let availableThemes: [StyleMatchAppTheme] = [.styleMatchAI, .system, .dark, .blackAMOLED, .premiumPink, .blue, .green, .light]

    var title: String {
        switch self {
        case .styleMatchAI:
            return "KigoStylist Signature"
        case .system:
            return "System"
        case .light:
            return "Monochrome"
        case .dark:
            return "Midnight"
        case .premiumPink:
            return "Rose Fashion"
        case .purple:
            return "Purple Theme"
        case .blue:
            return "Ocean"
        case .green:
            return "Emerald"
        case .blackAMOLED:
            return "Luxury Gold"
        }
    }

    var detail: String {
        switch self {
        case .styleMatchAI:
            return "Electric violet, fashion pink, mint, amber, coral, and gold."
        case .system:
            return "Follows your iPhone display setting."
        case .light:
            return "Keeps KigoStylist bright and clean."
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

    /// Version 1 deterministic semantic-token authority. The finite
    /// `StyleMatchAppTheme` registry remains the only rendering authority.
    func tokens(for tab: AppTab) -> StyleMatchThemeTokens {
        let palette = palette(for: tab)
        return StyleMatchThemeTokens(
            backgroundStart: palette.start,
            backgroundMiddle: palette.middle,
            backgroundEnd: palette.end,
            cardBackground: palette.card,
            elevatedCardBackground: self == .blackAMOLED ? Color(hex: 0x080808) : Color(.secondarySystemBackground),
            primaryText: Color.primary,
            secondaryText: Color.secondary,
            accent: palette.accent,
            secondaryAccent: palette.middle,
            premiumAccent: self == .blackAMOLED ? StyleMatchPremiumPalette.champagne : palette.end,
            divider: palette.accent,
            success: Color.green,
            warning: Color.orange,
            error: Color.red,
            aiAccent: self.palette(for: .ai).accent,
            scanAccent: self.palette(for: .scan).accent,
            weatherAccent: self.palette(for: .home).accent,
            shopAccent: self.palette(for: .shop).accent,
            socialAccent: self.palette(for: .profile).accent
        )
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
    @Binding var selectedThemeIntensity: Double
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage("styleMatchAppearanceMode") private var appearanceMode = StyleMatchAppearanceMode.manual.rawValue
    @AppStorage("styleMatchAdaptiveTheme") private var adaptiveTheme = ""
    @AppStorage("styleMatchAdaptiveThemeLock") private var adaptiveThemeLocked = false
    @State private var draftTheme: String
    @State private var draftIntensity: Double

    init(selectedTheme: Binding<String>, selectedThemeIntensity: Binding<Double>) {
        _selectedTheme = selectedTheme
        _selectedThemeIntensity = selectedThemeIntensity
        _draftTheme = State(initialValue: selectedTheme.wrappedValue)
        _draftIntensity = State(initialValue: selectedThemeIntensity.wrappedValue)
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
        StyleMatchAppearanceResolver.resolve(
            modeRawValue: appearanceMode,
            selectedThemeRawValue: selectedTheme,
            adaptiveThemeRawValue: adaptiveTheme
        ).theme
    }

    private var resolvedMode: StyleMatchAppearanceMode { StyleMatchAppearanceMode.resolve(appearanceMode) }

    private var adaptiveAccessibility: StyleMatchAdaptiveAccessibility {
        .init(
            colorScheme: colorScheme,
            increaseContrast: colorSchemeContrast == .increased,
            differentiateWithoutColor: differentiateWithoutColor,
            reduceTransparency: reduceTransparency
        )
    }

    private var adaptiveDecision: StyleMatchAdaptiveDecision {
        StyleMatchAdaptiveDecisionEngine.recommendation(
            hour: Calendar.current.component(.hour, from: Date()),
            accessibility: adaptiveAccessibility
        )
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
                Section("Appearance Mode") {
                    Picker("Appearance Mode", selection: $appearanceMode) {
                        ForEach(StyleMatchAppearanceMode.allCases) { mode in
                            Text(mode.rawValue.capitalized).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityHint("Manual keeps your choice. System follows iPhone appearance. Adaptive uses an approved local recommendation.")

                    if resolvedMode == .adaptive {
                        adaptiveAppearanceCard
                    }
                }

                Section {
                    themePreviewCard
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    .listRowBackground(Color.clear)
                }

                Section("Choose Theme To Preview") {
                    ForEach(StyleMatchAppTheme.availableThemes) { theme in
                        themeChoiceRow(theme)
                    }
                }

                Section("Tweak Before Applying") {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Color richness")
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
                            Text("Expressive")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Text("Color richness controls the visibility of theme surfaces.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    applyThemeButton
                }

                Section {
                    Text("Preview never changes the app until you apply it.")
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
                refreshAdaptiveThemeIfNeeded()
            }
            .onChange(of: appearanceMode) { _ in refreshAdaptiveThemeIfNeeded() }
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
            if resolvedMode == .adaptive {
                adaptiveTheme = draftTheme
                adaptiveThemeLocked = true
            }
        }
    }

    private var adaptiveAppearanceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Current adaptive theme")
                .font(.headline)
            Text(appliedTheme.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(appliedPalette.accent)
            Text(adaptiveExplanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Button("Keep this theme") {
                    adaptiveTheme = appliedTheme.rawValue
                    adaptiveThemeLocked = true
                }
                .buttonStyle(.borderedProminent)
                .tint(appliedPalette.accent)

                Button("Return to Adaptive") {
                    adaptiveThemeLocked = false
                    refreshAdaptiveThemeIfNeeded(force: true)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }

    private var adaptiveExplanation: String {
        switch adaptiveDecision.reasonCode {
        case "evening_editorial": return "Midnight gives your evening experience a more refined, editorial feel."
        case "elevated_occasion": return "Luxury Gold adds a more elevated finish."
        case "minimal_editorial": return "Monochrome keeps KigoStylist clean and fashion-forward."
        default: return "KigoStylist selected an approved look that fits the current moment."
        }
    }

    private func refreshAdaptiveThemeIfNeeded(force: Bool = false) {
        guard resolvedMode == .adaptive else { return }
        guard force || !adaptiveThemeLocked || StyleMatchAppTheme(rawValue: adaptiveTheme) == nil else { return }
        adaptiveTheme = adaptiveDecision.recommendedTheme.rawValue
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
                    Text("\(previewTheme.title) • \(Int(draftIntensity * 100))% richness")
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

private struct SupportFAQView: View {
    var body: some View {
        List {
            Section("Scans") {
                Text("For the clearest result, photograph the full outfit in even lighting with the clothing unobstructed.")
                Text("Saved scans keep their original score and analysis until you delete them.")
            }
            Section("Accounts") {
                Text("Sign out keeps your Apple account data on the server. Delete Account revokes the Apple token and removes your saved KigoStylist data.")
            }
            Section("Shopping") {
                Text("Retailer links open outside KigoStylist. Prices and availability can change at the retailer.")
            }
        }
        .navigationTitle("FAQ")
        .navigationBarTitleDisplayMode(.inline)
    }
}
