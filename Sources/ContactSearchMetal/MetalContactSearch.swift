// Copyright (c) 2026 Louis Emmett. MIT licence; see LICENSE.
import ContactSearch
import Foundation
import Metal

public enum MetalContactSearchError: Error, Equatable, Sendable {
  case shaderResourceUnavailable
  case shaderCompilation(String)
  case pipelineCreation(String)
  case allocationFailed
  case commandEncodingFailed
  case commandFailed(String)
  case capacityExceeded
  case bufferTooSmall
}

/// A contact table resident on the GPU, rebuilt each substep, and a search of it.
///
/// `encodeBuild` fills the table from a buffer of points (`float4`, xyz used) and their flags
/// (`ContactPointFlags` raw values) in two passes on a serial encoder; the table it leaves is
/// the one `ContactTable.build` makes, bit for bit, wherever no point lies within a rounding
/// error of a cell face. Applications may instead compile `functionSource()` into their own
/// kernels and bind `heads`, `slots` and `moved` there, keeping their own pair forces.
public final class MetalContactSearch {
  public let layout: ContactCellLayout
  public let capacity: Int
  /// Per entry, the stamp of the substep it last held a point in.
  public let heads: any MTLBuffer
  /// Per entry, `ContactCellLayout.slotCount` point indices.
  public let slots: any MTLBuffer
  /// Per entry, the stamp of the substep it last held a moved point in.
  public let moved: any MTLBuffer
  /// The stamp of the last build encoded.
  public private(set) var stamp: UInt32 = 0

  private let device: any MTLDevice
  private let clearPipeline, insertPipeline, candidatePipeline: any MTLComputePipelineState

  struct Uniforms {
    var originX, originY, originZ, cellSize: Float
    var periodX, periodY, periodZ, stamp: UInt32
    var count: UInt32
    var reach: Float
    var maxCandidates: UInt32
    var skipStill: UInt32
  }

  /// The Metal source of the shared functions (cell, entry, clearing, insertion, listing and
  /// which entries a search visits), for applications to compile ahead of their own kernels.
  public static func functionSource() throws -> String { try resource("ContactSearchFunctions") }

  static func resource(_ name: String) throws -> String {
    guard let url = Bundle.module.url(forResource: name, withExtension: "metal", subdirectory: "Shaders"),
      let source = try? String(contentsOf: url, encoding: .utf8)
    else { throw MetalContactSearchError.shaderResourceUnavailable }
    return source
  }

  public init(device: any MTLDevice, layout: ContactCellLayout, capacity: Int) throws {
    guard capacity > 0, capacity < Int(ContactCellLayout.emptySlot) else {
      throw MetalContactSearchError.capacityExceeded
    }
    self.device = device
    self.layout = layout
    self.capacity = capacity
    let library: any MTLLibrary
    do {
      library = try device.makeLibrary(
        source: try Self.functionSource() + "\n" + Self.resource("ContactSearchKernels"), options: nil)
    } catch let error as MetalContactSearchError {
      throw error
    } catch {
      throw MetalContactSearchError.shaderCompilation(String(describing: error))
    }
    func pipeline(_ name: String) throws -> any MTLComputePipelineState {
      guard let function = library.makeFunction(name: name) else {
        throw MetalContactSearchError.pipelineCreation(name)
      }
      do { return try device.makeComputePipelineState(function: function) } catch {
        throw MetalContactSearchError.pipelineCreation("\(name): \(error)")
      }
    }
    clearPipeline = try pipeline("cksClear")
    insertPipeline = try pipeline("cksInsertPoints")
    candidatePipeline = try pipeline("cksCandidates")
    let entries = layout.entryCount
    guard let heads = device.makeBuffer(length: entries * 4, options: .storageModeShared),
      let slots = device.makeBuffer(length: entries * 4 * ContactCellLayout.slotCount, options: .storageModeShared),
      let moved = device.makeBuffer(length: entries * 4, options: .storageModeShared)
    else { throw MetalContactSearchError.allocationFailed }
    // No entry is current until a build stamps it; stamps are never `emptySlot`.
    for buffer in [heads, slots, moved] { memset(buffer.contents(), 0xFF, buffer.length) }
    self.heads = heads
    self.slots = slots
    self.moved = moved
  }

