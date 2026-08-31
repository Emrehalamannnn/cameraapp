//
//  LumaSampler.swift
//  CameraApp
//
//  Reads a coarse brightness grid straight out of the capture buffer.
//
//  The sampler never copies the frame: it locks the buffer read-only, reads a
//  fixed 16x16 lattice of individual pixels (256 byte loads regardless of
//  capture resolution) and unlocks. That grid doubles as a frame-difference
//  signal for motion estimation.
//

import CoreVideo
import Foundation

enum LumaSampler {

    /// The lattice is deliberately tiny: it is a lighting/motion signal, not an
    /// image. 16x16 keeps the cost flat and the noise low.
    static let gridSize = 16

    struct Sample: Equatable {
        /// Mean luma across the lattice, normalised to `0...1`.
        var mean: Double
        /// Row-major luma lattice, normalised to `0...1`.
        var grid: [Float]
    }

    static func sample(_ pixelBuffer: CVPixelBuffer) -> Sample? {
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)

        guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else {
            return nil
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        switch format {
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
             kCVPixelFormatType_420YpCbCr8Planar,
             kCVPixelFormatType_420YpCbCr8PlanarFullRange:
            let isVideoRange = format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                || format == kCVPixelFormatType_420YpCbCr8Planar
            return sampleLumaPlane(pixelBuffer, isVideoRange: isVideoRange)

        case kCVPixelFormatType_32BGRA:
            return sampleBGRA(pixelBuffer)

        default:
            return nil
        }
    }

    // MARK: - Planar YUV

    private static func sampleLumaPlane(_ pixelBuffer: CVPixelBuffer, isVideoRange: Bool) -> Sample? {
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return nil }
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        guard width > 0, height > 0, bytesPerRow > 0 else { return nil }

        let pointer = base.assumingMemoryBound(to: UInt8.self)
        var grid = [Float](repeating: 0, count: gridSize * gridSize)
        var total: Double = 0

        for row in 0..<gridSize {
            let y = samplePosition(index: row, extent: height)
            let rowOffset = y * bytesPerRow
            for column in 0..<gridSize {
                let x = samplePosition(index: column, extent: width)
                let raw = Float(pointer[rowOffset + x])
                let value = isVideoRange ? min(max((raw - 16) / 219, 0), 1) : raw / 255
                grid[row * gridSize + column] = value
                total += Double(value)
            }
        }

        return Sample(mean: total / Double(grid.count), grid: grid)
    }

    // MARK: - Packed BGRA

    private static func sampleBGRA(_ pixelBuffer: CVPixelBuffer) -> Sample? {
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard width > 0, height > 0, bytesPerRow >= width * 4 else { return nil }

        let pointer = base.assumingMemoryBound(to: UInt8.self)
        var grid = [Float](repeating: 0, count: gridSize * gridSize)
        var total: Double = 0

        for row in 0..<gridSize {
            let y = samplePosition(index: row, extent: height)
            let rowOffset = y * bytesPerRow
            for column in 0..<gridSize {
                let x = samplePosition(index: column, extent: width)
                let pixel = rowOffset + x * 4
                let blue = Float(pointer[pixel])
                let green = Float(pointer[pixel + 1])
                let red = Float(pointer[pixel + 2])
                let value = (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255
                grid[row * gridSize + column] = min(max(value, 0), 1)
                total += Double(value)
            }
        }

        return Sample(mean: total / Double(grid.count), grid: grid)
    }

    /// Centre of the `index`-th cell of a `gridSize` lattice over `extent` pixels.
    private static func samplePosition(index: Int, extent: Int) -> Int {
        let position = ((index * 2) + 1) * extent / (gridSize * 2)
        return min(max(position, 0), extent - 1)
    }

    /// Mean absolute difference between two lattices, in `0...1`.
    static func difference(_ lhs: [Float], _ rhs: [Float]) -> Double {
        guard !lhs.isEmpty, lhs.count == rhs.count else { return 0 }
        var total: Float = 0
        for index in 0..<lhs.count {
            total += abs(lhs[index] - rhs[index])
        }
        return Double(total) / Double(lhs.count)
    }
}
