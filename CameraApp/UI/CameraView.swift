//
//  CameraView.swift
//  CameraApp
//
//  The camera screen: preview edge to edge, everything else floating on top.
//

import AVFoundation
import PhotosUI
import SwiftUI

struct CameraView: View {

    let model: CameraModel
    /// The camera screen does not own the settings sheet; it only asks for it.
    var onOpenSettings: () -> Void = {}

    /// Size of the preview surface itself — measured after safe areas are
    /// ignored, so it matches the AVCaptureVideoPreviewLayer's own bounds.
    @State private var previewSize: CGSize = .zero
    @State private var referenceItem: PhotosPickerItem? = nil

    init(model: CameraModel, onOpenSettings: @escaping () -> Void = {}) {
        self.model = model
        self.onOpenSettings = onOpenSettings
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch model.status {
            case .cameraAccessDenied:
                PermissionView(
                    symbolName: "camera.fill",
                    title: "Camera access is off",
                    message: "CameraApp needs the camera to frame and take photos. You can turn it on in Settings."
                )
            case .failed(let description):
                CameraUnavailableView(message: description) {
                    Task { await model.start() }
                }
            default:
                cameraInterface
            }

            if let review = model.review {
                PhotoReviewView(
                    review: model.displayedReview ?? review,
                    isSaving: model.isSaving,
                    isPhotoAccessDenied: model.isPhotoAccessDenied,
                    isEnhancing: model.isEnhancing,
                    isShowingEnhanced: model.isShowingEnhanced,
                    candidates: model.burstThumbnails,
                    selectedCandidate: model.selectedCandidate,
                    onRetake: { model.retakePhoto() },
                    onSave: { model.saveReviewedPhoto() },
                    onToggleEnhancement: { model.toggleEnhancement() },
                    onSelectCandidate: { model.selectCandidate($0) }
                )
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: model.isReviewing)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .task { await model.start() }
        .onChange(of: referenceItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await model.setReference(imageData: data)
                }
                referenceItem = nil
            }
        }
    }

    // MARK: - Camera interface

    private var cameraInterface: some View {
        ZStack {
            previewSurface

            Color.white
                .ignoresSafeArea()
                .opacity(model.shutterFlashOpacity)
                .allowsHitTesting(false)

            if let remaining = model.countdownRemaining {
                CountdownView(seconds: remaining)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                GuidanceBanner(state: model.guidance, rotation: model.orientation.controlRotation)
                    .padding(.top, 18)
                    // Once the shot has been Ready for a beat the instruction
                    // has said all it can, so it steps aside and leaves the
                    // picture the screen.
                    .opacity(model.isReadySettled ? 0 : 1)
                    .animation(.easeInOut(duration: 0.45), value: model.isReadySettled)

                if model.isLevelIndicatorEnabled, model.guidance?.message == .straightenCamera {
                    LevelIndicatorView(
                        rollDegrees: model.level.rollDegrees,
                        rotation: model.orientation.controlRotation
                    )
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }

                Spacer(minLength: 0)

                if let message = model.message {
                    MessageToast(text: message)
                        .padding(.bottom, 14)
                }

                bottomControls
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
            .animation(.easeInOut(duration: 0.2), value: model.message)
        }
        .animation(.easeOut(duration: 0.15), value: model.countdownRemaining)
    }

    private var previewSurface: some View {
        let geometry = PreviewGeometry(
            viewSize: previewSize,
            contentAspectRatio: model.configuration.contentAspectRatio
        )

        return ZStack {
            CameraPreview(session: model.session, controller: model.previewController)
                .opacity(model.isSwitchingCamera ? 0 : 1)
                .animation(.easeInOut(duration: 0.18), value: model.isSwitchingCamera)

            CompositionGuideOverlay(guide: model.compositionGuide)
                .transition(.opacity)
                .id(model.compositionGuide)

            SubjectOverlay(
                faces: model.faces,
                geometry: geometry,
                isReady: model.guidance?.isReady == true
            )

            DirectionalCueView(direction: model.guidance?.direction ?? .none)

            #if DEBUG
            if model.isDebugOverlayVisible {
                DebugOverlayView(
                    quality: model.shotQuality,
                    composition: model.composition,
                    level: model.level,
                    faces: model.faces,
                    geometry: geometry,
                    configuration: model.analysisConfiguration
                )
            }
            #endif

            if let focus = model.focusIndicator {
                FocusIndicatorView()
                    .position(focus.point)
                    .id(focus.id)
                    .transition(.opacity)

                ExposureSlider(bias: model.exposureBias) { model.setExposureBias($0) }
                    .position(exposureSliderPoint(for: focus.point))
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .background {
            // Applied after `ignoresSafeArea`, so this reports the expanded,
            // full-screen frame the preview layer actually occupies.
            GeometryReader { proxy in
                Color.clear
                    .onAppear { previewSize = proxy.size }
                    .onChange(of: proxy.size) { _, newValue in previewSize = newValue }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 1, coordinateSpace: .local) { location in
            model.focus(at: location)
        }
        .gesture(
            MagnifyGesture()
                .onChanged { value in model.updatePinchZoom(scale: value.magnification) }
                .onEnded { _ in model.endPinchZoom() }
        )
        .animation(.easeInOut(duration: 0.2), value: model.compositionGuide)
        .animation(.easeOut(duration: 0.18), value: model.focusIndicator)
    }

    /// Puts the slider beside the focus square, on whichever side has room.
    private func exposureSliderPoint(for focus: CGPoint) -> CGPoint {
        let offset: CGFloat = 62
        let margin: CGFloat = 30
        let x = focus.x + offset > previewSize.width - margin
            ? focus.x - offset
            : focus.x + offset
        return CGPoint(x: x, y: focus.y)
    }

    // MARK: - Controls

    private var topBar: some View {
        HStack(spacing: 12) {
            GlassCircleButton(
                systemImage: model.flashMode.symbolName,
                accessibilityLabel: model.flashMode.accessibilityLabel,
                isHighlighted: model.flashMode == .on,
                rotation: model.orientation.controlRotation
            ) {
                model.toggleFlashMode()
            }
            .opacity(model.configuration.isFlashAvailable ? 1 : 0.35)
            .disabled(!model.configuration.isFlashAvailable)

            if model.exposureBias != 0 {
                // The correction outlives the focus square that set it, so it
                // says so — and tapping puts it back to what the meter wants.
                Button { model.clearExposureBias() } label: {
                    Text(ExposureFormatter.label(for: model.exposureBias))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.yellow)
                        .rotationEffect(model.orientation.controlRotation)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Capsule().fill(.ultraThinMaterial))
                }
                .buttonStyle(PressableButtonStyle(pressedScale: 0.94))
                .accessibilityLabel(Text("Exposure \(ExposureFormatter.label(for: model.exposureBias)), reset"))
                .transition(.opacity)
            }

            Spacer(minLength: 0)

            referenceControl

            GlassCircleButton(
                systemImage: "timer",
                accessibilityLabel: model.isAutoCaptureEnabled
                    ? "Disable Auto Capture"
                    : "Enable Auto Capture",
                isHighlighted: model.isAutoCaptureEnabled,
                rotation: model.orientation.controlRotation
            ) {
                model.toggleAutoCapture()
            }

            // Everything else — the grid, Best Shot, resolution, the
            // subscription — lives behind this one button. The camera screen
            // stays a camera screen.
            #if DEBUG
            // A long press opens the calibration overlay. Debug builds only —
            // in Release this branch does not exist at all.
            settingsButton.simultaneousGesture(
                LongPressGesture(minimumDuration: 0.8).onEnded { _ in
                    model.toggleDebugOverlay()
                }
            )
            #else
            settingsButton
            #endif
        }
    }

    private var settingsButton: some View {
        GlassCircleButton(
            systemImage: "slider.horizontal.3",
            accessibilityLabel: "Settings",
            rotation: model.orientation.controlRotation,
            action: onOpenSettings
        )
    }

    /// Reference framing. Picking goes through the system photo picker, which
    /// hands over one image without the app ever gaining library access.
    @ViewBuilder
    private var referenceControl: some View {
        if !model.isReferenceFramingAvailable {
            // Opening the picker only to refuse the photo afterwards wastes the
            // customer's time and looks broken. Say it up front instead.
            GlassCircleButton(
                systemImage: "photo.on.rectangle",
                accessibilityLabel: "Match a reference photo, Pro",
                rotation: model.orientation.controlRotation
            ) {
                model.requestPaywall()
            }
            .opacity(0.55)
        } else if model.isMatchingReference {
            GlassCircleButton(
                systemImage: "photo.fill.on.rectangle.fill",
                accessibilityLabel: "Clear reference framing",
                isHighlighted: true,
                rotation: model.orientation.controlRotation
            ) {
                model.clearReference()
            }
        } else {
            // Read the rotation before handing a closure to the picker: the
            // label closure is Sendable, and touching main-actor state from
            // inside it is an error under the Swift 6 language mode.
            let rotation = model.orientation.controlRotation
            PhotosPicker(selection: $referenceItem, matching: .images, photoLibrary: .shared()) {
                GlassCircleLabel(systemImage: "photo.on.rectangle", rotation: rotation)
            }
            .accessibilityLabel(Text("Match a reference photo"))
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 14) {
            ModeSelector(
                modes: ShootingMode.allCases,
                selected: model.shootingMode,
                rotation: model.orientation.controlRotation,
                lockedModes: model.lockedShootingModes,
                onSelect: { model.setShootingMode($0) }
            )

            if model.configuration.zoom.displayOptions.count > 1 {
                ZoomSelector(
                    options: model.configuration.zoom.displayOptions,
                    currentZoom: model.selectedZoom,
                    rotation: model.orientation.controlRotation,
                    onSelect: { model.setZoom(displayFactor: $0) }
                )
            }

            ZStack {
                ShutterButton(
                    isReady: model.guidance?.isReady == true,
                    isBusy: model.isCapturing,
                    isEnabled: model.status.isRunning && !model.isInterrupted,
                    autoCaptureProgress: model.autoCaptureProgress
                ) {
                    model.capturePhoto()
                }

                HStack {
                    Spacer()
                    GlassCircleButton(
                        systemImage: "arrow.triangle.2.circlepath",
                        accessibilityLabel: "Switch camera",
                        diameter: 48,
                        rotation: model.orientation.controlRotation
                    ) {
                        model.switchCamera()
                    }
                    .disabled(model.isSwitchingCamera || model.isCapturing)
                }
            }
        }
    }
}

// MARK: - Failure state

struct CameraUnavailableView: View {

    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.white.opacity(0.85))
            Text("The camera is unavailable")
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
            Button("Try Again", action: onRetry)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.black)
                .padding(.horizontal, 22)
                .padding(.vertical, 11)
                .background(Capsule().fill(Color.white))
                .padding(.top, 4)
        }
        .padding(32)
    }
}
