import BenchmarkSupport
import Foundation

if CommandLine.arguments.contains("acoustic-reference") {
  try AcousticCommand.runReference()
} else {
  try AdiabaticCommand.run(
    model: "ContinuumKit.AdiabaticReservoir+trapezoidal-work",
    refinementMetric: "work", expectedOrder: 1.8...2.2,
    samples: AdiabaticBenchmark.reservoirSamples)

}
