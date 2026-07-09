import Foundation

struct SpokenScriptBuilder {
    static let maximumSpokenCharacters = 450
    static let maximumSentences = 4

    private static let intros = [
        "Here's my take on this look.",
        "Alright, let's talk about this outfit.",
        "Okay, here's what stands out.",
        "Here's the quick stylist read."
    ]

    private static let outros = [
        "If you want, I can help you pick the next upgrade.",
        "Next, focus on one clean improvement.",
        "A small styling tweak can make this feel more finished.",
        "That's the key takeaway for this scan."
    ]

    static func scanScript(
        explanation: String,
        scanIdentifier: String,
        includeOutro: Bool = true
    ) -> String {
        let body = speechFriendlyText(from: explanation)
        guard !body.isEmpty else {
            return template(from: intros, seed: scanIdentifier)
        }

        var pieces = [
            template(from: intros, seed: scanIdentifier),
            body
        ]

        if includeOutro {
            pieces.append(template(from: outros, seed: "\(scanIdentifier)-outro"))
        }

        return trimToSentenceBoundary(pieces.joined(separator: " "))
    }

    static func speechFriendlyText(from rawText: String) -> String {
        let withoutEmoji = removeEmojiAndSymbols(from: rawText)
        let lines = withoutEmoji
            .components(separatedBy: .newlines)
            .map { stripListMarkers(from: stripMarkdown(from: $0)) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let joined = lines
            .map { ensureSentence($0) }
            .joined(separator: " ")

        let scoreReadable = convertScores(joined)
        let collapsed = scoreReadable
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return trimToSentenceBoundary(collapsed)
    }

    static func template(from templates: [String], seed: String) -> String {
        guard !templates.isEmpty else { return "" }
        let index = abs(stableHash(seed)) % templates.count
        return templates[index]
    }

    static func stableHash(_ text: String) -> Int {
        text.unicodeScalars.reduce(5381) { partial, scalar in
            ((partial << 5) &+ partial) &+ Int(scalar.value)
        }
    }

    private static func stripMarkdown(from line: String) -> String {
        line
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: ">", with: "")
    }

    private static func stripListMarkers(from line: String) -> String {
        line.replacingOccurrences(
            of: #"^\s*(?:[-•]+|\d+[.)])\s*"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func convertScores(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"(?<!\d)(\d{1,3})\s*/\s*100(?!\d)"#,
            with: "$1 out of 100",
            options: .regularExpression
        )
    }

    private static func removeEmojiAndSymbols(from text: String) -> String {
        String(text.unicodeScalars.filter { scalar in
            switch scalar.properties.generalCategory {
            case .otherSymbol, .mathSymbol, .currencySymbol, .modifierSymbol:
                return false
            default:
                return true
            }
        })
    }

    private static func ensureSentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let last = trimmed.last, ".!?".contains(last) {
            return trimmed
        }
        return "\(trimmed)."
    }

    private static func trimToSentenceBoundary(_ text: String) -> String {
        let sentences = splitSentences(text)
        var result: [String] = []
        var count = 0

        for sentence in sentences {
            let nextCount = count + sentence.count + (result.isEmpty ? 0 : 1)
            if result.count >= maximumSentences || nextCount > maximumSpokenCharacters {
                break
            }
            result.append(sentence)
            count = nextCount
        }

        if !result.isEmpty {
            return result.joined(separator: " ")
        }

        let prefix = String(text.prefix(maximumSpokenCharacters))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ensureSentence(prefix)
    }

    private static func splitSentences(_ text: String) -> [String] {
        let pattern = #"[^.!?]+[.!?]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [ensureSentence(text)]
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        let sentences = matches.compactMap { match -> String? in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            return String(text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if sentences.isEmpty {
            return [ensureSentence(text)]
        }

        return sentences
    }
}
