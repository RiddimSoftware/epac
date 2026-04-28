# App Preview Video — Production Script

**Ticket:** EPAC-305
**Duration:** 30 seconds
**Format:** H.264 MP4, 886×1920 (6.9" iPhone), 30fps, no audio
**Source:** EPAC-300 creative brief

## Pre-production checklist

Before recording, prepare the simulator:
- [ ] Onboarding complete (postal code set to a real Canadian riding, e.g. M5H 2N2)
- [ ] One bill followed (e.g. Bill C-49)
- [ ] One MP followed (e.g. the MP for M5H 2N2)
- [ ] Home feed populated (at least one sitting day's data synced)
- [ ] No debug overlays, no test data, no "[PLACEHOLDER]" text
- [ ] Simulator language: English (Canada)
- [ ] Dark mode enabled (consistent with screenshot aesthetic)

## The 30-second sequence

| Timestamp | Screen | Action | On-screen text overlay |
|---|---|---|---|
| 0:00–0:03 | Home feed / notification | Notification banner animates in | "Parliament voted last night." |
| 0:03–0:08 | My MP feed | Slow scroll through MP activity: speech, vote, expense | "Your MP. Everything they do." |
| 0:08–0:14 | Debate (SpeechView) | Two MPs speaking, speech bubbles appear | "Hansard. Finally readable." |
| 0:14–0:19 | Lobbying connections | List of lobbyist communications scrolls | "Who's influencing them?" |
| 0:19–0:24 | Vote detail with speech link | Vote-speech cross-reference highlighted | "They said it. Then voted against it." |
| 0:24–0:30 | Contact sheet | Pre-filled message opens, send button | "Democracy. One tap." |

## Recording instructions

1. Open Simulator (iPhone 16 Pro Max — 6.9")
2. Navigate to each screen manually in sequence
3. Record using: `xcrun simctl io booted recordVideo --codec h264 raw-capture.mp4`
4. Perform the sequence naturally — no rushed navigation

## Post-production (ffmpeg commands)

```bash
# Check duration
ffprobe -i raw-capture.mp4 -show_entries format=duration -v quiet -of csv="p=0"

# Trim to 30 seconds (adjust start/end as needed after reviewing)
ffmpeg -i raw-capture.mp4 -ss 0 -t 30 -c copy trimmed.mp4

# Scale to required App Store resolution if needed
ffmpeg -i trimmed.mp4 -vf scale=886:1920 -c:v libx264 -preset slow -crf 18 app-preview-final.mp4

# Verify output
ffprobe -i app-preview-final.mp4 -show_entries stream=width,height,r_frame_rate -v quiet
```

## Text overlay (optional — iMovie/Final Cut)

For each timestamp segment in the table above, add a white text title card using iMovie:
1. Import trimmed.mp4
2. Add title at each timestamp
3. Font: system sans-serif (SF Pro or equivalent)
4. Color: white on semi-transparent dark overlay
5. Export: File → Share → File → H.264, 1920×886 (rotated — iMovie may need manual resize)

Apple does NOT require text overlays. The video can ship without them if time is short.

## Upload to App Store Connect

1. App Store Connect → My Apps → epac → iOS App → [current version] → App Preview
2. Drag `app-preview-final.mp4` into the App Preview slot for 6.9"
3. Submit with the next app version

## File locations

- Raw capture: `docs/marketing/preview/raw-capture.mp4`
- Trimmed: `docs/marketing/preview/trimmed-30s.mp4` (produced manually after review)
- Final: `docs/marketing/preview/app-preview-final.mp4` (produced after post-production)
