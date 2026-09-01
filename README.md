# CameraApp — an AI-assisted camera

A native iOS camera that watches the frame and tells you the one thing worth
changing. Live preview, capture, review and save, on top of a frame-analysis
pipeline that measures light, steadiness, faces, body pose and framing, and
reduces all of it to a single calm instruction — which disappears the moment
you are lined up.

**Swift · SwiftUI · AVFoundation · Vision · PhotoKit · Core Motion · Swift concurrency.**
No React Native, Capacitor, Expo, Flutter or WebView anywhere in the stack.

Requirements: Xcode 16, iOS 17.0+, iPhone (a physical device — the Simulator
has no camera).

```
open CameraApp.xcodeproj      # scheme: CameraApp
```

## Architecture

Five layers, each with one job. Nothing below the model knows the UI exists,
and nothing above `CaptureService` knows AVFoundation exists.

```
                 CameraView (SwiftUI)
                        │  reads state, sends intent
                 CameraModel  @MainActor @Observable
        ┌───────────────┼────────────────────┐
        │               │                    │
  CaptureService   FrameAnalysisService   MediaLibraryService
    (actor)            (actor)               (actor)
   AVCaptureSession   Vision + signals       PhotoKit
        │               ▲
   VideoFrameProcessor ─┘  throttled CVPixelBuffer handoff
```

| Layer | Type | Responsibility |
| --- | --- | --- |
| `CaptureService` | `actor` | Owns `AVCaptureSession`: devices, inputs, outputs, zoom, focus, rotation, still capture. |
| `VideoFrameProcessor` | `NSObject` on a serial queue | Receives every frame, throttles to ~12 Hz, drops frames while the analyser is busy. |
| `FrameAnalysisService` | `actor` | Vision face detection, luma sampling, lighting/stability/composition scoring. Publishes `FrameAnalysis` over an `AsyncStream`. |
| `GuidanceEngine` | `struct` (pure) | Reduces analyses to exactly one message, with dwell times so it never flickers. |
| `MediaLibraryService` | `actor` | Add-only PhotoKit writes. |
| `CameraModel` | `@MainActor @Observable` | All UI state; orchestrates the three services and owns the lifecycle. |
| `CameraSettings` | `@MainActor @Observable` | Persisted preferences. The model reads them; it does not own them. |
| `SubscriptionService` | `@MainActor @Observable` | The only thing that talks to StoreKit. |

The analysis vocabulary (`FrameAnalysis`, `LightingAssessment`,
`StabilityAssessment`, `DetectedFace`, `CompositionAssessment`,
`GuidanceMessage`) is plain value types in `Analysis/AnalysisTypes.swift` — the
seam future AI modules extend.

## Performance model

* The preview is an `AVCaptureVideoPreviewLayer` backing a `UIView`, so frames
  never pass through SwiftUI.
* Analysis is throttled two ways: a minimum interval (8–20 Hz, set by the
  Responsiveness preference) **and** a busy flag, so slow frames can never
  queue up behind each other.
* Frames are never copied. The `CVPixelBuffer` is passed by reference, read in
  place (locked read-only), and handed to Vision as-is. Rotation is expressed as
  a `CGImagePropertyOrientation` rather than by rotating pixels.
* Brightness comes from a 16×16 lattice — 256 byte reads regardless of capture
  resolution — plus the device's own ISO/shutter pair, which is a real
  photometric measurement rather than a guess from an auto-exposed image.
* Everything except UI state runs off the main thread, on actors and a dedicated
  capture queue.

## Testing

`CameraAppTests` covers the pure layers: guidance priority and dwell behaviour,
composition (including the mirrored front-camera case), the EV100 lighting
estimate, stability scoring, luma sampling against synthesised pixel buffers,
aspect-fill preview geometry, the zoom factor mapping, the paywall's per-month
and savings arithmetic, the free/Pro boundary, and that every preference
survives a relaunch.

A macOS GitHub Actions workflow builds the app target and runs the suite
against a real iOS simulator on every push, so "it compiles" is a fact rather
than a claim. It also checks that the product identifiers in
`SubscriptionPlan` and in the StoreKit configuration still match — a rename on
one side of that pairing is invisible to the compiler and fatal at runtime.

## Free and Pro

The free tier is a real camera, not a demo: manual capture at full quality,
live framing guidance, the thirds grid, the level, zoom, flash, the self-timer
and Portrait mode all work without paying. A camera that nags before it has
been useful gets deleted.

Pro buys the things that take work off your hands.

| | Free | Pro |
| --- | --- | --- |
| Shooting modes | Portrait | Outfit, Food, Product, Landscape, Night, Story |
| Auto Capture | — | Fires the shutter itself when the shot is right |
| Best Shot | — | Short burst, keeps the best few frames |
| Reference framing | — | Match the composition of a photo you like |
| Enhancement | — | A conservative clean-up on the review screen |
| Composition guides | Off, thirds | Golden ratio, live square-crop frame |
| Capture resolution | Standard | Maximum the camera supports |

