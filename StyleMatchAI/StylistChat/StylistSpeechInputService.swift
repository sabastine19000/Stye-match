import Foundation
import Combine

#if DEBUG && canImport(OSLog)
import OSLog
#endif

#if canImport(AVFoundation)
import AVFoundation
#endif

#if canImport(Speech)
import Speech
#endif

#if canImport(UIKit)
import UIKit
#endif

enum StylistSpeechInputState: Equatable {
    case idle
    case requestingPermission
    case listening
    case processingFinalTranscript
    case microphoneDenied
    case speechDenied
    case speechRestricted
    case recognitionUnavailable
    case noSpeechDetected
    case failed(String)

    var isActive: Bool {
        switch self {
        case .requestingPermission, .listening, .processingFinalTranscript:
            return true
        case .idle, .microphoneDenied, .speechDenied, .speechRestricted, .recognitionUnavailable, .noSpeechDetected, .failed:
            return false
        }
    }

    var userMessage: String? {
        switch self {
        case .idle:
            return nil
        case .requestingPermission:
            return "Checking voice permissions..."
        case .listening:
            return "Listening. Review or edit the transcript before sending."
        case .processingFinalTranscript:
            return "Finishing transcript..."
        case .microphoneDenied:
            return "Microphone access is off. You can enable it in Settings or type your question instead."
        case .speechDenied:
            return "Speech recognition is off. You can enable it in Settings or type your question instead."
        case .speechRestricted:
            return "Speech recognition is restricted on this device. You can type your question instead."
        case .recognitionUnavailable:
            return "Speech recognition is unavailable right now. You can type your question instead."
        case .noSpeechDetected:
            return "No speech was detected. Try again or type your question."
        case .failed(let message):
            return message
        }
    }
}

enum StylistSpeechAuthorizationStatus: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case unavailable
}

@MainActor
protocol StylistSpeechRecognitionControlling: AnyObject {
    var supportsRecognition: Bool { get }
    func microphoneAuthorizationStatus() -> StylistSpeechAuthorizationStatus
    func speechAuthorizationStatus() -> StylistSpeechAuthorizationStatus
    func requestMicrophoneAuthorization() async -> StylistSpeechAuthorizationStatus
    func requestSpeechAuthorization() async -> StylistSpeechAuthorizationStatus
    func startRecognition(
        onPartialTranscript: @escaping @MainActor (String) -> Void,
        onFinalTranscript: @escaping @MainActor (String) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) throws
    func stopRecognition(cancel: Bool)
}

@MainActor
final class StylistSpeechInputService: ObservableObject {
    @Published private(set) var state: StylistSpeechInputState = .idle
    @Published private(set) var transcript = ""

    private let controller: StylistSpeechRecognitionControlling
    private var originalText = ""
    private var hasRecognizedSpeech = false
    private var activeStartAttemptID: UUID?
    private var interruptionObserver: NSObjectProtocol?
    private var backgroundObserver: NSObjectProtocol?

    init(controller: StylistSpeechRecognitionControlling? = nil) {
        self.controller = controller ?? SystemStylistSpeechRecognitionController()
        installLifecycleObservers()
    }

