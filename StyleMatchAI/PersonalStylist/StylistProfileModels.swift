import Foundation

enum StyleMatchGreetingBuilder {
    static func periodGreeting(for date: Date = Date(), calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<12:
            return "Good Morning"
        case 12..<17:
            return "Good Afternoon"
        default:
            return "Good Evening"
        }
    }

    static func firstName(from storedName: String?) -> String? {
        let trimmed = (storedName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let blockedPlaceholders = [
            ["Style", "Match", "Pro", "User"].joined(separator: " "),
            ["StyleMatch", "Pro", "User"].joined(separator: " "),
            ["StyleMatch", "User"].joined(separator: " "),
            ["Saba", "stine"].joined()
        ]

        guard !blockedPlaceholders.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            return nil
        }

        return trimmed.components(separatedBy: .whitespacesAndNewlines).first
    }

    static func greetingLine(date: Date = Date(), calendar: Calendar = .current, storedName: String?) -> String {
        let greeting = periodGreeting(for: date, calendar: calendar)
        guard let firstName = firstName(from: storedName) else {
            return greeting
        }
        return "\(greeting), \(firstName)"
    }
}

enum StyleMatchAccountNameResolver {
    enum Source: String {
        case appleCredential
        case localDisplayName
        case storedProfile
        case unavailable
    }

    struct Resolution: Equatable {
        let displayName: String?
        let givenName: String?
        let source: Source
    }

    static func resolve(
        appleGivenName: String?,
        appleFamilyName: String?,
        localDisplayName: String?,
        storedProfileGivenName: String?
    ) -> Resolution {
        let givenName = firstToken(from: appleGivenName)
        let familyName = clean(appleFamilyName)
        let appleDisplayName = [givenName, familyName].compactMap { $0 }.joined(separator: " ")

        if let displayName = clean(appleDisplayName) {
            return Resolution(displayName: displayName, givenName: givenName, source: .appleCredential)
        }

        if let displayName = clean(localDisplayName) {
            return Resolution(
                displayName: displayName,
                givenName: firstToken(from: displayName),
                source: .localDisplayName
            )
        }

        if let givenName = firstToken(from: storedProfileGivenName) {
            return Resolution(displayName: givenName, givenName: givenName, source: .storedProfile)
        }

        return Resolution(displayName: nil, givenName: nil, source: .unavailable)
    }

    static func resolveStoredProfileThenLocal(
        storedProfileGivenName: String?,
        localDisplayName: String?
    ) -> Resolution {
        if let givenName = profileGivenName(from: storedProfileGivenName) {
            return Resolution(displayName: givenName, givenName: givenName, source: .storedProfile)
        }

        if let displayName = clean(localDisplayName) {
            return Resolution(
                displayName: displayName,
                givenName: profileGivenName(from: displayName),
                source: .localDisplayName
            )
        }

        return Resolution(displayName: nil, givenName: nil, source: .unavailable)
    }

    static func mergeDraftName(_ draftName: String, storedProfileGivenName: String?) -> String {
        if let draftName = clean(draftName) {
            return draftName
        }
        return profileGivenName(from: storedProfileGivenName) ?? ""
    }

    static func profileGivenName(from value: String?) -> String? {
        firstToken(from: value)
    }

    static func clean(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func firstToken(from value: String?) -> String? {
        clean(value)?.components(separatedBy: .whitespacesAndNewlines).first
    }
}

enum StyleMatchAppleCredentialProfileApplier {
    static let accountEmailBaseKey = "customerAccountEmail"

    struct Result: Equatable {
        let displayName: String?
        let givenName: String?
        let email: String?
        let source: StyleMatchAccountNameResolver.Source
    }

    @discardableResult
    static func applyAppleCredential(
        userID: String,
        email: String?,
        appleGivenName: String?,
        appleFamilyName: String?,
        localDisplayName: String?,
        defaults: UserDefaults = .standard
    ) -> Result {
        let store = ProfileStore(defaults: defaults, userId: userID)

        if let cleanEmail = StyleMatchAccountNameResolver.clean(email) {
            defaults.set(cleanEmail, forKey: scopedEmailKey(userID: userID))
        }
        let resolvedEmail = storedEmail(defaults: defaults, userID: userID)

        let appleResolution = StyleMatchAccountNameResolver.resolve(
            appleGivenName: appleGivenName,
            appleFamilyName: appleFamilyName,
            localDisplayName: nil,
            storedProfileGivenName: nil
        )

        if let appleGivenName = appleResolution.givenName {
            store.updateGivenName(appleGivenName)
            return Result(
                displayName: appleResolution.displayName,
                givenName: appleGivenName,
                email: resolvedEmail,
                source: .appleCredential
            )
        }

        let fallbackResolution = StyleMatchAccountNameResolver.resolveStoredProfileThenLocal(
            storedProfileGivenName: store.currentProfile.givenName,
            localDisplayName: localDisplayName
        )

        if fallbackResolution.source == .localDisplayName,
           let givenName = fallbackResolution.givenName {
            store.updateGivenName(givenName)
        }

        return Result(
            displayName: fallbackResolution.displayName,
            givenName: fallbackResolution.givenName,
            email: resolvedEmail,
            source: fallbackResolution.source
        )
    }

