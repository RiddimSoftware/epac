#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IOS_DIR="$ROOT_DIR/ios"
OUTPUT_DIR="$ROOT_DIR/docs/marketing/preview"
RAW_VIDEO="$OUTPUT_DIR/raw-capture.mp4"
FINAL_VIDEO="$OUTPUT_DIR/app-preview-final.mp4"
DEVICE_NAME="${DEVICE_NAME:-iPhone 17 Pro Max}"
DESTINATION="${DESTINATION:-platform=iOS Simulator,name=$DEVICE_NAME}"

mkdir -p "$OUTPUT_DIR"

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "error: ffmpeg is required" >&2
  exit 1
fi

if ! command -v ffprobe >/dev/null 2>&1; then
  echo "error: ffprobe is required" >&2
  exit 1
fi

xcrun simctl boot "$DEVICE_NAME" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$DEVICE_NAME" -b >/dev/null

rm -f "$RAW_VIDEO" "$FINAL_VIDEO"

xcrun simctl io "$DEVICE_NAME" recordVideo --codec h264 "$RAW_VIDEO" &
RECORDER_PID=$!

cleanup() {
  if kill -0 "$RECORDER_PID" >/dev/null 2>&1; then
    kill -INT "$RECORDER_PID" >/dev/null 2>&1 || true
    wait "$RECORDER_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

cd "$IOS_DIR"
xcodebuild test -project epac.xcodeproj -scheme epac -destination "$DESTINATION" -only-testing:epacUITests/AppPreviewRecordingTests/testAppPreviewSequence

cleanup
trap - EXIT

ffmpeg -y -i "$RAW_VIDEO" -t 30 -vf "scale=886:1920:force_original_aspect_ratio=increase,crop=886:1920,fps=30" -an -c:v libx264 -pix_fmt yuv420p -profile:v high -level 4.0 -movflags +faststart "$FINAL_VIDEO"

ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,width,height,r_frame_rate -show_entries format=duration -of default=noprint_wrappers=1 "$FINAL_VIDEO"
echo "Wrote $FINAL_VIDEO"
