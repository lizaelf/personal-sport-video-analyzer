import CoreGraphics
import Vision

/// Target joint positions for the bottom of a proper squat, shown as rings the
/// athlete steers into while descending.
struct ReferencePose: Equatable {
    var targets: [VNHumanBodyPoseObservation.JointName: CGPoint]

    /// Normalized distance (fraction of image height) within which a live
    /// joint counts as "on target". Also used as the ring radius on screen.
    static let tolerance: CGFloat = 0.045
}

/// Derives bottom-position targets from the athlete's own standing pose, so
/// the targets match their proportions and where they stand in the frame.
///
/// While the athlete stands upright the baseline follows them (exponential
/// moving average); it freezes as soon as the descent starts, so the targets
/// stay put during the rep.
struct ReferencePoseCalculator {

    private typealias JointName = VNHumanBodyPoseObservation.JointName

    /// Knee angle above which the current pose counts as "standing upright".
    private let uprightKneeAngle = 160.0
    /// Standing frames required before targets are shown.
    private let minBaselineFrames = 10
    private let alpha: CGFloat = 0.2

    /// How far the knee target sinks below the standing knee, per shin length.
    /// Calibrated against reference squat footage.
    private let kneeDrop: CGFloat = 0.12

    private var baseline: [JointName: CGPoint] = [:]
    private var baselineFrames = 0

    private static let trackedJoints: [JointName] = [
        .leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle,
    ]

    mutating func update(pose: DetectedPose, phase: SquatPhase, kneeAngle: Double?) -> ReferencePose? {
        if phase == .standing, let kneeAngle, kneeAngle > uprightKneeAngle {
            accumulate(pose)
        }
        guard baselineFrames >= minBaselineFrames else { return nil }

        let targets = frontTargets()
        guard !targets.isEmpty else { return nil }
        return ReferencePose(targets: targets)
    }

    mutating func reset() {
        baseline.removeAll()
        baselineFrames = 0
    }

    private mutating func accumulate(_ pose: DetectedPose) {
        for name in Self.trackedJoints {
            guard let current = pose[name] else { continue }
            if let previous = baseline[name] {
                baseline[name] = CGPoint(x: previous.x * (1 - alpha) + current.x * alpha,
                                         y: previous.y * (1 - alpha) + current.y * alpha)
            } else {
                baseline[name] = current
            }
        }
        baselineFrames = min(baselineFrames + 1, 1000)
    }

    /// Hips sink to knee height, knees track out over the feet, feet stay planted.
    private func frontTargets() -> [JointName: CGPoint] {
        var targets: [JointName: CGPoint] = [:]

        let chains: [(JointName, JointName, JointName)] = [
            (.leftHip, .leftKnee, .leftAnkle),
            (.rightHip, .rightKnee, .rightAnkle),
        ]
        for (hip, knee, ankle) in chains {
            guard let h = baseline[hip], let k = baseline[knee], let a = baseline[ankle] else { continue }
            let shin = abs(a.y - k.y)
            targets[hip] = CGPoint(x: h.x, y: k.y)
            targets[knee] = CGPoint(x: a.x, y: k.y + shin * kneeDrop)
            targets[ankle] = a
        }
        return targets
    }
}
