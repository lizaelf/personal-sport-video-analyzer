import CoreGraphics
import Foundation
import Vision

enum SquatPhase: String {
    case standing = "Standing"
    case descending = "Descending"
    case bottom = "Bottom"
    case ascending = "Ascending"
}

struct Feedback: Identifiable, Equatable {
    enum Severity {
        case good, warning, error
    }

    let id = UUID()
    let message: String
    let severity: Severity
}

/// Per-frame analysis output consumed by the view model.
struct AnalysisResult {
    var phase: SquatPhase
    var kneeAngle: Double?
    var repCount: Int
    var newFeedback: Feedback?
    var isBodyVisible: Bool
}

/// Tracks the squat through its phases using the knee angle and evaluates
/// form rules for a front-facing camera.
///
/// Knee angle is the front camera's 2D projection, not the true joint angle —
/// a parallel squat reads ~105–125° head-on due to foreshortening, calibrated
/// against reference footage.
struct SquatFormAnalyzer {

    // Phase thresholds (degrees, projected).
    private let standingThreshold = 155.0
    private let bottomThreshold = 130.0
    /// Rise from the deepest point that counts as the start of the ascent.
    private let ascentHysteresis = 12.0
    private let overFlexionAngle = 85.0
    private let insufficientDepthAngle = 130.0
    /// Knee angle below which the valgus rule applies.
    private let ruleMaxKneeAngle = 130.0

    private let kneeValgusRatio = 0.8
    /// Knees wider than this multiple of ankle width are flagged.
    private let kneeTooWideRatio = 1.35

    private(set) var phase: SquatPhase = .standing
    private(set) var repCount = 0

    private var previousKneeAngle: Double?
    private var minKneeAngleInRep = 180.0
    private var issuesThisRep: Set<String> = []

    mutating func analyze(_ pose: DetectedPose) -> AnalysisResult {
        let bodyVisible = PoseOrientation.isBodyVisible(in: pose)
        guard let kneeAngle = kneeAngle(of: pose) else {
            return AnalysisResult(phase: phase,
                                  kneeAngle: nil,
                                  repCount: repCount,
                                  newFeedback: nil,
                                  isBodyVisible: bodyVisible)
        }

        var feedback: Feedback?
        let previous = previousKneeAngle ?? kneeAngle
        previousKneeAngle = kneeAngle

        switch phase {
        case .standing:
            if kneeAngle < standingThreshold, kneeAngle < previous {
                phase = .descending
                minKneeAngleInRep = kneeAngle
                issuesThisRep.removeAll()
            }

        case .descending:
            minKneeAngleInRep = min(minKneeAngleInRep, kneeAngle)
            if kneeAngle < bottomThreshold {
                phase = .bottom
            } else if kneeAngle > standingThreshold {
                phase = .standing // Aborted the descent without a real squat.
            }
            feedback = movementFeedback(pose: pose, kneeAngle: kneeAngle)

        case .bottom:
            minKneeAngleInRep = min(minKneeAngleInRep, kneeAngle)
            if kneeAngle > minKneeAngleInRep + ascentHysteresis {
                phase = .ascending
            }
            feedback = movementFeedback(pose: pose, kneeAngle: kneeAngle)

        case .ascending:
            minKneeAngleInRep = min(minKneeAngleInRep, kneeAngle)
            if kneeAngle > standingThreshold {
                phase = .standing
                repCount += 1
                feedback = repSummary()
            } else {
                feedback = movementFeedback(pose: pose, kneeAngle: kneeAngle)
            }
        }

        return AnalysisResult(phase: phase,
                              kneeAngle: kneeAngle,
                              repCount: repCount,
                              newFeedback: feedback,
                              isBodyVisible: bodyVisible)
    }

    mutating func reset() {
        phase = .standing
        repCount = 0
        previousKneeAngle = nil
        minKneeAngleInRep = 180
        issuesThisRep.removeAll()
    }

    // MARK: - Form rules

    /// Rules checked continuously while the user is in motion.
    /// Each fires at most once per rep so feedback doesn't spam.
    private mutating func movementFeedback(pose: DetectedPose, kneeAngle: Double) -> Feedback? {
        if kneeAngle < overFlexionAngle, issuesThisRep.insert("depth").inserted {
            return Feedback(message: "Коліна занадто глибоко зігнуті. Зменши глибину або контролюй рух.",
                            severity: .error)
        }

        if let ratio = kneeSeparationRatio(of: pose),
           ratio < kneeValgusRatio,
           kneeAngle < ruleMaxKneeAngle,
           issuesThisRep.insert("valgus").inserted {
            return Feedback(message: "Коліна завалюються всередину. Розводь їх назовні.",
                            severity: .error)
        }

        if let ratio = kneeSeparationRatio(of: pose),
           ratio > kneeTooWideRatio,
           kneeAngle < ruleMaxKneeAngle,
           issuesThisRep.insert("wideKnees").inserted {
            return Feedback(message: "Коліна занадто розведені. Тримай їх над стопами.",
                            severity: .warning)
        }

        return nil
    }

    /// Summary shown when a rep completes (back to standing).
    private mutating func repSummary() -> Feedback? {
        if minKneeAngleInRep > insufficientDepthAngle, issuesThisRep.isEmpty {
            return Feedback(message: "Присідай глибше — намагайся, щоб стегна були паралельні підлозі.",
                            severity: .warning)
        }
        return nil
    }

    // MARK: - Metrics

    /// Knee angle (hip–knee–ankle), averaged over both legs.
    private func kneeAngle(of pose: DetectedPose) -> Double? {
        let sides: [BodySide] = [.left, .right]
        let angles = sides.compactMap { angle(forLegOf: $0, in: pose) }
        guard !angles.isEmpty else { return nil }
        return angles.reduce(0, +) / Double(angles.count)
    }

    private func angle(forLegOf side: BodySide, in pose: DetectedPose) -> Double? {
        let (hip, knee, ankle) = PoseOrientation.legChain(for: side)
        guard let h = pose[hip], let k = pose[knee], let a = pose[ankle] else { return nil }
        return AngleMath.angle(h, vertex: k, a)
    }

    /// Knee separation relative to ankle separation.
    private func kneeSeparationRatio(of pose: DetectedPose) -> Double? {
        guard
            let leftKnee = pose[.leftKnee], let rightKnee = pose[.rightKnee],
            let leftAnkle = pose[.leftAnkle], let rightAnkle = pose[.rightAnkle]
        else { return nil }

        let ankleSeparation = AngleMath.distance(leftAnkle, rightAnkle)
        guard ankleSeparation > 0.01 else { return nil }
        return AngleMath.distance(leftKnee, rightKnee) / ankleSeparation
    }
}
