//
//  CameraModel.swift
//  CameraApp
//
//  The single source of truth for the camera screen.
//
//  It owns UI state and orchestrates three services that know nothing about
//  each other: `CaptureService` (AVCaptureSession), `FrameAnalysisService`
//  (Vision + signal processing) and `MediaLibraryService` (PhotoKit). All of
//  its state is main-actor isolated; every service call is an `await` away.
//

import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Observation
import Photos
import QuartzCore
import SwiftUI
import UIKit

@MainActor
@Observable
final class CameraModel {

    // MARK: - Nested state

    enum Status: Equatable {
        case idle
        case starting
        case running
        case cameraAccessDenied
        case failed(String)

        var isRunning: Bool { self == .running }
    }

    struct PhotoReview: Identifiable, Equatable {
        let id = UUID()
        let photo: CapturedPhoto
        let image: UIImage?

        static func == (lhs: PhotoReview, rhs: PhotoReview) -> Bool { lhs.id == rhs.id }
    }

    struct FocusIndicator: Identifiable, Equatable {
        let id = UUID()
        let point: CGPoint
    }

    // MARK: - Observable state

    private(set) var status: Status = .idle
    /// The one instruction currently on screen. `nil` before the first is earned.
    private(set) var guidance: GuidanceState?
    private(set) var faces: [DetectedFace] = []
    private(set) var level: LevelAssessment = .unavailable
    private(set) var shotQuality: ShotQualityAssessment = .unknown
    /// Framing geometry behind the current guidance, for the calibration overlay.
    private(set) var composition: CompositionAssessment = .noSubject
    /// True once Ready has held long enough that the instruction has said all
    /// it usefully can. The UI uses it to get out of the way.
    private(set) var isReadySettled = false
    /// What the camera is being pointed at, which decides what good framing
    /// even means.
    private(set) var shootingMode: ShootingMode = .portrait
    private(set) var configuration: CameraConfiguration = .unknown
    private(set) var selectedZoom: Double = 1
    private(set) var flashMode: FlashMode = .auto
    /// The guide drawn over the preview. A Pro guide left selected after a
    /// subscription lapses shows as thirds rather than disappearing.
    var compositionGuide: CompositionGuide {
        let selected = settings.compositionGuide
        guard CompositionGuide.free.contains(selected) else {
            return subscription.isPro ? selected : CompositionGuide.fallback
        }
        return selected
    }
    private(set) var isCapturing = false
    private(set) var isSwitchingCamera = false
    private(set) var isSaving = false
    private(set) var isInterrupted = false
    private(set) var review: PhotoReview?
    private(set) var focusIndicator: FocusIndicator?
    /// Exposure compensation in stops. Survives the focus square fading, so
    /// the top bar shows it until it is cleared or another tap resets it.
    private(set) var exposureBias: Float = 0
    private(set) var shutterFlashOpacity: Double = 0
    private(set) var message: String?
    private(set) var isPhotoAccessDenied = false
    var isAutoCaptureEnabled: Bool {
        settings.isAutoCaptureEnabled
            && PremiumGate.isAvailable(.autoCapture, status: subscription.status)
    }
    /// Reference framing is Pro. Exposed so the control can go straight to the
    /// paywall rather than opening a photo picker that leads nowhere.
    var isReferenceFramingAvailable: Bool {
        PremiumGate.isAvailable(.referenceFraming, status: subscription.status)
    }
    /// The self-timer currently set, so the camera screen can say so rather
    /// than surprising you with a countdown you configured days ago.
    var captureTimer: CaptureTimer { settings.captureTimer }

    /// Cycles the timer from the chip on the camera screen. It only appears
    /// once a timer is set, so it never has to offer "off to 3s" — turning it
    /// on is a settings decision, turning it off mid-shoot is not.
    func cycleCaptureTimer() {
        switch settings.captureTimer {
        case .off: settings.captureTimer = .three
        case .three: settings.captureTimer = .ten
        case .ten: settings.captureTimer = .off
        }
        cancelCountdown()
        signalSelection()
        present(message: settings.captureTimer == .off
            ? "Self-timer off"
            : "Self-timer \(settings.captureTimer.title)")
    }

    /// Says the unlock out loud. Locks quietly disappearing from the mode
    /// strip is easy to miss in the second after paying for them.
    func announceProUnlocked() {
        present(message: "Pro is active — everything unlocked")
    }

