import CryptoKit
import Foundation

enum ScanImageIdentity {
    static let fingerprintVersion = "outfit-v4"

    static func sha256Hex<S: Sequence>(bytes: S) -> String where S.Element == UInt8 {
        SHA256.hash(data: Data(bytes)).map { String(format: "%02x", $0) }.joined()
    }

    static func isExactMatch(
        storedFingerprint: String?,
        storedImageDigest: String?,
        currentFingerprint: String?,
        currentImageDigest: String?
    ) -> Bool {
        guard let storedFingerprint = cleanIdentity(storedFingerprint),
              let storedImageDigest = cleanIdentity(storedImageDigest),
              let currentFingerprint = cleanIdentity(currentFingerprint),
              let currentImageDigest = cleanIdentity(currentImageDigest),
              storedFingerprint.hasPrefix("\(fingerprintVersion)|"),
              currentFingerprint.hasPrefix("\(fingerprintVersion)|") else {
            return false
        }
        return storedFingerprint == currentFingerprint && storedImageDigest == currentImageDigest
    }

    static func debugDigestPrefix(_ digest: String?, length: Int = 16) -> String {
        guard let digest = cleanIdentity(digest) else { return "none" }
        return String(digest.prefix(max(12, min(16, length))))
    }

    private static func cleanIdentity(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}

struct OutfitRecallFact: Equatable {
    let text: String
    let memoryID: UUID
}

struct OutfitRecallScanContext {
    let detectedGarments: [String]
    let colors: [String]
    let detectedStyle: String
    let garmentRecords: [GarmentRecord]
    let outfitFingerprint: String?
    let imageDigest: String?

    init(
        detectedGarments: [String],
        colors: [String],
        detectedStyle: String,
        garmentRecords: [GarmentRecord] = [],
        outfitFingerprint: String? = nil,
        imageDigest: String? = nil
    ) {
        self.detectedGarments = detectedGarments
        self.colors = colors
        self.detectedStyle = detectedStyle
        self.garmentRecords = garmentRecords
        self.outfitFingerprint = outfitFingerprint
        self.imageDigest = imageDigest
    }
}

enum OutfitRecallService {
    static func recallFact(
        for context: OutfitRecallScanContext,
        memories: [OutfitMemory],
        now: Date = Date()
    ) -> OutfitRecallFact? {
        bestMatch(for: context, memories: memories).map { memory in
            OutfitRecallFact(
                text: recallText(for: memory, now: now),
                memoryID: memory.id
            )
        }
    }

    static func recallFact(
        for context: OutfitRecallScanContext,
        store: OutfitMemoryStore,
        now: Date = Date(),
        incrementCounters: Bool = false
    ) -> OutfitRecallFact? {
        guard let match = bestMatch(for: context, memories: store.memories) else {
            return nil
        }

        if incrementCounters, !context.garmentRecords.isEmpty {
            _ = store.mergeGarmentRecords(context.garmentRecords, into: match.id)
        }

        return OutfitRecallFact(
            text: recallText(for: match, now: now),
            memoryID: match.id
        )
    }

    static func context(from analysis: OutfitAnalysisResult, scanID: String = UUID().uuidString, scanDate: Date = Date()) -> OutfitRecallScanContext {
        OutfitRecallScanContext(
            detectedGarments: analysis.safeDetectedClothingItems,
            colors: analysis.colorPalette,
            detectedStyle: analysis.styleBalance,
            garmentRecords: ItemFingerprintMatcher.records(from: analysis, scanID: scanID, scanDate: scanDate)
        )
    }

    static func relativeDateText(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let startNow = calendar.startOfDay(for: now)
        let startDate = calendar.startOfDay(for: date)
        let dayDelta = calendar.dateComponents([.day], from: startDate, to: startNow).day ?? 0

        if dayDelta == 0 {
            return "today"
        }
        if dayDelta == 1 {
            return "yesterday"
        }
        if (2...6).contains(dayDelta) {
            return "last \(weekdayName(for: date))"
        }
        if (7...30).contains(dayDelta) {
            let weeks = max(1, Int(round(Double(dayDelta) / 7.0)))
            return weeks == 1 ? "one week ago" : "\(numberWord(weeks)) weeks ago"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private static func bestMatch(for context: OutfitRecallScanContext, memories: [OutfitMemory]) -> OutfitMemory? {
        guard let fingerprint = cleanOptional(context.outfitFingerprint),
              let imageDigest = cleanOptional(context.imageDigest) else { return nil }
        return memories
            .filter {
                ScanImageIdentity.isExactMatch(
                    storedFingerprint: $0.outfitFingerprint,
                    storedImageDigest: $0.imageDigest,
                    currentFingerprint: fingerprint,
                    currentImageDigest: imageDigest
                )
            }
            .map { memory in
                (memory: memory, score: matchScore(context: context, memory: memory))
            }
            .filter { $0.score > 0 }
            .sorted { first, second in
                if first.score == second.score {
                    return first.memory.scanDate > second.memory.scanDate
                }
                return first.score > second.score
            }
            .first?
            .memory
    }

    private static func matchScore(context: OutfitRecallScanContext, memory: OutfitMemory) -> Int {
        let currentFingerprints = Set(context.garmentRecords.map(\.itemFingerprint))
        let memoryFingerprints = Set(memory.garmentRecords.map(\.itemFingerprint))
        let fingerprintMatches = currentFingerprints.isEmpty ? 0 : currentFingerprints.intersection(memoryFingerprints).count

        let styleMatch = clean(memory.detectedStyle).caseInsensitiveCompare(clean(context.detectedStyle)) == .orderedSame ? 2 : 0
        return fingerprintMatches * 10 + styleMatch
    }

    private static func recallText(for memory: OutfitMemory, now: Date) -> String {
        let items = itemPhrase(garments: memory.detectedGarments, colors: memory.colors)
        let dateText = relativeDateText(for: memory.scanDate, now: now)
        return "You wore \(items) \(dateText) (score: \(memory.styleScore))."
    }

    private static func itemPhrase(garments: [String], colors: [String]) -> String {
        let cleanedGarments = GarmentLabelMapper.sanitizedTerms(from: garments).map(clean).filter { !$0.isEmpty }
        let cleanedColors = colors.map(clean).filter { !$0.isEmpty }
        let paired = cleanedGarments.enumerated().map { index, garment in
            if index < cleanedColors.count {
                return "\(cleanedColors[index]) \(garment)"
            }
            return garment
        }

        if paired.isEmpty {
            return "this outfit"
        }
        if paired.count == 1 {
            return paired[0]
        }
        if paired.count == 2 {
            return "\(paired[0]) and \(paired[1])"
        }

        return paired.dropLast().joined(separator: ", ") + ", and \(paired.last ?? "")"
    }

    private static func weekdayName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    private static func numberWord(_ value: Int) -> String {
        switch value {
        case 2: return "two"
        case 3: return "three"
        case 4: return "four"
        default: return "\(value)"
        }
    }

    private static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanOptional(_ value: String?) -> String? {
        let cleaned = clean(value ?? "")
        return cleaned.isEmpty ? nil : cleaned
    }
}
