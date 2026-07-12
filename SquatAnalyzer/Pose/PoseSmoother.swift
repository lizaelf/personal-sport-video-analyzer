import CoreGraphics
import Vision

/// Reduces per-frame jitter with exponential smoothing:
/// smoothed = previous * (1 - alpha) + current * alpha.
struct PoseSmoother {

    private let alpha: CGFloat = 0.3
    /// Frames a joint may be missing before its history is discarded.
    private let maxMissingFrames = 5

    private var smoothed: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
    private var missingCounts: [VNHumanBodyPoseObservation.JointName: Int] = [:]
    private var shoulderOffsetFromNeck: [VNHumanBodyPoseObservation.JointName: CGVector] = [:]

    mutating func smooth(_ pose: DetectedPose) -> DetectedPose {
        var result = pose

        for name in Set(smoothed.keys).union(pose.joints.keys) {
            if let current = pose.joints[name] {
                missingCounts[name] = 0
                if let previous = smoothed[name] {
                    let point = CGPoint(x: previous.x * (1 - alpha) + current.x * alpha,
                                        y: previous.y * (1 - alpha) + current.y * alpha)
                    smoothed[name] = point
                    result.joints[name] = point
                } else {
                    smoothed[name] = current
                }
            } else {
                let missed = (missingCounts[name] ?? 0) + 1
                missingCounts[name] = missed
                if missed > maxMissingFrames {
                    smoothed[name] = nil
                } else if let previous = smoothed[name] {
                    // Briefly carry the last known position to avoid flicker.
                    result.joints[name] = previous
                }
            }
        }

        recoverShoulders(in: &result)
        return result
    }

    mutating func reset() {
        smoothed.removeAll()
        missingCounts.removeAll()
        shoulderOffsetFromNeck.removeAll()
    }

    /// Vision often drops shoulders during a squat; estimate them from the neck
    /// using the last known shoulder–neck offset so the live markers keep moving.
    private mutating func recoverShoulders(in result: inout DetectedPose) {
        guard let neck = result.joints[.neck] ?? smoothed[.neck] else { return }

        for shoulder in [VNHumanBodyPoseObservation.JointName.leftShoulder,
                         .rightShoulder] {
            if let detected = result.joints[shoulder] {
                shoulderOffsetFromNeck[shoulder] = CGVector(dx: detected.x - neck.x,
                                                            dy: detected.y - neck.y)
                continue
            }

            guard let offset = shoulderOffsetFromNeck[shoulder] else { continue }
            let estimated = CGPoint(x: neck.x + offset.dx, y: neck.y + offset.dy)
            result.joints[shoulder] = estimated
            smoothed[shoulder] = estimated
            missingCounts[shoulder] = 0
        }
    }
}
