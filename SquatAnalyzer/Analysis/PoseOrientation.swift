import CoreGraphics
import Foundation
import Vision

enum BodySide: Equatable {
    case left, right
}

/// Whether the athlete is facing the camera or shown in profile.
enum SquatViewMode: Equatable {
    case front
    case side(BodySide)

    var label: String {
        switch self {
        case .front: "Спереду"
        case .side: "Збоку"
        }
    }
}

/// The user's choice in the UI: let the app detect the camera angle, or force one.
enum ViewModeSelection: String, CaseIterable, Identifiable {
    case auto = "Авто"
    case front = "Спереду"
    case side = "Збоку"

    var id: String { rawValue }
}

/// Infers camera orientation from which joints are visible in the frame.
enum PoseOrientation {

    private static let sideLegJoints: [BodySide: (VNHumanBodyPoseObservation.JointName,
                                                  VNHumanBodyPoseObservation.JointName,
                                                  VNHumanBodyPoseObservation.JointName)] = [
        .left: (.leftHip, .leftKnee, .leftAnkle),
        .right: (.rightHip, .rightKnee, .rightAnkle),
    ]

    private static let sideTorsoJoints: [BodySide: (VNHumanBodyPoseObservation.JointName,
                                                    VNHumanBodyPoseObservation.JointName,
                                                    VNHumanBodyPoseObservation.JointName)] = [
        .left: (.leftShoulder, .leftHip, .leftKnee),
        .right: (.rightShoulder, .rightHip, .rightKnee),
    ]

    /// Minimum normalized ankle separation to treat the pose as front-facing.
    private static let frontAnkleSeparation = 0.08

    static func detect(in pose: DetectedPose) -> SquatViewMode {
        let leftScore = legChainScore(pose, side: .left)
        let rightScore = legChainScore(pose, side: .right)

        if leftScore >= 3,
           rightScore >= 3,
           let ankleSep = ankleSeparation(pose),
           ankleSep >= frontAnkleSeparation {
            return .front
        }

        return preferredSide(leftScore: leftScore, rightScore: rightScore)
    }

    static func isBodyVisible(in pose: DetectedPose, mode: SquatViewMode) -> Bool {
        switch mode {
        case .front:
            return legChainScore(pose, side: .left) >= 3 || legChainScore(pose, side: .right) >= 3
        case .side(let side):
            return legChainScore(pose, side: side) >= 3
        }
    }

    static func legChain(for side: BodySide)
        -> (VNHumanBodyPoseObservation.JointName,
            VNHumanBodyPoseObservation.JointName,
            VNHumanBodyPoseObservation.JointName) {
        sideLegJoints[side]!
    }

    static func torsoChain(for side: BodySide)
        -> (VNHumanBodyPoseObservation.JointName,
            VNHumanBodyPoseObservation.JointName,
            VNHumanBodyPoseObservation.JointName) {
        sideTorsoJoints[side]!
    }

    static func legChainScore(_ pose: DetectedPose, side: BodySide) -> Int {
        let (hip, knee, ankle) = legChain(for: side)
        return [hip, knee, ankle].filter { pose[$0] != nil }.count
    }

    /// The better-visible profile, for when the user has forced side view.
    static func detectSide(in pose: DetectedPose) -> SquatViewMode {
        preferredSide(leftScore: legChainScore(pose, side: .left),
                      rightScore: legChainScore(pose, side: .right))
    }

    private static func preferredSide(leftScore: Int, rightScore: Int) -> SquatViewMode {
        if leftScore >= rightScore, leftScore >= 2 {
            return .side(.left)
        }
        if rightScore > leftScore, rightScore >= 2 {
            return .side(.right)
        }
        return leftScore >= rightScore ? .side(.left) : .side(.right)
    }

    private static func ankleSeparation(_ pose: DetectedPose) -> Double? {
        guard let left = pose[.leftAnkle], let right = pose[.rightAnkle] else { return nil }
        return AngleMath.distance(left, right)
    }
}
