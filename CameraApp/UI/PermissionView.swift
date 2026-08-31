//
//  PermissionView.swift
//  CameraApp
//
//  Shown when a permission the app cannot work without has been declined.
//  The app stays usable and honest rather than showing a dead black screen.
//

import SwiftUI
import UIKit

struct PermissionView: View {

    let symbolName: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbolName)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.bottom, 6)

            Text(title)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button("Open Settings") {
                SettingsLauncher.open()
            }
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(.black)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Capsule().fill(Color.white))
            .padding(.top, 8)
        }
        .padding(.horizontal, 36)
    }
}

enum SettingsLauncher {
    @MainActor
    static func open() {
        guard let url = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
    }
}
