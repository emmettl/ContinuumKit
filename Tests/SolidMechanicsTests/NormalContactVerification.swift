import SolidMechanics
import Foundation
enum NormalContactVerification {
    static func check(_ ok:Bool,_ message:String) throws { if !ok { throw NSError(domain:"NormalContactStudy",code:1,userInfo:[NSLocalizedDescriptionKey:message]) } }
    static func run() throws {
        let k=6400.0,w=1/0.00002+1/0.000256,omega=sqrt(k*w)
        let duration=0.01,initialGap=0.001,initialVelocity = -8.0
        let result=NormalContactFlow.advance(gap:initialGap,relativeVelocity:initialVelocity,stiffness:k,inverseEffectiveMass:w,duration:duration)
        let entry=initialGap/8,contact=Double.pi/omega,expectedGap=8*(duration-entry-contact)
        try check(abs(result.gap-expectedGap)<1e-14 && abs(result.relativeVelocity-8)<1e-12 && abs(result.contactDuration-contact)<1e-14,"Independent elastic contact event solution")
        let initialEnergy=NormalContactFlow.energy(gap:initialGap,relativeVelocity:initialVelocity,stiffness:k,inverseEffectiveMass:w)
        let finalEnergy=NormalContactFlow.energy(gap:result.gap,relativeVelocity:result.relativeVelocity,stiffness:k,inverseEffectiveMass:w)
        try check(abs(initialEnergy-finalEnergy)/initialEnergy<1e-14,"Exact contact energy")
        // Arbitrary subdivisions must reproduce a single long step, including entry and release.
        var gap=initialGap,v=initialVelocity
        for fraction in [0.013,0.027,0.041,0.113,0.206,0.6] {
            let next=NormalContactFlow.advance(gap:gap,relativeVelocity:v,stiffness:k,inverseEffectiveMass:w,duration:duration*fraction)
            gap=next.gap;v=next.relativeVelocity
        }
        try check(abs(gap-result.gap)<1e-14 && abs(v-result.relativeVelocity)<1e-12,"Contact flow composition")
        let turning=NormalContactFlow.advance(gap:0,relativeVelocity:-8,stiffness:k,inverseEffectiveMass:w,duration:Double.pi/(2*omega))
        try check(abs(turning.gap+8/omega)<1e-14 && abs(turning.relativeVelocity)<1e-12,"Analytic maximum compression")
        let separating=NormalContactFlow.advance(gap:0.001,relativeVelocity:2,stiffness:k,inverseEffectiveMass:w,duration:duration)
        try check(separating.impulse==0 && abs(separating.gap-0.021)<1e-14,"No attraction")
        let compressed=NormalContactFlow.advance(gap:-0.0002,relativeVelocity:1,stiffness:k,inverseEffectiveMass:w,duration:duration)
        let e0=NormalContactFlow.energy(gap:-0.0002,relativeVelocity:1,stiffness:k,inverseEffectiveMass:w)
        let e1=NormalContactFlow.energy(gap:compressed.gap,relativeVelocity:compressed.relativeVelocity,stiffness:k,inverseEffectiveMass:w)
        try check(abs(e1-e0)/e0<1e-14 && compressed.gap>0,"Compressed release accounting")
        // Transfer the relative impulse to two finite masses; centre-of-mass momentum is unchanged.
        let a=0.00002,b=0.000256,va = -8.0,vb=0.0,j=result.impulse
        let finalA=va+j/a,finalB=vb-j/b
        try check(abs(a*va+b*vb-a*finalA-b*finalB)<1e-15 && abs((finalA-finalB)-result.relativeVelocity)<1e-12,"Effective-mass impulse transfer")
        var maximumResidual=0.0
        for stiffness in [100.0,6400,1_000_000] { for g in [-0.001,0,0.001] { for speed in [-8.0,-1,0,1,8] {
            let sample=NormalContactFlow.advance(gap:g,relativeVelocity:speed,stiffness:stiffness,inverseEffectiveMass:w,duration:0.0037)
            let before=NormalContactFlow.energy(gap:g,relativeVelocity:speed,stiffness:stiffness,inverseEffectiveMass:w)
            let after=NormalContactFlow.energy(gap:sample.gap,relativeVelocity:sample.relativeVelocity,stiffness:stiffness,inverseEffectiveMass:w)
            maximumResidual=max(maximumResidual,abs(after-before)/max(before,1e-20))
        }}}
        try check(maximumResidual<1e-12,"Contact stiffness/state sweep")
        print("contact_duration_s=\(contact) max_compression_m=\(8/omega) maximum_relative_energy_residual=\(maximumResidual) long_step_s=\(duration)")
        print("PASS exact normal contact: independent entry/release, compression, flow composition, no attraction, impulse transfer and stiffness/state energy sweep")
    }
}
