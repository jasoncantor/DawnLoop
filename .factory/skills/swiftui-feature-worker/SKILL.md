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
3. For the current DawnLoop mission phase, keep testing lean:
   - add or adjust tests only when they protect risky changed logic, cover a known regression, or are directly required to unblock validators
   - avoid broad new test scaffolding purely to satisfy scrutiny depth
4. Implement the feature using SwiftUI + Swift Concurrency while keeping business logic out of views.
5. Use protocols and dependency injection for anything that could later need HomeKit, WidgetKit, App Intents, StoreKit, time, UUID, or persistence seams.
6. Run the lightest validation that credibly proves the changed behavior, then use the shared project validators at milestone confidence points or when the feature explicitly requires them.
7. When the feature affects visible UI, do brief simulator verification for the changed path and capture it in `verification.interactiveChecks` when practical.
8. Before handing off success, verify that the committed revision matches your validation claim:
   - re-run the final validator commands after your last code edit
   - ensure the results come from the code you are actually committing
   - if a command failed or was cancelled earlier, do not report it as passing
9. Confirm no duplicate rows, stale state, broken navigation, or test-order dependencies were introduced in adjacent DawnLoop flows. If tests use launch arguments or reset hooks, confirm the app actually handles them.
   - reset hooks may clear persisted state for isolation, but they must never auto-complete product flows or convert blocked states into success semantics
10. Leave the tree clean: no watch processes, no orphaned simulators started by your session, no TODO-only “implement later” placeholders for required behavior.

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
- You cannot provide the required `verification.interactiveChecks` evidence for a visible UI change.
