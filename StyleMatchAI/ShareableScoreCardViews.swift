import SwiftUI

struct SharedScoreCardRecipientView: View {
    let token: String
    @Environment(\.dismiss) private var dismiss
    @State private var card: SharedScoreCard?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let configuration = ShareableScoreCardConfiguration.production

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if isLoading {
                        ProgressView("Opening shared card...")
                            .frame(maxWidth: .infinity, minHeight: 220)
                    } else if let card {
                        sharedCardContent(card)
                    } else {
                        unavailableState
                    }
                }
                .frame(maxWidth: 700, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Shared with you")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await load()
            }
        }
    }

    private func sharedCardContent(_ card: SharedScoreCard) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            PageColorBand(
                tab: .scan,
                title: "Shared with you",
                subtitle: "This score card was created with StyleMatch Pro.",
                icon: "sparkles"
            )

            if let imageURL = resolvedPhotoURL(for: card) {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 240)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                    case .failure:
                        EmptyView()
                    @unknown default:
                        EmptyView()
                    }
                }
            }

            if let score = card.sections.overallScore {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Overall Score")
                        .font(.headline)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(score)")
                            .font(.system(size: 62, weight: .black, design: .rounded))
                            .foregroundStyle(AppTab.scan.palette.accent)
                        Text("/100")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                    }
                    if let title = card.sections.scoreTitle, !title.isEmpty {
                        Text(title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(18)
                .appCard(.scan)
            }

            if let categories = card.sections.categoryScores, !categories.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Category Scores")
                        .font(.headline)
                    ForEach(categories) { category in
                        HStack {
                            Text(category.title)
                            Spacer()
                            Text(category.value)
                                .fontWeight(.bold)
                        }
                        .font(.subheadline)
                    }
                }
                .padding(18)
                .appCard(.scan)
            }

            if let notes = card.sections.outfitDescription, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Outfit Notes")
                        .font(.headline)
                    Text(notes)
                        .foregroundStyle(.secondary)
                }
                .padding(18)
                .appCard(.scan)
            }

            if let recommendations = card.sections.recommendations, !recommendations.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Improvement Recommendations")
                        .font(.headline)
                    ForEach(Array(recommendations.enumerated()), id: \.offset) { index, item in
                        Label(item, systemImage: "\(index + 1).circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(18)
                .appCard(.scan)
            }

            HStack {
                Label("Scored with StyleMatch Pro", systemImage: "checkmark.seal.fill")
                Spacer()
                if let dateText = scanDateText(card.sections.scanDate) {
                    Text(dateText)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            Button {
                dismiss()
            } label: {
                Label("Analyze Your Own Outfit", systemImage: "camera.viewfinder")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTab.scan.palette.accent)
        }
    }

    private var unavailableState: some View {
        VStack(spacing: 14) {
            Image(systemName: "link.badge.minus")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(.secondary)
            Text("This shared card is unavailable")
                .font(.title3)
                .fontWeight(.bold)
            Text(errorMessage ?? ShareableScoreCardError.unavailable.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .padding(24)
        .appCard(.scan)
    }

    @MainActor
    private func load() async {
        guard let configuration else {
            errorMessage = ShareableScoreCardError.configurationUnavailable.localizedDescription
            isLoading = false
            return
        }
        do {
            card = try await ShareableScoreCardClient(configuration: configuration).fetch(token: token)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? ShareableScoreCardError.unavailable.localizedDescription
        }
        isLoading = false
    }

    private func resolvedPhotoURL(for card: SharedScoreCard) -> URL? {
        guard let configuration,
              card.hasPhoto,
              let path = card.photoURL else {
            return nil
        }
        if let absolute = URL(string: path), absolute.scheme != nil {
            return absolute
        }
        return configuration.baseURL.appendingPathComponent(path)
    }

    private func scanDateText(_ value: String?) -> String? {
        guard let value,
              let date = ISO8601DateFormatter().date(from: value) else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

struct ShareableScoreCardManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var cards: [CreatedShareableScoreCard] = []
    @State private var statusMessage: String?

    private let store = ShareableScoreCardLocalStore()
    private let configuration = ShareableScoreCardConfiguration.production

    var body: some View {
        NavigationStack {
            List {
                if cards.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "link")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No Shared Links")
                            .font(.headline)
                        Text("Links you create from Share Preview will appear here until they expire.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(cards) { card in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(card.url.absoluteString)
                                .font(.subheadline)
                                .lineLimit(2)
                            Text(card.revokedAt == nil ? "Expires \(card.expiresAt.formatted(date: .abbreviated, time: .omitted))" : "Revoked")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack {
                                ShareLink(item: card.url) {
                                    Label("Copy Link", systemImage: "doc.on.doc")
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    Task { await revoke(card) }
                                } label: {
                                    Label("Revoke", systemImage: "xmark.circle")
                                }
                                .disabled(card.revokedAt != nil)
                            }
                            .font(.caption)
                        }
                        .padding(.vertical, 6)
                    }
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Shared Links")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                cards = store.cards
            }
        }
    }

    @MainActor
    private func revoke(_ card: CreatedShareableScoreCard) async {
        guard let configuration else {
            statusMessage = ShareableScoreCardError.configurationUnavailable.localizedDescription
            return
        }
        do {
            try await ShareableScoreCardClient(configuration: configuration).revoke(
                token: card.token,
                managementToken: card.creatorManagementToken
            )
            store.markRevoked(token: card.token)
            cards = store.cards
            statusMessage = "Link revoked."
        } catch {
            statusMessage = (error as? LocalizedError)?.errorDescription ?? ShareableScoreCardError.network.localizedDescription
        }
    }
}
