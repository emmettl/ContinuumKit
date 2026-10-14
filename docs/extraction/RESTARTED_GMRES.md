# Bounded Apple SIMD restarted GMRES

`Numerics.RestartedGMRES` exposes the Edgerton SIMD3-vector restarted GMRES engine
without changing its arithmetic. The original source is hash-guarded; a checked
public wrapper defines input/operator errors, finite-norm requirements and bounded
allocation. App code, Newton/preconditioning policy, dependency pin and defaults
remain unchanged. Adoption is deliberately deferred.

Vectors are arrays of `SIMD3<Double>`; the callback must be deterministic and linear,
with RHS in the same preconditioned system. The callback is the complete operator,
including any caller-chosen preconditioning. The library does not compute a
preconditioner or require symmetry. Tolerance is an absolute Euclidean residual
in the caller's vector units. The inherited explicit post-restart acceptance is
residual <= 5*tolerance; this is documented rather than silently tightened.
Restarted modified Gram-Schmidt uses two reorthogonalization passes and native
Apple SIMD reductions. The API is available only where `simd` can be imported;
other existing Numerics APIs retain their portability.

Positive finite tolerance must retain a finite fivefold threshold; restart is
1...256, cycles 1...100000, vector count <=262144 and basis array entries <=1048576.
Empty RHS is supported with a compatible empty callback result. Input components
and norm must be finite. Wrong-size/nonfinite or overflowing-norm callback results
reject. Nonrepresentable internal vectors and source breakdown map to numerical
breakdown; exhausted iterations map to nonconvergence. Callback errors propagate
unchanged. One additional final operator evaluation validates returned residual
with scaled `hypot`, rejecting false convergence from underflow of the source
squared norm. This changes callback counts, not source iteration arithmetic;
future application diagnostic counters must account for it. The result is (solution, iteration count), preserving the source shape.
No universal ill-conditioned-system accuracy or runtime guarantee is inferred.

Independent tests transfer the known 12-component nonsymmetric restarted-solve
oracle (manufactured truth), then check actual residual, a diagonal analytic
solution, zero/empty systems, singular breakdown, exhausted iteration, input bounds,
operator dimensions/finite norm, allocation guards and thrown cancellation.
The optimized public consumer compares four restart widths against the original
engine, including exact solution bits and iteration counts, and checks the
independent manufactured truth and CPU-only linkage. Frozen engine visibility is
adapted only for the verification target; it is not a second production solver.

Full Core verification and a verified tag precede a separate future Edgerton
adoption. Application-level Newton convergence, accepted/rejected step rollback,
preconditioning and coupled mechanics remain application-owned. Numerical solver
verification is separate from continuum convergence and empirical impact accuracy.
Generated logs/builds stay outside GitHub; run low priority and yield to feature work.
