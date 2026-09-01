//
//  SettingsView.swift
//  CameraApp
//
//  Everything that is not worth a button on the camera screen.
//
//  Styled by hand rather than with a stock Form: the camera is black and
//  restrained, and a default grey settings sheet in the middle of it looks like
//  a different app.
//

import SwiftUI

struct SettingsView: View {

    let settings: CameraSettings
    let subscription: SubscriptionService
    var onDismiss: () -> Void = {}

    /// The paywall is presented from here rather than handed back to the
    /// camera screen: every route into it from this sheet wants to come
    /// straight back to the row that was tapped.
    @State private var isShowingPaywall = false
    @State private var isShowingResetConfirmation = false

    var body: some View {
        ZStack {
            Color(red: 0.045, green: 0.05, blue: 0.06).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 26) {
                    subscriptionSection
                    cameraSection
                    guidanceSection
                    captureSection
                    aboutSection
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .safeAreaInset(edge: .top) { header }
        .preferredColorScheme(.dark)
        // Settings is a reading surface, so its text scales — unlike the
        // camera HUD, where the control sizes are deliberate. Capped, because
        // past accessibility2 the pill rows stop being rows.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .sheet(isPresented: $isShowingPaywall) {
            PaywallView(service: subscription) { isShowingPaywall = false }
        }
        .confirmationDialog(
            "Reset camera settings?",
            isPresented: $isShowingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset settings", role: .destructive) {
                settings.resetCameraPreferences()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Camera, guidance and capture preferences return to their defaults. Your subscription is not affected.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Settings")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(.white.opacity(0.08)))
            }
            .accessibilityLabel(Text("Close settings"))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    // MARK: - Sections

    private var subscriptionSection: some View {
        SettingsSection(title: "Subscription") {
            if subscription.isPro {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.readyAccent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pro is active")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.white)
                        if case .pro(let expires) = subscription.status, let expires {
                            Text("Renews \(expires.formatted(date: .abbreviated, time: .omitted))")
                                .font(.system(.caption, design: .default))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                SettingsDivider()
                SettingsLinkRow(
                    title: "Manage subscription",
                    systemImage: "creditcard",
                    url: URL(string: "https://apps.apple.com/account/subscriptions")
                )
            } else {
                Button { isShowingPaywall = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.readyAccent))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Upgrade to Pro")
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(.white)
                            Text("All modes, Auto Capture, Best Shot and more")
                                .font(.system(.caption, design: .default))
                                .foregroundStyle(.white.opacity(0.5))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
            }

            SettingsDivider()

            Button {
                Task { await subscription.restore() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(.subheadline, design: .default).weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 22)
                    Text("Restore purchases")
                        .font(.system(.subheadline, design: .default).weight(.medium))
                        .foregroundStyle(.white)
                    Spacer()
                    if subscription.isRestoring {
                        ProgressView().tint(.white).scaleEffect(0.8)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .disabled(subscription.isRestoring)

            if let message = subscription.message {
                SettingsDivider()
                Text(message)
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
    }

    private var cameraSection: some View {
        SettingsSection(title: "Camera") {
            SettingsChoiceRow(
                title: "Photo resolution",
                systemImage: "photo",
                options: PhotoResolution.allCases,
                selection: Binding(
                    get: { settings.photoResolution },
                    set: { newValue in
                        // Maximum resolution is a Pro feature; free accounts
                        // stay on standard rather than silently getting it.
                        if newValue == .maximum,
                           !PremiumGate.isAvailable(.maximumResolution, status: subscription.status) {
                            isShowingPaywall = true
                        } else {
                            settings.photoResolution = newValue
                        }
                    }
                ),
                label: \.title,
                detail: \.detail,
                lockedOptions: subscription.isPro ? [] : [PhotoResolution.maximum.id]
            )
            SettingsDivider()
            SettingsChoiceRow(
                title: "Preview frame rate",
                systemImage: "speedometer",
                options: PreviewFrameRate.allCases,
                selection: Binding(
                    get: { settings.previewFrameRate },
                    set: { settings.previewFrameRate = $0 }
                ),
                label: \.title,
                detail: \.detail
            )
            SettingsDivider()
            SettingsToggleRow(
                title: "Mirror front photos",
                detail: "Save selfies the way the preview shows them",
                systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                isOn: Binding(
                    get: { settings.mirrorFrontPhotos },
                    set: { settings.mirrorFrontPhotos = $0 }
                )
            )
        }
    }

    private var guidanceSection: some View {
        SettingsSection(title: "Guidance") {
            SettingsChoiceRow(
                title: "Composition guide",
                systemImage: "grid",
                options: CompositionGuide.allCases,
                selection: Binding(
                    get: { settings.compositionGuide },
                    set: { newValue in
                        guard PremiumGate.isAvailable(newValue, status: subscription.status) else {
                            isShowingPaywall = true
                            return
                        }
                        settings.compositionGuide = newValue
                    }
                ),
                label: \.title,
                detail: \.detail,
                lockedOptions: Set(
                    CompositionGuide.allCases
                        .filter { !PremiumGate.isAvailable($0, status: subscription.status) }
                        .map(\.id)
                )
            )
            SettingsDivider()
            SettingsToggleRow(
                title: "Level indicator",
                detail: "Show the horizon hint when the camera is tilted",
                systemImage: "level",
                isOn: Binding(
                    get: { settings.isLevelIndicatorEnabled },
                    set: { settings.isLevelIndicatorEnabled = $0 }
                )
            )
            SettingsDivider()
            SettingsChoiceRow(
                title: "Responsiveness",
                systemImage: "waveform",
                options: GuidanceResponsiveness.allCases,
                selection: Binding(
                    get: { settings.responsiveness },
                    set: { settings.responsiveness = $0 }
                ),
                label: \.title,
                detail: nil
            )
            SettingsDivider()
            SettingsToggleRow(
                title: "Haptics",
                detail: "A tap when the shot becomes ready",
                systemImage: "hand.tap",
                isOn: Binding(
                    get: { settings.isHapticsEnabled },
                    set: { settings.isHapticsEnabled = $0 }
                )
            )
        }
    }

    private var captureSection: some View {
        SettingsSection(title: "Capture") {
            SettingsChoiceRow(
                title: "Self-timer",
                systemImage: "clock",
                options: CaptureTimer.allCases,
                selection: Binding(
                    get: { settings.captureTimer },
                    set: { settings.captureTimer = $0 }
                ),
                label: \.title,
                detail: \.detail
            )
            SettingsDivider()
            SettingsToggleRow(
                title: "Auto Capture",
                detail: "Take the photo itself once the shot is right",
                systemImage: "timer",
                isPro: !subscription.isPro,
                isOn: Binding(
                    get: { settings.isAutoCaptureEnabled },
                    set: { newValue in
                        guard PremiumGate.isAvailable(.autoCapture, status: subscription.status) else {
                            isShowingPaywall = true
                            return
                        }
                        settings.isAutoCaptureEnabled = newValue
                    }
                )
            )
            SettingsDivider()
            SettingsToggleRow(
                title: "Best Shot",
                detail: "Take a short burst and keep the best frame",
                systemImage: "square.stack",
                isPro: !subscription.isPro,
                isOn: Binding(
                    get: { settings.isBestShotEnabled },
                    set: { newValue in
                        guard PremiumGate.isAvailable(.bestShot, status: subscription.status) else {
                            isShowingPaywall = true
                            return
                        }
                        settings.isBestShotEnabled = newValue
                    }
                )
            )
        }
    }

    private var aboutSection: some View {
        SettingsSection(title: "About") {
            HStack {
                Text("Version")
                    .font(.system(.subheadline, design: .default).weight(.medium))
                    .foregroundStyle(.white)
                Spacer()
                Text(Bundle.main.appVersion)
                    .font(.system(.subheadline, design: .default))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            SettingsDivider()

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.shield")
                    .font(.system(.subheadline, design: .default))
                    .foregroundStyle(Color.readyAccent)
                Text("Every photo is analysed on this device. Nothing is uploaded, and the app has no account and no analytics.")
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            SettingsDivider()

            Button {
                isShowingResetConfirmation = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(.subheadline, design: .default).weight(.semibold))
                        .frame(width: 22)
                    Text("Reset camera settings")
                        .font(.system(.subheadline, design: .default).weight(.medium))
                    Spacer()
                }
                .foregroundStyle(.red.opacity(0.9))
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
        }
    }
}

extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
