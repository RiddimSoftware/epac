#!/usr/bin/env python3
"""
Generate unique Open Graph social preview images for all riding and topic pages.
Usage: python3 generate_og_images.py
Output:
  website/og/ridings/{slug}.svg  — one per riding
  website/og/topics/{slug}.svg   — one per topic

Each SVG is 1200×630px (standard OG image size).
Also injects <meta property="og:image"> into each HTML page.
Re-run after generate_ridings.py or generate_topics.py to keep in sync.
"""

import os, re, html as html_lib

SITE_ROOT = "https://epac.riddimsoftware.com"
OG_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "og")
BLUE = "#0071e3"
DARK = "#1d1d1f"
LIGHT = "#f5f5f7"
GREY = "#6e6e73"

TOPICS = [
    ("housing",        "Housing in Parliament"),
    ("healthcare",     "Healthcare in Parliament"),
    ("climate",        "Climate Policy in Parliament"),
    ("immigration",    "Immigration in Parliament"),
    ("indigenous",     "Indigenous Affairs in Parliament"),
    ("economy",        "Economic Policy in Parliament"),
    ("defence",        "Defence Policy in Parliament"),
    ("agriculture",    "Agriculture in Parliament"),
    ("infrastructure", "Infrastructure in Parliament"),
    ("seniors",        "Seniors Policy in Parliament"),
]


def make_svg(line1: str, line2: str, tag: str) -> str:
    raw_len = len(line1)  # measure before escaping — HTML entities inflate length
    line1 = html_lib.escape(line1)
    line2 = html_lib.escape(line2)
    tag   = html_lib.escape(tag)
    font1 = 72 if raw_len <= 24 else 56 if raw_len <= 36 else 44 if raw_len <= 44 else 36
    font2 = 36
    tag_width = min(len(tag) * 14 + 32, 400)
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" viewBox="0 0 1200 630">
  <rect width="1200" height="630" fill="{LIGHT}"/>
  <rect x="0" y="0" width="8" height="630" fill="{BLUE}"/>
  <text x="60" y="72" font-family="system-ui,-apple-system,Helvetica Neue,Arial,sans-serif" font-size="28" font-weight="700" fill="{BLUE}" letter-spacing="-0.5">epac</text>
  <rect x="60" y="100" width="{tag_width}" height="36" rx="18" fill="{BLUE}" opacity="0.12"/>
  <text x="76" y="124" font-family="system-ui,-apple-system,Helvetica Neue,Arial,sans-serif" font-size="16" font-weight="600" fill="{BLUE}">{tag}</text>
  <text x="60" y="310" font-family="system-ui,-apple-system,Helvetica Neue,Arial,sans-serif" font-size="{font1}" font-weight="700" fill="{DARK}" letter-spacing="-1">{line1}</text>
  <text x="60" y="{310 + font1 + 16}" font-family="system-ui,-apple-system,Helvetica Neue,Arial,sans-serif" font-size="{font2}" font-weight="400" fill="{GREY}">{line2}</text>
  <text x="60" y="590" font-family="system-ui,-apple-system,Helvetica Neue,Arial,sans-serif" font-size="20" font-weight="400" fill="{GREY}">Track every vote, speech, and bill — free on the App Store</text>
