# Effort: App Store release pipeline with automated, branded screenshots

> **This prompt is app-agnostic.** It contains no project-specific names, paths,
> schemes, or bundle identifiers. Drop it into any iOS/iPadOS app repository as
> is. Phase 0 discovers what the project actually is; every later phase reads
> that result. Do not assume a project layout — verify it.

Read this whole prompt before starting. Work on a new branch off the default
branch, named `ci/appstore-screenshot-pipeline`. Commit after each phase
completes and its gate passes. Never push. Never weaken, skip, or delete an
existing test to make something pass. If you are blocked more than twice on the
same problem, stop, write `BLOCKED.md` at the repository root describing exactly
what you tried and why it is stuck, then move to the next independent phase
instead of guessing.

## Goal

Pushing to the `appstore-release` branch runs one pipeline that:

1. Runs the project's full validation suite — build, unit tests, UI tests,
   linting, and whatever other gates the repository already defines.
2. Boots simulators, drives the app to a defined set of screens, and captures
   real screenshots at every App Store size and locale required.
3. Composes those captures into finished marketing images with backgrounds,
   headline copy, and optional device frames.
4. Publishes the result as a downloadable artifact.

The developer triggers it, waits, downloads a zip, and uploads to App Store
Connect. No local screenshot work, no manual cropping, no hand-editing.

## Governing principles

**REAL PIXELS ONLY.** Every image that depicts the app is a genuine simulator
capture of the app running. No mockups, no redrawn UI, no Figma exports standing
in for the product. Apple rejects screenshots that are not the actual app in use
(guideline 2.3.3), so a mockup fallback is a submission risk, not a shortcut. If
a capture cannot be produced, the build fails.

**APP-AGNOSTIC AND CONFIG-DRIVEN.** No app name, scheme, bundle identifier,
device list, locale, or marketing string is hardcoded in a script or workflow.
All of it lives in one manifest file. Someone should be able to copy this
pipeline into an unrelated app, edit only the manifest, and have it work.

**DETERMINISTIC.** Two runs on the same commit produce byte-identical images.
Time, battery, signal strength, animations, and seeded data are all pinned.

**FAIL LOUDLY.** A missing screen, an empty capture, a clipped label, or a
timed-out simulator fails the run with a clear message. Never emit a placeholder
and never silently skip a device or locale.

## Phase 0 — Discovery and manifest

Do not write any pipeline code yet. First, inspect the repository and record
what is actually there:

- Xcode project vs workspace vs Swift Package; the exact path.
- Available schemes, and which one is the shippable app.
- Whether a UI test target already exists, and its name.
- The deployment target and supported device families (iPhone only, iPad, both).
- Existing lint/format/test scripts or Makefile targets, and how CI (if any)
  currently invokes them.
- Whether the app needs seeded state — an account, a database, network
  responses — to show a non-empty UI.
- Existing localization: which locales the app actually ships.

Write findings to `docs/SCREENSHOT_PIPELINE.md` as a short "detected project
shape" section. If something is ambiguous — two plausible schemes, no UI test
target — record the ambiguity and the choice made, rather than guessing
silently.

Then create the manifest, `fastlane/screenshots.yml` or
`tools/screenshots/manifest.yml` (pick one and be consistent), covering:

```yaml
app:
  scheme: ""            # discovered, not assumed
  project: ""           # .xcodeproj / .xcworkspace path
  ui_test_target: ""
  launch_arguments: []  # e.g. ["-UITestScreenshotMode", "YES"]

devices:                # simulator names, resolved against `xcrun simctl list`
  - name: ""
    appstore_size: ""   # the ASC display family this satisfies

locales: ["en-US"]

screens:                # one entry per screenshot
  - id: "home"
    headline: ""
    subhead: ""
    accent: ""
  # ...

style:
  background: ""        # gradient stops / solid
  font: ""              # path to a vendored font file
  device_frame: true|false
```

**Verify the required App Store sizes against Apple's current documentation
rather than hardcoding a remembered list.** Apple has repeatedly changed which
display families are mandatory and now derives some sizes automatically from
others. Getting this wrong means an upload rejection at the very last step.
Record the verified requirement, with the date checked, in
`docs/SCREENSHOT_PIPELINE.md`.

**Gate:** the manifest parses, and every device name in it resolves against
`xcrun simctl list devicetypes` on the runner image being targeted.

## Phase 1 — Drive the app to each screenshot state

Add (or extend) a UI test target whose only job is navigation and capture. One
test method per `screens` entry in the manifest, named to match its `id`.

Requirements:

- **Seed deterministic state.** Pass a launch argument that puts the app in a
  screenshot mode with fixed, realistic demo content — no empty states, no
  spinners, no "no data yet". If the app needs network, stub it; a screenshot run
  must never depend on a live service.
- **Disable animations** so captures are never taken mid-transition.
- **Wait for a real readiness signal** — a specific element existing and being
  hittable — not `sleep`. Sleeps are the single most common cause of a
  screenshot pipeline that passes locally and produces half-rendered images in
  CI, where everything is slower.
- **Dismiss or pre-grant permission dialogs.** A system alert over the UI ruins
  a capture. Handle notification, location, camera, and tracking prompts
  explicitly rather than hoping they do not appear.
- **Fail if an expected element is missing**, rather than capturing whatever is
  on screen.

Prefer `fastlane snapshot` if the project already uses fastlane or if
multi-locale is required — it solves device and locale looping, and its
`snapshot()` helper handles the capture plumbing. Otherwise a plain XCUITest
target driven by `xcodebuild test` is fine and has fewer moving parts. Record
the choice and the reason in `docs/SCREENSHOT_PIPELINE.md`.

