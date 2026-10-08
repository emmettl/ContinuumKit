# Contributing

Keep changes focused on implemented, reusable behavior. Do not import app targets,
add speculative model abstractions, or create empty products for a planned taxonomy.

Run `bash Scripts/check.sh` from a committed candidate. Add meaningful independent
tests with each extracted component and update its contract and evidence. Record
source revision, attribution and consumer parity when moving existing code.

PR descriptions should explain behavior, assumptions, verification, compatibility
and remaining limitations. A regression baseline alone is not a reference solution.

Ordinary pushes and merges never publish releases. Follow `docs/RELEASING.md` only
when a release has been explicitly authorized.
