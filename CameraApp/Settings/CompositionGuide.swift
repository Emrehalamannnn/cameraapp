//
//  CompositionGuide.swift
//  CameraApp
//
//  Which lines, if any, sit over the preview.
//
//  A grid is the one piece of chrome photographers actually want on screen, so
//  it is worth more than an on/off switch — but only just. Four choices, no
//  colour pickers, no opacity sliders.
//

import Foundation

enum CompositionGuide: String, CaseIterable, Identifiable, Sendable {
    /// Nothing over the picture.
    case off
    /// Thirds. The one almost everyone means by "the grid".
    case thirds
    /// Phi lines at 0.382 / 0.618 — a tighter centre than thirds, which suits
    /// portraits and anything with a single strong subject.
    case goldenRatio
    /// A centred 1:1 frame, for shots that are going to be cropped square
    /// later. Shows what survives the crop before you take the photo.
    case square

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .thirds: return "Thirds"
        case .goldenRatio: return "Golden"
        case .square: return "Square"
        }
    }

    var detail: String {
        switch self {
        case .off: return "Nothing over the preview"
        case .thirds: return "The familiar nine-box grid"
        case .goldenRatio: return "Phi lines — a tighter centre than thirds"
        case .square: return "Shows what survives a 1:1 crop"
        }
    }

    /// The two that come free. Thirds is the grid people expect a camera to
    /// have, so charging for it would be charging for the ordinary.
    static let free: Set<CompositionGuide> = [.off, .thirds]

    /// Where a Pro guide falls back to when the subscription is not active.
    static let fallback: CompositionGuide = .thirds
}
