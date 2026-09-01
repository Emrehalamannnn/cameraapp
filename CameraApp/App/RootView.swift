//
//  RootView.swift
//  CameraApp
//
//  Owns the two screens that sit on top of the camera — settings and the
//  paywall — so the camera view itself stays about taking photos.
//

import SwiftUI

struct RootView: View {

    let model: CameraModel
    let settings: CameraSettings
    let subscription: SubscriptionService

    @State private var isShowingSettings = false
    @State private var isShowingPaywall = false

    var body: some View {
        CameraView(model: model) { isShowingSettings = true }
            .sheet(isPresented: $isShowingSettings, onDismiss: applySettings) {
                SettingsView(settings: settings, subscription: subscription) {
                    isShowingSettings = false
                }
            }
            .fullScreenCover(isPresented: $isShowingPaywall, onDismiss: applySettings) {
                PaywallView(service: subscription) { isShowingPaywall = false }
            }
            .task { await subscription.start() }
            .onChange(of: model.status) { _, _ in offerPaywallIfNeeded() }
            // A locked control was tapped somewhere in the camera UI.
            .onChange(of: model.isPaywallPresented) { _, isPresented in
                guard isPresented else { return }
                model.dismissPaywall()
                if isShowingSettings {
                    // Settings presents its own paywall; two at once is a bug.
                    return
                }
                isShowingPaywall = true
            }
            // Entitlement can change while the app is open — a purchase, a
            // restore, or a lapse — and the capture session has to follow.
            .onChange(of: subscription.status) { previous, current in
                applySettings()
                offerPaywallIfNeeded()
                // Only for a real unlock. The launch transition out of
                // `.unknown` is not news to anyone.
                if current.isPro, previous == .free {
                    model.announceProUnlocked()
                }
            }
    }

    /// The first-launch offer, once and only when it can be made honestly.
    ///
    /// It waits for two things. The camera, because asking for money over a
    /// black screen — before the permission prompt has even been answered — is
    /// how a camera app gets deleted before it takes a photo. And the store,
    /// because `.unknown` is not the same as "not subscribed": showing the
    /// paywall to someone reinstalling with an active subscription would be
    /// the worst possible first impression.
    private func offerPaywallIfNeeded() {
        guard !settings.hasSeenPaywall,
              model.status.isRunning,
              subscription.status != .unknown else { return }

        settings.hasSeenPaywall = true
        if !subscription.isPro {
            isShowingPaywall = true
        }
    }

    private func applySettings() {
        Task { await model.applySettings() }
    }
}
