#!/usr/bin/env python3
import json
import re
import subprocess
import sys

devices = json.loads(
    subprocess.check_output(
        ["xcrun", "simctl", "list", "--json", "devices", "available"], text=True
    )
)["devices"]
candidates = []
for runtime, entries in devices.items():
    if "iOS" not in runtime:
        continue
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    version = (int(match.group(1)), int(match.group(2))) if match else (0, 0)
    for entry in entries:
        if entry.get("isAvailable") and entry.get("name", "").startswith("iPhone"):
            candidates.append((version, entry["udid"]))
if not candidates:
    sys.exit("No available iPhone simulators found.")
candidates.sort(reverse=True)
print(candidates[0][1])
