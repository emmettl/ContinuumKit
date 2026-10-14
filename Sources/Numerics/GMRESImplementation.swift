#if canImport(simd)
import Foundation
import simd

/// Restarted left-preconditioned GMRES. Stores a bounded basis, not a global Jacobian.
enum GMRESImplementation {
    typealias Vector=[SIMD3<Double>]
    enum Error:Swift.Error { case breakdown,notConverged }
    static func dot(_ a:Vector,_ b:Vector) -> Double { a.indices.reduce(0) { $0+simd_dot(a[$1],b[$1]) } }
    static func norm(_ a:Vector) -> Double { sqrt(max(0,dot(a,a))) }
    static func solve(rhs:Vector,tolerance:Double,restart:Int=24,cycles:Int=4,action:(Vector)throws->Vector) throws -> (Vector,Int) {
        var x=Array(repeating:SIMD3<Double>.zero,count:rhs.count),iterations=0
        let width=min(restart,3*rhs.count)
        for _ in 0..<cycles {
            let ax=try action(x),r=rhs.indices.map { rhs[$0]-ax[$0] },beta=norm(r)
            if beta<=tolerance { return (x,iterations) }
            var basis=[r.map { $0/beta }],h=Array(repeating:Array(repeating:0.0,count:width),count:width+1)
            var cosine=Array(repeating:0.0,count:width),sine=cosine,g=Array(repeating:0.0,count:width+1),used=0
            g[0]=beta
            for column in 0..<width {
                var w=try action(basis[column])
                // Reorthogonalize to limit loss of the Krylov basis at tight Newton tolerances.
                for _ in 0..<2 { for row in 0...column {
                    let projection=dot(w,basis[row]);h[row][column] += projection
                    for i in w.indices { w[i] -= projection*basis[row][i] }
                } }
                let length=norm(w);h[column+1][column]=length
                basis.append(length>1e-20 ? w.map { $0/length }:Array(repeating:.zero,count:rhs.count))
                for row in 0..<column {
                    let a=h[row][column],b=h[row+1][column]
                    h[row][column]=cosine[row]*a+sine[row]*b
                    h[row+1][column] = -sine[row]*a+cosine[row]*b
                }
                let diagonal=h[column][column],below=h[column+1][column],divisor=hypot(diagonal,below)
                guard divisor.isFinite && divisor>1e-20 else { throw Error.breakdown }
                cosine[column]=diagonal/divisor;sine[column]=below/divisor
                h[column][column]=divisor;h[column+1][column]=0
                g[column+1] = -sine[column]*g[column];g[column] *= cosine[column]
                used=column+1;iterations += 1
                if abs(g[column+1])<=tolerance || length<=1e-20 { break }
            }
            var coefficients=Array(repeating:0.0,count:used)
            for row in stride(from:used-1,through:0,by:-1) {
                var value=g[row]
                for column in row+1..<used { value -= h[row][column]*coefficients[column] }
                guard abs(h[row][row])>1e-20 else { throw Error.breakdown }
                coefficients[row]=value/h[row][row]
            }
            for column in 0..<used { for i in x.indices { x[i] += coefficients[column]*basis[column][i] } }
            let actual=try action(x),residual=rhs.indices.map { rhs[$0]-actual[$0] }
            if norm(residual)<=5*tolerance { return (x,iterations) }
        }
        throw Error.notConverged
    }
}
#endif
