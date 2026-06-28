#!/usr/bin/env bash
#
# Record App Store preview videos for TraderSuite in every configured language
# and device size, offline and deterministic.
#
# Flow per language × device:
#   1. Create a throwaway simulator on a modern iOS runtime, clean status bar.
#   2. Run the PreviewVideoUITests flow (add a futures from search → size a
#      position → sweep risk levels) while screen-recording, bounded to the demo
#      via marker files → Previews/<lang>/<device>/preview.mov (raw capture).
#   3. Finalize into the App Store size with scripts/finalize_preview.swift
#      (AVFoundation — no ffmpeg): scale to 886×1920, speed up to ≤ AIM_SECONDS,
#      30 fps, H.264 → Previews/<lang>/<device>/preview-appstore.mp4.
#
# App Store Connect wants a precise preview size (886×1920 portrait) and 15–30 s
# length; the finalize step produces exactly that. Requires Xcode only.
#
# Usage:
#   scripts/record_preview.sh                      # all devices × both languages
#   scripts/record_preview.sh --devices iphone
#   scripts/record_preview.sh --langs ru
#   scripts/record_preview.sh --aim 24             # target transcode length (≤30)
#   scripts/record_preview.sh --size 886x1920      # output resolution
#
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT="TraderSuite.xcodeproj"
SCHEME="TraderSuite"
DERIVED=".build/dd-screenshots"
OUT="Previews"
TEST_ID="TraderSuiteUITests/PreviewVideoUITests/testRecordPreview"
SIM_PREFIX="TraderSuitePreview"
BUNDLE_ID="com.ilyakharabet.tradersuite"
AIM_SECONDS="26"      # target length of the App Store cut (must be ≤ 30)
OUT_W="886"           # App Store preview width
OUT_H="1920"          # App Store preview height

device_spec() {
  case "$1" in
    iphone) echo "iphone-6.9|com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max" ;;
    ipad)   echo "ipad-13|com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M4-8GB" ;;
    *)      echo "" ;;
  esac
}
lang_spec() {
  case "$1" in
    en) echo "en|US" ;;
    ru) echo "ru|RU" ;;
    *)  echo "" ;;
  esac
}

WANT_DEVICES=(iphone ipad)
WANT_LANGS=(en ru)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --devices) IFS=',' read -ra WANT_DEVICES <<< "$2"; shift 2 ;;
    --langs)   IFS=',' read -ra WANT_LANGS   <<< "$2"; shift 2 ;;
    --aim)     AIM_SECONDS="$2"; shift 2 ;;
    --size)    OUT_W="${2%x*}"; OUT_H="${2#*x}"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

RUNTIME="$(xcrun simctl list runtimes ios -j | python3 -c '
import json,sys
rts=[r for r in json.load(sys.stdin)["runtimes"] if r.get("isAvailable")]
def ver(r): return tuple(int(x) for x in r["version"].split("."))
rts=[r for r in rts if ver(r)>=(26,)]
if not rts: sys.exit("No installed iOS 26+ simulator runtime found")
print(sorted(rts,key=ver)[-1]["identifier"])
')"
echo "▶ Using runtime: $RUNTIME"

mkdir -p "$OUT"

