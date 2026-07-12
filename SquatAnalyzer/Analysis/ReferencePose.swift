import CoreGraphics
import Vision

/// Target joint positions for the bottom of a proper squat, drawn as a ghost
/// posture outline the athlete steers into while descending.
struct ReferencePose: Equatable {
    /// Bottom-of-squat targets to steer into: hip, knee, shoulder, and the
    /// (unmoving) ankle.
    var targets: [VNHumanBodyPoseObservation.JointName: CGPoint]
    /// Fixed standing-level markers: the shoulder's starting height, shown
    /// alongside the bottom-of-squat shoulder target for reference.
    var standingMarkers: [VNHumanBodyPoseObservation.JointName: CGPoint]

    /// Normalized distance (fraction of image height) within which a live
    /// joint counts as "on target".
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

    // Bottom-position geometry, expressed as fractions of the athlete's own
    // shin length so the targets scale to their body and camera distance.
    // Tuned down from the original reference-video measurement (0.48/0.34),
    // which pointed at a much deeper squat than a standard "thighs parallel"
    // depth and felt too low on real devices — hip target now sits just
    // above the knee target (parallel), not noticeably below it.
    /// Knee sinks this far below the standing knee at the bottom.
    private let kneeDrop: CGFloat = 0.32
    /// Knee tracks this far outside the ankle (over the foot) at the bottom.
    private let kneeOutward: CGFloat = 0.08
    /// Hips sink this far below the standing knee at the bottom.
    private let hipDrop: CGFloat = 0.28
    /// Shoulders sink this far below the standing knee at the bottom — more
    /// than the hips, since the chest/torso continues down and leans forward
    /// slightly, but well short of hip level so the chest stays visibly up.
    /// Rough estimate from reference footage — expect to tune after trying it.
    private let shoulderDrop: CGFloat = 0.40

    private var baseline: [JointName: CGPoint] = [:]
    private var baselineFrames = 0

    private static let trackedJoints: [JointName] = [
        .leftShoulder, .rightShoulder,
        .leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle,
    ]

    mutating func update(pose: DetectedPose, phase: SquatPhase, kneeAngle: Double?) -> ReferencePose? {
        if phase == .standing, let kneeAngle, kneeAngle > uprightKneeAngle {
            accumulate(pose)
        }
        guard baselineFrames >= minBaselineFrames else { return nil }

        let (targets, standingMarkers) = frontTargets()
        guard !targets.isEmpty else { return nil }
        return ReferencePose(targets: targets, standingMarkers: standingMarkers)
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

    /// Shoulders sink partway down (chest continues lowering, though less
    /// than the hips), hips sink toward knee height, knees track down and out
    /// over the feet, feet stay planted. All offsets are the measured
    /// reference ratios scaled by the athlete's own shin length, anchored at
    /// their standing knee and foot positions. Shoulders also get a fixed
    /// standing-level marker, so both the start and target heights are visible.
    private func frontTargets() -> (targets: [JointName: CGPoint], standingMarkers: [JointName: CGPoint]) {
        guard let leftAnkle = baseline[.leftAnkle], let rightAnkle = baseline[.rightAnkle] else { return ([:], [:]) }
        let midlineX = (leftAnkle.x + rightAnkle.x) / 2

        var targets: [JointName: CGPoint] = [:]
        var standingMarkers: [JointName: CGPoint] = [:]
        let chains: [(JointName, JointName, JointName, JointName)] = [
            (.leftShoulder, .leftHip, .leftKnee, .leftAnkle),
            (.rightShoulder, .rightHip, .rightKnee, .rightAnkle),
        ]
        for (shoulder, hip, knee, ankle) in chains {
            guard let h = baseline[hip], let k = baseline[knee], let a = baseline[ankle] else { continue }
            let shin = AngleMath.distance(k, a)
            let outward: CGFloat = a.x >= midlineX ? 1 : -1

            targets[hip] = CGPoint(x: h.x, y: k.y + shin * hipDrop)
            targets[knee] = CGPoint(x: a.x + outward * shin * kneeOutward,
                                    y: k.y + shin * kneeDrop)
            targets[ankle] = a
            if let s = baseline[shoulder] {
                standingMarkers[shoulder] = s
                targets[shoulder] = CGPoint(x: s.x, y: k.y + shin * shoulderDrop)
            }
        }
        return (targets, standingMarkers)
    }
}
