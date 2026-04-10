# AGENTS.md

## Cursor Cloud specific instructions

### Project overview

DawnLoop is an iPhone-first SwiftUI app (iOS 17+) that turns Apple Home accessories into sunrise alarm clocks via HomeKit. There are zero third-party dependencies, zero backend services, and zero databases to provision externally—everything is on-device via SwiftData.

### Environment limitations

This is a **native iOS/Xcode project**. The full build (`xcodebuild`), unit tests (`DawnLoopTests`), and UI tests (`DawnLoopUITests`) **require macOS + Xcode 26.3 + iOS Simulator**. These cannot run on the Linux Cloud Agent VM.

What **can** run on the Cloud Agent VM:

- **Linting** via `swift-format` (installed via `swiftly` — see update script)
- **SPM build** of the `DawnLoopApp` local package target (`cd DawnLoopApp && swift build`) — this compiles `Sources/DawnLoopApp/DawnLoopApp.swift` only, not the full Xcode app target
- General code editing, review, and static analysis

### Commands

All canonical commands are in `.factory/services.yaml`. On Linux, only linting is feasible:

| Task | Command (Linux) | Notes |
|------|-----------------|-------|
| Lint | `swift-format lint -r DawnLoopApp DawnLoopTests DawnLoopUITests` | Warnings only (style); exit code 13 = findings, 0 = clean |
| SPM build | `cd DawnLoopApp && swift build` | Compiles the SPM executable target only |
| Full build | N/A (requires macOS) | See `.factory/services.yaml` `build` command |
| Tests | N/A (requires macOS) | See `.factory/services.yaml` `test` command |

### Gotchas

- The `Packages`, `DawnLoopWidgetExtension`, and `DawnLoopIntentsExtension` directories referenced in the lint command in `.factory/services.yaml` do not exist yet (planned for future milestones). `swift-format lint` silently skips missing directories.
- The `.swift-version` file at the repo root is managed by `swiftly` and set to `6.3.0`.
- The `DawnLoopApp/Package.swift` defines a minimal SPM executable target (`Sources/DawnLoopApp/DawnLoopApp.swift`). The real app is built via `DawnLoop.xcodeproj` using `xcodebuild`.
- Swift source files use 2-space indentation (Xcode style), which `swift-format` flags as warnings with its default 4-space config. This is expected project style.
