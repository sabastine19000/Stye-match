import Foundation

#if canImport(AVFoundation)
import AVFoundation
#endif

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AVFoundation)
@MainActor
final class VoiceAssistantService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()
    private var interruptionObserver: NSObjectProtocol?

    override init() {
        super.init()
        synthesizer.delegate = self
        #if os(iOS)
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: typeValue) == .began else {
                return
            }
            Task { @MainActor in
                self?.stop()
            }
        }
        #endif
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
    }

    func speak(_ script: VoiceScript) {
        let cleaned = script.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        #if canImport(UIKit)
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: cleaned)
            #if DEBUG
            print("[VoiceAssistant] VoiceOver running; posted accessibility announcement for script \(script.id)")
            #endif
            return
        }
        #endif

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        activateAudioSessionIfNeeded()

        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.voice = selectedVoice()
        utterance.rate = Float(UserDefaults.standard.double(forKey: VoiceAssistantSettings.speechRateKey).nonZeroOrDefault(VoiceAssistantSettings.defaultSpeechRate)) * AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        utterance.postUtteranceDelay = 0.1

        isSpeaking = true
        #if DEBUG
        print("[VoiceAssistant] Speaking script \(script.id) with voice \(utterance.voice?.identifier ?? "default")")
        #endif
        synthesizer.speak(utterance)
    }

    func stop() {
        guard synthesizer.isSpeaking else {
            isSpeaking = false
            deactivateAudioSession()
            return
        }
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        deactivateAudioSession()
    }

    func previewVoice() {
        speak(VoiceScriptBuilder.preview())
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
            deactivateAudioSession()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
            deactivateAudioSession()
        }
    }

    private func selectedVoice() -> AVSpeechSynthesisVoice? {
        let storedIdentifier = UserDefaults.standard.string(forKey: VoiceAssistantSettings.selectedVoiceIdentifierKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let storedIdentifier,
           !storedIdentifier.isEmpty,
           let storedVoice = AVSpeechSynthesisVoice(identifier: storedIdentifier) {
            return storedVoice
        }

        let englishVoices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.lowercased().hasPrefix("en") }

        let selected = englishVoices.sorted { lhs, rhs in
            if lhs.quality.rank != rhs.quality.rank {
                return lhs.quality.rank > rhs.quality.rank
            }
            return lhs.identifier < rhs.identifier
        }.first ?? AVSpeechSynthesisVoice(language: "en-US")

        #if DEBUG
        print("[VoiceAssistant] Selected voice \(selected?.identifier ?? "default") quality \(selected?.quality.rawValue ?? 0)")
        #endif
        return selected
    }

    private func activateAudioSessionIfNeeded() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            #if DEBUG
            print("[VoiceAssistant] Audio session activation failed: \(error.localizedDescription)")
            #endif
        }
        #endif
    }

    private func deactivateAudioSession() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            #if DEBUG
            print("[VoiceAssistant] Audio session deactivation failed: \(error.localizedDescription)")
            #endif
        }
        #endif
    }
}

private extension AVSpeechSynthesisVoiceQuality {
    var rank: Int {
        switch self {
        case .premium: return 3
        case .enhanced: return 2
        default: return 1
        }
    }
}
#endif

private extension Double {
    func nonZeroOrDefault(_ fallback: Double) -> Double {
        self > 0 ? self : fallback
    }
}
