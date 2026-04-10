# DawnLoop

DawnLoop is an iPhone app for iOS 17+ that creates stepped sunrise alarms in Apple Home using selected lights.

## What v1 ships

- Onboarding into Home selection and compatible light selection
- Local alarm persistence with repeat schedules
- Create, edit, duplicate, enable, disable, and delete alarm flows
- HomeKit automation generation for enabled alarms
- Drift detection and repair for broken HomeKit bindings
- Alarm list status, health, and next-run visibility

## Local setup

1. Open [DawnLoop.xcodeproj](/Users/jasoncantor/Downloads/DawnLoop/DawnLoop.xcodeproj) in Xcode 16+.
2. Set a valid Apple development team for the `DawnLoop` target.
3. Confirm the `HomeKit` capability is enabled and [DawnLoop.entitlements](/Users/jasoncantor/Downloads/DawnLoop/DawnLoopApp/DawnLoop.entitlements) is attached.
4. Build and run on an iPhone running iOS 17+ for real HomeKit verification.

## Required capabilities

- HomeKit entitlement
- `NSHomeKitUsageDescription` privacy string
- Apple Home configured with a Home Hub for real timer-trigger execution

## Running tests

- App build: `xcodebuild -scheme DawnLoop -project DawnLoop.xcodeproj -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
- Simulator tests: `xcodebuild -scheme DawnLoop -project DawnLoop.xcodeproj -destination 'platform=iOS Simulator,OS=26.4,name=iPhone 17' CODE_SIGNING_ALLOWED=NO test`

## TestFlight readiness notes

- CI is defined in [.github/workflows/ios-ci.yml](/Users/jasoncantor/Downloads/DawnLoop/.github/workflows/ios-ci.yml).
- The remaining manual work is signing, real-home validation, screenshots, privacy disclosures, and App Store Connect metadata.
