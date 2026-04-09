# Environment

Environment variables, external dependencies, and setup notes.

**What belongs here:** required capabilities, privacy strings, external prerequisites, and local setup assumptions.
**What does NOT belong here:** service ports/commands (use `.factory/services.yaml`).

---

## Platform Assumptions

- iPhone-first app
- iOS 17+
- SwiftUI
- Swift Concurrency
- SwiftData for app-owned persistence
- Xcode 26.3 toolchain available in this environment

## Apple Framework Requirements

Workers should expect to configure and use:

- HomeKit capability
- `NSHomeKitUsageDescription`
- WidgetKit extension target
- App Intents extension target

StoreKit 2 is scaffolded behind feature flags and must not block MVP functionality.

## External Dependencies

No backend, cloud service, or third-party API is required for MVP.

Real end-to-end validation later depends on:

- a physical iPhone
- an Apple Home with at least one compatible accessory
- a home hub for reliable automation validation

## Persistence Assumptions

- SwiftData is the local source of truth for app-owned alarm metadata and HomeKit bindings.
- Durable app-to-HomeKit identifiers must survive relaunchs.
- HomeKit data should be re-resolved against the current Home graph instead of assuming stored references are always still valid.

## Setup Notes

- Prefer simulator work for UI, layout, pure business logic, and repository tests.
- Reserve real-device testing for Home permission, accessory discovery against a real Home, widgets, App Intents, and HomeKit automation behavior.
- Do not introduce private APIs or foreground timer execution for scheduled alarms.
