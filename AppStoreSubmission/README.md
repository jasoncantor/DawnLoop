# App Store Submission Assets

This folder contains the current DawnLoop App Store submission package.

## Screenshot set

- Display class: `iPhone 6.9-inch`
- Source simulator: `iPhone 17 Pro Max`
- Upload resolution: `1284 x 2778`
- Raw capture resolution: `1320 x 2868`
- Capture date: `2026-04-10`
- Appearance: `Light`
- Status bar: `9:41`, full battery, active signal

Named screenshots are in [/Users/jasoncantor/Downloads/DawnLoop/AppStoreSubmission/Screenshots/iPhone-6.9](/Users/jasoncantor/Downloads/DawnLoop/AppStoreSubmission/Screenshots/iPhone-6.9):

1. [01-welcome.png](/Users/jasoncantor/Downloads/DawnLoop/AppStoreSubmission/Screenshots/iPhone-6.9/01-welcome.png)
2. [02-home-selection.png](/Users/jasoncantor/Downloads/DawnLoop/AppStoreSubmission/Screenshots/iPhone-6.9/02-home-selection.png)
3. [03-light-selection.png](/Users/jasoncantor/Downloads/DawnLoop/AppStoreSubmission/Screenshots/iPhone-6.9/03-light-selection.png)
4. [04-empty-alarm-list.png](/Users/jasoncantor/Downloads/DawnLoop/AppStoreSubmission/Screenshots/iPhone-6.9/04-empty-alarm-list.png)
5. [05-alarm-editor.png](/Users/jasoncantor/Downloads/DawnLoop/AppStoreSubmission/Screenshots/iPhone-6.9/05-alarm-editor.png)
6. [06-alarm-list-populated.png](/Users/jasoncantor/Downloads/DawnLoop/AppStoreSubmission/Screenshots/iPhone-6.9/06-alarm-list-populated.png)
7. [07-repair-needed.png](/Users/jasoncantor/Downloads/DawnLoop/AppStoreSubmission/Screenshots/iPhone-6.9/07-repair-needed.png)

The original simulator-native PNGs are preserved in [/Users/jasoncantor/Downloads/DawnLoop/AppStoreSubmission/Screenshots/iPhone-6.9/Raw-1320x2868](/Users/jasoncantor/Downloads/DawnLoop/AppStoreSubmission/Screenshots/iPhone-6.9/Raw-1320x2868).

The raw UI test result bundle is stored at [/Users/jasoncantor/Downloads/DawnLoop/AppStoreSubmission/ScreenshotCapture.xcresult](/Users/jasoncantor/Downloads/DawnLoop/AppStoreSubmission/ScreenshotCapture.xcresult).

## How the screenshots were generated

The screenshots were captured by the UITest class [AppStoreScreenshotTests.swift](/Users/jasoncantor/Downloads/DawnLoop/DawnLoopUITests/AppStoreScreenshotTests.swift). The test uses DawnLoop's seeded home and seeded repair state, so the images are repeatable and do not depend on live HomeKit accessories.

To regenerate:

```sh
xcrun simctl boot 0F683F09-D2ED-4B5A-8A01-357E8DE94C54
xcrun simctl bootstatus 0F683F09-D2ED-4B5A-8A01-357E8DE94C54 -b
xcrun simctl status_bar 0F683F09-D2ED-4B5A-8A01-357E8DE94C54 override --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularMode active --cellularBars 4
xcrun simctl ui 0F683F09-D2ED-4B5A-8A01-357E8DE94C54 appearance light
xcodebuild -project DawnLoop.xcodeproj -scheme DawnLoop -destination 'platform=iOS Simulator,id=0F683F09-D2ED-4B5A-8A01-357E8DE94C54' -parallel-testing-enabled NO -only-testing:DawnLoopUITests/AppStoreScreenshotTests -derivedDataPath .derivedData-screenshots -resultBundlePath AppStoreSubmission/ScreenshotCapture.xcresult test
xcrun xcresulttool export attachments --path AppStoreSubmission/ScreenshotCapture.xcresult --output-path AppStoreSubmission/Screenshots/iPhone-6.9
```

## Metadata

Use [APP_STORE_METADATA.md](/Users/jasoncantor/Downloads/DawnLoop/APP_STORE_METADATA.md) for the App Store Connect copy, review notes, keywords, and screenshot upload order.
