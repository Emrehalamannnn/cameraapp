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

    // MARK: - What a lapse leaves behind

    func testALapseLeavesAWorkingModeRatherThanABrokenOne() {
        for mode in ShootingMode.allCases {
            let resolved = PremiumGate.resolve(mode, status: .free)
            XCTAssertTrue(
                PremiumGate.isAvailable(resolved, status: .free),
                "\(mode) resolved to \(resolved), which is itself locked"
            )
        }
    }

    func testALapseLeavesAGuideThatCanActuallyBeDrawn() {
        for guide in CompositionGuide.allCases {
            let resolved = PremiumGate.resolve(guide, status: .free)
            XCTAssertTrue(
                PremiumGate.isAvailable(resolved, status: .free),
                "\(guide) resolved to \(resolved), which is itself locked"
            )
        }
    }

    func testResubscribingGetsBackExactlyWhatWasChosen() {
        // The selection is never rewritten on a lapse, only reinterpreted, so
        // paying again restores the setup rather than a default.
        for mode in ShootingMode.allCases {
            XCTAssertEqual(PremiumGate.resolve(mode, status: .pro(expires: nil)), mode)
        }
        for guide in CompositionGuide.allCases {
            XCTAssertEqual(PremiumGate.resolve(guide, status: .pro(expires: nil)), guide)
        }
    }

    func testAFreeChoiceIsNeverSubstituted() {
        XCTAssertEqual(PremiumGate.resolve(ShootingMode.portrait, status: .free), .portrait)
        XCTAssertEqual(PremiumGate.resolve(CompositionGuide.off, status: .free), .off)
        XCTAssertEqual(PremiumGate.resolve(CompositionGuide.thirds, status: .free), .thirds)
    }

    func testTurningTheGuideOffIsNotUpsoldIntoTurningItOn() {
        // `.off` is a free choice, and resolving it to thirds would put lines
        // back over the picture of someone who asked for none.
        XCTAssertEqual(PremiumGate.resolve(CompositionGuide.off, status: .unknown), .off)
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

    func testNamedDefaultsMatchAFirstLaunch() {
        let settings = CameraSettings(defaults: makeDefaults())
        let values = CameraSettings.defaultValues

        XCTAssertEqual(settings.photoResolution, values.photoResolution)
        XCTAssertEqual(settings.previewFrameRate, values.previewFrameRate)
        XCTAssertEqual(settings.responsiveness, values.responsiveness)
        XCTAssertEqual(settings.compositionGuide, values.compositionGuide)
        XCTAssertEqual(settings.isLevelIndicatorEnabled, values.isLevelIndicatorEnabled)
        XCTAssertEqual(settings.isHapticsEnabled, values.isHapticsEnabled)
        XCTAssertEqual(settings.isAutoCaptureEnabled, values.isAutoCaptureEnabled)
        XCTAssertEqual(settings.isBestShotEnabled, values.isBestShotEnabled)
        XCTAssertEqual(settings.captureTimer, values.captureTimer)
        XCTAssertEqual(settings.mirrorFrontPhotos, values.mirrorFrontPhotos)
        XCTAssertEqual(settings.hasSeenPaywall, values.hasSeenPaywall)
    }

    func testResetRestoresCameraPreferencesButKeepsPaywallHistory() {
        let defaults = makeDefaults()
        let settings = CameraSettings(defaults: defaults)

        settings.photoResolution = .maximum
        settings.previewFrameRate = .sixty
        settings.responsiveness = .responsive
        settings.compositionGuide = .square
        settings.isLevelIndicatorEnabled = false
        settings.isHapticsEnabled = false
        settings.isAutoCaptureEnabled = true
        settings.isBestShotEnabled = true
        settings.captureTimer = .ten
        settings.mirrorFrontPhotos = true
        settings.hasSeenPaywall = true

        settings.resetCameraPreferences()
        let values = CameraSettings.defaultValues

        XCTAssertEqual(settings.photoResolution, values.photoResolution)
        XCTAssertEqual(settings.previewFrameRate, values.previewFrameRate)
        XCTAssertEqual(settings.responsiveness, values.responsiveness)
        XCTAssertEqual(settings.compositionGuide, values.compositionGuide)
        XCTAssertEqual(settings.isLevelIndicatorEnabled, values.isLevelIndicatorEnabled)
        XCTAssertEqual(settings.isHapticsEnabled, values.isHapticsEnabled)
        XCTAssertEqual(settings.isAutoCaptureEnabled, values.isAutoCaptureEnabled)
        XCTAssertEqual(settings.isBestShotEnabled, values.isBestShotEnabled)
        XCTAssertEqual(settings.captureTimer, values.captureTimer)
        XCTAssertEqual(settings.mirrorFrontPhotos, values.mirrorFrontPhotos)
        XCTAssertTrue(settings.hasSeenPaywall)
    }

    func testResetPersistsAcrossRelaunch() {
        let defaults = makeDefaults()
        let first = CameraSettings(defaults: defaults)
        first.photoResolution = .maximum
        first.previewFrameRate = .sixty
        first.compositionGuide = .square
        first.isAutoCaptureEnabled = true
        first.captureTimer = .ten
        first.hasSeenPaywall = true

        first.resetCameraPreferences()

        let second = CameraSettings(defaults: defaults)
        let values = CameraSettings.defaultValues
        XCTAssertEqual(second.photoResolution, values.photoResolution)
        XCTAssertEqual(second.previewFrameRate, values.previewFrameRate)
        XCTAssertEqual(second.compositionGuide, values.compositionGuide)
        XCTAssertEqual(second.isAutoCaptureEnabled, values.isAutoCaptureEnabled)
        XCTAssertEqual(second.captureTimer, values.captureTimer)
        XCTAssertTrue(second.hasSeenPaywall)
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
