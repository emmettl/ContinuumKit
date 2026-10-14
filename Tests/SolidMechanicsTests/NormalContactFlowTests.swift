import SolidMechanics
import Testing
import Foundation

@Suite struct NormalContactFlowTests {
    @Test func originalIndependentEventImpulseAndEnergyStudy() throws {
        try NormalContactVerification.run()
    }
    @Test func harmonicCompressedStateAndComposition() {
        let k=49.0, inverseMass=1.0, omega=7.0
        for gap in [-0.1,-0.03] { for velocity in [-0.5,0,0.5] {
            let t=0.01
            let q=NormalContactFlow.advance(gap:gap,relativeVelocity:velocity,stiffness:k,inverseEffectiveMass:inverseMass,duration:t)
            let expectedGap=gap*cos(omega*t)+velocity*sin(omega*t)/omega
            let expectedVelocity=velocity*cos(omega*t)-omega*gap*sin(omega*t)
            #expect(abs(q.gap-expectedGap)<1e-15)
            #expect(abs(q.relativeVelocity-expectedVelocity)<1e-15)
            #expect(abs(q.impulse-(expectedVelocity-velocity))<1e-15)
            let first=NormalContactFlow.advance(gap:gap,relativeVelocity:velocity,stiffness:k,inverseEffectiveMass:inverseMass,duration:t*0.37)
            let second=NormalContactFlow.advance(gap:first.gap,relativeVelocity:first.relativeVelocity,stiffness:k,inverseEffectiveMass:inverseMass,duration:t*0.63)
            #expect(abs(second.gap-q.gap)<1e-15)
            #expect(abs(second.relativeVelocity-q.relativeVelocity)<1e-15)
            #expect(abs(first.impulse+second.impulse-q.impulse)<1e-15)
        }}
    }
    @Test func entryAtEndAndZeroDuration() {
        let entry=NormalContactFlow.advance(gap:0.2,relativeVelocity:-2,stiffness:100,inverseEffectiveMass:1,duration:0.1)
        #expect(entry.gap==0 && entry.relativeVelocity == -2 && entry.impulse==0 && entry.contactDuration==0)
        let initial=NormalContactFlow.advance(gap:-0.2,relativeVelocity:-2,stiffness:100,inverseEffectiveMass:1,duration:0)
        #expect(initial.gap == -0.2 && initial.relativeVelocity == -2 && initial.impulse==0 && initial.contactDuration==0)
    }
}
