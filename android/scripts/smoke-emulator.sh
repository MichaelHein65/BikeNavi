#!/usr/bin/env bash
set -euo pipefail

adb install -r artifacts/app-debug.apk
adb shell pm grant de.michaelhein.bikenavi android.permission.ACCESS_FINE_LOCATION
adb shell pm grant de.michaelhein.bikenavi android.permission.POST_NOTIFICATIONS
adb shell am start -n de.michaelhein.bikenavi/.MainActivity
sleep 20
adb exec-out screencap -p > artifacts/android-home.png || true
app_pid="$(adb shell pidof de.michaelhein.bikenavi | tr -d '\r' || true)"
if [[ -z "$app_pid" ]]; then
  adb logcat -d -s AndroidRuntime:E ActivityTaskManager:E | tail -180
  exit 1
fi
adb shell uiautomator dump /sdcard/bikenavi-window.xml
adb shell cat /sdcard/bikenavi-window.xml > artifacts/android-window.xml
grep -Eq 'text="(Route|ROUTE)"' artifacts/android-window.xml
read -r tap_x tap_y < <(python3 - artifacts/android-window.xml <<'PY'
import re
import sys

xml = open(sys.argv[1], encoding="utf-8").read()
match = re.search(r'text="(?:Mehr|MEHR)"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', xml)
if not match:
    raise SystemExit("Mehr-Schaltfläche nicht sichtbar")
x1, y1, x2, y2 = map(int, match.groups())
print((x1 + x2) // 2, (y1 + y2) // 2)
PY
)
adb shell input tap "$tap_x" "$tap_y"
adb shell uiautomator dump /sdcard/bikenavi-menu.xml
adb shell cat /sdcard/bikenavi-menu.xml | grep -q 'text="Bike-Verbindung"'
