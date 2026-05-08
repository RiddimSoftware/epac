#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
OUTPUT_PATH="${1:-$ROOT_DIR/docs/brand/github-social-preview-1280x640.png}"
ICON_PATH="$ROOT_DIR/docs/brand/icon/epac-marketing-icon-1024.png"

mkdir -p "$(dirname "$OUTPUT_PATH")"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

ICON_RESIZED="$TMP_DIR/icon.png"
TITLE="$TMP_DIR/title.png"
TAGLINE="$TMP_DIR/tagline.png"
BODY="$TMP_DIR/body.png"
FOOTER="$TMP_DIR/footer.png"

magick "$ICON_PATH" -resize 220x220 "$ICON_RESIZED"
magick -background none -fill '#F3F4F6' -font Helvetica-Bold -pointsize 96 \
  label:'epac' "$TITLE"
magick -background none -fill '#FFFFFF' -font Helvetica-Bold -pointsize 40 \
  label:"Canada's Parliament, in your pocket." "$TAGLINE"
magick -background none -fill '#CBD5E1' -font Helvetica -pointsize 28 -size 720x \
  caption:'Track MPs, bills, votes, debates, expenses, and lobbying from official government sources.' \
  "$BODY"
magick -background none -fill '#94A3B8' -font Helvetica -pointsize 20 \
  label:'RiddimSoftware/epac · GitHub social preview' "$FOOTER"

magick -size 1280x640 xc:'#081226' \
  \( -size 1280x640 radial-gradient:'#16355F-#081226' -alpha set -channel A -evaluate multiply 0.45 +channel \) -compose screen -composite \
  \( -size 1280x640 xc:none -fill '#1D4ED8' -draw 'circle 1120,120 1120,360' -alpha set -channel A -evaluate multiply 0.18 +channel \) -compose screen -composite \
  \( -size 1280x640 xc:none -fill '#38BDF8' -draw 'circle 190,500 190,690' -alpha set -channel A -evaluate multiply 0.14 +channel \) -compose screen -composite \
  \( -size 1280x640 xc:none -fill none -stroke '#1E293B' -strokewidth 2 -draw 'roundrectangle 56,56 1224,584 28,28' \) -composite \
  \( -size 1280x640 xc:none -fill '#0F172A' -draw 'roundrectangle 72,72 1208,568 24,24' -alpha set -channel A -evaluate multiply 0.18 +channel \) -compose over -composite \
  \( "$ICON_RESIZED" -gravity northwest -geometry +116+206 \) -composite \
  \( "$TITLE" -gravity northwest -geometry +410+150 \) -composite \
  \( "$TAGLINE" -gravity northwest -geometry +410+258 \) -composite \
  \( "$BODY" -gravity northwest -geometry +410+332 \) -composite \
  \( "$FOOTER" -gravity northwest -geometry +410+520 \) -composite \
  PNG32:"$OUTPUT_PATH"

sips -g pixelWidth -g pixelHeight "$OUTPUT_PATH" >&2
ls -lh "$OUTPUT_PATH" >&2
