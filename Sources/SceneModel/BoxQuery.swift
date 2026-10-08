import simd

extension Box {
  /// The parameter interval where `origin + t * direction` lies in these closed bounds.
  ///
  /// Positions and bounds are in metres in the same frame; the direction need not be
  /// normalized. With a unit direction, `t` is a distance in metres. With `end - start`
  /// and `parameters: 0...1`, `t` is a segment fraction. Starting inside returns the
  /// supplied lower parameter. Faces, edges and corners count as intersections.
  ///
  /// A component with magnitude at most `parallelTolerance` is treated as zero.
  /// The tolerance is in direction-component units, not metres or an expanded box.
  /// The default tests exact parallelism. Applications own their tolerance choice.
  ///
  /// Returns nil for an empty intersection, nonfinite geometry/direction, zero
  /// direction, nonpositive box dimensions, invalid tolerance, or an entry parameter
  /// that cannot be represented as a finite Float. The interval may have an infinite
  /// upper endpoint when the exit exceeds Float's range. Arithmetic uses Float.
  public func intersection(
    origin: SIMD3<Float>, direction: SIMD3<Float>,
    parameters: ClosedRange<Float> = 0...Float.infinity, parallelTolerance: Float = 0
  ) -> ClosedRange<Float>? {
    guard parameters.lowerBound.isFinite, !parameters.upperBound.isNaN,
      parallelTolerance.isFinite, parallelTolerance >= 0,
      direction != .zero,
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