    /// Enhancement is Pro. The review screen marks the button rather than
    /// hiding it, so the offer is legible instead of a dead end.
    var isEnhancementAvailable: Bool {
        PremiumGate.isAvailable(.enhancement, status: subscription.status)
    }
    /// Whether the horizon hint may appear at all.
    var isLevelIndicatorEnabled: Bool { settings.isLevelIndicatorEnabled }
    /// Modes the current entitlement does not cover, so the selector can mark
    /// them rather than letting a tap fail silently.
    var lockedShootingModes: Set<ShootingMode> {
        Set(ShootingMode.allCases.filter { !PremiumGate.isAvailable($0, status: subscription.status) })
    }
    /// Takes a short burst and keeps the frame that scored best.
    var isBestShotEnabled: Bool {
        settings.isBestShotEnabled
            && PremiumGate.isAvailable(.bestShot, status: subscription.status)
    }

    /// Set when a locked feature is tapped, so the camera screen can offer the
    /// upgrade rather than silently doing nothing.
    private(set) var isPaywallPresented = false

    func requestPaywall() {
        isPaywallPresented = true
    }

    func dismissPaywall() {
        isPaywallPresented = false
    }
    /// The shortlist from a burst, best first. Empty for a single capture.
    private(set) var burstCandidates: [CapturedPhoto] = []
    private(set) var burstThumbnails: [UIImage?] = []
    private(set) var selectedCandidate = 0
    private(set) var autoCaptureProgress: Double = 0
    /// Seconds left on the self-timer, or nil when it is not running.
    private(set) var countdownRemaining: Int?

    var isReviewing: Bool { review != nil }

    // MARK: - Collaborators

    @ObservationIgnored let previewController = PreviewController()
    @ObservationIgnored let orientation = DeviceOrientationObserver()

    @ObservationIgnored private let analysisService: FrameAnalysisService
    @ObservationIgnored private let captureService: CaptureService
    @ObservationIgnored private let mediaLibrary = MediaLibraryService()
    /// Calibration values in force for the selected mode. Exposed so the debug
    /// overlay can draw the regions the rules actually test against.
    @ObservationIgnored private(set) var analysisConfiguration: AnalysisConfiguration

    @ObservationIgnored private var guidanceEngine: GuidanceEngine
    @ObservationIgnored private var autoCaptureController: AutoCaptureController
    @ObservationIgnored private var readyShownAt: TimeInterval?
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    /// Preferences live outside the model: it reads them, it does not own them.
    @ObservationIgnored let settings: CameraSettings
    @ObservationIgnored let subscription: SubscriptionService
    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var observationTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var messageTask: Task<Void, Never>?
    @ObservationIgnored private var focusTask: Task<Void, Never>?
    @ObservationIgnored private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    @ObservationIgnored private var rotationObservers: [NSKeyValueObservation] = []
    @ObservationIgnored private var pinchBaseZoom: Double?
    @ObservationIgnored private var isForegrounded = false

    var session: AVCaptureSession { captureService.session }

    init(
        settings: CameraSettings,
        subscription: SubscriptionService,
        shootingMode: ShootingMode = .portrait
    ) {
        self.settings = settings
        self.subscription = subscription
        self.shootingMode = shootingMode
        let analysisConfiguration = shootingMode.configuration
        self.analysisConfiguration = analysisConfiguration
        let analysis = FrameAnalysisService(configuration: analysisConfiguration)
        analysisService = analysis
        captureService = CaptureService(analyzer: analysis)
        guidanceEngine = GuidanceEngine(configuration: analysisConfiguration)
        autoCaptureController = AutoCaptureController(configuration: analysisConfiguration)
        previewController.onAttach = { [weak self] in
            guard let self else { return }
            Task { await self.refreshRotationCoordinator() }
        }
        previewController.onHardwareShutter = { [weak self] in
            self?.capturePhoto()
        }
    }

    // MARK: - Lifecycle

