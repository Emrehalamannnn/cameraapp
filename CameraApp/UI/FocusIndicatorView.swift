//
//  FocusIndicatorView.swift
//  CameraApp
//
//  The square that confirms a tap-to-focus landed.
//

import SwiftUI

struct FocusIndicatorView: View {

    @State private var isSettled = false

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .stroke(Color.yellow.opacity(0.95), lineWidth: 1.2)
            .frame(width: 74, height: 74)
            .overlay(alignment: .center) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(Color.yellow.opacity(0.95), lineWidth: 1.2)
                    .frame(width: 10, height: 10)
                    .opacity(0.7)
            }
            .scaleEffect(isSettled ? 1 : 1.35)
            .opacity(isSettled ? 0.9 : 0)
            .shadow(color: .black.opacity(0.35), radius: 4)
            .onAppear {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                    isSettled = true
                }
            }
            .allowsHitTesting(false)
    }
}
