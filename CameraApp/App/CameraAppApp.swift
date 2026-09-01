//
//  CameraAppApp.swift
//  CameraApp
//

import SwiftUI

@main
struct CameraAppApp: App {

    /// Preferences and entitlement outlive any one screen, so they are created
    /// here and handed down rather than owned by a view.
    @State private var settings: CameraSettings
    @State private var subscription: SubscriptionService
    @State private var camera: CameraModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let settings = CameraSettings()
        let subscription = SubscriptionService()
        _settings = State(initialValue: settings)
        _subscription = State(initialValue: subscription)
        _camera = State(initialValue: CameraModel(settings: settings, subscription: subscription))
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: camera, settings: settings, subscription: subscription)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await camera.resume() }
            case .background:
                // Release the camera as soon as the app leaves the screen:
                // holding a session in the background is denied by the system
                // anyway and keeps the in-use indicator lit.
                Task { await camera.suspend() }
            default:
                break
            }
        }
    }
}
