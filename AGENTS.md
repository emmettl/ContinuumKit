# Working agreements

Follow CONTRIBUTING.md and the architecture/verification documents.
Do not migrate application code or create release tags without task authorization.
Keep this initial scaffold minimal; add actual modules with independently verified
implementations rather than filling a speculative target graph.

Models must be verifiable without application imports. Changes to a model's contract
must include independent evidence, units and supported assumptions.

Run Scripts/check.sh for package changes. It checks the committed Git consumer;
commit the reviewed candidate before the final clean-consumer verification.

Treat sandbox failures involving host credentials as inconclusive. Retry read-only
authentication checks once with narrow host access. Git metadata mutations may need
host access; do not bypass normal safety checks.
