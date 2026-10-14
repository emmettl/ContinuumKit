import simd
import SolidMechanics
import FrozenTet
func bits(_ a:Double,_ b:Double) {precondition(a.bitPattern==b.bitPattern)}
func vectors(_ a:[SIMD3<Double>],_ b:[SIMD3<Double>]) {
    precondition(a.count==b.count)
    for (x,y) in zip(a,b) {for i in 0..<3 {bits(x[i],y[i])}}
}
let rest=[SIMD3<Double>.zero,SIMD3(0.01,0,0),SIMD3(0,0.01,0),SIMD3(0,0,0.01)]
var samples=0
for name in ["isochoricNeoHookeanLogBulk","saintVenantKirchhoff","saintVenantKirchhoffLogBarrier"] {
    let a=try IsotropicTetrahedron(rest:rest,shear:5000,bulk:20000,responseLaw:.init(rawValue:name)!)
    let b=try TargetIsotropicTet(rest:rest,shear:5000,bulk:20000,responseLaw:.init(rawValue:name)!)
    bits(a.restVolume,b.restVolume);bits(a.barrierModulus,b.barrierModulus)
    for scale in [0.8,1.0,1.2] {for shear in [0.0,0.12] {
        var f=simd_double3x3(diagonal:SIMD3<Double>(repeating:scale));f.columns.1.x=shear
        let p=rest.map {f*$0},q=p.enumerated().map {i,x in x+SIMD3<Double>(Double(i)*1e-5,-Double(i)*5e-6,3e-6)}
        let ra=try a.evaluate(positions:p),rb=try b.evaluate(positions:p)
        bits(ra.energy,rb.energy);bits(ra.jacobian,rb.jacobian);vectors(ra.forces,rb.forces)
        let sa=try a.cauchyStress(positions:p),sb=try b.cauchyStress(positions:p)
        vectors([sa.columns.0,sa.columns.1,sa.columns.2],[sb.columns.0,sb.columns.1,sb.columns.2])
        bits(try a.stressDifferentialNormBound(positions:p),try b.stressDifferentialNormBound(positions:p))
        let directions=rest.enumerated().map {i,x in SIMD3<Double>(Double(i)*0.2,-Double(i)*0.1,0.3)}
        vectors(try a.forceDifferential(positions:p,directions:directions),try b.forceDifferential(positions:p,directions:directions))
        vectors(try a.discreteGradient(old:p,new:q),try b.discreteGradient(old:p,new:q))
        let inline=try a.evaluate(p[0],p[1],p[2],p[3]),original=try frozenInlineResponse(b,p)
        bits(inline.energy,original.0);bits(inline.jacobian,original.1)
        vectors([inline.forces.0,inline.forces.1,inline.forces.2,inline.forces.3],original.2)
        let g=try a.discreteGradient(old:.init(p[0],p[1],p[2],p[3]),new:.init(q[0],q[1],q[2],q[3]))
        vectors((0..<4).map {g[$0]},try frozenInlineGradient(b,p,q))
        samples += 1
    }}
}
precondition(samples==18)
print("PASS 18 three-law public/frozen samples: exact energy, J, forces, Cauchy stress, tangent/bound and both array/inline work gradients; adoption deferred")
