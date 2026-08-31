//
//  PhotoReviewView.swift
//  CameraApp
//
//  A lightweight look at the shot just taken: keep it or take it again.
//

import SwiftUI
import UIKit

struct PhotoReviewView: View {

    let review: CameraModel.PhotoReview
    let isSaving: Bool
    let isPhotoAccessDenied: Bool
    let onRetake: () -> Void
    let onSave: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = review.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .ignoresSafeArea()
                    .accessibilityLabel(Text("Photo just taken"))
            } else {
                ProgressView()
                    .tint(.white)
            }

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                if isPhotoAccessDenied {
                    photoAccessNotice
                        .padding(.horizontal, 24)
                        .padding(.bottom, 18)
                }

                HStack {
                    Button(action: onRetake) {
                        Text("Retake")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(.ultraThinMaterial))
                    }
                    .buttonStyle(PressableButtonStyle())
                    .disabled(isSaving)

                    Spacer()

                    Button(action: onSave) {
                        HStack(spacing: 8) {
                            if isSaving {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.black)
                            } else {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 15, weight: .bold))
                            }
                            Text(isSaving ? "Saving" : "Save")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.white))
                    }
                    .buttonStyle(PressableButtonStyle())
                    .disabled(isSaving)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 10)
            }
        }
    }

    private var photoAccessNotice: some View {
        VStack(spacing: 10) {
            Text("CameraApp can't add photos to your library")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                SettingsLauncher.open()
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.black)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Capsule().fill(Color.white))
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }
}
