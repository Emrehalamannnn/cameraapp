//
//  LightingEstimator.swift
//  CameraApp
//
//  Turns the capture device's exposure state into a light-quality judgement.
//
//  Mean luma on its own is a poor signal because auto-exposure drives it back
//  toward mid-grey in almost any light. The device's own ISO/shutter pair is a
//  real photometric measurement of the scene, so that is the primary input and
//  luma is used for clipping detection and as a fallback (e.g. the Simulator).
//

import Foundation

enum LightingEstimator {

    /// Below this EV100 the sensor is pushing ISO hard enough that noise and
    /// motion blur dominate.
    static let tooDarkExposureValue = 1.5
    /// Below this EV100 the shot is usable but visibly compromised.
    static let dimExposureValue = 4.0

    static let tooDarkLuma = 0.16
    static let dimLuma = 0.28
    static let clippedLuma = 0.94

    /// EV100: the exposure value the scene would need at ISO 100.
    /// `EV = log2(N² / t) - log2(S / 100)` for aperture `N`, shutter `t`, ISO `S`.
    static func exposureValue(for reading: ExposureReading) -> Double? {
        guard reading.duration > 0,
              reading.iso > 0,
              reading.aperture > 0,
              reading.duration.isFinite else { return nil }
        let apertureTerm = log2((reading.aperture * reading.aperture) / reading.duration)
        let isoTerm = log2(reading.iso / 100.0)
        let value = apertureTerm - isoTerm
        return value.isFinite ? value : nil
    }

    static func evaluate(exposure: ExposureReading?, meanLuma: Double) -> LightingAssessment {
        let ev = exposure.flatMap(exposureValue(for:))

        // Blown highlights are worth calling out regardless of the exposure pair.
        if meanLuma >= clippedLuma {
            return LightingAssessment(quality: .overexposed, exposureValue: ev, meanLuma: meanLuma)
        }

        guard let ev else {
            // No exposure metadata: fall back to raw scene luma.
            let quality: LightingQuality
            if meanLuma <= tooDarkLuma {
                quality = .tooDark
            } else if meanLuma <= dimLuma {
                quality = .dim
            } else {
                quality = .good
            }
            return LightingAssessment(quality: quality, exposureValue: nil, meanLuma: meanLuma)
        }

        let quality: LightingQuality
        if ev < tooDarkExposureValue {
            quality = .tooDark
        } else if ev < dimExposureValue {
            quality = .dim
        } else {
            quality = .good
        }
        return LightingAssessment(quality: quality, exposureValue: ev, meanLuma: meanLuma)
    }
}
