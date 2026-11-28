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
#
# Captures are pulled in short tar streams and checked against the device's
# listing, each by size and a final IEND chunk. A cut-off file is deleted and
# whatever is missing is pulled again, so a truncated PNG never reaches Argos.
# A set still incomplete after the last try fails the run and is held back
# from Argos. SMOKE_PULL_DEADLINE_S overrides the per-try transfer deadline.
set -u

backend=$1
apk=$2
pkg=dev.bdero.smoke_render
attempt_cap_s=1200
stall_cap_s=300
poll_s=10
pull_tries=4

cd "$(dirname "$0")/.."
diag=build/android-diagnostics
mkdir -p "$diag" build/smoke

# A wedged transport can hang adb indefinitely, so calls get a deadline.
adbt() { timeout 30 adb "$@"; }

# Brings back a device adb dropped, waiting up to a minute for it.
reconnect() {
  adb reconnect offline > /dev/null 2>&1 || true
  timeout 60 adb wait-for-device || true
}

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

# The device's captures as "<name> <bytes>" lines. Fails when adb does not
# answer.
device_captures() {
  local out
  out=$(adbt exec-out run-as "$pkg" sh -c 'cd files/smoke 2>/dev/null && stat -c "%n %s" *.png 2>/dev/null; echo ---') || return 1
  case $out in *---) printf '%s' "${out%---}" ;; *) return 1 ;; esac
}

# Whether $1 holds exactly $2 bytes and ends in a PNG's IEND chunk.
png_complete() {
  [ -f "$1" ] && [ "$(($(wc -c < "$1")))" -eq "$2" ] &&
    [ "$(tail -c 12 "$1" | od -An -tx1 | tr -d ' \n')" = 0000000049454e44ae426082 ]
}

pull_log=$diag/capture_pull_$backend.txt
pull_missing=
# Copies the device's captures into build/smoke. A stream can end early or
# stall, so each try fetches what this pull has not verified yet into a staging
# directory, with 30s plus 1s per 64 KiB to finish, and moves over only files
# that pass png_complete. A cut-off file is deleted with the staging directory.
# Fails when the set is still incomplete after the last try, naming the missing
# scenes in pull_missing (left empty when adb never listed the captures).
pull_captures() {
  local try out listing='' listed=0 want names total name size deadline status
  local left cut why verified=' ' stage=build/smoke-pull
  pull_missing=
  for try in $(seq "$pull_tries"); do
    if [ "$try" -gt 1 ]; then
      sleep 2
      reconnect
    fi
    if ! out=$(device_captures); then
      echo "Capture pull $try of $pull_tries got no listing from adb."
      continue
    fi
    listing=$out
    listed=1
    want='' names='' total=0
    while read -r name size; do
      [ -n "$name" ] || continue
      case $verified in *" $name "*) continue ;; esac
      want+="$name $size"$'\n'
      names+=" $name"
      total=$((total + size))
    done <<< "$listing"
    if [ -n "$names" ]; then
      deadline=${SMOKE_PULL_DEADLINE_S:-$((30 + total / 65536))}
      rm -rf "$stage" && mkdir -p "$stage"
      timeout "$deadline" adb exec-out run-as "$pkg" sh -c "cd files/smoke && tar cf -$names" 2> "$stage.log" |
        tar xf - -C "$stage" 2>> "$stage.log"
      status=("${PIPESTATUS[@]}")
      left=0 cut=''
      while read -r name size; do
        [ -n "$name" ] || continue
        if png_complete "$stage/$name" "$size"; then
          mv -f "$stage/$name" build/smoke/
          verified+="$name "
        else
          left=$((left + 1))
          [ -e "$stage/$name" ] && cut+=" $name"
        fi
      done <<< "$want"
      { echo "Try $try, ${deadline}s deadline, exits ${status[*]}, fetching$names"; cat "$stage.log"; } >> "$pull_log"
      if [ "$left" -gt 0 ]; then
        case ${status[0]} in
          124) why="stopped at the ${deadline}s deadline" ;;
          *) why="adb exited ${status[0]}, tar ${status[1]}" ;;
        esac
        echo "Capture pull $try of $pull_tries left $left PNGs missing or cut off ($why)."
        [ -z "$cut" ] || echo "  Deleted the cut-off$cut."
        sed 's/^/  /' "$stage.log"
      fi
      rm -rf "$stage" "$stage.log"
      [ "$left" -eq 0 ] || continue
    fi
    echo "Pulled all $(grep -c . <<< "$listing") captures, each matching the device."
    return 0
  done
  if [ "$listed" -eq 0 ]; then
    echo "adb never listed the captures, so the PNGs on the host are unverified."
    return 1
  fi
  while read -r name size; do
    [ -n "$name" ] || continue
    case $verified in *" $name "*) ;; *) pull_missing+=" ${name%.png}" ;; esac
  done <<< "$listing"
  echo "After $pull_tries tries these captures are still missing or cut off (${pull_missing# })."
  return 1
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
      reconnect
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
pulled=1
pull_captures || pulled=0

verdict=
for _ in 1 2 3; do
  verdict=$(adbt exec-out run-as "$pkg" cat files/smoke/summary 2> /dev/null || true)
  [ -n "$verdict" ] && break
  reconnect
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
if [ "$pulled" -eq 0 ]; then
  echo "The captures did not all reach the host intact, so the run fails."
  code=1
  # In Argos a known-partial set shows scenes as removed, or becomes a partial
  # master baseline, so it goes to the diagnostics instead.
  if [ -n "$pull_missing" ]; then
    mkdir -p "$diag/incomplete_captures"
    mv build/smoke/*.png "$diag/incomplete_captures/" 2> /dev/null || true
    echo "Held the partial set back from Argos, in $diag/incomplete_captures."
  fi
fi

adbt logcat -d -b crash -v time > "$diag/logcat_crash_$backend.txt" 2>&1 || true
adbt devices -l > "$diag/adb_devices_after_$backend.txt" 2>&1 || true
sudo -n dmesg -T > "$diag/host_dmesg_$backend.txt" 2>&1 || true
cat /proc/meminfo > "$diag/host_meminfo_after_$backend.txt" 2>&1 || true
kill "$monitor_pid" 2>/dev/null || true
exit "$code"
