//
//  CameraSettings.swift
//  CameraApp
//
//  Everything the camera screen does not need to ask about on the front page.
//
//  These are preferences, not state: they survive relaunch, and the camera
//  reads them rather than owning them. Anything here is deliberately absent
//  from the shooting UI, which stays down to the handful of controls you
//  actually reach for mid-shot.
//

import Foundation
import Observation

enum PhotoResolution: String, CaseIterable, Identifiable, Sendable {
    /// Everything the active format can give. Bigger files, slower saves.
    case maximum
    /// The sensor's natural output. Faster, and enough for almost everything.
    case standard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .maximum: return "Maximum"
        case .standard: return "Standard"
        }
    }

    var detail: String {
        switch self {
        case .maximum: return "Highest resolution your camera supports"
        case .standard: return "Faster capture, smaller files"
        }
    }
}

enum PreviewFrameRate: Int, CaseIterable, Identifiable, Sendable {
    case thirty = 30
    case sixty = 60

    var id: Int { rawValue }
    var title: String { "\(rawValue) fps" }

    var detail: String {
        switch self {
        case .thirty: return "Smooth, and easier on the battery"
        case .sixty: return "Smoothest preview, more power"
        }
    }
}

/// How often the guidance re-reads the scene. Faster feels more alive and
/// costs more battery; slower is calmer and cheaper.
enum GuidanceResponsiveness: String, CaseIterable, Identifiable, Sendable {
    case relaxed
    case balanced
    case responsive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .relaxed: return "Relaxed"
        case .balanced: return "Balanced"
        case .responsive: return "Responsive"
        }
    }

    /// Analyses per second handed to the frame processor.
    var analysesPerSecond: Double {
        switch self {
        case .relaxed: return 8
        case .balanced: return 12
        case .responsive: return 20
        }
    }
}

/// Persisted preferences.
///
/// The properties are written out longhand rather than left as plain stored
/// properties, because `@Observable` claims the accessors of anything it
/// tracks: a `didSet` on a tracked property does not compile. Spelling out
/// `access` / `withMutation` keeps both halves — SwiftUI still sees every
/// change, and every change still reaches `UserDefaults` on the spot, so a
/// preference survives even if the app is killed a second later.
@MainActor
@Observable
final class CameraSettings {

    enum Key {
        static let photoResolution = "settings.photoResolution"
        static let previewFrameRate = "settings.previewFrameRate"
        static let responsiveness = "settings.guidanceResponsiveness"
        static let grid = "settings.gridVisible"
        static let levelIndicator = "settings.levelIndicator"
        static let haptics = "settings.haptics"
        static let bestShot = "settings.bestShot"
        static let autoCapture = "settings.autoCapture"
        static let mirrorFront = "settings.mirrorFrontPhotos"
        static let hasSeenPaywall = "settings.hasSeenPaywall"
    }

    @ObservationIgnored private let defaults: UserDefaults

    @ObservationIgnored private var storedPhotoResolution: PhotoResolution
    @ObservationIgnored private var storedPreviewFrameRate: PreviewFrameRate
    @ObservationIgnored private var storedResponsiveness: GuidanceResponsiveness
    @ObservationIgnored private var storedIsGridVisible: Bool
    @ObservationIgnored private var storedIsLevelIndicatorEnabled: Bool
    @ObservationIgnored private var storedIsHapticsEnabled: Bool
    @ObservationIgnored private var storedIsBestShotEnabled: Bool
    @ObservationIgnored private var storedIsAutoCaptureEnabled: Bool
    @ObservationIgnored private var storedMirrorFrontPhotos: Bool
    @ObservationIgnored private var storedHasSeenPaywall: Bool

    var photoResolution: PhotoResolution {
        get { access(keyPath: \.photoResolution); return storedPhotoResolution }
        set {
            withMutation(keyPath: \.photoResolution) { storedPhotoResolution = newValue }
            defaults.set(newValue.rawValue, forKey: Key.photoResolution)
        }
    }

    var previewFrameRate: PreviewFrameRate {
        get { access(keyPath: \.previewFrameRate); return storedPreviewFrameRate }
        set {
            withMutation(keyPath: \.previewFrameRate) { storedPreviewFrameRate = newValue }
            defaults.set(newValue.rawValue, forKey: Key.previewFrameRate)
        }
    }

