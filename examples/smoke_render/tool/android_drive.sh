#!/usr/bin/env bash
# Drives the prebuilt smoke APK on the running emulator and collects frames.
#
#   tool/android_drive.sh <backend> <apk>
#
# The APK is built before the emulator boots, so the time caps here cover only
# the tests. Each scene's PNG is written on the device as it renders and pulled
# after every attempt, so a run that dies late keeps what it drew. An attempt
# that stops making progress is cut short, the adb transport is reconnected,
# and the retry skips scenes that already passed (the test checks the markers
# it left on the device, since the app stays installed between attempts).
set -u

backend=$1
apk=$2
pkg=dev.bdero.smoke_render
attempt_cap_s=1200
stall_cap_s=300

cd "$(dirname "$0")/.."
diag=build/android-diagnostics
mkdir -p "$diag" build/smoke

adb shell getprop ro.hardware.vulkan || true
adb shell getprop ro.opengles.version || true
adb shell svc power stayon true
adb shell wm dismiss-keyguard || true
adb devices -l > "$diag/adb_devices_before_$backend.txt" 2>&1 || true
adb shell getprop > "$diag/getprop_$backend.txt" 2>&1 || true
adb shell dumpsys SurfaceFlinger > "$diag/surfaceflinger_$backend.txt" 2>&1 || true

# Host pressure and process evidence, for when SwiftShader or the emulator is
# terminated without an Android crash report.
(
  while true; do
    date -u +%FT%TZ
    free -m
    cat /proc/pressure/memory
    cat /proc/pressure/cpu 2>/dev/null || true
    ps -eo pid,ppid,rss,vsz,%mem,%cpu,stat,comm,args --sort=-rss | head -n 20
    sleep 2
  done
) > "$diag/host_resources_$backend.txt" 2>&1 &
monitor_pid=$!

# A large ring buffer instead of a live stream, so diagnostics add no steady
# traffic to the adb transport; it is dumped once at the end.
adb logcat -G 16M || true
adb logcat -c || true

pull_captures() {
  adb exec-out run-as "$pkg" sh -c 'cd files/smoke 2>/dev/null && tar cf - *.png' 2>/dev/null |
    tar xf - -C build/smoke 2>/dev/null || true
  echo "Pulled captures: $(find build/smoke -maxdepth 1 -name '*.png' | wc -l) PNGs on the host."
}

# Runs one attempt with a hard cap and a no-progress watchdog. A test finishing
# or a scene logging its SMOKE line counts as progress.
drive() {
  local attempt=$1
  local log="$diag/drive_${backend}_attempt$attempt.txt"
  : > "$log"
  timeout "$attempt_cap_s" flutter drive \
    --driver=test_driver/integration_test.dart \
    --target=integration_test/smoke_test.dart \
    --use-application-binary="$apk" \
    --keep-app-running \
    -d emulator-5554 \
    --enable-impeller \
    --enable-flutter-gpu \
    > "$log" 2>&1 &
  local pid=$!
  # Echo through a file, not a pipe. `--keep-app-running` leaves the
  # development service and its logcat follower alive after the drive exits,
  # and a pipe they inherited would hold this step open until the job timeout.
  tail -n +1 -f "$log" &
  local tail_pid=$!
  local seen=0 last now count
  last=$(date +%s)
  while kill -0 "$pid" 2>/dev/null; do
    sleep 10
    count=$(grep -cE ' \+[0-9]+( -[0-9]+)?: |SMOKE ' "$log" || true)
    now=$(date +%s)
    if [ "$count" -gt "$seen" ]; then
      seen=$count
      last=$now
    elif [ $((now - last)) -ge "$stall_cap_s" ]; then
      echo "No test progress for ${stall_cap_s}s; stopping attempt $attempt."
      kill "$pid" 2>/dev/null || true
      break
    fi
  done
  wait "$pid"
  local code=$?
  sleep 1
  kill "$tail_pid" 2>/dev/null || true
  pull_captures
  return "$code"
}

drive 1
code=$?
if [ "$code" -ne 0 ]; then
  echo "Attempt 1 failed (status $code); reconnecting adb and retrying the scenes that have not passed."
  adb reconnect offline || true
  adb kill-server || true
  adb start-server || true
  if timeout 60 adb wait-for-device && [ "$(adb get-state 2>/dev/null)" = "device" ]; then
    # Stop the app left running so the retry launches it fresh.
    adb shell am force-stop "$pkg" || true
    drive 2
    code=$?
  else
    echo "The emulator did not reconnect within 60 seconds; skipping the retry."
  fi
fi

adb logcat -d -v time > "$diag/logcat_$backend.txt" 2>&1 || true
adb devices -l > "$diag/adb_devices_after_$backend.txt" 2>&1 || true
sudo -n dmesg -T > "$diag/host_dmesg_$backend.txt" 2>&1 || true
cat /proc/meminfo > "$diag/host_meminfo_after_$backend.txt" 2>&1 || true
kill "$monitor_pid" 2>/dev/null || true
exit "$code"
