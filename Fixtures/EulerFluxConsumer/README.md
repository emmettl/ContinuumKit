# Euler flux consumer

Run `bash Scripts/check-euler-flux-consumer.sh` from a clean committed candidate.
It fetches that Git revision, builds optimized code, rejects Metal/UI linkage and
retains complete original/shared native reports, pins and producer metadata. Passing
a release version requires that exact tag to identify candidate HEAD.

The original Swift source is protected immutable MIT-authored BombCAD code, using
the already released packet and wall primitives. It is a verification oracle.
The shared implementation is consumed through public CompressibleFlow only.

See [the contract](../../docs/extraction/FRACTIONAL_EULER_FLUX.md) for the complete
751-case tree, continuum refinement gates, units, trace/clock limitations and the
separate application adoption requirement. Output directories preserve every native
cell, physical clock, supplied interface/trace and ordered wall exchange.

The compiled scratch copy of the original receives one explicit CompressibleFlow
import so released alias types are visible to the compiler. The remaining bytes
are checked identical to the immutable oracle; no numerical adaptation occurs.