    /// Entry point for the camera screen. Safe to call repeatedly.
    func start() async {
        guard status == .idle || status == .cameraAccessDenied || isFailed else { return }
        isForegrounded = true
        resetAutoCapture(requiresReadyExit: true)
        status = .starting

        let access = await CameraPermission.requestAccess()
        guard access == .granted else {
            status = .cameraAccessDenied
            return
        }

        do {
            let configuration = try await captureService.start()
            apply(configuration)
            // Preferences are pushed once the session exists: resolution and
            // frame rate are properties of a configured device, not of the app.
            await applySettings()
            status = .running
            orientation.start()
            Haptics.shared.prepare()
            await analysisService.start()
            startConsumingAnalyses()
            startObservingSessionEvents()
            await refreshRotationCoordinator()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Called when the app returns to the foreground.
    func resume() async {
        isForegrounded = true
        resetAutoCapture(requiresReadyExit: true)
        switch status {
        case .cameraAccessDenied where CameraPermission.access == .granted:
            status = .idle
            await start()
        case .idle, .cameraAccessDenied:
            await start()
        case .running:
            guidanceEngine.reset()
            guidance = nil
            orientation.start()
            await analysisService.start()
            startConsumingAnalyses()
            do {
                let configuration = try await captureService.start()
                apply(configuration)
                await applySettings()
                await captureService.setAnalysisEnabled(!isReviewing)
                await refreshRotationCoordinator()
            } catch {
                status = .failed(error.localizedDescription)
            }
        case .starting, .failed:
            break
        }
    }

    /// Called when the app is backgrounded: the session is released so the
    /// camera is not held while another app may need it.
    func suspend() async {
        isForegrounded = false
        resetAutoCapture(requiresReadyExit: true)
        // A timer that kept running would fire the shutter at a pocket.
        cancelCountdown()
        orientation.stop()
        // The analysis consumer is deliberately left running: an AsyncStream is
        // single-shot, and cancelling its consumer would tear the pipeline down
        // for good. With the analyser stopped it simply parks until frames
        // start flowing again.
        await analysisService.stop()
        await captureService.stop()
        guidance = nil
        faces = []
        level = .unavailable
        shotQuality = .unknown
        guidanceEngine.reset()
    }

    // MARK: - Controls

    func toggleFlashMode() {
        flashMode = flashMode.next
        signalSelection()
    }

    func toggleAutoCapture() {
        guard PremiumGate.isAvailable(.autoCapture, status: subscription.status) else {
            requestPaywall()
            return
        }
        settings.isAutoCaptureEnabled.toggle()
        resetAutoCapture()
        signalSelection()
        present(message: isAutoCaptureEnabled ? "Auto capture on" : "Auto capture off")
    }

    func switchCamera() {
        guard status.isRunning, !isSwitchingCamera, !isCapturing else { return }
        isSwitchingCamera = true
        signalSelection()
        faces = []
        guidance = nil
        level = .unavailable
        shotQuality = .unknown
        composition = .noSubject
        isReadySettled = false
        readyShownAt = nil
        guidanceEngine.reset()
        resetAutoCapture(requiresReadyExit: true)
        // The other camera meters for itself.
        exposureBias = 0

        Task {
            defer { isSwitchingCamera = false }
            do {
                let configuration = try await captureService.switchCamera()
                apply(configuration)
                suppressAutoCaptureForSettling()
                await refreshRotationCoordinator()
            } catch {
                present(message: "Could not switch camera")
            }
        }
    }

    func setZoom(displayFactor: Double, ramp: Bool = true, feedback: Bool = true) {
        guard status.isRunning else { return }
        let capabilities = configuration.zoom
        let clamped = min(
            max(displayFactor, capabilities.minimumDisplayFactor),
            capabilities.maximumDisplayFactor
        )
        guard abs(clamped - selectedZoom) > 0.001 || ramp else { return }
        selectedZoom = clamped
        if feedback { signalSelection() }

        Task {
            let applied = await captureService.applyZoom(displayFactor: clamped, ramp: ramp)
            if abs(applied - selectedZoom) > 0.001 {
                selectedZoom = applied
            }
        }
    }

    func updatePinchZoom(scale: CGFloat) {
        guard status.isRunning else { return }
        let base = pinchBaseZoom ?? selectedZoom
        pinchBaseZoom = base
        setZoom(displayFactor: base * Double(scale), ramp: false, feedback: false)
    }

    func endPinchZoom() {
        pinchBaseZoom = nil
    }

    func focus(at point: CGPoint) {
        guard status.isRunning, let devicePoint = previewController.devicePoint(for: point) else { return }

        let indicator = FocusIndicator(point: point)
        focusIndicator = indicator
        signalSelection()
        suppressAutoCaptureForSettling()
        // Metering somewhere new starts from what the meter says, not from a
        // correction that was aimed at the last subject.
        setExposureBias(0)

        Task { await captureService.focus(at: devicePoint, isUserInitiated: true) }
        holdFocusIndicator(indicator, seconds: 1.2)
    }

    /// Exposure compensation, driven by the slider beside the focus square.
    /// Adjusting keeps the square on screen — it is the only thing anchoring
    /// the slider to the point being metered.
    func setExposureBias(_ bias: Float) {
        exposureBias = bias
        if let indicator = focusIndicator {
            holdFocusIndicator(indicator, seconds: 2.5)
        }
        Task {
            let applied = await captureService.setExposureBias(bias)
            // The device has the final say on the range it will accept.
            if abs(applied - bias) > 0.001 { exposureBias = applied }
        }
    }

    func clearExposureBias() {
        setExposureBias(0)
        signalSelection()
    }

    private func holdFocusIndicator(_ indicator: FocusIndicator, seconds: Double) {
        focusTask?.cancel()
        focusTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.focusIndicator?.id == indicator.id else { return }
            self.focusIndicator = nil
        }
    }

    // MARK: - Capture

    func capturePhoto() {
        resetAutoCapture(requiresReadyExit: true)

        // A second press during the countdown cancels it. Anything else would
        // mean the only way out is to wait for a photo you no longer want.
        if countdownTask != nil {
            cancelCountdown()
            present(message: "Timer cancelled")
            return
        }

        let seconds = settings.captureTimer.rawValue
        guard seconds > 0 else {
            performCapture()
            return
        }
        startCountdown(from: seconds)
    }

    /// The self-timer. Auto Capture deliberately does not go through here: it
    /// already waits for the right moment, and waiting twice would miss it.
    private func startCountdown(from seconds: Int) {
        guard status.isRunning, !isCapturing, !isReviewing else { return }
        countdownRemaining = seconds
        signalSelection()

        countdownTask = Task { [weak self] in
            for remaining in stride(from: seconds - 1, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.countdownRemaining = remaining > 0 ? remaining : nil
                if remaining > 0 { self.signalSelection() }
            }
            guard let self, !Task.isCancelled else { return }
            self.countdownTask = nil
            self.performCapture()
        }
    }

    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        countdownRemaining = nil
    }

