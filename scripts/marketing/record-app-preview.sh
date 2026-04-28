#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Configuration. Override SIMULATOR_ID or DEVICE_NAME when the standard
# recording simulator is unavailable locally.
SIMULATOR_ID="${SIMULATOR_ID:-FCFAF817-6694-402D-B116-A86EDAF34237}"
DEVICE_NAME="${DEVICE_NAME:-}"
SCHEME="${SCHEME:-epac}"
PROJECT="$ROOT_DIR/ios/epac.xcodeproj"
TEST_ID="${TEST_ID:-epacUITests/AppPreviewRecordingTests/testAppPreviewRecordingSequence}"
OUTPUT_DIR="$ROOT_DIR/docs/marketing/preview"
RAW_FILE="$OUTPUT_DIR/raw-capture-$(date +%Y%m%d-%H%M%S).mp4"
FINAL_FILE="$OUTPUT_DIR/app-preview-final.mp4"
FASTLANE_PREVIEW_DIR="$ROOT_DIR/ios/fastlane/app-previews/en-CA"
FASTLANE_PREVIEW_VIDEO="$FASTLANE_PREVIEW_DIR/IPHONE_67_app-preview.mp4"
TARGET_DURATION=30
TARGET_W=886
TARGET_H=1920
TARGET_FPS=30
# Set SIMULATOR_ORIENTATION=landscape-left or landscape-right when recording a
# landscape App Preview. The default stays portrait for the 886x1920 App Store
# output used by the 6.9-inch portrait slot.
SIMULATOR_ORIENTATION="${SIMULATOR_ORIENTATION:-portrait}"

command -v ffmpeg >/dev/null 2>&1 || {
  echo "ERROR: ffmpeg not found. Install with: brew install ffmpeg" >&2
  exit 1
}

command -v ffprobe >/dev/null 2>&1 || {
  echo "ERROR: ffprobe not found. Install with: brew install ffmpeg" >&2
  exit 1
}

command -v xcrun >/dev/null 2>&1 || {
  echo "ERROR: xcrun not found. Install Xcode command line tools." >&2
  exit 1
}

if [[ -n "$DEVICE_NAME" ]]; then
  SIMULATOR_TARGET="$DEVICE_NAME"
  DESTINATION="platform=iOS Simulator,name=$DEVICE_NAME"
else
  SIMULATOR_TARGET="$SIMULATOR_ID"
  DESTINATION="platform=iOS Simulator,id=$SIMULATOR_ID"
fi

mkdir -p "$OUTPUT_DIR" "$FASTLANE_PREVIEW_DIR"

echo "Booting simulator $SIMULATOR_TARGET..."
xcrun simctl boot "$SIMULATOR_TARGET" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIMULATOR_TARGET" -b >/dev/null

rotate_simulator() {
  local direction="$1"
  local key_code

  case "$direction" in
    left) key_code=123 ;;
    right) key_code=124 ;;
    *)
      echo "ERROR: unknown simulator rotation direction '$direction'" >&2
      exit 1
      ;;
  esac

  if ! osascript >/dev/null <<OSA
tell application "Simulator" to activate
delay 0.2
tell application "System Events"
  key code $key_code using {command down}
end tell
OSA
  then
    echo "ERROR: could not rotate Simulator with Cmd-$direction. Grant automation/accessibility permission to your terminal, or rotate manually from Simulator > Device > Rotate." >&2
    exit 1
  fi
}

case "$SIMULATOR_ORIENTATION" in
  portrait)
    ;;
  landscape-left)
    echo "Rotating Simulator to landscape-left with Cmd-Left..."
    rotate_simulator left
    ;;
  landscape-right)
    echo "Rotating Simulator to landscape-right with Cmd-Right..."
    rotate_simulator right
    ;;
  *)
    echo "ERROR: SIMULATOR_ORIENTATION must be portrait, landscape-left, or landscape-right." >&2
    exit 1
    ;;
esac

echo "Building $SCHEME for simulator..."
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -configuration Debug \
  build

echo "Starting screen recording: $RAW_FILE"
xcrun simctl io "$SIMULATOR_TARGET" recordVideo \
  --codec h264 \
  --mask black \
  "$RAW_FILE" &
RECORDER_PID=$!

