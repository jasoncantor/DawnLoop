---
name: apple-integration-worker
description: Implements DawnLoop Apple-platform integrations, including HomeKit automation, widgets, App Intents, repair flows, and reliability-critical platform adapters.
---

# Apple Integration Worker

NOTE: Startup and cleanup are handled by `worker-base`. This skill defines the work procedure.

## When to Use This Skill

Use this skill for DawnLoop features centered on:

- HomeKit adapters, capability mapping, and permission handling
- sunrise step planning tied to accessory capabilities
- automation binding generation, diffing, rollback, cleanup, and repair
- widget timeline and interactive control behavior
- App Intents / Siri / Shortcuts integration
- platform-facing billing scaffolding when StoreKit interfaces are involved

## Required Skills

None.

## Work Procedure

1. Read the assigned feature, `mission.md`, `AGENTS.md`, `.factory/library/architecture.md`, `.factory/library/automation-strategy.md`, `.factory/library/environment.md`, and `.factory/library/user-testing.md`.
2. Read the feature’s `fulfills` IDs and translate them into observable outcomes before implementing.
3. Put platform seams behind protocols first if they are missing. Do not wire HomeKit, WidgetKit, App Intents, StoreKit, time, or UUID access directly into views.
4. Write failing tests first:
   - pure planner tests for ordered steps and capability degradation
   - mocked adapter/repository tests for HomeKit binding, diff, rollback, cleanup, and repair behavior
   - intent/widget tests for canonical state mutation and blocked-state handling where supported
5. Implement the feature with reliability-first behavior:
   - avoid foreground timers for alarm execution
   - namescape app-created HomeKit objects
   - persist durable app-to-HomeKit bindings
   - roll back or surface repair-needed state on partial failure
6. Run targeted tests, then run the shared `build` and `test` commands from `.factory/services.yaml`.
7. Manually verify the changed surface:
   - simulator for planner/UI/platform-independent state
   - real iPhone + Apple Home when the feature genuinely requires live HomeKit, widget interaction, or App Intent validation
8. Record exactly what was and was not validated in the handoff. If real-device validation was required but unavailable, return to the orchestrator instead of guessing.
9. Confirm repeated runs do not duplicate HomeKit bindings, widget controls, or intent entities.

## Example Handoff

```json
{
  "salientSummary": "Implemented HomeKit-backed automation generation for enabled DawnLoop alarms using stepped action sets and timer triggers. Added failure-injection tests for rollback and verified the generated alarm reports a ready state after save.",
  "whatWasImplemented": "Added the HomeKit adapter protocol implementation, capability-driven planner integration, durable AutomationBinding persistence, save-time creation of action sets and timer triggers, and user-visible ready/blocked state reporting for enabled alarm saves.",
  "whatWasLeftUndone": "",
  "verification": {
    "commandsRun": [
      {
        "command": "xcodebuild -project DawnLoop.xcodeproj -scheme DawnLoop -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing DawnLoopTests/AutomationBindingServiceTests",
        "exitCode": 0,
        "observation": "Planner, binding, and rollback tests passed with mocked HomeKit services."
      },
      {
        "command": "xcodebuild -project DawnLoop.xcodeproj -scheme DawnLoop -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build",
        "exitCode": 0,
        "observation": "App and extensions compiled cleanly for simulator."
      }
    ],
    "interactiveChecks": [
      {
        "action": "Created a valid single-light alarm on simulator using mocked HomeKit capabilities and saved it as enabled.",
        "observed": "The save flow completed, a ready state was shown, and the alarm detail reflected the generated step summary and binding metadata."
      },
      {
        "action": "Ran a real-device save against a Home with one compatible light and inspected the resulting automation state.",
        "observed": "The alarm created HomeKit action sets and timer triggers for each planned step, and the app remained in a healthy synced state after save."
      }
    ]
  },
  "tests": {
    "added": [
      {
        "file": "DawnLoopTests/AutomationBindingServiceTests.swift",
        "cases": [
          {
            "name": "testEnabledSaveCreatesBindingsForAllPlannedSteps",
            "verifies": "A saved enabled alarm persists one durable binding covering the generated HomeKit objects."
          },
          {
            "name": "testFailedSaveRollsBackPartialHomeKitObjects",
            "verifies": "Partial HomeKit writes are cleaned up or reverted when generation fails."
          }
        ]
      }
    ]
  },
  "discoveredIssues": []
}
```

## When to Return to Orchestrator

- A required real-device or Apple Home validation step cannot be performed because the device is unavailable or the Home environment is not in the needed state.
- HomeKit public APIs do not support the requested behavior without changing the product approach.
- A feature would require violating the no-private-API or no-foreground-timer boundary.
- Widget or App Intent behavior is OS-version-dependent enough that the product requirement needs a human decision on fallback behavior.
