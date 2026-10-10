# Gas packet conservation planning checkpoint

The [implemented candidate](PRESCRIBED_GAS_PACKETS.md) now follows this planning checkpoint.

The wall reference is released at alpha.13 and adopted in BombCAD. The next small
candidate is BombCAD's 104-line `FractionalGasTransport`, rather than its complete
Euler, moving-volume or rigid-body coupling systems. This records a bounded task;
no packet implementation or public API is added by this checkpoint.

## Frozen source and scope

Inspect source at BombCAD `8ec83cb524d1e745c0793106b0d78a7269131030`, path
`Sources/BlastCore/FractionalGasTransport.swift`, Git blob
`af65c142dbd6dfaffe8ccbb516c0b846d62c4086`, SHA-256
`9a3bccd54cd6448bb468ccd71e6d0f391ccd6f6f19f9661f6c250f2c9daa02a7`.
Retain its MIT attribution and an immutable original before extraction. Existing
application tests are evidence to inspect, alongside new independent references.

The operator carries extensive mass, momentum and total energy in prescribed gas
volumes. The caller supplies directed volume transfers and external wall impulse /
work on the gas. Frozen donor states prevent reusing incoming material in the same
update; aggregate outgoing volume cannot exceed the old donor volume. Topology,
volume trajectories, face construction, Riemann fluxes, reconstruction, timestep
selection, body dynamics and production Metal air evolution stay app-owned.

## Contract decisions before moving code

Specify SI units, impulse/work signs, array/cell identity, finite input requirements,
reserved zero storage lanes and dry/wet behavior. Explain how density/velocity/pressure
convert to extensive state and how the caloric ratio is supplied; distinguish this
from the current step's positive-internal-energy check. Define invalid graph/state,
excessive outflow, invalid wall exchange and occupied-dry-cell failures.

The source's dry-cell cleanup permits a bounded floating-point residual before
zeroing the packet. Record that budget explicitly, including signed-zero and operation
order behavior. Do not describe cleanup as exact conservation or silently widen its
threshold. Examine overflow/underflow and intermediate representability; any deliberate
adaptation needs a separate independent test and adoption decision. Choose a minimal
public representation after these contracts are written, without exposing application
geometry or introducing a speculative general flow abstraction.

## Independent core acceptance

- Closed graphs with analytically known packet mixing, simultaneous transfer and
  frozen-donor controls must preserve mass/momentum/energy within declared rounding
  budgets. Vary cell volume and transfer fraction, including zero/full donation.
- Known external impulses and gas work must change the corresponding extensive
  quantities exactly as specified. Nonphysical trial states must reject transactionally.
- Dry/wet transitions, empty graphs, invalid indices, self transfers, non-finite inputs,
  occupied dry cells and excessive aggregate outflow need direct contract tests.
- Compare complete original/shared states, values and bits over an enumerated case
  tree. Keep regression conformance separate from the analytic references; retain
  every cell and all supplied graph/exchange inputs.
- A clean optimized public CompressibleFlow consumer must require no application,
  renderer or Metal linkage. Retain its Git pin, source identity and complete reports
  on both Macs, with completeness/rejection controls and unchanged existing core gates.

Publish only after exact-tag verification. BombCAD adoption then replaces its local
packet calculation through a bounded adapter and separately verifies all affected
piston, remap, reservoir, moving-gas and full-app contracts. The wall release and
previous application evidence remain immutable. Euler fluxes and moving geometry
follow as separate decisions; empirical gas/blast validation is outside this task.