    private func performCapture() {
        guard status.isRunning, !isCapturing, !isReviewing else { return }
        isCapturing = true
        Haptics.shared.shutterSignal()
        playShutterFlash()

        Task {
            defer { isCapturing = false }
            do {
                let photo = try await capturePreferredPhoto()
                // The preview stays live behind the review screen, but there is
                // nothing to guide while the shot is being judged.
                await captureService.setAnalysisEnabled(false)
                let image = await photo.makePreviewImage(maxDimension: 2200)
                guidance = nil
                faces = []
                level = .unavailable
                shotQuality = .unknown
                guidanceEngine.reset()
                review = PhotoReview(photo: photo, image: image)
            } catch {
                present(message: error.localizedDescription)
            }
        }
    }

    /// One frame, or the best of a short burst when Best Shot is on.
    private func capturePreferredPhoto() async throws -> CapturedPhoto {
        guard isBestShotEnabled, analysisConfiguration.burstFrameCount > 1 else {
            return try await captureService.capturePhoto(flashMode: flashMode)
        }
        let photos = try await captureService.capturePhotoBurst(
            flashMode: flashMode,
            count: analysisConfiguration.burstFrameCount
        )
        guard let first = photos.first else { throw CameraError.photoDataUnavailable }
        guard photos.count > 1 else { return first }

        let shortlist = await Self.shortlist(from: photos, limit: 3)
        guard let best = shortlist.photos.first else { return first }
        burstCandidates = shortlist.photos
        burstThumbnails = shortlist.thumbnails
        selectedCandidate = 0
        present(message: "Best of \(photos.count)")
        return best
    }

    private func clearBurstShortlist() {
        burstCandidates = []
        burstThumbnails = []
        selectedCandidate = 0
    }

    func retakePhoto() {
        review = nil
        enhancedReview = nil
        isShowingEnhanced = false
        clearBurstShortlist()
        isPhotoAccessDenied = false
        resetAutoCapture(requiresReadyExit: true)
        Task { await captureService.setAnalysisEnabled(true) }
    }

