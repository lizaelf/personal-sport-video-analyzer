import AVFoundation

/// Speaks form feedback aloud during a workout.
@MainActor
final class FeedbackSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var audioSessionConfigured = false
    private var queuedMessage: String?

    override init() {
        super.init()
        synthesizer.delegate = self
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

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard let next = self.queuedMessage else { return }
            self.queuedMessage = nil
            self.speakNow(next)
        }
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
        AVSpeechSynthesisVoice(language: "uk-UA")
            ?? AVSpeechSynthesisVoice(language: "uk")
            ?? AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier ?? "en-US")
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }
}
