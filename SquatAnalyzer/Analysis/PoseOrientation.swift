import CoreGraphics
import Foundation
import Vision

enum BodySide: Equatable {
    case left, right
}

/// Leg-joint lookup and visibility check for the front-facing camera view.
enum PoseOrientation {

    private static let legJoints: [BodySide: (VNHumanBodyPoseObservation.JointName,
                                              VNHumanBodyPoseObservation.JointName,
                                              VNHumanBodyPoseObservation.JointName)] = [
        .left: (.leftHip, .leftKnee, .leftAnkle),
        .right: (.rightHip, .rightKnee, .rightAnkle),
    ]

    static func legChain(for side: BodySide)
        -> (VNHumanBodyPoseObservation.JointName,
            VNHumanBodyPoseObservation.JointName,
            VNHumanBodyPoseObservation.JointName) {
        legJoints[side]!
    }

    static func legChainScore(_ pose: DetectedPose, side: BodySide) -> Int {
        let (hip, knee, ankle) = legChain(for: side)
        return [hip, knee, ankle].filter { pose[$0] != nil }.count
    }

    static func isBodyVisible(in pose: DetectedPose) -> Bool {
        legChainScore(pose, side: .left) >= 3 || legChainScore(pose, side: .right) >= 3
    }
}
