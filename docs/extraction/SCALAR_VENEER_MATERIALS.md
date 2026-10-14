# Bounded scalar veneer material extraction

This adds `SolidMechanics.VeneerCompression` and `VeneerDamage` from Edgerton's
verified P2 coupons. The only implementation transformation is removal of the
`Target` name prefix. No Edgerton source, study, package pin or default is changed.
Adoption is deliberately deferred to a separately scheduled application task.

## Supported contract

Compression is an infinitesimal one-axis surrogate, compression negative, with
Young modulus/yield/hardening in Pa. Plastic strain is minus alpha. Linear
hardening stores H alpha²/2 and yield friction dissipates Y alpha, in J/m³.
The configured strain range stays within [-0.03, 0.001]. There is no reverse
plastic branch, finite-strain crushing, rate, temperature or coupled tensor law.

Damage is either scalar tension (nonnegative strain) or symmetric engineering
shear, not combined orthotropic damage. Modulus/strength are Pa, band length is m,
and fracture energy is J/m², including pre-peak elastic work. Complete failure
consumes Gf/bandLength per rest volume. Maximum strain is at most 0.1.
Callers select the mode, local band and characteristic length; no crack selection,
mesh construction, topology transition or mixed tensor interaction is exported.

Both laws return immutable states. Callers accept a trial by assigning it;
abandoning or rejecting a trial leaves accepted history untouched. Exact parameter
signatures reject cross-material history. Errors distinguish invalid parameters,
invalid trials and incompatible states. Nonfinite intermediates reject. These
chosen surrogate laws and their numerical checks do not establish measured
plywood accuracy, general panel response or projectile impact validity.

## Verification and provenance

`scalar-material-source.json` freezes source, harness, input and independent CSV
identities at the application revision observed during extraction. Frozen original
laws are verification-only consumer targets. `verify-scalar-material-source.py`
checks their hashes, original independent inputs/references and rename-only public
implementations. References are immutable 45-digit Decimal envelope/antiderivative
solutions, not regenerated from Core. The original generators are retained.

Core tests transfer all 12 compression and 24 damage coupon cases: 1,964/2,796
samples with at least 30,257/77,524 checks. They retain loading/unloading,
partition/refinement, work/storage/loss, irreversible histories, rollback,
invalid inputs, P1 reduction and damage two-mesh wrong-length negative controls.
Additional analytic tests cover permanent set, complete separation and cross-mode
state rejection. A fetched optimized public consumer compares all seven state
fields bit-for-bit against frozen originals on 52 representative samples and
checks CPU-only linkage. Original Edgerton evidence remains in place.

Small compressed reference fixtures are committed. Generated histories, logs,
build caches and larger retained evidence stay outside the GitHub repository.
Run focused checks serially at low priority; full package and exact-tag release
checks require a resource window that yields to orchestrated feature work.

## Deferred adoption gate

After a verified immutable Core release, a separate Edgerton change can pin it and
replace local laws with thin aliases/adapters. It must verify public parameter and
history forwarding, invalid/abandoned trial handling and unchanged affected P2/P3
assembled fixtures. Core owns exhaustive law tests; application-specific assembly,
contact, fracture, rendering and physical validation remain application-owned.
No application test is removed by this extraction. Do not infer a build speedup.
