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

The authorized next prerelease is `0.1.0-alpha.2`. RoomCAD will use that exact tag and
retain its own document, acoustic and audition integration tests. Standalone repository
migration and removal of the nested application follow successful application parity.
