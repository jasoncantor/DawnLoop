# DawnLoop

DawnLoop is an iPhone app for iOS 17+ that creates stepped Light Alarms in Apple Home using selected lights.

## License

This repository is source-available under [LICENSE](/Users/jasoncantor/Downloads/DawnLoop/LICENSE).
It is intentionally not released under an OSI-approved open-source license.
People may build and install DawnLoop for themselves, but public App Store and
TestFlight redistribution of this app or its branded forks is reserved. Brand
rules are in [TRADEMARKS.md](/Users/jasoncantor/Downloads/DawnLoop/TRADEMARKS.md).
A plain-language summary is in [LEGAL.md](/Users/jasoncantor/Downloads/DawnLoop/LEGAL.md).

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

- Shared local simulator validation is defined in `.factory/services.yaml` and mirrors CI by resolving an available iPhone simulator dynamically, running `build-for-testing`, then `test-without-building`.
- App build: use the shared `.factory/services.yaml` `build` command.
- Simulator tests: use the shared `.factory/services.yaml` `test` command.

## TestFlight readiness notes

- CI is defined in [.github/workflows/ios-ci.yml](/Users/jasoncantor/Downloads/DawnLoop/.github/workflows/ios-ci.yml).
- App submission assets and copy are in [AppStoreSubmission/README.md](/Users/jasoncantor/Downloads/DawnLoop/AppStoreSubmission/README.md) and [APP_STORE_METADATA.md](/Users/jasoncantor/Downloads/DawnLoop/APP_STORE_METADATA.md).
- The remaining manual work is signing, real-home validation, hosted policy/support URLs, privacy disclosures, and App Store Connect submission.
