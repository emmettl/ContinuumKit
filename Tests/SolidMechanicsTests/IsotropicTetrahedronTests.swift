import Foundation
import simd
import SolidMechanics
import Testing

@Suite struct IsotropicTetrahedronTests {
    let rest=[SIMD3<Double>.zero,SIMD3(0.01,0,0),SIMD3(0,0.01,0),SIMD3(0,0,0.01)]
    @Test func independentDiagonalReferencesAllLaws() throws {
        let text=try String(contentsOf:Bundle.module.resourceURL!.appendingPathComponent("Fixtures/IsotropicTet/reference.csv"),encoding:.utf8)
        for row in text.split(separator:"\n").dropFirst() {
            let c=row.split(separator:",").map(String.init)
            let law=IsotropicTetrahedron.ResponseLaw(rawValue:c[0])!
            let f=simd_double3x3(diagonal:SIMD3(Double(c[1])!,Double(c[2])!,Double(c[3])!))
            let element=try IsotropicTetrahedron(rest:rest,shear:5000,bulk:20000,responseLaw:law)
            let positions=rest.map {f*$0},response=try element.evaluate(positions:positions)
            #expect(abs(response.jacobian-Double(c[4])!)<1e-12)
            #expect(abs(response.energy/element.restVolume-Double(c[5])!)<1e-8)
            let stress=try element.cauchyStress(positions:positions)
            for i in 0..<3 { #expect(abs(stress[i][i]-Double(c[i+6])!)<1e-8) }
        }
    }
    @Test func energyDerivativeTangentObjectivityAndWorkAllLaws() throws {
        for law in [IsotropicTetrahedron.ResponseLaw.isochoricNeoHookeanLogBulk,.saintVenantKirchhoff,.saintVenantKirchhoffLogBarrier] {
            let element=try IsotropicTetrahedron(rest:rest,shear:5000,bulk:20000,responseLaw:law)
            var f=simd_double3x3(diagonal:SIMD3(1.05,0.97,1.01));f.columns.1.x=0.12
            let p=rest.map {f*$0},r=try element.evaluate(positions:p)
            #expect(simd_length(r.forces.reduce(.zero,+))<1e-12)
            #expect(simd_length(p.indices.reduce(SIMD3<Double>.zero) {$0+simd_cross(p[$1],r.forces[$1])})<1e-12)
            let direction=rest.enumerated().map {i,x in SIMD3<Double>(Double(i)*0.2,-Double(i)*0.1,0.3)}
            let derivative=try element.forceDifferential(positions:p,directions:direction)
            let epsilon=1e-8
            let plus=zip(p,direction).map {$0+epsilon*$1},minus=zip(p,direction).map {$0-epsilon*$1}
            let rp=try element.evaluate(positions:plus),rm=try element.evaluate(positions:minus)
            let exactWork = -zip(r.forces,direction).reduce(0) {$0+simd_dot($1.0,$1.1)}
            #expect(abs((rp.energy-rm.energy)/(2*epsilon)-exactWork)<1e-7)
            for i in 0..<4 { #expect(simd_distance((rp.forces[i]-rm.forces[i])/(2*epsilon),derivative[i])<1e-5) }
            let rotation=simd_quatd(angle:0.7,axis:simd_normalize(SIMD3<Double>(1,2,3)))
            let moved=try element.evaluate(positions:p.map {rotation.act($0)+SIMD3(0.02,-0.01,0.03)})
            #expect(abs(moved.energy-r.energy)<1e-15)
            #expect(zip(moved.forces,r.forces).allSatisfy {simd_distance($0,rotation.act($1))<1e-10})
            let q=simd_double3x3(rotation)
            let right=try element.evaluate(positions:rest.map {f*q*$0})
            #expect(abs(right.energy-r.energy)<1e-15)
            let next=p.enumerated().map {i,x in x+SIMD3<Double>(Double(i)*0.00001,-Double(i)*0.000005,0.000003)}
            let g=try element.discreteGradient(old:p,new:next)
            let change=try element.evaluate(positions:next).energy-r.energy
            #expect(abs(zip(g,zip(p,next)).reduce(0) {$0+simd_dot($1.0,$1.1.1-$1.1.0)}-change)<1e-15)
            #expect(simd_length(g.reduce(.zero,+))<1e-11)
            #expect(simd_length(p.indices.reduce(SIMD3<Double>.zero) {$0+simd_cross((p[$1]+next[$1])/2,g[$1])})<1e-12)
            let inline=try element.evaluate(p[0],p[1],p[2],p[3])
            #expect(inline.energy.bitPattern==r.energy.bitPattern)
            let a=IsotropicTetrahedron.Corners(p[0],p[1],p[2],p[3]),b=IsotropicTetrahedron.Corners(next[0],next[1],next[2],next[3])
            let inlineGradient=try element.discreteGradient(old:a,new:b)
            #expect((0..<4).allSatisfy {simd_distance(inlineGradient[$0],g[$0])<1e-11})
            let bound=try element.stressDifferentialNormBound(positions:p)
            #expect(bound.isFinite && bound>0)
            let restBasis=simd_double3x3(diagonal:SIMD3<Double>(repeating:0.01))
            for column in 0..<3 { for axis in 0..<3 {
                var h=simd_double3x3(columns:(.zero,.zero,.zero));h[column][axis]=1
                let df=try element.forceDifferential(positions:p,directions:rest.map {h*$0})
                let dP=(-1/element.restVolume)*simd_double3x3(columns:(df[1],df[2],df[3]))*simd_transpose(restBasis)
                let norm=sqrt(simd_length_squared(dP.columns.0)+simd_length_squared(dP.columns.1)+simd_length_squared(dP.columns.2))
                #expect(norm <= bound*(1+1e-12))
            }}
            let translated=try element.forceDifferential(positions:p,directions:Array(repeating:SIMD3(1,2,3),count:4))
            #expect(translated.allSatisfy {$0 == .zero})
        }
    }
    @Test func invalidDefinitionAndInversion() throws {
        #expect(throws:IsotropicTetrahedron.ElementError.invalidDefinition) {try IsotropicTetrahedron(rest:[],shear:5000,bulk:20000)}
        #expect(throws:IsotropicTetrahedron.ElementError.invalidDefinition) {try IsotropicTetrahedron(rest:Array(repeating:.zero,count:4),shear:5000,bulk:20000)}
        #expect(throws:IsotropicTetrahedron.ElementError.invalidDefinition) {try IsotropicTetrahedron(rest:rest,shear:0,bulk:20000)}
        #expect(throws:IsotropicTetrahedron.ElementError.invalidDefinition) {try IsotropicTetrahedron(rest:rest,shear:5000,bulk:20000,barrierFraction:1)}
        for law in [IsotropicTetrahedron.ResponseLaw.isochoricNeoHookeanLogBulk,.saintVenantKirchhoff,.saintVenantKirchhoffLogBarrier] {
            let element=try IsotropicTetrahedron(rest:rest,shear:5000,bulk:20000,responseLaw:law)
            #expect(throws:IsotropicTetrahedron.ElementError.invalidDefinition) {try element.evaluate(positions:rest.map {-$0})}
            #expect(throws:IsotropicTetrahedron.ElementError.invalidDefinition) {try element.evaluate(positions:Array(rest.dropLast()))}
        }
    }
}
