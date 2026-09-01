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

---

# Phase 2.5 additions

Everything below was added after the original Phase 2 checklist and has the
same status: the logic is unit tested, the feel is not. Report **too early /
correct / too late** for thresholds and **correct / reversed / inconsistent**
for directions.

## Shooting modes

The mode strip sits above the zoom controls. Each mode changes what the app
considers good framing, so test them against the thing they are for.

- **Portrait** — head-and-shoulders. Should behave exactly as it did before
  modes existed. Report any change in feel from the Phase 2 baseline.
- **Outfit** — stand back for a full-body shot. Report whether the app stops
  asking you to move closer at a distance that actually frames the whole body,
  and whether Fit The Whole Body appears when the frame cuts your knees or
  ankles. This is the pose pass; report if it fires when it should not.
- **Story** — report whether the framing it settles on leaves usable room at
  the top for text.
- **Food / Product** — shoot a plate or an object, with and without a person
  visible behind it. Report whether the app ever gives face-based framing
  advice in these modes. It should not.
- **Landscape** — report whether the horizon tolerance feels right. This is the
  tightest in the app; it should catch a tilt you can see but not nag at one
  you cannot.
- **Night** — shoot in a genuinely dark room. Report whether More Light Needed
  stops appearing, and whether Hold Still becomes noticeably stricter.

## Best shot

- Turn on Best Shot (stacked-squares icon). Take a photo of someone blinking
  deliberately. Report whether the kept frame has their eyes open.
- Report the shutter-to-review delay with Best Shot on. Three frames should
  feel deliberate, not slow. If it feels slow, report the count to reduce.
- Report whether the "Kept the best of 3" message is useful or noise.

## Reference framing

- Tap the photo icon, pick a portrait you like. Report whether the guidance
  then steers you toward that photo's framing rather than a centred one.
- With an off-centre reference, confirm the app asks you to move the frame in
  the direction that actually matches the reference.
- Report whether clearing the reference returns behaviour to the mode default.

## Enhancement

- Take an underexposed photo, tap Enhance. Report whether the result looks
  like a better photograph or like a processed one. **Faces are the thing to
  watch: any hint of plastic skin means the ceilings are too high.**
- Toggle Enhanced / original repeatedly. Confirm the original is unchanged.
- Save while Enhanced is showing and confirm the saved file is the enhanced
  one; repeat with the original showing.
- Take an already well-exposed photo and tap Enhance. Report whether "Already
  looks good" appears rather than a pointless change.

## Guidance that gets out of the way

- Line up a good shot and hold it. Report whether the instruction fading out
  after roughly a second and a half feels right, too eager, or too slow.
- Confirm the shutter ring stays accented while Ready even after the text has
  gone, so you can still tell the app is happy.

## Directional cue

- Report whether the edge chevron helps or distracts, and whether it ever
  covers the subject.
- On the front camera, confirm the chevron points the same way the instruction
  reads.

## Calibration overlay (debug builds only)

- Long-press the grid button. Confirm the overlay appears in a debug build and
  that the numbers track what you see.
- Confirm it cannot be summoned in a Release build.

## Expression gating

- Frame a good shot with Auto Capture on, then blink deliberately as the ring
  starts to fill. Report whether the capture is held off and "Almost — hold it"
  appears.
- Report whether the gate is too strict: if it regularly refuses to fire on a
  face that looks fine to you, `minimumFaceCaptureQuality` is too high.
- Group photo: confirm one person blinking holds the capture for everyone.
- Confirm the **manual shutter still fires immediately** while "Almost — hold
  it" is showing. It must never block a deliberate press.

## Burst shortlist

- With Best Shot on, take a photo and report whether the strip of three
  alternatives appears, and whether the app's own pick (the first, outlined) is
  the one you would have chosen.
- Tap another frame and confirm the large preview switches and Save keeps that
  frame.
- Confirm choosing a different frame clears any enhancement you had applied.
