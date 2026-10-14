import simd
import Numerics
import FrozenGMRES
let truth=(0..<4).map { i in SIMD3<Double>(sin(Double(i+1)),cos(Double(i+2)),Double(i)*0.2-0.3) }
func action(_ vector:[SIMD3<Double>]) -> [SIMD3<Double>] {
    let flat=vector.flatMap { [$0.x,$0.y,$0.z] }
    let values=flat.indices.map { i in (1+0.3*Double(i))*flat[i]+0.2*flat[(i+1)%flat.count]-0.1*flat[(i+4)%flat.count] }
    return vector.indices.map { SIMD3(values[3*$0],values[3*$0+1],values[3*$0+2]) }
}
for restart in [2,4,12,24] {
    let rhs=action(truth)
    let a=try RestartedGMRES.solve(rhs:rhs,tolerance:1e-11,restart:restart,cycles:30,action:action)
    let b=try TargetKrylov.solve(rhs:rhs,tolerance:1e-11,restart:restart,cycles:30,action:action)
    precondition(a.1==b.1)
    precondition(zip(a.0,b.0).allSatisfy { x,y in x.x.bitPattern==y.x.bitPattern && x.y.bitPattern==y.y.bitPattern && x.z.bitPattern==y.z.bitPattern })
    precondition(zip(a.0,truth).allSatisfy { simd_distance($0,$1)<1e-9 })
}
print("PASS public/original restarted GMRES: four restart widths, exact solution bits and iteration counts, independent manufactured truth; adoption deferred")
