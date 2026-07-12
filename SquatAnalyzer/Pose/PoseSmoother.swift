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
        return result
    }

    mutating func reset() {
        smoothed.removeAll()
        missingCounts.removeAll()
    }
}
