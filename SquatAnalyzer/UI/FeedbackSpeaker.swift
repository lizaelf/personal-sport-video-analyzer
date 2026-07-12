import AVFoundation

/// Speaks form feedback aloud during a workout.
@MainActor
final class FeedbackSpeaker {
    private let synthesizer = AVSpeechSynthesizer()
    private var audioSessionConfigured = false

    func speak(_ message: String) {
        guard !message.isEmpty else { return }
        configureAudioSession()
        synthesizer.stopSpeaking(at: .immediate)

        let utterance = AVSpeechUtterance(string: message)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        utterance.voice = preferredVoice()
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
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