    deinit {
        [interruptionObserver, backgroundObserver].forEach { observer in
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }

    func startListening(existingText: String) async {
        guard !state.isActive else { return }
        guard controller.supportsRecognition else {
            state = .recognitionUnavailable
            announce(state)
            return
        }

        let attemptID = UUID()
        activeStartAttemptID = attemptID
        originalText = existingText
        transcript = existingText
        hasRecognizedSpeech = false
        state = .requestingPermission
        announce(state)

        let microphoneStatus = await resolvedMicrophoneAuthorization()
        guard isCurrentStartAttempt(attemptID) else { return }
        guard microphoneStatus == .authorized else {
            activeStartAttemptID = nil
            state = microphoneStatus == .restricted ? .speechRestricted : .microphoneDenied
            announce(state)
            return
        }

        let speechStatus = await resolvedSpeechAuthorization()
        guard isCurrentStartAttempt(attemptID) else { return }
        guard speechStatus == .authorized else {
            activeStartAttemptID = nil
            state = speechState(for: speechStatus)
            announce(state)
            return
        }

        do {
            guard isCurrentStartAttempt(attemptID) else { return }
            try controller.startRecognition { [weak self] partial in
                self?.applyRecognizedText(partial)
            } onFinalTranscript: { [weak self] final in
                self?.applyRecognizedText(final)
                self?.finishListening()
            } onError: { [weak self] error in
                self?.handleRecognitionError(error)
            }
            state = .listening
            announce(state)
        } catch {
            activeStartAttemptID = nil
            handleRecognitionError(error)
        }
    }

    func stopListening() {
        guard state.isActive else { return }
        state = .processingFinalTranscript
        announce(state)
        finishListening()
    }

    @discardableResult
    func cancelListening() -> String {
        guard state.isActive || !transcript.isEmpty else {
            return originalText
        }
        controller.stopRecognition(cancel: true)
        activeStartAttemptID = nil
        transcript = originalText
        hasRecognizedSpeech = false
        state = .idle
        announce("Voice input cancelled.")
        return originalText
    }

    func clearTranscript() {
        transcript = ""
        originalText = ""
        hasRecognizedSpeech = false
    }

    private func resolvedMicrophoneAuthorization() async -> StylistSpeechAuthorizationStatus {
        let current = controller.microphoneAuthorizationStatus()
        guard current == .notDetermined else { return current }
        return await controller.requestMicrophoneAuthorization()
    }

    private func resolvedSpeechAuthorization() async -> StylistSpeechAuthorizationStatus {
        let current = controller.speechAuthorizationStatus()
        guard current == .notDetermined else { return current }
        return await controller.requestSpeechAuthorization()
    }

    private func speechState(for status: StylistSpeechAuthorizationStatus) -> StylistSpeechInputState {
        switch status {
        case .authorized:
            return .idle
        case .restricted:
            return .speechRestricted
        case .unavailable:
            return .recognitionUnavailable
        case .notDetermined, .denied:
            return .speechDenied
        }
    }

    private func applyRecognizedText(_ recognizedText: String) {
        let cleaned = recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        hasRecognizedSpeech = true

        let base = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        transcript = base.isEmpty ? cleaned : "\(base) \(cleaned)"
    }

    private func finishListening() {
        activeStartAttemptID = nil
        controller.stopRecognition(cancel: false)
        if hasRecognizedSpeech || !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            state = .idle
            announce("Listening stopped. Transcript is ready to edit or send.")
        } else {
            state = .noSpeechDetected
            announce(state)
        }
    }

    private func handleRecognitionError(_ error: Error) {
        activeStartAttemptID = nil
        controller.stopRecognition(cancel: true)
        let nsError = error as NSError
        if nsError.domain == "kAFAssistantErrorDomain", nsError.code == 1110 {
            state = .noSpeechDetected
        } else {
            state = .failed("Voice input stopped. You can try again or type your question.")
        }
        announce(state)
    }

    private func installLifecycleObservers() {
        #if os(iOS) && canImport(AVFoundation)
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue),
                  type == .began else {
                return
            }
            Task { @MainActor in
                guard let self, self.state.isActive else { return }
                self.controller.stopRecognition(cancel: true)
                self.state = .failed("Voice input was interrupted. Try again or type your question.")
                self.announce(self.state)
            }
        }
        #endif

        #if canImport(UIKit)
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                _ = self?.cancelListening()
            }
        }
        #endif
    }

    private func isCurrentStartAttempt(_ attemptID: UUID) -> Bool {
        activeStartAttemptID == attemptID && state == .requestingPermission
    }

    private func announce(_ state: StylistSpeechInputState) {
        if let message = state.userMessage {
            announce(message)
        }
    }

    private func announce(_ message: String) {
        #if canImport(UIKit)
        UIAccessibility.post(notification: .announcement, argument: message)
        #endif
    }
}

#if os(iOS) && canImport(Speech) && canImport(AVFoundation)
@MainActor
final class SystemStylistSpeechRecognitionController: StylistSpeechRecognitionControlling {
    var supportsRecognition: Bool {
        recognizer?.isAvailable == true
    }

    private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    private var audioEngine: AVAudioEngine?
    private weak var tappedInputNode: AVAudioInputNode?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var activeSessionID: UUID?

    #if DEBUG && canImport(OSLog)
    private let diagnosticLogger = Logger(
        subsystem: "com.sabastine.stylematchai",
        category: "StylistSpeechInput"
    )
    #endif

