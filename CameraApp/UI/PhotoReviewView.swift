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
    var isEnhancing: Bool = false
    var isShowingEnhanced: Bool = false
    /// Enhancement is a Pro feature. Marked rather than hidden: a button that
    /// looks ordinary and then asks for money is worse than one that says so.
    var isEnhancementLocked: Bool = false
    var candidates: [UIImage?] = []
    var selectedCandidate: Int = 0
    let onRetake: () -> Void
    let onSave: () -> Void
    var onToggleEnhancement: () -> Void = {}
    var onSelectCandidate: (Int) -> Void = { _ in }

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

                if candidates.count > 1 {
                    candidateStrip
                        .padding(.bottom, 12)
                }

                enhanceControl
                    .padding(.bottom, 14)

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

    /// The shortlist from a burst, best first. Small and out of the way: the
    /// app has already made a choice, and this only exists for the times it
    /// chose differently to you.
    private var candidateStrip: some View {
        HStack(spacing: 8) {
            ForEach(Array(candidates.enumerated()), id: \.offset) { index, thumbnail in
                Button {
                    onSelectCandidate(index)
                } label: {
                    Group {
                        if let thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Color.white.opacity(0.15)
                        }
                    }
                    .frame(width: 46, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(
                                index == selectedCandidate ? Color.readyAccent : Color.white.opacity(0.25),
                                lineWidth: index == selectedCandidate ? 2 : 0.5
                            )
                    }
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(Text("Alternative \(index + 1)"))
                .accessibilityAddTraits(index == selectedCandidate ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.ultraThinMaterial)
        }
        .animation(.easeOut(duration: 0.2), value: selectedCandidate)
    }

    /// Enhancement is opt-in and reversible: the original is always kept, and
    /// the button says which version is on screen.
    private var enhanceControl: some View {
        Button(action: onToggleEnhancement) {
            HStack(spacing: 7) {
                if isEnhancing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    Image(systemName: isShowingEnhanced ? "wand.and.stars" : "wand.and.stars.inverse")
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(isShowingEnhanced ? "Enhanced" : "Enhance")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                if isEnhancementLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .bold))
                }
            }
            .foregroundStyle(isShowingEnhanced ? Color.black : Color.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background {
                Capsule().fill(
                    isShowingEnhanced
                        ? AnyShapeStyle(Color.readyAccent)
                        : AnyShapeStyle(Material.ultraThin)
                )
            }
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isEnhancing || isSaving)
        .accessibilityLabel(
            Text(
                isEnhancementLocked
                    ? "Enhance photo, Pro"
                    : (isShowingEnhanced ? "Show original" : "Enhance photo")
            )
        )
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
