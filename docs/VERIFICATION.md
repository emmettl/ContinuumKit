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

Current CI builds the CAD foundations, runs 141 tests across CAD foundations, response
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

Project-container diagnostics independently check malformed syntax and invalid UTF-8 in
`scene.json`, `settings.json` and `view.json` through validation, construction, native file
wrappers and bounded disk reads. Those failures use `ProjectFileError` and identify the
payload filename; failed reads preserve the on-disk bytes. Valid JSON arrays, nulls, numbers,
booleans and strings are rejected with an object-shape error. Payloads still require JSON
objects, and application codecs retain ownership of field and value validation. This change
does not alter the package schema or publish a new release.

Manifest diagnostics cover all six required fields, incorrect types, null metadata,
invalid asset identifiers, non-object roots, malformed JSON and invalid UTF-8 through both
native wrappers and bounded disk reads. Errors identify `manifest.json` and the coding path, including array
indices. Existing semantic messages and unsupported-version precedence remain covered;
an incomplete newer manifest reports its unsupported version before decoding other fields.

See [masked domains](benchmarks/MASKED_DOMAINS.md) for independent geometry, connectivity,
active-only field/energy and leakage contracts. This candidate does not alter release tags.

The [rigid cylinder candidate](benchmarks/CYLINDER.md) separates staircase spatial error
from continuous-time graph-reference checks, with ten independent tests and geometry gates.

The [curved admittance audit](benchmarks/CURVED_ADMITTANCE.md) has ten independent tests
and reports physical geometry gaps separately from numerical substep verification.

The [coupled absorbing cylinder](benchmarks/ABSORBING_CYLINDER.md) has ten independent
complex-mode, physical-work and dissipative-graph checks. Application conformance
requires actual CPU/Metal histories and all-step source wall pressures.

The [tilted pulse candidate](benchmarks/TILTED_PULSE.md) adds twelve independent
controls and explicitly separates causal plane-region accuracy from finite-domain
graph time/energy verification. Spatial gaps are never physical passes.

The [equivalent extrusion audit](benchmarks/EXTRUDED_LAYOUT.md) adds eight independent
Python geometry controls and a complete native layout contract. Assignment gaps
remain explicit; this audit does not run a wave update or publish a model release.

The unreleased [LinearAcoustics CPU candidate](extraction/LINEAR_WAVE_CPU.md) adds
seventeen independent contract/reference tests and a committed optimized consumer
that depends only on the CPU product and checks absence of Metal/UI binary links.
The existing all-product consumer also imports it; the total is now nine libraries.
Exact-block RoomCAD comparison is a separate read-only source-provenance gate.

The [Metal wave candidate](extraction/LINEAR_WAVE_METAL.md) adds eleven required
actual-device tests using the same independent all-field/time/work bounds as CPU,
an independent packaged-grid ABI probe, residency/multi-batch and injected failure
checks, plus a fetched optimized GPU consumer. CPU consumer linkage remains guarded.
