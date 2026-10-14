import Foundation
import simd

/// Isotropic isochoric neo-Hookean shear plus logarithmic bulk energy.
/// W = G/2 (J^(-2/3) tr(FᵀF)-3) + K/2 log(J)^2, per rest volume.
/// A conservative element kernel; no integration, fracture, damping or calibration.
public struct TargetIsotropicTet:Sendable {
    public struct Response:Sendable {
        public let energy:Double,jacobian:Double
        public let forces:[SIMD3<Double>]
    }
    public enum ResponseLaw:String,Sendable {
        case isochoricNeoHookeanLogBulk,saintVenantKirchhoff,saintVenantKirchhoffLogBarrier
    }
    public let responseLaw:ResponseLaw
    public let barrierFraction:Double
    /// Fixed explicit candidate coefficient, retained in source region metadata.
    public var barrierModulus:Double {responseLaw == .saintVenantKirchhoffLogBarrier ? barrierFraction*bulk:0}
    public let shear:Double,bulk:Double,restVolume:Double
    private let inverseRest:simd_double3x3,shapeGradients:[SIMD3<Double>]
    struct FixedResponse:Sendable {
        let energy:Double,jacobian:Double
        let forces:(SIMD3<Double>,SIMD3<Double>,SIMD3<Double>,SIMD3<Double>)
    }
    /// Four inline corners for the implicit hot path; no element-sized arrays.
    struct Corners:Sendable {
        var a:SIMD3<Double>,b:SIMD3<Double>,c:SIMD3<Double>,d:SIMD3<Double>
        init(_ a:SIMD3<Double>,_ b:SIMD3<Double>,_ c:SIMD3<Double>,_ d:SIMD3<Double>) {self.a=a;self.b=b;self.c=c;self.d=d}
        subscript(_ i:Int)->SIMD3<Double> {
            get {switch i {case 0:return a;case 1:return b;case 2:return c;default:precondition(i==3);return d}}
            set {switch i {case 0:a=newValue;case 1:b=newValue;case 2:c=newValue;default:precondition(i==3);d=newValue}}
        }
    }
    public init(rest:[SIMD3<Double>],shear:Double,bulk:Double,responseLaw:ResponseLaw = .isochoricNeoHookeanLogBulk,barrierFraction:Double=0.05) throws {
        guard rest.count==4 && rest.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) && shear.isFinite && shear>0 && bulk.isFinite && bulk>0 else { throw TargetGeometryError.invalidDefinition }
        let matrix=simd_double3x3(columns:(rest[1]-rest[0],rest[2]-rest[0],rest[3]-rest[0])),determinant=simd_determinant(matrix)
        guard abs(determinant)>1e-18 else { throw TargetGeometryError.invalidDefinition }
        let inverse=simd_inverse(matrix),transpose=simd_transpose(inverse)
        guard barrierFraction.isFinite && barrierFraction>0 && barrierFraction<1 else {throw TargetGeometryError.invalidDefinition}
        self.responseLaw=responseLaw;self.barrierFraction=barrierFraction
        inverseRest=inverse;restVolume=abs(determinant)/6;self.shear=shear;self.bulk=bulk
        shapeGradients=[-(transpose.columns.0+transpose.columns.1+transpose.columns.2),transpose.columns.0,transpose.columns.1,transpose.columns.2]
    }
    var restGradients:[SIMD3<Double>] { shapeGradients }
    /// Frobenius operator-norm upper bound for dP/dF at this deformation.
    /// Triangle/Cauchy inequalities retain negative as well as positive modes.
    /// This is a bulk constitutive bound; contacts and finite-step motion differ.
    public func stressDifferentialNormBound(positions:[SIMD3<Double>]) throws -> Double {
        guard positions.count==4 else {throw TargetGeometryError.invalidDefinition}
        let f=simd_double3x3(columns:(positions[1]-positions[0],positions[2]-positions[0],positions[3]-positions[0]))*inverseRest,j=simd_determinant(f)
        guard j.isFinite && j>0 else {throw TargetGeometryError.invalidDefinition}
        if responseLaw != .isochoricNeoHookeanLogBulk {
            let c=simd_transpose(f)*f-matrix_identity_double3x3,lambda=bulk-2*shear/3-barrierModulus
            let trace=c.columns.0.x+c.columns.1.y+c.columns.2.z
            let second=shear*c+(lambda*trace/2)*matrix_identity_double3x3
            // Frobenius norms conservatively dominate spectral matrix norms;
            // absolute lambda retains negative as well as positive modes.
            var value=sqrt(simd_length_squared(second.columns.0)+simd_length_squared(second.columns.1)+simd_length_squared(second.columns.2))+(2*shear+3*abs(lambda))*(simd_length_squared(f.columns.0)+simd_length_squared(f.columns.1)+simd_length_squared(f.columns.2))
            if barrierModulus>0 {
                let a=simd_transpose(simd_inverse(f)),t=simd_length_squared(a.columns.0)+simd_length_squared(a.columns.1)+simd_length_squared(a.columns.2)
                value+=barrierModulus*(j+abs(j-1))*t
            }
            guard value.isFinite && value>0 else {throw TargetGeometryError.invalidDefinition}
            return value
        }
        let a=simd_transpose(simd_inverse(f))
        let s=simd_length_squared(f.columns.0)+simd_length_squared(f.columns.1)+simd_length_squared(f.columns.2)
        let t=simd_length_squared(a.columns.0)+simd_length_squared(a.columns.1)+simd_length_squared(a.columns.2)
        let value=shear*pow(j,-2.0/3.0)*(1+(4.0/3.0)*sqrt(s*t)+(5.0/9.0)*s*t)+bulk*(1+abs(log(j)))*t
        guard value.isFinite && value>0 else {throw TargetGeometryError.invalidDefinition}
        return value
    }
    /// Objective discrete gradient: exact finite-step work with zero net force/midpoint torque.
    public func discreteGradient(old:[SIMD3<Double>],new:[SIMD3<Double>]) throws -> [SIMD3<Double>] {
        guard old.count==4 && new.count==4 else { throw TargetGeometryError.invalidDefinition }
        let midpoint=zip(old,new).map { ($0+$1)/2 },middle=try evaluate(positions:midpoint)
        let change=try evaluate(positions:new).energy-evaluate(positions:old).energy
        return TargetImplicitFaceContact.correctedGradient(old:old,new:new,midpointGradient:middle.forces.map { -$0 },energyChange:change)
    }
    /// Same arithmetic and objective work correction as the retained array path.
    func discreteGradient(old:Corners,new:Corners) throws -> Corners {
        var middle=Corners(.zero,.zero,.zero,.zero),delta=middle
        for i in 0..<4 {middle[i]=(old[i]+new[i])/2;delta[i]=new[i]-old[i]}
        let response=try evaluate(middle.a,middle.b,middle.c,middle.d)
        let change=try evaluate(new.a,new.b,new.c,new.d).energy-evaluate(old.a,old.b,old.c,old.d).energy
        var g=Corners(-response.forces.0,-response.forces.1,-response.forces.2,-response.forces.3)
        var centre=SIMD3<Double>.zero,drift=centre
        for i in 0..<4 {centre+=middle[i];drift+=delta[i]}
        centre/=4;drift/=4
        var x=Corners(.zero,.zero,.zero,.zero),u=x
        var inertia=simd_double3x3(columns:(.zero,.zero,.zero)),angular=SIMD3<Double>.zero
        for i in 0..<4 {
            x[i]=middle[i]-centre;u[i]=delta[i]-drift
            let point=x[i]
            inertia += matrix_identity_double3x3*simd_length_squared(point)-simd_double3x3(columns:(point*point.x,point*point.y,point*point.z))
            angular += simd_cross(point,u[i])
        }
        let omega=simd_inverse(inertia)*angular
        var direction=Corners(.zero,.zero,.zero,.zero),denominator=0.0,scale=0.0
        for i in 0..<4 {direction[i]=u[i]-simd_cross(omega,x[i]);denominator+=simd_length_squared(direction[i]);scale=max(scale,simd_length_squared(x[i]))}
        scale=max(scale,1e-24)
        if denominator>scale*1e-24 {
            var work=0.0
            for i in 0..<4 {work+=simd_dot(g[i],delta[i])}
            let correction=(change-work)/denominator
            for i in 0..<4 {g[i]+=correction*direction[i]}
        }
        return g
    }
    public func evaluate(positions:[SIMD3<Double>]) throws -> Response {
        guard positions.count==4 else { throw TargetGeometryError.invalidDefinition }
        let response=try evaluate(positions[0],positions[1],positions[2],positions[3])
        return .init(energy:response.energy,jacobian:response.jacobian,forces:[response.forces.0,response.forces.1,response.forces.2,response.forces.3])
    }
    /// Read-only constitutive Cauchy stress, reconstructed from the same
    /// element forces and actual current basis. Contact, support and damage
    /// tractions are not included. Tension is positive; no failure is triggered.
    public func cauchyStress(positions:[SIMD3<Double>]) throws -> simd_double3x3 {
        let response=try evaluate(positions:positions)
        let basis=simd_double3x3(columns:(positions[1]-positions[0],positions[2]-positions[0],positions[3]-positions[0]))
        let forces=simd_double3x3(columns:(response.forces[1],response.forces[2],response.forces[3]))
        let stress=(-1/(restVolume*response.jacobian))*(forces*simd_transpose(basis))
        guard (0..<3).allSatisfy({i in (0..<3).allSatisfy {stress[i][$0].isFinite}}) else {throw TargetGeometryError.invalidDefinition}
        return stress
    }
    /// Exact directional derivative of the current forces. This reads the same
    /// hyperelastic law; it does not change integration or impose a rest-state
    /// stability estimate on a severely deformed element.
    public func forceDifferential(positions:[SIMD3<Double>],directions:[SIMD3<Double>]) throws -> [SIMD3<Double>] {
        guard positions.count==4 && directions.count==4 && (positions+directions).allSatisfy({ p in (0..<3).allSatisfy { p[$0].isFinite } }) else { throw TargetGeometryError.invalidDefinition }
        let f=simd_double3x3(columns:(positions[1]-positions[0],positions[2]-positions[0],positions[3]-positions[0]))*inverseRest
        let h=simd_double3x3(columns:(directions[1]-directions[0],directions[2]-directions[0],directions[3]-directions[0]))*inverseRest
        let j=simd_determinant(f)
        guard j.isFinite && j>0 else { throw TargetGeometryError.invalidDefinition }
        if responseLaw != .isochoricNeoHookeanLogBulk {
            let c=simd_transpose(f)*f-matrix_identity_double3x3,lambda=bulk-2*shear/3-barrierModulus
            let second=shear*c+(lambda*(c.columns.0.x+c.columns.1.y+c.columns.2.z)/2)*matrix_identity_double3x3
            let dc=simd_transpose(h)*f+simd_transpose(f)*h
            var differential=h*second+f*(shear*dc+(lambda*(dc.columns.0.x+dc.columns.1.y+dc.columns.2.z)/2)*matrix_identity_double3x3)
            if barrierModulus>0 {
                let a=simd_transpose(simd_inverse(f)),da = -a*simd_transpose(h)*a
                let trace=simd_dot(a.columns.0,h.columns.0)+simd_dot(a.columns.1,h.columns.1)+simd_dot(a.columns.2,h.columns.2)
                differential+=barrierModulus*(j*trace*a+(j-1)*da)
            }
            let forces=shapeGradients.map {-restVolume*(differential*$0)}
            guard forces.allSatisfy({p in (0..<3).allSatisfy {p[$0].isFinite}}) else {throw TargetGeometryError.invalidDefinition}
            return forces
        }
        let a=simd_transpose(simd_inverse(f)),da = -a*simd_transpose(h)*a
        let trace=simd_length_squared(f.columns.0)+simd_length_squared(f.columns.1)+simd_length_squared(f.columns.2)
        let logDerivative=simd_dot(a.columns.0,h.columns.0)+simd_dot(a.columns.1,h.columns.1)+simd_dot(a.columns.2,h.columns.2)
        let traceDerivative=2*(simd_dot(f.columns.0,h.columns.0)+simd_dot(f.columns.1,h.columns.1)+simd_dot(f.columns.2,h.columns.2))
        let base=f-(trace/3)*a
        let differential=shear*pow(j,-2.0/3.0)*(h-(traceDerivative/3)*a-(trace/3)*da-(2*logDerivative/3)*base)+bulk*(logDerivative*a+log(j)*da)
        let forces=shapeGradients.map { -restVolume*(differential*$0) }
        guard forces.allSatisfy({ p in (0..<3).allSatisfy { p[$0].isFinite } }) else { throw TargetGeometryError.invalidDefinition }
        return forces
    }
    /// Same arithmetic as the array entry point, without transient element arrays.
    func evaluate(_ p0:SIMD3<Double>,_ p1:SIMD3<Double>,_ p2:SIMD3<Double>,_ p3:SIMD3<Double>) throws ->FixedResponse {
        func finite(_ p:SIMD3<Double>)->Bool { p.x.isFinite && p.y.isFinite && p.z.isFinite }
        guard finite(p0) && finite(p1) && finite(p2) && finite(p3) else { throw TargetGeometryError.invalidDefinition }
        let spatial=simd_double3x3(columns:(p1-p0,p2-p0,p3-p0)),f=spatial*inverseRest,j=simd_determinant(f)
        guard j.isFinite && j>0 else { throw TargetGeometryError.invalidDefinition }
        if responseLaw != .isochoricNeoHookeanLogBulk {
            let c=simd_transpose(f)*f-matrix_identity_double3x3,lambda=bulk-2*shear/3-barrierModulus
            let trace=c.columns.0.x+c.columns.1.y+c.columns.2.z
            var stress=f*(shear*c+(lambda*trace/2)*matrix_identity_double3x3)
            var energy=restVolume*(shear/4*(simd_length_squared(c.columns.0)+simd_length_squared(c.columns.1)+simd_length_squared(c.columns.2))+lambda/8*trace*trace)
            if barrierModulus>0 {
                stress+=barrierModulus*(j-1)*simd_transpose(simd_inverse(f))
                let delta=j-1,logJ=abs(delta)<0.5 ? log1p(delta):log(j)
                energy+=restVolume*barrierModulus*(delta-logJ)
            }
            let forces=(-restVolume*(stress*shapeGradients[0]),-restVolume*(stress*shapeGradients[1]),-restVolume*(stress*shapeGradients[2]),-restVolume*(stress*shapeGradients[3]))
            guard energy.isFinite && finite(forces.0) && finite(forces.1) && finite(forces.2) && finite(forces.3) else {throw TargetGeometryError.invalidDefinition}
            return .init(energy:energy,jacobian:j,forces:forces)
        }
        let trace=simd_length_squared(f.columns.0)+simd_length_squared(f.columns.1)+simd_length_squared(f.columns.2),iso=pow(j,-2.0/3.0),logJ=log(j),inverseTranspose=simd_transpose(simd_inverse(f))
        let stress=shear*iso*(f-(trace/3)*inverseTranspose)+(bulk*logJ)*inverseTranspose
        let energy=restVolume*(0.5*shear*(iso*trace-3)+0.5*bulk*logJ*logJ)
        let forces=(-restVolume*(stress*shapeGradients[0]),-restVolume*(stress*shapeGradients[1]),-restVolume*(stress*shapeGradients[2]),-restVolume*(stress*shapeGradients[3]))
        guard energy.isFinite && finite(forces.0) && finite(forces.1) && finite(forces.2) && finite(forces.3) else { throw TargetGeometryError.invalidDefinition }
        return .init(energy:energy,jacobian:j,forces:forces)
    }
}
