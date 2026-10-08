import Foundation
import ImpulseResponseKit
import Testing

@Suite("Response interchange conformance")
struct InterchangeConformanceTests {
  private func metadata() -> ResponseMetadata {
    ResponseMetadata(
      sampleRate: 1_000, frameCount: 2,
      channels: [
        .init(
          name: "Reference path",
          sourceID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
          receiverID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        )
      ],
      content: .reflectionsOnly, gainConvention: "Relative pressure",
      usableBand: .init(lowerHz: 20, upperHz: 400), model: "Reference",
      assumptions: [], generator: "Conformance fixture"
    )
  }

  @Test("A hand-authored mono float WAV decodes independently of the writer")
  func referenceWAV() throws {
    // RIFF/WAVE, fmt length 16, IEEE float, mono, 1 kHz, 32-bit samples: 1 and -0.5.
    let bytes: [UInt8] = [
      0x52, 0x49, 0x46, 0x46, 0x2C, 0, 0, 0, 0x57, 0x41, 0x56, 0x45,
      0x66, 0x6D, 0x74, 0x20, 0x10, 0, 0, 0, 3, 0, 1, 0,
      0xE8, 3, 0, 0, 0xA0, 0x0F, 0, 0, 4, 0, 0x20, 0,
      0x64, 0x61, 0x74, 0x61, 8, 0, 0, 0, 0, 0, 0x80, 0x3F, 0, 0, 0, 0xBF,
    ]
    let audio = try WAVFile.decode(Data(bytes))
    #expect(audio.sampleRate == 1_000)
    #expect(audio.channels == [[1, -0.5]])
    let response = try ImpulseResponse(wav: Data(bytes), metadata: JSONEncoder().encode(metadata()))
    #expect(response.metadata.content == .reflectionsOnly)
    #expect(response.channels == [[1, -0.5]])
  }

  @Test("Incompatible identifiers, versions and WAV/metadata dimensions are rejected")
  func incompatibleMetadata() throws {
    let wav = try WAVFile.encode(channels: [[1, -0.5]], sampleRate: 1_000)
    var variants: [ResponseMetadata] = []
    var changed = metadata()
    changed.format = "other.response"
    variants.append(changed)
    changed = metadata()
    changed.encodingVersion = 2
    variants.append(changed)
    changed = metadata()
    changed.sampleRate = 2_000
    variants.append(changed)
    changed = metadata()
    changed.frameCount = 3
    variants.append(changed)
    changed = metadata()
    changed.channels.append(changed.channels[0])
    variants.append(changed)
    for variant in variants {
      let json = try JSONEncoder().encode(variant)
      #expect(throws: ImpulseResponseError.self) {
        try ImpulseResponse(wav: wav, metadata: json)
      }
    }
  }

  @Test("Generator extensions and conditioning history survive without a generator dependency")
  func generatorExtension() throws {
    struct Details: Codable, Equatable { var seed: Int }
    var response = try ImpulseResponse(channels: [[1, -0.5]], metadata: metadata())
    try response.applyCommonGain(0.5, detail: "Reference gain")
    try response.removeLeadingFrames(1)
    let files = try response.encoded(generatorDetails: Details(seed: 42))
    let read = try ImpulseResponse(wav: files.wav, metadata: files.metadata)
    #expect(read == response)
    #expect(read.channels == [[-0.25]])
    #expect(read.metadata.emissionFrame == -1)
    #expect(read.metadata.commonGain == 0.5)
    #expect(read.metadata.processing.map(\.kind) == ["commonGain", "removeLeadingFrames"])
    #expect(
      try ImpulseResponse.generatorDetails(Details.self, from: files.metadata) == Details(seed: 42))
    #expect(
      try ImpulseResponse.generatorDetails(Details.self, from: JSONEncoder().encode(metadata()))
        == nil)
  }

  @Test("Construction rejects mismatched, non-finite and non-positive sampling inputs")
  func invalidResponse() throws {
    #expect(throws: ImpulseResponseError.self) {
      try ImpulseResponse(channels: [[1], [1]], metadata: metadata())
    }
    #expect(throws: ImpulseResponseError.self) {
      try ImpulseResponse(channels: [[.infinity]], metadata: metadata())
    }
    var invalidRate = metadata()
    invalidRate.sampleRate = 0
    #expect(throws: ImpulseResponseError.self) {
      try ImpulseResponse(channels: [[1]], metadata: invalidRate)
    }
  }
}
