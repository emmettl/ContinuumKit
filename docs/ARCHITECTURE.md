# Architecture and extraction

ContinuumKit follows the MotionStudies ownership pattern: a shared package with
explicit contracts and independent verification, consumed by independently released
applications. A clean consumer checks the distributable package boundary.

The [roadmap](../ROADMAP.md) sets out candidate products, extraction order and readiness
gates. It does not authorize migration now or create target/API commitments.

## Candidate areas

These are areas of responsibility, not empty targets or promised public APIs:

| Area | Responsibilities |
| --- | --- |
| Numerical primitives | Integration, interpolation, operators and error estimation |
| Models | Acoustics, gas thermodynamics and pressure/boundary work |
| Geometry | Meshes, boundary representation, spatial queries and coordinate conventions |
| Model loading | Import, validation, units and region mapping |
| Scene helpers | Camera controls, picking, rendering and inspection |
| Verification | Reference cases, conformance, convergence and result reporting |

Numerical and model modules must not import an application target or UI layer.
Geometry and model loading must be usable without constructing a renderer.
Platform-specific rendering and GPU implementations belong in explicit targets;
CPU verification must not accidentally acquire a Metal-device requirement.

## Released products

The five CAD foundations (`SceneModel`, `SceneView`, `SceneRender`, `GeometryImport`,
`DocumentKit`) are independently verified in this repository and adopted by both CAD
apps. Their original local copy is retired; see [CAD provenance](extraction/CAD_FOUNDATIONS.md).

`SceneModel` also has a released closed-box ray/segment query with independent
analytic and face-plane checks; see [contract and provenance](extraction/BOX_QUERIES.md).
Scene selection, ownership and overlap policy remain application responsibilities.

`ImpulseResponseKit` owns Foundation-only response metadata, float WAV interchange and
common conditioning. Its implementation is unchanged from RoomCAD, with independent
conformance and fetched-consumer checks; see [response provenance](extraction/IMPULSE_RESPONSE.md).

RoomCAD, BombCAD and Edgerton have independent repositories. Applications pin tested
releases and retain their integration checks. AcousticCore, audition, scenarios,
measured fixtures and application policy remain with their applications.

## Extraction gates

1. Identify the implemented behavior and actual consumers.
2. Specify units, coordinate frames, assumptions, limits and ownership of state.
3. Bring independent tests and reference cases with the component.
4. Verify the public product from a clean Git consumer.
5. Demonstrate preserved application results and record extraction provenance.
6. Release a tested version; update each application deliberately.

Specialized gel, concrete and room-acoustic policies remain with their applications
until a concrete reusable contract is established. Shared location alone does not
make different physical assumptions interchangeable.

## Linear-wave extraction history

The [proposed complete-step contract](extraction/LINEAR_WAVE_UPDATE.md) bounds the
next extraction to RoomCAD's source-free masked update. An owned serial CPU stepper
comes first; an explicit Metal backend follows after its own device/resource gates.
The source map pins the exact blocks and distinguishes optimized-box evidence from
masked-path evidence. Geometry/material preparation, injection/sampling, response
policy and application scheduling stay in RoomCAD. Edgerton's 2D physical-pressure,
force/damping model needs a separate adapter. No products or releases are added by
this design checkpoint.

The first [serial CPU implementation](extraction/LINEAR_WAVE_CPU.md) introduced the
framework-free `LinearAcoustics` product. CPU and Metal updates were released in
alpha.6, prepared forcing in alpha.7 and observations/lookahead in alpha.8. Production
application loop adoption remains subject to its own numerical and timing gates.

The separate [Metal wave backend](extraction/LINEAR_WAVE_METAL.md) owns resident
tracked buffers, synchronous complete-batch clocks and packaged source-free kernels.
Shared initial-field validation remains in the CPU module. Alpha.9 execution
adds system Dispatch for explicit synchronous slabs; CPU consumers still require no
Metal device or UI framework. Published alpha.8 retains its original serial implementation.

Released sparse source and receiver plans use the exact prepared grid identity.
Metal mappings also bind to the physical device; mutable output/field state stays
stepper-owned. Bounded histories retain backend arithmetic and complete native clocks.
Geometry, microphone patterns/mixing, longer history, cancellation and GPU abandonment
remain application-owned. See [alpha.8 publication proof](extraction/alpha8-release-verification.json).

The [explicit Metal wave context](extraction/METAL_WAVE_CONTEXT.md) separates immutable
compiled device pipelines from each single-owner run's queue, resident fields, staging
and clock. Callers can reuse pipelines across independent runs without global caching
or application scheduling inside the model. Production Metal adoption remains a
separate application gate.

RoomCAD's production masked CPU/GPU loops are now retired in favour of exact released
alpha.12, with canonical verification-only originals, immutable reconstruction and
complete two-host application evidence. App-owned selected-backend availability,
geometry, microphone mixing, cancellation and fresh CPU restart remain explicit.
The optimized box CPU and Edgerton's 2D force/damping contracts remain distinct.
See the [current inventory](INVENTORY.md#current-four-repository-checkpoint--10-october-2026)
for the next stable primitive and unresolved model gaps.

A [standalone planar ideal-gas wall reference](extraction/IDEAL_GAS_WALL.md) is released at alpha.13
and adopted in BombCAD after independent gas-law/representability tests, optimized
public CPU-only consumers and separate complete two-host application gates. It adds
no bulk transport, moving geometry or production blast backend.

The prescribed gas-packet candidate belongs to CompressibleFlow: immutable extensive
state and supplied transfer/impulse/work only. Its [contract](extraction/PRESCRIBED_GAS_PACKETS.md)
keeps constructor/view algebra distinct from checked advance, and documents the dry
cleanup budget. Geometry, fluxes, timesteps and coupled body policy remain app-owned.
