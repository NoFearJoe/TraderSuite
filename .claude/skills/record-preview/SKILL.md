---
name: record-preview
description: Record App Store preview videos for TraderSuite in RU + EN across iPhone and iPad. The demo adds a futures contract to the watchlist from search, then sizes a position while sweeping risk levels. Use when the user asks to create/regenerate App Store preview videos or app previews.
---

# Record App Store preview videos

`scripts/record_preview.sh` records the demo flow on throwaway simulators,
offline and deterministic. RU shows MOEX, EN shows CME.

## The flow (UITests/PreviewVideoUITests.swift)

1. Start on a small watchlist.
2. Search and add the "hero" contract (RU: Si / EN: ES) to the watchlist.
3. Open Position Sizing, type entry + stop, then tap risk 2% → 3% → 1% so the
   recommended lots / loss / margin update live.
4. Leave the calculator (this is the recording's stop boundary).

The app (video mode, `ScreenshotSupport.swift`) drops `uitest.start` /
`uitest.end` marker files; the script polls them so the clip is bounded to the
demo, excluding XCUITest launch/teardown springboard.

## Running it

```bash
scripts/record_preview.sh                       # all devices × both languages
scripts/record_preview.sh --devices iphone      # one device class
scripts/record_preview.sh --langs ru            # one language
scripts/record_preview.sh --aim 24              # target final length (≤30s)
scripts/record_preview.sh --size 886x1920       # output resolution
```

Outputs per combo in `Previews/<lang>/<device>/`:
- `preview.mov` — raw capture at native device resolution.
- `preview-appstore.mp4` — the file to upload: **886×1920**, 30 fps, H.264, sped
  up to ≤ `--aim` seconds (App Store wants this exact size and a 15–30s length).

## Finalize step (no ffmpeg)

The raw demo runs long (~45–70s) due to XCUITest interaction latency and records
at the device's native resolution, so it's finalized to App Store spec by
`scripts/finalize_preview.swift` — pure **AVFoundation** (system frameworks, no
ffmpeg): it scales to 886×1920, speeds the clip up to fit `AIM_SECONDS`,
normalizes to 30 fps, and writes H.264 MP4. Run it standalone if needed:
`swift scripts/finalize_preview.swift in.mov out.mp4 886 1920 26`.

## What to do

1. Run the script (scope per the user's request).
2. Report the output paths and confirm `preview-appstore.mp4` is 886×1920 and
   within 15–30s (`swift scripts/finalize_preview.swift` prints the result size
   and length).
3. Spot-check a frame to confirm the demo ran: the calculator should show a
   non-zero "lots" result. If the flow drifted after a UI change, the selectors
   to check are `searchResult.<symbol>`, `watchlistRow.calc`, `calc.entry`,
   `calc.stop`, and `risk.preset.<n>`.

## Notes

- A new UI-test file needs `xcodegen generate` before it's compiled.
- macOS previews aren't wired (give the UITest a macOS destination to add them).
- See also the `screenshots` skill for still screenshots (shared demo data).
