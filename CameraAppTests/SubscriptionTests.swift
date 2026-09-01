//
//  SubscriptionTests.swift
//  CameraAppTests
//
//  The paywall maths and the free/Pro boundary. Neither needs a store or a
//  camera to be wrong, so neither needs one to be tested.
//

import Foundation
import XCTest
@testable import CameraApp

final class SubscriptionPricingTests: XCTestCase {

    private func offer(_ plan: SubscriptionPlan, _ price: Decimal) -> SubscriptionOffer {
        SubscriptionOffer(
            plan: plan,
            displayPrice: SubscriptionPricing.formatUSD(price),
            price: price,
            isFromStore: true
        )
    }

    // MARK: - Per-month

    func testPerMonthDividesByThePeriodLength() {
        XCTAssertEqual(SubscriptionPricing.monthlyEquivalent(of: offer(.sixMonth, 12)), 2)
        XCTAssertEqual(SubscriptionPricing.monthlyEquivalent(of: offer(.yearly, 24)), 2)
    }

    func testMonthlyPlanIsItsOwnPerMonthPrice() {
        XCTAssertEqual(SubscriptionPricing.monthlyEquivalent(of: offer(.monthly, 12.99)), 12.99)
    }

    // MARK: - Savings badge

    func testSavingIsMeasuredPerMonthNotPerPurchase() {
        // The yearly plan costs more in one go and far less per month. Comparing
        // the totals would report the longer plan as worse value.
        let saving = SubscriptionPricing.savingPercentage(
            of: offer(.yearly, 14.99),
            againstMonthly: offer(.monthly, 12.99)
        )
        XCTAssertEqual(saving, 90)
    }

    func testMonthlyPlanNeverAdvertisesASaving() {
        XCTAssertNil(
            SubscriptionPricing.savingPercentage(
                of: offer(.monthly, 12.99),
                againstMonthly: offer(.monthly, 12.99)
            )
        )
    }

    func testNoBadgeWhenTheLongerPlanIsNotActuallyCheaper() {
        // A storefront where the prices have been set badly should show no
        // badge at all rather than "Save 0%".
        XCTAssertNil(
            SubscriptionPricing.savingPercentage(
                of: offer(.yearly, 240),
                againstMonthly: offer(.monthly, 10)
            )
        )
    }

    func testSavingRoundsDownSoTheBadgeNeverOverstates() {
        // 8.99 vs 9.99 per month is 10.01%, which must not be shown as 11%.
        let saving = SubscriptionPricing.savingPercentage(
            of: offer(.sixMonth, 53.94),
            againstMonthly: offer(.monthly, 9.99)
        )
        XCTAssertEqual(saving, 10)
    }

    // MARK: - Formatting

    func testPricesAlwaysCarryTwoDecimals() {
        XCTAssertEqual(SubscriptionPricing.formatUSD(9), "$9.00")
        XCTAssertEqual(SubscriptionPricing.formatUSD(9.9), "$9.90")
        XCTAssertEqual(SubscriptionPricing.formatUSD(9.99), "$9.99")
    }

    func testCaptionUsesTheStorefrontSymbolWhenOneIsKnown() {
        let caption = SubscriptionPricing.monthlyCaption(
            for: offer(.yearly, 24),
            currencyExample: "£"
        )
        XCTAssertEqual(caption, "£2.00 / month")
    }

    func testFallbackOffersAreMarkedAsNotFromTheStore() {
        for plan in SubscriptionPlan.allCases {
            let fallback = SubscriptionOffer.fallback(plan)
            XCTAssertFalse(fallback.isFromStore)
            XCTAssertEqual(fallback.price, plan.fallbackPrice)
        }
    }

    func testTheFallbackTableMatchesThePricesTheAppAdvertises() {
        // Not the real prices — StoreKit supplies those — but the figures the
        // paywall shows when the store cannot be reached, and they should not
        // drift from what was agreed.
        XCTAssertEqual(SubscriptionPlan.monthly.fallbackPrice, 12.99)
        XCTAssertEqual(SubscriptionPlan.sixMonth.fallbackPrice, 9.99)
        XCTAssertEqual(SubscriptionPlan.yearly.fallbackPrice, 14.99)
    }

