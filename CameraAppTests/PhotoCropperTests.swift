//
//  PhotoCropperTests.swift
//  CameraAppTests
//
//  Confirms the crop that actually reaches Photos matches the geometry
//  `AspectCropRectTests` proves in isolation — decoding real JPEG bytes end
//  to end rather than trusting the two paths agree by inspection.
//

import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import CameraApp

final class PhotoCropperTests: XCTestCase {

    private func makeJPEGPhoto(width: Int, height: Int) -> CapturedPhoto {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cgImage = context.makeImage()!

        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, cgImage, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        return CapturedPhoto(data: data as Data, uniformTypeIdentifier: UTType.jpeg.identifier, isMirrored: false)
    }

    private func decodedSize(_ photo: CapturedPhoto) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(photo.data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return CGSize(width: image.width, height: image.height)
    }

    func testA4x3CaptureIsCroppedToTrue9by16() {
        let photo = makeJPEGPhoto(width: 3024, height: 4032)
        let cropped = PhotoCropper.cropToTargetAspect(photo)

        guard let size = decodedSize(cropped) else { return XCTFail("Could not decode the cropped photo") }
        XCTAssertEqual(size.height, 4032, "The sensor's full height is kept")
        XCTAssertEqual(size.width, 2268, accuracy: 1, "4032 * 9/16 == 2268")
        XCTAssertEqual(size.width / size.height, 9.0 / 16.0, accuracy: 0.001)
    }

    func testAnAlreadyVerticalCaptureIsUnchangedInSize() {
        let photo = makeJPEGPhoto(width: 900, height: 1600)
        let cropped = PhotoCropper.cropToTargetAspect(photo)

        guard let size = decodedSize(cropped) else { return XCTFail("Could not decode the cropped photo") }
        XCTAssertEqual(size, CGSize(width: 900, height: 1600))
    }

    func testTheCroppedPhotoKeepsItsContainerType() {
        let photo = makeJPEGPhoto(width: 3024, height: 4032)
        let cropped = PhotoCropper.cropToTargetAspect(photo)
        XCTAssertEqual(cropped.uniformTypeIdentifier, UTType.jpeg.identifier)
    }

    func testUndecodableDataFallsBackToTheOriginalRatherThanCrashing() {
        let photo = CapturedPhoto(data: Data([0x00, 0x01, 0x02]), uniformTypeIdentifier: UTType.jpeg.identifier, isMirrored: false)
        let cropped = PhotoCropper.cropToTargetAspect(photo)
        XCTAssertEqual(cropped.data, photo.data)
    }
}
