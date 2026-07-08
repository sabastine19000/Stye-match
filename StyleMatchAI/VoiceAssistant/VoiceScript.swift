import Foundation

struct VoiceAssistantSettings {
    static let enabledKey = "voiceAssistantEnabled"
    static let selectedVoiceIdentifierKey = "voiceAssistantVoiceIdentifier"
    static let speechRateKey = "voiceAssistantSpeechRate"

    static let defaultSpeechRate = 0.95
}

struct VoiceScript: Equatable, Identifiable {
    enum Kind: String {
        case scanStarted
        case scanResult
        case scanFailed
        case profileSaved
        case appGuide
        case preview
    }

    let id: String
    let kind: Kind
    let text: String

    init(id: String = UUID().uuidString, kind: Kind, text: String) {
        self.id = id
        self.kind = kind
        self.text = VoiceScriptBuilder.trimmedScript(text)
    }
}

