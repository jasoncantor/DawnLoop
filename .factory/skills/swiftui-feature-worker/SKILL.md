---
name: swiftui-feature-worker
description: Implements DawnLoop SwiftUI features, domain models, persistence, and app-facing workflows with tests first.
---

# SwiftUI Feature Worker

NOTE: Startup and cleanup are handled by `worker-base`. This skill defines the work procedure.

## When to Use This Skill

Use this skill for DawnLoop features centered on:

- app shell and theme
- onboarding presentation
- home/accessory presentation with mocked platform services
- alarm editor and list UI
- SwiftData repositories and model mapping
- feature flags and billing scaffolding
- README / architecture-note updates near mission end

## Required Skills

None.

## Work Procedure

1. Read the assigned feature, `mission.md`, `AGENTS.md`, `.factory/library/architecture.md`, and any relevant library topic files before touching code.
2. Identify the validation-contract IDs listed in the feature’s `fulfills` array and make sure the implementation will make those assertions testable.
3. Write failing tests first:
   - unit tests for pure state, view models, repositories, and formatting rules
   - UI tests or snapshot-style coverage for visible screen states when the feature changes UI
4. Implement the feature using SwiftUI + Swift Concurrency while keeping business logic out of views.
5. Use protocols and dependency injection for anything that could later need HomeKit, WidgetKit, App Intents, StoreKit, time, UUID, or persistence seams.
6. Run the narrowest targeted tests first, then run the project validation commands from `.factory/services.yaml`.
7. Manually verify the changed UX on iPhone Simulator when the feature affects visible UI. Capture the exact flow in `verification.interactiveChecks`.
8. Confirm no duplicate rows, stale state, or broken navigation were introduced in adjacent DawnLoop flows.
9. Leave the tree clean: no watch processes, no orphaned simulators started by your session, no TODO-only “implement later” placeholders for required behavior.

## Example Handoff

```json
{
  "salientSummary": "Built the initial DawnLoop onboarding shell and app theme, including the three-screen first-run flow and persisted onboarding completion. Added SwiftUI UI tests for screen order and relaunch behavior, then verified the flow on iPhone Simulator.",
  "whatWasImplemented": "Created the app shell, shared sunrise-inspired theme tokens, onboarding router state, three onboarding screens, and persisted onboarding-completion handling so the main app flow appears on relaunch instead of replaying onboarding.",
  "whatWasLeftUndone": "",
  "verification": {
    "commandsRun": [
      {
        "command": "xcodebuild -project DawnLoop.xcodeproj -scheme DawnLoop -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing DawnLoopUITests/OnboardingFlowTests",
        "exitCode": 0,
        "observation": "Onboarding UI tests passed, including relaunch coverage."
      },
      {
        "command": "xcodebuild -project DawnLoop.xcodeproj -scheme DawnLoop -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build",
        "exitCode": 0,
        "observation": "App built cleanly for simulator."
      }
    ],
    "interactiveChecks": [
      {
        "action": "Launched the app on iPhone 17 Pro simulator, advanced through the three onboarding screens, terminated the app, and relaunched it.",
        "observed": "The onboarding screens rendered correctly, the primary CTA advanced in order, and relaunch returned to the main flow rather than replaying onboarding."
      }
    ]
  },
  "tests": {
    "added": [
      {
        "file": "DawnLoopUITests/OnboardingFlowTests.swift",
        "cases": [
          {
            "name": "testOnboardingShowsThreeScreensInOrder",
            "verifies": "The first-run flow shows exactly three onboarding screens before completion."
          },
          {
            "name": "testCompletedOnboardingDoesNotReappearOnRelaunch",
            "verifies": "Onboarding completion is persisted across relaunch."
          }
        ]
      }
    ]
  },
  "discoveredIssues": []
}
```

## When to Return to Orchestrator

- The feature needs real HomeKit/device behavior that cannot be validated from simulator or mocks alone.
- The feature depends on a HomeKit adapter or shared model that does not exist yet.
- The visual requirement conflicts with an existing architecture boundary or validation assertion.
- `xcodebuild` commands or simulator destinations in `.factory/services.yaml` are broken and require orchestrator updates.