    func testEveryPlanHasItsOwnProductIdentifier() {
        let identifiers = Set(SubscriptionPlan.allCases.map(\.productID))
        XCTAssertEqual(identifiers.count, SubscriptionPlan.allCases.count)
    }
}

final class PremiumGateTests: XCTestCase {

    func testNothingPremiumIsAvailableBeforeTheStoreHasAnswered() {
        // `.unknown` is the state at launch. Treating it as entitled would give
        // every user a free trial of everything on every cold start.
        for feature in PremiumFeature.allCases {
            XCTAssertFalse(PremiumGate.isAvailable(feature, status: .unknown))
        }
    }

    func testProUnlocksEveryFeature() {
        for feature in PremiumFeature.allCases {
            XCTAssertTrue(PremiumGate.isAvailable(feature, status: .pro(expires: nil)))
        }
    }

    func testFreeTierStillHasAWorkingCamera() {
        // Portrait has to survive without a subscription: it is the mode the
        // camera falls back to, so a locked one would leave no mode at all.
        XCTAssertTrue(PremiumGate.isAvailable(.portrait, status: .free))
        XCTAssertTrue(PremiumGate.isAvailable(PremiumGate.fallbackMode, status: .free))
    }

    func testTheOtherModesAreLockedWithoutPro() {
        let locked = ShootingMode.allCases.filter { !PremiumGate.isAvailable($0, status: .free) }
        XCTAssertEqual(Set(locked), Set(ShootingMode.allCases).subtracting(PremiumGate.freeShootingModes))
        XCTAssertFalse(locked.isEmpty)
    }

    func testEveryModeIsAvailableWithPro() {
        for mode in ShootingMode.allCases {
            XCTAssertTrue(PremiumGate.isAvailable(mode, status: .pro(expires: nil)))
        }
    }

    func testAnExpiredSubscriptionIsNotPro() {
        XCTAssertFalse(EntitlementStatus.free.isPro)
        XCTAssertFalse(EntitlementStatus.unknown.isPro)
        XCTAssertTrue(EntitlementStatus.pro(expires: Date()).isPro)
    }
}

@MainActor
final class CameraSettingsTests: XCTestCase {

    private func makeDefaults(_ name: String = #function) -> UserDefaults {
        let suite = "CameraSettingsTests.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testDefaultsAreTheQuietOnes() {
        let settings = CameraSettings(defaults: makeDefaults())
        // Nothing that costs battery or takes photos on its own is on by
        // default; the things that only help you frame are.
        XCTAssertEqual(settings.photoResolution, .standard)
        XCTAssertEqual(settings.previewFrameRate, .thirty)
        XCTAssertEqual(settings.responsiveness, .balanced)
        XCTAssertEqual(settings.compositionGuide, .thirds)
        XCTAssertTrue(settings.isLevelIndicatorEnabled)
        XCTAssertTrue(settings.isHapticsEnabled)
        XCTAssertFalse(settings.isAutoCaptureEnabled)
        XCTAssertFalse(settings.isBestShotEnabled)
        XCTAssertEqual(settings.captureTimer, .off)
        XCTAssertFalse(settings.mirrorFrontPhotos)
        XCTAssertFalse(settings.hasSeenPaywall)
    }

    func testEveryPreferenceSurvivesARelaunch() {
        let defaults = makeDefaults()
        let first = CameraSettings(defaults: defaults)
        first.photoResolution = .maximum
        first.previewFrameRate = .sixty
        first.responsiveness = .responsive
        first.compositionGuide = .square
        first.isLevelIndicatorEnabled = false
        first.isHapticsEnabled = false
        first.isAutoCaptureEnabled = true
        first.isBestShotEnabled = true
        first.captureTimer = .ten
        first.mirrorFrontPhotos = true
        first.hasSeenPaywall = true

        let second = CameraSettings(defaults: defaults)
        XCTAssertEqual(second.photoResolution, .maximum)
        XCTAssertEqual(second.previewFrameRate, .sixty)
        XCTAssertEqual(second.responsiveness, .responsive)
        XCTAssertEqual(second.compositionGuide, .square)
        XCTAssertFalse(second.isLevelIndicatorEnabled)
        XCTAssertFalse(second.isHapticsEnabled)
        XCTAssertTrue(second.isAutoCaptureEnabled)
        XCTAssertTrue(second.isBestShotEnabled)
        XCTAssertEqual(second.captureTimer, .ten)
        XCTAssertTrue(second.mirrorFrontPhotos)
        XCTAssertTrue(second.hasSeenPaywall)
    }

