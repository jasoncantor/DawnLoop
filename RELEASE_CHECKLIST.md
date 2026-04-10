# Release Checklist

## Before archiving

- Confirm the `DawnLoop` target signs with the correct team and bundle identifier.
- Verify [DawnLoop.entitlements](/Users/jasoncantor/Downloads/DawnLoop/DawnLoopApp/DawnLoop.entitlements) is present in Signing & Capabilities.
- Build and run the app on an iPhone running iOS 17+.
- Run unit and UI tests locally or through CI.

## Privacy and capabilities

- Confirm `NSHomeKitUsageDescription` matches the shipped product behavior.
- Verify no debug-only UI is visible in Release.
- Review any HomeKit-dependent messaging for accuracy.

## TestFlight validation

- Complete onboarding on device.
- Select the intended Apple Home.
- Select at least one compatible light.
- Create, edit, duplicate, enable, disable, and delete an alarm.
- Confirm enabled alarms create HomeKit triggers and scenes.
- Confirm broken bindings surface as repair-needed and can be repaired.
- Confirm next-run times match Home app automation schedules.

## App Store submission prep

- Capture required screenshots.
- Finalize privacy disclosures in App Store Connect.
- Review metadata in [APP_STORE_METADATA.md](/Users/jasoncantor/Downloads/DawnLoop/APP_STORE_METADATA.md).
- Archive, validate, and upload the build.
