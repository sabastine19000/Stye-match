import SwiftUI

struct StylistChatView: View {
    @StateObject private var service: StylistChatService
    @State private var draft = ""
    @State private var showingHistory = false

    private let initialQuestion: String?
    private let initialContext: ChatContext?

    init(
        service: StylistChatService? = nil,
        initialQuestion: String? = nil,
        initialContext: ChatContext? = nil
    ) {
        _service = StateObject(wrappedValue: service ?? StylistChatService())
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
                        service.newChat()
                    }
                }
            }
            .sheet(isPresented: $showingHistory) {
                ChatHistorySheet(conversations: service.conversations) { conversation in
                    service.openConversation(conversation)
                    showingHistory = false
                }
            }
            .onAppear {
                if let initialQuestion, let initialContext, service.activeConversation.messages.isEmpty {
                    service.sendPreseededQuestion(initialQuestion, context: initialContext)
                }
            }
        }
        .appScreenBackground(.ai)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
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
            Text("Get short, practical outfit advice based on your saved profile and recent scans.")
                .foregroundStyle(.secondary)

            ForEach(starterPrompts, id: \.self) { prompt in
                Button {
                    service.send(prompt)
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
            }
        }
        .padding(18)
        .appCard(.ai)
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            // future: add voice input when SFSpeechRecognizer support is scoped.
            HStack(spacing: 10) {
                TextField("Ask your stylist...", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .disabled(service.isStreaming)

                if service.isStreaming {
                    Button {
                        service.stopStreaming()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        service.send(draft)
                        draft = ""
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }

    private var starterPrompts: [String] {
        [
            "What should I wear today?",
            "Do these colors go together?",
            "Why did my last outfit score what it did?",
            "What’s missing from my closet?"
        ]
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
