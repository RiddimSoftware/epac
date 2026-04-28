#!/usr/bin/env python3
"""Render EPAC-111 Product Page Optimization assets with the shared evidence CLI."""

from __future__ import annotations

from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[2]
SCENES = ROOT / "docs/marketing/app-store/evidence-scenes/epac-111"
OUT = ROOT / "docs/marketing/app-store/ppo-epac111/variant-b"
EVIDENCE = ROOT / "scripts/evidence/run-evidence.sh"


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    scene_files = sorted(SCENES.glob("*.json"))
    if not scene_files:
        raise SystemExit(f"No scene specs found in {SCENES}")

    for scene in scene_files:
        stem = scene.stem
        subprocess.run(
            [
                str(EVIDENCE),
                "render-marketing",
                "--scene",
                str(scene.relative_to(ROOT)),
                "--svg",
                str(OUT / f"{stem}.svg"),
                "--output",
                str(OUT / f"{stem}.png"),
                "--target",
                "6.9",
            ],
            cwd=ROOT,
            check=True,
        )


if __name__ == "__main__":
    main()
