import simd
public enum TargetGeometryError: Error { case invalidDefinition }
enum TargetImplicitFaceContact {
    static func correctedGradient(old:[SIMD3<Double>],new:[SIMD3<Double>],midpointGradient:[SIMD3<Double>],energyChange:Double) -> [SIMD3<Double>] {
        let count=old.count,middle=(0..<old.count).map { (old[$0]+new[$0])/2 },delta=(0..<old.count).map { new[$0]-old[$0] }
        var g=midpointGradient
        let centre=middle.reduce(SIMD3<Double>.zero,+)/Double(count),drift=delta.reduce(SIMD3<Double>.zero,+)/Double(count)
        let x=middle.map { $0-centre },u=delta.map { $0-drift }
        var inertia=simd_double3x3(columns:(.zero,.zero,.zero)),angular=SIMD3<Double>.zero
        for i in 0..<count {
            inertia += matrix_identity_double3x3*simd_length_squared(x[i])-simd_double3x3(columns:(x[i]*x[i].x,x[i]*x[i].y,x[i]*x[i].z))
            angular += simd_cross(x[i],u[i])
        }
        let omega=simd_inverse(inertia)*angular
        let direction=(0..<count).map { u[$0]-simd_cross(omega,x[$0]) }
        let denominator=direction.reduce(0) { $0+simd_length_squared($1) }
        let scale=max(x.map { simd_length_squared($0) }.max()!,1e-24)
        if denominator>scale*1e-24 {
            let work=(0..<count).reduce(0.0) { $0+simd_dot(g[$1],delta[$1]) }
            let change=energyChange
            let correction=(change-work)/denominator
            for i in 0..<count { g[i] += correction*direction[i] }
        }
        return g
    }
}