  func uniforms(count: Int, reach: Float = 0, maxCandidates: Int = 0, skipStill: Bool = false) -> Uniforms {
    Uniforms(
      originX: layout.origin.x, originY: layout.origin.y, originZ: layout.origin.z, cellSize: layout.cellSize,
      periodX: layout.period.x, periodY: layout.period.y, periodZ: layout.period.z, stamp: stamp,
      count: UInt32(count), reach: reach, maxCandidates: UInt32(maxCandidates), skipStill: skipStill ? 1 : 0)
  }

  /// Encodes this substep's table of the first `count` points: a new stamp, a clearing pass and
  /// an insertion pass. Returns the stamp.
  @discardableResult
  public func encodeBuild(
    _ encoder: any MTLComputeCommandEncoder, points: any MTLBuffer, flags: any MTLBuffer, count: Int
  ) throws -> UInt32 {
    guard count >= 0, count <= capacity else { throw MetalContactSearchError.capacityExceeded }
    guard points.length >= count * 16, flags.length >= count * 4 else {
      throw MetalContactSearchError.bufferTooSmall
    }
    stamp = stamp % 0x1FFF_FFF0 + 1
    guard count > 0 else { return stamp }
    var values = uniforms(count: count)
    for pipeline in [clearPipeline, insertPipeline] {
      encoder.setComputePipelineState(pipeline)
      encoder.setBuffer(points, offset: 0, index: 0)
      encoder.setBuffer(flags, offset: 0, index: 1)
      encoder.setBytes(&values, length: MemoryLayout<Uniforms>.stride, index: 2)
      encoder.setBuffer(heads, offset: 0, index: 3)
      encoder.setBuffer(slots, offset: 0, index: 4)
      encoder.setBuffer(moved, offset: 0, index: 5)
      encoder.dispatchThreads(
        MTLSize(width: count, height: 1, depth: 1),
        threadsPerThreadgroup: MTLSize(width: min(pipeline.maxTotalThreadsPerThreadgroup, 64), height: 1, depth: 1))
    }
    return stamp
  }

  /// Encodes the search of the last table built: each point's candidates within `reach` (at
  /// most the cell size), in search order, into `candidates` (`maxCandidates` per point) and
  /// their number into `counts`. `threadgroupWidth` changes only how the work is split.
  public func encodeCandidates(
    _ encoder: any MTLComputeCommandEncoder, points: any MTLBuffer, flags: any MTLBuffer, count: Int,
    reach: Float, skipStill: Bool, maxCandidates: Int, candidates: any MTLBuffer, counts: any MTLBuffer,
    threadgroupWidth: Int = 64
  ) throws {
    guard count >= 0, count <= capacity else { throw MetalContactSearchError.capacityExceeded }
    guard reach.isFinite, reach > 0, reach <= layout.cellSize else { throw ContactSearchError.invalidReach }
    guard maxCandidates > 0, maxCandidates <= 1 << 16 else { throw ContactSearchError.invalidCandidateLimit }
    guard points.length >= count * 16, flags.length >= count * 4, counts.length >= count * 4,
      candidates.length >= count * maxCandidates * 4
    else { throw MetalContactSearchError.bufferTooSmall }
    guard count > 0 else { return }
    var values = uniforms(count: count, reach: reach, maxCandidates: maxCandidates, skipStill: skipStill)
    encoder.setComputePipelineState(candidatePipeline)
    encoder.setBuffer(points, offset: 0, index: 0)
    encoder.setBuffer(flags, offset: 0, index: 1)
    encoder.setBytes(&values, length: MemoryLayout<Uniforms>.stride, index: 2)
    encoder.setBuffer(heads, offset: 0, index: 3)
    encoder.setBuffer(slots, offset: 0, index: 4)
    encoder.setBuffer(moved, offset: 0, index: 5)
    encoder.setBuffer(candidates, offset: 0, index: 6)
    encoder.setBuffer(counts, offset: 0, index: 7)
    let width = max(1, min(threadgroupWidth, candidatePipeline.maxTotalThreadsPerThreadgroup))
    encoder.dispatchThreads(
      MTLSize(width: count, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1))
  }

