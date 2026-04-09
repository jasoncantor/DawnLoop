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

if [ -d "DawnLoop.xcworkspace" ]; then
  xcodebuild -workspace DawnLoop.xcworkspace -scheme DawnLoop -resolvePackageDependencies >/dev/null
elif [ -d "DawnLoop.xcodeproj" ]; then
  xcodebuild -project DawnLoop.xcodeproj -resolvePackageDependencies >/dev/null
else
  echo "DawnLoop bootstrap feature has not created the Xcode project yet."
fi