`PremiumGate` is the single table that decides this. Moving the boundary is one
edit rather than an audit.

Entitlement is always read from `Transaction.currentEntitlements` and never
cached as a local flag — a stored `isPro` boolean is a refund or a lapsed
renewal waiting to be wrong. `Transaction.updates` is watched for the session,
so a renewal, a refund, or a purchase made on another device lands without a
relaunch. Unverified and revoked transactions grant nothing. When Pro lapses
while a Pro mode or guide is selected, the camera drops back to Portrait and
thirds rather than breaking.

## Settings

Everything that is not worth a button mid-shot lives behind one control on the
camera screen: subscription status and restore purchases, photo resolution,
preview frame rate, front-camera mirroring, composition guide, level indicator,
guidance responsiveness, haptics, self-timer, Auto Capture and Best Shot.

The front bar is left with the four things you actually reach for while
framing: flash, reference, Auto Capture, settings.

Either volume key takes the photo (iOS 17.2+, via `AVCaptureEventInteraction`),
which is how most people hold a phone one-handed.

Tap to focus brings up an exposure slider beside the square. The correction
outlives the square, so the top bar carries a `+0.7 EV` chip until it is
cleared — and a chip for the self-timer whenever one is set, because a timer
configured days ago should not be a surprise the next time the shutter is
pressed. Both chips are tappable and both disappear when there is nothing to
say.

Settings and the paywall scale with Dynamic Type; the camera HUD does not,
because control sizes there are about where your thumb lands.

## Before shipping

Two things in this repository are placeholders and have to be replaced, and
one is a local convenience:

* The product identifiers in `SubscriptionPlan.productID` (`com.example.…`)
  must match real subscriptions in App Store Connect, in one subscription
  group, or `Product.products(for:)` returns nothing and the paywall stays on
  its fallback prices.
* The privacy URL in `PaywallView` points at `example.com`.
* `StoreKit/CameraApp.storekit` is wired into the scheme's Run action and
  mirrors those identifiers, so purchase, restore, expiry and refund can be
  exercised locally. Its product IDs have to be changed in step with
  `SubscriptionPlan`. (If Xcode does not pick it up, set it under Product →
  Scheme → Edit Scheme → Run → Options → StoreKit Configuration.)

The prices in `SubscriptionPlan.fallbackPrice` are fallbacks for layout and for
a store that cannot be reached. The price shown to a customer always comes from
StoreKit, which is the only thing that knows their currency and storefront.

## Privacy

Everything the app does happens on the device.

`CameraApp/PrivacyInfo.xcprivacy` says the same thing in the form the App
Store checks: no tracking, no tracking domains, no collected data types, and
the two required-reason APIs the app does use — `UserDefaults` for
preferences, and `CACurrentMediaTime` to time how long a shot has been steady.

There is no analytics, no account and no backend. The only thing that leaves
the device is a StoreKit purchase, which goes to Apple and carries no photo,
no analysis and no identifier of ours — there is no other networking code in
the project. Face detection, body pose, framing analysis, best-shot scoring and
enhancement all run through Vision and Core Image locally. Reference photos are
read through the system photo picker, which hands over a single image without
the app ever gaining access to the library, and the only Photos permission
requested is add-only — the app can save your photos and cannot read them.

## The composition brain

| Layer | Type | Responsibility |
| --- | --- | --- |
| `ShootingMode` | `enum` | What is being photographed, and therefore what good framing means. Supplies a whole `AnalysisConfiguration` and declares whether faces are the subject. |
| `CompositionEvaluator` | pure | Framing geometry and verdict, in normalised preview space, aimed at a `CompositionTarget`. |
| `LevelEstimator` | pure | Camera roll from gravity, standing down when the phone is too flat for roll to mean anything. |
| `BodyPoseRules` | pure | Where the frame cuts the body, for full-body modes only. |
| `ShotQualityModel` | pure | One conservative readiness decision from every signal, including whether the subject is camera-ready. |
| `GuidanceEngine` | `struct` | One instruction at a time, with dwell and hysteresis. |
| `AutoCaptureController` | `struct` | When the app is allowed to take a photo by itself. |
| `BestShotSelector` / `ShotScorer` | pure | Which frame of a burst to keep. |
| `EnhancementPlanner` / `PhotoEnhancer` | pure / Core Image | How little to change a photo. |

Everything in the "pure" rows is a value type with no camera dependency, which
is why the framing rules, the safety rules and the enhancement ceilings are all
unit tested rather than hoped for.

## Calibration

Every threshold lives in `AnalysisConfiguration`, and each shooting mode is a
set of overrides on it. None of the defaults have been validated against a real
phone yet — `docs/DEVICE_TEST_CHECKLIST.md` says exactly what to observe
and report for each one.
