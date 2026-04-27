#!/usr/bin/env python3
"""Generate EPAC-111 Product Page Optimization Variant B screenshots.

The images are intentionally generated from structured scene data so the
headline treatment can be reviewed and regenerated without manual design drift.
"""

from __future__ import annotations

from pathlib import Path
import html
import subprocess


OUT = Path("docs/marketing/app-store/ppo-epac111/variant-b")
WIDTH = 1290
HEIGHT = 2796


SCENES = [
    {
        "file": "01-your-mp-voted-last-night",
        "headline": "Your MP voted last night. Did you know?",
        "subhead": "See the vote record, the party split, and the official source in one place.",
        "kicker": "Vote record",
        "screen": "House of Commons vote record",
        "detail": "Recorded division with official result",
        "accent": "#0071E3",
        "rows": [
            ("Result", "Official House record", "#007D3C"),
            ("Members", "Yea, Nay, Paired", "#D01D1D"),
            ("Source", "Parliament of Canada", "#8E8E93"),
        ],
    },
    {
        "file": "02-what-they-said-before",
        "headline": "What did they say before the vote?",
        "subhead": "Read the official Hansard debate in a chat format built for scanning.",
        "kicker": "Debate",
        "screen": "Official Report of Debates",
        "detail": "Hansard transcript from the House",
        "accent": "#00A4B0",
        "rows": [
            ("Speaker", "Name and riding", "#D01D1D"),
            ("Topic", "Subject of business", "#003F7D"),
            ("Text", "Official transcript", "#E67E00"),
        ],
    },
    {
        "file": "03-your-representative",
        "headline": "Your representative has a record.",
        "subhead": "Enter a postal code once. Track votes, speeches, expenses, and contact info.",
        "kicker": "My MP",
        "screen": "Your riding",
        "detail": "Votes, speeches, expenses, and contact details",
        "accent": "#003F7D",
        "rows": [
            ("Votes", "Recorded divisions", "#007D3C"),
            ("Speeches", "Hansard interventions", "#0071E3"),
            ("Expenses", "Public disclosures", "#E67E00"),
        ],
    },
    {
        "file": "04-bill-cost",
        "headline": "A bill can spend billions.",
        "subhead": "Follow each stage, every vote, and the Parliamentary Budget Officer estimate.",
        "kicker": "Bills",
        "screen": "Federal bill timeline",
        "detail": "Stages, votes, and cost context",
        "accent": "#5856D6",
        "rows": [
            ("Stages", "LEGISinfo status", "#007D3C"),
            ("Votes", "Recorded divisions", "#0071E3"),
            ("Costs", "PBO publications", "#8E8E93"),
        ],
    },
    {
        "file": "05-party-line",
        "headline": "Was it a party-line vote?",
        "subhead": "Compare MP votes by party and see who broke ranks.",
        "kicker": "Voting records",
        "screen": "Recorded division",
        "detail": "Party split by official vote",
        "accent": "#E67E00",
        "rows": [
            ("Liberals", "Party position", "#D01D1D"),
            ("Conservatives", "Party position", "#003F7D"),
            ("NDP", "Party position", "#E67E00"),
        ],
    },
    {
        "file": "06-contact-with-context",
        "headline": "Have something to say?",
        "subhead": "Contact your MP with the vote, bill, or debate already attached.",
        "kicker": "Civic action",
        "screen": "Email your MP",
        "detail": "Subject includes the source record",
        "accent": "#007D3C",
        "rows": [
            ("To", "Your MP's public email", "#0071E3"),
            ("Source", "House record link", "#8E8E93"),
            ("Action", "Ready to send", "#007D3C"),
        ],
    },
]


def wrap(text: str, limit: int) -> list[str]:
    words = text.split()
    lines: list[str] = []
    current: list[str] = []
    for word in words:
        trial = " ".join(current + [word])
        if len(trial) > limit and current:
            lines.append(" ".join(current))
            current = [word]
        else:
            current.append(word)
    if current:
        lines.append(" ".join(current))
    return lines


