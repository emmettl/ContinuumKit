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

`SceneModel` also has a candidate closed-box ray/segment query with independent
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
