#!/usr/bin/env python3
import hashlib
from pathlib import Path
r=Path(__file__).resolve().parent.parent
p=r/'Fixtures/RealFFTConsumer/Sources/RealFFTConsumer/OriginalFFT.swift'
assert hashlib.sha256(p.read_bytes()).hexdigest()=='63da5cb9c3ead610051a2b43faf3c345d4168d7e6580abd25ea202c18877b617','frozen RoomCAD FFT changed'
assert [x for x in (r/'Sources/SpectralTransforms/RealFFT.swift').read_text().splitlines() if x.startswith('import ')]==['import Accelerate']
print('PASS immutable RoomCAD FFT and explicit Accelerate-only capability')
