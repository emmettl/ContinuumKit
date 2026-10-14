#if canImport(simd)
import simd

/// Bounded restarted GMRES using arrays of three-component Double vectors.
/// The supplied action is the complete operator (including any caller preconditioning).
/// Apple SIMD arithmetic is preserved from the independently checked source algorithm.
public enum RestartedGMRES {
    public typealias Vector = [SIMD3<Double>]
    public enum SolverError: Error { case invalidInput, invalidOperatorResult, numericalBreakdown, notConverged }
    public static let maximumVectorCount = 262_144
    public static let maximumRestart = 256
    public static let maximumBasisEntries = 1_048_576

    /// Absolute Euclidean residual contract: returned solutions have residual at most
    /// five times tolerance, matching the source's explicit post-restart acceptance.
    /// Empty RHS returns an empty vector. Operator failures propagate unchanged.
    public static func solve(rhs: Vector, tolerance: Double, restart: Int = 24, cycles: Int = 4,
                             action: (Vector) throws -> Vector) throws -> (Vector, Int) {
        guard rhs.count <= maximumVectorCount, tolerance.isFinite, tolerance > 0,
              (5 * tolerance).isFinite, (1...maximumRestart).contains(restart),
              (1...100_000).contains(cycles), finite(rhs) else { throw SolverError.invalidInput }
        let width = min(restart, 3 * rhs.count)
        guard rhs.count <= maximumBasisEntries / (width + 1), GMRESImplementation.norm(rhs).isFinite else {
            throw SolverError.invalidInput
        }
        func checkedAction(_ vector: Vector) throws -> Vector {
            guard vector.count == rhs.count, finite(vector), GMRESImplementation.norm(vector).isFinite else {
                throw SolverError.numericalBreakdown
            }
            let result = try action(vector)
            guard result.count == rhs.count, finite(result), GMRESImplementation.norm(result).isFinite else {
                throw SolverError.invalidOperatorResult
            }
            return result
        }
        do {
            return try GMRESImplementation.solve(rhs: rhs, tolerance: tolerance, restart: restart,
                                                 cycles: cycles, action: checkedAction)
        } catch GMRESImplementation.Error.breakdown { throw SolverError.numericalBreakdown }
        catch GMRESImplementation.Error.notConverged { throw SolverError.notConverged }
    }
    private static func finite(_ vector: Vector) -> Bool {
        vector.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }
    }
}
#endif
