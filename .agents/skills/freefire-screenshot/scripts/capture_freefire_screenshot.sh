#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: capture_freefire_screenshot.sh [options]

Launch a connected Android Free Fire installation and save a PNG after the
selected package is foreground. The image still requires visual inspection.

Options:
  --variant <max|standard>  Which build to launch (default: max)
  --serial <serial>         ADB serial; required when multiple devices are online
  --out <path>              PNG output path (default: ./freefire-<variant>-<timestamp>.png)
  --timeout-seconds <n>     Foreground wait timeout (default: 60)
  --settle-seconds <n>      Wait after foreground detection (default: 8)
  --dry-run                 Print the resolved plan without launching or capturing
  --help                    Show this help
USAGE
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

variant='max'
requested_serial=''
output_path=''
timeout_seconds=60
settle_seconds=8
dry_run=0

while (($# > 0)); do
  case "$1" in
    --variant)
      (($# >= 2)) || die "--variant requires max or standard"
      variant="$2"
      shift 2
      ;;
    --serial)
      (($# >= 2)) || die "--serial requires a device serial"
      requested_serial="$2"
      shift 2
      ;;
    --out)
      (($# >= 2)) || die "--out requires a PNG path"
      output_path="$2"
      shift 2
      ;;
    --timeout-seconds)
      (($# >= 2)) || die "--timeout-seconds requires a positive integer"
      timeout_seconds="$2"
      shift 2
      ;;
    --settle-seconds)
      (($# >= 2)) || die "--settle-seconds requires a non-negative integer"
      settle_seconds="$2"
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

case "$variant" in
  max)
    package_name='com.dts.freefiremax'
    ;;
  standard|freefire)
    variant='standard'
    package_name='com.dts.freefireth'
    ;;
  *)
    die "unsupported variant '$variant'; use max or standard"
    ;;
esac

case "$timeout_seconds" in
  ''|*[!0-9]*) die '--timeout-seconds must be a positive integer' ;;
esac
((timeout_seconds > 0)) || die '--timeout-seconds must be greater than zero'

case "$settle_seconds" in
  ''|*[!0-9]*) die '--settle-seconds must be a non-negative integer' ;;
esac

adb_bin="${FF_ADB_BIN:-$(command -v adb || true)}"
[[ -n "$adb_bin" ]] || die 'adb was not found on PATH'

if [[ -z "$output_path" ]]; then
  timestamp="$(date '+%Y-%m-%dT%H-%M-%S%z')"
  output_path="${PWD}/freefire-${variant}-${timestamp}.png"
fi

if ((dry_run)); then
  printf 'variant=%s\n' "$variant"
  printf 'package=%s\n' "$package_name"
  printf 'adb=%s\n' "$adb_bin"
  printf 'serial=%s\n' "${requested_serial:-auto-select-one-online-device}"
  printf 'timeout_seconds=%s\n' "$timeout_seconds"
  printf 'settle_seconds=%s\n' "$settle_seconds"
  printf 'output=%s\n' "$output_path"
  printf 'mutation=launch-and-capture-only; no-login-input\n'
  exit 0
fi

serial="$requested_serial"
if [[ -n "$serial" ]]; then
  device_state="$("$adb_bin" -s "$serial" get-state 2>/dev/null | tr -d '\r\n' || true)"
  [[ "$device_state" == 'device' ]] || die "device '$serial' is not online in state device (state: ${device_state:-unavailable})"
else
  online_serials=()
  while IFS=$'\t' read -r candidate state _rest; do
    [[ -n "$candidate" ]] || continue
    [[ "$state" == 'device' ]] || continue
    online_serials+=("$candidate")
  done < <("$adb_bin" devices | tr -d '\r' | tail -n +2)

  case "${#online_serials[@]}" in
    0)
      die 'no online ADB device found; inspect adb devices for offline or unauthorized entries'
      ;;
    1)
      serial="${online_serials[0]}"
      ;;
    *)
      die 'multiple online ADB devices found; rerun with --serial <serial>'
      ;;
  esac
fi

installed_packages="$("$adb_bin" -s "$serial" shell pm list packages 2>/dev/null | tr -d '\r')"
printf '%s\n' "$installed_packages" | grep -Fxq "package:${package_name}" \
  || die "package ${package_name} is not installed on device ${serial}"

if ! "$adb_bin" -s "$serial" shell monkey -p "$package_name" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; then
  die "failed to launch ${package_name}"
fi

foreground_activity() {
  local activity
  activity="$("$adb_bin" -s "$serial" shell dumpsys activity activities 2>/dev/null \
    | tr -d '\r' \
    | sed -nE 's/.*topResumedActivity=.* u[0-9]+ ([^ ]+).*/\1/p' \
    | head -n 1)"
  if [[ -z "$activity" ]]; then
    activity="$("$adb_bin" -s "$serial" shell dumpsys window windows 2>/dev/null \
      | tr -d '\r' \
      | sed -nE 's/.*mCurrentFocus=Window\{[^ ]+ u[0-9]+ ([^}]+).*/\1/p' \
      | head -n 1)"
  fi
  printf '%s' "$activity"
}

deadline=$((SECONDS + timeout_seconds))
foreground=''
while ((SECONDS < deadline)); do
  foreground="$(foreground_activity)"
  if [[ "$foreground" == "${package_name}/"* ]]; then
    break
  fi
  sleep 1
done

[[ "$foreground" == "${package_name}/"* ]] \
  || die "${package_name} did not become foreground within ${timeout_seconds}s (last: ${foreground:-unknown})"

sleep "$settle_seconds"

mkdir -p "$(dirname "$output_path")"
if ! "$adb_bin" -s "$serial" exec-out screencap -p > "$output_path"; then
  die 'failed to capture screenshot'
fi

[[ -s "$output_path" ]] || die "screenshot is empty: $output_path"
file "$output_path" | grep -q 'PNG image data' \
  || die "screenshot is not a valid PNG: $output_path"

foreground="$(foreground_activity)"
[[ "$foreground" == "${package_name}/"* ]] \
  || die "foreground changed before handoff; refusing to call this an in-game capture (last: ${foreground:-unknown})"

printf 'variant=%s\n' "$variant"
printf 'package=%s\n' "$package_name"
printf 'serial=%s\n' "$serial"
printf 'foreground=%s\n' "$foreground"
printf 'screenshot=%s\n' "$output_path"
printf 'visual_check=required\n'
