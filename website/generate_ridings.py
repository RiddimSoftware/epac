#!/usr/bin/env python3
"""
Generate 338 federal electoral district landing pages for epac.
Usage: python3 generate_ridings.py
Output: website/ridings/{slug}.html for each riding + website/ridings/index.html
Run again after an election to refresh all pages.
"""

import json, os, re, urllib.request

MEMBERS_URL = "https://www.ourcommons.ca/Members/en/search/XML?parliament=all&caucusId=all&province=all&gender=all"
RIDINGS_DIR = os.path.join(os.path.dirname(__file__), "ridings")
APPSTORE_URL_BASE = "https://apps.apple.com/ca/app/epac/id1224459142"

def appstore_url(slug: str) -> str:
    return f"{APPSTORE_URL_BASE}?ct=epac-web-riding&mt=8&utm_source=epac-web&utm_medium=riding-page&utm_content={slug}&utm_campaign=organic"

def open_in_app_head(path: str) -> str:
    from urllib.parse import quote
    encoded = quote(path, safe="")
    return f"""  <meta name="apple-itunes-app" content="app-id=1224459142, app-argument=https://epac.riddimsoftware.com/app/?path={encoded}">
  <script defer src="/open-in-app.js"></script>"""

def slugify(s):
    s = s.lower().strip()
    s = re.sub(r"[àáâãäå]", "a", s)
    s = re.sub(r"[èéêë]", "e", s)
    s = re.sub(r"[ìíîï]", "i", s)
    s = re.sub(r"[òóôõö]", "o", s)
    s = re.sub(r"[ùúûü]", "u", s)
    s = re.sub(r"[ç]", "c", s)
    s = re.sub(r"[^a-z0-9\s-]", "", s)
    s = re.sub(r"[\s]+", "-", s)
    return s

def fetch_members():
    # Parse the OurCommons XML members feed
    import xml.etree.ElementTree as ET
    import ssl
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    with urllib.request.urlopen(MEMBERS_URL, timeout=30, context=ctx) as r:
        tree = ET.parse(r)
    members = []
    for m in tree.findall(".//MemberOfParliament"):
        fn = (m.findtext("PersonOfficialFirstName") or "").strip()
        ln = (m.findtext("PersonOfficialLastName") or "").strip()
        riding = (m.findtext("ConstituencyName") or "").strip()
        province = (m.findtext("ConstituencyProvinceTerritoryName") or "").strip()
        party = (m.findtext("CaucusShortName") or "").strip()
        if fn and ln and riding:
            members.append({"first": fn, "last": ln, "name": f"{fn} {ln}",
                            "riding": riding, "province": province, "party": party})
    return members

def html_for_riding(member):
    riding = member["riding"]
    mp_name = member["name"]
    party = member["party"]
    province = member["province"]
    slug = slugify(riding)
    desc = f"{mp_name} represents {riding} in the House of Commons. Track their votes, speeches, and expenses in epac — the free iOS app for Canadian civic engagement."
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
{open_in_app_head(f"/ridings/{slug}.html")}
  <title>{riding} — {mp_name} — epac</title>
  <meta name="description" content="{desc}">
  <link rel="stylesheet" href="../default.css">
  <script type="application/ld+json">
  {{
    "@context": "https://schema.org",
    "@graph": [
      {{
        "@type": "Person",
        "name": "{mp_name}",
        "jobTitle": "Member of Parliament",
        "memberOf": {{ "@type": "GovernmentOrganization", "name": "House of Commons of Canada" }}
      }},
      {{
        "@type": "GovernmentOrganization",
        "name": "{riding}",
        "description": "Federal electoral district represented by {mp_name}",
        "address": {{ "@type": "PostalAddress", "addressRegion": "{province}", "addressCountry": "CA" }}
      }}
    ]
  }}
  </script>
</head>
<body>
  <nav class="nav"><div class="nav-left"><a href="/" class="wordmark">epac</a></div></nav>
  <main style="max-width:680px;margin:0 auto;padding:2rem 1.5rem">
    <p style="color:#888;font-size:.875rem;margin-bottom:.5rem">{province} · {party}</p>
    <h1 style="margin:0 0 .25rem">{riding}</h1>
    <h2 style="font-weight:400;font-size:1.5rem;margin:0 0 2rem">{mp_name}</h2>
    <p>Track {mp_name}'s votes, speeches, expenses, and lobbyist connections in the epac app — using only data published by the Government of Canada.</p>
    <a href="{appstore_url(slug)}" style="display:inline-block;margin:1.5rem 0;padding:.875rem 2rem;background:#0071e3;color:#fff;border-radius:12px;text-decoration:none;font-weight:600">Download epac — free</a>
    <p style="font-size:.8rem;color:#888;margin-top:3rem">Data source: Parliament of Canada. epac is not affiliated with or endorsed by any government body.</p>
  </main>
  <footer style="text-align:center;padding:2rem;color:#888;font-size:.8rem;opacity:.6">
    <p><a href="/">epac</a> &middot; <a href="/blog/">Blog</a> &middot; <a href="/press.html">Press</a> &middot; <a href="{appstore_url(slug)}">App Store</a></p>
  </footer>
</body>
</html>"""

def generate():
    os.makedirs(RIDINGS_DIR, exist_ok=True)
    print("Fetching member list...")
    members = fetch_members()
    # Deduplicate by riding (keep current member for each riding)
    seen = {}
    for m in members:
        seen[m["riding"]] = m
    members = sorted(seen.values(), key=lambda m: m["riding"])
    print(f"Generating {len(members)} riding pages...")
    slugs = []
    for m in members:
        slug = slugify(m["riding"])
        path = os.path.join(RIDINGS_DIR, f"{slug}.html")
        with open(path, "w", encoding="utf-8") as f:
            f.write(html_for_riding(m))
        slugs.append((m["riding"], m["name"], slug))
    # Generate index
    rows = "\n".join(
        f'<li><a href="/ridings/{slug}.html">{riding}</a> — {name}</li>'
        for riding, name, slug in slugs
    )
    index = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
{open_in_app_head("/ridings/")}
  <title>338 Federal Ridings — epac</title>
  <meta name="description" content="All 338 federal electoral districts in Canada. Find your MP and track their votes in epac.">
  <link rel="stylesheet" href="../default.css">
</head>
<body>
  <nav class="nav"><div class="nav-left"><a href="/" class="wordmark">epac</a></div></nav>
  <main style="max-width:800px;margin:0 auto;padding:2rem 1.5rem">
    <h1>338 Federal Electoral Districts</h1>
    <p>Find your riding and MP below. Tap any riding to see their parliamentary activity.</p>
    <ul style="column-count:2;column-gap:2rem;list-style:disc;padding-left:1.5rem;line-height:2">
{rows}
    </ul>
  </main>
</body>
</html>"""
    with open(os.path.join(RIDINGS_DIR, "index.html"), "w", encoding="utf-8") as f:
        f.write(index)
    print(f"Done. Generated {len(members)} pages + index.html")
    return slugs

if __name__ == "__main__":
    generate()
