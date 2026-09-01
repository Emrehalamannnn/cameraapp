//
//  SettingsComponents.swift
//  CameraApp
//
//  The building blocks of the settings sheet, kept dark and quiet so the sheet
//  belongs to the same app as the camera behind it.
//

import SwiftUI

struct SettingsSection<Content: View>: View {

    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.4))
                .padding(.leading, 6)

            VStack(spacing: 0) {
                content
            }
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.055))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
            }
        }
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 0.5)
            .padding(.leading, 48)
    }
}

/// A badge for anything the free tier does not include.
struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(.system(size: 9, weight: .heavy, design: .rounded))
            .tracking(0.5)
            .foregroundStyle(.black)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.readyAccent))
    }
}

struct SettingsToggleRow: View {

    let title: String
    var detail: String?
    let systemImage: String
    /// True when this is a Pro feature the customer does not have. The row then
    /// becomes a button to the paywall rather than a switch that snaps back.
    var isPro: Bool = false
    @Binding var isOn: Bool

    var body: some View {
        if isPro {
            Button {
                isOn.toggle() // Routed to the paywall by the binding's setter.
            } label: {
                content(trailing: AnyView(ProBadge()))
            }
            .buttonStyle(.plain)
        } else {
            content(
                trailing: AnyView(
                    Toggle("", isOn: $isOn)
                        .labelsHidden()
                        .tint(Color.readyAccent)
                )
            )
        }
    }

    private func content(trailing: AnyView) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                if let detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// A row of pill options. Used instead of a wheel picker because there are only
/// ever a handful of choices and they should be readable without a tap.
struct SettingsChoiceRow<Option: Identifiable & Hashable>: View {

    let title: String
    let systemImage: String
    let options: [Option]
    @Binding var selection: Option
    let label: KeyPath<Option, String>
    var detail: KeyPath<Option, String>?
    var lockedOptions: Set<Option.ID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: 22)
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                Spacer()
            }

            // Scrolls rather than wraps: four options with a PRO badge on two
            // of them will not fit across a small phone, and a clipped pill
            // looks like a bug.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options) { option in
                        let isSelected = option == selection
                        let isLocked = lockedOptions.contains(option.id)
                        Button {
                            selection = option
                        } label: {
                            HStack(spacing: 4) {
                                Text(option[keyPath: label])
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                if isLocked { ProBadge() }
                            }
                            .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.8))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background {
                                Capsule().fill(
                                    isSelected
                                        ? AnyShapeStyle(Color.readyAccent)
                                        : AnyShapeStyle(Color.white.opacity(0.08))
                                )
                            }
                        }
                        .buttonStyle(PressableButtonStyle(pressedScale: 0.96))
                    }
                }
                .padding(.leading, 34)
                .padding(.trailing, 4)
                // The pressed pill scales down, so the row needs a little
                // vertical room inside the scroll view or it gets clipped.
                .padding(.vertical, 2)
            }

            if let detail {
                Text(selection[keyPath: detail])
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.leading, 34)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .animation(.easeOut(duration: 0.18), value: selection)
    }
}

struct SettingsLinkRow: View {

    let title: String
    let systemImage: String
    let url: URL?

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url { openURL(url) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: 22)
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}
