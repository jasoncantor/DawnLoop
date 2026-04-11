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

- **Max concurrent validators:** `1`
- Rationale: the validation dry run showed the simulator path is relatively heavy on this 10-core / 16 GB machine, and this mission only needs one reliable simulator lane while the test-path repair is in flight.
- Use CI-style `build-for-testing` + `test-without-building` against a dynamically resolved available iPhone simulator, with `-maximum-parallel-testing-workers 1` for the shared full-suite command.

### Real-device / Apple Home validation

- **Max concurrent validators:** `1`
- Rationale: this surface depends on one physical iPhone and one shared HomeKit environment; concurrent mutation would create unreliable evidence and cross-test interference.

## Special Guidance

- Treat HomeKit execution through Apple Home as the reliability contract; do not validate wake execution via foreground timers.
- Current user preference for this mission: automated validation only for now. Do not require physical-device or Apple Home checks to complete this mission.
- Current user preference for this mission phase: keep active feature work light on testing. Use targeted simulator checks during implementation and reserve the shared full-suite simulator flow for milestone confidence checks or clearly risky changes.
- For widget quick controls, validate both shipped states:
  - interactive controls enabled and working safely, or
  - widget intentionally shipped as read-only
- For App Intents, validate both happy paths and blocked/out-of-sync alarm responses.
- If a validator cannot access a real Home or unlocked device when required, it must return to the orchestrator instead of silently downgrading to mocks.
- If validators are green and only scrutiny depth concerns remain, the orchestrator may intentionally override scrutiny and defer extra test-depth work.
