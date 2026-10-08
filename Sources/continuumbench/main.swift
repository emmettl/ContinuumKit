import BenchmarkSupport

try AdiabaticCommand.run(
  model: "ContinuumKit.AdiabaticReservoir+trapezoidal-work",
  refinementMetric: "work", expectedOrder: 1.8...2.2,
  samples: AdiabaticBenchmark.reservoirSamples)
