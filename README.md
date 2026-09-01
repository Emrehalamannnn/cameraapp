# CameraApp — AI-assisted camera, Phase 1 foundation

A native iOS camera built so that a real-time "AI photographer" can be layered
onto it without rewriting the camera. Phase 1 delivers a complete, working
camera: live preview, capture, review, save — plus a running frame-analysis
pipeline that already measures light, steadiness and faces, and turns those
signals into one calm on-screen instruction.

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

The analysis vocabulary (`FrameAnalysis`, `LightingAssessment`,
`StabilityAssessment`, `DetectedFace`, `CompositionAssessment`,
`GuidanceMessage`) is plain value types in `Analysis/AnalysisTypes.swift` — the
seam future AI modules extend.

## Performance model

* The preview is an `AVCaptureVideoPreviewLayer` backing a `UIView`, so frames
  never pass through SwiftUI.
* Analysis is throttled two ways: a minimum interval (12 Hz) **and** a busy flag,
  so slow frames can never queue up behind each other.
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
aspect-fill preview geometry, and the zoom factor mapping.

## Privacy

Everything the app does happens on the device.

There is no networking code in the project, no analytics, no account and no
backend. Face detection, body pose, framing analysis, best-shot scoring and
enhancement all run through Vision and Core Image locally. Reference photos are
read through the system photo picker, which hands over a single image without
the app ever gaining access to the library, and the only Photos permission
requested is add-only — the app can save your photos and cannot read them.

## What Phase 2 adds

Aesthetic scoring, auto-capture at the ideal moment, photo enhancement, and
richer subject understanding — all of which plug into `FrameAnalysisService`
and `GuidanceEngine` without touching the camera stack.
