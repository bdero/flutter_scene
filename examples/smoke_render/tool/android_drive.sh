#!/usr/bin/env bash
# Runs the prebuilt smoke APK on the running emulator and collects frames.
#
#   tool/android_drive.sh <backend> <apk>
#
# The app is launched directly and runs the suite on its own, writing each
# scene's PNG, a count of finished tests, and finally the suite's verdict to its
# files directory. This script polls them with short adb commands. No
# connection to the app stays open, so a dropped VM service or adb transport,
# which used to fail runs whose tests had all passed, only delays a poll. An
# attempt that stops making progress or loses the app is retried once, skipping
# the scenes that already passed. The app's verdict decides the result, and a
# run that never reports one fails.
set -u

backend=$1
apk=$2
pkg=dev.bdero.smoke_render
attempt_cap_s=1200
stall_cap_s=300
poll_s=10

cd "$(dirname "$0")/.."
diag=build/android-diagnostics
mkdir -p "$diag" build/smoke

# A wedged transport can hang adb indefinitely, so calls get a deadline.
adbt() { timeout 30 adb "$@"; }

adbt shell getprop ro.hardware.vulkan || true
adbt shell getprop ro.opengles.version || true
adbt shell svc power stayon true || true
adbt shell wm dismiss-keyguard || true
adbt devices -l > "$diag/adb_devices_before_$backend.txt" 2>&1 || true
adbt shell getprop > "$diag/getprop_$backend.txt" 2>&1 || true
adbt shell dumpsys SurfaceFlinger > "$diag/surfaceflinger_$backend.txt" 2>&1 || true

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

log_tags=(
  flutter:V AndroidRuntime:V DEBUG:V libc:V tombstoned:V
  ActivityManager:I ActivityTaskManager:I lowmemorykiller:V Zygote:W
  EGL_emulation:W OpenGLRenderer:W vulkan:W goldfish_vulkan:W '*:S'
)
# The log is dumped on every poll rather than streamed, since a stream holds an
# adb connection open for the whole run. The larger ring buffer keeps all of it.
adbt logcat -G 16M || true
adbt logcat -c || true
device_log="$diag/logcat_$backend.txt"
: > "$device_log"
printed=0
# Refreshes the log and echoes the app's new lines into the step output.
print_new_log() {
  local total
  adbt logcat -d -v time "${log_tags[@]}" > "$device_log.tmp" 2>/dev/null &&
    mv "$device_log.tmp" "$device_log"
  total=$(($(wc -l < "$device_log")))
  [ "$total" -gt "$printed" ] || return 0
  sed -n "$((printed + 1)),${total}p" "$device_log" |
    grep -E '/(flutter|AndroidRuntime|DEBUG)|F/libc' || true
  printed=$total
}

pull_captures() {
  adbt exec-out run-as "$pkg" sh -c 'cd files/smoke 2>/dev/null && tar cf - *.png' 2>/dev/null |
    tar xf - -C build/smoke 2>/dev/null || true
  echo "Pulled captures: $(find build/smoke -maxdepth 1 -name '*.png' | wc -l) PNGs on the host."
}

# The app's pid, then its files directory and finished-test count. Fails when
# adb does not answer.
probe() {
  local out
  out=$(adbt exec-out "pidof $pkg; echo ---; run-as $pkg sh -c 'cd files/smoke 2>/dev/null && ls -1; cat progress 2>/dev/null'") || return 1
  case $out in *---*) printf '%s' "$out" ;; *) return 1 ;; esac
}

# Runs the suite until the app writes its verdict. Fails on a stall, a lost
# app, or the cap.
run_attempt() {
  local attempt=$1 start last now state pid listing prev='' gone=0
  echo "Attempt $attempt: launching the app."
  adbt shell am force-stop "$pkg" || true
  adbt shell run-as "$pkg" rm -f files/smoke/summary files/smoke/progress || true
  adbt shell am start -W -n "$pkg/.MainActivity" || return 1
  start=$(date +%s)
  last=$start
  while true; do
    sleep "$poll_s"
    now=$(date +%s)
    print_new_log
    if state=$(probe); then
      pid=${state%%---*}
      listing=${state#*---}
      if grep -qx summary <<< "$listing"; then return 0; fi
      if [ -n "${pid//[[:space:]]/}" ]; then
        gone=0
      else
        # Confirmed on a second poll before the attempt is given up.
        gone=$((gone + 1))
        if [ "$gone" -ge 2 ]; then
          echo "The app is no longer running."
          return 1
        fi
      fi
      if [ "$listing" != "$prev" ]; then
        prev=$listing
        last=$now
      fi
    else
      echo "adb did not answer; reconnecting."
      adb reconnect offline > /dev/null 2>&1 || true
      timeout 60 adb wait-for-device || true
    fi
    if [ $((now - last)) -ge "$stall_cap_s" ]; then
      echo "No progress for ${stall_cap_s}s; stopping attempt $attempt."
      return 1
    fi
    if [ $((now - start)) -ge "$attempt_cap_s" ]; then
      echo "Attempt $attempt reached the ${attempt_cap_s}s cap."
      return 1
    fi
  done
}

adbt uninstall "$pkg" > /dev/null 2>&1 || true
installed=0
for _ in 1 2 3; do
  if timeout 300 adb install -r -t "$apk"; then
    installed=1
    break
  fi
  sleep 5
done
if [ "$installed" -ne 1 ]; then
  echo "Could not install $apk."
fi

if [ "$installed" -eq 1 ] && ! run_attempt 1; then
  pull_captures
  echo "Attempt 1 ended without a verdict; restarting adb and retrying the scenes that have not passed."
  adb kill-server || true
  adb start-server || true
  if timeout 60 adb wait-for-device && [ "$(adb get-state 2>/dev/null)" = "device" ]; then
    run_attempt 2 || true
  else
    echo "The emulator did not reconnect within 60 seconds; skipping the retry."
  fi
fi
print_new_log
pull_captures

verdict=
for _ in 1 2 3; do
  verdict=$(adbt exec-out run-as "$pkg" cat files/smoke/summary 2> /dev/null || true)
  [ -n "$verdict" ] && break
  adb reconnect offline > /dev/null 2>&1 || true
  timeout 60 adb wait-for-device || true
done
printf '%s\n' "$verdict" > "$diag/summary_$backend.txt"
case $(head -n 1 <<< "$verdict") in
  passed)
    echo "All tests passed."
    code=0
    ;;
  failed)
    echo "Some tests failed."
    tail -n +2 <<< "$verdict"
    code=1
    ;;
  *)
    echo "The app never reported a verdict."
    code=1
    ;;
esac

adbt logcat -d -b crash -v time > "$diag/logcat_crash_$backend.txt" 2>&1 || true
adbt devices -l > "$diag/adb_devices_after_$backend.txt" 2>&1 || true
sudo -n dmesg -T > "$diag/host_dmesg_$backend.txt" 2>&1 || true
cat /proc/meminfo > "$diag/host_meminfo_after_$backend.txt" 2>&1 || true
kill "$monitor_pid" 2>/dev/null || true
exit "$code"