    var responsiveness: GuidanceResponsiveness {
        get { access(keyPath: \.responsiveness); return storedResponsiveness }
        set {
            withMutation(keyPath: \.responsiveness) { storedResponsiveness = newValue }
            defaults.set(newValue.rawValue, forKey: Key.responsiveness)
        }
    }

    var isGridVisible: Bool {
        get { access(keyPath: \.isGridVisible); return storedIsGridVisible }
        set {
            withMutation(keyPath: \.isGridVisible) { storedIsGridVisible = newValue }
            defaults.set(newValue, forKey: Key.grid)
        }
    }

    var isLevelIndicatorEnabled: Bool {
        get { access(keyPath: \.isLevelIndicatorEnabled); return storedIsLevelIndicatorEnabled }
        set {
            withMutation(keyPath: \.isLevelIndicatorEnabled) { storedIsLevelIndicatorEnabled = newValue }
            defaults.set(newValue, forKey: Key.levelIndicator)
        }
    }

    var isHapticsEnabled: Bool {
        get { access(keyPath: \.isHapticsEnabled); return storedIsHapticsEnabled }
        set {
            withMutation(keyPath: \.isHapticsEnabled) { storedIsHapticsEnabled = newValue }
            defaults.set(newValue, forKey: Key.haptics)
        }
    }

    /// Takes a short burst and keeps the best frames.
    var isBestShotEnabled: Bool {
        get { access(keyPath: \.isBestShotEnabled); return storedIsBestShotEnabled }
        set {
            withMutation(keyPath: \.isBestShotEnabled) { storedIsBestShotEnabled = newValue }
            defaults.set(newValue, forKey: Key.bestShot)
        }
    }

    var isAutoCaptureEnabled: Bool {
        get { access(keyPath: \.isAutoCaptureEnabled); return storedIsAutoCaptureEnabled }
        set {
            withMutation(keyPath: \.isAutoCaptureEnabled) { storedIsAutoCaptureEnabled = newValue }
            defaults.set(newValue, forKey: Key.autoCapture)
        }
    }

    /// Whether front-camera photos are saved mirrored, matching the preview.
    /// Off by default, which is what the system camera does.
    var mirrorFrontPhotos: Bool {
        get { access(keyPath: \.mirrorFrontPhotos); return storedMirrorFrontPhotos }
        set {
            withMutation(keyPath: \.mirrorFrontPhotos) { storedMirrorFrontPhotos = newValue }
            defaults.set(newValue, forKey: Key.mirrorFront)
        }
    }

    /// Set the first time the paywall is shown, so it is offered once rather
    /// than on every launch.
    var hasSeenPaywall: Bool {
        get { access(keyPath: \.hasSeenPaywall); return storedHasSeenPaywall }
        set {
            withMutation(keyPath: \.hasSeenPaywall) { storedHasSeenPaywall = newValue }
            defaults.set(newValue, forKey: Key.hasSeenPaywall)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        storedPhotoResolution = PhotoResolution(
            rawValue: defaults.string(forKey: Key.photoResolution) ?? ""
        ) ?? .standard
        storedPreviewFrameRate = PreviewFrameRate(
            rawValue: defaults.integer(forKey: Key.previewFrameRate)
        ) ?? .thirty
        storedResponsiveness = GuidanceResponsiveness(
            rawValue: defaults.string(forKey: Key.responsiveness) ?? ""
        ) ?? .balanced
        storedIsGridVisible = defaults.object(forKey: Key.grid) as? Bool ?? true
        storedIsLevelIndicatorEnabled = defaults.object(forKey: Key.levelIndicator) as? Bool ?? true
        storedIsHapticsEnabled = defaults.object(forKey: Key.haptics) as? Bool ?? true
        storedIsBestShotEnabled = defaults.object(forKey: Key.bestShot) as? Bool ?? false
        storedIsAutoCaptureEnabled = defaults.object(forKey: Key.autoCapture) as? Bool ?? false
        storedMirrorFrontPhotos = defaults.object(forKey: Key.mirrorFront) as? Bool ?? false
        storedHasSeenPaywall = defaults.object(forKey: Key.hasSeenPaywall) as? Bool ?? false
    }
}
