//
//  DebugPremiumOverride.swift
//  CameraApp
//
//  Lets a developer's own installed build carry Pro without a purchase, so
//  the app can be exercised end to end without buying a subscription on every
//  test device.
//
//  The entire file is compiled only into Debug builds: `DEBUG` is defined by
//  `SWIFT_ACTIVE_COMPILATION_CONDITIONS` on the Debug configuration alone, so
//  an Archive or a TestFlight/App Store Release build — which always builds
//  Release — does not contain this type at all. There is no runtime check to
//  disable, misconfigure, or bypass; the code is simply absent.
//
//  Production entitlement is untouched: `SubscriptionService.refreshEntitlement()`
//  still computes real status from `Transaction.currentEntitlements` first,
//  and only *then*, in Debug, may override the result. A real customer's
//  verified transactions remain the only thing that can grant Pro.
//

#if DEBUG

import Foundation

enum DebugPremiumOverride {

    private static let key = "debug.testPremiumEnabled"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

#endif
