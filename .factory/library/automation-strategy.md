# Automation Strategy

Specific factual guidance for DawnLoop automation generation.

---

## Execution Model

DawnLoop alarms are represented as:

1. app-owned alarm metadata in SwiftData
2. a generated step plan
3. a durable binding to HomeKit action sets and timer triggers

The app is responsible for generating, diffing, validating, repairing, and deleting those bindings.

## Reliability Rules

- Prefer stepped HomeKit automations over foreground timers.
- Prefer fewer, safer steps over very fine-grained but fragile schedules.
- Make step count configurable in code.
- Treat partially created HomeKit objects as failure states that require rollback or cleanup.
- Never expose raw HomeKit errors directly to end users.

## Capability Rules

- Brightness-only accessories must remain valid targets.
- Color-capable alarms degrade gracefully for less capable accessories.
- Outlets and window coverings are supported only if the shipped workflow gives them a clear wake-routine behavior; otherwise they should be filtered cleanly.

## Binding Rules

- Namescape app-created HomeKit objects so they can be identified later.
- Persist the mapping between each DawnLoop alarm and every generated HomeKit object.
- Editing should preserve stable bindings where user-visible behavior remains the same.
- Deleting must remove bindings and attempt HomeKit cleanup.
- Validation must detect drift caused by Home app changes or missing accessories.

## Repair Rules

- Repair should rebuild only what is broken where possible.
- Re-running repair on a healthy alarm should be idempotent.
- Any unrepaired mismatch must surface as a user-visible needs-attention state.
