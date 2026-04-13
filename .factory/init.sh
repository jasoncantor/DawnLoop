#!/bin/sh
set -eu

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild is required for DawnLoop workers."
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun is required for DawnLoop workers."
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required to resolve the simulator destination."
  exit 1
fi

python3 .factory/resolve_simulator_udid.py >/dev/null

if [ -d "DawnLoop.xcworkspace" ]; then
  xcodebuild -workspace DawnLoop.xcworkspace -scheme DawnLoop -resolvePackageDependencies >/dev/null
elif [ -d "DawnLoop.xcodeproj" ]; then
  xcodebuild -project DawnLoop.xcodeproj -resolvePackageDependencies >/dev/null
else
  echo "DawnLoop bootstrap feature has not created the Xcode project yet."
fi