    static func storedEmail(defaults: UserDefaults = .standard, userID: String) -> String? {
        StyleMatchAccountNameResolver.clean(defaults.string(forKey: scopedEmailKey(userID: userID)))
    }

    static func scopedEmailKey(userID: String) -> String {
        PersonalStylistStorage.scopedKey(accountEmailBaseKey, userID: userID)
    }
}

enum StyleMatchAccountModeDisplay {
    static func accountStatusTitle(for rawValue: String) -> String {
        switch rawValue {
        case "Sign in with Apple", "apple":
            return "Signed in with Apple"
        case "Email and Password", "email":
            return "Email account"
        default:
            return "Guest"
        }
    }
}

struct StylistProfile: Codable, Identifiable {
    let id: UUID
    var userId: String
    var givenName: String?
    var favoriteColors: [String]
    var dislikedColors: [String]
    var favoriteBrands: [String]
    var preferredFit: FitPreference
    var budgetRange: BudgetRange
    var climate: String
    var workDressCode: String
    var bodyProportions: BodyProportions?
    var clothingSizes: ClothingSizes
    var stylePreferencesLearned: [String: Double]
    var createdAt: Date
    var lastUpdatedAt: Date
    var totalScansCompleted: Int
    var profileConfidenceScore: Double

    init(
        id: UUID,
        userId: String,
        givenName: String? = nil,
        favoriteColors: [String],
        dislikedColors: [String],
        favoriteBrands: [String],
        preferredFit: FitPreference,
        budgetRange: BudgetRange,
        climate: String,
        workDressCode: String,
        bodyProportions: BodyProportions?,
        clothingSizes: ClothingSizes,
        stylePreferencesLearned: [String: Double],
        createdAt: Date,
        lastUpdatedAt: Date,
        totalScansCompleted: Int,
        profileConfidenceScore: Double
    ) {
        self.id = id
        self.userId = userId
        self.givenName = StyleMatchAccountNameResolver.profileGivenName(from: givenName)
        self.favoriteColors = favoriteColors
        self.dislikedColors = dislikedColors
        self.favoriteBrands = favoriteBrands
        self.preferredFit = preferredFit
        self.budgetRange = budgetRange
        self.climate = climate
        self.workDressCode = workDressCode
        self.bodyProportions = bodyProportions
        self.clothingSizes = clothingSizes
        self.stylePreferencesLearned = stylePreferencesLearned
        self.createdAt = createdAt
        self.lastUpdatedAt = lastUpdatedAt
        self.totalScansCompleted = max(0, totalScansCompleted)
        self.profileConfidenceScore = min(100, max(0, profileConfidenceScore))
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let now = Date()
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        userId = try container.decodeIfPresent(String.self, forKey: .userId) ?? "guest"
        givenName = StyleMatchAccountNameResolver.profileGivenName(from: try container.decodeIfPresent(String.self, forKey: .givenName))
        favoriteColors = try container.decodeIfPresent([String].self, forKey: .favoriteColors) ?? []
        dislikedColors = try container.decodeIfPresent([String].self, forKey: .dislikedColors) ?? []
        favoriteBrands = try container.decodeIfPresent([String].self, forKey: .favoriteBrands) ?? []
        preferredFit = try container.decodeIfPresent(FitPreference.self, forKey: .preferredFit) ?? .unset
        budgetRange = try container.decodeIfPresent(BudgetRange.self, forKey: .budgetRange) ?? .neutral
        climate = try container.decodeIfPresent(String.self, forKey: .climate) ?? ""
        workDressCode = try container.decodeIfPresent(String.self, forKey: .workDressCode) ?? ""
        bodyProportions = try container.decodeIfPresent(BodyProportions.self, forKey: .bodyProportions)
        clothingSizes = try container.decodeIfPresent(ClothingSizes.self, forKey: .clothingSizes) ?? ClothingSizes()
        stylePreferencesLearned = try container.decodeIfPresent([String: Double].self, forKey: .stylePreferencesLearned) ?? [:]
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? now
        lastUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .lastUpdatedAt) ?? createdAt
        totalScansCompleted = max(0, try container.decodeIfPresent(Int.self, forKey: .totalScansCompleted) ?? 0)
        profileConfidenceScore = min(100, max(0, try container.decodeIfPresent(Double.self, forKey: .profileConfidenceScore) ?? 20))
    }
}

struct TopStylePreferences: Codable, Equatable {
    var colors: [String]
    var categories: [String]
    var styleTags: [String]

    static let empty = TopStylePreferences(colors: [], categories: [], styleTags: [])
}

enum FitPreference: String, Codable, CaseIterable {
    case unset = ""
    case slim
    case relaxed
    case oversized
    case tailored
    case athletic
    case regular

    static func fromProfileInput(_ value: String?) -> FitPreference {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return .unset }
        return FitPreference(rawValue: trimmed.lowercased()) ?? .unset
    }

    var isSet: Bool {
        self != .unset
    }
}

struct BudgetRange: Codable {
    var minPrice: Double
    var maxPrice: Double
    var preferredTier: String

    static let neutral = BudgetRange(minPrice: 0, maxPrice: 0, preferredTier: "")
}

