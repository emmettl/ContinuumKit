# Verification policy

Each model owns verification that can run without application-layer code.
Declare required capabilities so unsupported cases are reported explicitly.

- Fast correctness/conformance: independent analytic cases, invariants, conservation
  and invalid-input behavior. Add SwiftPM test targets when these cases exist.
- Convergence: independently refine space and time, check complete histories,
  amplitude/phase, boundary work, momentum and cost. Keep these out of fast CI.
- Physical validation: sourced measurements, provenance, parameter choices and
  stated applicability. Numerical conformance is not physical validation.

Suggested initial cases are travelling pulses, rigid-wall reflection and adiabatic
chamber expansion. Compare solvers only under matched assumptions. A compartment
reservoir is not required to pass a travelling-wave test.

Future benchmark results should include case/schema version, source revision,
solver configuration, units, device/toolchain, resolution, errors, budget residuals
and runtime in JSON, with CSV histories and reproducible comparison reports.
Reference solutions must be independent of the implementation under test.

Current CI checks the bootstrap build and a separate consumer of the committed
package. It contains no numerical or measured validation and does not fabricate
passing model tests. When test targets arrive, `Scripts/check.sh` runs `swift test`.
GPU suites need a declared device-capable runner; hosted scaffold CI proves builds,
not availability of a Metal device.
