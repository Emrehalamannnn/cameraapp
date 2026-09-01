//
//  SubscriptionPlan.swift
//  CameraApp
//
//  The three things a customer can buy, and the arithmetic behind how they are
//  presented.
//
//  Prices here are *fallbacks*, used for layout in development and if the App
//  Store cannot be reached. The real price always comes from StoreKit, because
//  it is the only source that knows the customer's currency, their storefront,
//  and any offer they are eligible for. Showing a hardcoded price to a paying
//  customer would be wrong in most of the world.
//

import Foundation

enum SubscriptionPlan: String, CaseIterable, Identifiable, Sendable {
    case monthly
    case sixMonth
    case yearly

    var id: String { rawValue }

    /// App Store Connect product identifiers.
    var productID: String {
        switch self {
        case .monthly: return "com.example.CameraApp.pro.monthly"
        case .sixMonth: return "com.example.CameraApp.pro.sixmonth"
        case .yearly: return "com.example.CameraApp.pro.yearly"
        }
    }

    var title: String {
        switch self {
        case .monthly: return "Monthly"
        case .sixMonth: return "6 Months"
        case .yearly: return "12 Months"
        }
    }

    /// Billing period length in months, used for the per-month maths.
    var months: Int {
        switch self {
        case .monthly: return 1
        case .sixMonth: return 6
        case .yearly: return 12
        }
    }

    /// Fallback price in USD. Superseded by StoreKit whenever products load.
    var fallbackPrice: Decimal {
        switch self {
        case .monthly: return 12.99
        case .sixMonth: return 9.99
        case .yearly: return 14.99
        }
    }

    /// The plan offered first. Not the cheapest — the one most people should
    /// pick, which the layout then makes obvious.
    static let recommended: SubscriptionPlan = .yearly
}

/// A plan with whatever pricing is currently known about it.
struct SubscriptionOffer: Identifiable, Equatable, Sendable {
    var plan: SubscriptionPlan
    /// Localised, store-provided price string when available, e.g. "£12.99".
    var displayPrice: String
    /// Numeric price used for the per-month and savings maths.
    var price: Decimal
    /// True when this came from StoreKit rather than the fallback table.
    var isFromStore: Bool

    var id: String { plan.id }

    static func fallback(_ plan: SubscriptionPlan) -> SubscriptionOffer {
        SubscriptionOffer(
            plan: plan,
            displayPrice: SubscriptionPricing.formatUSD(plan.fallbackPrice),
            price: plan.fallbackPrice,
            isFromStore: false
        )
    }
}

enum SubscriptionPricing {

    /// Price per month, for comparing plans of different lengths.
    static func monthlyEquivalent(of offer: SubscriptionOffer) -> Decimal {
        guard offer.plan.months > 0 else { return offer.price }
        return offer.price / Decimal(offer.plan.months)
    }

    /// Percentage saved against the monthly plan, rounded down so the badge
    /// never overstates the discount.
    ///
    /// - Returns: `nil` when there is nothing to boast about, so the UI can
    ///   simply omit the badge rather than showing "Save 0%".
    static func savingPercentage(
        of offer: SubscriptionOffer,
        againstMonthly monthly: SubscriptionOffer
    ) -> Int? {
        guard offer.plan != .monthly else { return nil }
        let baseline = monthlyEquivalent(of: monthly)
        let candidate = monthlyEquivalent(of: offer)
        guard baseline > 0, candidate < baseline else { return nil }

        // Rounded to a whole number *as a Decimal* before it becomes an Int.
        // A division like this leaves a 38-digit mantissa, and converting one
        // of those to an integer directly does not survive the trip — which is
        // how a "Save 90%" badge ends up showing something else entirely.
        var ratio = (baseline - candidate) / baseline * 100
        var whole = Decimal()
        NSDecimalRound(&whole, &ratio, 0, .down)
        let percentage = (whole as NSDecimalNumber).intValue
        return percentage > 0 ? percentage : nil
    }

    /// Formats a per-month figure for the small print under each plan.
    static func monthlyCaption(
        for offer: SubscriptionOffer,
        currencyExample: String? = nil
    ) -> String {
        let perMonth = monthlyEquivalent(of: offer)
        let formatted = currencyExample.map { symbol in
            "\(symbol)\(rounded(perMonth))"
        } ?? formatUSD(perMonth)
        return "\(formatted) / month"
    }

    static func formatUSD(_ value: Decimal) -> String {
        "$\(rounded(value))"
    }

    private static func rounded(_ value: Decimal) -> String {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 2, .plain)
        return NSDecimalNumber(decimal: result).stringValue.paddedDecimals
    }
}

private extension String {
    /// Keeps prices looking like prices: "9.9" reads as a mistake, "9.90" does not.
    var paddedDecimals: String {
        guard let separator = firstIndex(of: ".") else { return self + ".00" }
        let decimals = distance(from: index(after: separator), to: endIndex)
        return decimals >= 2 ? self : self + String(repeating: "0", count: 2 - decimals)
    }
}
