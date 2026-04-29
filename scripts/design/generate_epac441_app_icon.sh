#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ICON_DIR="$ROOT/ios/epac/Assets.xcassets/AppIcon.appiconset"
CLIP_ICON_DIR="$ROOT/ios/epac-clip/Assets.xcassets/AppIcon.appiconset"
EXPLORE_DIR="$ROOT/docs/brand/icon/v1-explorations"
EVIDENCE_DIR="$ROOT/docs/build-evidence"
MARKETING_ICON="$ROOT/docs/brand/icon/epac-marketing-icon-1024.png"

MAGICK="${MAGICK:-/opt/homebrew/bin/magick}"

mkdir -p "$EXPLORE_DIR" "$EVIDENCE_DIR"

if [[ -f "$ICON_DIR/AppIcon-Light.png" && ! -f "$EXPLORE_DIR/current-icon-before.png" ]]; then
	cp "$ICON_DIR/AppIcon-Light.png" "$EXPLORE_DIR/current-icon-before.png"
fi

draw_record_lens_light() {
	"$MAGICK" -size 1024x1024 \
		gradient:"#f8fbf6-#dbe8df" \
		-fill "#07120d" -draw "rectangle 0,0 1024,1024" \
		-fill "#123324" -draw "roundrectangle 152,152 872,872 178,178" \
		-fill "#f8fbf6" -draw "roundrectangle 258,164 766,860 82,82" \
		-fill "#d8efe0" -draw "roundrectangle 310,232 714,310 38,38" \
		-fill "#0d2217" -draw "roundrectangle 324,394 700,454 30,30" \
		-fill "#0d2217" -draw "roundrectangle 324,514 636,574 30,30" \
		-fill "#0d2217" -draw "roundrectangle 324,634 700,694 30,30" \
		-fill "none" -stroke "#2fdf6c" -strokewidth 58 -draw "ellipse 512,544 188,188 0,360" \
		-stroke "#2fdf6c" -strokewidth 64 -draw "line 646,678 744,776" \
		-fill "#07120d" -stroke "none" -draw "roundrectangle 424,505 600,564 28,28" \
		-fill "#07120d" -draw "roundrectangle 424,594 560,652 28,28" \
		-alpha off -strip "$1"
}

draw_record_lens_dark() {
	"$MAGICK" -size 1024x1024 \
		gradient:"#0b110f-#020403" \
		-fill "#06100b" -draw "rectangle 0,0 1024,1024" \
		-fill "#1d3f2d" -draw "roundrectangle 152,152 872,872 178,178" \
		-fill "#0f1714" -draw "roundrectangle 258,164 766,860 82,82" \
		-fill "#1d3f2d" -draw "roundrectangle 310,232 714,310 38,38" \
		-fill "#f7fbf5" -draw "roundrectangle 324,394 700,454 30,30" \
		-fill "#f7fbf5" -draw "roundrectangle 324,514 636,574 30,30" \
		-fill "#f7fbf5" -draw "roundrectangle 324,634 700,694 30,30" \
		-fill "none" -stroke "#36e879" -strokewidth 58 -draw "ellipse 512,544 188,188 0,360" \
		-stroke "#36e879" -strokewidth 64 -draw "line 646,678 744,776" \
		-fill "#07120d" -stroke "none" -draw "roundrectangle 424,505 600,564 28,28" \
		-fill "#07120d" -draw "roundrectangle 424,594 560,652 28,28" \
		-alpha off -strip "$1"
}

draw_record_lens_tinted() {
	"$MAGICK" -size 1024x1024 xc:none \
		-fill "none" -stroke "#ffffff" -strokewidth 72 -draw "roundrectangle 238,142 786,882 90,90" \
		-stroke "none" \
		-fill "#ffffff" -draw "roundrectangle 302,228 722,316 42,42" \
		-fill "#ffffff" -draw "roundrectangle 316,390 708,458 34,34" \
		-fill "#ffffff" -draw "roundrectangle 316,516 642,584 34,34" \
		-fill "#ffffff" -draw "roundrectangle 316,642 708,710 34,34" \
		-fill "none" -stroke "#ffffff" -strokewidth 70 -draw "ellipse 512,552 198,198 0,360" \
		-stroke "#ffffff" -strokewidth 74 -draw "line 656,692 764,800" \
		-strip "$1"
}

