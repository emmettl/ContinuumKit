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

Current CI builds the CAD foundations, runs 102 tests across CAD foundations, response
interchange, thermodynamics and numerical benchmark contracts, and exercises all
eight public libraries from an isolated Git consumer compiled in release configuration.
Seven additional closed-box query checks cover analytic intersections, invalid input,
transform invariance and 400 segment comparisons against an independent face-plane oracle.
The consumer verifies archive disk round trips, OBJ reading, bounds/grid/camera/picking
and shader loading with actual offscreen pixels, and response conditioning plus WAV/JSON
disk round trips. Response conformance includes independently authored WAV bytes and
metadata/version/dimension rejection. Rendering requires a real device;
the imported render test no longer returns early on unavailable Metal.
The independent adiabatic and acoustic contracts are numerical verification.
The acoustic command emits analytic references; application source adapters own
solver conformance. These checks do not establish measured application accuracy.
CI uses the dedicated physical Mac mini runner. With `CONTINUUMKIT_REQUIRE_METAL=1`,
the check script compiles and dispatches a Metal kernel and verifies all 256 outputs.
This proves device access in the CI service session, not numerical model validity.
Future GPU suites run on that same declared device-capable runner.

See [masked domains](benchmarks/MASKED_DOMAINS.md) for independent geometry, connectivity,
active-only field/energy and leakage contracts. This candidate does not alter release tags.

The [rigid cylinder candidate](benchmarks/CYLINDER.md) separates staircase spatial error
from continuous-time graph-reference checks, with ten independent tests and geometry gates.
