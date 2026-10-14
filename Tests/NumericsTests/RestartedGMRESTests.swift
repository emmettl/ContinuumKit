#if canImport(simd)
import simd
import Testing
import Numerics

@Suite struct RestartedGMRESTests {
    static let truth = (0..<4).map { i in SIMD3<Double>(sin(Double(i+1)), cos(Double(i+2)), Double(i)*0.2-0.3) }
    static func nonsymmetric(_ vector: RestartedGMRES.Vector) -> RestartedGMRES.Vector {
        let flat = vector.flatMap { [$0.x,$0.y,$0.z] }
        let values = flat.indices.map { i in (1+0.3*Double(i))*flat[i]+0.2*flat[(i+1)%flat.count]-0.1*flat[(i+4)%flat.count] }
        return vector.indices.map { SIMD3(values[3*$0],values[3*$0+1],values[3*$0+2]) }
    }
    @Test func independentNonsymmetricRestartOracle() throws {
        let rhs = Self.nonsymmetric(Self.truth)
        let (solution, iterations) = try RestartedGMRES.solve(rhs: rhs, tolerance: 1e-11, restart: 2, cycles: 30, action: Self.nonsymmetric)
        #expect(iterations > 2)
        #expect(zip(solution,Self.truth).allSatisfy { simd_distance($0,$1)<1e-9 })
        let residual = zip(Self.nonsymmetric(solution),rhs).map(-)
        #expect(sqrt(residual.reduce(0) { $0+simd_dot($1,$1) }) <= 5e-11)
    }
    @Test func diagonalAndZeroReferences() throws {
        let truth=[SIMD3<Double>(1,-2,3)]
        let rhs=[SIMD3<Double>(2,-6,15)]
        let (x, iterations)=try RestartedGMRES.solve(rhs:rhs,tolerance:1e-12,action:{v in v.map { $0 * SIMD3(2,3,5) }})
        #expect(simd_distance(x[0],truth[0])<1e-12)
        #expect(iterations==3)
        let zero=try RestartedGMRES.solve(rhs:[.zero],tolerance:1e-12,action:{$0})
        #expect(zero.0==[.zero] && zero.1==0)
        let empty=try RestartedGMRES.solve(rhs:[],tolerance:1e-12,action:{$0})
        #expect(empty.0.isEmpty && empty.1==0)
    }
    @Test func inputOperatorAllocationAndFailureContracts() throws {
        for tolerance in [0.0,-1,.nan,.infinity,Double.greatestFiniteMagnitude] {
            #expect(throws: RestartedGMRES.SolverError.invalidInput) {
                try RestartedGMRES.solve(rhs:[SIMD3(1,2,3)],tolerance:tolerance,action:{$0})
            }
        }
        for restart in [0,-1,257,Int.max] {
            #expect(throws: RestartedGMRES.SolverError.invalidInput) {
                try RestartedGMRES.solve(rhs:[SIMD3(1,2,3)],tolerance:1e-12,restart:restart,action:{$0})
            }
        }
        for cycles in [0,-1,100_001,Int.max] {
            #expect(throws: RestartedGMRES.SolverError.invalidInput) {
                try RestartedGMRES.solve(rhs:[SIMD3(1,2,3)],tolerance:1e-12,cycles:cycles,action:{$0})
            }
        }
        for rhs in [[SIMD3<Double>(.nan,0,0)],[SIMD3<Double>(Double.greatestFiniteMagnitude,0,0)]] {
            #expect(throws: RestartedGMRES.SolverError.invalidInput) {
                try RestartedGMRES.solve(rhs:rhs,tolerance:1e-12,action:{$0})
            }
        }
        for output in [[],[SIMD3<Double>(.nan,0,0)],[SIMD3<Double>(Double.greatestFiniteMagnitude,0,0)]] {
            #expect(throws: RestartedGMRES.SolverError.invalidOperatorResult) {
                try RestartedGMRES.solve(rhs:[SIMD3(1,2,3)],tolerance:1e-12,action:{_ in output})
            }
        }
        #expect(throws: RestartedGMRES.SolverError.numericalBreakdown) {
            try RestartedGMRES.solve(rhs:[SIMD3(1,2,3)],tolerance:1e-12,action:{_ in [.zero]})
        }
        #expect(throws: RestartedGMRES.SolverError.notConverged) {
            try RestartedGMRES.solve(rhs:Self.nonsymmetric(Self.truth),tolerance:1e-15,restart:1,cycles:1,action:Self.nonsymmetric)
        }
        let oversized=Array(repeating:SIMD3<Double>.zero,count:RestartedGMRES.maximumVectorCount+1)
        #expect(throws: RestartedGMRES.SolverError.invalidInput) {
            try RestartedGMRES.solve(rhs:oversized,tolerance:1e-12,action:{$0})
        }
        let basis=Array(repeating:SIMD3<Double>.zero,count:RestartedGMRES.maximumBasisEntries/257+1)
        #expect(throws: RestartedGMRES.SolverError.invalidInput) {
            try RestartedGMRES.solve(rhs:basis,tolerance:1e-12,restart:256,action:{$0})
        }
        enum CallbackError: Error { case cancelled }
        #expect(throws: CallbackError.cancelled) {
            try RestartedGMRES.solve(rhs:[SIMD3(1,2,3)],tolerance:1e-12,action:{_ in throw CallbackError.cancelled})
        }
    }
}
#endif
