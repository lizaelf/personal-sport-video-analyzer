import AVFoundation

/// Speaks form feedback aloud during a workout.
@MainActor
final class FeedbackSpeaker {
    private let synthesizer = AVSpeechSynthesizer()
    private let delegateBridge = SynthesizerDelegateBridge()
    private var audioSessionConfigured = false
    private var queuedMessage: String?

    init() {
        delegateBridge.onFinish = { [weak self] in
            Task { @MainActor in self?.speakQueuedIfNeeded() }
        }
        synthesizer.delegate = delegateBridge
    }

    var isSpeaking: Bool { synthesizer.isSpeaking }

    /// Interrupts any in-progress speech — for new form errors.
    func speakFeedback(_ message: String) {
        guard !message.isEmpty else { return }
        queuedMessage = nil
        speakNow(message)
    }

    /// Waits for the current utterance to finish before speaking the rep count.
    func speakRepCount(_ message: String) {
        guard !message.isEmpty else { return }
        if synthesizer.isSpeaking {
            queuedMessage = message
        } else {
            speakNow(message)
        }
    }

    func stop() {
        queuedMessage = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func speakQueuedIfNeeded() {
        guard let next = queuedMessage else { return }
        queuedMessage = nil
        speakNow(next)
    }

    private func speakNow(_ message: String) {
        configureAudioSession()

        let utterance = AVSpeechUtterance(string: message)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        utterance.voice = preferredVoice()
        synthesizer.speak(utterance)
    }

    private func configureAudioSession() {
        guard !audioSessionConfigured else { return }
        audioSessionConfigured = true

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }

    private func preferredVoice() -> AVSpeechSynthesisVoice? {
        maleVoice(languagePrefixes: ["uk-UA", "uk"])
            ?? AVSpeechSynthesisVoice(language: "uk-UA")
            ?? maleVoice(languagePrefixes: ["en-US", "en"])
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    private func maleVoice(languagePrefixes: [String]) -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice.speechVoices().first { voice in
            voice.gender == .male
                && languagePrefixes.contains { voice.language.hasPrefix($0) }
        }
    }
}

/// NSObject bridge for `AVSpeechSynthesizerDelegate` — kept separate so the
/// main speaker type stays a plain `@MainActor` class (mixing NSObject +
/// `@MainActor` on the same type can crash at runtime).
private final class SynthesizerDelegateBridge: NSObject, AVSpeechSynthesizerDelegate {
    var onFinish: (() -> Void)?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        onFinish?()
    }
}