draw_civic_grid() {
	"$MAGICK" -size 1024x1024 gradient:"#f5f9f6-#dce8e0" \
		-fill "#0b1711" -draw "rectangle 0,0 1024,1024" \
		-fill "#f8fbf6" -draw "roundrectangle 230,230 462,462 54,54" \
		-fill "#f8fbf6" -draw "roundrectangle 562,230 794,462 54,54" \
		-fill "#f8fbf6" -draw "roundrectangle 230,562 462,794 54,54" \
		-fill "#f8fbf6" -draw "roundrectangle 562,562 794,794 54,54" \
		-stroke "#2fdf6c" -strokewidth 44 -draw "line 462,346 562,346 line 346,462 346,562 line 678,462 678,562 line 462,678 562,678" \
		-fill "#2fdf6c" -stroke "none" -draw "ellipse 512,512 72,72 0,360" \
		-alpha off -strip "$1"
}

draw_source_path() {
	"$MAGICK" -size 1024x1024 gradient:"#f9fbf7-#dce7df" \
		-fill "#07120d" -draw "rectangle 0,0 1024,1024" \
		-fill "none" -stroke "#2fdf6c" -strokewidth 54 -draw "path 'M 250 702 C 350 522, 392 508, 512 512 S 682 502, 774 320'" \
		-fill "#f8fbf6" -stroke "none" \
		-draw "ellipse 250,702 92,92 0,360 ellipse 512,512 108,108 0,360 ellipse 774,320 92,92 0,360" \
		-fill "#102118" -draw "ellipse 250,702 32,32 0,360 ellipse 512,512 36,36 0,360 ellipse 774,320 32,32 0,360" \
		-fill "#f8fbf6" -draw "roundrectangle 314,236 654,360 42,42 roundrectangle 314,672 654,796 42,42" \
		-alpha off -strip "$1"
}

draw_record_lens_light "$ICON_DIR/AppIcon-Light.png"
draw_record_lens_dark "$ICON_DIR/AppIcon-Dark.png"
draw_record_lens_tinted "$ICON_DIR/AppIcon-Tinted.png"
cp "$ICON_DIR/AppIcon-Light.png" "$CLIP_ICON_DIR/AppIcon-Light.png"
cp "$ICON_DIR/AppIcon-Dark.png" "$CLIP_ICON_DIR/AppIcon-Dark.png"
cp "$ICON_DIR/AppIcon-Tinted.png" "$CLIP_ICON_DIR/AppIcon-Tinted.png"
draw_record_lens_light "$MARKETING_ICON"

draw_record_lens_light "$EXPLORE_DIR/01-record-lens.png"
draw_civic_grid "$EXPLORE_DIR/02-civic-grid.png"
draw_source_path "$EXPLORE_DIR/03-source-path.png"

"$MAGICK" montage \
	"$EXPLORE_DIR/01-record-lens.png" \
	"$EXPLORE_DIR/02-civic-grid.png" \
	"$EXPLORE_DIR/03-source-path.png" \
	-background "#f6f8f6" -geometry 220x220+18+18 \
	-tile 3x1 "$EXPLORE_DIR/concept-contact-sheet.png"

"$MAGICK" montage \
	"$EXPLORE_DIR/current-icon-before.png" \
	"$ICON_DIR/AppIcon-Light.png" \
	-background "#f6f8f6" -geometry 260x260+24+24 \
	-tile 2x1 "$EVIDENCE_DIR/EPAC-441-before-after.png"
"$MAGICK" "$EVIDENCE_DIR/EPAC-441-before-after.png" -resize 600x "$EVIDENCE_DIR/EPAC-441-before-after.png"