def text_lines(lines: list[str], x: int, y: int, size: int, weight: int, color: str, gap: int) -> str:
    parts = []
    for idx, line in enumerate(lines):
        parts.append(
            f'<text x="{x}" y="{y + idx * gap}" font-family="Helvetica Neue, Arial, sans-serif" '
            f'font-size="{size}" font-weight="{weight}" fill="{color}">{html.escape(line)}</text>'
        )
    return "\n".join(parts)


def render(scene: dict[str, object]) -> str:
    headline = wrap(str(scene["headline"]), 18)
    subhead = wrap(str(scene["subhead"]), 36)
    rows = scene["rows"]
    row_svg = []
    for idx, (label, value, color) in enumerate(rows):  # type: ignore[misc]
        y = 1635 + idx * 205
        row_svg.append(
            f"""
            <rect x="164" y="{y}" width="962" height="148" rx="32" fill="#FFFFFF" stroke="#E5E5EA" stroke-width="2"/>
            <circle cx="230" cy="{y + 74}" r="22" fill="{color}"/>
            <text x="286" y="{y + 62}" font-family="Helvetica Neue, Arial, sans-serif" font-size="38" font-weight="700" fill="#1C1C1E">{html.escape(label)}</text>
            <text x="286" y="{y + 108}" font-family="Helvetica Neue, Arial, sans-serif" font-size="32" font-weight="500" fill="#6E6E73">{html.escape(value)}</text>
            """
        )

    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}" viewBox="0 0 {WIDTH} {HEIGHT}">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#0B1220"/>
      <stop offset="0.55" stop-color="#172033"/>
      <stop offset="1" stop-color="{scene["accent"]}"/>
    </linearGradient>
    <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="0" dy="28" stdDeviation="24" flood-color="#000000" flood-opacity="0.35"/>
    </filter>
  </defs>
  <rect width="{WIDTH}" height="{HEIGHT}" fill="url(#bg)"/>
  <text x="104" y="176" font-family="Helvetica Neue, Arial, sans-serif" font-size="42" font-weight="700" fill="#FFFFFF" opacity="0.82">epac</text>
  {text_lines(headline, 104, 430, 100, 800, "#FFFFFF", 112)}
  {text_lines(subhead, 108, 760 + max(0, len(headline) - 2) * 80, 42, 500, "#D9E2F2", 56)}
  <g filter="url(#shadow)">
    <rect x="112" y="1110" width="1066" height="1320" rx="72" fill="#F5F7FA"/>
    <rect x="150" y="1170" width="990" height="120" rx="36" fill="{scene["accent"]}"/>
    <text x="194" y="1248" font-family="Helvetica Neue, Arial, sans-serif" font-size="40" font-weight="800" fill="#FFFFFF">{html.escape(str(scene["kicker"]))}</text>
    <rect x="164" y="1360" width="962" height="210" rx="36" fill="#FFFFFF"/>
    <text x="210" y="1450" font-family="Helvetica Neue, Arial, sans-serif" font-size="50" font-weight="800" fill="#1C1C1E">{html.escape(str(scene["screen"]))}</text>
    <text x="210" y="1518" font-family="Helvetica Neue, Arial, sans-serif" font-size="34" font-weight="500" fill="#6E6E73">{html.escape(str(scene["detail"]))}</text>
    {"".join(row_svg)}
    <rect x="164" y="2262" width="962" height="82" rx="24" fill="#EEF5FF"/>
    <text x="210" y="2316" font-family="Helvetica Neue, Arial, sans-serif" font-size="28" font-weight="700" fill="#0071E3">Source: official parliamentary records</text>
  </g>
</svg>
"""


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for scene in SCENES:
        stem = str(scene["file"])
        svg = OUT / f"{stem}.svg"
        png = OUT / f"{stem}.png"
        svg.write_text(render(scene), encoding="utf-8")
        subprocess.run(["magick", str(svg), str(png)], check=True)


if __name__ == "__main__":
    main()