    func microphoneAuthorizationStatus() -> StylistSpeechAuthorizationStatus {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            return .authorized
        case .denied:
            return .denied
        case .undetermined:
            return .notDetermined
        @unknown default:
            return .unavailable
        }
    }

    func speechAuthorizationStatus() -> StylistSpeechAuthorizationStatus {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .authorized:
            return .authorized
        @unknown default:
            return .unavailable
        }
    }

    func requestMicrophoneAuthorization() async -> StylistSpeechAuthorizationStatus {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted ? .authorized : .denied)
            }
        }
    }

    func requestSpeechAuthorization() async -> StylistSpeechAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                let mapped: StylistSpeechAuthorizationStatus
                switch status {
                case .authorized:
                    mapped = .authorized
                case .denied:
                    mapped = .denied
                case .restricted:
                    mapped = .restricted
                case .notDetermined:
                    mapped = .notDetermined
                @unknown default:
                    mapped = .unavailable
                }
                continuation.resume(returning: mapped)
            }
        }
    }

    func startRecognition(
        onPartialTranscript: @escaping @MainActor (String) -> Void,
        onFinalTranscript: @escaping @MainActor (String) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) throws {
        if activeSessionID != nil || recognitionRequest != nil || recognitionTask != nil {
            recordInstallGuard("existing_session")
            throw StylistSpeechInputError.recognitionAlreadyActive
        }
        if tappedInputNode != nil {
            recordInstallGuard("existing_owned_tap")
            throw StylistSpeechInputError.recognitionAlreadyActive
        }
        if audioEngine != nil {
            recordInstallGuard("existing_audio_engine")
            throw StylistSpeechInputError.recognitionAlreadyActive
        }

        guard let recognizer, recognizer.isAvailable else {
            recordInstallGuard("recognizer_unavailable")
            throw StylistSpeechInputError.recognitionUnavailable
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        guard !session.currentRoute.inputs.isEmpty else {
            recordInstallGuard("invalid_audio_route")
            resetRecognitionState(cancel: true)
            throw StylistSpeechInputError.invalidAudioRoute
        }

        let sessionID = UUID()
        activeSessionID = sessionID

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        // A fresh engine gives each recognition attempt sole ownership of its
        // input tap. Reusing an engine can leave an AVAudioNode tap behind
        // across cancellation or audio-route changes; installTap then raises
        // an Objective-C exception that Swift cannot catch.
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            recordInstallGuard("invalid_input_format")
            resetRecognitionState(cancel: true)
            throw StylistSpeechInputError.invalidAudioInput
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            guard buffer.frameLength > 0 else { return }
            request?.append(buffer)
        }
        tappedInputNode = inputNode
        audioEngine = engine

        do {
            engine.prepare()
            try engine.start()
        } catch {
            recordInstallGuard("audio_engine_start_failed")
            resetRecognitionState(cancel: true)
            throw error
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let result {
                let transcript = result.bestTranscription.formattedString
                Task { @MainActor in
                    guard self?.activeSessionID == sessionID else { return }
                    if result.isFinal {
                        onFinalTranscript(transcript)
                    } else {
                        onPartialTranscript(transcript)
                    }
                }
            }

            if let error {
                Task { @MainActor in
                    guard self?.activeSessionID == sessionID else { return }
                    onError(error)
                }
            }
        }

        recordLifecycle("recognition_started")
    }

    func stopRecognition(cancel: Bool) {
        resetRecognitionState(cancel: cancel)
    }

    private func resetRecognitionState(cancel: Bool) {
        activeSessionID = nil
        if audioEngine?.isRunning == true {
            audioEngine?.stop()
        }
        if let tappedInputNode {
            tappedInputNode.removeTap(onBus: 0)
        }
        tappedInputNode = nil
        audioEngine?.reset()
        audioEngine = nil
        if cancel {
            recognitionTask?.cancel()
        } else {
            recognitionRequest?.endAudio()
        }
        recognitionTask = nil
        recognitionRequest = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        recordLifecycle(cancel ? "recognition_cancelled" : "recognition_stopped")
    }

    private func recordInstallGuard(_ reason: String) {
        #if DEBUG && canImport(OSLog)
        diagnosticLogger.error("install_tap_guard=\(reason, privacy: .public)")
        #endif
    }

    private func recordLifecycle(_ event: String) {
        #if DEBUG && canImport(OSLog)
        diagnosticLogger.debug("speech_lifecycle=\(event, privacy: .public)")
        #endif
    }
}
#else
final class SystemStylistSpeechRecognitionController: StylistSpeechRecognitionControlling {
    var supportsRecognition: Bool { false }
    func microphoneAuthorizationStatus() -> StylistSpeechAuthorizationStatus { .unavailable }
    func speechAuthorizationStatus() -> StylistSpeechAuthorizationStatus { .unavailable }
    func requestMicrophoneAuthorization() async -> StylistSpeechAuthorizationStatus { .unavailable }
    func requestSpeechAuthorization() async -> StylistSpeechAuthorizationStatus { .unavailable }
    func startRecognition(
        onPartialTranscript: @escaping @MainActor (String) -> Void,
        onFinalTranscript: @escaping @MainActor (String) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) throws {
        throw StylistSpeechInputError.recognitionUnavailable
    }
    func stopRecognition(cancel: Bool) {}
}
#endif

enum StylistSpeechInputError: LocalizedError {
    case recognitionUnavailable
    case recognitionAlreadyActive
    case invalidAudioRoute
    case invalidAudioInput

    var errorDescription: String? {
        switch self {
        case .recognitionUnavailable:
            return "Speech recognition is unavailable right now."
        case .recognitionAlreadyActive:
            return "Voice input is already active."
        case .invalidAudioRoute, .invalidAudioInput:
            return "Microphone input is unavailable right now."
        }
    }
}
