# Real FFT public consumer

Run `bash Scripts/check-real-fft-consumer.sh` from a clean committed checkout.
The script fetches the exact Git revision (or supplied exact semantic-version tag),
builds optimized public APIs, preserves the original RoomCAD file byte-for-byte,
and retains complete inputs, values/bits, checked failures, environment, source
hashes and resolved pins. Independent scalar Python references and corruption
controls run after production of both variants. No app/renderer/Metal framework
is linked. Accelerate is this module's explicit platform capability.

See [the contract](../../docs/extraction/REAL_FFT.md). Application adoption and
throughput are separate gates.
