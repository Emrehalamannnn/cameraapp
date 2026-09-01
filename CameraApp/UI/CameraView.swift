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

    /// Size of the preview surface itself — measured after safe areas are
    /// ignored, so it matches the AVCaptureVideoPreviewLayer's own bounds.
    @State private var previewSize: CGSize = .zero
    @State private var referenceItem: PhotosPickerItem?

    init(model: CameraModel) {
        self.model = model
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
                    review: review,
                    isSaving: model.isSaving,
                    isPhotoAccessDenied: model.isPhotoAccessDenied,
                    onRetake: { model.retakePhoto() },
                    onSave: { model.saveReviewedPhoto() }
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

                if model.guidance?.message == .straightenCamera {
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

            if model.isGridVisible {
                RuleOfThirdsGrid()
                    .transition(.opacity)
            }

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
        .animation(.easeInOut(duration: 0.2), value: model.isGridVisible)
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

            Spacer(minLength: 0)

            referenceControl

            GlassCircleButton(
                systemImage: model.isBestShotEnabled ? "square.stack.fill" : "square.stack",
                accessibilityLabel: model.isBestShotEnabled
                    ? "Disable Best Shot"
                    : "Enable Best Shot",
                isHighlighted: model.isBestShotEnabled,
                rotation: model.orientation.controlRotation
            ) {
                model.toggleBestShot()
            }

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

            #if DEBUG
            // A long press opens the calibration overlay. Debug builds only —
            // in Release this branch does not exist at all.
            gridButton.simultaneousGesture(
                LongPressGesture(minimumDuration: 0.8).onEnded { _ in
                    model.toggleDebugOverlay()
                }
            )
            #else
            gridButton
            #endif
        }
    }

    /// Reference framing. Picking goes through the system photo picker, which
    /// hands over one image without the app ever gaining library access.
    @ViewBuilder
    private var referenceControl: some View {
        if model.isMatchingReference {
            GlassCircleButton(
                systemImage: "photo.fill.on.rectangle.fill",
                accessibilityLabel: "Clear reference framing",
                isHighlighted: true,
                rotation: model.orientation.controlRotation
            ) {
                model.clearReference()
            }
        } else {
            PhotosPicker(selection: $referenceItem, matching: .images, photoLibrary: .shared()) {
                GlassCircleLabel(
                    systemImage: "photo.on.rectangle",
                    rotation: model.orientation.controlRotation
                )
            }
            .accessibilityLabel(Text("Match a reference photo"))
        }
    }

    private var gridButton: some View {
        GlassCircleButton(
            systemImage: "grid",
            accessibilityLabel: model.isGridVisible ? "Hide grid" : "Show grid",
            isHighlighted: model.isGridVisible,
            rotation: model.orientation.controlRotation
        ) {
            model.toggleGrid()
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 14) {
            ModeSelector(
                modes: ShootingMode.allCases,
                selected: model.shootingMode,
                rotation: model.orientation.controlRotation,
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
