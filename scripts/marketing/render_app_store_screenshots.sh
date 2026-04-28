#!/usr/bin/env bash
set -euo pipefail

source_dir="${1:-/tmp/epac-appstore-screenshots}"
output_dir="${2:-docs/marketing/screenshots}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EVIDENCE="$ROOT_DIR/scripts/evidence/run-evidence.sh"

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

for file in "${expected[@]}"; do
  input="$source_dir/$file"
  output="$output_dir/$file"
  if [[ ! -f "$input" ]]; then
    echo "Missing source screenshot: $input" >&2
    exit 1
  fi

  "$EVIDENCE" resize --input "$input" --target 6.9 --output "$output"
done

ls -lh "$output_dir"/*.png
