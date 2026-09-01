//
//  SubscriptionService.swift
//  CameraApp
//
//  The only thing in the app that talks to StoreKit.
//
//  Three habits worth naming, because getting them wrong is how subscription
//  bugs reach customers:
//
//  * Entitlement is read from `Transaction.currentEntitlements`, never stored
//    as a local "isPro" flag. The App Store is the source of truth; a cached
//    boolean is a refund or a lapsed renewal waiting to be wrong.
//  * `Transaction.updates` is listened to for the whole session, so a renewal,
//    a refund, or a purchase made on another device lands here without the
//    customer relaunching.
//  * Unverified transactions are treated as no entitlement. A failed signature
//    is exactly the case where being generous is being exploited.
//
//  This file deliberately does not import SwiftUI: StoreKit's `Transaction`
//  and SwiftUI's `Transaction` are different types with the same name, and the
//  ambiguity is not worth the convenience.
//

import Foundation
import Observation
import StoreKit

@MainActor
@Observable
final class SubscriptionService {

    private(set) var status: EntitlementStatus = .unknown
    /// One offer per plan, in display order. Populated with fallback pricing
    /// immediately so the paywall never renders empty while the store loads.
    private(set) var offers: [SubscriptionOffer] = SubscriptionPlan.allCases.map(SubscriptionOffer.fallback)
    private(set) var isLoadingProducts = false
    private(set) var isRestoring = false
    /// The plan currently being bought, so its button can show progress.
    private(set) var purchaseInFlight: SubscriptionPlan?
    private(set) var message: String?

    /// True once the store has answered, however it answered. The paywall uses
    /// it to avoid flashing fallback prices at someone whose real prices are
    /// about to arrive.
    private(set) var hasLoadedStore = false

    @ObservationIgnored private var products: [String: Product] = [:]
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    var isPro: Bool { status.isPro }

    // MARK: - Lifecycle

    func start() async {
        observeTransactionUpdates()
        await loadProducts()
        await refreshEntitlement()
    }

    deinit {
        updatesTask?.cancel()
    }

    /// Renewals, refunds and purchases made elsewhere all arrive here.
    private func observeTransactionUpdates() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self.refreshEntitlement()
            }
        }
    }

    // MARK: - Products

    func loadProducts() async {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        defer {
            isLoadingProducts = false
            hasLoadedStore = true
        }

        do {
            let identifiers = SubscriptionPlan.allCases.map(\.productID)
            let loaded = try await Product.products(for: identifiers)
            products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
            offers = SubscriptionPlan.allCases.map { plan in
                guard let product = products[plan.productID] else {
                    return SubscriptionOffer.fallback(plan)
                }
                return SubscriptionOffer(
                    plan: plan,
                    displayPrice: product.displayPrice,
                    price: product.price,
                    isFromStore: true
                )
            }
        } catch {
            // No store, no products configured yet, or offline. The paywall
            // keeps its fallback pricing and purchase reports the problem
            // honestly rather than pretending to have succeeded.
            offers = SubscriptionPlan.allCases.map(SubscriptionOffer.fallback)
        }
    }

    // MARK: - Purchase

    /// - Returns: true when the customer now has Pro.
    @discardableResult
    func purchase(_ plan: SubscriptionPlan) async -> Bool {
        guard purchaseInFlight == nil else { return false }
        guard let product = products[plan.productID] else {
            message = "This subscription isn't available yet."
            return false
        }

        purchaseInFlight = plan
        defer { purchaseInFlight = nil }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    message = "That purchase could not be verified."
                    return false
                }
                await transaction.finish()
                await refreshEntitlement()
                return status.isPro

            case .userCancelled:
                return false

            case .pending:
                // Ask-to-buy and similar: the purchase may complete later, and
                // `Transaction.updates` will pick it up when it does.
                message = "Your purchase is waiting for approval."
                return false

            @unknown default:
                return false
            }
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    // MARK: - Restore

    func restore() async {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }

        do {
            try await AppStore.sync()
        } catch {
            // A cancelled sign-in sheet lands here too, so this is not
            // necessarily a failure worth shouting about.
        }
        await refreshEntitlement()
        message = status.isPro ? "Your subscription is active." : "No purchases to restore."
    }

    // MARK: - Entitlement

    func refreshEntitlement() async {
        var latestExpiry: Date?
        var isEntitled = false

        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            guard SubscriptionPlan.allCases.contains(where: { $0.productID == transaction.productID })
            else { continue }
            // A revoked transaction is a refund: it must not keep Pro alive.
            guard transaction.revocationDate == nil else { continue }
            if let expiry = transaction.expirationDate, expiry <= Date() { continue }

            isEntitled = true
            if let expiry = transaction.expirationDate {
                latestExpiry = max(latestExpiry ?? expiry, expiry)
            }
        }

        status = isEntitled ? .pro(expires: latestExpiry) : .free
    }

    func clearMessage() {
        message = nil
    }
}
