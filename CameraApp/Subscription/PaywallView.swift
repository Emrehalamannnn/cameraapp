//
//  PaywallView.swift
//  CameraApp
//
//  The subscription screen.
//
//  It is dismissible, it names the price and the period next to every plan, and
//  it links to terms and privacy — partly because the App Store requires all
//  three, and partly because a paywall that hides any of them is the kind of
//  thing people screenshot.
//

import SwiftUI

struct PaywallView: View {

    let service: SubscriptionService
    var canDismiss: Bool = true
    var onDismiss: () -> Void = {}

    @State private var selected: SubscriptionPlan = .recommended

    private var monthlyOffer: SubscriptionOffer? {
        service.offers.first { $0.plan == .monthly }
    }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                header
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        featureList
                        planPicker
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 18)
                }
                footer
            }
        }
        .preferredColorScheme(.dark)
        // Prices, periods and the renewal disclosure all have to stay legible
        // at larger text sizes — a paywall is the last place to fix type size
        // in place. Capped, or the plan rows stop fitting a phone.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .task {
            service.clearMessage()
            await service.loadProducts()
        }
    }

    // MARK: - Chrome

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.06, blue: 0.08),
                Color.black
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            // A soft wash of the accent behind the title, so the screen reads
            // as an upgrade rather than a bill.
            Circle()
                .fill(Color.readyAccent.opacity(0.16))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(y: -140)
                .ignoresSafeArea()
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                Spacer()
                if canDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(.white.opacity(0.08)))
                    }
                    .accessibilityLabel(Text("Close"))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            Text("CameraApp Pro")
                .font(.system(.title, design: .rounded).weight(.bold))
                .foregroundStyle(.white)

            Text("A photographer in your pocket.")
                .font(.system(.subheadline, design: .default))
                .foregroundStyle(.white.opacity(0.62))
                .padding(.bottom, 18)
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(PremiumFeature.allCases, id: \.self) { feature in
                HStack(alignment: .top, spacing: 13) {
                    Image(systemName: feature.symbolName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.readyAccent)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.readyAccent.opacity(0.12)))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.title)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.white)
                        Text(feature.detail)
                            .font(.system(.caption, design: .default))
                            .foregroundStyle(.white.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Plans

    private var planPicker: some View {
        VStack(spacing: 10) {
            ForEach(service.offers) { offer in
                PlanRow(
                    offer: offer,
                    isSelected: offer.plan == selected,
                    saving: monthlyOffer.flatMap {
                        SubscriptionPricing.savingPercentage(of: offer, againstMonthly: $0)
                    }
                ) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        selected = offer.plan
                    }
                    Haptics.shared.selectionSignal()
                }
            }
        }
        // Until the store answers these are fallback figures. Blurring them
        // for the moment they are on screen is better than showing a price
        // that is about to change.
        .redacted(reason: service.hasLoadedStore ? [] : .placeholder)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 12) {
            if let message = service.message {
                Text(message)
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }

            Button {
                Task {
                    if await service.purchase(selected) { onDismiss() }
                }
            } label: {
                ZStack {
                    if service.purchaseInFlight != nil {
                        ProgressView().tint(.black)
                    } else {
                        Text("Continue")
                            .font(.system(.headline, design: .rounded).weight(.bold))
                    }
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, minHeight: 52)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.readyAccent))
            }
            .buttonStyle(PressableButtonStyle(pressedScale: 0.97))
            .disabled(service.purchaseInFlight != nil)

            HStack(spacing: 18) {
                Button("Restore") {
                    Task {
                        await service.restore()
                        // A restore that worked has nothing left to sell.
                        if service.isPro { onDismiss() }
                    }
                }
                .disabled(service.isRestoring)

                Link("Terms", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Link("Privacy", destination: URL(string: "https://example.com/privacy")!)
            }
            .font(.system(.caption, design: .default).weight(.medium))
            .foregroundStyle(.white.opacity(0.5))

            Text("Subscriptions renew automatically until cancelled. Manage or cancel in Settings.")
                .font(.system(.caption2, design: .default))
                .foregroundStyle(.white.opacity(0.35))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(.black.opacity(0.35))
        .animation(.easeInOut(duration: 0.2), value: service.message)
    }
}

/// One selectable plan.
private struct PlanRow: View {

    let offer: SubscriptionOffer
    let isSelected: Bool
    let saving: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            isSelected ? Color.readyAccent : Color.white.opacity(0.25),
                            lineWidth: isSelected ? 6 : 1.5
                        )
                        .frame(width: 20, height: 20)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(offer.plan.title)
                            .font(.system(.callout, design: .rounded).weight(.semibold))
                            .foregroundStyle(.white)
                        if let saving {
                            Text("SAVE \(saving)%")
                                .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2.5)
                                .background(Capsule().fill(Color.readyAccent))
                        }
                    }
                    Text(
                        offer.plan == .monthly
                            ? "Billed every month"
                            : SubscriptionPricing.monthlyCaption(for: offer)
                    )
                        .font(.system(.caption, design: .default))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer(minLength: 0)

                Text(offer.displayPrice)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.10 : 0.045))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.readyAccent : Color.white.opacity(0.10),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            }
        }
        .buttonStyle(PressableButtonStyle(pressedScale: 0.98))
        .accessibilityLabel(Text("\(offer.plan.title), \(offer.displayPrice)"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