    func saveReviewedPhoto() {
        guard let review = displayedReview, !isSaving else { return }
        isSaving = true

        Task {
            defer { isSaving = false }
            let authorization = await mediaLibrary.requestAuthorization()
            guard MediaLibraryService.isUsable(authorization) else {
                isPhotoAccessDenied = true
                return
            }
            do {
                try await mediaLibrary.save(review.photo)
                self.review = nil
                enhancedReview = nil
                isShowingEnhanced = false
                clearBurstShortlist()
                isPhotoAccessDenied = false
                resetAutoCapture(requiresReadyExit: true)
                await captureService.setAnalysisEnabled(true)
                present(message: "Saved to Photos")
            } catch {
                present(message: error.localizedDescription)
            }
        }
    }

    // MARK: - Analysis

    private func startConsumingAnalyses() {
        guard analysisTask == nil else { return }
        let analyses = analysisService.analyses
        analysisTask = Task { [weak self] in
            for await analysis in analyses {
                guard !Task.isCancelled, let self else { return }
                self.handle(analysis)
            }
        }
    }

    private func handle(_ analysis: FrameAnalysis) {
        guard !isReviewing else { return }

        if faces != analysis.faces {
            faces = analysis.faces
        }
        if level != analysis.level {
            level = analysis.level
        }
        if shotQuality != analysis.quality {
            shotQuality = analysis.quality
        }
        if composition != analysis.composition {
            composition = analysis.composition
        }

        let now = CACurrentMediaTime()
        let update = guidanceEngine.update(with: analysis, now: now)
        if guidance != update.state {
            guidance = update.state
            readyShownAt = update.state?.isReady == true ? now : nil
        }
        if update.didBecomeReady {
            if settings.isHapticsEnabled {
                Haptics.shared.readySignal()
            }
        }
        updateReadySettled(now: now)

        let autoUpdate = autoCaptureController.update(
            isEnabled: isAutoCaptureEnabled,
            isReady: guidance?.isReady == true && analysis.quality.isReady,
            canCapture: canAutoCapture,
            now: CACurrentMediaTime()
        )
        if autoCaptureProgress != autoUpdate.progress {
            autoCaptureProgress = autoUpdate.progress
        }
        if autoUpdate.shouldCapture {
            performCapture()
        }
    }

    /// Once the shot has been Ready for a beat there is nothing left to say,
    /// so the instruction fades out and the picture gets the screen back. This
    /// is the difference between a helpful camera and a fighter-jet HUD.
    private func updateReadySettled(now: TimeInterval) {
        let settled: Bool
        if let shownAt = readyShownAt, guidance?.isReady == true {
            settled = (now - shownAt) >= analysisConfiguration.readyFadeDelay
        } else {
            settled = false
        }
        if isReadySettled != settled {
            isReadySettled = settled
        }
    }

    // MARK: - Enhancement

    private(set) var isEnhancing = false
    private(set) var enhancedReview: PhotoReview?
    /// Which version the review screen is showing. The original is the default,
    /// always kept, and never overwritten.
    private(set) var isShowingEnhanced = false

    /// The version the user is looking at, and therefore the one Save keeps.
    var displayedReview: PhotoReview? {
        isShowingEnhanced ? (enhancedReview ?? review) : review
    }

    /// Enhances on first use, then toggles between the two versions.
    func toggleEnhancement() {
        guard PremiumGate.isAvailable(.enhancement, status: subscription.status) else {
            requestPaywall()
            return
        }
        guard let review, !isEnhancing else { return }

        if enhancedReview != nil {
            isShowingEnhanced.toggle()
            signalSelection()
            return
        }

        isEnhancing = true
        Task {
            defer { isEnhancing = false }
            guard let enhanced = await Self.makeEnhanced(from: review.photo) else {
                present(message: "Already looks good")
                return
            }
            let image = await enhanced.makePreviewImage(maxDimension: 2200)
            enhancedReview = PhotoReview(photo: enhanced, image: image)
            isShowingEnhanced = true
            signalSelection()
        }
    }

