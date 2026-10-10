import Foundation

/// The only local bridge permitted to prepare a Scan, Score, or Outfit for a
/// private Style Friends DM. It never hands a backing record, CloudKit name,
/// image asset ID, or other local identifier to the chat transport.
@MainActor
final class StyleFriendsDMShareEligibilityAuthority {
    enum Kind: CaseIterable { case scan, score, outfit }

    enum AvailabilityError: Error, Equatable {
        case historyUnavailable, noSavedScans, noValidScores, photosUnavailable
        var message: String {
            switch self {
            case .historyUnavailable:
                "Your saved scans could not be loaded for sharing. Open Scan history and try again. Your saved data has not been changed."
            case .noSavedScans:
                "No saved scans are available on this device yet."
            case .noValidScores:
                "Your saved scans are still stored, but their scores could not be verified for sharing."
            case .photosUnavailable:
                "Your saved scans are still stored, but their photos are unavailable for sharing. Choose Saved Score to share the saved score without a photo."
            }
        }
    }

    struct Selection: Identifiable, Equatable {
        let id: UUID
        let kind: Kind
        let title: String
        let occasion: String?
        let score: Int?
        let summary: String
        let imagePreview: Data?
    }

    private struct PrivateCandidate {
        let selection: Selection
        let snapshot: StyleFriendsDMAttachmentSnapshot
    }

    private let scans: SavedScanPersistenceAuthority
    private var candidates: [UUID: PrivateCandidate] = [:]

    init(scans: SavedScanPersistenceAuthority = .init()) {
        self.scans = scans
    }

    /// Rebuilds ephemeral choices from valid canonical saved scans. A UUID is
    /// intentionally local-only and has no relation to a persisted record ID.
    func choices(for kind: Kind) throws -> [Selection] {
        candidates = [:]
        let result: SavedScanShareReadResult
        do { result = try scans.readSavedScanShareSources() }
        catch { throw AvailabilityError.historyUnavailable }
        guard result.savedRecordCount > 0 else { throw AvailabilityError.noSavedScans }
        guard !result.sources.isEmpty else { throw AvailabilityError.noValidScores }
        let selections = result.sources.compactMap { record -> Selection? in
            guard let snapshot = snapshot(for: record, kind: kind) else { return nil }
            let image = record.imagePreview
            // Scan and Outfit shares require a locally readable, owned preview;
            // Score shares may intentionally be card-only.
            guard kind == .score || image != nil else { return nil }
            let token = UUID()
            let selection = Selection(
                id: token,
                kind: kind,
                title: snapshot.title,
                occasion: snapshot.occasion,
                score: snapshot.score,
                summary: snapshot.summary,
                imagePreview: image
            )
            candidates[token] = PrivateCandidate(selection: selection, snapshot: snapshot)
            return selection
        }
        guard !selections.isEmpty else { throw AvailabilityError.photosUnavailable }
        return selections
    }

    /// Consumes an ephemeral selection. The token itself is never serialised
    /// and source changes cannot mutate the previously created snapshot.
    func consumeSnapshot(for token: UUID, kind: Kind) -> StyleFriendsDMAttachmentSnapshot? {
        guard let candidate = candidates.removeValue(forKey: token), candidate.selection.kind == kind else { return nil }
        return candidate.snapshot
    }

    private func snapshot(for record: SavedScanShareSource, kind: Kind) -> StyleFriendsDMAttachmentSnapshot? {
        let title = sanitized(record.title) ?? defaultTitle(for: kind)
        let occasion = sanitized(record.occasion)
        let score = record.authoritativeScore
        let summary: String
        switch kind {
        case .scan: summary = "A saved StyleMatch scan selected by its owner."
        case .score: summary = "A saved StyleMatch score selected by its owner."
        case .outfit: summary = "A saved StyleMatch outfit selected by its owner."
        }
        return .init(title: title, occasion: occasion, score: score, summary: summary)
    }

    private func defaultTitle(for kind: Kind) -> String {
        switch kind { case .scan: "Shared scan"; case .score: "Shared score"; case .outfit: "Shared outfit" }
    }

    private func sanitized(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= 80,
              !cleaned.localizedCaseInsensitiveContains("cloudkit"),
              !cleaned.localizedCaseInsensitiveContains("record id") else { return nil }
        return cleaned
    }
}

/// A separately-scoped bridge for the currently displayed Scan result.  Unlike
/// `StyleFriendsDMShareEligibilityAuthority`, this has no Saved Scan authority
/// and never writes one.  Callers hand it already-rendered, user-visible values
/// and it produces only the immutable DM snapshot accepted by the Worker.
enum StyleFriendsDMTransientShareAuthority {
    struct Input: Equatable {
        let title: String
        let occasion: String?
        let score: Int?
        let summary: String
        let imagePreview: Data?
        let classification: String?
    }

    static func snapshot(from input: Input) -> StyleFriendsDMAttachmentSnapshot? {
        StyleFriendsDMAttachmentSnapshot(
            title: input.title,
            occasion: input.occasion,
            score: input.score,
            summary: input.summary,
            classification: input.classification
        )
    }

    /// Creates the local-only immutable draft used by the established delivery
    /// lifecycle.  No saved-scan record or persistence collaborator is read
    /// or written; the supplied client reference remains stable for a retry.
    static func preparedShare(
        from input: Input,
        clientShareReference: String = UUID().uuidString
    ) -> StyleFriendsDMPreparedShare? {
        guard let snapshot = snapshot(from: input),
              let imagePreview = input.imagePreview,
              !imagePreview.isEmpty else {
            return nil
        }
        return StyleFriendsDMPreparedShare(
            kind: .scanSnapshot,
            snapshot: snapshot,
            imagePreview: imagePreview,
            clientShareReference: clientShareReference
        )
    }
}
