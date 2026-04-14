# DawnLoop

DawnLoop is an iPhone-first SwiftUI app that turns Apple Home lights into gradual sunrise-style alarms. It lets you choose lights from your Apple Home setup, define a wake-up target based on a fixed time or solar events, preview the ramp, and generate the underlying Apple Home automations for you.

## Download

- App Store: [DawnLoop on the App Store](https://apps.apple.com/app/dawnloop/id6762026316)
- Prefer not to pay for the App Store version? You can clone this repository and build/run DawnLoop yourself in Xcode by following the setup steps below.

## Bugs and issues

If you run into a bug or have an issue, please open an issue in this repository so I can see it and fix it:

- [Create a new issue](https://github.com/jasoncantor/DawnLoop/issues/new)

This is my first app using HomeKit, and it’s working pretty well for me so far, but reports are very helpful.

## Why DawnLoop?

Traditional alarms wake you with sound. DawnLoop uses the lights you already own to make mornings feel more natural:

- Pick one or more compatible lights from Apple Home
- Build a gradual wake-up ramp over a configurable duration
- Base alarms on a clock time, sunrise, or sunset
- Repeat on selected weekdays
- Use brightness-only, color-temperature, or full-color ramps depending on device capability
- Repair or recreate Apple Home automations when they drift out of sync

## Current feature set

- Guided onboarding and Apple Home access checks
- Multi-home selection when more than one Home exists
- Compatible accessory discovery grouped by room
- Alarm editor with:
  - custom names
  - fixed-time, sunrise, and sunset scheduling
  - weekday repeat schedules
  - duration and step-count control
  - gradient curves
  - brightness and color targets
  - live preview of the generated ramp
- Capability-aware planning that gracefully degrades for brightness-only or tunable-white lights
- On-device persistence with SwiftData
- HomeKit automation generation, removal, validation, and repair
- Unit tests and UI tests, plus launch arguments for seeded test states

## How it works

1. Complete onboarding and grant Apple Home access.
2. Choose the Home you want to control if you have more than one.
3. Select the compatible lights you want DawnLoop to use.
4. Create a Light Alarm based on a clock time, sunrise, or sunset.
5. Tune repeat days, duration, step count, brightness, gradient, and color behavior.
6. Save the alarm and let DawnLoop create the matching Apple Home automations.
7. If those automations drift later, use the in-app repair flow to resync them.

## Tech stack

- SwiftUI for the app UI
- SwiftData for on-device persistence
- HomeKit and Apple Home for automation creation and accessory discovery
- Core Location for local sunrise and sunset preview calculations
- Swift 6
- Xcode project based workflow, no backend, no third-party dependencies

## Requirements

For the setup reflected in this repo, use:

- macOS
- Xcode 26.3
- iOS Simulator for automated build and test runs
- An Apple Home setup with:
  - at least one Home
  - a Home Hub
  - one or more compatible lights
- Apple Home permission
- Location permission if you want local sunrise and sunset preview timing

The current Xcode project is configured with a minimum iOS deployment target of **iOS 26.0**.

## Getting started

### 1. Clone the repo

```bash
git clone https://github.com/jasoncantor/DawnLoop.git
cd DawnLoop
```

### 2. Open the project in Xcode

Open `DawnLoop.xcodeproj`.

If Xcode asks you to update signing, choose your team and adjust the bundle identifier if needed.

### 3. Resolve package dependencies

```bash
xcodebuild -project DawnLoop.xcodeproj -resolvePackageDependencies
```

### 4. Run the app

Select the `DawnLoop` scheme and run on an iPhone simulator or a device.

On first launch, DawnLoop will guide you through onboarding, request access to Apple Home, and optionally use your location to preview sunrise or sunset based schedules on-device.

## Command line build and test

The repo treats `.factory/services.yaml` as the canonical source for shared commands. The most useful ones are below.

### Build

```bash
SIMULATOR_UDID=$(python3 .factory/resolve_simulator_udid.py)

xcodebuild \
  -project DawnLoop.xcodeproj \
  -scheme DawnLoop \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -derivedDataPath .derivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

### Test

```bash
SIMULATOR_UDID=$(python3 .factory/resolve_simulator_udid.py)

xcodebuild \
  -project DawnLoop.xcodeproj \
  -scheme DawnLoop \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -derivedDataPath .derivedData \
  CODE_SIGNING_ALLOWED=NO \
  build-for-testing

xcodebuild \
  -project DawnLoop.xcodeproj \
  -scheme DawnLoop \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -derivedDataPath .derivedData \
  CODE_SIGNING_ALLOWED=NO \
  test-without-building \
  -parallel-testing-enabled YES \
  -maximum-parallel-testing-workers 1
```

### Planner-focused tests

```bash
SIMULATOR_UDID=$(python3 .factory/resolve_simulator_udid.py)

xcodebuild \
  -project DawnLoop.xcodeproj \
  -scheme DawnLoop \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -derivedDataPath .derivedData \
  CODE_SIGNING_ALLOWED=NO \
  test \
  -parallel-testing-enabled NO \
  -only-testing:DawnLoopTests/WakeAlarmPlannerPreviewTests \
  -only-testing:DawnLoopTests/AutomationServicesTests \
  -only-testing:DawnLoopTests/AlarmEditorValidationTests
```

### Lint

```bash
xcrun swift-format lint -r DawnLoopApp Packages DawnLoopWidgetExtension DawnLoopIntentsExtension DawnLoopTests
```

Note: the repo guidance mentions that some directories referenced by the lint command are planned for future milestones and may not exist yet.

## Project structure

```text
DawnLoop/
├── .factory/              # Shared build, test, and tooling commands
├── DawnLoop.xcodeproj/    # Xcode project
├── DawnLoopApp/
│   ├── Alarms/            # Alarm editor, planner preview, alarm flows
│   ├── App/               # App entry, environment, persistence wiring
│   ├── MainFlow/          # Main navigation and alarm list
│   ├── Models/            # Core alarm and HomeKit-facing models
│   ├── Onboarding/        # Onboarding and Apple Home setup flow
│   ├── Services/          # Home access, discovery, repository, automation services
│   └── Theme/             # Shared visual styling
├── DawnLoopTests/         # Unit tests
└── DawnLoopUITests/       # UI and flow tests
```

## Test coverage highlights

Unit tests cover:

- accessory discovery
- home access state
- home selection
- onboarding state
- repository behavior
- alarm validation
- preview planning
- automation services

UI tests cover:

- onboarding flow
- home discovery flow
- alarm validation flows
- alarm preview flows
- launch coverage
- App Store screenshot generation

For deterministic UI testing, the app supports launch arguments such as:

- `--seed-test-home`
- `--seed-repair-needed-alarm`
- `--reset-onboarding`
- `--reset-home-selection`
- `--reset-alarms`

## Notes and limitations

- DawnLoop is built around Apple Home and HomeKit. Without a configured Home, a Home Hub, and compatible accessories, the full automation flow cannot complete.
- Solar previews use local device context when available, while the generated HomeKit automations still use native solar triggers.
- Selected lights may support different capabilities. DawnLoop falls back to the best supported behavior instead of assuming every light can do full color or tunable white.
- Full end-to-end validation of Home automations is best done on real Apple hardware and a real Apple Home setup.
- This is a native iOS and Xcode project. The full app target, unit tests, and UI tests require macOS.

## Contributing

Issues and pull requests are welcome.

For changes that affect alarm timing, brightness behavior, or automation generation, validate both the preview planner and the generated automation behavior.
