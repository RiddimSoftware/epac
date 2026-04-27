#!/usr/bin/env python3
"""Generate EPAC-109 App Store screenshot refresh assets.

The output images are deterministic 1290x2796 App Store screenshots with a
headline overlay and an app-content device frame. Scene copy uses concrete
official-source examples instead of placeholder text.
"""

from __future__ import annotations

from pathlib import Path
import html
import subprocess


OUT = Path("docs/marketing/screenshots/epac-109")
WIDTH = 1290
HEIGHT = 2796


SCENES = [
    {
        "file": "01-parliament-in-your-pocket",
        "headline": "Parliament in your pocket",
        "subhead": "Read official House debates in a format built for scanning.",
        "tab": "Debate",
        "screen": "Hansard",
        "source": "House of Commons Hansard",
        "accent": "#0071E3",
        "content": [
            ("The Speaker", "Government Orders. Bill C-5, One Canadian Economy Act.", "left", "#8E8E93"),
            ("Minister", "Internal trade and labour mobility across Canada.", "right", "#D01D1D"),
            ("Opposition MP", "Scrutiny, timelines, and accountability.", "left", "#003F7D"),
        ],
    },
    {
        "file": "02-see-how-your-mp-votes",
        "headline": "See how your MP votes",
        "subhead": "Every recorded division, result, and official source link.",
        "tab": "Votes",
        "screen": "Vote 24",
        "source": "OurCommons votes, June 20, 2025",
        "accent": "#007D3C",
        "content": [
            ("Bill C-5 report stage amendment", "Negatived", "badge", "#D01D1D"),
            ("Yea", "163 members", "metric", "#007D3C"),
            ("Nay", "174 members", "metric", "#D01D1D"),
            ("Paired", "2 members", "metric", "#8E8E93"),
        ],
    },
    {
        "file": "03-your-mp-everything-they-do",
        "headline": "Your MP. Everything they do.",
        "subhead": "Votes, speeches, expenses, and contact details in one feed.",
        "tab": "My MP",
        "screen": "Saanich-Gulf Islands",
        "source": "Parliament of Canada member data",
        "accent": "#003F7D",
        "content": [
            ("Vote", "Bill C-5 amendment: Nay", "timeline", "#D01D1D"),
            ("Speech", "Debated national interest projects", "timeline", "#0071E3"),
            ("Expense", "Quarterly travel disclosure", "timeline", "#E67E00"),
            ("Contact", "Hill office email and phone", "timeline", "#007D3C"),
        ],
    },
    {
        "file": "04-track-a-bill-start-to-finish",
        "headline": "Track a bill start to finish",
        "subhead": "Stages, votes, debates, and cost context stay connected.",
        "tab": "Bills",
        "screen": "Bill C-15",
        "source": "LEGISinfo and Parliament of Canada",
        "accent": "#5856D6",
        "content": [
            ("First reading", "Completed", "stage", "#007D3C"),
            ("Committee", "Completed", "stage", "#007D3C"),
            ("Third reading", "Completed", "stage", "#007D3C"),
            ("Royal Assent", "March 26, 2026", "stage", "#0071E3"),
        ],
    },
    {
        "file": "05-know-whos-influencing-your-mp",
        "headline": "Know who's influencing your MP",
        "subhead": "Lobbying communications appear beside the member profile.",
        "tab": "Lobbying",
        "screen": "Registry matches",
        "source": "Commissioner of Lobbying registry",
        "accent": "#E67E00",
        "content": [
            ("Subject", "Economic development", "row", "#0071E3"),
            ("Institution", "House of Commons", "row", "#8E8E93"),
            ("Registrant", "Monthly communication report", "row", "#E67E00"),
        ],
    },
    {
        "file": "06-contact-them-in-one-tap",
        "headline": "Contact them in one tap",
        "subhead": "Write with the vote, bill, or debate already attached.",
        "tab": "Contact",
        "screen": "Email your MP",
        "source": "Official MP contact information",
        "accent": "#00A4B0",
        "content": [
            ("To", "Member of Parliament", "compose", "#0071E3"),
            ("Subject", "Re: Bill C-5 vote record", "compose", "#5856D6"),
            ("Source", "OurCommons vote link included", "compose", "#007D3C"),
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


def text_block(lines: list[str], x: int, y: int, size: int, weight: int, color: str, gap: int) -> str:
    return "\n".join(
        f'<text x="{x}" y="{y + idx * gap}" font-family="Outfit, Helvetica Neue, Arial, sans-serif" '
        f'font-size="{size}" font-weight="{weight}" fill="{color}">{html.escape(line)}</text>'
        for idx, line in enumerate(lines)
    )


def phone_rows(scene: dict[str, object]) -> str:
    rows = []
    for idx, item in enumerate(scene["content"]):  # type: ignore[index]
        title, detail, kind, color = item
        y = 1270 + idx * 210
        if kind == "left":
            x = 192
            width = 710
            fill = "#F2F2F7"
        elif kind == "right":
            x = 385
            width = 710
            fill = "#E8F2FF"
        elif kind == "badge":
            x = 192
            width = 904
            fill = "#FFF4F2"
        else:
            x = 192
            width = 904
            fill = "#FFFFFF"
        detail_lines = wrap(str(detail), 39 if width > 800 else 32)[:2]
        detail_svg = text_block(detail_lines, x + 92, y + 100, 25, 500, "#6E6E73", 31)

        rows.append(
            f"""
            <rect x="{x}" y="{y}" width="{width}" height="166" rx="30" fill="{fill}" stroke="#E5E5EA" stroke-width="2"/>
            <circle cx="{x + 54}" cy="{y + 75}" r="20" fill="{color}"/>
            <text x="{x + 92}" y="{y + 62}" font-family="Helvetica Neue, Arial, sans-serif" font-size="33" font-weight="800" fill="#1C1C1E">{html.escape(str(title))}</text>
            {detail_svg}
            """
        )
    return "\n".join(rows)


def render(scene: dict[str, object]) -> str:
    headline = wrap(str(scene["headline"]), 18)
    subhead = wrap(str(scene["subhead"]), 34)
    headline_bottom = 392 + (len(headline) - 1) * 108
    subhead_y = headline_bottom + 100
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}" viewBox="0 0 {WIDTH} {HEIGHT}">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#07111F"/>
      <stop offset="0.62" stop-color="#142235"/>
      <stop offset="1" stop-color="{scene["accent"]}"/>
    </linearGradient>
    <filter id="shadow" x="-18%" y="-18%" width="136%" height="136%">
      <feDropShadow dx="0" dy="34" stdDeviation="28" flood-color="#000000" flood-opacity="0.36"/>
    </filter>
  </defs>
  <rect width="{WIDTH}" height="{HEIGHT}" fill="url(#bg)"/>
  <text x="92" y="150" font-family="Cooper Hewitt, Outfit, Helvetica Neue, Arial, sans-serif" font-size="46" font-weight="900" fill="#FFFFFF">epac</text>
  {text_block(headline, 92, 392, 100, 900, "#FFFFFF", 108)}
  {text_block(subhead, 96, subhead_y, 42, 500, "#DCE8F8", 56)}

  <g filter="url(#shadow)">
    <rect x="122" y="910" width="1046" height="1608" rx="96" fill="#111827"/>
    <rect x="158" y="956" width="974" height="1524" rx="72" fill="#F7F8FB"/>
    <rect x="158" y="956" width="974" height="180" rx="72" fill="{scene["accent"]}"/>
    <rect x="158" y="1046" width="974" height="90" fill="{scene["accent"]}"/>
    <text x="204" y="1068" font-family="Helvetica Neue, Arial, sans-serif" font-size="38" font-weight="800" fill="#FFFFFF">{html.escape(str(scene["tab"]))}</text>
    <text x="204" y="1196" font-family="Helvetica Neue, Arial, sans-serif" font-size="52" font-weight="900" fill="#1C1C1E">{html.escape(str(scene["screen"]))}</text>
    {phone_rows(scene)}
    <rect x="192" y="2282" width="904" height="88" rx="24" fill="#EEF5FF"/>
    <text x="232" y="2338" font-family="Helvetica Neue, Arial, sans-serif" font-size="28" font-weight="700" fill="#0071E3">Source: {html.escape(str(scene["source"]))}</text>
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
        subprocess.run(["magick", str(svg), "-depth", "8", str(png)], check=True)


if __name__ == "__main__":
    main()
