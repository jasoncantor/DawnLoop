# App Store Metadata Checklist

## Core metadata

- App name
- Subtitle
- Promotional text
- Description
- Keywords
- Support URL
- Marketing URL
- Privacy Policy URL

## Required product messaging

- Explain that DawnLoop creates Apple Home automations using selected lights.
- State that a Home Hub is required for reliable scheduled execution.
- Clarify that HomeKit access is used only to discover homes, accessories, and create automations on device.

## Privacy disclosures

- HomeKit usage
- Diagnostics or analytics, if later added
- No account creation or cloud sync in v1

## Screenshot plan

- Onboarding screen
- Home selection
- Light selection
- Empty alarm list
- Alarm editor
- Alarm list with healthy alarm
- Alarm list with repair-needed state

## Real-device validation checklist

- Verify the chosen home appears correctly.
- Verify compatible lights match actual Home app data.
- Verify the generated action sets and timer triggers appear in Apple Home.
- Verify turning an alarm off removes its HomeKit automations.
- Verify repairs restore missing triggers or scenes without duplicating healthy ones.
