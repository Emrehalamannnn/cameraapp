//
//  DebugPremiumOverride.swift
//  CameraApp
//
//  A local, on-device Pro override. Compiled into every configuration,
//  Release included, so it survives into TestFlight and App Store builds.
//
//  Production entitlement is still computed first: `SubscriptionService.
//  refreshEntitlement()` reads real status from `Transaction.currentEntitlements`
//  before this is ever consulted, and a verified purchase or its absence is
//  never overwritten by anything else in this file — this only ever adds Pro
//  on top, never removes it.
//

import Foundation

enum DebugPremiumOverride {

    private static let key = "debug.testPremiumEnabled"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
