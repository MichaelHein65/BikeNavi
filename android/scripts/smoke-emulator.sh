#!/usr/bin/env bash
set -euo pipefail

adb install -r artifacts/app-debug.apk
adb shell pm grant de.michaelhein.bikenavi android.permission.ACCESS_FINE_LOCATION
adb shell pm grant de.michaelhein.bikenavi android.permission.POST_NOTIFICATIONS
adb shell am start -n de.michaelhein.bikenavi/.MainActivity
sleep 8
adb exec-out screencap -p > artifacts/android-home.png || true
app_pid="$(adb shell pidof de.michaelhein.bikenavi | tr -d '\r')"
if [[ -z "$app_pid" ]]; then
  adb logcat -d -s AndroidRuntime:E ActivityTaskManager:E | tail -180
  exit 1
fi
adb shell uiautomator dump /sdcard/bikenavi-window.xml
adb shell cat /sdcard/bikenavi-window.xml | grep -Eq 'text="(Route|ROUTE)"'
