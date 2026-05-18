# App Preview Video Production

**Ticket:** EPAC-535  
**Duration:** 30 seconds  
**Format:** H.264 MP4, 886x1920, 30fps, silent AAC audio
**Output:** `docs/marketing/preview/app-preview-final.mp4`

## Automated production (recommended)

Run from the repository root:

```bash
./scripts/marketing/record-app-preview.sh
```

The script builds the app, boots the 6.9-inch simulator, starts `simctl recordVideo`, runs only `AppPreviewRecordingTests/testAppPreviewSequence`, stops the recorder, delegates final H.264 encoding to `evidence record-preview`, then adds the silent AAC audio track required by App Store Connect.

**Prerequisites:**

- `ffmpeg` and `ffprobe` installed (`brew install ffmpeg`)
- Simulator `FCFAF817-6694-402D-B116-A86EDAF34237` available, or a 6.9-inch iPhone simulator selected with `DEVICE_NAME="..."`
- Xcode with the `epac` scheme available

**Output:** `docs/marketing/preview/app-preview-final.mp4`, ready for App Store Connect upload.

## Storyboard

| Timestamp | Screen | Automated scene | Text overlay for post-production |
|---|---|---|---|
| 0:00-0:05 | Home feed | Today in Parliament cards | "Your MP. Everything they do." |
| 0:05-0:11 | My MP profile | MP activity and vote record | "Every vote. Every detail." |
| 0:11-0:17 | Debate / SpeechView | Hansard-style speech bubbles | "Hansard. Finally readable." |
| 0:17-0:22 | Lobbying connections | Communications list | "Who's influencing them?" |
| 0:22-0:27 | Vote detail | MP breakdown and debate link | "They said it. Then voted against it." |
| 0:27-0:30 | Contact sheet | Pre-filled constituent message | "Democracy. One tap." |

The automated recording contains clean app UI only. Add text overlays in iMovie, Final Cut, or App Store Connect media tooling after the MP4 is generated.

## Manual production (fallback)

Only use manual production if the automated script is broken and the video is needed urgently.

1. Build and install the simulator app.
2. Launch with `--app-preview-mode`.
3. Start `simctl recordVideo`.
4. Let the six-scene storyboard above run to completion.
5. Stop recording and encode the final video as H.264, 886x1920, 30fps, with a silent AAC audio track.

## Verification

```bash
ffprobe -v error \
  -select_streams v:0 \
  -show_entries stream=codec_name,width,height,r_frame_rate \
  -show_entries format=duration \
  -of default=noprint_wrappers=1 \
  docs/marketing/preview/app-preview-final.mp4

ffprobe -v error \
  -select_streams a:0 \
  -show_entries stream=codec_name,channels,sample_rate \
  -of default=noprint_wrappers=1 \
  docs/marketing/preview/app-preview-final.mp4
```

Expected values: H.264 video, 886x1920, 30fps, 30 seconds +/- 1 second, plus a silent AAC stereo audio stream at 44.1 kHz.

## Upload

1. App Store Connect -> My Apps -> epac -> iOS App -> current version -> App Preview.
2. Upload `docs/marketing/preview/app-preview-final.mp4` to the 6.9-inch App Preview slot.
3. Add optional text overlays before upload if the campaign requires them.
