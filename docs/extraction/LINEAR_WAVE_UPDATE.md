# Linear wave update: proposed contract and bounded extraction

Design checkpoint: 9 October 2026. This specifies a future move; no solver has moved,
no SwiftPM product is added, and `0.1.0-alpha.4` remains the latest release. Names and
signatures below are proposed. Implement and verify each tranche before committing
to a public API.

The first reusable unit is RoomCAD's **source-free masked-grid complete step**, not
AcousticCore. A CPU product, provisionally `LinearAcoustics`, owns checked grid/state
types and serial evolution. A separate `LinearAcousticsMetal` product can later own
the two update kernels and resident device state. Neither imports an application,
scene target, renderer, audio framework or room geometry. Independent references
remain in `BenchmarkSupport`; production code must not call its numerical oracles.

## Scope and numerical contract

Supported initially: a fixed uniform Cartesian 3D grid, constant sound speed and
density, Float32 fields, a fixed binary active-cell mask, and fixed nonnegative
local real wall terms. Disconnected active regions and inactive padding are allowed.
Dimensions are at least two on each axis. Variable fluid properties, changing
topology, adaptive timesteps, forcing, bulk damping, nonlinear flow and moving walls
need separate contracts.

| Quantity | Representation and units |
| --- | --- |
| Grid dimensions | `nx`, `ny`, `nz`; `N = nx * ny * nz`; x fastest: `i + nx * (j + ny * k)` |
| Spacing, timestep | Positive finite Double metres and seconds, fixed for the lifetime of a stepper |
| Sound speed, density | Positive finite Double m/s and kg/m³ |
| `pressureOverDensity` | N Float32 values of ψ = physical pressure / density, m²/s², at cell centres |
| `velocityX/Y/Z` | Three N Float32 arrays, m/s; each slot is the cell's positive-axis face |
| Active cells | N bytes, exactly 0 or 1 |
| Boundary terms | 6N Float32 values in blocks −x, +x, −y, +y, −z, +z |

A boundary value of exactly −1 denotes a link to an active neighbour. Each active
link must have reciprocal −1 entries at its two ends. All other active-cell faces
are closed and have finite β ≥ 0. Outer negative faces have no velocity slot and
are implicitly zero. Positive endpoints and links touching inactive cells have
stored velocity zero. Inactive pressure values are preserved, including finite
test sentinels; inactive boundary entries use −1 as unused padding. They are never
read as active links. Require at least one active cell.

RoomCAD prepares β from its impedance, spacing, timestep and area quadrature:
β = c Δt a / (2 ξ d). The shared model consumes the **prepared numbers**; it does
not select materials, derive ξ from statistical absorption, find surfaces or choose
normals. β is dimensionless and tied to this particular Δt. Changing Δt requires
rebuilding the descriptor and boundary terms, not rescaling hidden state.

Prepare coefficients once in the source's Double evaluation order, then round:
`k_a = Float(dt / d_a)` and `b_a = Float(c * c * dt / d_a)`. The velocity phase is
`u_a -= k_a * (ψ_neighbour - ψ_cell)` on active links. Preserve the original
subtraction expression when porting, rather than relying on algebraic equivalence.
The pressure phase sums Float32 divergence and closed wall terms in the order
−x, +x, −y, +y, −z, +z, then evaluates:

```text
ψ_new = ((1 - B) * ψ_old - divergence) / (1 + B)
B = sum of the cell's closed-face β values
```

The velocity phase must finish globally before the pressure phase starts. Keep
subtraction, multiplication, accumulation and division order in the first port.
CPU exact-history comparison is a gate on the same toolchain/build mode; Metal
comparison also retains its existing declared floating-point bounds. Do not promise
cross-toolchain bitwise equality or change thresholds to accommodate a port.

## State, clocks and proposed surface

Initial pressure is at caller epoch t₀; initial velocities are at t₀ − Δt/2.
Initialization is the caller's responsibility: no implicit half kick, density
conversion or source injection. At complete-step index n, pressure is at
t₀ + nΔt and velocities at t₀ + (n − 1/2)Δt. The first completed step therefore has
pressure at t₀ + Δt and velocities at t₀ + Δt/2. Absolute epoch stays with the caller.

Proposed public shape (a design sketch, not compilable declarations):

