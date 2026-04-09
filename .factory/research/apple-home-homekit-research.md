# Apple Home / HomeKit Research Notes

Date: 2026-04-09

## Recommended Public APIs

- `HMHomeManager` for authorization and home enumeration
- `HMHome` for selected-home context, accessories, triggers, action sets, and hub state
- `HMAccessory`, `HMService`, and `HMCharacteristic` for capability discovery and writes
- `HMActionSet` and `HMCharacteristicWriteAction` for stored actions
- `HMTimerTrigger` for scheduled execution
- App Intents for Siri / Shortcuts integration
- WidgetKit for Home Screen and Lock Screen widget presentation

## Key Product Constraint

Public HomeKit APIs do not provide a generic native “sunrise ramp” primitive. The reliability-first path is to build a deterministic stepped plan and generate HomeKit action sets + timer triggers from that plan.

## Detectable States

Reliably detectable:

- Home access granted / denied / restricted
- no homes configured
- home hub availability state
- accessory reachability and characteristic support
- missing HomeKit bindings or drifted object identifiers

Partially inferable or limited:

- why a future automation might fail
- whether widget-triggered HomeKit mutations will be equally reliable across OS versions
- overall quality of a specific vendor accessory’s color behavior

## Architectural Implications

- Keep HomeKit behind protocols
- persist HomeKit UUIDs as bindings, not as the only source of truth
- namescape app-created HomeKit objects
- keep widget and App Intent actions as control surfaces, not the primary wake execution engine