    /// Measures the photo, plans a conservative adjustment and applies it —
    /// all on device, and always as a second copy rather than in place.
    private static func makeEnhanced(from photo: CapturedPhoto) async -> CapturedPhoto? {
        await Task.detached(priority: .userInitiated) { () -> CapturedPhoto? in
            guard let image = photo.makeScoringImage(maxDimension: 512),
                  let gray = ShotScorer.grayPixels(for: image) else { return nil }
            let statistics = ImageStatistics.measure(grayPixels: gray.pixels)
            let plan = EnhancementPlanner.plan(for: statistics)
            guard let data = PhotoEnhancer().enhance(data: photo.data, plan: plan) else {
                return nil
            }
            return CapturedPhoto(
                data: data,
                uniformTypeIdentifier: photo.uniformTypeIdentifier,
                isMirrored: photo.isMirrored
            )
        }.value
    }

    // MARK: - Reference framing

    /// Framing lifted from a reference photo, or `nil` when shooting free.
    private(set) var referenceFraming: ReferenceFraming?

    var isMatchingReference: Bool { referenceFraming?.hasSubject == true }

    /// Reads a reference photo's framing and aims the guidance at it.
    ///
    /// The image arrives from the system picker, so the app never gains access
    /// to the photo library, and the analysis happens on device.
    func setReference(imageData: Data) async {
        guard PremiumGate.isAvailable(.referenceFraming, status: subscription.status) else {
            requestPaywall()
            return
        }
        let framing = await Task.detached(priority: .userInitiated) { () -> ReferenceFraming in
            guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(
                      source,
                      0,
                      [
                          kCGImageSourceCreateThumbnailFromImageAlways: true,
                          kCGImageSourceCreateThumbnailWithTransform: true,
                          kCGImageSourceThumbnailMaxPixelSize: 1024
                      ] as CFDictionary
                  ) else { return .none }
            return ReferenceFramingExtractor.extract(from: image)
        }.value

        guard framing.hasSubject else {
            present(message: "No subject found in that photo")
            return
        }

        referenceFraming = framing
        guidanceEngine = GuidanceEngine(configuration: analysisConfiguration)
        resetAutoCapture(requiresReadyExit: true)
        await analysisService.setCompositionTarget(framing.target)
        present(message: "Matching reference framing")
    }

    func clearReference() {
        guard referenceFraming != nil else { return }
        referenceFraming = nil
        guidanceEngine = GuidanceEngine(configuration: analysisConfiguration)
        resetAutoCapture(requiresReadyExit: true)
        signalSelection()
        Task { await analysisService.setCompositionTarget(.neutral) }
        present(message: "Reference cleared")
    }

    // MARK: - Best shot

    func toggleBestShot() {
        guard PremiumGate.isAvailable(.bestShot, status: subscription.status) else {
            requestPaywall()
            return
        }
        settings.isBestShotEnabled.toggle()
        signalSelection()
        present(message: isBestShotEnabled ? "Best shot on" : "Best shot off")
    }

    /// Scores a burst and returns a shortlist, best first.
    ///
    /// Runs off the main actor: decoding and scoring three frames is real work
    /// and the preview is still live behind the review screen. Thumbnails come
    /// back with it so the strip does not have to decode again on the main
    /// thread.
    private static func shortlist(
        from photos: [CapturedPhoto],
        limit: Int
    ) async -> (photos: [CapturedPhoto], thumbnails: [UIImage?]) {
        await Task.detached(priority: .userInitiated) { () -> ([CapturedPhoto], [UIImage?]) in
            var scores: [ShotScore] = []
            for (index, photo) in photos.enumerated() {
                guard let image = photo.makeScoringImage(
                    maxDimension: ShotScorer.scoringDimension
                ) else { continue }
                scores.append(ShotScorer.score(image: image, index: index))
            }
            let ranked = BestShotSelector.rank(scores, limit: limit)
                .compactMap { photos.indices.contains($0.id) ? photos[$0.id] : nil }
            guard !ranked.isEmpty else { return (photos, []) }
            let thumbnails = ranked.map { candidate -> UIImage? in
                candidate.makeScoringImage(maxDimension: 220).map(UIImage.init(cgImage:))
            }
            return (ranked, thumbnails)
        }.value
    }

    /// Switches the review to another frame from the shortlist.
    func selectCandidate(_ index: Int) {
        guard burstCandidates.indices.contains(index), index != selectedCandidate else { return }
        selectedCandidate = index
        // Enhancement belongs to the frame it was computed from.
        enhancedReview = nil
        isShowingEnhanced = false
        signalSelection()

        let photo = burstCandidates[index]
        Task {
            let image = await photo.makePreviewImage(maxDimension: 2200)
            guard selectedCandidate == index else { return }
            review = PhotoReview(photo: photo, image: image)
        }
    }