```swift
// LinearAcoustics
public struct PreparedWaveGrid {
    public init(
        dimensions: SIMD3<Int>, spacing: SIMD3<Double>,
        soundSpeed: Double, density: Double, timeStep: Double,
        activeCells: [UInt8], boundaryTerms: [Float]
    ) throws
    // Read-only dimensions, physical parameters and prepared coefficients.
}

public struct WaveInitialFields {
    public init(
        pressureOverDensity: [Float],
        velocityX: [Float], velocityY: [Float], velocityZ: [Float]
    )
}

public struct WaveSnapshot {
    public let pressureStepIndex: Int
    public let pressureOverDensity: [Float]
    public let velocityX: [Float], velocityY: [Float], velocityZ: [Float]
    // Read-only relative pressure/velocity times derived from index and Δt.
}

public final class CPUWaveStepper {
    public init(grid: PreparedWaveGrid, initialFields: WaveInitialFields) throws
    public func advance(steps: Int = 1) throws
    public func snapshot() throws -> WaveSnapshot
}

// LinearAcousticsMetal, later; explicitly requires a Metal device.
public final class MetalWaveStepper {
    public init(device: any MTLDevice,
                grid: PreparedWaveGrid, initialFields: WaveInitialFields) throws
    public func advance(steps: Int = 1) throws
    public func snapshot() throws -> WaveSnapshot
}
```

Grid data and fields have owned value semantics at construction; the implementation
must prevent later caller mutation or aliased buffers from changing its state.
Stepper buffers are private, separately owned and reused. A snapshot makes an
explicit copy; advancing must not allocate or copy full fields per step. Steppers
are single-owner, synchronous and not concurrently callable in the initial API.
No public unsafe mutable buffers, caller command encoders or async completion API
are needed for the first source-free benchmark consumer.

Zero steps is an identity. Reject negative step counts and logical-index overflow
before mutation. Successful `advance` returns only after all requested complete
steps. Input errors leave an existing state unchanged. A compute failure can leave
partly modified buffers: invalidate the stepper, report a typed error, and require
reconstruction from a caller checkpoint. Do not promise rollback, advance a clock
for an incomplete step, silently clamp fields or fall back to CPU on GPU failure.
Define finite-output detection and failure reporting in the implementation tranche;
snapshot must reject nonfinite output. Avoid an unadvertised O(N) GPU readback scan
on every step. Until a device-side check is specified, snapshot is the finite-output
check and successful command completion alone is not a finiteness claim.

Density is metadata for physical conversion and diagnostics; it must not be inserted
into the normalized-pressure update. Consumers needing pascals explicitly multiply
ψ by density. Existing physical-pressure benchmark adapters retain their conversion
and rounding order.

## Construction checks

Validate before allocating solver state or dispatching:

- Dimensions, N, 6N and byte counts cannot overflow. Keep the common checked layout
  within the Metal kernel's UInt32 index range (`6N <= UInt32.max`); validate actual
  host allocation limits separately.
- All physical parameters and prepared Float coefficients are finite and positive.
  Require the conservative multi-axis CFL squared `c² dt² Σ(1/d_a²) < 1`, and
  `Σ(Double(k_a) * Double(b_a)) < 1` for the rounded update coefficients. RoomCAD's
  safety factor and power-of-two/audio timestep choice remain app policy.
- Array lengths match N/6N; masks are binary; active links have reciprocal flags
  and valid neighbours. A closed face is never marked open to inactive padding or
  outside the grid. Closed coefficients are finite/nonnegative, and Float-ordered
  per-cell B and `1 + B` are finite.
- Initial fields are finite, and every stored closed/unused velocity slot is zero.
  Do not silently zero invalid inputs: the original kernels skip those writes and
  otherwise retain their contents.

Add independent invalid-input tests, including reciprocal flags, outer −1 faces,
overflow, NaN and closed-slot contamination. These checks are new wrapper behavior,
not evidence that the existing app constructors already reject every invalid case.

## CPU and Metal boundaries

The first CPU port uses serial iteration. RoomCAD currently chooses one slab below
4096 cells and up to sixteen otherwise; benchmark wrappers use one. A later threaded
CPU path must prove disjoint writes, a phase barrier and unchanged histories before
adoption. The optimized unmasked box CPU path has a different interior expression
and accumulation order. Leave it in RoomCAD; matching the differential equations
does not justify rerouting it through the masked implementation.

The Metal tranche ports only `waveVelocity` and `wavePressure`, with the same native
field layout. Upload initial state/grid once; keep buffers resident across steps;
read back only on explicit snapshot. Use separate ordered dispatches with verified
resource hazards. The source's Swift/Metal Grid has three UInt32 and six Float fields;
36-byte size/stride and 4-byte alignment are the expected ABI, to be measured and
tested on the actual mini along with field offsets and buffer bindings. Treat shader
resource packaging and clean consumer compilation as required gates. Retain MIT
attribution when moving kernel text out of the current embedded string.

The Metal product depends on the CPU product's shared types, but CPU model tests and
its clean consumer require no Metal device. Creating a device, compiling pipelines,
allocating resident buffers and reporting command failures are explicit backend
responsibilities. `waveInject`, `waveSample`, batch cancellation, trial timings,
GPU abandonment/fallback and response construction stay in RoomCAD for now.

