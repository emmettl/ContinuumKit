import Foundation
import SolidMechanics
import FrozenContact
var count=0
for k in [100.0,6400,1_000_000] { for gap in [-0.001,0,0.001] { for v in [-8.0,-1,0,1,8] { for t in [0.0,0.000001,0.0037] {
    let w=1/0.00002+1/0.000256
    let a=NormalContactFlow.advance(gap:gap,relativeVelocity:v,stiffness:k,inverseEffectiveMass:w,duration:t)
    let b=TargetNormalContactSolver.advance(gap:gap,relativeVelocity:v,stiffness:k,inverseEffectiveMass:w,duration:t)
    precondition([a.gap,a.relativeVelocity,a.impulse,a.contactDuration].map(\.bitPattern)==[b.gap,b.relativeVelocity,b.impulse,b.contactDuration].map(\.bitPattern))
    let e=NormalContactFlow.energy(gap:a.gap,relativeVelocity:a.relativeVelocity,stiffness:k,inverseEffectiveMass:w)
    let original=TargetNormalContactSolver.energy(gap:b.gap,relativeVelocity:b.relativeVelocity,stiffness:k,inverseEffectiveMass:w)
    precondition(e.bitPattern==original.bitPattern)
    count += 1
}}}}
precondition(count==135)
print("PASS 135 public/frozen contact states: exact bits for gap, velocity, impulse, duration and energy; adoption deferred")
