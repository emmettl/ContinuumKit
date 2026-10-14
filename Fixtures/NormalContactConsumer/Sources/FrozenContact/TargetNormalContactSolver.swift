import Foundation

/// Exact frictionless normal penalty flow for a fixed contact direction and effective mass.
/// It resolves entry/release within a step. Changing mesh features/normals require a coupled scheme.
public enum TargetNormalContactSolver {
    public struct Result: Sendable {
        public let gap:Double,relativeVelocity:Double,impulse:Double
        public let contactDuration:Double
    }
    /// gap is positive outside; relativeVelocity < 0 closes the gap.
    /// inverseEffectiveMass is the sum of squared normal gradients divided by nodal masses.
    public static func advance(gap initialGap:Double,relativeVelocity initialVelocity:Double,
                               stiffness:Double,inverseEffectiveMass:Double,duration:Double) -> Result {
        precondition([initialGap,initialVelocity,stiffness,inverseEffectiveMass,duration].allSatisfy { $0.isFinite })
        precondition(stiffness>0 && inverseEffectiveMass>0 && duration>=0)
        let omega=sqrt(stiffness)*sqrt(inverseEffectiveMass)
        precondition(omega.isFinite && omega>0)
        var gap=initialGap,velocity=initialVelocity,remaining=duration,contactDuration=0.0
        if gap>=0 {
            guard velocity<0 else { return .init(gap:gap+velocity*duration,relativeVelocity:velocity,impulse:0,contactDuration:0) }
            let entry=gap/(-velocity)
            guard entry<remaining else { return .init(gap:gap+velocity*duration,relativeVelocity:velocity,impulse:0,contactDuration:0) }
            remaining -= entry;gap=0
        }
        // The compressed harmonic state leaves at phase zero with positive normal velocity.
        let phase=gap==0 ? -Double.pi:atan2(omega*gap,velocity)
        let exit = -phase/omega
        contactDuration=min(remaining,exit)
        let angle=omega*contactDuration,c=cos(angle),s=sin(angle)
        let newGap=gap*c+(velocity/omega)*s,newVelocity=velocity*c-omega*gap*s
        gap=newGap;velocity=newVelocity
        if remaining>=exit {
            // Compute the release speed from the invariant, avoiding cancellation at the zero crossing.
            velocity=hypot(initialVelocity,omega*min(initialGap,0));gap=velocity*(remaining-exit)
        }
        return .init(gap:gap,relativeVelocity:velocity,impulse:(velocity-initialVelocity)/inverseEffectiveMass,contactDuration:contactDuration)
    }
    public static func energy(gap:Double,relativeVelocity:Double,stiffness:Double,inverseEffectiveMass:Double) -> Double {
        0.5*relativeVelocity*relativeVelocity/inverseEffectiveMass+0.5*stiffness*pow(min(0,gap),2)
    }
}