struct BodyProportions: Codable {
    var heightInches: Double?
    var bodyType: String?
    var notes: String?
}

struct ClothingSizes: Codable {
    var shirtSize: String?
    var pantSize: String?
    var shoeSize: String?
    var jacketSize: String?
    var dressSize: String?

    init(
        shirtSize: String? = nil,
        pantSize: String? = nil,
        shoeSize: String? = nil,
        jacketSize: String? = nil,
        dressSize: String? = nil
    ) {
        self.shirtSize = shirtSize
        self.pantSize = pantSize
        self.shoeSize = shoeSize
        self.jacketSize = jacketSize
        self.dressSize = dressSize
    }
}

struct PantsSizeMeasurements: Equatable {
    let waist: String
    let inseam: String
}

struct PantsSizeVisibleValues: Equatable {
    let pantsSize: String
    let waistSize: String
    let inseamLength: String
}

enum PantsSizeEditSource: String {
    case picker
    case manual
}

enum PantsSizeSync {
    static func cleaned(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func measurements(from selection: String) -> PantsSizeMeasurements? {
        let pattern = #"(?i)(\d{1,3})\s*[x×]\s*(\d{1,3})"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(selection.startIndex..<selection.endIndex, in: selection)
        guard let match = expression.firstMatch(in: selection, range: range),
              match.numberOfRanges >= 3,
              let waistRange = Range(match.range(at: 1), in: selection),
              let inseamRange = Range(match.range(at: 2), in: selection) else {
            return nil
        }

        return PantsSizeMeasurements(
            waist: String(selection[waistRange]),
            inseam: String(selection[inseamRange])
        )
    }

    static func displayValue(waist: String, inseam: String) -> String? {
        let waist = cleaned(waist)
        let inseam = cleaned(inseam)
        guard !waist.isEmpty, !inseam.isEmpty else { return nil }
        return "\(waist) × \(inseam)"
    }

    static func categoryUsesGeneratedPants(_ category: String) -> Bool {
        let category = cleaned(category)
        return category.caseInsensitiveCompare("Men") == .orderedSame
            || category.caseInsensitiveCompare("Unisex") == .orderedSame
            || category.caseInsensitiveCompare("Unisex / Prefer not to say") == .orderedSame
    }

    static func storageValue(category: String, waist: String, inseam: String) -> String? {
        let waist = cleaned(waist)
        let inseam = cleaned(inseam)
        guard !waist.isEmpty, !inseam.isEmpty, categoryUsesGeneratedPants(category) else { return nil }
        let category = cleaned(category)
        if category.caseInsensitiveCompare("Men") == .orderedSame {
            return "Men \(waist)x\(inseam)"
        }
        return "Unisex \(waist)x\(inseam)"
    }

    static func reconciledValues(
        pantsSize: String,
        waistSize: String,
        inseamLength: String,
        category: String
    ) -> PantsSizeVisibleValues {
        var waist = cleaned(waistSize)
        var inseam = cleaned(inseamLength)
        let legacyPants = cleaned(pantsSize)

        if (waist.isEmpty || inseam.isEmpty),
           let measurements = measurements(from: legacyPants) {
            if waist.isEmpty {
                waist = measurements.waist
            }
            if inseam.isEmpty {
                inseam = measurements.inseam
            }
        }

        let generated = storageValue(category: category, waist: waist, inseam: inseam)
        return PantsSizeVisibleValues(
            pantsSize: generated ?? legacyPants,
            waistSize: waist,
            inseamLength: inseam
        )
    }
}

enum PantsSizeProfileReconciliation {
    static let migrationFlag = "didRunPantsSizeProfileReconciliation_v1"

    static func migrationKey(userID: String) -> String {
        PersonalStylistStorage.scopedKey(migrationFlag, userID: userID)
    }

    @discardableResult
    static func reconcile(
        defaults: UserDefaults = .standard,
        userID: String,
        profile: StylistProfile
    ) -> (profile: StylistProfile, didChangeProfile: Bool) {
        let key = migrationKey(userID: userID)
        guard defaults.bool(forKey: key) == false else {
            return (profile, false)
        }
        defer { defaults.set(true, forKey: key) }

        var updated = profile
        var didChangeProfile = false

        let category = clean(defaults.string(forKey: "sizeCategory")) ?? "Men"
        let defaultsPantsSize = clean(defaults.string(forKey: "pantsSize"))
        let profilePantsSize = clean(profile.clothingSizes.pantSize)
        let sourcePantsSize = defaultsPantsSize ?? profilePantsSize ?? ""
        let sourceWaist = clean(defaults.string(forKey: "waistSize")) ?? ""
        let sourceInseam = clean(defaults.string(forKey: "inseamLength")) ?? ""

        let canReconcile = PantsSizeSync.categoryUsesGeneratedPants(category)
            || PantsSizeSync.measurements(from: sourcePantsSize) != nil
            || !sourceWaist.isEmpty
            || !sourceInseam.isEmpty

        if canReconcile {
            let values = PantsSizeSync.reconciledValues(
                pantsSize: sourcePantsSize,
                waistSize: sourceWaist,
                inseamLength: sourceInseam,
                category: category
            )

            write(values.pantsSize, forKey: "pantsSize", defaults: defaults)
            write(values.waistSize, forKey: "waistSize", defaults: defaults)
            write(values.inseamLength, forKey: "inseamLength", defaults: defaults)

            let reconciledPantsSize = clean(values.pantsSize)
            if updated.clothingSizes.pantSize != reconciledPantsSize {
                updated.clothingSizes.pantSize = reconciledPantsSize
                didChangeProfile = true
            }
        }

        if defaults.object(forKey: "sizeProfile") != nil {
            defaults.removeObject(forKey: "sizeProfile")
        }

        return (updated, didChangeProfile)
    }

