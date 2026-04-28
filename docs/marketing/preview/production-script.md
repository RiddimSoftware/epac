# App Preview Video Production

**Ticket:** EPAC-535  
**Duration:** 30 seconds  
**Format:** H.264 MP4, 886x1920, 30fps, no audio  
**Output:** `docs/marketing/preview/app-preview-final.mp4`

## One-command regeneration

Run from the repository root:

```bash
./scripts/marketing/record-app-preview.sh
```

The script boots the 6.9-inch simulator, starts `simctl recordVideo`, runs only `AppPreviewRecordingTests/testAppPreviewSequence`, stops the recorder, and uses `ffmpeg` to export the App Store-ready MP4.

## Storyboard

| Timestamp | Screen | Automated scene | Text overlay for post-production |
|---|---|---|---|
| 0:00-0:05 | Home feed | Today in Parliament cards | "Your MP. Everything they do." |
| 0:05-0:11 | My MP profile | MP activity and vote record | "Every word. Every vote." |
| 0:11-0:17 | Debate / SpeechView | Hansard-style speech bubbles | "Hansard. Finally readable." |
| 0:17-0:22 | Lobbying connections | Communications list | "Who's influencing them?" |
| 0:22-0:27 | Vote detail | MP breakdown and debate link | "They said it. Then voted against it." |
| 0:27-0:30 | Contact sheet | Pre-filled constituent message | "Democracy. One tap." |

The automated recording contains clean app UI only. Add text overlays in iMovie, Final Cut, or App Store Connect media tooling after the MP4 is generated.

## Requirements

- Xcode with the `epac` scheme available
- A 6.9-inch iPhone simulator; override with `DEVICE_NAME="..."` if needed
- `ffmpeg` and `ffprobe` on `PATH`

## Verification

```bash
ffprobe -v error \
  -select_streams v:0 \
  -show_entries stream=codec_name,width,height,r_frame_rate \
  -show_entries format=duration \
  -of default=noprint_wrappers=1 \
  docs/marketing/preview/app-preview-final.mp4
```

Expected values: H.264 video, 886x1920, 30fps, 30 seconds +/- 1 second, no audio stream.

## Upload

1. App Store Connect -> My Apps -> epac -> iOS App -> current version -> App Preview.
2. Upload `docs/marketing/preview/app-preview-final.mp4` to the 6.9-inch App Preview slot.
3. Add optional text overlays before upload if the campaign requires them.
