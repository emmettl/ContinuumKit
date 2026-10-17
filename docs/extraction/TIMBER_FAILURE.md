# Timber failure: orthotropic damage and crushing

The `SolidMechanics` product exposes `TimberFailure`, a small-strain material point for timber
that breaks. It is new here, not moved from an application: BombCAD proposed it (2026-10-17,
under the sharing rule, Edgerton having parked its veneer work) and copies it into its GPU
shells in single precision, tested against this reference. It imports only Foundation.

## Contract

Moduli, strengths and stresses are in Pa, fracture energies in J/m², bands in m and work in
J/m³. The point works in its grain frame:
- **Strain:** (ε_L, ε_T, γ_LT) in the plane, engineering shear, then the shears through the
  thickness (γ_LZ, γ_TZ). L runs along the grain, T across it in the plane, Z along the normal.
- **Stress:** in the same order.
- **Rotation:** callers rotate into the frame. Combine with `OrthotropicPlaneStress`'s
  transform for a sheet frame.

**Elastic part.** Orthotropic plane stress with reciprocal ν_TL = ν_LT E_T/E_L, identical in
binary64 to `OrthotropicPlaneStress` at zero grain angle. Shear through the thickness takes G
along the grain and the rolling modulus across it.

**Failure.** Three brittle modes are judged on the effective (undamaged) stress, after
Sandhaas and van de Kuilen's Hashin-type criteria:

| Mode | Index | Softens |
|---|---|---|
| fibre | ⟨σ_L⟩ / f_t0 | σ_L in tension |
| splitting | √((⟨σ_T⟩/f_t90)² + (τ_LT² + τ_LZ²)/f_v²) | σ_T in tension, τ_LT, τ_LZ |
| rolling shear | \|τ_TZ\| / f_r | τ_TZ |

- **Softening:** each mode softens linearly over its fracture energy per band length (crack
  band; Bažant and Oh 1983).
- **The ratio:** a mode's index at the end of softening is its fracture energy per band over
  the elastic energy density at initiation, ½f²/E. For splitting, both are mixed at the current
  share of opening in the index. Below one, the mode breaks at once (a band too long for its
  energy).
- **Damage:** never decreases, and never softens compression, since a closed crack carries it.
- **Bands:** the in-plane modes use `bandLength`, rolling shear `throughBandLength`.

**Crushing.** Along and across the grain, crushing is perfectly plastic at f_c0 and f_c90 on
the effective stress. Both are returned together, which a few sweeps settle under Poisson
coupling. The plastic strain stays on unloading.

**What it is not:**
- no rate law (scale the strengths by a dynamic increase factor);
- no hardening or densification in compression;
- no stiffness degradation symmetric in Q: damage scales stresses, as Sandhaas's
  implementation does;
- no fatigue, moisture or temperature;
- no glue line or lamella interface;
- no finite strain.

**Domain and errors:**
- `MaterialError.invalidParameters` for non-positive or non-finite inputs, or a compliance
  that is not positive definite.
- `invalidTrial` for a non-finite strain or a component beyond `maximumStrain` (default 0.1).
- `incompatibleState` for a state from other parameters.
- Evaluation is pure: rejection never mutates accepted history.

## Sources

- C. Sandhaas and J.-W. G. van de Kuilen, "Material model for wood", HERON 58(2/3), 2013
  (open). The eight Hashin-type criteria this simplifies to three brittle modes and two plastic
  ones, and its spruce inputs, which the tests use:
  - E_L 11,000, E_T 370, G 690, G_R 50 MPa;
  - f_t0 24, f_c0 36, f_t90 0.7, f_c90 4.3, f_v 6.9, f_r 0.5 MPa;
  - G_t0 60 kJ/m², G_t90 0.5, G_II 1.2, G_roll 0.6 kJ/m².
- Z. Hashin, "Failure criteria for unidirectional fiber composites", J. Appl. Mech. 47, 1980.
- I. Lapczyk and J. A. Hurtado, "Progressive damage modeling in fiber-reinforced materials",
  Composites A 38, 2007. Mode-wise linear softening on a characteristic length.
- Z. P. Bažant and B. H. Oh, "Crack band theory for fracture of concrete", Matériaux et
  Constructions 16, 1983.

## Verification

`Tests/SolidMechanicsTests/TimberFailureTests.swift` checks closed forms, not a stored baseline:
- **Elastic stress:** matches `OrthotropicPlaneStress` to 1e-9.
- **Each brittle mode alone:** its peak equals its strength within 0.2%, and its work to full
  separation equals G/band within 0.5%. The fibre, splitting, longitudinal shear and rolling
  shear modes are each checked.
- **Crushing:** holds f_c0 and f_c90, and leaves the closed-form permanent set.
- **Partly split:** a point unloads along its secant and carries compression in full once closed.
- **Mixed index:** reaches one at equal shares of opening and sliding.
- **A band too long:** breaks at once.
- **Rejections and purity.**

`Scripts/check-timber-failure-consumer.sh` builds a clean Git consumer in release mode. It checks
the peaks, separation energies and crushing plateau through the public API, and excludes
Metal/UI/Accelerate linkage. `Scripts/check.sh` runs both.

Published in [alpha.26](https://github.com/emmettl/ContinuumKit/releases/tag/0.1.0-alpha.26)
([proof](alpha26-release-verification.json)). BombCAD runs a single-precision copy in its GPU
shells and beams and tests it against the released law.
