#!/usr/bin/env python3
"""Generate comparison-tool OG share assets from website/og/compare-template.svg."""

from __future__ import annotations

import argparse
import html
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent
TEMPLATE = ROOT / "og" / "compare-template.svg"


def initials(value: str) -> str:
    parts = [part for part in value.replace("-", " ").split() if part]
    return "".join(part[0] for part in parts[:3]).upper()


def render(args: argparse.Namespace) -> str:
    svg = TEMPLATE.read_text(encoding="utf-8")
    replacements = {
        "ENTITY_A": args.entity_a,
        "ENTITY_B": args.entity_b,
        "A_INITIALS": args.a_initials or initials(args.entity_a),
        "B_INITIALS": args.b_initials or initials(args.entity_b),
        "A_LABEL": args.a_label,
        "B_LABEL": args.b_label,
        "SCORE": args.score,
        "BASIS": args.basis,
        "URL": args.url,
        "VARIANT": args.variant,
    }
    for key, value in replacements.items():
        svg = svg.replace("{{" + key + "}}", html.escape(value))
    return svg


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--entity-a", required=True)
    parser.add_argument("--entity-b", required=True)
    parser.add_argument("--score", required=True)
    parser.add_argument("--basis", required=True)
    parser.add_argument("--url", required=True)
    parser.add_argument("--output", required=True, help="Output path without extension")
    parser.add_argument("--a-label", default="Member of Parliament")
    parser.add_argument("--b-label", default="Member of Parliament")
    parser.add_argument("--a-initials", default="")
    parser.add_argument("--b-initials", default="")
    parser.add_argument("--variant", default="MP-vs-MP")
    args = parser.parse_args()

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    svg_path = output.with_suffix(".svg")
    png_path = output.with_suffix(".png")

    svg_path.write_text(render(args), encoding="utf-8")

    magick = shutil.which("magick")
    if magick:
        subprocess.run([magick, str(svg_path), str(png_path)], check=True)
    else:
        print("ImageMagick not found; wrote SVG only.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
