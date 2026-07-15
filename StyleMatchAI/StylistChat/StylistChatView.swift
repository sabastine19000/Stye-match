import SwiftUI

struct StylistChatView: View {
    @StateObject private var service: StylistChatService
    @StateObject private var speechInput: StylistSpeechInputService
    @State private var draft = ""
    @State private var showingHistory = false
    @State private var activeConversationContext: ChatContext?

    private let initialQuestion: String?
    private let initialContext: ChatContext?
    private let voiceInputEnabled: Bool

    init(
        service: StylistChatService? = nil,
        speechInput: StylistSpeechInputService? = nil,
        voiceInputEnabled: Bool = true,
        initialQuestion: String? = nil,
        initialContext: ChatContext? = nil
    ) {
        _service = StateObject(
            wrappedValue: service ?? StylistChatService(
                contextProvider: { PersonalizationContextBuilder.conversationalStylistContext() }
            )
        )
        _speechInput = StateObject(wrappedValue: speechInput ?? StylistSpeechInputService())
        self.voiceInputEnabled = voiceInputEnabled
        self.initialQuestion = initialQuestion
        self.initialContext = initialContext
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messageList
                inputBar
            }
            .navigationTitle("AI Stylist Chat")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("History") {
                        showingHistory = true
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New chat") {
                        startNewChat()
                    }
                }
            }
            .sheet(isPresented: $showingHistory) {
                ChatHistorySheet(conversations: service.conversations) { conversation in
                    openConversation(conversation)
                    showingHistory = false
                }
            }
            .onAppear {
                if let initialQuestion, let initialContext, service.activeConversation.messages.isEmpty {
                    activeConversationContext = initialContext
                    service.sendPreseededQuestion(initialQuestion, context: initialContext)
                }
            }
            .onDisappear {
                draft = speechInput.cancelListening()
            }
            .styleMatchOnChange(of: speechInput.transcript) { transcript in
                draft = transcript
            }
        }
        .appScreenBackground(.ai)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if activeConversationContext != nil {
                        selectedScanContextNote
                    }

                    if service.activeConversation.messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(service.activeConversation.messages) { message in
                            ChatBubble(message: message, isStreaming: service.isStreaming)
                                .id(message.id)
                        }
                    }

                    if service.isStreaming {
                        TypingIndicator()
                            .id("typing")
                    }

                    if let error = service.inlineError {
                        SystemChatRow(text: error)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .padding(.bottom, 90)
            }
            .styleMatchOnChange(of: service.activeConversation.messages.count) { _ in
                scrollToBottom(proxy)
            }
            .styleMatchOnChange(of: service.isStreaming) { _ in
                scrollToBottom(proxy)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ask your stylist")
                .font(.title2)
                .fontWeight(.bold)
            Text("Get short, practical outfit advice for colors, garments, shoes, accessories, and occasions.")
                .foregroundStyle(.secondary)

            ForEach(starterPrompts, id: \.self) { prompt in
                Button {
                    service.send(prompt, forcedContext: currentConversationContext)
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
                .accessibilityLabel(prompt)
                .accessibilityHint("Sends this suggested styling question.")
            }
        }
        .padding(18)
        .appCard(.ai)
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                TextField("Ask your stylist...", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .disabled(service.isStreaming)
                    .submitLabel(.send)
                    .accessibilityLabel("Stylist question")
                    .accessibilityHint("Type a styling question. The send button becomes available when text is entered.")

                if voiceInputEnabled {
                    voiceInputButton
                } else {
                    Image(systemName: "mic.slash")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Voice input disabled for launch diagnosis")
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
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Send styling question")
                    .accessibilityHint("Sends your typed question to the personal stylist.")
                }
            }
            if voiceInputEnabled {
                voiceStatusRow
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
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
            .accessibilityElement(children: .combine)
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

    private func sendDraft() {
        if speechInput.state.isActive {
            speechInput.stopListening()
        }
        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDraft.isEmpty else { return }
        service.send(trimmedDraft, forcedContext: currentConversationContext)
        draft = ""
        speechInput.clearTranscript()
    }

    private var currentConversationContext: ChatContext {
        activeConversationContext ?? PersonalizationContextBuilder.conversationalStylistContext()
    }

    private var selectedScanContextNote: some View {
        Label("Using selected scan context", systemImage: "sparkles")
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground))
            .clipShape(Capsule())
            .accessibilityLabel("Using selected scan context")
            .accessibilityHint("This conversation can use facts from the scan you opened.")
    }

    private func startNewChat() {
        activeConversationContext = nil
        _ = speechInput.cancelListening()
        draft = ""
        speechInput.clearTranscript()
        service.newChat()
    }

    private func openConversation(_ conversation: ChatConversation) {
        activeConversationContext = nil
        _ = speechInput.cancelListening()
        draft = ""
        speechInput.clearTranscript()
        service.openConversation(conversation)
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
}

private struct ChatBubble: View {
    let message: ChatMessage
    let isStreaming: Bool

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 42) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content.isEmpty && isStreaming ? "Thinking..." : message.content)
                    .foregroundStyle(message.role == .user ? .white : .primary)
                    .padding(12)
                    .background(message.role == .user ? AppTab.ai.palette.accent : Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if message.role != .user { Spacer(minLength: 42) }
        }
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
    }
}

private struct SystemChatRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
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
                    ForEach(conversations) { conversation in
                        Button {
                            onSelect(conversation)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(title(for: conversation))
                                    .fontWeight(.semibold)
                                    .lineLimit(1)
                                Text(conversation.updatedAt, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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

    private func title(for conversation: ChatConversation) -> String {
        conversation.messages.first(where: { $0.role == .user })?.content ?? "Stylist chat"
    }
}
