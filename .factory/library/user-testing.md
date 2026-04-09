# User Testing

Testing surface notes for DawnLoop validators and workers.

**What belongs here:** validation surfaces, required tools, setup expectations, and concurrency guidance.
**What does NOT belong here:** implementation detail or speculative product requirements.

---

## Validation Surface

### Surface A: iPhone Simulator

Use this surface for:

- onboarding screen flow and relaunch behavior
- list/detail/editor UI behavior
- pure planner behavior surfaced through UI
- SwiftData-backed persistence flows
- mocked HomeKit capability and drift states
- widget layout/timeline previews when available
- App Intent metadata and non-HomeKit action flows where simulator execution is sufficient

Primary tools:

- `xcodebuild`
- XCTest / Swift Testing / UI tests
- Widget previews / timeline inspection

Expected evidence:

- screenshots
- UI test logs
- deterministic planner/repository test output

### Surface B: Real iPhone + Apple Home

Use this surface for:

- Home permission prompts
- no Home / no hub / no compatible accessory states
- live home and accessory discovery
- HomeKit action set + trigger generation
- automation edit/rollback/delete behavior against a real Home
- consistency checking and repair against a changed Home graph
- widget interaction fidelity
- App Intents / Shortcuts execution quality

Primary tools:

- physical iPhone
- Apple Home setup
- manual validation with screenshots / recordings
- `xcodebuild` for device build/test if available

Expected evidence:

- screenshots
- screen recordings
- structured app logs when helpful

## Validation Concurrency

### Simulator-based validation

- **Max concurrent validators:** `3`
- Rationale: iOS Simulator + `xcodebuild test` is materially heavier than a typical web or CLI validation path on this 10-core / 16 GB machine.
- Use `-maximum-parallel-testing-workers 3` for simulator test runs unless a worker has a narrower, cheaper test target.

### Real-device / Apple Home validation

- **Max concurrent validators:** `1`
- Rationale: this surface depends on one physical iPhone and one shared HomeKit environment; concurrent mutation would create unreliable evidence and cross-test interference.

## Special Guidance

- Treat HomeKit execution through Apple Home as the reliability contract; do not validate wake execution via foreground timers.
- For widget quick controls, validate both shipped states:
  - interactive controls enabled and working safely, or
  - widget intentionally shipped as read-only
- For App Intents, validate both happy paths and blocked/out-of-sync alarm responses.
- If a validator cannot access a real Home or unlocked device when required, it must return to the orchestrator instead of silently downgrading to mocks.
