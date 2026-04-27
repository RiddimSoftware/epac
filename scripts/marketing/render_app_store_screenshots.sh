#!/usr/bin/env bash
set -euo pipefail

source_dir="${1:-/tmp/epac-appstore-screenshots}"
output_dir="${2:-docs/marketing/screenshots}"

mkdir -p "$output_dir"

if ! command -v magick >/dev/null 2>&1; then
  echo "ImageMagick 'magick' is required to render screenshots." >&2
  exit 1
fi

expected=(
  "01-parliament-in-your-pocket.png"
  "02-see-how-your-mp-votes.png"
  "03-your-mp-everything-they-do.png"
  "04-track-a-bill-start-to-finish.png"
  "05-know-whos-influencing-your-mp.png"
  "06-contact-them-in-one-tap.png"
)

for file in "${expected[@]}"; do
  input="$source_dir/$file"
  output="$output_dir/$file"
  if [[ ! -f "$input" ]]; then
    echo "Missing source screenshot: $input" >&2
    exit 1
  fi

  magick "$input" \
    -resize '1290x2796^' \
    -gravity center \
    -extent 1290x2796 \
    -strip \
    "$output"
done

magick identify "$output_dir"/*.png
