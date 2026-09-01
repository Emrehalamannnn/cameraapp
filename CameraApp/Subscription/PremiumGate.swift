//
//  PremiumGate.swift
//  CameraApp
//
//  What you get for free, and what Pro adds.
//
//  The free tier is deliberately a real camera, not a demo: manual capture at
//  full quality, live framing guidance, the grid, level, zoom and flash all
//  work without paying. A camera that nags before it has been useful gets
//  deleted.
//
//  Pro buys the things that take work off your hands — the automation and the
//  modes that know what you are shooting. Keeping the whole policy in one
//  table means changing the boundary is one edit, not an audit.
//

import Foundation

enum PremiumFeature: String, CaseIterable, Sendable {
    case advancedShootingModes
    case autoCapture
    case bestShot
    case referenceFraming
    case enhancement
    case compositionGuides
    case maximumResolution

    var title: String {
        switch self {
        case .advancedShootingModes: return "All shooting modes"
        case .autoCapture: return "Auto Capture"
        case .bestShot: return "Best Shot"
        case .referenceFraming: return "Reference framing"
        case .enhancement: return "One-tap enhance"
        case .compositionGuides: return "Composition guides"
        case .maximumResolution: return "Full resolution capture"
        }
    }

    var detail: String {
        switch self {
        case .advancedShootingModes:
            return "Outfit, Food, Product, Landscape, Night and Story — each with its own idea of good framing."
        case .autoCapture:
            return "The shutter fires itself the moment the shot is genuinely right."
        case .bestShot:
            return "Takes a short burst and keeps the frame where nobody blinked."
        case .referenceFraming:
            return "Point at a photo you like and get guided to the same composition."
        case .enhancement:
            return "A conservative clean-up that still looks like your photograph."
        case .compositionGuides:
            return "Golden-ratio lines and a live square-crop frame, on top of the usual grid."
        case .maximumResolution:
            return "Capture at the highest resolution your camera supports."
        }
    }

    var symbolName: String {
        switch self {
        case .advancedShootingModes: return "square.grid.2x2"
        case .autoCapture: return "timer"
        case .bestShot: return "square.stack"
        case .referenceFraming: return "photo.on.rectangle"
        case .enhancement: return "wand.and.stars"
        case .compositionGuides: return "grid"
        case .maximumResolution: return "arrow.up.left.and.arrow.down.right"
        }
    }
}

/// Whether the customer currently has Pro.
enum EntitlementStatus: Equatable, Sendable {
    case unknown
    case free
    case pro(expires: Date?)

    var isPro: Bool {
        if case .pro = self { return true }
        return false
    }
}

enum PremiumGate {

    /// The one place that decides whether a feature is available.
    static func isAvailable(_ feature: PremiumFeature, status: EntitlementStatus) -> Bool {
        status.isPro
    }

    /// Shooting modes available without Pro. Portrait is the free mode because
    /// it is the one people reach for first, and it shows what the guidance is
    /// actually worth.
    static let freeShootingModes: Set<ShootingMode> = [.portrait]

    static func isAvailable(_ mode: ShootingMode, status: EntitlementStatus) -> Bool {
        status.isPro || freeShootingModes.contains(mode)
    }

    /// The mode to fall back to when a Pro mode is in use and Pro goes away —
    /// a lapsed subscription should return you to a working camera, not a
    /// broken one.
    static let fallbackMode: ShootingMode = .portrait
}
