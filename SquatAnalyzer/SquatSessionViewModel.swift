import Combine
import CoreVideo
import Foundation

/// A single per-frame snapshot of everything the UI draws for the live pose.
///
/// The whole pipeline publishes this as ONE value per frame. Updating one
/// `@Published` property per frame (instead of six) keeps SwiftUI from
/// re-entering its update cycle mid-frame, which is what triggers the
/// "Publishing changes from within view updates" runtime warning.
struct FrameState: Equatable {
    var pose: DetectedPose?
    var phase: SquatPhase = .standing
    var kneeAngle: Double?
    var repCount = 0
    var isBodyVisible = false
    /// Bottom-position joint targets ("reference zones"), once calibrated.
    var reference: ReferencePose?
}

/// Wires the pipeline together:
/// camera frame → pose detection → smoothing → squat analysis → published UI state.
@MainActor
final class SquatSessionViewModel: ObservableObject {

    enum CameraState {
        case starting
        case running
        case permissionDenied
        case failed
    }

    @Published var cameraState: CameraState = .starting
    @Published var frame = FrameState()
    @Published var feedback: Feedback?
    /// True once the camera has delivered at least one frame. Stays false in the
    /// iOS Simulator (no live capture), which the UI uses to explain the black view.
    @Published var isReceivingFrames = false

    let camera = CameraManager()

    private nonisolated let detector = PoseDetector()
    private var smoother = PoseSmoother()
    private var analyzer = SquatFormAnalyzer()
    private var referenceCalculator = ReferencePoseCalculator()
    private var feedbackDismissTask: Task<Void, Never>?
    private let speaker = FeedbackSpeaker()

    /// Consecutive frames without a usable pose before the "step back" hint shows.
    private var framesWithoutPose = 0

    init() {
        // Runs on the camera's video queue; detection happens inline so
        // alwaysDiscardsLateVideoFrames provides natural backpressure.
        camera.onFrame = { [weak self] pixelBuffer in
            self?.process(pixelBuffer)
        }
    }

    func startSession() async {
        let camera = self.camera

        // Race setup against a timeout so a hung capture stack (seen with the
        // "Designed for iPad" runtime on Mac) surfaces a message instead of an
        // endless "Starting camera…" spinner. `nil` means the timeout won.
        let result: CameraManager.SetupResult? = await withTaskGroup(of: CameraManager.SetupResult?.self) { group in
            group.addTask { await camera.setUp() }
            group.addTask {
                try? await Task.sleep(for: .seconds(10))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }

        switch result {
        case .ready:
            camera.start()
            cameraState = .running
        case .permissionDenied:
            cameraState = .permissionDenied
        case .configurationFailed, .none:
            cameraState = .failed
        }
    }

    func stopSession() {
        camera.stop()
        speaker.stop()
    }

    /// Resume after returning from the background. Safe to call before the
    /// initial `startSession()` finishes: `CameraManager.start()` no-ops until
    /// the session is configured, and the initial `.task` starts it then.
    func resumeSession() {
        guard cameraState == .running else { return }
        camera.start()
    }

    func resetSession() {
        analyzer.reset()
        smoother.reset()
        referenceCalculator.reset()
        frame = FrameState()
        feedback = nil
        speaker.stop()
    }

    private nonisolated func process(_ pixelBuffer: CVPixelBuffer) {
        let detected = detector.detectPose(in: pixelBuffer)

        Task { @MainActor in
            if !self.isReceivingFrames { self.isReceivingFrames = true }

            guard let detected else {
                self.framesWithoutPose += 1
                if self.framesWithoutPose > 10, self.frame.isBodyVisible || self.frame.pose != nil {
                    self.frame.pose = nil
                    self.frame.isBodyVisible = false
                }
                return
            }
            self.framesWithoutPose = 0

            let smoothedPose = self.smoother.smooth(detected)
            let result = self.analyzer.analyze(smoothedPose)
            let reference = self.referenceCalculator.update(pose: smoothedPose,
                                                            phase: result.phase,
                                                            kneeAngle: result.kneeAngle)

            let previousRepCount = self.frame.repCount

            // One atomic publish per frame.
            self.frame = FrameState(pose: smoothedPose,
                                    phase: result.phase,
                                    kneeAngle: result.kneeAngle,
                                    repCount: result.repCount,
                                    isBodyVisible: result.isBodyVisible,
                                    reference: reference)

            if let newFeedback = result.newFeedback {
                self.show(newFeedback)
            } else if result.repCount > previousRepCount {
                speaker.speak(repCountUtterance(result.repCount))
            }
        }
    }

    private func repCountUtterance(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = Locale(identifier: "uk_UA")
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    private func show(_ newFeedback: Feedback) {
        feedback = newFeedback
        speaker.speak(newFeedback.message)
        feedbackDismissTask?.cancel()
        feedbackDismissTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            feedback = nil
        }
    }
}
