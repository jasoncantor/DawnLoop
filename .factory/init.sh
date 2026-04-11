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

python3 <<'PY' >/dev/null
import json
import subprocess
import sys

devices = json.loads(
    subprocess.check_output(["xcrun", "simctl", "list", "--json", "devices", "available"], text=True)
)["devices"]

for entries in devices.values():
    for entry in entries:
        if entry.get("isAvailable") and entry.get("name", "").startswith("iPhone"):
            raise SystemExit(0)

sys.exit("No available iPhone simulators found for DawnLoop validation.")
PY

if [ -d "DawnLoop.xcworkspace" ]; then
  xcodebuild -workspace DawnLoop.xcworkspace -scheme DawnLoop -resolvePackageDependencies >/dev/null
elif [ -d "DawnLoop.xcodeproj" ]; then
  xcodebuild -project DawnLoop.xcodeproj -resolvePackageDependencies >/dev/null
else
  echo "DawnLoop bootstrap feature has not created the Xcode project yet."
fi