    // MARK: - Feedback

    /// All selection feedback goes through here so the haptics preference is
    /// honoured in one place rather than at sixteen call sites.
    private func signalSelection() {
        guard settings.isHapticsEnabled else { return }
        signalSelection()
    }

    // MARK: - Settings

    /// Pushes preferences that the capture session has to be told about.
    /// Called at start-up and whenever the settings sheet closes.
    func applySettings() async {
        let isPro = subscription.isPro
        await captureService.applyCaptureSettings(
            resolution: isPro ? settings.photoResolution : .standard,
            frameRate: settings.previewFrameRate,
            mirrorFrontPhotos: settings.mirrorFrontPhotos
        )
        await captureService.setAnalysisRate(settings.responsiveness.analysesPerSecond)

        // A lapsed subscription must leave a working camera, not a broken one.
        if !PremiumGate.isAvailable(shootingMode, status: subscription.status),
           shootingMode != PremiumGate.fallbackMode {
            setShootingModeUnchecked(PremiumGate.fallbackMode)
        }
    }

    // MARK: - Shooting mode

    /// Switches calibration wholesale. Every downstream rule reads its numbers
    /// from the configuration, so a mode change is a data change rather than a
    /// branch scattered through the analysis code.
    func setShootingMode(_ mode: ShootingMode) {
        guard mode != shootingMode else { return }
        guard PremiumGate.isAvailable(mode, status: subscription.status) else {
            requestPaywall()
            return
        }
        setShootingModeUnchecked(mode)
    }

    /// The mode change itself, with the entitlement check already made. Used
    /// directly when dropping back to a free mode after a subscription lapses.
    private func setShootingModeUnchecked(_ mode: ShootingMode) {
        shootingMode = mode
        analysisConfiguration = mode.configuration
        guidanceEngine = GuidanceEngine(configuration: analysisConfiguration)
        autoCaptureController = AutoCaptureController(configuration: analysisConfiguration)

        guidance = nil
        composition = .noSubject
        shotQuality = .unknown
        isReadySettled = false
        readyShownAt = nil
        resetAutoCapture(requiresReadyExit: true)
        signalSelection()

        Task {
            await analysisService.setMode(mode)
            // A mode change resets the analyser's target, so re-apply any
            // reference the user is still shooting against.
            if let target = referenceFraming?.target {
                await analysisService.setCompositionTarget(target)
            }
        }
        present(message: mode.title)
    }

    // MARK: - Debug

    /// Calibration overlay. The toggle compiles to nothing outside DEBUG, so
    /// this stays false in shipping builds.
    private(set) var isDebugOverlayVisible = false

    func toggleDebugOverlay() {
        #if DEBUG
        isDebugOverlayVisible.toggle()
        signalSelection()
        #endif
    }

    // MARK: - Session events

    private func startObservingSessionEvents() {
        guard observationTasks.isEmpty else { return }
        let session = captureService.session
        let center = NotificationCenter.default

        observationTasks.append(
            Task { [weak self] in
                for await notification in center.notifications(
                    named: AVCaptureSession.wasInterruptedNotification,
                    object: session
                ) {
                    guard let self else { return }
                    self.handleInterruption(notification)
                }
            }
        )

        observationTasks.append(
            Task { [weak self] in
                for await _ in center.notifications(
                    named: AVCaptureSession.interruptionEndedNotification,
                    object: session
                ) {
                    guard let self else { return }
                    self.isInterrupted = false
                    await self.captureService.setAnalysisEnabled(!self.isReviewing)
                }
            }
        )

        observationTasks.append(
            Task { [weak self] in
                for await notification in center.notifications(
                    named: AVCaptureSession.runtimeErrorNotification,
                    object: session
                ) {
                    guard let self else { return }
                    await self.handleRuntimeError(notification)
                }
            }
        )

        observationTasks.append(
            Task { [weak self] in
                for await _ in center.notifications(
                    named: AVCaptureDevice.subjectAreaDidChangeNotification
                ) {
                    guard let self else { return }
                    self.suppressAutoCaptureForSettling()
                    await self.captureService.resetFocusAndExposure()
                }
            }
        )
    }