created_sims=()
cleanup() {
  for udid in "${created_sims[@]:-}"; do
    [[ -z "$udid" ]] && continue
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
    xcrun simctl delete "$udid"   >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

# Build once; each combo reuses the products via test-without-building so the
# app launches promptly after recording starts (less dead air at the top).
echo "▶ Building for testing…"
xcodebuild build-for-testing \
  -project "$PROJECT" -scheme "$SCHEME" \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO >/dev/null

for dkey in "${WANT_DEVICES[@]}"; do
  spec="$(device_spec "$dkey")"
  [[ -z "$spec" ]] && { echo "Unknown device: $dkey" >&2; exit 2; }
  dlabel="${spec%%|*}"; dtype="${spec##*|}"

  simname="$SIM_PREFIX-$dkey"
  xcrun simctl delete "$simname" >/dev/null 2>&1 || true
  udid="$(xcrun simctl create "$simname" "$dtype" "$RUNTIME")"
  created_sims+=("$udid")
  echo "▶ [$dlabel] simulator $udid"
  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true

  for lkey in "${WANT_LANGS[@]}"; do
    lr="$(lang_spec "$lkey")"
    [[ -z "$lr" ]] && { echo "Unknown language: $lkey" >&2; exit 2; }
    lang="${lr%%|*}"; region="${lr##*|}"

    # Match the simulator's system UI language to the run, then clean status bar.
    xcrun simctl spawn "$udid" defaults write -g AppleLanguages -array "$lang" >/dev/null 2>&1 || true
    xcrun simctl spawn "$udid" defaults write -g AppleLocale "${lang}_${region}" >/dev/null 2>&1 || true
    xcrun simctl spawn "$udid" launchctl kickstart -k system/com.apple.SpringBoard >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
    xcrun simctl status_bar "$udid" override \
      --time "09:41" --batteryState charged --batteryLevel 100 \
      --cellularMode active --cellularBars 4 \
      --dataNetwork wifi --wifiMode active --wifiBars 3 \
      --operatorName "" >/dev/null 2>&1 || true

    dest="$OUT/$lkey/$dlabel"
    mkdir -p "$dest"
    raw="$dest/preview.mov"
    rm -f "$raw"

    echo "  • [$dlabel/$lkey] running demo…"
    # Run the UI test in the background; the app drops start/end marker files in
    # its container that we poll, so the recording is bounded to the demo (no
    # XCUITest launch/teardown springboard). The container UUID can change per
    # run and stale markers persist, so we re-resolve it each poll and require the
    # marker to be newer than this run.
    run_t0="$(date +%s)"
    xcodebuild test-without-building \
      -project "$PROJECT" -scheme "$SCHEME" \
      -destination "id=$udid" \
      -only-testing:"$TEST_ID" \
      -testLanguage "$lang" -testRegion "$region" \
      -derivedDataPath "$DERIVED" \
      CODE_SIGNING_ALLOWED=NO >/dev/null &
    xcpid=$!

    fresh() { # $1=marker name → true if it exists and is newer than run_t0
      local f="$appdir/Documents/uitest.$1"
      [[ -n "$appdir" && -f "$f" ]] || return 1
      local m; m="$(stat -f %m "$f" 2>/dev/null || echo 0)"
      (( m >= run_t0 ))
    }

    rec=""; appdir=""
    deadline=$((SECONDS + 240))
    while (( SECONDS < deadline )); do      # wait for fresh home (start marker)
      appdir="$(xcrun simctl get_app_container "$udid" "$BUNDLE_ID" data 2>/dev/null || true)"
      if fresh start; then
        xcrun simctl io "$udid" recordVideo --codec=h264 --force "$raw" >/dev/null 2>&1 &
        rec=$!; echo "    recording…"; break
      fi
      kill -0 "$xcpid" 2>/dev/null || break
      sleep 0.2
    done
    while (( SECONDS < deadline )); do      # stop when the calc is left (end marker)
      fresh end && break
      kill -0 "$xcpid" 2>/dev/null || break
      sleep 0.2
    done
    if [[ -n "$rec" ]]; then
      kill -INT "$rec" >/dev/null 2>&1 || true
      wait "$rec" 2>/dev/null || true
    fi

    if ! wait "$xcpid"; then
      echo "    ⚠ UI test reported a failure for [$dlabel/$lkey]." >&2
    fi
    [[ -f "$raw" ]] && echo "    raw video -> $raw" || echo "    ⚠ no video captured for [$dlabel/$lkey]." >&2

    # Finalize to the exact App Store preview size + length (AVFoundation, no
    # ffmpeg): scale to OUT_W×OUT_H, speed up to ≤ AIM_SECONDS, 30fps, H.264.
    if [[ -f "$raw" ]]; then
      final="$dest/preview-appstore.mp4"
      if swift scripts/finalize_preview.swift "$raw" "$final" "$OUT_W" "$OUT_H" "$AIM_SECONDS" 2>/dev/null; then
        echo "    App Store cut -> $final (${OUT_W}×${OUT_H})"
      else
        echo "    ⚠ finalize failed for [$dlabel/$lkey]; raw .mov kept." >&2
      fi
    fi

    xcrun simctl status_bar "$udid" clear >/dev/null 2>&1 || true
  done
done

echo "✅ Done. Preview videos in: $OUT/<lang>/<device>/"