</svg>
"""


def generate_riding_images():
    ridings_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ridings")
    out_dir = os.path.join(OG_DIR, "ridings")
    os.makedirs(out_dir, exist_ok=True)
    if not os.path.exists(ridings_dir):
        print("  ⚠️  No ridings/ directory. Run generate_ridings.py first.")
        return 0
    count = 0
    for fname in sorted(os.listdir(ridings_dir)):
        if not fname.endswith(".html") or fname == "index.html":
            continue
        slug = fname[:-5]
        content = open(os.path.join(ridings_dir, fname), encoding="utf-8").read()
        h1 = re.search(r"<h1[^>]*>(.*?)</h1>", content)
        h2 = re.search(r"<h2[^>]*>(.*?)</h2>", content)
        riding  = html_lib.unescape(h1.group(1)) if h1 else slug
        mp_name = html_lib.unescape(h2.group(1)) if h2 else ""
        with open(os.path.join(out_dir, f"{slug}.svg"), "w", encoding="utf-8") as f:
            f.write(make_svg(riding, mp_name, "Member of Parliament"))
        count += 1
    return count


def generate_mp_images():
    import shutil
    mp_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mp")
    out_dir = os.path.join(OG_DIR, "mp")
    if os.path.exists(out_dir):
        shutil.rmtree(out_dir)
    os.makedirs(out_dir, exist_ok=True)
    if not os.path.exists(mp_dir):
        print("  ⚠️  No mp/ directory. Run generate_mps.py first.")
        return 0
    count = 0
    for slug in sorted(os.listdir(mp_dir)):
        subdir = os.path.join(mp_dir, slug)
        if not os.path.isdir(subdir):
            continue
        html_path = os.path.join(subdir, "index.html")
        if not os.path.exists(html_path):
            continue
        content = open(html_path, encoding="utf-8").read()
        h1 = re.search(r"<h1[^>]*>(.*?)</h1>", content)
        h2 = re.search(r"<h2[^>]*>(.*?)</h2>", content)
        name   = html_lib.unescape(h1.group(1)) if h1 else slug
        riding = html_lib.unescape(h2.group(1)) if h2 else ""
        # Clean up riding if it's "MP for Riding Name"
        riding = riding.replace("MP for ", "").split("<")[0].strip()
        with open(os.path.join(out_dir, f"{slug}.svg"), "w", encoding="utf-8") as f:
            f.write(make_svg(name, f"MP for {riding}", "Member of Parliament"))
        count += 1
    return count


def generate_topic_images():
    out_dir = os.path.join(OG_DIR, "topics")
    os.makedirs(out_dir, exist_ok=True)
    for slug, headline in TOPICS:
        with open(os.path.join(out_dir, f"{slug}.svg"), "w", encoding="utf-8") as f:
            f.write(make_svg(headline, "Canada's Parliament · epac", "Parliamentary topic"))
    return len(TOPICS)


def inject_og_tags():
    updated = 0

    def inject(html_path, og_url):
        nonlocal updated
        content = open(html_path, encoding="utf-8").read()
        if "og:image" in content:
            return
        tag = f'  <meta property="og:image" content="{og_url}">\n'
        new_content = content.replace("</head>", tag + "</head>", 1)
        if new_content != content:
            open(html_path, "w", encoding="utf-8").write(new_content)
            updated += 1

    base = os.path.dirname(os.path.abspath(__file__))
    for subdir, tag_suffix in [("ridings", "ridings"), ("topics", "topics"), ("mp", "mp")]:
        d = os.path.join(base, subdir)
        if not os.path.exists(d):
            continue
        if subdir == "mp":
            for slug in os.listdir(d):
                subdir_path = os.path.join(d, slug)
                if os.path.isdir(subdir_path):
                    inject(os.path.join(subdir_path, "index.html"),
                           f"{SITE_ROOT}/og/mp/{slug}.svg")
        else:
            for fname in os.listdir(d):
                if not fname.endswith(".html") or fname == "index.html":
                    continue
                inject(os.path.join(d, fname),
                       f"{SITE_ROOT}/og/{tag_suffix}/{fname[:-5]}.svg")

    return updated


if __name__ == "__main__":
    print("Generating riding OG images...")
    r = generate_riding_images()
    print(f"  ✓ {r} riding images → og/ridings/")

    print("Generating MP OG images...")
    m = generate_mp_images()
    print(f"  ✓ {m} MP images → og/mp/")

    print("Generating topic OG images...")
    t = generate_topic_images()
    print(f"  ✓ {t} topic images → og/topics/")

    print("Injecting og:image tags into HTML pages...")
    u = inject_og_tags()
    print(f"  ✓ Updated {u} HTML files with og:image tags")

    print(f"\nDone. {r + m + t} SVG images generated.")
