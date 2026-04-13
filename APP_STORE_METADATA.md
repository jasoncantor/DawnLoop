# DawnLoop App Store Metadata

## App Store Connect fields

- App name: `DawnLoop`
- Subtitle: `Light Alarms for Apple Home`
- Primary category: `Utilities`
- Secondary category: none
- Age rating: `4+`

## Promotional text

Wake up gradually with Light Alarms that brighten your Apple Home lights before you need to be awake.

## Description

DawnLoop turns your Apple Home lights into reliable Light Alarms.

Choose a home, pick the lights you want to use, and create a gentle wake-up routine that brightens in steps before your target time. DawnLoop saves alarms locally on your device and creates the matching Apple Home automations for enabled alarms, so your schedule keeps running without keeping the app open.

Built for a focused 1.0 release, DawnLoop helps you:

- Create, edit, duplicate, enable, disable, and delete Light Alarms
- Use clock time, sunrise, or sunset with offsets
- See the next run time and current sync health for each alarm
- Detect broken or drifted HomeKit bindings
- Repair missing or out-of-sync automations without rebuilding everything by hand

DawnLoop does not require an account and does not sync your data to a backend. HomeKit access is used only to discover your homes and lights, and to create, update, repair, or remove automations on your device.

For reliable scheduled execution, Apple Home must already be configured with a Home Hub and compatible lights.

## Keywords

`light alarm,homekit,apple home,sunrise,sunset,wake up,smart lights,automation`

## What's New in Version 1.0

First release of DawnLoop with onboarding, Light Alarm creation, local persistence, HomeKit automation sync, drift detection, and repair tools.

## URLs to provide in App Store Connect

- Support URL: replace with your real support page or contact page
- Marketing URL: optional for 1.0
- Privacy Policy URL: `https://github.com/jasoncantor/DawnLoop/blob/main/PRIVACY_POLICY.md`

## App Review notes

- DawnLoop does not require account creation or login.
- Core functionality requires Apple Home to be configured on the review device with at least one compatible dimmable light.
- For reliable scheduled execution, the configured home should also have a Home Hub such as Apple TV or HomePod.
- DawnLoop requests HomeKit access only to read the user’s homes and selected lights, then create, update, repair, or remove Apple Home automations on-device.
- DawnLoop optionally requests When In Use location access only to preview sunrise- and sunset-based next-run times inside the app. Solar HomeKit automations can still be created without granting location.
- If HomeKit is unavailable or not configured, the app will stop in the onboarding/home-access flow rather than presenting the main alarm list.

## Privacy disclosure notes

- Data linked to the user: none in app v1
- Data used for tracking: none
- HomeKit data usage: homes, accessories, and automation objects are used only for in-app setup and automation management
- Location usage: optional, on-device only, for sunrise/sunset preview and next-run estimation

## Screenshot upload plan

Upload the following files from [AppStoreSubmission/Screenshots/iPhone-6.9](AppStoreSubmission/Screenshots/iPhone-6.9) for the iPhone 6.9-inch display class, and the matching files from [AppStoreSubmission/Screenshots/iPad-13](AppStoreSubmission/Screenshots/iPad-13) for the 13-inch iPad display class, in this order:

1. `01-welcome.png`
   Caption concept: `Gentle Light Alarms for calmer mornings`
2. `02-home-selection.png`
   Caption concept: `Choose the Apple Home you want DawnLoop to manage`
3. `03-light-selection.png`
   Caption concept: `Pick the lights that should brighten before wake-up`
4. `04-empty-alarm-list.png`
   Caption concept: `Start clean and build your first routine in seconds`
5. `05-alarm-editor.png`
   Caption concept: `Fine-tune timing, repeat days, brightness, and steps`
6. `06-alarm-list-populated.png`
   Caption concept: `See your next run time and sync status at a glance`
7. `07-repair-needed.png`
   Caption concept: `Repair broken Home automations without starting over`

## Real-device validation before submission

- Confirm the intended Apple Home appears correctly on a real iPhone.
- Confirm compatible lights match the actual Home app configuration.
- Confirm enabled alarms create the expected scenes and triggers in Apple Home.
- Confirm disabling or deleting an alarm removes or disables the matching HomeKit automations.
- Confirm repair restores broken scenes or triggers without duplicating healthy bindings.
- Confirm sunrise and sunset alarms line up with expected local solar times on device.