    private static func clean(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func write(_ value: String, forKey key: String, defaults: UserDefaults) {
        let trimmed = PantsSizeSync.cleaned(value)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(trimmed, forKey: key)
        }
    }
}

struct PantsSizeFieldState: Equatable {
    var pantsSize: String
    var waistSize: String
    var inseamLength: String
    var lastEditSource: PantsSizeEditSource

    init(
        pantsSize: String,
        waistSize: String,
        inseamLength: String,
        lastEditSource: PantsSizeEditSource = .manual
    ) {
        self.pantsSize = pantsSize
        self.waistSize = waistSize
        self.inseamLength = inseamLength
        self.lastEditSource = lastEditSource
    }

    mutating func applyPickerSelection(_ selection: String) {
        pantsSize = selection
        lastEditSource = .picker
        guard let measurements = PantsSizeSync.measurements(from: selection) else { return }
        waistSize = measurements.waist
        inseamLength = measurements.inseam
    }

    mutating func applyManualWaist(_ value: String) {
        waistSize = value
        pantsSize = PantsSizeSync.storageValue(category: "Men", waist: waistSize, inseam: inseamLength) ?? ""
        lastEditSource = .manual
    }

    mutating func applyManualInseam(_ value: String) {
        inseamLength = value
        pantsSize = PantsSizeSync.storageValue(category: "Men", waist: waistSize, inseam: inseamLength) ?? ""
        lastEditSource = .manual
    }

    var visibleValuesForSave: PantsSizeVisibleValues {
        PantsSizeVisibleValues(
            pantsSize: pantsSize,
            waistSize: waistSize,
            inseamLength: inseamLength
        )
    }
}

enum FounderProfileDefaultsMigration {
    static let migrationFlag = "didRunFounderDefaultsMigration_v1"
    static let profileLastSavedAtKey = "profileLastSavedAt"

    private static let exactFingerprint: [String: String] = [
        "sizeCategory": "Men",
        "shirtSize": "L",
        "pantsSize": "Men 36x36",
        "waistSize": "36",
        "inseamLength": "36",
        "shoeSize": "10",
        "fitPreference": "Regular"
    ]

    static let profilePreferenceKeys = [
        "profileName",
        "favoriteColors",
        "favoriteBrands",
        "favoriteStores",
        "shoppingBudget",
        "budget",
        "sizeProfile",
        "sizeCategory",
        "shirtSize",
        "pantsSize",
        "dressSize",
        "waistSize",
        "inseamLength",
        "neckSize",
        "sleeveLength",
        "shoeSize",
        "fitPreference",
        "stylePreferences",
        "occasions",
        "plannedOccasion",
        "dressCode",
        "occasionFormality",
        "weather",
        "weatherCity",
        "weatherCondition",
        "weatherSource",
        "pastPurchases",
        "favoriteOutfits",
        "closetInventory",
        "outfitDislikes",
        "clothingPreferences"
    ]

    static func hasIntentionalProfileSave(defaults: UserDefaults = .standard) -> Bool {
        clean(defaults.string(forKey: profileLastSavedAtKey)) != nil
    }

    static func matchesFounderFingerprint(defaults: UserDefaults = .standard) -> Bool {
        for (key, expectedValue) in exactFingerprint {
            guard clean(defaults.string(forKey: key))?.caseInsensitiveCompare(expectedValue) == .orderedSame else {
                return false
            }
        }
        return true
    }

    @discardableResult
    static func run(defaults: UserDefaults = .standard, userID: String? = nil) -> Bool {
        guard defaults.bool(forKey: migrationFlag) == false else { return false }
        defer { defaults.set(true, forKey: migrationFlag) }
        guard hasIntentionalProfileSave(defaults: defaults) == false,
              matchesFounderFingerprint(defaults: defaults) else {
            return false
        }
        clearProfilePreferenceDefaults(defaults: defaults, userID: userID)
        return true
    }

    static func clearProfilePreferenceDefaults(defaults: UserDefaults = .standard, userID: String? = nil) {
        for key in profilePreferenceKeys {
            defaults.removeObject(forKey: key)
        }
        defaults.removeObject(forKey: profileLastSavedAtKey)

        let resolvedUserID = PersonalStylistStorage.normalizedUserID(
            userID ?? PersonalStylistStorage.activeUserID(defaults: defaults)
        )
        defaults.removeObject(
            forKey: PersonalStylistStorage.scopedKey(PersonalStylistStorage.legacyProfileKey, userID: resolvedUserID)
        )
        PersonalStylistSnapshotStore.deleteData(store: "StylistProfile", userID: resolvedUserID)
    }

