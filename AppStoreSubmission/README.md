# App Store Submission Assets

This folder contains the current DawnLoop App Store submission package.

## Screenshot sets

### iPhone 6.9-inch

- Display class: `iPhone 6.9-inch`
- Source simulator: `iPhone 17 Pro Max`
- Upload resolution: `1284 x 2778`
- Raw capture resolution: `1320 x 2868`
- Capture date: `2026-04-10`
- Appearance: `Light`
- Status bar: `9:41`, full battery, active signal

Named screenshots are in [Screenshots/iPhone-6.9](Screenshots/iPhone-6.9):

1. [01-welcome.png](Screenshots/iPhone-6.9/01-welcome.png)
2. [02-home-selection.png](Screenshots/iPhone-6.9/02-home-selection.png)
3. [03-light-selection.png](Screenshots/iPhone-6.9/03-light-selection.png)
4. [04-empty-alarm-list.png](Screenshots/iPhone-6.9/04-empty-alarm-list.png)
5. [05-alarm-editor.png](Screenshots/iPhone-6.9/05-alarm-editor.png)
6. [06-alarm-list-populated.png](Screenshots/iPhone-6.9/06-alarm-list-populated.png)
7. [07-repair-needed.png](Screenshots/iPhone-6.9/07-repair-needed.png)

The original simulator-native PNGs are preserved in [Screenshots/iPhone-6.9/Raw-1320x2868](Screenshots/iPhone-6.9/Raw-1320x2868).

### iPad 13-inch

- Display class: `iPad 13-inch`
- Source simulator: `iPad Pro 13-inch (M5)`
- Upload resolution: `2064 x 2752`
- Raw capture resolution: `2064 x 2752`
- Capture date: `2026-04-12`
- Appearance: `Light`
- Status bar: `9:41`, full battery, active signal

Named screenshots are in [Screenshots/iPad-13](Screenshots/iPad-13):

1. [01-welcome.png](Screenshots/iPad-13/01-welcome.png)
2. [02-home-selection.png](Screenshots/iPad-13/02-home-selection.png)
3. [03-light-selection.png](Screenshots/iPad-13/03-light-selection.png)
4. [04-empty-alarm-list.png](Screenshots/iPad-13/04-empty-alarm-list.png)
5. [05-alarm-editor.png](Screenshots/iPad-13/05-alarm-editor.png)
6. [06-alarm-list-populated.png](Screenshots/iPad-13/06-alarm-list-populated.png)
7. [07-repair-needed.png](Screenshots/iPad-13/07-repair-needed.png)

The simulator-native PNGs are preserved in [Screenshots/iPad-13/Raw-2064x2752](Screenshots/iPad-13/Raw-2064x2752).

The raw UI test result bundle for the iPad capture is stored at [ScreenshotCapture-iPad13.xcresult](ScreenshotCapture-iPad13.xcresult).

The raw UI test result bundle is stored at [ScreenshotCapture.xcresult](ScreenshotCapture.xcresult).

## How the screenshots were generated

The screenshots were captured by the UITest class [AppStoreScreenshotTests.swift](../DawnLoopUITests/AppStoreScreenshotTests.swift). The test uses DawnLoop's seeded home and seeded repair state, so the images are repeatable and do not depend on live HomeKit accessories.

To regenerate the iPhone 6.9-inch set (from the repository root; resolves an available iPhone simulator UDID):

```sh
SIM_UDID="$(python3 .factory/resolve_simulator_udid.py)"
xcrun simctl boot "$SIM_UDID"
xcrun simctl bootstatus "$SIM_UDID" -b
xcrun simctl status_bar "$SIM_UDID" override --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularMode active --cellularBars 4
xcrun simctl ui "$SIM_UDID" appearance light
xcodebuild -project DawnLoop.xcodeproj -scheme DawnLoop -destination "platform=iOS Simulator,id=${SIM_UDID}" -parallel-testing-enabled NO -only-testing:DawnLoopUITests/AppStoreScreenshotTests -derivedDataPath .derivedData-screenshots -resultBundlePath AppStoreSubmission/ScreenshotCapture.xcresult test
xcrun xcresulttool export attachments --path AppStoreSubmission/ScreenshotCapture.xcresult --output-path AppStoreSubmission/Screenshots/iPhone-6.9
```

To regenerate the 13-inch iPad set:

```sh
SIM_UDID="4983E388-A09C-4420-BF20-499A20B60398"
xcrun simctl boot "$SIM_UDID"
xcrun simctl bootstatus "$SIM_UDID" -b
xcrun simctl status_bar "$SIM_UDID" override --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3
xcrun simctl ui "$SIM_UDID" appearance light
xcodebuild -project DawnLoop.xcodeproj -scheme DawnLoop -destination "platform=iOS Simulator,id=${SIM_UDID}" -derivedDataPath .derivedData-screenshots-ipad test-without-building -parallel-testing-enabled NO -only-testing:DawnLoopUITests/AppStoreScreenshotTests -resultBundlePath AppStoreSubmission/ScreenshotCapture-iPad13.xcresult
xcrun xcresulttool export attachments --path AppStoreSubmission/ScreenshotCapture-iPad13.xcresult --output-path AppStoreSubmission/Screenshots/iPad-13
```

## Metadata

Use [APP_STORE_METADATA.md](../APP_STORE_METADATA.md) for the App Store Connect copy, review notes, keywords, and screenshot upload order.