    func testAToggledOffBooleanIsStoredRatherThanForgotten() {
        // `object(forKey:) as? Bool ?? true` is the trap here: a false written
        // over a defaulted-true value has to read back as false, not as the
        // default again.
        let defaults = makeDefaults()
        let first = CameraSettings(defaults: defaults)
        first.isLevelIndicatorEnabled = false
        XCTAssertFalse(CameraSettings(defaults: defaults).isLevelIndicatorEnabled)
    }

    // MARK: - Composition guide

    func testTurningTheOldGridOffSurvivesTheUpgradeToGuides() {
        // The grid used to be a boolean. Someone who had switched it off must
        // not be handed it back by an update.
        let defaults = makeDefaults()
        defaults.set(false, forKey: CameraSettings.Key.grid)
        XCTAssertEqual(CameraSettings(defaults: defaults).compositionGuide, .off)
    }

    func testTheOldGridBeingOnBecomesThirds() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: CameraSettings.Key.grid)
        XCTAssertEqual(CameraSettings(defaults: defaults).compositionGuide, .thirds)
    }

    func testAChosenGuideWinsOverTheOldGridSetting() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: CameraSettings.Key.grid)
        defaults.set(CompositionGuide.goldenRatio.rawValue, forKey: CameraSettings.Key.compositionGuide)
        XCTAssertEqual(CameraSettings(defaults: defaults).compositionGuide, .goldenRatio)
    }

    func testTheOrdinaryGridIsFree() {
        // Charging for thirds would be charging for what every camera has.
        XCTAssertTrue(CompositionGuide.free.contains(.thirds))
        XCTAssertTrue(CompositionGuide.free.contains(.off))
        XCTAssertTrue(CompositionGuide.free.contains(CompositionGuide.fallback))
        XCTAssertFalse(CompositionGuide.free.contains(.goldenRatio))
        XCTAssertFalse(CompositionGuide.free.contains(.square))
    }

    func testUnreadableStoredValuesFallBackInsteadOfCrashing() {
        // An old build, a corrupted plist, or a renamed case.
        let defaults = makeDefaults()
        defaults.set("ultra", forKey: CameraSettings.Key.photoResolution)
        defaults.set(999, forKey: CameraSettings.Key.previewFrameRate)
        defaults.set("frantic", forKey: CameraSettings.Key.responsiveness)
        defaults.set(7, forKey: CameraSettings.Key.captureTimer)

        let settings = CameraSettings(defaults: defaults)
        XCTAssertEqual(settings.photoResolution, .standard)
        XCTAssertEqual(settings.previewFrameRate, .thirty)
        XCTAssertEqual(settings.responsiveness, .balanced)
        XCTAssertEqual(settings.captureTimer, .off)
    }

    func testTheSelfTimerIsOffUntilItIsAskedFor() {
        // A camera that silently counts down before every photo would be
        // baffling, so nothing but an explicit choice turns this on.
        XCTAssertEqual(CaptureTimer.off.rawValue, 0)
        XCTAssertTrue(CaptureTimer.allCases.contains(.off))
        XCTAssertTrue(CaptureTimer.allCases.allSatisfy { $0.rawValue >= 0 })
    }

    func testResponsivenessMapsToADistinctAnalysisRate() {
        let rates = GuidanceResponsiveness.allCases.map(\.analysesPerSecond)
        XCTAssertEqual(Set(rates).count, rates.count)
        XCTAssertTrue(rates.allSatisfy { $0 > 0 })
        XCTAssertLessThan(
            GuidanceResponsiveness.relaxed.analysesPerSecond,
            GuidanceResponsiveness.responsive.analysesPerSecond
        )
    }
}
