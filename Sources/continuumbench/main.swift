import BenchmarkSupport
import Foundation

if CommandLine.arguments.contains("tilted-pulse-reference") {
  try TiltedPulseCommand.runReference()
} else if CommandLine.arguments.contains("absorbing-cylinder-reference") {
  try AbsorbingCylinderCommand.runReference()
} else if CommandLine.arguments.contains("admittance-reference") {
  try AdmittanceCommand.runReference()
} else if CommandLine.arguments.contains("cylinder-reference") {
  try CylinderCommand.runReference()
} else if CommandLine.arguments.contains("masked-reference") {
  try MaskedModeCommand.runReference()
} else if CommandLine.arguments.contains("oblique-reference") {
  try ObliqueModeCommand.runReference()
} else if CommandLine.arguments.contains("rigid-3d-reference") {
  try RigidModeCommand.runReference()
} else if CommandLine.arguments.contains("boundary-reference") {
  try BoundaryCommand.runReference()
} else if CommandLine.arguments.contains("acoustic-reference") {
  try AcousticCommand.runReference()
} else {
  try AdiabaticCommand.run(
    model: "ContinuumKit.AdiabaticReservoir+trapezoidal-work",
    refinementMetric: "work", expectedOrder: 1.8...2.2,
    samples: AdiabaticBenchmark.reservoirSamples)

}
