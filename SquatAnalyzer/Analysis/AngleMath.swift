import CoreGraphics
import Foundation

enum AngleMath {

    /// Angle in degrees at vertex B formed by points A–B–C, via the dot product.
    static func angle(_ a: CGPoint, vertex b: CGPoint, _ c: CGPoint) -> Double {
        let ba = CGVector(dx: a.x - b.x, dy: a.y - b.y)
        let bc = CGVector(dx: c.x - b.x, dy: c.y - b.y)

        let dot = ba.dx * bc.dx + ba.dy * bc.dy
        let magBA = sqrt(ba.dx * ba.dx + ba.dy * ba.dy)
        let magBC = sqrt(bc.dx * bc.dx + bc.dy * bc.dy)

        guard magBA > 0, magBC > 0 else { return 0 }

        let cosAngle = dot / (magBA * magBC)
        let clamped = min(1, max(-1, cosAngle))

        return acos(clamped) * 180 / .pi
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        hypot(a.x - b.x, a.y - b.y)
    }

    /// How far the torso (hip→shoulder) tilts from vertical. 0° = upright, larger = more forward lean.
    static func leanFromVertical(shoulder: CGPoint, hip: CGPoint) -> Double {
        let torso = CGVector(dx: shoulder.x - hip.x, dy: shoulder.y - hip.y)
        let verticalUp = CGVector(dx: 0, dy: -1)

        let magTorso = hypot(torso.dx, torso.dy)
        guard magTorso > 0 else { return 0 }

        let dot = torso.dx * verticalUp.dx + torso.dy * verticalUp.dy
        let cosAngle = min(1, max(-1, dot / magTorso))

        return acos(cosAngle) * 180 / .pi
    }
}