    private static func clean(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum LoginWelcomeProfileData {
    static func hasValue(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func hasIntentionalProfileValues(
        favoriteOutfits: String,
        stylePreferences: String,
        favoriteColors: String,
        profileName: String,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard FounderProfileDefaultsMigration.hasIntentionalProfileSave(defaults: defaults) else {
            return false
        }
        return hasValue(favoriteOutfits)
            || hasValue(stylePreferences)
            || hasValue(favoriteColors)
            || StyleMatchGreetingBuilder.firstName(from: profileName) != nil
    }
}

struct GarmentRecord: Codable, Identifiable, Equatable {
    let id: UUID
    var garmentCategory: String
    var itemFingerprint: String
    var brand: String?
    var fit: String?
    var fabric: String?
    var pattern: String?
    var colors: [String]
    var styleTags: [String]
    var colorConfidence: Double
    var timesSeen: Int
    var timesWorn: Int
    var lastWorn: Date?
    var sourceScanIds: [String]
    var firstSeenAt: Date
    var lastSeenAt: Date

    init(
        id: UUID = UUID(),
        garmentCategory: String,
        itemFingerprint: String,
        brand: String? = nil,
        fit: String? = nil,
        fabric: String? = nil,
        pattern: String? = nil,
        colors: [String],
        styleTags: [String],
        colorConfidence: Double,
        timesSeen: Int = 1,
        timesWorn: Int = 0,
        lastWorn: Date? = nil,
        sourceScanIds: [String],
        firstSeenAt: Date = Date(),
        lastSeenAt: Date = Date()
    ) {
        self.id = id
        self.garmentCategory = garmentCategory
        self.itemFingerprint = itemFingerprint
        self.brand = brand
        self.fit = fit
        self.fabric = fabric
        self.pattern = pattern
        self.colors = colors
        self.styleTags = styleTags
        self.colorConfidence = min(100, max(0, colorConfidence))
        self.timesSeen = max(0, timesSeen)
        self.timesWorn = max(0, timesWorn)
        self.lastWorn = lastWorn
        self.sourceScanIds = sourceScanIds
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        garmentCategory = try container.decodeIfPresent(String.self, forKey: .garmentCategory) ?? "item"
        itemFingerprint = try container.decodeIfPresent(String.self, forKey: .itemFingerprint) ?? UUID().uuidString
        brand = try container.decodeIfPresent(String.self, forKey: .brand)
        fit = try container.decodeIfPresent(String.self, forKey: .fit)
        fabric = try container.decodeIfPresent(String.self, forKey: .fabric)
        pattern = try container.decodeIfPresent(String.self, forKey: .pattern)
        colors = try container.decodeIfPresent([String].self, forKey: .colors) ?? []
        styleTags = try container.decodeIfPresent([String].self, forKey: .styleTags) ?? []
        colorConfidence = min(100, max(0, try container.decodeIfPresent(Double.self, forKey: .colorConfidence) ?? 50))
        timesSeen = max(0, try container.decodeIfPresent(Int.self, forKey: .timesSeen) ?? 1)
        timesWorn = max(0, try container.decodeIfPresent(Int.self, forKey: .timesWorn) ?? 0)
        lastWorn = try container.decodeIfPresent(Date.self, forKey: .lastWorn)
        sourceScanIds = try container.decodeIfPresent([String].self, forKey: .sourceScanIds) ?? []
        firstSeenAt = try container.decodeIfPresent(Date.self, forKey: .firstSeenAt) ?? Date()
        lastSeenAt = try container.decodeIfPresent(Date.self, forKey: .lastSeenAt) ?? firstSeenAt
    }
}

enum Occasion: String, Codable, CaseIterable {
    case general
    case work
    case businessFormal
    case weddingGuest
    case party
    case casualDay
    case gym
    case loungewear
    case specialEvent

    // Legacy values kept so existing saved scans decode without data loss.
    case casual
    case dateNight
    case wedding
    case formalEvent
    case travel
    case other

    static var allCases: [Occasion] {
        [
            .general,
            .work,
            .businessFormal,
            .dateNight,
            .weddingGuest,
            .party,
            .casualDay,
            .gym,
            .travel,
            .loungewear,
            .specialEvent
        ]
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        if let occasion = Occasion(rawValue: rawValue)?.canonical ?? Occasion(label: rawValue)?.canonical {
            self = occasion
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unknown occasion value: \(rawValue)"
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode((canonical ?? self).rawValue)
    }

    var canonical: Occasion? {
        switch self {
        case .general, .other:
            return nil
        case .casual:
            return .casualDay
        case .wedding:
            return .weddingGuest
        case .formalEvent:
            return .specialEvent
        default:
            return self
        }
    }

    var isSpecified: Bool {
        canonical != nil
    }

    init?(label: String?) {
        guard let label else {
            return nil
        }

        let cleaned = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty else {
            return nil
        }

        if cleaned.contains("general") || cleaned.contains("default") {
            self = .general
        } else if cleaned.contains("business formal") || cleaned.contains("interview") || cleaned.contains("business professional") {
            self = .businessFormal
        } else if cleaned.contains("work") || cleaned.contains("office") {
            self = .work
        } else if cleaned.contains("date") || cleaned.contains("dinner") {
            self = .dateNight
        } else if cleaned.contains("wedding guest") || cleaned.contains("wedding") {
            self = .weddingGuest
        } else if cleaned.contains("party") {
            self = .party
        } else if cleaned.contains("gym") || cleaned.contains("workout") || cleaned.contains("fitness") {
            self = .gym
        } else if cleaned.contains("lounge") || cleaned.contains("sleep") || cleaned.contains("home") {
            self = .loungewear
        } else if cleaned.contains("special") {
            self = .specialEvent
        } else if cleaned.contains("casual") || cleaned.contains("everyday") || cleaned.contains("weekend") {
            self = .casualDay
        } else if cleaned.contains("wedding") {
            self = .wedding
        } else if cleaned.contains("formal") || cleaned.contains("ceremony") || cleaned.contains("event") {
            self = .formalEvent
        } else if cleaned.contains("travel") || cleaned.contains("airport") || cleaned.contains("vacation") {
            self = .travel
        } else if cleaned == "other" {
            self = .other
        } else {
            return nil
        }
    }

    var displayName: String {
        switch self {
        case .general:
            return "General"
        case .work:
            return "Work"
        case .businessFormal:
            return "Business Formal"
        case .weddingGuest:
            return "Wedding Guest"
        case .party:
            return "Party"
        case .casualDay:
            return "Casual Day"
        case .gym:
            return "Gym"
        case .loungewear:
            return "Loungewear"
        case .specialEvent:
            return "Special Event"
        case .casual:
            return "Casual"
        case .dateNight:
            return "Date Night"
        case .wedding:
            return "Wedding"
        case .formalEvent:
            return "Formal Event"
        case .travel:
            return "Travel"
        case .other:
            return "Other"
        }
    }
}

enum FormalityLevel: String, Codable, CaseIterable {
    case unknown
    case sleepwear
    case casual
    case smartCasual
    case businessCasual
    case business
    case semiFormal
    case formal
    case ceremonial

    var displayName: String {
        switch self {
        case .unknown:
            return "uncertain"
        case .sleepwear:
            return "sleepwear or loungewear"
        case .casual:
            return "casual"
        case .smartCasual:
            return "smart casual"
        case .businessCasual:
            return "business casual"
        case .business:
            return "business"
        case .semiFormal:
            return "semi-formal"
        case .formal:
            return "formal"
        case .ceremonial:
            return "ceremonial or traditional"
        }
    }
}

struct FormalityMismatch: Equatable {
    let occasion: Occasion
    let detectedFormality: FormalityLevel
    let message: String
}

struct FormalityMismatchEvaluator {
    struct ConflictPair: Hashable {
        let formality: FormalityLevel
        let occasion: Occasion
    }

    static let explicitConflictPairs: Set<ConflictPair> = [
        ConflictPair(formality: .sleepwear, occasion: .work),
        ConflictPair(formality: .sleepwear, occasion: .businessFormal),
        ConflictPair(formality: .sleepwear, occasion: .weddingGuest)
    ]

    static let acceptableFormalityBands: [Occasion: Set<FormalityLevel>] = [
        .general: Set(FormalityLevel.allCases),
        .casual: [.casual, .smartCasual, .businessCasual, .business, .semiFormal, .formal, .ceremonial],
        .casualDay: [.casual, .smartCasual, .businessCasual],
        .work: [.smartCasual, .businessCasual, .business, .semiFormal],
        .businessFormal: [.business, .semiFormal, .formal],
        .dateNight: [.smartCasual, .businessCasual, .business, .semiFormal, .formal],
        .wedding: [.semiFormal, .formal, .ceremonial],
        .weddingGuest: [.semiFormal, .formal, .ceremonial],
        .party: [.smartCasual, .businessCasual, .semiFormal, .formal],
        .formalEvent: [.semiFormal, .formal, .ceremonial],
        .specialEvent: [.semiFormal, .formal, .ceremonial],
        .gym: [.casual],
        .loungewear: [.sleepwear, .casual],
        .travel: [.casual, .smartCasual, .businessCasual],
        .other: Set(FormalityLevel.allCases)
    ]

    static func evaluate(detectedStyle: String, occasion: Occasion?) -> FormalityMismatch? {
        guard let occasion = occasion?.canonical else {
            return nil
        }

        let formality = formalityLevel(from: detectedStyle)
        guard formality != .unknown else {
            return FormalityMismatch(
                occasion: occasion,
                detectedFormality: formality,
                message: "StyleMatch Pro could not confidently read this outfit for \(occasion.displayName.lowercased()). Try a clearer full-outfit scan before relying on this for the occasion."
            )
        }

        if hasExplicitConflict(formality: formality, occasion: occasion) {
            return FormalityMismatch(
                occasion: occasion,
                detectedFormality: formality,
                message: "Occasion check: this reads as \(formality.displayName), but you selected \(occasion.displayName.lowercased()). The score is unchanged; address the mismatch honestly instead of praising the fit for that occasion."
            )
        }

        guard acceptableFormalityBands[occasion, default: Set(FormalityLevel.allCases)].contains(formality) else {
            return FormalityMismatch(
                occasion: occasion,
                detectedFormality: formality,
                message: "Occasion check: this reads as \(formality.displayName), but you selected \(occasion.displayName.lowercased()). The score is unchanged; use this as a styling warning."
            )
        }

        return nil
    }

    static func hasExplicitConflict(formality: FormalityLevel, occasion: Occasion?) -> Bool {
        guard let occasion = occasion?.canonical else {
            return false
        }
        return explicitConflictPairs.contains(ConflictPair(formality: formality, occasion: occasion))
    }

    static func formalityLevel(from detectedStyle: String) -> FormalityLevel {
        let text = detectedStyle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return .unknown }

        if text.contains("unrecognized") || text.contains("uncertain") || text.contains("unknown") {
            return .unknown
        }
        if text.contains("sleepwear")
            || text.contains("loungewear")
            || text.contains("pajama")
            || text.contains("pyjama")
            || text.contains("robe")
            || text.contains("slipper")
            || text.contains("indoor wear") {
            return .sleepwear
        }
        if text.contains("traditional") || text.contains("cultural") || text.contains("ceremonial") || text.contains("heritage") {
            return .ceremonial
        }
        if text.contains("black tie") || text.contains("formal") {
            return .formal
        }
        if text.contains("cocktail") || text.contains("semi-formal") || text.contains("semiformal") || text.contains("wedding") {
            return .semiFormal
        }
        if text.contains("business professional") || text.contains("business formal") {
            return .business
        }
        if text.contains("business casual") {
            return .businessCasual
        }
        if text.contains("smart casual") || text.contains("polished casual") {
            return .smartCasual
        }
        if text.contains("casual")
            || text.contains("streetwear")
            || text.contains("athletic")
            || text.contains("sportswear")
            || text.contains("rugged")
            || text.contains("outdoor") {
            return .casual
        }

        return .unknown
    }
}

enum DislikeReason: String, Codable, CaseIterable {
    case tooFormal = "too_formal"
    case tooCasual = "too_casual"
    case colorsOff = "colors_off"
    case fitIssue = "fit_issue"
    case wrongForWeather = "wrong_for_weather"
    case notMyStyle = "not_my_style"

    var displayName: String {
        switch self {
        case .tooFormal:
            return "Too formal"
        case .tooCasual:
            return "Too casual"
        case .colorsOff:
            return "Colors were off"
        case .fitIssue:
            return "Fit"
        case .wrongForWeather:
            return "Wrong for the weather"
        case .notMyStyle:
            return "Not my style"
        }
    }

    init?(legacyValue: String?) {
        guard let legacyValue else { return nil }
        let normalized = legacyValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        if let reason = DislikeReason(rawValue: normalized) {
            self = reason
            return
        }

        switch normalized {
        case "formal", "too_formal":
            self = .tooFormal
        case "casual", "too_casual":
            self = .tooCasual
        case "color", "colors", "colors_were_off", "color_off":
            self = .colorsOff
        case "fit", "fit_issue", "size":
            self = .fitIssue
        case "weather", "wrong_weather", "wrong_for_weather":
            self = .wrongForWeather
        case "style", "occasion", "other", "not_my_style":
            self = .notMyStyle
        default:
            return nil
        }
    }
}

struct OutfitFeedback: Codable, Equatable {
    enum Verdict: String, Codable {
        case loved
        case liked
        case notForMe
    }

    let verdict: Verdict
    let woreIt: Bool?
    let recordedAt: Date
}

struct OutfitMemory: Codable, Identifiable {
    let id: UUID
    var userId: String
    var scanDate: Date
    var detectedGarments: [String]
    var colors: [String]
    var detectedStyle: String
    var styleScore: Int
    var occasion: Occasion?
    var wasWorn: Bool?
    var wasLiked: Bool?
    var feedbackTimestamp: Date?
    var dislikeReason: DislikeReason?
    var feedbackPromptCount: Int
    var feedbackDismissedAt: Date?
    var feedbackCompletedAt: Date?
    var feedback: OutfitFeedback?
    var wouldWearAgain: Bool?
    var receivedCompliments: Bool?
    var isFavorite: Bool
    var timesWorn: Int
    var garmentRecords: [GarmentRecord]
    var outfitFingerprint: String?
    var imageDigest: String?

    init(
        id: UUID,
        userId: String,
        scanDate: Date,
        detectedGarments: [String],
        colors: [String],
        detectedStyle: String,
        styleScore: Int,
        occasion: Occasion?,
        wasWorn: Bool?,
        wasLiked: Bool?,
        feedbackTimestamp: Date?,
        dislikeReason: DislikeReason?,
        feedbackPromptCount: Int = 0,
        feedbackDismissedAt: Date? = nil,
        feedbackCompletedAt: Date? = nil,
        feedback: OutfitFeedback? = nil,
        wouldWearAgain: Bool?,
        receivedCompliments: Bool?,
        isFavorite: Bool,
        timesWorn: Int,
        garmentRecords: [GarmentRecord] = [],
        outfitFingerprint: String? = nil,
        imageDigest: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.scanDate = scanDate
        self.detectedGarments = detectedGarments.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        self.colors = colors.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        self.detectedStyle = detectedStyle
        self.styleScore = min(100, max(0, styleScore))
        self.occasion = occasion
        self.wasWorn = wasWorn
        self.wasLiked = wasLiked
        self.feedbackTimestamp = feedbackTimestamp
        self.dislikeReason = dislikeReason
        self.feedbackPromptCount = max(0, feedbackPromptCount)
        self.feedbackDismissedAt = feedbackDismissedAt
        self.feedbackCompletedAt = feedbackCompletedAt
        self.feedback = feedback
        self.wouldWearAgain = wouldWearAgain
        self.receivedCompliments = receivedCompliments
        self.isFavorite = isFavorite
        self.timesWorn = max(0, timesWorn)
        self.garmentRecords = garmentRecords
        self.outfitFingerprint = outfitFingerprint
        self.imageDigest = imageDigest
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        userId = try container.decodeIfPresent(String.self, forKey: .userId) ?? "guest"
        scanDate = try container.decodeIfPresent(Date.self, forKey: .scanDate) ?? Date()
        detectedGarments = try container.decodeIfPresent([String].self, forKey: .detectedGarments) ?? []
        colors = try container.decodeIfPresent([String].self, forKey: .colors) ?? []
        detectedStyle = try container.decodeIfPresent(String.self, forKey: .detectedStyle) ?? "Casual"
        styleScore = min(100, max(0, try container.decodeIfPresent(Int.self, forKey: .styleScore) ?? 0))
        if let decodedOccasion = try? container.decodeIfPresent(Occasion.self, forKey: .occasion) {
            occasion = decodedOccasion.canonical
        } else {
            occasion = Occasion(label: try? container.decodeIfPresent(String.self, forKey: .occasion))?.canonical
        }
        wasWorn = try container.decodeIfPresent(Bool.self, forKey: .wasWorn)
        wasLiked = try container.decodeIfPresent(Bool.self, forKey: .wasLiked)
        feedbackTimestamp = try container.decodeIfPresent(Date.self, forKey: .feedbackTimestamp)
        if let decodedReason = try? container.decodeIfPresent(DislikeReason.self, forKey: .dislikeReason) {
            dislikeReason = decodedReason
        } else {
            dislikeReason = DislikeReason(legacyValue: try? container.decodeIfPresent(String.self, forKey: .dislikeReason))
        }
        feedbackPromptCount = max(0, try container.decodeIfPresent(Int.self, forKey: .feedbackPromptCount) ?? 0)
        feedbackDismissedAt = try container.decodeIfPresent(Date.self, forKey: .feedbackDismissedAt)
        feedbackCompletedAt = try container.decodeIfPresent(Date.self, forKey: .feedbackCompletedAt)
        feedback = try container.decodeIfPresent(OutfitFeedback.self, forKey: .feedback)
        wouldWearAgain = try container.decodeIfPresent(Bool.self, forKey: .wouldWearAgain)
        receivedCompliments = try container.decodeIfPresent(Bool.self, forKey: .receivedCompliments)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        timesWorn = max(0, try container.decodeIfPresent(Int.self, forKey: .timesWorn) ?? 0)
        garmentRecords = try container.decodeIfPresent([GarmentRecord].self, forKey: .garmentRecords) ?? Self.makeLegacyGarmentRecords(
            scanID: id.uuidString,
            scanDate: scanDate,
            detectedGarments: detectedGarments,
            colors: colors,
            detectedStyle: detectedStyle,
            timesWorn: timesWorn,
            lastWorn: wasWorn == true ? scanDate : nil
        )
        outfitFingerprint = try container.decodeIfPresent(String.self, forKey: .outfitFingerprint)
        imageDigest = try container.decodeIfPresent(String.self, forKey: .imageDigest)
    }

    private static func makeLegacyGarmentRecords(
        scanID: String,
        scanDate: Date,
        detectedGarments: [String],
        colors: [String],
        detectedStyle: String,
        timesWorn: Int,
        lastWorn: Date?
    ) -> [GarmentRecord] {
        detectedGarments.enumerated().map { index, garment in
            let category = GarmentRecordHelpers.category(from: garment)
            let itemColors = colors.isEmpty ? [] : [colors[min(index, colors.count - 1)]]
            let fingerprint = GarmentRecordHelpers.fingerprint(
                category: category,
                colors: itemColors,
                pattern: nil,
                fabric: nil,
                brand: nil,
                styleTags: [detectedStyle]
            )
            return GarmentRecord(
                garmentCategory: category,
                itemFingerprint: fingerprint,
                colors: itemColors,
                styleTags: [detectedStyle],
                colorConfidence: itemColors.isEmpty ? 35 : 55,
                timesSeen: 1,
                timesWorn: timesWorn,
                lastWorn: lastWorn,
                sourceScanIds: [scanID],
                firstSeenAt: scanDate,
                lastSeenAt: scanDate
            )
        }
    }
}

struct FeedbackEntry: Codable, Identifiable {
    let id: UUID
    var outfitMemoryId: UUID
    var question: String
    var response: String
    var submittedAt: Date
}