    private func handleInterruption(_ notification: Notification) {
        isInterrupted = true
        guidance = nil
        faces = []
        level = .unavailable
        shotQuality = .unknown
        guidanceEngine.reset()
        resetAutoCapture(requiresReadyExit: true)

        let rawReason = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int
        let reason = rawReason.flatMap(AVCaptureSession.InterruptionReason.init(rawValue:))
        switch reason {
        case .videoDeviceNotAvailableInBackground:
            break // Expected while backgrounded; nothing worth saying.
        case .audioDeviceInUseByAnotherClient, .videoDeviceInUseByAnotherClient:
            present(message: "Camera in use by another app")
        case .videoDeviceNotAvailableWithMultipleForegroundApps:
            present(message: "Camera paused in Split View")
        case .videoDeviceNotAvailableDueToSystemPressure:
            present(message: "Camera paused to cool down")
        default:
            break
        }
    }

    private func handleRuntimeError(_ notification: Notification) async {
        guidance = nil
        faces = []
        level = .unavailable
        shotQuality = .unknown
        guidanceEngine.reset()
        resetAutoCapture(requiresReadyExit: true)

        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError
        // A media services reset invalidates the session; restarting is the
        // documented recovery.
        if error?.code == .mediaServicesWereReset {
            do {
                let configuration = try await captureService.start()
                apply(configuration)
                suppressAutoCaptureForSettling()
                await refreshRotationCoordinator()
                return
            } catch {
                status = .failed(error.localizedDescription)
                return
            }
        }
        present(message: error?.localizedDescription ?? "The camera stopped unexpectedly")
    }

    // MARK: - Rotation

    /// Rebuilds the rotation coordinator for the active device. The coordinator
    /// reports two angles: one that keeps the preview upright, and one that
    /// keeps captured photos horizon-level regardless of how the phone is held.
    private func refreshRotationCoordinator() async {
        guard let device = await captureService.currentDevice else { return }

        rotationObservers.removeAll()
        let coordinator = AVCaptureDevice.RotationCoordinator(
            device: device,
            previewLayer: previewController.previewLayer
        )
        rotationCoordinator = coordinator

        applyPreviewRotation(coordinator.videoRotationAngleForHorizonLevelPreview)
        await captureService.setCaptureRotationAngle(coordinator.videoRotationAngleForHorizonLevelCapture)

        rotationObservers.append(
            coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: .new) { [weak self] _, change in
                guard let angle = change.newValue else { return }
                Task { @MainActor in
                    self?.applyPreviewRotation(angle)
                }
            }
        )
        rotationObservers.append(
            coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: .new) { [weak self] _, change in
                guard let angle = change.newValue else { return }
                Task { @MainActor in
                    await self?.captureService.setCaptureRotationAngle(angle)
                }
            }
        )
    }

    private func applyPreviewRotation(_ angle: CGFloat) {
        previewController.setRotationAngle(angle)
        Task { await captureService.setPreviewRotationAngle(angle) }
    }

    // MARK: - Helpers

    private var isFailed: Bool {
        if case .failed = status { return true }
        return false
    }

    private var canAutoCapture: Bool {
        isForegrounded
            && status.isRunning
            && !isCapturing
            && !isReviewing
            && !isSwitchingCamera
            && !isInterrupted
    }

    private func resetAutoCapture(requiresReadyExit: Bool = false) {
        autoCaptureProgress = 0
        autoCaptureController.reset(requiresReadyExit: requiresReadyExit)
    }

    private func suppressAutoCaptureForSettling() {
        autoCaptureProgress = 0
        autoCaptureController.suppress(
            until: CACurrentMediaTime() + analysisConfiguration.focusSettlingDwell
        )
    }

    private func apply(_ configuration: CameraConfiguration) {
        self.configuration = configuration
        selectedZoom = configuration.currentDisplayZoom
    }

    private func playShutterFlash() {
        withAnimation(.easeOut(duration: 0.06)) {
            shutterFlashOpacity = 1
        }
        Task {
            try? await Task.sleep(for: .milliseconds(70))
            withAnimation(.easeIn(duration: 0.22)) {
                shutterFlashOpacity = 0
            }
        }
    }

    private func present(message text: String) {
        message = text
        messageTask?.cancel()
        messageTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }
}
