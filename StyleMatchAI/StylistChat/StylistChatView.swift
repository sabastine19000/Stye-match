import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

/// Local-only authority captured when the customer approves a pending AI
/// transmission. It is intentionally not Codable and never leaves this view.
enum StylistPendingSendAuthority: Equatable {
    case general
    case scan(StylistConversationScope)
    case screen(ScreenAwarenessSnapshot, generation: UInt64)

    func isCurrent(
        activeConversationScope: StylistConversationScope,
        hasExplicitlySelectedGeneralStylist: Bool,
        screenAwarenessSnapshot: ScreenAwarenessSnapshot?,
        screenAwarenessGeneration: UInt64,
        availableShoppingProductIDs: Set<String>
    ) -> Bool {
        switch self {
        case .general:
            return activeConversationScope == .generalStylist
                && (hasExplicitlySelectedGeneralStylist || screenAwarenessSnapshot == nil)
        case let .scan(scope):
            return scope.isScanBound && activeConversationScope == scope
        case let .screen(snapshot, generation):
            return activeConversationScope.isContextual
                && !hasExplicitlySelectedGeneralStylist
                && screenAwarenessSnapshot == snapshot
                && generation == screenAwarenessGeneration
                && snapshot.isCurrent(
                    generation: generation,
                    availableShoppingProductIDs: availableShoppingProductIDs
                )
        }
    }
}

private enum StylistFactAttachmentKind: String, Identifiable {
    case savedScan
    case closet
    case stylePreferences

    var id: String { rawValue }
    var title: String {
        switch self {
        case .savedScan: "Saved Scan Facts"
        case .closet: "Closet Items"
        case .stylePreferences: "Style Preferences"
        }
    }
    var scope: AIScopedConsentScope {
        switch self {
        case .savedScan: .selectedScanFacts
        case .closet: .selectedClosetItems
        case .stylePreferences: .stylePreferences
        }
    }
}

private enum StylistFactContextResolution {
    case noneSelected
    case resolved(PersonalizationContextBuilder.StylistFactContextV1)
    case failed
}

struct StylistChatView: View {
    @StateObject private var service: StylistChatService
    @StateObject private var speechInput: StylistSpeechInputService
    @StateObject private var voiceAssistant: VoiceStylistService
    @State private var draft = ""
    @State private var showingHistory = false
    @State private var activeConversationContext: ChatContext?
    @State private var handoffController = StylistScanConversationHandoffController()
    @State private var lastAnnouncedAssistantID: UUID?
    @State private var composerFrame: CGRect = .null
    @State private var isScanCardExpanded = false
    @State private var hasExplicitlySelectedGeneralStylist = false
    @State private var isShowingCurrentContext = false
    @StateObject private var aiTransmissionConsent = AITransmissionConsentStore.shared
    @State private var isShowingAITransmissionDisclosure = false
    @State private var pendingConsentRequest: PendingConsentRequest?
    @State private var isRecordingAIProcessingConsent = false
    @State private var speakingAssistantMessageID: UUID?
    @State private var factAttachmentSheet: StylistFactAttachmentKind?
    @State private var scopedConsentSheet: AIScopedConsentScope?
    @State private var availableSavedScanFacts: [SavedScanStylistFacts] = []
    @State private var availableClosetFacts: [ClosetStylistFacts] = []
    @State private var selectedSavedScanKeys: Set<String> = []
    @State private var selectedClosetKeys: Set<UUID> = []
    @State private var currentStylePreferences: StyleProfilePersonalizationContext?
    @State private var selectedPreferredColors: Set<String> = []
    @State private var selectedAvoidedColors: Set<String> = []
    @State private var selectedPreferredFits: Set<String> = []
    @State private var selectedPreferredStyles: Set<String> = []
    @State private var selectedPreferredBrands: Set<String> = []
    @State private var selectedVisionPhoto: PhotosPickerItem?
    @State private var normalizedVisionImage: VisionChatRequestV1.SelectedImage?
    @State private var isPreparingVisionImage = false
    @State private var visionRetryRequest: VisionChatRequestV1?
    @State private var factSelectionAvailabilityError: String?
    @State private var scopedConsentStates: [AIScopedConsentScope: AIScopedConsentState] = [:]
    @State private var isRefreshingScopedConsent = false
    @State private var isMutatingScopedConsent = false
    @State private var scopedConsentFeedback: String?

    private let initialQuestion: String?
    private let initialContext: ChatContext?
    private let scanHandoff: StylistScanHandoff?
    private let screenAwarenessSnapshot: ScreenAwarenessSnapshot?
    private let screenAwarenessGeneration: UInt64
    private let availableShoppingProductIDs: Set<String>
    private let screenContext: StylistScreenContext
    private let voiceInputEnabled: Bool
    private let bottomNavigationClearance: CGFloat
    private let onSignInRequested: () -> Void
    private let onUseGeneralStylist: () -> Void
    private let showsBackControl: Bool
    private let onBackRequested: () -> Void
    private let showsDismissControl: Bool
    private let onDismissRequested: () -> Void

    init(
        service: StylistChatService? = nil,
        speechInput: StylistSpeechInputService? = nil,
        voiceAssistant: VoiceStylistService? = nil,
        voiceInputEnabled: Bool = true,
        initialQuestion: String? = nil,
        initialContext: ChatContext? = nil,
        scanHandoff: StylistScanHandoff? = nil,
        screenAwarenessSnapshot: ScreenAwarenessSnapshot? = nil,
        screenAwarenessGeneration: UInt64 = 0,
        availableShoppingProductIDs: Set<String> = [],
        screenContext: StylistScreenContext = .aiTab(),
        bottomNavigationClearance: CGFloat = 0,
        onSignInRequested: @escaping () -> Void = {},
        onUseGeneralStylist: @escaping () -> Void = {},
        showsBackControl: Bool = false,
        onBackRequested: @escaping () -> Void = {},
        showsDismissControl: Bool = false,
        onDismissRequested: @escaping () -> Void = {}
    ) {
        _service = StateObject(
            wrappedValue: service ?? StylistChatService(
                contextProvider: {
                    PersonalizationContextBuilder.conversationalStylistContext(
                        screenContext: screenContext,
                        weatherConstraint: AIStylistContextSelection.weatherConstraint(
                            defaults: .standard
                        )
                    )
                }
            )
        )
        _speechInput = StateObject(wrappedValue: speechInput ?? StylistSpeechInputService())
        _voiceAssistant = StateObject(wrappedValue: voiceAssistant ?? VoiceStylistService())
        self.voiceInputEnabled = voiceInputEnabled
        self.initialQuestion = initialQuestion
        self.initialContext = initialContext
        self.scanHandoff = scanHandoff
        self.screenAwarenessSnapshot = screenAwarenessSnapshot
        self.screenAwarenessGeneration = screenAwarenessGeneration
        self.availableShoppingProductIDs = availableShoppingProductIDs
        self.screenContext = screenContext
        self.bottomNavigationClearance = max(0, bottomNavigationClearance)
        self.onSignInRequested = onSignInRequested
        self.onUseGeneralStylist = onUseGeneralStylist
        self.showsBackControl = showsBackControl
        self.onBackRequested = onBackRequested
        self.showsDismissControl = showsDismissControl
        self.onDismissRequested = onDismissRequested
    }

    private var effectiveVoiceInputEnabled: Bool {
        #if DEBUG
        voiceInputEnabled
        #else
        true
        #endif
    }

