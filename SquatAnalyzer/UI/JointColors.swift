import SwiftUI
import Vision

/// Shared colors for shoulders, hips, and knees — live markers and reference targets match.
enum JointColors {
    static let shoulder = Color.cyan
    static let hip = Color.yellow
    static let knee = Color.orange

    static func color(for joint: VNHumanBodyPoseObservation.JointName) -> Color? {
        switch joint {
        case .leftShoulder, .rightShoulder: shoulder
        case .leftHip, .rightHip: hip
        case .leftKnee, .rightKnee: knee
        default: nil
        }
    }

    static var shoulderJoints: Set<VNHumanBodyPoseObservation.JointName> {
        [.leftShoulder, .rightShoulder]
    }

    static var kneeJoints: Set<VNHumanBodyPoseObservation.JointName> {
        [.leftKnee, .rightKnee]
    }
}
