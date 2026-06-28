#!/usr/bin/env bash
#
# Generate App Store screenshots for TraderSuite in every configured language and
# device size, fully offline and deterministic.
#
# How it works:
#   1. Creates a throwaway simulator of each device type on a modern iOS runtime.
#   2. Overrides its status bar to a clean 9:41 / full battery / full signal.
#   3. Runs the ScreenshotUITests UI test once per language (xcodebuild
#      -testLanguage/-testRegion), which launches the app with seeded demo data
#      and attaches one screenshot per screen to the test result.
#   4. Exports the attachments from the .xcresult and lays them out under
#      Screenshots/<lang>/<device>/NN_name.png — ready to upload to App Store
#      Connect (RU shows MOEX data, EN shows CME data).
#
# Requires: Xcode 16+ (xcresulttool export attachments), python3 (manifest parse).
# No Ruby / fastlane / third-party gems.
#
# Usage:
#   scripts/screenshots.sh                       # all devices, all languages
#   scripts/screenshots.sh --devices iphone      # one device class
#   scripts/screenshots.sh --langs ru            # one language
#   scripts/screenshots.sh --devices iphone --langs en
#
set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="TraderSuite.xcodeproj"
SCHEME="TraderSuite"
DERIVED=".build/dd-screenshots"
OUT="Screenshots"
TEST_ID="TraderSuiteUITests/ScreenshotUITests/testCaptureScreenshots"
SIM_PREFIX="TraderSuiteShots"

# Mappings via functions (portable to macOS's stock bash 3.2 — no `declare -A`).
# device key -> "label|simctl device type id"
device_spec() {
  case "$1" in
    iphone) echo "iphone-6.9|com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max" ;;
    ipad)   echo "ipad-13|com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M4-8GB" ;;
    *)      echo "" ;;
  esac
}
# language key -> "lang|region"
lang_spec() {
  case "$1" in
    en) echo "en|US" ;;
    ru) echo "ru|RU" ;;
    *)  echo "" ;;
  esac
}

WANT_DEVICES=(iphone ipad)
WANT_LANGS=(en ru)

# ---- args --------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --devices) IFS=',' read -ra WANT_DEVICES <<< "$2"; shift 2 ;;
    --langs)   IFS=',' read -ra WANT_LANGS   <<< "$2"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

# ---- pick newest installed iOS >= 26 runtime ---------------------------------
RUNTIME="$(xcrun simctl list runtimes ios -j | python3 -c '
import json,sys
rts=[r for r in json.load(sys.stdin)["runtimes"] if r.get("isAvailable")]
def ver(r):
    return tuple(int(x) for x in r["version"].split("."))
rts=[r for r in rts if ver(r)>=(26,)]
if not rts:
    sys.exit("No installed iOS 26+ simulator runtime found")
print(sorted(rts,key=ver)[-1]["identifier"])
')"
echo "▶ Using runtime: $RUNTIME"

mkdir -p "$OUT"

# ---- helpers -----------------------------------------------------------------
created_sims=()
cleanup() {
  for udid in "${created_sims[@]:-}"; do
    [[ -z "$udid" ]] && continue
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
    xcrun simctl delete "$udid"  >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

# extract named PNG attachments from an .xcresult into a destination dir
export_shots() {
  local result="$1" dest="$2"
  local tmp; tmp="$(mktemp -d)"
  xcrun xcresulttool export attachments --path "$result" --output-path "$tmp" >/dev/null
  mkdir -p "$dest"
  python3 - "$tmp" "$dest" <<'PY'
import json, os, re, shutil, sys
src, dest = sys.argv[1], sys.argv[2]
manifest = json.load(open(os.path.join(src, "manifest.json")))
count = 0
for test in manifest:
    for att in test.get("attachments", []):
        raw = att.get("suggestedHumanReadableName") or ""
        # Xcode decorates our name ("02_position_sizing") into e.g.
        # "02_position_sizing_0_<UUID>.png" — recover the clean leading part.
        m = re.match(r"^(\d\d_[A-Za-z0-9]+(?:_[A-Za-z0-9]+)*?)(?:_\d+_[0-9A-Fa-f-]{36})?\.png$", raw)
        if not m:
            continue
        name = m.group(1)
        fn = att.get("exportedFileName")
        if not fn:
            continue
        shutil.copyfile(os.path.join(src, fn), os.path.join(dest, name + ".png"))
        count += 1
print(f"    exported {count} screenshot(s) -> {dest}")
PY
  rm -rf "$tmp"
}

# ---- main matrix -------------------------------------------------------------
for dkey in "${WANT_DEVICES[@]}"; do
  spec="$(device_spec "$dkey")"
  [[ -z "$spec" ]] && { echo "Unknown device: $dkey" >&2; exit 2; }
  dlabel="${spec%%|*}"; dtype="${spec##*|}"

  simname="$SIM_PREFIX-$dkey"
  # recreate clean each run for determinism
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

    # Localize the simulator's system UI (e.g. the iPad status-bar date) to match
    # the run's language, then respring so it takes effect. -testLanguage only
    # affects the app, not the system chrome captured in a full-screen shot.
    xcrun simctl spawn "$udid" defaults write -g AppleLanguages -array "$lang" >/dev/null 2>&1 || true
    xcrun simctl spawn "$udid" defaults write -g AppleLocale "${lang}_${region}" >/dev/null 2>&1 || true
    xcrun simctl spawn "$udid" launchctl kickstart -k system/com.apple.SpringBoard >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true

    # clean, App-Store-friendly status bar (re-applied: a respring clears it)
    xcrun simctl status_bar "$udid" override \
      --time "09:41" \
      --batteryState charged --batteryLevel 100 \
      --cellularMode active --cellularBars 4 \
      --dataNetwork wifi --wifiMode active --wifiBars 3 \
      --operatorName "" >/dev/null 2>&1 || true

    result="$DERIVED/result-$dkey-$lkey.xcresult"
    rm -rf "$result"
    echo "  • [$dlabel/$lkey] running UI test…"
    xcodebuild test \
      -project "$PROJECT" -scheme "$SCHEME" \
      -destination "id=$udid" \
      -only-testing:"$TEST_ID" \
      -testLanguage "$lang" -testRegion "$region" \
      -derivedDataPath "$DERIVED" \
      -resultBundlePath "$result" \
      CODE_SIGNING_ALLOWED=NO \
      >/dev/null

    export_shots "$result" "$OUT/$lkey/$dlabel"
  done

  xcrun simctl status_bar "$udid" clear >/dev/null 2>&1 || true
done

echo "✅ Done. Screenshots in: $OUT/<lang>/<device>/"