    var body: some View {
        NavigationStack {
            messageList
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    anchoredInputBar
                        .padding(.bottom, bottomNavigationClearance)
                }
                .scrollDismissesKeyboard(.interactively)
            .navigationTitle("AI Stylist")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if showsBackControl {
                        Button {
                            onBackRequested()
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                        .accessibilityHint("Returns to Home without deleting this conversation.")
                    } else {
                        Button("History") {
                            showingHistory = true
                        }
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if showsBackControl {
                        Button {
                            showingHistory = true
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                        .accessibilityLabel("History")
                        .accessibilityHint("Opens your Stylist conversation history.")
                    }
                    Button(showsBackControl ? "General" : "General Stylist") {
                        switchToGeneralStylist()
                    }
                    .accessibilityLabel("General Stylist")
                }
                if showsDismissControl {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            onDismissRequested()
                        }
                    }
                }
            }
            .sheet(isPresented: $showingHistory) {
                ChatHistorySheet(conversations: service.conversations) { conversation in
                    openConversation(conversation)
                    showingHistory = false
                }
            }
            .sheet(isPresented: $isShowingCurrentContext) {
                CurrentStylistContextSheet(
                    snapshot: validScreenAwarenessSnapshot,
                    threadCorrection: currentThreadCorrection,
                    useGeneralStylist: switchToGeneralStylist
                )
            }
            .sheet(isPresented: $isShowingAITransmissionDisclosure) {
                AITransmissionConsentDisclosureView(
                    consentStore: aiTransmissionConsent,
                    recordCurrentConsent: recordCurrentAIProcessingConsent,
                    agreeAndContinue: continueAfterAcceptingAITransmission,
                    decline: { pendingConsentRequest = nil }
                )
            }
            .sheet(item: $factAttachmentSheet) { kind in
                factAttachmentSelectionSheet(kind)
            }
            .sheet(item: $scopedConsentSheet) { scope in
                scopedConsentPermissionSheet(scope)
            }
            .onAppear {
                service.refreshAuthorizationState()
                aiTransmissionConsent.refresh()
                reloadFactSelections()
                loadRememberedStylePreferences()
                refreshScopedConsent()
                applyCurrentScanHandoff()
                if scanHandoff?.routeToken != nil {
                    consumeExplicitScanHandoff()
                } else if let initialContext, initialContext.authoritativeScan?.isComplete == true {
                    service.openOrCreateScanConversation(context: initialContext)
                    activeConversationContext = initialContext
                }
                if let initialQuestion, let initialContext, service.activeConversation.messages.isEmpty {
                    activeConversationContext = initialContext
                    service.sendPreseededQuestion(initialQuestion, context: initialContext)
                }
                if screenAwarenessSnapshot != nil,
                   !hasExplicitlySelectedGeneralStylist,
                   !service.activeConversation.scope.isScanBound,
                   !service.activeConversation.scope.isContextual {
                    service.beginContextualConversation()
                }
            }
            .onDisappear {
                draft = speechInput.cancelListening()
                stopReadingResponse()
            }
            .onReceive(NotificationCenter.default.publisher(for: StyleMatchAccountSessionStore.didChangeNotification)) { _ in
                // Neither selected facts nor local permission UI state may
                // survive an account change. The Worker remains authoritative.
                clearFactSelections()
                clearVisionImage()
                scopedConsentStates = [:]
            }
            .styleMatchOnChange(of: speechInput.transcript) { transcript in
                draft = transcript
            }
            .styleMatchOnChange(of: screenContext) { _ in
                applyCurrentScanHandoff()
            }
            .styleMatchOnChange(of: scanHandoff?.routeToken) { _ in
                consumeExplicitScanHandoff()
            }
            .styleMatchOnChange(of: screenAwarenessSnapshot?.generation) { _ in
                guard screenAwarenessSnapshot != nil else { return }
                hasExplicitlySelectedGeneralStylist = false
                activeConversationContext = nil
                service.beginContextualConversation()
            }
            .styleMatchOnChange(of: service.activeConversation.id) { _ in
                stopReadingResponse()
                clearFactSelections()
                clearVisionImage()
            }
            .styleMatchOnChange(of: selectedVisionPhoto) { item in
                prepareVisionImage(item)
            }
            .onPreferenceChange(StyleMatchComposerFramePreferenceKey.self) { frame in
                guard !frame.isNull, !frame.isEmpty, frame != composerFrame else { return }
                composerFrame = frame
            }
        }
        .appScreenBackground(.ai)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if service.activeConversation.scope.isScanBound {
                        selectedScanContextNote
                        scanQuickFollowUps
                    } else if let snapshot = validScreenAwarenessSnapshot,
                              !hasExplicitlySelectedGeneralStylist {
                        currentContextNote(snapshot)
                    } else if let correction = currentThreadCorrection {
                        currentThreadCorrectionNote(correction)
                    } else if canPinCurrentScan {
                        pinCurrentScanPrompt
                    }

                    if let snapshot = validScreenAwarenessSnapshot,
                       !hasExplicitlySelectedGeneralStylist,
                       shouldShowStarterPrompts,
                       !service.activeConversation.scope.isScanBound {
                        contextualPromptStrip(snapshot)
                    }

                    if shouldShowStarterPrompts {
                        promptLibrary
                    }

                    if service.requiresSignIn {
                        signInPrompt
                    }

                    if !service.activeConversation.messages.isEmpty {
                        ForEach(service.activeConversation.messages) { message in
                            ChatBubble(
                                message: message,
                                isStreaming: service.isStreaming
                                    && message.id == service.activeConversation.messages.last?.id,
                                isReadAloudActive: voiceAssistant.isSpeaking
                                    && speakingAssistantMessageID == message.id,
                                onListen: { listen(to: message) },
                                onStopReading: stopReadingResponse
                            )
                                .id(message.id)
                        }
                    }

                    if service.isStreaming {
                        TypingIndicator()
                            .id("typing")
                    }

                    if let error = service.inlineError {
                        SystemChatRow(
                            text: error,
                            retry: service.canRetryLastFailedSend ? {
                                _ = service.retryLastFailedSend()
                            } : nil,
                            actionTitle: error == StylistChatError.aiTransmissionConsentRequired.localizedDescription
                                ? "Review AI Consent" : nil,
                            action: error == StylistChatError.aiTransmissionConsentRequired.localizedDescription
                                ? { isShowingAITransmissionDisclosure = true } : nil
                        )
#if DEBUG || OWNER_BETA
                        if let diagnostic = service.lastDeliveryDiagnostic {
                            Text("Owner diagnostic • build \(ownerBuildIdentifier): category=\(String(describing: diagnostic.category)) status=\(diagnostic.statusCode.map(String.init) ?? "none") phase=\(diagnostic.requestPhase?.rawValue ?? "unknown")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Owner diagnostic summary")
                        }
#endif
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .padding(.bottom, 24)
            }
            .styleMatchOnChange(of: service.activeConversation.messages.count) { _ in
                scrollToBottom(proxy)
            }
            .styleMatchOnChange(of: service.isStreaming) { _ in
                scrollToBottom(proxy)
                announceCompletedResponseIfNeeded()
            }
        }
    }

    #if DEBUG || OWNER_BETA
    private var ownerBuildIdentifier: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        return "\(version) (\(build))"
    }
    #endif

    private var promptLibrary: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ask your stylist")
                .font(.title2)
                .fontWeight(.bold)
            Text("Get short, practical outfit advice for colors, garments, shoes, accessories, and occasions.")
                .foregroundStyle(.secondary)

            ForEach(starterPrompts, id: \.self) { prompt in
                Button {
                    _ = submitQuestion(prompt)
                } label: {
                    HStack {
                        Text(prompt)
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "arrow.up.circle.fill")
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(service.isStreaming)
                .accessibilityLabel(prompt)
                .accessibilityHint("Sends this suggested styling question.")
            }
        }
        .padding(18)
        .appCard(.ai)
    }

    private var signInPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(StyleMatchSessionRecoveryCopy.title)
                .font(.headline)
            Text(StyleMatchSessionRecoveryCopy.detail(for: "AI Stylist"))
                .foregroundStyle(.secondary)
            Button(StyleMatchSessionRecoveryCopy.actionTitle) {
                onSignInRequested()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Opens Profile to reconnect your KigoStylist session.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .appCard(.ai)
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            factAttachmentControls
            HStack(spacing: 10) {
                TextField("Ask your stylist...", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .disabled(service.isStreaming)
                    .submitLabel(.send)
                    .onSubmit {
                        sendDraft()
                    }
                    .accessibilityLabel("Stylist question")
                    .accessibilityHint("Type a styling question. The send button becomes available when text is entered.")

                if effectiveVoiceInputEnabled {
                    voiceInputButton
                } else {
                    #if DEBUG
                    Image(systemName: "mic.slash")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Voice input disabled for launch diagnosis")
                    #endif
                }

                if service.isStreaming {
                    Button {
                        service.stopStreaming()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Stop generating")
                    .accessibilityHint("Stops the current stylist response.")
                } else {
                    Button {
                        sendDraft()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(preparedDraft.isEmpty || draftExceedsLimit)
                    .accessibilityLabel("Send styling question")
                    .accessibilityHint("Sends your typed question to the personal stylist.")
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if draftExceedsLimit {
                    Text(StylistChatMessageLimit.limitMessage)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer(minLength: 0)
                }
                Text("\(draftUTF16Length) / 2,000")
                    .foregroundStyle(draftExceedsLimit ? .red : .secondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)
            }
            .font(.caption)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Message length")
            .accessibilityValue("\(draftUTF16Length) of 2,000 UTF-16 units\(draftExceedsLimit ? ", over the limit" : "")")
            if effectiveVoiceInputEnabled {
                voiceStatusRow
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
            }
        }
    }

    @ViewBuilder
    private var factAttachmentControls: some View {
        HStack(spacing: 8) {
            Menu {
                PhotosPicker(selection: $selectedVisionPhoto, matching: .images) {
                    Label("Choose Photo", systemImage: "photo")
                }
                Button("Choose Saved Scan Facts") {
                    reloadFactSelections()
                    factAttachmentSheet = .savedScan
                }
                Button("Choose Closet Items") {
                    reloadFactSelections()
                    factAttachmentSheet = .closet
                }
                Button("Attach style preferences") {
                    reloadFactSelections()
                    factAttachmentSheet = .stylePreferences
                }
                if hasFactSelection {
                    Button("Clear selected facts", role: .destructive) { clearFactSelections() }
                }
            } label: {
                Label("Add selected facts", systemImage: "paperclip")
            }
            .buttonStyle(.bordered)
            .disabled(service.isStreaming)
            if hasFactSelection {
                selectedFactChips
            } else {
                Text("Optional — selected facts only")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .accessibilityHint("Attachments are sent only when you explicitly select them. A selected photo is sent to the Worker for moderation and vision analysis after the Worker confirms the applicable permission.")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Optional selected stylist facts")
        .accessibilityHint("Choose exact saved scan facts or Closet items for this one request. Nothing is attached automatically.")
    }

    private var hasFactSelection: Bool {
        normalizedVisionImage != nil || !selectedSavedScanKeys.isEmpty || !selectedClosetKeys.isEmpty || !selectedStylePreferenceSelection.isEmpty
    }

    private var hasSelectedFactRecords: Bool {
        !selectedSavedScanKeys.isEmpty || !selectedClosetKeys.isEmpty
    }

    private var factSelectionSummary: String {
        var parts: [String] = []
        if normalizedVisionImage != nil { parts.append("photo") }
        if !selectedSavedScanKeys.isEmpty { parts.append("\(selectedSavedScanKeys.count) scan\(selectedSavedScanKeys.count == 1 ? "" : "s")") }
        if !selectedClosetKeys.isEmpty { parts.append("\(selectedClosetKeys.count) Closet item\(selectedClosetKeys.count == 1 ? "" : "s")") }
        if !selectedStylePreferenceSelection.isEmpty { parts.append("selected style preferences") }
        return "Using: \(parts.joined(separator: " · "))"
    }

    @ViewBuilder
    private var selectedFactChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if normalizedVisionImage != nil {
                    Button {
                        clearVisionImage()
                    } label: {
                        Label("Selected photo", systemImage: "xmark.circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Remove selected photo")
                }
                ForEach(availableSavedScanFacts.filter { selectedSavedScanKeys.contains($0.localRecordKey) }, id: \.localRecordKey) { scan in
                    Button {
                        selectedSavedScanKeys.remove(scan.localRecordKey)
                    } label: {
                        Label("Scan \(scan.scanDate.formatted(date: .abbreviated, time: .omitted))", systemImage: "xmark.circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Remove selected saved scan")
                }
                ForEach(availableClosetFacts.filter { selectedClosetKeys.contains($0.localRecordKey) }, id: \.localRecordKey) { item in
                    Button {
                        selectedClosetKeys.remove(item.localRecordKey)
                    } label: {
                        Label("\(item.category)", systemImage: "xmark.circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Remove selected Closet item")
                }
                if !selectedStylePreferenceSelection.isEmpty {
                    Button {
                        clearStylePreferenceSelection()
                    } label: {
                        Label("Style preferences", systemImage: "xmark.circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Remove selected style preferences")
                }
            }
        }
        .accessibilityLabel(factSelectionSummary)
    }

    private var anchoredInputBar: some View {
        inputBar
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
            .overlay(alignment: .top) {
                Divider()
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: StyleMatchComposerFramePreferenceKey.self,
                        value: proxy.frame(in: .global)
                    )
                }
            }
    }

    private var voiceInputButton: some View {
        Group {
            if speechInput.state.isActive {
                Menu {
                    Button("Stop Listening") {
                        speechInput.stopListening()
                    }
                    Button("Cancel Voice Input", role: .destructive) {
                        draft = speechInput.cancelListening()
                    }
                } label: {
                    Image(systemName: speechInput.state == .listening ? "mic.fill" : "mic")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(speechInput.state == .listening ? "Stop listening" : "Cancel voice input")
                .accessibilityValue(speechInput.state.userMessage ?? "Voice input active")
                .accessibilityHint("Opens controls to stop or cancel voice input.")
            } else {
                Button {
                    Task {
                        stopReadingResponse()
                        await speechInput.startListening(existingText: draft)
                    }
                } label: {
                    Image(systemName: "mic")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .disabled(service.isStreaming)
                .accessibilityLabel("Ask stylist by voice")
                .accessibilityValue(service.isStreaming ? "Unavailable while response is generating" : "Ready")
                .accessibilityHint("Starts voice input. You can review and edit the transcript before sending.")
            }
        }
    }

    @ViewBuilder
    private var voiceStatusRow: some View {
        if let message = speechInput.state.userMessage {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: speechInput.state.isActive ? "waveform" : "info.circle")
                    .accessibilityHidden(true)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if speechInput.state.isActive {
                    Button("Cancel") {
                        draft = speechInput.cancelListening()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Cancel voice input")
                } else if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("Clear") {
                        draft = ""
                        speechInput.clearTranscript()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Clear transcript")
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    private var starterPrompts: [String] {
        [
            "What goes with olive pants?",
            "Build an outfit around this item.",
            "Build three outfits around this item.",
            "What shoes work with this outfit?",
            "Make this look more professional.",
            "Make this outfit business casual.",
            "Give me a casual and an elevated version.",
            "Give me three color combinations.",
            "Suggest another shirt-and-pants combination.",
            "Build a dinner outfit.",
            "Give me a warm-weather option.",
            "What should I wear for dinner?",
            "Help me match this shirt."
        ]
    }

    private var shouldShowStarterPrompts: Bool {
        return !service.activeConversation.messages.contains {
            $0.role == .assistant
                && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func sendDraft() {
        if speechInput.state.isActive {
            speechInput.stopListening()
        }
        let capturedDraft = preparedDraft
        guard !capturedDraft.isEmpty, !draftExceedsLimit else { return }
        guard submitQuestion(capturedDraft) else { return }
        draft = ""
        speechInput.clearTranscript()
    }

    private func listen(to message: ChatMessage) {
        guard message.role == .assistant else { return }
        let response = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !response.isEmpty else { return }

        // Input and output must not compete for the shared audio session. Only
        // cancel active recognition so an unrelated typed draft is retained.
        if speechInput.state.isActive {
            draft = speechInput.cancelListening()
        }
        stopReadingResponse()
        speakingAssistantMessageID = message.id
        voiceAssistant.speak(response)
    }

    private func stopReadingResponse() {
        voiceAssistant.stop()
        speakingAssistantMessageID = nil
    }

    private var preparedDraft: String {
        StylistChatMessageLimit.trimmedForSending(draft)
    }

    private var draftUTF16Length: Int {
        StylistChatMessageLimit.utf16Length(of: preparedDraft)
    }

    private var draftExceedsLimit: Bool {
        draftUTF16Length > StylistChatMessageLimit.maximumUTF16Length
    }

    @discardableResult
    private func submitQuestion(_ question: String) -> Bool {
        guard let authority = currentPendingSendAuthority else {
            reportUnavailableAuthority()
            return false
        }
        service.refreshAuthorizationState()
        guard service.authorizationState == .authorized else {
            service.inlineError = StylistChatError.unauthorized.localizedDescription
            return false
        }
        switch aiTransmissionConsent.state {
        case .accepted:
            break
        case .undecided:
            pendingConsentRequest = PendingConsentRequest(question: question, authority: authority)
            isShowingAITransmissionDisclosure = true
            return false
        case .declined:
            service.inlineError = StylistChatError.aiTransmissionConsentRequired.localizedDescription
            return false
        }
        return send(question, authorizedBy: authority)
    }

    private func continueAfterAcceptingAITransmission() {
        guard let pending = pendingConsentRequest else { return }
        pendingConsentRequest = nil
        if send(pending.question, authorizedBy: pending.authority) {
            draft = ""
            speechInput.clearTranscript()
        }
    }

    private func recordCurrentAIProcessingConsent() async -> Bool {
        guard !isRecordingAIProcessingConsent else { return false }
        isRecordingAIProcessingConsent = true
        defer { isRecordingAIProcessingConsent = false }
        do {
            try await AIProcessingConsentService().acceptCurrentConsent()
            aiTransmissionConsent.accept()
            return true
        } catch {
            service.inlineError = (error as? LocalizedError)?.errorDescription
                ?? AIProcessingConsentServiceError.unavailable.localizedDescription
            return false
        }
    }

    @discardableResult
    private func send(_ question: String, authorizedBy authority: StylistPendingSendAuthority) -> Bool {
        guard authority.isCurrent(
            activeConversationScope: service.activeConversation.scope,
            hasExplicitlySelectedGeneralStylist: hasExplicitlySelectedGeneralStylist,
            screenAwarenessSnapshot: screenAwarenessSnapshot,
            screenAwarenessGeneration: screenAwarenessGeneration,
            availableShoppingProductIDs: availableShoppingProductIDs
        ) else {
            reportUnavailableAuthority()
            return false
        }
        guard routeMissingScopedConsentIfNeeded() else { return false }
        if normalizedVisionImage != nil {
            return sendVision(question)
        }
        let assembly = currentConversationAssembly(including: question)
        var context = assembly.context
        switch resolvingSelectedFactContextForSend() {
        case .noneSelected:
            break
        case let .resolved(selectedFactContext):
            context.stylistFactContext = selectedFactContext
        case .failed:
            return false
        }
        do {
            context.stylePreferences = try PersonalizationContextBuilder.chatV2StylePreferences(
                selection: selectedStylePreferenceSelection,
                currentProfile: ProfileStore().currentProfile.personalizationContext
            )
        } catch {
            inlineFactSelectionError("A selected style preference changed. Review your selection before sending.")
            return false
        }
        let accepted = service.send(
            question,
            forcedContext: context,
            intelligenceSnapshot: assembly.snapshot
        )
        // These local keys are a single-send selection aid, not conversation
        // state. A follow-up, relaunch, or new chat must choose them again.
        if accepted { clearTransientFactSelections() }
        return accepted
    }

    @discardableResult
    private func sendVision(_ question: String) -> Bool {
        guard let image = normalizedVisionImage else { return false }
        let factResolution = resolvingSelectedFactContextForSend()
        let factContext: PersonalizationContextBuilder.StylistFactContextV1?
        switch factResolution {
        case .noneSelected: factContext = nil
        case let .resolved(context): factContext = context
        case .failed: return false
        }
        let factAttachments: PersonalizationContextBuilder.VisionV1Attachments?
        do {
            factAttachments = try factContext.flatMap { try PersonalizationContextBuilder.visionV1Attachments(from: $0) }
        } catch {
            inlineFactSelectionError("Selected facts cannot be used with this photo. Review the selection and try again.")
            return false
        }
        let profile = ProfileStore().currentProfile.personalizationContext
        let preferenceAttachment: PersonalizationContextBuilder.VisionV1StylePreferences?
        do {
            preferenceAttachment = try PersonalizationContextBuilder.visionV1StylePreferences(
                selection: selectedStylePreferenceSelection,
                currentProfile: profile
            )
        } catch {
            inlineFactSelectionError("A selected style preference changed. Review your selection before sending.")
            return false
        }
        let attachments = VisionChatRequestV1.Attachments(
            selectedImage: image,
            selectedScanFacts: factAttachments?.selectedScanFacts,
            stylePreferences: preferenceAttachment,
            selectedClosetItems: factAttachments?.selectedClosetItems
        )
        let request: VisionChatRequestV1
        if let retry = visionRetryRequest,
           retry.prompt == question,
           retry.attachments == attachments {
            request = retry
        } else {
            request = VisionChatRequestV1(
                contractVersion: 1,
                requestID: UUID().uuidString.lowercased(),
                prompt: question,
                attachments: attachments
            )
            visionRetryRequest = request
        }
        guard let encoded = try? JSONEncoder().encode(request), encoded.count <= 8 * 1024 * 1024 else {
            inlineFactSelectionError("Selected attachments are too large to send. Remove an attachment and try again.")
            return false
        }
        return service.sendVision(request) { success in
            if success {
                clearTransientFactSelections()
                clearVisionImage()
            }
        }
    }

    private func resolvingSelectedFactContextForSend() -> StylistFactContextResolution {
        guard hasSelectedFactRecords else { return .noneSelected }
        do {
            // Re-resolve immediately before the request. A deleted, missing,
            // or inaccessible record never falls back to the newest record.
            let currentScans = try SavedScanPersistenceAuthority().enumerateSavedScanStylistFacts()
            let currentCloset = try ClosetPersistenceAuthority().enumerateStylistFacts()
            let scans = currentScans.filter { selectedSavedScanKeys.contains($0.localRecordKey) }
            let closet = currentCloset.filter { selectedClosetKeys.contains($0.localRecordKey) }
            guard scans.count == selectedSavedScanKeys.count,
                  closet.count == selectedClosetKeys.count else {
                inlineFactSelectionError("A selected item is no longer available. Choose it again before sending.")
                return .failed
            }
            guard let context = try PersonalizationContextBuilder.stylistFactContext(
                selectedCloset: closet,
                selectedScans: scans
            ) else {
                inlineFactSelectionError("No selected facts are attached.")
                return .failed
            }
            return .resolved(context)
        } catch {
            inlineFactSelectionError((error as? LocalizedError)?.errorDescription ?? "Selected facts are unavailable. Choose them again before sending.")
            return .failed
        }
    }

    private func inlineFactSelectionError(_ message: String) {
        service.inlineError = message
    }

    private func reloadFactSelections() {
        do {
            availableSavedScanFacts = try SavedScanPersistenceAuthority().enumerateSavedScanStylistFacts()
            availableClosetFacts = try ClosetPersistenceAuthority().enumerateStylistFacts()
            currentStylePreferences = ProfileStore().currentProfile.personalizationContext
            factSelectionAvailabilityError = nil
            selectedSavedScanKeys = selectedSavedScanKeys.intersection(Set(availableSavedScanFacts.map(\.localRecordKey)))
            selectedClosetKeys = selectedClosetKeys.intersection(Set(availableClosetFacts.map(\.localRecordKey)))
            reResolveStylePreferenceSelection()
        } catch {
            availableSavedScanFacts = []
            availableClosetFacts = []
            currentStylePreferences = nil
            factSelectionAvailabilityError = "Selected facts are unavailable. Try again later."
            clearFactSelections()
        }
    }

    private func clearTransientFactSelections() {
        selectedSavedScanKeys = []
        selectedClosetKeys = []
    }

    private func clearFactSelections() {
        clearTransientFactSelections()
        clearStylePreferenceSelection()
        saveRememberedStylePreferences()
    }

    private func clearVisionImage() {
        selectedVisionPhoto = nil
        normalizedVisionImage = nil
        visionRetryRequest = nil
    }

    private func prepareVisionImage(_ item: PhotosPickerItem?) {
        guard let item else { normalizedVisionImage = nil; return }
        visionRetryRequest = nil
        isPreparingVisionImage = true
        Task {
            defer { isPreparingVisionImage = false }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw StylistVisionRequestError.invalidSelection }
                normalizedVisionImage = try StylistVisionImageNormalizer.normalizeToJPEG(data)
            } catch {
                normalizedVisionImage = nil
                inlineFactSelectionError("This photo could not be prepared safely. Choose a JPEG, PNG, or HEIC photo and try again.")
            }
        }
    }

    private var selectedStylePreferenceSelection: PersonalizationContextBuilder.VisionStylePreferenceSelection {
        .init(
            preferredColors: selectedPreferredColors.sorted(),
            avoidedColors: selectedAvoidedColors.sorted(),
            preferredFits: selectedPreferredFits.sorted(),
            preferredStyles: selectedPreferredStyles.sorted(),
            preferredBrands: selectedPreferredBrands.sorted()
        )
    }

    private var hasStylePreferenceSelection: Bool { !selectedStylePreferenceSelection.isEmpty }

    private func clearStylePreferenceSelection() {
        selectedPreferredColors = []
        selectedAvoidedColors = []
        selectedPreferredFits = []
        selectedPreferredStyles = []
        selectedPreferredBrands = []
    }

    private var rememberedStylePreferencesKey: String {
        PersonalStylistStorage.scopedKey("rememberedStylePreferences", userID: PersonalStylistStorage.activeUserID())
    }

    private func saveRememberedStylePreferences() {
        let values = selectedStylePreferenceSelection
        UserDefaults.standard.set([
            "preferredColors": values.preferredColors,
            "avoidedColors": values.avoidedColors,
            "preferredFits": values.preferredFits,
            "preferredStyles": values.preferredStyles,
            "preferredBrands": values.preferredBrands
        ], forKey: rememberedStylePreferencesKey)
    }

    private func loadRememberedStylePreferences() {
        guard let values = UserDefaults.standard.dictionary(forKey: rememberedStylePreferencesKey) else { return }
        selectedPreferredColors = Set(values["preferredColors"] as? [String] ?? [])
        selectedAvoidedColors = Set(values["avoidedColors"] as? [String] ?? [])
        selectedPreferredFits = Set(values["preferredFits"] as? [String] ?? [])
        selectedPreferredStyles = Set(values["preferredStyles"] as? [String] ?? [])
        selectedPreferredBrands = Set(values["preferredBrands"] as? [String] ?? [])
        reResolveStylePreferenceSelection()
    }

    private func reResolveStylePreferenceSelection() {
        guard let profile = currentStylePreferences else { clearStylePreferenceSelection(); return }
        selectedPreferredColors = selectedPreferredColors.intersection(Set(profile.favoriteColors))
        selectedAvoidedColors = selectedAvoidedColors.intersection(Set(profile.avoidedColors))
        selectedPreferredBrands = selectedPreferredBrands.intersection(Set(profile.favoriteBrands))
        selectedPreferredStyles = selectedPreferredStyles.intersection(Set(profile.styleGoals))
        let fits = profile.preferredFit?.isSet == true ? Set([profile.preferredFit!.rawValue]) : []
        selectedPreferredFits = selectedPreferredFits.intersection(fits)
    }

    private func refreshScopedConsent() {
        guard !isRefreshingScopedConsent else { return }
        isRefreshingScopedConsent = true
        Task {
            defer { isRefreshingScopedConsent = false }
            do {
                scopedConsentStates = try await AIScopedConsentService().currentStates()
            } catch {
                // A missing/failed authority read is deliberately indistinguishable
                // from no grant in the UI and never permits an outbound context.
                scopedConsentStates = [:]
            }
        }
    }

    private var currentConsentAttachmentSnapshot: StylistScopedConsentAttachmentSnapshot {
        StylistScopedConsentAttachmentSnapshot(
            selectedImage: normalizedVisionImage != nil,
            selectedScanFacts: !selectedSavedScanKeys.isEmpty,
            stylePreferences: !selectedStylePreferenceSelection.isEmpty,
            selectedClosetItems: !selectedClosetKeys.isEmpty
        )
    }

    private func missingScopedConsent() -> [AIScopedConsentScope] {
        let requiredScopes = StylistScopedConsentRouter.requiredScopes(for: currentConsentAttachmentSnapshot)
        return StylistScopedConsentRouter.missingScopes(from: requiredScopes, states: scopedConsentStates)
    }

    private func routeMissingScopedConsentIfNeeded() -> Bool {
        guard let missingScope = missingScopedConsent().first else { return true }
        scopedConsentFeedback = nil
        scopedConsentSheet = missingScope
        inlineFactSelectionError("Allow \(missingScope.permissionTitle) before asking AI Stylist.")
        return false
    }

    private func grantScopedConsent(_ scope: AIScopedConsentScope) {
        guard !isMutatingScopedConsent else { return }
        isMutatingScopedConsent = true
        scopedConsentFeedback = nil
        let service = AIScopedConsentService()
        Task {
            defer { isMutatingScopedConsent = false }
            do {
                let expectedRevision = scopedConsentStates[scope]?.revision ?? 0
                _ = try await service.grant(scope, expectedRevision: expectedRevision)
                let refreshedStates = try await service.currentStates()
                guard refreshedStates[scope]?.granted == true else {
                    throw AIScopedConsentServiceError.invalidResponse
                }
                scopedConsentStates = refreshedStates
                scopedConsentFeedback = "Permission granted."
                scopedConsentSheet = nil
            } catch {
                scopedConsentFeedback = (error as? LocalizedError)?.errorDescription
                    ?? "We could not confirm that permission. Please try again."
                inlineFactSelectionError(scopedConsentFeedback!)
            }
        }
    }

    private func mutateScopedConsent(_ kind: StylistFactAttachmentKind) {
        let scope = kind.scope
        guard scopedConsentStates[scope]?.granted == true else {
            // Grants use the same post-200 authoritative reload path as the
            // send-blocking sheet; a mutation response is not local authority.
            grantScopedConsent(scope)
            return
        }
        let service = AIScopedConsentService()
        Task {
            do {
                // Disable locally before request completion. A successful
                // response is still required before presenting revocation
                // as confirmed or allowing any future selected-fact send.
                if let state = scopedConsentStates[scope] {
                    scopedConsentStates[scope] = AIScopedConsentState(scope: scope, granted: false, revision: state.revision)
                }
                try await service.revoke(scope)
                refreshScopedConsent()
            } catch {
                scopedConsentStates[scope] = nil
                inlineFactSelectionError((error as? LocalizedError)?.errorDescription ?? "We could not confirm that permission. Please try again.")
            }
        }
    }

    private func scopedConsentPermissionSheet(_ scope: AIScopedConsentScope) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Allow \(scope.permissionTitle)")
                    .font(.title2.bold())
                Text("AI Stylist will use only the explicitly selected \(scope.permissionTitle.lowercased()) for this request. The Worker verifies this permission for your account before sending.")
                    .foregroundStyle(.secondary)
                if let scopedConsentFeedback {
                    Text(scopedConsentFeedback)
                        .foregroundStyle(scopedConsentFeedback == "Permission granted." ? .green : .red)
                }
                Button {
                    grantScopedConsent(scope)
                } label: {
                    if isMutatingScopedConsent {
                        ProgressView("Allowing…")
                    } else {
                        Text(scope.allowAccessibilityLabel)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isMutatingScopedConsent)
                .accessibilityLabel(scope.allowAccessibilityLabel)
                Spacer()
            }
            .padding()
            .navigationTitle("AI Sharing Permission")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") { scopedConsentSheet = nil }
                }
            }
        }
    }

    private func factAttachmentSelectionSheet(_ kind: StylistFactAttachmentKind) -> some View {
        NavigationStack {
            List {
                Section {
                    Text("AI Stylist uses only the selected facts below when you send a question. It does not attach your photo, profile picture, full Closet, or other scans.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button(scopedConsentStates[kind.scope]?.granted == true ? "Stop sharing \(kind.title)" : "Allow \(kind.title)") {
                        mutateScopedConsent(kind)
                    }
                    .buttonStyle(.bordered)
                } header: {
                    Text("Permission")
                }
                Section(kind.title) {
                    switch kind {
                    case .savedScan:
                        if let factSelectionAvailabilityError {
                            Text(factSelectionAvailabilityError).foregroundStyle(.secondary)
                        } else if availableSavedScanFacts.isEmpty {
                            Text("No saved scan facts are available.").foregroundStyle(.secondary)
                        }
                        ForEach(availableSavedScanFacts, id: \.localRecordKey) { scan in
                            Button {
                                toggleSavedScan(scan.localRecordKey)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(scan.scanDate, style: .date)
                                        if let style = scan.detectedStyle { Text(style).font(.caption).foregroundStyle(.secondary) }
                                    }
                                    Spacer()
                                    Image(systemName: selectedSavedScanKeys.contains(scan.localRecordKey) ? "checkmark.circle.fill" : "circle")
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    case .closet:
                        if let factSelectionAvailabilityError {
                            Text(factSelectionAvailabilityError).foregroundStyle(.secondary)
                        } else if availableClosetFacts.isEmpty {
                            Text("No Closet items are available.").foregroundStyle(.secondary)
                        }
                        ForEach(availableClosetFacts, id: \.localRecordKey) { item in
                            Button {
                                toggleCloset(item.localRecordKey)
                            } label: {
                                HStack {
                                    Text(item.category)
                                    Spacer()
                                    Image(systemName: selectedClosetKeys.contains(item.localRecordKey) ? "checkmark.circle.fill" : "circle")
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    case .stylePreferences:
                        stylePreferenceRows
                    }
                }
            }
            .navigationTitle(kind.title)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { saveRememberedStylePreferences(); factAttachmentSheet = nil } } }
        }
    }

    @ViewBuilder
    private var stylePreferenceRows: some View {
        if let profile = currentStylePreferences {
            Text("Selected preferences remain in use until you change or clear them. They are checked against your current profile before each request.")
                .font(.caption)
                .foregroundStyle(.secondary)
            stylePreferenceSection("Preferred colors", values: profile.favoriteColors, selected: $selectedPreferredColors)
            stylePreferenceSection("Avoided colors", values: profile.avoidedColors, selected: $selectedAvoidedColors)
            stylePreferenceSection("Preferred brands", values: profile.favoriteBrands, selected: $selectedPreferredBrands)
            stylePreferenceSection("Style labels", values: profile.styleGoals, selected: $selectedPreferredStyles)
            if let fit = profile.preferredFit, fit.isSet {
                stylePreferenceSection("Preferred fit", values: [fit.rawValue], selected: $selectedPreferredFits)
            }
            if profile.favoriteColors.isEmpty, profile.avoidedColors.isEmpty, profile.favoriteBrands.isEmpty,
               profile.styleGoals.isEmpty, profile.preferredFit?.isSet != true {
                Text("No eligible stored style preferences are available.").foregroundStyle(.secondary)
            }
        } else {
            Text("Style preferences are unavailable. No preferences are attached.").foregroundStyle(.secondary)
        }
    }

    private func stylePreferenceSection(
        _ title: String,
        values: [String],
        selected: Binding<Set<String>>
    ) -> some View {
        Section(title) {
            ForEach(values, id: \.self) { value in
                Button {
                    if selected.wrappedValue.contains(value) {
                        selected.wrappedValue.remove(value)
                    } else {
                        selected.wrappedValue.insert(value)
                    }
                } label: {
                    HStack {
                        Text(value)
                        Spacer()
                        Image(systemName: selected.wrappedValue.contains(value) ? "checkmark.circle.fill" : "circle")
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func toggleSavedScan(_ key: String) {
        if selectedSavedScanKeys.contains(key) {
            selectedSavedScanKeys.remove(key)
        } else if selectedSavedScanKeys.count < PersonalizationContextBuilder.maximumSavedScans {
            selectedSavedScanKeys.insert(key)
        } else {
            inlineFactSelectionError("Select at most \(PersonalizationContextBuilder.maximumSavedScans) saved scans for one request.")
        }
    }

    private func toggleCloset(_ key: UUID) {
        if selectedClosetKeys.contains(key) {
            selectedClosetKeys.remove(key)
        } else if selectedClosetKeys.count < PersonalizationContextBuilder.maximumClosetItems {
            selectedClosetKeys.insert(key)
        } else {
            inlineFactSelectionError("Select at most \(PersonalizationContextBuilder.maximumClosetItems) Closet items for one request.")
        }
    }

    private var currentPendingSendAuthority: StylistPendingSendAuthority? {
        let scope = service.activeConversation.scope
        if scope.isScanBound {
            return .scan(scope)
        }
        if hasExplicitlySelectedGeneralStylist || screenAwarenessSnapshot == nil {
            return .general
        }
        guard let snapshot = validScreenAwarenessSnapshot else { return nil }
        return .screen(snapshot, generation: screenAwarenessGeneration)
    }

    private var validScreenAwarenessSnapshot: ScreenAwarenessSnapshot? {
        guard !hasExplicitlySelectedGeneralStylist,
              !service.activeConversation.scope.isScanBound,
              let snapshot = screenAwarenessSnapshot,
              snapshot.isCurrent(
                generation: screenAwarenessGeneration,
                availableShoppingProductIDs: availableShoppingProductIDs
              ) else {
            return nil
        }
        return snapshot
    }

    private func reportUnavailableAuthority() {
        service.inlineError = "That context is no longer available. Choose it again from Home, Closet, or Shop."
    }

    private var currentThreadCorrection: StylistIntelligenceThreadCorrection? {
        StylistConversationState.reconstructing(
            messages: service.activeConversation.messages,
            including: pendingConsentRequest?.question
        )
            .intelligenceThreadCorrection
    }

    private func currentConversationContext(including question: String? = nil) -> ChatContext {
        currentConversationAssembly(including: question).context
    }

    private func currentConversationAssembly(
        including question: String? = nil
    ) -> StylistIntelligenceRequestAssembly {
        if hasExplicitlySelectedGeneralStylist, !service.activeConversation.scope.isScanBound {
            return assemblingIntelligenceRequest(
                to: generalStylistBaseContext,
                screenAwareness: nil,
                exactScan: nil,
                including: question
            )
        }
        if !service.activeConversation.scope.isScanBound, screenAwarenessSnapshot != nil {
            return assemblingIntelligenceRequest(
                to: generalStylistBaseContext,
                screenAwareness: screenAwarenessSnapshot,
                exactScan: nil,
                including: question
            )
        }
        let currentScreenContext = StylistConversationScreenContextResolver.resolve(
            screenContext,
            hasAuthoritativeScanHandoff: activeConversationContext != nil,
            savedScanIDs: StylistSavedScanAvailability.savedScanIDs()
        )
        let context = activeConversationContext ?? PersonalizationContextBuilder.conversationalStylistContext(
            screenContext: currentScreenContext,
            weatherConstraint: AIStylistContextSelection.weatherConstraint(defaults: .standard)
        )
        if service.activeConversation.scope.isScanBound,
           let scan = service.activeScanConversationContext {
            let scoped = scanContext(scan, applyingTo: context)
            return assemblingIntelligenceRequest(
                to: scoped,
                screenAwareness: nil,
                exactScan: scan.authoritativeScan,
                including: question
            )
        }
        let current = context.applyingCurrentScreenContext(currentScreenContext)
        let authoritativeScan = CurrentScanContextProvider.resolve(
            preferred: current.authoritativeScan,
            screenContext: current.screenContext
        )
        return assemblingIntelligenceRequest(
            to: current.applyingAuthoritativeScan(authoritativeScan),
            screenAwareness: nil,
            exactScan: nil,
            including: question
        )
    }

    private var generalStylistBaseContext: ChatContext {
        PersonalizationContextBuilder.conversationalStylistContext(
            screenContext: .aiTab(),
            weatherConstraint: AIStylistContextSelection.weatherConstraint(defaults: .standard)
        )
    }

    private func assemblingIntelligenceRequest(
        to context: ChatContext,
        screenAwareness: ScreenAwarenessSnapshot?,
        exactScan: StylistAuthoritativeScanContext?,
        including question: String? = nil
    ) -> StylistIntelligenceRequestAssembly {
        let threadState = StylistConversationState.reconstructing(
            messages: service.activeConversation.messages,
            including: question
        )
        let snapshot = StylistIntelligenceSnapshotBuilder.build(
            StylistIntelligenceSnapshotInput(
                conversationScope: service.activeConversation.scope,
                screenAwareness: screenAwareness,
                screenAwarenessGeneration: screenAwarenessGeneration,
                exactScan: exactScan,
                threadCorrection: threadState.intelligenceThreadCorrection,
                availableShoppingProductIDs: availableShoppingProductIDs,
                weather: WeatherKitAuthority.loadSnapshot(defaults: .standard),
                styleProfileSummary: context.profileSummary,
                conversation: StylistConversationSnapshot.from(exactScan)
            )
        )
        return StylistIntelligenceRequestAssembly(
            context: snapshot.networkSafeContext(applying: context),
            snapshot: snapshot
        )
    }

    private struct StylistIntelligenceRequestAssembly {
        let context: ChatContext
        let snapshot: StylistIntelligenceSnapshot
    }

    private struct PendingConsentRequest {
        let question: String
        let authority: StylistPendingSendAuthority
    }

    private var selectedScanContextNote: some View {
        Group {
            if let scan = service.activeScanConversationContext {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        isScanCardExpanded.toggle()
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Discussing this Scan", systemImage: "pin.fill")
                                    .font(.headline)
                                Text("\(scan.score)/100 • \(scan.scoreBand)")
                                    .font(.subheadline.weight(.semibold))
                            }
                            Spacer()
                            Image(systemName: isScanCardExpanded ? "chevron.up" : "chevron.down")
                                .accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Discussing this Scan, \(scan.score) out of 100, \(scan.scoreBand)")
                    .accessibilityHint(isScanCardExpanded ? "Collapses scan details." : "Expands scan details.")

                    if isScanCardExpanded {
                        if let detectedStyle = scan.detectedStyle {
                            Text("Detected style: \(detectedStyle)")
                        }
                        if !scan.palette.isEmpty {
                            Text("Palette: \(scan.palette.joined(separator: ", "))")
                        }
                        if let outfitType = scan.outfitType {
                            Text("Outfit type: \(outfitType)")
                        }
                        Text(scan.selectedOccasion.map { "Selected occasion: \($0)" } ?? "Occasion not selected")
                        if let weather = scan.reliableWeatherSummary {
                            Text("Weather: \(weather)")
                        } else {
                            Text("Reliable weather unavailable")
                                .foregroundStyle(.secondary)
                        }
                        if let analyzedAt = scan.analyzedAt {
                            Text("Scan date: \(analyzedAt, style: .date) \(analyzedAt, style: .time)")
                                .foregroundStyle(.secondary)
                        }
                        if !scan.evidenceLimitations.isEmpty {
                            Text("Evidence limitations")
                                .fontWeight(.semibold)
                            ForEach(scan.evidenceLimitations, id: \.self) { limitation in
                                Text(limitation)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Button("Switch to General Stylist") {
                            switchToGeneralStylist()
                        }
                        .buttonStyle(.bordered)
                        .accessibilityHint("Stops using this scan as the conversation context.")
                    }
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(scanContextAccessibilityLabel(scan))
                .accessibilityHint("Using selected scan context. This conversation is limited to the selected scan.")
            }
        }
    }

    private func currentContextNote(_ snapshot: ScreenAwarenessSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: snapshot.contextIconName)
                    .font(.headline)
                    .foregroundStyle(StyleMatchPremiumPalette.champagneSoft)
                    .frame(width: 38, height: 38)
                    .background(StyleMatchPremiumPalette.champagne.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("CURRENT CONTEXT")
                        .font(.caption2.weight(.black))
                        .tracking(1.1)
                        .foregroundStyle(StyleMatchPremiumPalette.champagneSoft)
                    Text(snapshot.displayTitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                }

                Spacer(minLength: 8)

                Button("What I’m using") {
                    isShowingCurrentContext = true
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(StyleMatchPremiumPalette.champagneSoft)
            }

            Text(snapshot.detail)
                .font(.caption)
                .foregroundStyle(StyleMatchPremiumPalette.mutedText)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(contextSignalLabels(for: snapshot), id: \.self) { label in
                        Text(label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.88))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.white.opacity(0.06), in: Capsule())
                            .overlay(Capsule().stroke(StyleMatchPremiumPalette.border, lineWidth: 1))
                    }
                }
            }
            .accessibilityLabel("Context signals: \(contextSignalLabels(for: snapshot).joined(separator: ", "))")

            if let correction = currentThreadCorrection?.customerVisibleFact {
                Text(correction)
                    .font(.caption)
                    .foregroundStyle(StyleMatchPremiumPalette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Use General Stylist instead") {
                switchToGeneralStylist()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.82))
            .frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(StyleMatchPremiumPalette.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(StyleMatchPremiumPalette.champagne.opacity(0.20), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Current context. \(snapshot.displayTitle). \(snapshot.detail)")
    }

    private func contextSignalLabels(for snapshot: ScreenAwarenessSnapshot) -> [String] {
        var labels: [String] = []
        switch snapshot.kind {
        case .home:
            labels.append("Home")
        case .closetItem:
            labels.append(contentsOf: ["Closet", "Selected item"])
        case .shoppingProduct:
            labels.append(contentsOf: ["Shop", "Selected product"])
        case .profile:
            labels.append("Preferences")
        case .weatherStyling:
            labels.append("Weather")
        case .scanComparison:
            labels.append("Scan comparison")
        }
        if snapshot.selectedOccasion != nil {
            labels.append("Occasion")
        }
        if !snapshot.customerVisibleFacts.isEmpty {
            labels.append("Confirmed facts")
        }
        return Array(labels.prefix(4))
    }

    private func contextualPromptStrip(_ snapshot: ScreenAwarenessSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ask about what you’re viewing")
                .font(.subheadline.weight(.bold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(contextualPrompts(for: snapshot).enumerated()), id: \.offset) { _, prompt in
                        Button {
                            _ = submitQuestion(prompt.question)
                        } label: {
                            Label(prompt.title, systemImage: prompt.icon)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 11)
                                .frame(minHeight: 40)
                                .background(StyleMatchPremiumPalette.champagne.opacity(0.10), in: Capsule())
                                .overlay(Capsule().stroke(StyleMatchPremiumPalette.champagne.opacity(0.24), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(service.isStreaming)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground).opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func contextualPrompts(for snapshot: ScreenAwarenessSnapshot) -> [(title: String, question: String, icon: String)] {
        switch snapshot.kind {
        case .home:
            return [
                ("Build today’s look", "Build today’s look from the context I opened.", "sparkles"),
                ("Improve it", "What would you change about today’s look?", "wand.and.stars"),
                ("Work-ready", "Make today’s look work-ready.", "briefcase.fill")
            ]
        case .closetItem:
            return [
                ("What works with this?", "What works with this closet item?", "tshirt.fill"),
                ("Build 3 outfits", "Build three outfits around this closet item.", "square.grid.2x2"),
                ("Best shoes", "What shoes work best with this closet item?", "shoeprints.fill")
            ]
        case .shoppingProduct:
            return [
                ("Should I buy this?", "Should I buy this product based on my confirmed style context?", "bag.fill"),
                ("Wardrobe fit", "How would this fit with my wardrobe?", "tshirt.fill"),
                ("Style it", "What would I wear with this product?", "sparkles")
            ]
        case .profile:
            return [
                ("Use my preferences", "Build a look using the profile preferences I opened.", "person.crop.circle"),
                ("Work look", "Build a work look from my confirmed preferences.", "briefcase.fill"),
                ("Closet gaps", "What wardrobe gaps should I consider from these preferences?", "checklist")
            ]
        case .weatherStyling:
            return [
                ("Weather-ready?", "Is this recommendation weather-ready?", "cloud.sun.fill"),
                ("Best shoes", "What shoes make sense for this weather?", "shoeprints.fill"),
                ("Need a layer?", "Do I need another layer for these conditions?", "wind")
            ]
        case .scanComparison:
            return [
                ("What improved?", "What improved between these scans?", "arrow.up.right"),
                ("Explain difference", "Explain the most important difference between these scans.", "chart.line.uptrend.xyaxis"),
                ("Next change", "What should I change next and then rescan?", "arrow.clockwise")
            ]
        }
    }

    private func currentThreadCorrectionNote(_ correction: StylistIntelligenceThreadCorrection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label("Current thread correction", systemImage: "checkmark.bubble.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Button("What I’m using") {
                    isShowingCurrentContext = true
                }
                .font(.caption.weight(.semibold))
            }
            if let fact = correction.customerVisibleFact {
                Text(fact)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Current thread correction. \(correction.customerVisibleFact ?? "")")
    }

    private var scanQuickFollowUps: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About this Scan")
                .font(.subheadline.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8)], spacing: 8) {
                ForEach(scanFollowUpPrompts, id: \.title) { prompt in
                    Button(prompt.title) {
                        _ = submitQuestion(prompt.question)
                    }
                    .buttonStyle(.bordered)
                    .disabled(service.isStreaming)
                    .accessibilityHint("Asks the stylist about the selected scan.")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var pinCurrentScanPrompt: some View {
        Button {
            pinCurrentScan()
        } label: {
            Label("Discuss this Scan", systemImage: "pin.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .accessibilityHint("Starts a separate conversation using only the current scan.")
    }

    private var canPinCurrentScan: Bool {
        (scanHandoff?.aiChatContext.authoritativeScan ?? initialContext?.authoritativeScan)?.isComplete == true
    }

    private var scanFollowUpPrompts: [(title: String, question: String)] {
        [
            ("Explain My Score", "Explain my score."),
            ("Best Shoes", "What shoes go with this outfit?"),
            ("Better Shirt", "What shirt would improve this outfit?"),
            ("Better Pants", "What pants would improve this outfit?"),
            ("Accessories", "What accessories work with this outfit?"),
            ("Weather Advice", "What weather advice applies to this outfit?"),
            ("Shopping Suggestions", "What shopping suggestions fit this outfit?")
        ]
    }

    private func applyCurrentScanHandoff() {
        if let selectedID = handoffController.openCurrentScanConversation(
            context: initialContext,
            screenContext: screenContext,
            generalStylistSelected: hasExplicitlySelectedGeneralStylist,
            using: service
        ) {
            _ = selectedID
            activeConversationContext = initialContext
        } else if activeConversationContext?.screenContext?.activeScanState != StylistActiveScanState.none {
            activeConversationContext = nil
            if service.activeConversation.scope.isScanBound {
                handoffController.clearSelection()
                service.newChat()
            }
        }
    }

    private func consumeExplicitScanHandoff() {
        guard let scanHandoff else { return }
        let selectedID = handoffController.consume(scanHandoff, using: service)
        guard selectedID != nil else {
            activeConversationContext = nil
            return
        }
        hasExplicitlySelectedGeneralStylist = false
        isScanCardExpanded = false
        activeConversationContext = scanHandoff.aiChatContext
    }

    private func pinCurrentScan() {
        guard let context = scanHandoff?.aiChatContext ?? initialContext,
              context.authoritativeScan?.isComplete == true else {
            return
        }
        hasExplicitlySelectedGeneralStylist = false
        isScanCardExpanded = false
        service.openOrCreateScanConversation(context: context)
        activeConversationContext = context
    }

    private func switchToGeneralStylist() {
        hasExplicitlySelectedGeneralStylist = true
        isScanCardExpanded = false
        _ = speechInput.cancelListening()
        draft = ""
        speechInput.clearTranscript()
        activeConversationContext = nil
        service.newChat()
        onUseGeneralStylist()
    }

    private func openConversation(_ conversation: ChatConversation) {
        hasExplicitlySelectedGeneralStylist = conversation.isVerifiedGeneral
        isScanCardExpanded = false
        activeConversationContext = conversation.scanContext.map { scanContext in
            var context = ChatContext(authoritativeScan: scanContext.authoritativeScan)
            context.screenContext = StylistScreenContext(
                currentTab: .ai,
                activeScanState: .saved,
                activeScanID: scanContext.scanID,
                selectedOccasion: scanContext.selectedOccasion,
                visibleOverallScore: scanContext.score,
                entryPoint: .scanResult,
                closetState: .unavailable
            )
            return context
        }
        _ = speechInput.cancelListening()
        draft = ""
        speechInput.clearTranscript()
        service.openConversation(conversation)
    }

    private func scanContext(_ scan: StylistConversationScanContext, applyingTo context: ChatContext) -> ChatContext {
        var resolved = context.applyingAuthoritativeScan(scan.authoritativeScan)
        resolved.screenContext = StylistScreenContext(
            currentTab: .ai,
            activeScanState: .saved,
            activeScanID: scan.scanID,
            selectedOccasion: scan.selectedOccasion,
            visibleOverallScore: scan.score,
            entryPoint: .scanResult,
            closetState: context.screenContext?.closetState ?? .unavailable
        )
        return resolved.applyingAuthoritativeScan(scan.authoritativeScan)
    }

    private func scanContextAccessibilityLabel(_ scan: StylistConversationScanContext) -> String {
        var parts = ["Discussing this Scan", "Score \(scan.score) out of 100, \(scan.scoreBand)"]
        if let style = scan.detectedStyle { parts.append("Detected style \(style)") }
        if !scan.palette.isEmpty { parts.append("Palette \(scan.palette.joined(separator: ", "))") }
        if let occasion = scan.selectedOccasion { parts.append("Selected occasion \(occasion)") }
        parts.append("Conversation uses only this scan")
        return parts.joined(separator: ". ")
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            if service.isStreaming {
                proxy.scrollTo("typing", anchor: .bottom)
            } else if let last = service.activeConversation.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func announceCompletedResponseIfNeeded() {
        guard !service.isStreaming,
              let message = service.activeConversation.messages.last(where: {
                  $0.role == .assistant && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              }),
              lastAnnouncedAssistantID != message.id else {
            return
        }
        lastAnnouncedAssistantID = message.id
        #if canImport(UIKit)
        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .announcement, argument: "Stylist response ready.")
        #endif
    }
}

private struct CurrentStylistContextSheet: View {
    let snapshot: ScreenAwarenessSnapshot?
    let threadCorrection: StylistIntelligenceThreadCorrection?
    let useGeneralStylist: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let snapshot {
                    Section("Current Context") {
                        Label(snapshot.displayTitle, systemImage: snapshot.kind == .home ? "house.fill" : "tshirt.fill")
                            .font(.headline)
                        Text(snapshot.detail)
                            .foregroundStyle(.secondary)
                    }
                    Section("How it helps") {
                        Text("KigoStylist uses this customer-visible context for this request only. It does not create a remembered preference.")
                    }
                }
                if let correction = threadCorrection?.customerVisibleFact {
                    Section("Current thread correction") {
                        Text(correction)
                            .foregroundStyle(.secondary)
                    }
                }
                if snapshot != nil || threadCorrection != nil {
                    Section {
                        Button("Use General Stylist instead") {
                            dismiss()
                            useGeneralStylist()
                        }
                        .frame(minHeight: 44)
                    }
                }
            }
            .navigationTitle("What I’m Using")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Customer-facing, versioned disclosure for the verified production processor chain.
struct AITransmissionConsentDisclosureView: View {
    @ObservedObject var consentStore: AITransmissionConsentStore
    let recordCurrentConsent: () async -> Bool
    let agreeAndContinue: () -> Void
    let decline: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isRecordingConsent = false
    @State private var acceptanceError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("KigoStylist sends information over the network when you use AI features.")
                        .font(.body)
                }
                Section("What may be sent") {
                    Text("Your question and relevant bounded text styling context, such as a preference or profile summary, selected scan or outfit details, and score breakdown information where applicable.")
                }
                Section("What is not sent") {
                    Text("This AI request path does not send raw photos or image bytes, screenshots, precise location, local database IDs, or internal route metadata.")
                }
                Section("Where it goes") {
                    Text("KigoStylist sends approved requests to its Cloudflare-hosted API. Cloudflare routes them to OpenAI, the downstream AI processor.")
                }
                Section("Why") {
                    Text("This information is used only to generate the AI Stylist response you requested.")
                }
                Section("Your choice") {
                    Text("Agree & Continue records your acceptance of the current AI-processing consent before any external AI transmission. Not Now sends no AI request and keeps local, non-AI features available. You can later review or revoke permission in Profile → Your Privacy → AI Processing Consent.")
                        .foregroundStyle(.secondary)
                }
                Section {
                    if let acceptanceError {
                        Text(acceptanceError)
                            .foregroundStyle(.red)
                    }
                    Button(isRecordingConsent ? "Recording consent…" : "Agree & Continue") {
                        Task {
                            isRecordingConsent = true
                            acceptanceError = nil
                            if await recordCurrentConsent() {
                                dismiss()
                                agreeAndContinue()
                            } else {
                                acceptanceError = "We could not record your AI consent. Please try again."
                            }
                            isRecordingConsent = false
                        }
                    }
                    .disabled(isRecordingConsent)
                    .frame(minHeight: 44)
                    Button("Not Now", role: .cancel) {
                        consentStore.decline()
                        dismiss()
                        decline()
                    }
                    .frame(minHeight: 44)
                }
            }
            .navigationTitle("AI Processing Consent")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") {
                        consentStore.decline()
                        dismiss()
                        decline()
                    }
                }
            }
        }
    }
}

private struct StyleMatchComposerFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .null

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isNull, !next.isEmpty {
            value = next
        }
    }
}

private struct ChatBubble: View {
    let message: ChatMessage
    let isStreaming: Bool
    let isReadAloudActive: Bool
    let onListen: () -> Void
    let onStopReading: () -> Void

    private var displayedContent: String {
        StylistChatPresentation.displayText(message.content)
    }

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 42) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                if message.role == .user {
                    Text(message.content.isEmpty && isStreaming ? "Thinking..." : displayedContent)
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(AppTab.ai.palette.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(StyleMatchPremiumPalette.champagneSoft)
                            Text("KIGOSTYLIST AI")
                                .font(.caption2.weight(.black))
                                .tracking(1.0)
                                .foregroundStyle(StyleMatchPremiumPalette.champagneSoft)
                            Spacer(minLength: 0)
                        }

                        Text(message.content.isEmpty && isStreaming ? "Thinking..." : displayedContent)
                            .foregroundStyle(.white.opacity(0.94))
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .background(StyleMatchPremiumPalette.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(StyleMatchPremiumPalette.champagne.opacity(0.18), lineWidth: 1)
                    )
                }

                if message.role == .assistant, let attribution = message.weatherAttribution {
                    WeatherKitAttributionView(attribution: attribution, surface: .weatherChat)
                }
                if message.role == .assistant,
                   !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !isStreaming {
                    if isReadAloudActive {
                        Button(action: onStopReading) {
                            Label("Stop", systemImage: "stop.fill")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(StyleMatchPremiumPalette.champagne)
                        .accessibilityLabel("Stop reading response")
                        .accessibilityHint("Stops the current Stylist response.")
                    } else {
                        Button(action: onListen) {
                            Label("Listen", systemImage: "speaker.wave.2.fill")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(StyleMatchPremiumPalette.champagne)
                        .accessibilityLabel("Listen to Stylist response")
                        .accessibilityHint("Reads this response aloud.")
                    }
                }
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if message.role != .user { Spacer(minLength: 28) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            StyleMatchAccessibilityText.chatMessageLabel(
                role: message.role == .user ? "You" : "Stylist",
                content: message.content.isEmpty && isStreaming ? "Thinking" : displayedContent
            )
        )
        .accessibilityValue(Text(message.timestamp, style: .time))
    }
}

private struct TypingIndicator: View {
    var body: some View {
        HStack {
            ProgressView()
            Text("Stylist is typing...")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .font(.subheadline)
        .padding(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Stylist is typing")
    }
}

private struct SystemChatRow: View {
    let text: String
    let retry: (() -> Void)?
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let retry {
                Button("Retry", action: retry)
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                    .accessibilityHint("Retries your last question once.")
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
                    .accessibilityHint("Reviews the current AI-processing consent before another request can be sent.")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Stylist message. \(text)")
    }
}

private struct ChatHistorySheet: View {
    let conversations: [ChatConversation]
    let onSelect: (ChatConversation) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if conversations.isEmpty {
                    Text("No previous chats yet.")
                        .foregroundStyle(.secondary)
                } else {
                    if !generalConversations.isEmpty {
                        Section("General Stylist") {
                            ForEach(generalConversations) { conversation in
                                conversationRow(conversation)
                            }
                        }
                    }
                    if !scanConversations.isEmpty {
                        Section("Scan Conversations") {
                            ForEach(scanConversations) { conversation in
                                conversationRow(conversation)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Prior chats")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var generalConversations: [ChatConversation] {
        conversations.filter(\.isVerifiedGeneral)
    }

    private var scanConversations: [ChatConversation] {
        conversations.filter(\.scope.isScanBound)
    }

    @ViewBuilder
    private func conversationRow(_ conversation: ChatConversation) -> some View {
        Button {
            onSelect(conversation)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title(for: conversation))
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text(subtitle(for: conversation))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("\(title(for: conversation)). \(subtitle(for: conversation))")
    }

    private func title(for conversation: ChatConversation) -> String {
        if let scan = conversation.scanContext {
            return "Saved Scan • \(scan.score)/100"
        }
        return conversation.messages.first(where: { $0.role == .user })?.content ?? "Stylist chat"
    }

    private func subtitle(for conversation: ChatConversation) -> String {
        if let scan = conversation.scanContext {
            var parts = [scan.scoreBand]
            if let style = scan.detectedStyle { parts.append(style) }
            if !scan.palette.isEmpty { parts.append(scan.palette.joined(separator: ", ")) }
            return parts.joined(separator: " • ")
        }
        return conversation.updatedAt.formatted(date: .abbreviated, time: .omitted)
    }
}
