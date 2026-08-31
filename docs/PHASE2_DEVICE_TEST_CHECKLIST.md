# Phase 2 iPhone Calibration Checklist

CI can prove that the state machines and thresholds compile and pass their
unit tests. It cannot prove that camera directions feel natural, that the
thresholds match real hands and lenses, or that overlays align with a physical
preview. Run this checklist before treating the default values as calibrated.

For every threshold item, report **too early / correct / too late**. For every
direction item, report **correct / reversed / inconsistent**.

## Framing and direction

- Rear camera, single face: move the face to the left and right edges. Report
  whether Move Left and Move Right match the correction you naturally make.
- Front camera, single face: repeat in the mirrored preview. Report whether
  either direction is reversed from what the preview suggests.
- Move the face low in the frame to create excessive headroom. Confirm that
  Lower Camera moves the face toward a better position.
- Move the face close to the top without clipping it. Confirm that Raise Camera
  moves the face away from the top edge.
- Approach until Step Back appears, then move away until Move Closer appears.
  Report both trigger distances as too early, correct, or too late.
- Approach every frame edge separately. Confirm Keep Subject in Frame appears
  before the forehead, chin, or side of the face is visibly clipped.
- Frame two to five people. Confirm the app corrects the group as one unit and
  never alternates directions based on individual faces.

## Light, stability, and level

- Test daylight, an evenly lit room, a dim room, and near darkness. Report when
  More Light Needed first appears and whether a usable dim shot is rejected.
- Pan deliberately, hold with normal hand tremor, brace against a surface, and
  use a tripod. Report whether Hold Still is too sensitive or too permissive.
- Tilt clockwise and counterclockwise by small and obvious amounts. Confirm the
  level cue appears in both directions, disappears near level, and does not
  flicker around the threshold.
- Point the phone steeply up and down. Confirm level guidance disappears instead
  of inventing a horizon when gravity has too little screen-plane projection.

## Ready and Auto Capture

- Confirm Ready appears only after light, stability, framing, and level are all
  acceptable, and that the Ready haptic fires once per transition.
- Enable Auto Capture and measure the perceived delay after Ready. Report too
  fast, correct, or too slow; the starting target is about 0.7 seconds.
- Lose Ready halfway through the progress ring. Confirm progress cancels at once
  and no photo is taken.
- Hold the same Ready scene after an automatic photo. Confirm it cannot capture
  a second photo until Ready is left and earned again.
- Press the manual shutter during Auto Capture progress. Confirm one photo is
  taken and no delayed automatic capture follows.
- Tap to focus while Ready. Confirm progress restarts only after focus/exposure
  settles and the new frame remains Ready.
- Switch front/rear cameras during a pending dwell, background/foreground the
  app, and trigger a camera interruption if practical. Confirm no immediate or
  duplicate capture follows any transition.

## Lens, orientation, saving, and performance

- Repeat key framing tests at every available 0.5x, 1x, and 2x preset. Report
  overlay misalignment or meaningfully different thresholds per lens.
- Verify capture orientation and rotating controls in portrait, upside-down,
  landscape-left, and landscape-right positions supported by the app/device.
- Save rear and front photos to Photos. Confirm orientation, mirroring, quality,
  metadata behavior, and that the original bytes are preserved.
- Run the preview for at least two minutes with faces entering/leaving the frame,
  Auto Capture enabled, and pinch zoom active. Report frame-rate drops, heat,
  delayed controls, or guidance lag.

Record the iPhone model, iOS version, active lens, light conditions, and whether
the phone was handheld or supported with every calibration report.
