# Architecture

How DawnLoop works at a high level.

**What belongs here:** system boundaries, module responsibilities, data flows, control surfaces, and invariants.
**What does NOT belong here:** implementation tickets, exact file paths for every screen, or step-by-step coding instructions.

---

## System Overview

DawnLoop is an iPhone-first SwiftUI app that turns Apple Home accessories into reliability-first sunrise alarms. The app owns alarm configuration, local metadata, validation state, and HomeKit object mappings. Apple Home executes the actual wake routine through generated HomeKit action sets and timer triggers so alarms do not depend on the app remaining active in the foreground.

## Implementation Posture

- SwiftUI UI layer
- Swift Concurrency for async flows
- MVVM-style feature architecture
- SwiftData-backed app-owned metadata and bindings
- protocol-wrapped platform adapters
- widgets, App Intents, and billing are later-milestone control surfaces; they should not distort earlier milestone architecture

## Top-Level Domains

- **Onboarding**: first-run education, Home access request, blocker-state messaging, retry and troubleshooting flows.
- **Homes & Accessories**: active-home selection, accessory discovery, capability filtering, room grouping, and plain-language readiness checks.
- **Alarms**: alarm editing, persistence, list presentation, quick controls, and empty/detail states.
- **Automation Generation**: pure step planning, HomeKit object generation, diff/update behavior, rollback, cleanup, consistency checking, and repair orchestration.
- **Control Surfaces**: widgets and App Intents that read and mutate the same canonical alarm state as the main app.
- **Billing**: isolated feature-flag and entitlement scaffolding only; it must not block MVP alarm flows.

## Runtime Components

### App Shell

The main SwiftUI app target owns:

- navigation and feature routing
- theme and design tokens
- shared app environment / dependency container
- top-level persistence container setup

### Domain Services

The app should keep business rules in services/use-cases, not in views:

- `HomeAccessService`
- `AccessoryDiscoveryService`
- `WakeAlarmRepository`
- `WakeAlarmPlanner`
- `AutomationBindingService`
- `AutomationRepairService`
- `AlarmValidationService`
- `FeatureFlagService`

### Platform Adapters

All Apple-framework integrations stay behind protocols:

- HomeKit adapter
- Widget synchronization adapter
- App Intents adapter
- StoreKit adapter
- logging adapter

## Recommended Module Shape

Use a small modular structure that keeps boundaries clear without over-fragmenting a greenfield app:

- `App` target for composition and UI entry
- shared foundation/domain module(s) for models and pure logic
- platform module for HomeKit / WidgetKit / App Intents / StoreKit adapters
- feature modules for onboarding, homes, alarms, and automation

The exact Xcode layout may use local packages or grouped folders, but workers should preserve the same domain boundaries either way.

## Primary Data Flows

### 1. Onboarding and Home Readiness

1. User completes the three onboarding screens.
2. App requests Apple Home access.
3. App evaluates readiness in this order:
   - permission
   - available homes
   - home hub availability
   - compatible accessories
4. App routes to either:
   - a blocker state with retry/troubleshooting, or
   - the first usable setup screen.

### 2. Alarm Authoring

1. User selects home/accessories and configures the alarm.
2. Editor validates required inputs locally.
3. Preview requests a pure step plan from the planner.
4. Save writes app-owned metadata to SwiftData.
5. If the alarm is enabled, automation generation is invoked.

### 3. Automation Generation

1. Planner converts the alarm into ordered step targets.
2. Binding service compares intended state with any existing binding.
3. HomeKit action sets and timer triggers are created, reused, or replaced.
4. Durable mappings between app alarm IDs and HomeKit IDs are persisted.
5. If any HomeKit write fails, partial objects are rolled back or the alarm is moved into a recoverable needs-attention state.

### 4. Validation and Repair

1. Consistency checks compare stored metadata/bindings with current HomeKit state.
2. Drift is classified into user-visible validation states.
3. Repair rebuilds or reconnects only the pieces that need attention where possible.
4. Repair completion updates the persisted binding and validation state.

### 5. Widgets and App Intents

1. Widgets and intents resolve alarms from the same canonical app-owned store.
2. Control actions mutate canonical alarm state first.
3. Any required automation refresh is routed back through the same alarm/automation services used by the app.
4. Widgets and app UI converge through normal refresh/state propagation instead of parallel bespoke logic.

## Core Models

The mission requires models for:

- `HomeReference`
- `AccessoryReference`
- `WakeAlarm`
- `WakeAlarmSchedule`
- `WakeAlarmGradient`
- `WakeAlarmStepPlan`
- `AutomationBinding`
- `ValidationState`

Domain models should stay independent from SwiftData-specific persistence types. Repositories map between persisted records and domain models.

## HomeKit Strategy

DawnLoop does **not** rely on foreground timers for alarm execution.

The supported strategy is:

1. build a deterministic stepped sunrise plan
2. generate HomeKit action sets + timer triggers
3. persist a durable binding between each DawnLoop alarm and created HomeKit objects
4. repair or clean up when the Home graph changes

This favors fewer, safer automation steps over fragile complexity.

Practical planning guidance:

- step count must be configurable in code
- safe means the plan is coarse enough to keep HomeKit object count manageable and reliable during create/edit/delete/repair
- edit flows should avoid duplicate or conflicting automations even if the underlying implementation chooses reuse, replace, or mixed diff behavior

## Capability Model

Accessory behavior is characteristic-driven rather than category-label driven:

- brightness-only
- brightness + color temperature
- brightness + hue/saturation
- outlet / power-only
- window covering only if the shipped workflow gives it a clear wake-routine meaning; otherwise filter it out cleanly

Mixed-capability selections should degrade gracefully rather than failing the whole alarm when a subset can only support brightness behavior.

## Source of Truth and Invariants

Workers should preserve these invariants:

1. **Canonical alarm truth lives in app-owned persistence.**
2. **HomeKit IDs are treated as bindings, not as the only source of alarm data.**
3. **Views do not own business logic.**
4. **HomeKit access stays behind protocols so tests can use mocks.**
5. **Any enabled alarm must have either a healthy binding or a visible repair-needed state.**
6. **Create/edit/delete flows must avoid orphaned HomeKit objects whenever possible.**
7. **Widgets and intents must operate on the same canonical alarm entities as the main app.**
8. **Billing remains isolated behind feature flags and interfaces.**

## Validation-State Vocabulary

Workers should converge on a small shared vocabulary for user-visible sync health:

- `healthy`
- `needsAttention`
- `repairing`
- `blocked`

Specific UI labels can vary, but these concepts should stay consistent across list, detail, widget, and intent surfaces.

## Validation Notes

- Simulator-first: UI rendering, navigation, view models, repositories, planner logic, mocked HomeKit states
- Real-device-only: Home permission prompts, live Home discovery, home-hub readiness, HomeKit automation behavior, widget interaction fidelity, Siri / Shortcuts behavior
- Features should keep mockable seams even when the milestone also requires real-device proof later

## Observability

Structured logging is required around:

- automation planning inputs/outputs
- binding creation/update/delete
- rollback paths
- consistency checks
- repair actions

Logs are diagnostic only; user-facing states must remain plain-language.
