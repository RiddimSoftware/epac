#!/usr/bin/env bash
set -euo pipefail

source_dir="${1:-/tmp/epac-appstore-screenshots}"
output_dir="${2:-docs/marketing/screenshots}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EVIDENCE="$ROOT_DIR/scripts/evidence/run-evidence.sh"
MAGICK="${MAGICK:-magick}"

mkdir -p "$output_dir"
source_dir="$(cd "$source_dir" && pwd)"
output_dir="$(cd "$output_dir" && pwd)"

expected=(
  "01-parliament-in-your-pocket.png"
  "02-see-how-your-mp-votes.png"
  "03-your-mp-everything-they-do.png"
  "04-track-a-bill-start-to-finish.png"
  "05-know-whos-influencing-your-mp.png"
  "06-contact-them-in-one-tap.png"
)

ipad_targets=(
  "APP_IPAD_PRO_3GEN_129:2064x2752"
  "APP_IPAD_PRO_129:2048x2732"
)

for file in "${expected[@]}"; do
  input="$source_dir/$file"
  if [[ ! -f "$input" ]]; then
    echo "Missing source screenshot: $input" >&2
    exit 1
  fi

  output="$output_dir/$file"
  "$EVIDENCE" resize --input "$input" --target 6.9 --output "$output"

  background="$("$MAGICK" "$input" -format "%[pixel:p{0,0}]" info:)"
  for target in "${ipad_targets[@]}"; do
    device="${target%%:*}"
    size="${target#*:}"
    output="$output_dir/${device}_${file}"
    "$MAGICK" "$input" \
      -resize "$size" \
      -background "$background" \
      -gravity center \
      -extent "$size" \
      -alpha remove \
      -alpha off \
      "$output"
  done
done

ls -lh "$output_dir"/*.png
