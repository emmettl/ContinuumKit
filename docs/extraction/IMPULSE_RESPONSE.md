# ImpulseResponseKit extraction

Source: BombCAD commit `285b620806418f39e4bc7a66be20191f2d366612`,
`RoomCAD/Sources/ImpulseResponseKit`. The two implementation files and existing
8-test suite retain their original bytes and MIT attribution. See the
[file hashes](impulse-response-source.json).

## Contract and ownership

`ResponseMetadata` describes sampled source-to-receiver paths independently of a
room or solver. Samples are Float values at an integer rate in Hz; all channels
have the same number of frames. Channel IDs, optional metre/z-up receiver positions,
content selection, gain convention, usable frequency band and generator assumptions
are metadata. Applications supply their interpretation and generation settings.

`ImpulseResponse` applies one gain or time trim to all channels and records ordered
conditioning steps. Trimming shifts the emission frame equally; it does not reset
source-relative timing. JSON retains `dev.roomcad.impulse-response`, version 1.
Unknown generator details are separate from the interchange contract.

`WAVFile` supports interleaved 32-bit IEEE float WAV, including the existing extensible
multichannel representation. It does not implement PCM conversion, compressed audio,
RF64, resampling, convolution or an acoustic propagation model. The original reader's
header checks and conditioning input limits are retained; extraction adds no new
validation guarantees for arbitrary hostile files or extreme arithmetic inputs.

## Independent verification

The original eight tests cover stereo/extensible files, odd chunks, rejected inputs,
common gain, trimming, fading and disk metadata. Four new conformance tests check a
hand-authored WAV independent of the encoder, incompatible formats/versions/dimensions,
generator extension and processing history, and invalid response sampling inputs.

The external release consumer imports the fetched product, conditions a two-channel
response and verifies its WAV/JSON disk round trip, timing, ratios and stable identifier.
No application target, recording or measured room is required. Both implementations
remain byte-identical to the source: this verifies interchange, not acoustic accuracy.

## Release and adoption

[ContinuumKit PR #2](https://github.com/emmettl/ContinuumKit/pull/2) is merged. The
public [0.1.0-alpha.2 release](https://github.com/emmettl/ContinuumKit/releases/tag/0.1.0-alpha.2)
points to `06841daecc26812706f8c686618aadb0cb6b7efa`. All 27 tests and the optimized
Git consumer pass locally on M4 Max and in the [Mac mini candidate check](https://github.com/emmettl/ContinuumKit/actions/runs/37830563317).
The [release workflow](https://github.com/emmettl/ContinuumKit/actions/runs/37830760444)
passes exact-version verification before publication.

[Standalone RoomCAD](https://github.com/emmettl/RoomCAD) pins this exact release and
retains its own document, acoustic and audition integration tests. Its source hashes,
rewritten commit map and historical release tag are retained. Application and CI
parity evidence is recorded separately from this library's interchange checks.

[Standalone Mac mini CI](https://github.com/emmettl/RoomCAD/actions/runs/37831881121)
passes all 143 application tests, eight release-script checks, actual Metal work, release
packaging, deep strict signature verification and the packaged snapshot. A separate
[fixture reliability change](https://github.com/emmettl/RoomCAD/pull/1) fixes stochastic
receiver UUID inputs without changing acoustic source or tolerances.
