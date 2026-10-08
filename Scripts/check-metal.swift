import Foundation
import Metal

// Runner conformance smoke test, independent of future model implementation.
// It must dispatch actual GPU work and verify every output, not just find a device.
enum SmokeFailure: Error {
    case unavailable(String)
    case incorrectOutput(index: Int, actual: Float, expected: Float)
}

func checkMetal() throws {
    guard let device = MTLCreateSystemDefaultDevice(),
          let queue = device.makeCommandQueue() else {
        throw SmokeFailure.unavailable("Metal device or command queue")
    }
    let library = try device.makeLibrary(source: """
        #include <metal_stdlib>
        using namespace metal;
        kernel void verify(const device float *input [[buffer(0)]],
                           device float *output [[buffer(1)]],
                           uint id [[thread_position_in_grid]]) {
            output[id] = input[id] * input[id] + 1.0f;
        }
        """, options: nil)
    guard let function = library.makeFunction(name: "verify") else {
        throw SmokeFailure.unavailable("compute function")
    }
    let pipeline = try device.makeComputePipelineState(function: function)
    let count = 256
    let bytes = count * MemoryLayout<Float>.stride
    guard let input = device.makeBuffer(length: bytes, options: .storageModeShared),
          let output = device.makeBuffer(length: bytes, options: .storageModeShared),
          let command = queue.makeCommandBuffer(),
          let encoder = command.makeComputeCommandEncoder() else {
        throw SmokeFailure.unavailable("buffers or command encoder")
    }
    let values = input.contents().bindMemory(to: Float.self, capacity: count)
    let results = output.contents().bindMemory(to: Float.self, capacity: count)
    for index in 0..<count {
        values[index] = Float(index)
        results[index] = .nan
    }
    encoder.setComputePipelineState(pipeline)
    encoder.setBuffer(input, offset: 0, index: 0)
    encoder.setBuffer(output, offset: 0, index: 1)
    encoder.dispatchThreads(
        MTLSize(width: count, height: 1, depth: 1),
        threadsPerThreadgroup: MTLSize(
            width: min(count, pipeline.maxTotalThreadsPerThreadgroup), height: 1, depth: 1
        )
    )
    encoder.endEncoding()
    command.commit()
    command.waitUntilCompleted()
    guard command.status == .completed else {
        throw SmokeFailure.unavailable(command.error?.localizedDescription ?? "GPU command failed")
    }
    for index in 0..<count {
        let expected = Float(index * index + 1)
        guard results[index] == expected else {
            throw SmokeFailure.incorrectOutput(index: index, actual: results[index], expected: expected)
        }
    }
    print("Metal compute passed: \(device.name), \(count) verified outputs.")
}

try checkMetal()
