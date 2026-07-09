import Foundation

#if canImport(AVFoundation)
import AVFoundation
#endif

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AVFoundation)
@MainActor
final class VoiceStylistService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isSpeaking = false
    @Published private(set) var isUsingDefaultQualityVoice = false

    private enum VoiceSelectionRung: String {
        case localePremium
        case localeEnhanced
        case localeDefault
        case fallback
    }

    private let synthesizer = AVSpeechSynthesizer()
    private var cachedVoice: AVSpeechSynthesisVoice?
    private var cachedRung: VoiceSelectionRung = .fallback
    private var interruptionObserver: NSObjectProtocol?
    private var voicesChangedObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?

    private let rateMultiplier: Float = 0.92
    private let pitchMultiplier: Float = 1.0
    private let preUtteranceDelay: TimeInterval = 0.1
    private let postUtteranceDelay: TimeInterval = 0.1

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

        #if canImport(UIKit)
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshVoiceSelection()
            }
        }
        #endif

        if #available(iOS 17.0, macOS 14.0, *) {
            voicesChangedObserver = NotificationCenter.default.addObserver(
                forName: AVSpeechSynthesizer.availableVoicesDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshVoiceSelection()
                }
            }
        }

        refreshVoiceSelection()
    }

    deinit {
        [interruptionObserver, voicesChangedObserver, foregroundObserver].forEach { observer in
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }

    func speak(_ script: String) {
        let cleaned = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        #if canImport(UIKit)
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: cleaned)
            #if DEBUG
            print("[VoiceStylist] VoiceOver running; posted accessibility announcement")
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
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * rateMultiplier
        utterance.pitchMultiplier = pitchMultiplier
        utterance.volume = 1.0
        utterance.preUtteranceDelay = preUtteranceDelay
        utterance.postUtteranceDelay = postUtteranceDelay

        isSpeaking = true
        #if DEBUG
        print("[VoiceStylist] Speaking with voice \(utterance.voice?.identifier ?? "default"); rung=\(cachedRung.rawValue)")
        #endif
        synthesizer.speak(utterance)
    }

    func speak(_ script: VoiceScript) {
        speak(script.text)
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

    private func refreshVoiceSelection() {
        cachedVoice = resolveVoice()
        isUsingDefaultQualityVoice = cachedRung == .localeDefault || cachedRung == .fallback
        #if DEBUG
        print("[VoiceStylist] Selected voice \(cachedVoice?.identifier ?? "default"); quality=\(cachedVoice?.quality.rawValue ?? 0); rung=\(cachedRung.rawValue)")
        #endif
    }

    private func selectedVoice() -> AVSpeechSynthesisVoice? {
        if cachedVoice == nil {
            refreshVoiceSelection()
        }
        return cachedVoice
    }

    private func resolveVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let locale = Locale.current
        let preferredIdentifier = locale.identifier.replacingOccurrences(of: "_", with: "-")
        let preferredLanguage = locale.language.languageCode?.identifier ?? "en"

        if let premium = bestVoice(in: voices, preferredIdentifier: preferredIdentifier, preferredLanguage: preferredLanguage, quality: .premium) {
            cachedRung = .localePremium
            return premium
        }

        if let enhanced = bestVoice(in: voices, preferredIdentifier: preferredIdentifier, preferredLanguage: preferredLanguage, quality: .enhanced) {
            cachedRung = .localeEnhanced
            return enhanced
        }

        if let localeDefault = voices.first(where: { $0.language == preferredIdentifier })
            ?? voices.first(where: { $0.language.hasPrefix(preferredLanguage) }) {
            cachedRung = .localeDefault
            return localeDefault
        }

        cachedRung = .fallback
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    private func bestVoice(
        in voices: [AVSpeechSynthesisVoice],
        preferredIdentifier: String,
        preferredLanguage: String,
        quality: AVSpeechSynthesisVoiceQuality
    ) -> AVSpeechSynthesisVoice? {
        voices
            .filter { voice in
                voice.quality == quality
                    && (voice.language == preferredIdentifier || voice.language.hasPrefix(preferredLanguage))
            }
            .sorted { lhs, rhs in
                if lhs.language == preferredIdentifier, rhs.language != preferredIdentifier { return true }
                if rhs.language == preferredIdentifier, lhs.language != preferredIdentifier { return false }
                return lhs.identifier < rhs.identifier
            }
            .first
    }

    private func activateAudioSessionIfNeeded() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            #if DEBUG
            print("[VoiceStylist] Audio session activation failed: \(error.localizedDescription)")
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
            print("[VoiceStylist] Audio session deactivation failed: \(error.localizedDescription)")
            #endif
        }
        #endif
    }
}
#else
@MainActor
final class VoiceStylistService: ObservableObject {
    @Published private(set) var isSpeaking = false
    @Published private(set) var isUsingDefaultQualityVoice = false

    func speak(_ script: String) {}
    func speak(_ script: VoiceScript) {}
    func stop() {}
    func previewVoice() {}
}
#endif