**Gate:** running the UI test target locally against one simulator produces one
correctly-named PNG per screen, each showing populated UI.

## Phase 2 — Capture harness

Add `scripts/capture-screenshots.sh`, reading only the manifest:

1. Boot each simulator, and **wait for it to be fully booted**, not merely
   created.
2. **Override the status bar** before capturing:
   ```sh
   xcrun simctl status_bar <udid> override \
     --time "9:41" --batteryState charged --batteryLevel 100 \
     --cellularBars 4 --wifiBars 3
   ```
   Without this, every screenshot carries the runner's real clock and a
   half-empty battery, which looks unfinished and breaks determinism.
3. Set the appearance (light/dark) explicitly if the manifest specifies it.
4. Loop devices × locales × screens, invoking the Phase 1 tests.
5. Capture the **full device screen**, including the status bar, with
   `xcrun simctl io <udid> screenshot`. Note that XCUITest's own screenshot API
   captures only the app's own frame and may omit the status bar — for store
   assets, the full-screen capture is normally what you want. Confirm which one
   the chosen approach produces and make it explicit.
6. Write output to a predictable tree: `<out>/<locale>/<device>/<screen>.png`.
7. **Validate every capture**: non-zero size, expected pixel dimensions, and not
   a single flat color. A uniformly black or white image means the capture
   happened before the UI drew — fail, do not ship it.
8. Shut down and clean up simulators so repeat runs start clean.

**Gate:** the script produces the full tree for at least two devices and, if
localized, two locales, with every image passing validation.

## Phase 3 — Branding and marketing composition

Add `tools/screenshots/compose.py` (Python + Pillow), driven by the same
manifest. For each capture, produce the finished store image:

- Background from the manifest's style block — gradient or solid, with optional
  soft accent glows.
- Headline and subhead from the manifest's `screens` entry, positioned
  consistently.
- The device capture inset, with rounded corners and a soft drop shadow, and an
  optional device frame if `device_frame` is true.
- Output at the exact pixel dimensions the target App Store display family
  requires — no scaling after the fact.

### Traps that will otherwise bite

- **Fonts.** Vendor the font file into the repository and load it by relative
  path. Never resolve a font by system name or absolute path: it silently falls
  back to a different typeface on a machine that lacks it, and the mismatch is
  easy to miss in a thumbnail. Confirm the font's license permits redistribution
  and include the license file.
- **Alpha compositing.** Drawing a translucent fill directly onto a canvas that
  is later flattened to RGB discards the alpha and leaves an opaque block —
  typically a bright bar where a subtle frosted panel was intended, swallowing
  any light text on it. Draw translucent layers separately and combine with
  `alpha_composite`.
- **Text overflow, especially localized.** German and French strings routinely
  run 30–40% longer than English. Measure and auto-shrink every headline and
  subhead to its allotted box; never position text by fixed offsets that assume
  a length. A run must **fail** on text that cannot fit legibly rather than
  clipping it.
- **Right-to-left locales.** If any target locale is RTL, mirror the layout
  rather than leaving left-aligned text hanging.
- **Colour space.** Save sRGB. Simulator captures can carry a display P3
  profile, which shifts colours once composited and uploaded.

**Gate:** every composed image is the exact required size, with no clipped,
overlapping, or missing text, in every locale. Inspect them — do not infer
success from the script exiting zero.

## Phase 4 — The workflow

Add `.github/workflows/appstore-release.yml`:

- Triggers on `push` to `appstore-release`, plus `workflow_dispatch` for manual
  reruns.
- Runs on a macOS runner. Do not pin an image version without checking which
  Xcode and Swift it provides — mismatches with the project's required toolchain
  are a common and confusing failure.
- Job order: **validation gates first**, screenshots second. Do not spend
  simulator time on a commit that does not build or whose tests fail. Reuse the
  repository's existing scripts rather than reimplementing checks.
- Cache derived data and dependencies where it is safe to.
- Upload one artifact containing the composed store images, organised by locale
  and device, plus the raw captures for debugging.
- Set a realistic `timeout-minutes`. Simulator matrices are slow, and macOS
  runner minutes bill at a multiplier on private repositories — keep the device
  and locale matrix to what the store actually requires.
- Do **not** upload to App Store Connect automatically. If an upload step is
  wanted, add it behind an explicit `workflow_dispatch` boolean input that
  defaults to false, using credentials from repository secrets, and document
  which secrets are required.

**Gate:** the workflow file parses as valid YAML and any repository metadata
check still passes.

## Phase 5 — Documentation

Complete `docs/SCREENSHOT_PIPELINE.md`:

- The detected project shape from Phase 0.
- How to add a new screen, device, or locale — which should be a manifest edit
  plus one UI test method, and nothing else.
- How to run the whole thing locally.
- The verified App Store size requirements and the date checked.
- Any known gaps, explicitly listed rather than left implicit.

## Verification

- Run the pipeline end to end locally.
- Run the composition step twice and confirm byte-identical output.
- Open every composed image at full size and check it against the Phase 3 trap
  list.
- Confirm each image's dimensions match what App Store Connect expects.
- Confirm the validation gates actually fail the run when something is broken —
  introduce a deliberate test failure, watch the pipeline stop, then revert it.

## Human checklist

Write `HUMAN_CHECKLIST-SCREENSHOTS.md` at the repository root:

- Push to `appstore-release`, download the artifact, and review every image at
  full size.
- Confirm the screenshots show the real app in use and would satisfy guideline
  2.3.3 — not a title card, login screen, or splash screen.
- Check that marketing copy is current and free of typos in every locale.
- Upload to App Store Connect and confirm every required display family is
  accepted.
