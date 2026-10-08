# CI on the Mac mini

ContinuumKit uses a dedicated repository-scoped GitHub Actions runner on the physical
Apple Silicon Mac mini at SSH alias `scrimply-ci-tb` (fallback: `scrimply-ci-lan`).
The host already serves BombCAD and other repositories; their runners are separate.

- Runner name: `mac-mini-continuumkit`.
- Labels: `self-hosted`, `macOS`, `ARM64`, `metal`, `continuumkit`.
- Install: `~/Developer/continuumkit-runner` on the mini.
- Service: a user launch agent, installed and started with the runner's `svc.sh`.
- Initial runner: GitHub Actions runner 2.338.0, SHA-256 checked against the official
  release. The runner updates itself.
- Initial toolchain: Xcode Swift 6.4, matching the development host.

`Check` runs for pushes to main and manual dispatch. Release verification uses the
same runner; creating the GitHub release runs separately on a hosted Linux runner.
The shared `continuumkit-metal` concurrency group lets active verification finish.
GitHub may replace an older pending run with a newer one. ContinuumKit has one runner,
so its GPU jobs are serial; other repositories can still use the machine concurrently.
Before introducing sustained heavy suites, coordinate scheduling with those workloads
and record device/load metadata for performance comparisons.

## Device check

Both workflows set `CONTINUUMKIT_REQUIRE_METAL=1`. `Scripts/check-metal.swift` finds
the device, compiles a kernel, dispatches actual compute, waits for completion and
verifies every output. A missing device, GPU error or wrong result fails the job.
This ensures GPU-dependent model checks cannot silently pass on a VM without Metal.

## Service operations

On the mini, as `louisemmett`:

```sh
cd ~/Developer/continuumkit-runner
./svc.sh status
./svc.sh stop
./svc.sh start
```

The user must remain signed in and the machine awake. Runner diagnostic logs are in
`_diag/`; inspect service state before re-registering. Never print `.credentials`,
tokens or environment secrets into job logs.

For a fresh installation, download the official macOS ARM64 runner from
https://github.com/actions/runner/releases and verify its published SHA-256. Obtain
a temporary registration token using the GitHub runner-registration API and pass
it without logging it to `config.sh --unattended`, using the repository URL, runner
name and labels above. Install and start the service, then manually dispatch Check.
Verify both runner identity and the Metal-compute output in the GitHub job logs.

## Workflow trust

Self-hosted checks do not automatically execute pull-request code. Review and merge
trusted changes before running them on the mini. If the repository becomes public,
configure approval for all external fork workflow runs and retain this trigger policy.
Only explicitly authorized, reviewed tags go through the manual release workflow.