cleanup() {
  if kill -0 "$RECORDER_PID" >/dev/null 2>&1; then
    kill -INT "$RECORDER_PID" >/dev/null 2>&1 || true
    wait "$RECORDER_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

sleep 1

echo "Running AppPreviewRecordingTests..."
set +e
TEST_RUNNER_APP_PREVIEW_RECORDING=1 xcodebuild test \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -only-testing:"$TEST_ID"
TEST_EXIT=$?
set -e

cleanup
trap - EXIT

if [[ "$TEST_EXIT" -ne 0 ]]; then
  echo "ERROR: XCUITest failed (exit $TEST_EXIT). Raw capture saved to $RAW_FILE for debugging." >&2
  exit "$TEST_EXIT"
fi

RAW_DURATION=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$RAW_FILE")
echo "Raw capture duration: ${RAW_DURATION}s"

if awk "BEGIN { exit !($RAW_DURATION < 25) }"; then
  echo "WARNING: Raw capture is shorter than expected (${RAW_DURATION}s). Check test timing." >&2
fi

TMP_FINAL="$OUTPUT_DIR/app-preview-final.$(date +%Y%m%d-%H%M%S)-$$.tmp.mp4"
TMP_WITH_AUDIO="$OUTPUT_DIR/app-preview-final.$(date +%Y%m%d-%H%M%S)-$$.with-audio.tmp.mp4"
cleanup_tmp() {
  rm -f "$TMP_FINAL" "$TMP_WITH_AUDIO"
}
trap cleanup_tmp EXIT

echo "Trimming to ${TARGET_DURATION}s and scaling to ${TARGET_W}x${TARGET_H}..."
ffmpeg -y \
  -i "$RAW_FILE" \
  -ss 0 \
  -t "$TARGET_DURATION" \
  -vf "fps=${TARGET_FPS},scale=${TARGET_W}:${TARGET_H}:force_original_aspect_ratio=decrease,pad=${TARGET_W}:${TARGET_H}:(ow-iw)/2:(oh-ih)/2" \
  -c:v libx264 \
  -preset slow \
  -crf 18 \
  -an \
  "$TMP_FINAL"

FINAL_DURATION=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$TMP_FINAL")
FINAL_DIM=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$TMP_FINAL" | head -1)
FINAL_SIZE_BYTES=$(wc -c < "$TMP_FINAL" | tr -d ' ')

if ! awk "BEGIN { exit !($FINAL_DURATION >= 29 && $FINAL_DURATION <= 31) }"; then
  echo "ERROR: Final duration ${FINAL_DURATION}s is outside 30s +/- 1s." >&2
  exit 1
fi

if [[ "$FINAL_DIM" != "${TARGET_W},${TARGET_H}" ]]; then
  echo "ERROR: Final dimensions $FINAL_DIM do not match ${TARGET_W}x${TARGET_H}." >&2
  exit 1
fi

if [[ "$FINAL_SIZE_BYTES" -ge 500000000 ]]; then
  echo "ERROR: Final file is $FINAL_SIZE_BYTES bytes, above App Store's 500MB limit." >&2
  exit 1
fi

# Apple's App Preview pipeline rejects videos with no audio track
# ("unsupported or corrupted audio") even though the spec calls audio
# "optional", so mux in a silent AAC stereo @ 44.1 kHz before publishing.
echo "Muxing silent AAC audio track for App Store compatibility..."
ffmpeg -y \
  -i "$TMP_FINAL" \
  -f lavfi -i anullsrc=cl=stereo:r=44100 \
  -shortest \
  -map 0:v -map 1:a \
  -c:v copy \
  -c:a aac -b:a 128k \
  "$TMP_WITH_AUDIO"

WITH_AUDIO_SIZE_BYTES=$(wc -c < "$TMP_WITH_AUDIO" | tr -d ' ')
if [[ "$WITH_AUDIO_SIZE_BYTES" -ge 500000000 ]]; then
  echo "ERROR: Final file with audio is $WITH_AUDIO_SIZE_BYTES bytes, above App Store's 500MB limit." >&2
  exit 1
fi

mv "$TMP_WITH_AUDIO" "$FINAL_FILE"
rm -f "$TMP_FINAL"
trap - EXIT

cp "$FINAL_FILE" "$FASTLANE_PREVIEW_VIDEO"

FINAL_SIZE=$(du -sh "$FINAL_FILE" | cut -f1)

echo ""
echo "App Preview video ready"
echo "  File:       $FINAL_FILE"
echo "  Raw:        $RAW_FILE"
echo "  Duration:   ${FINAL_DURATION}s"
echo "  Dimensions: $FINAL_DIM"
echo "  Size:       $FINAL_SIZE"
echo "  Fastlane:   $FASTLANE_PREVIEW_VIDEO"
