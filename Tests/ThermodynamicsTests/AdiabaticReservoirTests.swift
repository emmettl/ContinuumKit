import Foundation
import Testing
import Thermodynamics

@Suite("Sealed adiabatic reservoir")
struct AdiabaticReservoirTests {
  @Test("Integer-exponent golden states, signed work and reversible composition")
  func goldenStates() throws {
    let law = try AdiabaticReservoir(referenceVolume: 2, referenceEnergy: 5, heatCapacityRatio: 2)
    let expanded = try law.state(atVolume: 4)
    let compressed = try law.state(atVolume: 1)
    #expect(expanded.energy == 2.5 && expanded.pressure == 0.625)
    #expect(compressed.energy == 10 && compressed.pressure == 10)
    #expect(abs(try law.work(fromVolume: 2, toVolume: 4) - 2.5) < 1e-14)
    #expect(abs(try law.work(fromVolume: 4, toVolume: 1) + 7.5) < 1e-14)
    let composed = try law.work(fromVolume: 2, toVolume: 4) + law.work(fromVolume: 4, toVolume: 1)
    #expect(abs(composed - (try law.work(fromVolume: 2, toVolume: 1))) < 1e-14)
    #expect(try law.work(fromVolume: 2, toVolume: 2) == 0)
  }

  @Test("The five-thirds eightfold expansion has quarter energy")
  func rationalExponent() throws {
    let law = try AdiabaticReservoir(
      referenceVolume: 1, referenceEnergy: 8, heatCapacityRatio: 5.0 / 3)
    let state = try law.state(atVolume: 8)
    #expect(abs(state.energy - 2) < 2e-15)
    #expect(abs(state.pressure - 1.0 / 6) < 3e-16)
    #expect(abs(try law.work(fromVolume: 1, toVolume: 8) - 6) < 3e-15)
  }

  @Test("Pressure is the negative energy gradient, with central-difference refinement")
  func potentialGradient() throws {
    for gamma in [1.01, 1.4, 5.0 / 3, 2] {
      let law = try AdiabaticReservoir(
        referenceVolume: 1, referenceEnergy: 12, heatCapacityRatio: gamma)
      let v = 1.7
      let pressure = try law.state(atVolume: v).pressure
      var errors: [Double] = []
      for h in [0.01, 0.005, 0.0025] {
        let derivative =
          try -(law.state(atVolume: v + h).energy - law.state(atVolume: v - h).energy) / (2 * h)
        errors.append(abs(derivative / pressure - 1))
      }
      #expect(errors[2] < errors[1] && errors[1] < errors[0])
      #expect(errors[0] / errors[1] > 3.9 && errors[1] / errors[2] > 3.9)
    }
  }

  @Test("Independent Simpson pressure integration agrees with signed energy transfer")
  func integratedWork() throws {
    let law = try AdiabaticReservoir(referenceVolume: 1, referenceEnergy: 12)
    for end in [0.9, 2.0] {
      let n = 512
      let delta = (end - 1) / Double(n)
      var integral = 0.0
      for i in 0...n {
        let weight = i == 0 || i == n ? 1.0 : i % 2 == 0 ? 2.0 : 4.0
        integral += weight * (try law.state(atVolume: 1 + Double(i) * delta).pressure)
      }
      integral *= delta / 3
      #expect(abs(integral - (try law.work(fromVolume: 1, toVolume: end))) < 1e-10)
    }
  }

  @Test("Tiny volume changes retain their work without subtractive cancellation")
  func smallWork() throws {
    let law = try AdiabaticReservoir(referenceVolume: 1, referenceEnergy: 5, heatCapacityRatio: 2)
    let end = 1 + 1e-12
    let reference = 5 * (end - 1) / end
    #expect(abs((try law.work(fromVolume: 1, toVolume: end)) / reference - 1) < 1e-14)
  }

  @Test("An empty reservoir stays empty under expansion and compression")
  func empty() throws {
    let law = try AdiabaticReservoir(referenceVolume: 1, referenceEnergy: 0)
    for volume in [1e-100, 0.5, 1, 2, 1e100] {
      let state = try law.state(atVolume: volume)
      #expect(state.energy == 0 && state.pressure == 0)
      #expect(try law.work(fromVolume: 1, toVolume: volume) == 0)
    }
  }

  @Test("Invalid references, invalid volumes and unrepresentable states fail explicitly")
  func failures() throws {
    for v in [0.0, -1, .nan, .infinity] {
      #expect(throws: AdiabaticReservoir.Failure.self) {
        try AdiabaticReservoir(referenceVolume: v, referenceEnergy: 1)
      }
    }
    for e in [-1.0, .nan, .infinity] {
      #expect(throws: AdiabaticReservoir.Failure.self) {
        try AdiabaticReservoir(referenceVolume: 1, referenceEnergy: e)
      }
    }
    for g in [1.0, 0.5, .nan, .infinity] {
      #expect(throws: AdiabaticReservoir.Failure.self) {
        try AdiabaticReservoir(referenceVolume: 1, referenceEnergy: 1, heatCapacityRatio: g)
      }
    }
    let law = try AdiabaticReservoir(referenceVolume: 1, referenceEnergy: 12)
    for v in [0.0, -1, .nan, .infinity, Double.leastNonzeroMagnitude] {
      #expect(throws: AdiabaticReservoir.Failure.self) { try law.state(atVolume: v) }
      #expect(throws: AdiabaticReservoir.Failure.self) { try law.work(fromVolume: v, toVolume: 1) }
    }
  }
}
