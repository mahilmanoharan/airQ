#!/bin/zsh
# Runs everything the handoff notes ask for, from fresh scratch paths (no stale module caches):
#   scripts/verify.sh             both package suites + an app build
#   scripts/verify.sh --ui        ... and the UI tests
# Simulator: set SIM_UDID, or the first booted (else first available) iPhone is used.
set -euo pipefail
cd "$(dirname "$0")/.."

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

run_ui=false
[[ "${1:-}" == "--ui" ]] && run_ui=true

run_filtered() {
  local pattern=$1
  shift
  # A quiet command is valid. With pipefail, the producer's failure still reaches the caller.
  "$@" 2>&1 | { grep -E "$pattern" || [[ $? == 1 ]]; } || return $?
}

for package in AirQualityKit RespiratoryKit; do
  echo "== swift test: $package"
  (cd "$package" && run_filtered "warning:|error:|Test run with|✘" swift test --scratch-path "$scratch/$package")
done

# Prefer a booted simulator the scheme can build for, else the first supported iPhone.
supported=$(xcodebuild -project airQ.xcodeproj -scheme airQ -showdestinations 2>/dev/null \
  | grep "platform:iOS Simulator" | grep "name:iPhone" | grep -Eo 'id:[0-9A-F-]{36}' | cut -d: -f2 || true)
booted=$(xcrun simctl list devices booted | grep -Eo '[0-9A-F-]{36}' || true)
udid="${SIM_UDID:-}"
if [[ -z "$udid" ]]; then
  for id in ${(f)supported}; do
    if [[ -n "$booted" && "$booted" == *"$id"* ]]; then udid=$id; break; fi
  done
  [[ -n "$udid" ]] || udid=$(echo "$supported" | head -1)
fi
# Destination discovery can come back empty while Xcode is busy: fall back to any booted iPhone.
[[ -n "$udid" ]] || udid=$(echo "$booted" | head -1)
[[ -n "$udid" ]] || { echo "No supported iPhone simulator found; set SIM_UDID." >&2; exit 1; }
xcrun simctl boot "$udid" 2>/dev/null || true
echo "== app build (simulator $udid)"
run_filtered "warning:|error:|BUILD" xcodebuild build -project airQ.xcodeproj -scheme airQ -destination "id=$udid" \
  -derivedDataPath "$scratch/dd"

if $run_ui; then
  echo "== UI tests"
  test_status=0
  run_filtered "error:|TEST (SUCCEEDED|FAILED)|failed" xcodebuild test -project airQ.xcodeproj -scheme airQUITests \
    -destination "id=$udid" -derivedDataPath "$scratch/dd" || test_status=$?
  # xcodebuild shuts the simulator down when it finishes.
  xcrun simctl boot "$udid" 2>/dev/null || true
  exit "$test_status"
fi
