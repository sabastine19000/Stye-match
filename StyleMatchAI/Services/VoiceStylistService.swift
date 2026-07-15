import Foundation
import OSLog

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
    @Published private(set) var playbackErrorMessage: String?

    private enum VoiceSelectionRung: String, Sendable {
        case localePremium
        case localeEnhanced
        case localeDefault
        case fallback
    }

    private struct VoiceSelectionDescriptor: Sendable {
        let identifier: String?
        let language: String?
        let rung: VoiceSelectionRung
    }

    #if os(iOS)
    private struct AudioSessionActivationResult: Sendable {
        let didActivate: Bool
        let outputs: String
        let category: String
        let mode: String
        let errorDomain: String?
        let errorCode: Int?
    }
    #endif

    nonisolated private static let logger = Logger(subsystem: "com.sabastine.stylematchai", category: "VoicePlayback")
    private var synthesizer: AVSpeechSynthesizer?
    private var cachedVoice: AVSpeechSynthesisVoice?
    private var cachedRung: VoiceSelectionRung = .fallback
    private var speechStartupTask: Task<Void, Never>?
    private var speechWatchdogTask: Task<Void, Never>?
    private var activeSpeechRequestID: UUID?
    private var isPreparingSpeech = false
    private var interruptionObserver: NSObjectProtocol?
    private var voicesChangedObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var mediaServicesResetObserver: NSObjectProtocol?

    private let rateMultiplier: Float = 0.92
    private let pitchMultiplier: Float = 1.0
    private let preUtteranceDelay: TimeInterval = 0.1
    private let postUtteranceDelay: TimeInterval = 0.1
    private let speechStartupTimeoutNanoseconds: UInt64 = 4_000_000_000

    override init() {
        super.init()
    }

    private func preparePlaybackResourcesIfNeeded() {
        if synthesizer == nil {
            let newSynthesizer = AVSpeechSynthesizer()
            newSynthesizer.delegate = self
            synthesizer = newSynthesizer
            Self.logger.notice("stage=voice_resources_ready")
        }

        registerPlaybackObserversIfNeeded()
    }

    private func registerPlaybackObserversIfNeeded() {
        guard interruptionObserver == nil else { return }

        #if os(iOS)
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
                return
            }
            Task { @MainActor in
                guard let self else { return }
                if type == .began {
                    Self.logger.notice("stage=interruption_began")
                    self.stop(withError: "Voice playback was interrupted. Tap Listen to try again.")
                } else {
                    Self.logger.notice("stage=interruption_ended")
                }
            }
        }

        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            let reason = rawReason.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            Task { @MainActor in
                guard let self else { return }
                Self.logger.notice("stage=route_changed reason=\(reason?.rawValue ?? 0, privacy: .public)")
                if reason == .oldDeviceUnavailable, self.synthesizer?.isSpeaking == true {
                    self.stop(withError: "Your audio output changed. Tap Listen to continue on the current speaker.")
                }
            }
        }

        mediaServicesResetObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                Self.logger.error("stage=media_services_reset")
                self.isSpeaking = false
                self.isPreparingSpeech = false
                self.activeSpeechRequestID = nil
                self.speechStartupTask?.cancel()
                self.speechWatchdogTask?.cancel()
                self.playbackErrorMessage = "Audio services restarted. Tap Listen to try again."
                self.synthesizer = nil
                self.cachedVoice = nil
                self.cachedRung = .fallback
                self.isUsingDefaultQualityVoice = false
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
                guard let self, self.synthesizer != nil else { return }
                self.resolveAndCacheVoice(reason: "foreground", startedAt: Self.currentTimestamp(), textLength: nil)
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
                    guard let self, self.synthesizer != nil else { return }
                    self.resolveAndCacheVoice(reason: "voices_changed", startedAt: Self.currentTimestamp(), textLength: nil)
                }
            }
        }
    }

    deinit {
        [interruptionObserver, voicesChangedObserver, foregroundObserver, routeChangeObserver, mediaServicesResetObserver].forEach { observer in
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }

    func speak(_ script: String) {
        let cleaned = script.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestID = UUID()
        let startedAt = Self.currentTimestamp()
        guard !cleaned.isEmpty else {
            playbackErrorMessage = "There is no voice summary available for this result."
            Self.logStage("empty_script", startedAt: startedAt, textLength: cleaned.count)
            return
        }

        playbackErrorMessage = nil
        Self.logStage("requested", startedAt: startedAt, textLength: cleaned.count, extra: "request_id=\(requestID.uuidString)")

        #if canImport(UIKit)
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: cleaned)
            Self.logStage("voiceover_announcement", startedAt: startedAt, textLength: cleaned.count, extra: "request_id=\(requestID.uuidString)")
            return
        }
        #endif

        guard !isPreparingSpeech else {
            Self.logStage("duplicate_start_ignored", startedAt: startedAt, textLength: cleaned.count, extra: "request_id=\(requestID.uuidString)")
            return
        }

        preparePlaybackResourcesIfNeeded()

        if synthesizer?.isSpeaking == true {
            synthesizer?.stopSpeaking(at: .immediate)
        }

        isPreparingSpeech = true
        activeSpeechRequestID = requestID
        startSpeechStartupWatchdog(requestID: requestID, startedAt: startedAt, textLength: cleaned.count)

        speechStartupTask?.cancel()
        speechStartupTask = Task { [weak self] in
            guard let self else { return }
            await Task.yield()
            self.startSpeech(
                cleaned,
                requestID: requestID,
                startedAt: startedAt
            )
        }
    }

    private func startSpeech(_ cleaned: String, requestID: UUID, startedAt: TimeInterval) {
        guard activeSpeechRequestID == requestID else { return }
        Self.logStage("speech_startup_begin", startedAt: startedAt, textLength: cleaned.count, extra: "request_id=\(requestID.uuidString)")

        let voice = selectedVoice(startedAt: startedAt, textLength: cleaned.count)
        guard activeSpeechRequestID == requestID, !Task.isCancelled else { return }

        let voiceIdentifier = voice?.identifier
        let voiceLanguage = voice?.language

        #if os(iOS)
        let activation = Self.activateAudioSessionForPlayback(
            startedAt: startedAt,
            textLength: cleaned.count,
            voiceIdentifier: voiceIdentifier,
            voiceLanguage: voiceLanguage
        )
        guard activeSpeechRequestID == requestID, !Task.isCancelled else { return }
        guard activation.didActivate else {
            failSpeechStartup(
                requestID: requestID,
                message: "Voice playback couldn’t start. Check your volume and audio output, then try again.",
                stage: "session_activation_failed",
                startedAt: startedAt,
                textLength: cleaned.count,
                extra: "domain=\(activation.errorDomain ?? "unknown") code=\(activation.errorCode ?? -1)"
            )
            return
        }
        Self.logStage(
            "session_active",
            startedAt: startedAt,
            textLength: cleaned.count,
            voiceIdentifier: voiceIdentifier,
            voiceLanguage: voiceLanguage,
            extra: "outputs=\(activation.outputs) category=\(activation.category) mode=\(activation.mode)"
        )
        #endif

        Self.logStage(
            "utterance_create_begin",
            startedAt: startedAt,
            textLength: cleaned.count,
            voiceIdentifier: voiceIdentifier,
            voiceLanguage: voiceLanguage
        )
        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * rateMultiplier
        utterance.pitchMultiplier = pitchMultiplier
        utterance.volume = 1.0
        utterance.preUtteranceDelay = preUtteranceDelay
        utterance.postUtteranceDelay = postUtteranceDelay
        Self.logStage(
            "utterance_create_done",
            startedAt: startedAt,
            textLength: cleaned.count,
            voiceIdentifier: voiceIdentifier,
            voiceLanguage: voiceLanguage
        )

        Self.logStage(
            "queued",
            startedAt: startedAt,
            textLength: cleaned.count,
            voiceIdentifier: voiceIdentifier,
            voiceLanguage: voiceLanguage,
            extra: "voice_quality=\(cachedRung.rawValue)"
        )
        guard let synthesizer else {
            failSpeechStartup(
                requestID: requestID,
                message: "Voice playback couldn’t start. Tap Listen to try again.",
                stage: "synthesizer_unavailable",
                startedAt: startedAt,
                textLength: cleaned.count
            )
            return
        }
        synthesizer.speak(utterance)
        Self.logStage(
            "speak_returned",
            startedAt: startedAt,
            textLength: cleaned.count,
            voiceIdentifier: voiceIdentifier,
            voiceLanguage: voiceLanguage
        )
    }

    func speak(_ script: VoiceScript) {
        speak(script.text)
    }

    func stop() {
        speechStartupTask?.cancel()
        speechWatchdogTask?.cancel()
        activeSpeechRequestID = nil
        isPreparingSpeech = false
        guard synthesizer?.isSpeaking == true else {
            isSpeaking = false
            deactivateAudioSession()
            return
        }
        synthesizer?.stopSpeaking(at: .immediate)
        isSpeaking = false
        deactivateAudioSession()
    }

    private func stop(withError message: String) {
        speechStartupTask?.cancel()
        speechWatchdogTask?.cancel()
        activeSpeechRequestID = nil
        isPreparingSpeech = false
        if synthesizer?.isSpeaking == true {
            synthesizer?.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        playbackErrorMessage = message
        deactivateAudioSession()
    }

    func previewVoice() {
        speak(VoiceScriptBuilder.preview())
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let textLength = utterance.speechString.count
        let voiceIdentifier = utterance.voice?.identifier
        let voiceLanguage = utterance.voice?.language
        Task { @MainActor in
            speechWatchdogTask?.cancel()
            playbackErrorMessage = nil
            isPreparingSpeech = false
            isSpeaking = true
            Self.logStage("started", startedAt: nil, textLength: textLength, voiceIdentifier: voiceIdentifier, voiceLanguage: voiceLanguage)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let textLength = utterance.speechString.count
        let voiceIdentifier = utterance.voice?.identifier
        let voiceLanguage = utterance.voice?.language
        Task { @MainActor in
            speechStartupTask?.cancel()
            speechWatchdogTask?.cancel()
            activeSpeechRequestID = nil
            isPreparingSpeech = false
            isSpeaking = false
            Self.logStage("finished", startedAt: nil, textLength: textLength, voiceIdentifier: voiceIdentifier, voiceLanguage: voiceLanguage)
            deactivateAudioSession()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let textLength = utterance.speechString.count
        let voiceIdentifier = utterance.voice?.identifier
        let voiceLanguage = utterance.voice?.language
        Task { @MainActor in
            speechStartupTask?.cancel()
            speechWatchdogTask?.cancel()
            activeSpeechRequestID = nil
            isPreparingSpeech = false
            isSpeaking = false
            Self.logStage("cancelled", startedAt: nil, textLength: textLength, voiceIdentifier: voiceIdentifier, voiceLanguage: voiceLanguage)
            deactivateAudioSession()
        }
    }

    private func selectedVoice(startedAt: TimeInterval, textLength: Int) -> AVSpeechSynthesisVoice? {
        if cachedVoice == nil {
            resolveAndCacheVoice(reason: "speech_request", startedAt: startedAt, textLength: textLength)
        }
        return cachedVoice
    }

    private func resolveAndCacheVoice(reason: String, startedAt: TimeInterval, textLength: Int?) {
        Self.logStage("voice_selection_begin", startedAt: startedAt, textLength: textLength, extra: "reason=\(reason)")
        Self.logStage("voice_enumeration_begin", startedAt: startedAt, textLength: textLength)
        let descriptor = Self.resolveVoiceDescriptorSynchronously()
        Self.logStage(
            "voice_enumeration_done",
            startedAt: startedAt,
            textLength: textLength,
            voiceIdentifier: descriptor.identifier,
            voiceLanguage: descriptor.language,
            extra: "quality=\(descriptor.rung.rawValue)"
        )
        cachedRung = descriptor.rung
        if let identifier = descriptor.identifier {
            cachedVoice = AVSpeechSynthesisVoice(identifier: identifier)
        } else if let language = descriptor.language {
            cachedVoice = AVSpeechSynthesisVoice(language: language)
        } else {
            cachedVoice = nil
        }
        isUsingDefaultQualityVoice = cachedRung == .localeDefault || cachedRung == .fallback
        Self.logStage(
            "voice_selected",
            startedAt: startedAt,
            textLength: textLength,
            voiceIdentifier: cachedVoice?.identifier ?? descriptor.identifier,
            voiceLanguage: cachedVoice?.language ?? descriptor.language,
            extra: "quality=\(cachedRung.rawValue)"
        )
    }

    private static func resolveVoiceDescriptorSynchronously() -> VoiceSelectionDescriptor {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let locale = Locale.current
        let preferredIdentifier = locale.identifier.replacingOccurrences(of: "_", with: "-")
        let preferredLanguage = locale.language.languageCode?.identifier ?? "en"

        if let premium = bestVoice(in: voices, preferredIdentifier: preferredIdentifier, preferredLanguage: preferredLanguage, quality: .premium) {
            return VoiceSelectionDescriptor(identifier: premium.identifier, language: premium.language, rung: .localePremium)
        }

        if let enhanced = bestVoice(in: voices, preferredIdentifier: preferredIdentifier, preferredLanguage: preferredLanguage, quality: .enhanced) {
            return VoiceSelectionDescriptor(identifier: enhanced.identifier, language: enhanced.language, rung: .localeEnhanced)
        }

        if let localeDefault = voices.first(where: { $0.language == preferredIdentifier })
            ?? voices.first(where: { $0.language.hasPrefix(preferredLanguage) }) {
            return VoiceSelectionDescriptor(identifier: localeDefault.identifier, language: localeDefault.language, rung: .localeDefault)
        }

        return VoiceSelectionDescriptor(identifier: nil, language: "en-US", rung: .fallback)
    }

    private static func bestVoice(
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

    private func startSpeechStartupWatchdog(requestID: UUID, startedAt: TimeInterval, textLength: Int) {
        speechWatchdogTask?.cancel()
        speechWatchdogTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.speechStartupTimeoutNanoseconds ?? 4_000_000_000)
            } catch {
                return
            }
            self?.handleSpeechStartupTimeout(requestID: requestID, startedAt: startedAt, textLength: textLength)
        }
    }

    private func handleSpeechStartupTimeout(requestID: UUID, startedAt: TimeInterval, textLength: Int) {
        guard activeSpeechRequestID == requestID, isPreparingSpeech, !isSpeaking else { return }
        failSpeechStartup(
            requestID: requestID,
            message: "Voice playback took too long to start. Tap Listen to try again.",
            stage: "startup_timeout",
            startedAt: startedAt,
            textLength: textLength
        )
    }

    private func failSpeechStartup(
        requestID: UUID,
        message: String,
        stage: String,
        startedAt: TimeInterval,
        textLength: Int,
        extra: String = ""
    ) {
        guard activeSpeechRequestID == requestID else { return }
        speechStartupTask?.cancel()
        speechWatchdogTask?.cancel()
        activeSpeechRequestID = nil
        isPreparingSpeech = false
        isSpeaking = false
        playbackErrorMessage = message
        Self.logStage(stage, startedAt: startedAt, textLength: textLength, extra: extra)
        deactivateAudioSession()
    }

    #if os(iOS)
    private static func activateAudioSessionForPlayback(
        startedAt: TimeInterval,
        textLength: Int,
        voiceIdentifier: String?,
        voiceLanguage: String?
    ) -> AudioSessionActivationResult {
        let session = AVAudioSession.sharedInstance()
            Self.logStage(
                "session_category_begin",
                startedAt: startedAt,
                textLength: textLength,
                voiceIdentifier: voiceIdentifier,
                voiceLanguage: voiceLanguage,
                extra: "category=\(session.category.rawValue) mode=\(session.mode.rawValue)"
            )
        do {
                try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
                Self.logStage(
                    "session_category_done",
                    startedAt: startedAt,
                    textLength: textLength,
                    voiceIdentifier: voiceIdentifier,
                    voiceLanguage: voiceLanguage,
                    extra: "category=\(session.category.rawValue) mode=\(session.mode.rawValue)"
                )
                Self.logStage(
                    "session_active_begin",
                    startedAt: startedAt,
                    textLength: textLength,
                    voiceIdentifier: voiceIdentifier,
                    voiceLanguage: voiceLanguage,
                    extra: "category=\(session.category.rawValue) mode=\(session.mode.rawValue)"
                )
                try session.setActive(true)
                Self.logStage(
                    "session_active_done",
                    startedAt: startedAt,
                    textLength: textLength,
                    voiceIdentifier: voiceIdentifier,
                    voiceLanguage: voiceLanguage,
                    extra: "category=\(session.category.rawValue) mode=\(session.mode.rawValue)"
                )
                let outputs = session.currentRoute.outputs.map(\.portType.rawValue).joined(separator: ",")
            return AudioSessionActivationResult(
                    didActivate: true,
                    outputs: outputs,
                    category: session.category.rawValue,
                    mode: session.mode.rawValue,
                    errorDomain: nil,
                    errorCode: nil
                )
        } catch {
            let nsError = error as NSError
            return AudioSessionActivationResult(
                    didActivate: false,
                    outputs: session.currentRoute.outputs.map(\.portType.rawValue).joined(separator: ","),
                    category: session.category.rawValue,
                    mode: session.mode.rawValue,
                    errorDomain: nsError.domain,
                    errorCode: nsError.code
                )
        }
    }
    #endif

    nonisolated private static func currentTimestamp() -> TimeInterval {
        Date().timeIntervalSince1970
    }

    nonisolated private static func logStage(
        _ stage: String,
        startedAt: TimeInterval?,
        textLength: Int?,
        voiceIdentifier: String? = nil,
        voiceLanguage: String? = nil,
        extra: String = ""
    ) {
        let now = currentTimestamp()
        let elapsed = startedAt.map { Int((now - $0) * 1_000) } ?? 0
        let mainThread = Thread.isMainThread
        let thread = mainThread ? "main" : "background"
        let length = textLength.map(String.init) ?? "unknown"
        let voiceID = voiceIdentifier ?? "none"
        let language = voiceLanguage ?? "none"
        let suffix = extra.isEmpty ? "" : " \(extra)"
        logger.notice("stage=\(stage, privacy: .public) timestamp=\(now, privacy: .public) elapsed_ms=\(elapsed, privacy: .public) thread=\(thread, privacy: .public) main=\(mainThread, privacy: .public) text_length=\(length, privacy: .public) voice_id=\(voiceID, privacy: .public) voice_language=\(language, privacy: .public)\(suffix, privacy: .public)")
    }

    private func deactivateAudioSession() {
        #if os(iOS)
        do {
            Self.logStage("session_deactivation_begin", startedAt: nil, textLength: nil)
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            Self.logStage("session_deactivation_done", startedAt: nil, textLength: nil)
        } catch {
            let nsError = error as NSError
            Self.logger.error("stage=session_deactivation_failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)")
        }
        #endif
    }
}
#else
@MainActor
final class VoiceStylistService: ObservableObject {
    @Published private(set) var isSpeaking = false
    @Published private(set) var isUsingDefaultQualityVoice = false
    @Published private(set) var playbackErrorMessage: String?

    func speak(_ script: String) {}
    func speak(_ script: VoiceScript) {}
    func stop() {}
    func previewVoice() {}
}
#endif
