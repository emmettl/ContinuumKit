/// Stateless Double-precision queries of axis-aligned bounds in metres, z up.
/// No conversion to the persisted Float `Box` representation is performed.
public enum BoxQuery {
  /// The closed parameter interval inside `min...max` along `origin + t * direction`.
  /// Unit directions give distances in metres; `end - start` with `parameters: 0...1`
  /// gives segment fractions. Interior starts retain the supplied lower parameter.
  /// Faces, edges and corners count, including a zero-length interval.
  ///
  /// Components at most `parallelTolerance` in magnitude are classified as parallel.
  /// This tolerance has direction-component units and does not enlarge the bounds.
  /// Exact parallelism is the default; applications own tolerance and contact policy.
  ///
  /// Returns nil for nonfinite geometry/direction, zero direction, nonpositive
  /// dimensions, invalid tolerance/clipping, or an unrepresentable finite entry.
  /// The upper endpoint may be infinite. Arithmetic is Double, including subtraction;
  /// this is a bounded floating-point query, not an exact predicate or an overflow-safe
  /// large-coordinate geometry solver. Callers must not infer robust geometry from nil.
  public static func intersection(
    min: SIMD3<Double>, max: SIMD3<Double>, origin: SIMD3<Double>, direction: SIMD3<Double>,
    parameters: ClosedRange<Double> = 0...Double.infinity, parallelTolerance: Double = 0
  ) -> ClosedRange<Double>? {
    guard parameters.lowerBound.isFinite, !parameters.upperBound.isNaN,
      parallelTolerance.isFinite, parallelTolerance >= 0, direction != .zero,
      (0..<3).allSatisfy({
        origin[$0].isFinite && direction[$0].isFinite && min[$0].isFinite && max[$0].isFinite
          && min[$0] < max[$0]
      })
    else { return nil }
    var near = parameters.lowerBound
    var far = parameters.upperBound
    for axis in 0..<3 {
      if abs(direction[axis]) <= parallelTolerance {
        if origin[axis] < min[axis] || origin[axis] > max[axis] { return nil }
      } else {
        let a = (min[axis] - origin[axis]) / direction[axis]
        let b = (max[axis] - origin[axis]) / direction[axis]
        near = Swift.max(near, Swift.min(a, b))
        far = Swift.min(far, Swift.max(a, b))
        if far < near { return nil }
      }
    }
    return near.isFinite ? near...far : nil
  }
}
