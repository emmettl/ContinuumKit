import simd
public func frozenInlineResponse(_ element:TargetIsotropicTet, _ points:[SIMD3<Double>]) throws -> (Double,Double,[SIMD3<Double>]) {
    let r=try element.evaluate(points[0],points[1],points[2],points[3])
    return (r.energy,r.jacobian,[r.forces.0,r.forces.1,r.forces.2,r.forces.3])
}
public func frozenInlineGradient(_ element:TargetIsotropicTet, _ old:[SIMD3<Double>], _ new:[SIMD3<Double>]) throws -> [SIMD3<Double>] {
    let a=TargetIsotropicTet.Corners(old[0],old[1],old[2],old[3]),b=TargetIsotropicTet.Corners(new[0],new[1],new[2],new[3])
    let g=try element.discreteGradient(old:a,new:b)
    return (0..<4).map {g[$0]}
}