  /// The table as last built, with entries not current this substep shown empty, for
  /// comparison with `ContactTable.build`. Read after the build's command buffer completes.
  public func snapshot() -> ContactTable {
    let entries = layout.entryCount
    let slotCount = ContactCellLayout.slotCount
    let empty = ContactCellLayout.emptySlot
    let h = heads.contents().bindMemory(to: UInt32.self, capacity: entries)
    let s = slots.contents().bindMemory(to: UInt32.self, capacity: entries * slotCount)
    let m = moved.contents().bindMemory(to: UInt32.self, capacity: entries)
    var headValues = [UInt32](repeating: empty, count: entries)
    var slotValues = [UInt32](repeating: empty, count: entries * slotCount)
    var movedValues = [UInt32](repeating: empty, count: entries)
    for entry in 0..<entries where h[entry] == stamp {
      headValues[entry] = stamp
      for slot in 0..<slotCount { slotValues[entry * slotCount + slot] = s[entry * slotCount + slot] }
      if m[entry] == stamp { movedValues[entry] = stamp }
    }
    return ContactTable(layout: layout, stamp: stamp, heads: headValues, slots: slotValues, moved: movedValues)
  }

  /// Builds the table of `points` and searches it, on a command buffer of its own, waiting for
  /// it: each point's candidates in search order (complete only where its count is at most
  /// `maxCandidates`), and the table.
  public func search(
    points: [SIMD3<Float>], flags: [ContactPointFlags], reach: Float, skipStill: Bool, maxCandidates: Int,
    threadgroupWidth: Int = 64
  ) throws -> (candidates: [[UInt32]], counts: [Int], table: ContactTable) {
    guard points.count == flags.count else { throw ContactSearchError.countMismatch }
    guard points.count <= capacity else { throw MetalContactSearchError.capacityExceeded }
    guard reach.isFinite, reach > 0, reach <= layout.cellSize else { throw ContactSearchError.invalidReach }
    guard maxCandidates > 0, maxCandidates <= 1 << 16 else { throw ContactSearchError.invalidCandidateLimit }
    for (index, point) in points.enumerated() where flags[index].contains(.active) {
      try layout.check(point, index: index)
    }
    let count = points.count
    guard let queue = device.makeCommandQueue(),
      let pointBuffer = device.makeBuffer(length: max(count, 1) * 16, options: .storageModeShared),
      let flagBuffer = device.makeBuffer(length: max(count, 1) * 4, options: .storageModeShared),
      let candidateBuffer = device.makeBuffer(
        length: max(count * maxCandidates, 1) * 4, options: .storageModeShared),
      let countBuffer = device.makeBuffer(length: max(count, 1) * 4, options: .storageModeShared)
    else { throw MetalContactSearchError.allocationFailed }
    let p = pointBuffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: max(count, 1))
    let f = flagBuffer.contents().bindMemory(to: UInt32.self, capacity: max(count, 1))
    for index in 0..<count {
      p[index] = SIMD4(points[index], 0)
      f[index] = flags[index].rawValue
    }
    guard let commands = queue.makeCommandBuffer(), let encoder = commands.makeComputeCommandEncoder() else {
      throw MetalContactSearchError.commandEncodingFailed
    }
    try encodeBuild(encoder, points: pointBuffer, flags: flagBuffer, count: count)
    try encodeCandidates(
      encoder, points: pointBuffer, flags: flagBuffer, count: count, reach: reach, skipStill: skipStill,
      maxCandidates: maxCandidates, candidates: candidateBuffer, counts: countBuffer,
      threadgroupWidth: threadgroupWidth)
    encoder.endEncoding()
    commands.commit()
    commands.waitUntilCompleted()
    if let error = commands.error { throw MetalContactSearchError.commandFailed(String(describing: error)) }
    let c = candidateBuffer.contents().bindMemory(to: UInt32.self, capacity: max(count * maxCandidates, 1))
    let n = countBuffer.contents().bindMemory(to: UInt32.self, capacity: max(count, 1))
    var lists: [[UInt32]] = []
    var counts: [Int] = []
    for index in 0..<count {
      let found = Int(n[index])
      counts.append(found)
      lists.append((0..<min(found, maxCandidates)).map { c[index * maxCandidates + $0] })
    }
    return (lists, counts, snapshot())
  }
}