## What existing evidence covers

The [source manifest](linear-wave-source.json) pins seven whole files and seven
bounded blocks. [Read-only verification](linear-wave-source-verification.json)
checks Git objects, not live files; it proves source identity, not extracted behavior.
Run `python3 Scripts/verify-wave-extraction-source.py --roomcad /path/to/RoomCAD
--edgerton /path/to/edgerton` to repeat it. Edgerton hashes are comparison-only.

| Existing evidence | Relationship to the candidate |
| --- | --- |
| Axial, normal boundary, rigid 3D and oblique box CPU adapters | Exercise the optimized box path; valuable model references, not direct masked CPU port parity |
| Masked boxes, rigid/absorbing cylinder, curved admittance and tilted pulse CPU adapters | Bind actual masked update blocks with serial execution |
| RoomCAD Metal source adapters | Bind actual update kernels; retain per-suite layout, clock and work checks |
| Extruded-layout audit and matched thin-mesh pulse | Verify RoomCAD's geometry preparation separately; full plan/mesh field/work parity does not transfer geometry ownership |
| Edgerton wave adapters | Separate 2D physical-pressure implementation; matched supported cases only |

The full RoomCAD mini checkpoint retained 222 existing wave histories, and the
thin-mesh checkpoint retained 24 pulse histories and twelve exact plan/mesh pairs;
see the manifest's run/source links and [extrusion audit](../benchmarks/EXTRUDED_LAYOUT.md).
The raw application reports remain private in Edgerton. Public Core retains its
independently authored references and aggregate findings. Existing independent
contracts and all-field/work thresholds remain immutable inputs to the port.

Use the established staggered modified-energy and trapezoidal wall-work references
in BenchmarkSupport; kinetic and pressure energies sampled at different clocks are
not a conserved ordinary energy. Do not add diagnostics to the production API until
their storage/clock contract is independently tested. Numerical convergence/source
parity do not establish measured room or material accuracy.

## Bounded implementation and adoption sequence

1. **CPU implementation.** Add the actual product with owned buffers, construction
   checks and a serial masked complete step. Port the three pinned CPU blocks with
   explicit adaptations recorded. Add independent rigid and dissipative fixed-grid
   tests, native fields/clock/inactive/closed-slot checks, zero-step/composition checks,
   and rounded-coefficient tests. Exercise an all-active 3D mode through this masked
   path; the older optimized-box adapter alone cannot cover it. Compare complete
   candidate histories with the pinned source wrapper without changing an oracle.
2. **CPU package gate.** Commit the candidate, run `Scripts/check.sh`, and exercise
   the product from a clean Git consumer without an app import or Metal device.
   Keep source bindings and candidate revision identifiable in every report.
3. **Separate Metal implementation.** Add only the two update kernels and synchronous
   resident-buffer stepper. On the physical mini check ABI, packaged resources,
   dispatch ordering, multiple-step clocks, command failure semantics and all native
   fields against CPU and independent references. A missing GPU is a required-test
   failure, never a passing CPU fallback.
4. **RoomCAD benchmark adoption.** Bind the exact candidate revision beside the
   retained original-source adapter. Re-run the applicable masked/curved/dissipative
   cases and all 24 tilted plan/mesh histories with unchanged independent references,
   full wall traces and global/patch work. Store complete app evidence privately.
5. **Separate application integration.** Design safe pressure/source writes and
   source/receiver Metal encoding before replacing a production loop. Preserve
   velocity → pressure → injection → sampling order, source scaling, microphone
   staggering, cancellation and buffer lifetimes. Check actual application outputs
   and full RoomCAD CI. Initially retain the optimized box path and its old gates.
6. **Release and deliberate pins.** Only after review, package/actual-app checks and
   release authorization, tag a tested version and update application dependencies.
   Do not retire source or mutate prior evidence merely because a new module exists.

The next bounded task is step 1, with step 2 as its completion gate. Actual source
extraction, Metal work, application refactoring and publication are subsequent tasks.

## Other consumers

Edgerton stores pressure in Pa on a 2D dense grid, with `(nx+1)*ny` x velocities and
`nx*(ny+1)` y velocities. It has explicit density arithmetic, a moving body force,
bulk exponential damping, probe extraction and colour rendering. A layout/rho
conversion alone cannot preserve its rounding or forced/damped model. A future
adapter needs an explicit 2D state/clock map, a separate force/damping contract,
actual GPU conformance and preserved application outputs. It is not part of the
first extraction and remains explicit about unsupported masks/impedance walls.

BombCAD's nonlinear compressible blast/air evolution is not covered by this constant
fluid linear update. Lower-level primitives may later be reusable under separately
verified contracts. A useful component can enter Core with one application consumer;
sharing with all three apps is not an extraction prerequisite.
