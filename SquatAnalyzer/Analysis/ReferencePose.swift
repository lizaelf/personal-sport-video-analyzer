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
    // Tuned down twice now (0.48 → 0.34 → 0.28) after real-device feedback
    // that the hip target still sat too low/deep each time — reduced more
    // aggressively this round rather than nudging by the same small amount again.
    /// Knee sinks this far below the standing knee at the bottom.
    private let kneeDrop: CGFloat = 0.32
    /// Knee tracks this far outside the ankle (over the foot) at the bottom.
    private let kneeOutward: CGFloat = 0.08
    /// Hips sink this far below the standing knee at the bottom.
    private let hipDrop: CGFloat = 0.15
    /// Feet stance width (ankle-to-ankle) as a multiple of the athlete's own
    /// shoulder width, measured from the reference photo: feet planted
    /// noticeably wider than the shoulders.
    private let stanceWidthRatio: CGFloat = 1.7

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

    /// Hips sink toward knee height, knees track down and out over the feet,
    /// feet stay planted. The shoulder target keeps the torso vertical: it
    /// sits exactly one torso-length (measured from THIS athlete's own
    /// standing pose, not guessed) above the hip target, so a squat that
    /// hits both the hip and shoulder targets keeps the chest up rather than
    /// folding forward. Shoulders also get a fixed standing-level marker, so
    /// both the start and target heights are visible.
    ///
    /// The foot target is a stance-width guide rather than a bottom-of-squat
    /// target: it sits at the athlete's own standing ankle height but at an
    /// x-position derived from their shoulder width, so it shows where to
    /// plant their feet before descending (per the reference photo, wider
    /// than shoulder-width) rather than just echoing wherever they're
    /// currently standing.
    private func frontTargets() -> (targets: [JointName: CGPoint], standingMarkers: [JointName: CGPoint]) {
        guard let leftAnkle = baseline[.leftAnkle], let rightAnkle = baseline[.rightAnkle] else { return ([:], [:]) }
        let midlineX = (leftAnkle.x + rightAnkle.x) / 2

        var targets: [JointName: CGPoint] = [:]
        var standingMarkers: [JointName: CGPoint] = [:]

        if let ls = baseline[.leftShoulder], let rs = baseline[.rightShoulder] {
            let shoulderMidX = (ls.x + rs.x) / 2
            let halfStance = AngleMath.distance(ls, rs) * stanceWidthRatio / 2
            targets[.leftAnkle] = CGPoint(x: shoulderMidX - halfStance, y: leftAnkle.y)
            targets[.rightAnkle] = CGPoint(x: shoulderMidX + halfStance, y: rightAnkle.y)
        } else {
            targets[.leftAnkle] = leftAnkle
            targets[.rightAnkle] = rightAnkle
        }

        let chains: [(JointName, JointName, JointName, JointName)] = [
            (.leftShoulder, .leftHip, .leftKnee, .leftAnkle),
            (.rightShoulder, .rightHip, .rightKnee, .rightAnkle),
        ]
        for (shoulder, hip, knee, ankle) in chains {
            guard let h = baseline[hip], let k = baseline[knee], let a = baseline[ankle] else { continue }
            let shin = AngleMath.distance(k, a)
            let outward: CGFloat = a.x >= midlineX ? 1 : -1

            let hipTarget = CGPoint(x: h.x, y: k.y + shin * hipDrop)
            targets[hip] = hipTarget
            targets[knee] = CGPoint(x: a.x + outward * shin * kneeOutward,
                                    y: k.y + shin * kneeDrop)
            if let s = baseline[shoulder] {
                standingMarkers[shoulder] = s
                let torsoLength = AngleMath.distance(s, h)
                targets[shoulder] = CGPoint(x: s.x, y: hipTarget.y - torsoLength)
            }
        }
        return (targets, standingMarkers)
    }
}
