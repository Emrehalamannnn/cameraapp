//
//  CameraAppApp.swift
//  CameraApp
//

import SwiftUI

@main
struct CameraAppApp: App {

    @State private var camera = CameraModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            CameraView(model: camera)
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
