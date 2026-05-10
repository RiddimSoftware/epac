#!/usr/bin/env python3
"""
Generate 338 federal MP landing pages for epac.
Usage: python3 generate_mps.py
Output: website/mp/{slug}/index.html for each MP
"""

import json, os, re, urllib.request, ssl, csv
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor

MEMBERS_URL = "https://www.ourcommons.ca/Members/en/search/XML?parliament=all&caucusId=all&province=all&gender=all"
API_BASE = "https://api.epac.riddimsoftware.com/api/v1"
MP_DIR = os.path.join(os.path.dirname(__file__), "mp")
CACHE_DIR = os.path.join(os.path.dirname(__file__), ".cache")
APPSTORE_URL_BASE = "https://apps.apple.com/ca/app/epac/id1224459142"
SITE_ROOT = "https://epac.riddimsoftware.com"

# SSL context to bypass cert verification for some govt sites
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

def appstore_url(slug: str) -> str:
    return f"{APPSTORE_URL_BASE}?ct=epac-web-mp&mt=8&utm_source=epac-web&utm_medium=mp-page&utm_content={slug}&utm_campaign=organic"

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
    import xml.etree.ElementTree as ET
    try:
        with urllib.request.urlopen(MEMBERS_URL, timeout=30, context=ctx) as r:
            tree = ET.parse(r)
        members = []
        for m in tree.findall(".//MemberOfParliament"):
            to_date = m.find("ToDateTime")
            is_current = to_date is not None and to_date.get("{http://www.w3.org/2001/XMLSchema-instance}nil") == "true"
            
            if not is_current:
                continue

            fn = (m.findtext("PersonOfficialFirstName") or "").strip()
            ln = (m.findtext("PersonOfficialLastName") or "").strip()
            riding = (m.findtext("ConstituencyName") or "").strip()
            province = (m.findtext("ConstituencyProvinceTerritoryName") or "").strip()
            party = (m.findtext("CaucusShortName") or "").strip()
            person_id = (m.findtext("PersonId") or "").strip()
            from_date = (m.findtext("FromDateTime") or "").strip()
            
            if fn and ln and riding:
                members.append({
                    "id": person_id,
                    "first": fn,
                    "last": ln,
                    "name": f"{fn} {ln}",
                    "riding": riding,
                    "province": province,
                    "party": party,
                    "from_date": from_date,
                    "slug": slugify(f"{fn} {ln}")
                })
        return members
    except Exception as e:
        print(f"Error fetching members: {e}")
        return []

def fetch_json(url):
    cache_key = re.sub(r'[^a-z0-9]', '_', url.lower())
    cache_path = os.path.join(CACHE_DIR, f"{cache_key}.json")
    
    if os.path.exists(cache_path):
        # Check if cache is fresh (1 day)
        if (datetime.now() - datetime.fromtimestamp(os.path.getmtime(cache_path))).days < 1:
            with open(cache_path, 'r') as f:
                return json.load(f)

    try:
        with urllib.request.urlopen(url, timeout=10, context=ctx) as r:
            data = json.loads(r.read().decode('utf-8'))
            with open(cache_path, 'w') as f:
                json.dump(data, f)
            return data
    except Exception as e:
        return None

def fetch_expenditures():
    # Attempt to fetch the latest summary CSV
    # For now, we'll try 2025 Q4 as a fallback
    url = "https://www.ourcommons.ca/proactivedisclosure/en/members/2025/4"
    # Scrape the page for the CSV link
    # This is a bit complex for a static generator, so we'll use a known pattern if possible
    # or mock it if we can't hit the network reliably.
    
    # Mocking for implementation speed, but could be real
    return {}

def fetch_mp_data(mp):
    person_id = mp["id"]
    votes = fetch_json(f"{API_BASE}/members/{person_id}/votes")
    speeches = fetch_json(f"{API_BASE}/members/{person_id}/speeches")
    return {
        "votes": votes.get("votes", [])[:10] if votes else [],
        "speeches": speeches.get("speeches", [])[:5] if speeches else []
    }

def html_for_mp(mp, data):
    name = mp["name"]
    riding = mp["riding"]
    party = mp["party"]
    province = mp["province"]
    slug = mp["slug"]
    riding_slug = slugify(riding)
    
    from_year = ""
    if mp.get("from_date"):
        try:
            # Format is usually YYYY-MM-DDTHH:MM:SS
            from_year = mp["from_date"].split("-")[0]
        except:
            pass
    term = f"Member of Parliament since {from_year}" if from_year else "Current Member of Parliament"
    
    photo_url = f"https://www.ourcommons.ca/MemberIdImages/Official/{mp['id']}.jpg"
    
    votes_html = ""
    if data["votes"]:
        votes_html = '<h3 style="margin-top:2rem">Recent Votes</h3><ul style="list-style:none;padding:0">'
        for v in data["votes"]:
            date = v.get("date", "")
            desc = v.get("description", v.get("description_en", "No description"))
            result = v.get("recorded_vote", "Voted")
            color = "#1d1d1f"
            if result == "Yea": color = "#28a745"
            elif result == "Nay": color = "#dc3545"
            votes_html += f'<li style="margin-bottom:1rem;padding-bottom:1rem;border-bottom:1px solid #eee"><span style="font-weight:700;color:{color}">{result}</span> — {desc} <div style="font-size:.75rem;color:#888;margin-top:.25rem">{date}</div></li>'
        votes_html += "</ul>"
    else:
        votes_html = '<h3 style="margin-top:2rem">Recent Votes</h3><p style="color:#666">No recent voting records found for this member in the current session.</p>'

    speeches_html = ""
    if data["speeches"]:
        speeches_html = '<h3 style="margin-top:2rem">Recent Speeches</h3><ul style="list-style:none;padding:0">'
        for s in data["speeches"]:
            date = s.get("sitting_date", "")
            subject = s.get("subject_title", "General Debate")
            preview = s.get("preview", "")
            speeches_html += f'<li style="margin-bottom:1.5rem"><strong>{subject}</strong> <span style="font-size:.75rem;color:#888">({date})</span><p style="font-size:.9rem;color:#444;margin-top:.5rem;line-height:1.5">{preview}...</p></li>'
        speeches_html += "</ul>"
    else:
        speeches_html = '<h3 style="margin-top:2rem">Recent Speeches</h3><p style="color:#666">No recent speeches found in the official Hansard record.</p>'

    desc = f"Track {name}, MP for {riding}, in the House of Commons. Recent votes, speeches, and expenditures from official parliamentary records."
    
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
{open_in_app_head(f"/mp/{slug}/")}
  <title>{name} — MP for {riding} — epac</title>
  <meta name="description" content="{desc}">
  <link rel="stylesheet" href="../../default.css">
  <link rel="canonical" href="{SITE_ROOT}/mp/{slug}/">
  <style>
    .mp-content h3 {{ font-size: 1.25rem; margin-bottom: 1.5rem; border-bottom: 2px solid #0071e3; display: inline-block; padding-bottom: 4px; }}
    @media (max-width: 768px) {{ .mp-content {{ grid-template-columns: 1fr !important; gap: 2rem !important; }} }}
  </style>
</head>
<body>
  <nav class="nav"><div class="nav-left"><a href="/" class="wordmark">epac</a></div></nav>
  <main style="max-width:900px;margin:0 auto;padding:2rem 1.5rem">
    <div style="display:flex;gap:2.5rem;align-items:center;margin-bottom:4rem" class="mp-header">
      <img src="{photo_url}" alt="{name}" style="width:180px;height:225px;object-fit:cover;border-radius:16px;background:#eee;box-shadow:0 8px 24px rgba(0,0,0,0.12)">
      <div>
        <p style="color:#0071e3;font-size:.875rem;margin-bottom:.5rem;font-weight:700;text-transform:uppercase;letter-spacing:0.1em">{party} · {province}</p>
        <h1 style="margin:0 0 .5rem;font-size:3rem;letter-spacing:-0.02em">{name}</h1>
        <h2 style="font-weight:400;font-size:1.5rem;margin:0 0 1rem;color:#444">Member of Parliament for <a href="/ridings/{riding_slug}.html" style="color:#0071e3;text-decoration:none;border-bottom:1px solid rgba(0,113,227,0.2)">{riding}</a></h2>
        <p style="color:#888;margin-bottom:2rem;font-size:1rem">{term}</p>
        <a href="{appstore_url(slug)}" class="btn-primary" style="display:inline-block;padding:1rem 2rem;background:#0071e3;color:#fff;border-radius:14px;text-decoration:none;font-weight:700;box-shadow:0 4px 14px rgba(0,113,227,0.3);transition:transform 0.2s">Open in epac app</a>
      </div>
    </div>
    
    <div class="mp-content" style="display:grid;grid-template-columns:1.2fr 1fr;gap:4rem">
      <section>
        {votes_html}
        <p style="font-size:.7rem;color:#aaa;margin-top:2rem">Source: <a href="https://api.open.ourcommons.ca" style="color:inherit">House of Commons Open Data</a></p>
      </section>

      <div>
        <section>
          {speeches_html}
          <p style="font-size:.7rem;color:#aaa;margin-top:2rem">Source: <a href="https://www.ourcommons.ca/en/parliamentary-business/hansard" style="color:inherit">Hansard</a></p>
        </section>

        <section style="margin-top:4rem;padding:2rem;background:#f5f5f7;border-radius:20px">
          <h3 style="margin-top:0">Expenditures</h3>
          <p style="font-size:1rem;line-height:1.6;color:#333">Member office, travel, and hospitality expenses are published by the Board of Internal Economy. View the latest detailed breakdown for {name} in the epac app.</p>
          <p style="font-size:.7rem;color:#aaa;margin-top:1.5rem">Source: <a href="https://www.ourcommons.ca/ProactiveDisclosure/en/members" style="color:inherit">Proactive Disclosure</a></p>
        </section>
      </div>
    </div>

    <div style="background:linear-gradient(135deg, #1d1d1f, #333);padding:4rem 2rem;border-radius:32px;text-align:center;margin-top:6rem;color:#fff;box-shadow:0 20px 40px rgba(0,0,0,0.1)">
      <h2 style="margin:0 0 1rem;font-size:2.5rem;letter-spacing:-0.02em">Track {name} on your iPhone</h2>
      <p style="font-size:1.25rem;opacity:0.8;margin-bottom:2.5rem;max-width:600px;margin-left:auto;margin-right:auto">Get instant notifications when {name} votes or speaks in the House. Follow the bills and topics that matter to you most.</p>
      <a href="{appstore_url(slug)}" style="display:inline-block;padding:1.25rem 3rem;background:#fff;color:#1d1d1f;border-radius:18px;text-decoration:none;font-weight:800;font-size:1.25rem;box-shadow:0 4px 20px rgba(0,0,0,0.2)">Download epac — Free</a>
    </div>

  </main>
  <footer style="text-align:center;padding:8rem 2rem 4rem;color:#888;font-size:.875rem">
    <p style="margin-bottom:2rem"><a href="/" style="color:inherit;text-decoration:none">epac</a> &middot; <a href="/blog/" style="color:inherit;text-decoration:none">Blog</a> &middot; <a href="/ridings/" style="color:inherit;text-decoration:none">Ridings</a> &middot; <a href="/mp/" style="color:inherit;text-decoration:none">MPs</a> &middot; <a href="/privacy.html" style="color:inherit;text-decoration:none">Privacy</a></p>
    <p style="opacity:0.5;max-width:600px;margin:0 auto;line-height:1.5">epac is a non-partisan civic engagement tool using official data from the Parliament of Canada. We are not affiliated with any government body.</p>
  </footer>
</body>
</html>"""

def update_sitemap(mps):
    path = os.path.join(os.path.dirname(__file__), "sitemap.xml")
    if not os.path.exists(path): return
    
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    if "</urlset>" not in content: return
    
    # Remove existing /mp/ entries to avoid duplication
    content = re.sub(r'  <url>\s+<loc>https://epac\.riddimsoftware\.com/mp/.*?</url>\n', '', content, flags=re.DOTALL)
    
    urls = []
    # Add MP index
    urls.append(f"""  <url>
    <loc>{SITE_ROOT}/mp/</loc>
    <changefreq>weekly</changefreq>
    <priority>0.7</priority>
  </url>""")
    
    # Add each MP
    for name, slug in mps:
        urls.append(f"""  <url>
    <loc>{SITE_ROOT}/mp/{slug}/</loc>
    <changefreq>daily</changefreq>
    <priority>0.6</priority>
  </url>""")
    
    new_content = content.replace("</urlset>", "\n".join(urls) + "\n</urlset>")
    with open(path, 'w', encoding='utf-8') as f:
        f.write(new_content)

def generate():
    import shutil
    if os.path.exists(MP_DIR):
        shutil.rmtree(MP_DIR)
    os.makedirs(MP_DIR, exist_ok=True)
    os.makedirs(CACHE_DIR, exist_ok=True)
    print("Fetching member list...")
    members = fetch_members()
    
    import sys
    limit = None
    if len(sys.argv) > 1:
        limit = int(sys.argv[1])
    
    if limit:
        members = members[:limit]
    
    print(f"Found {len(members)} members.")
    
    # Sort for consistent index
    members = sorted(members, key=lambda m: m["last"])
    
    def process_mp(m):
        slug = m["slug"]
        data = fetch_mp_data(m)
        
        mp_path = os.path.join(MP_DIR, slug)
        os.makedirs(mp_path, exist_ok=True)
        
        path = os.path.join(mp_path, "index.html")
        with open(path, "w", encoding="utf-8") as f:
            f.write(html_for_mp(m, data))
        return (m["name"], slug)

    print(f"Generating {len(members)} MP pages (using threads)...")
    with ThreadPoolExecutor(max_workers=20) as executor:
        results = list(executor.map(process_mp, members))

    # Generate index
    rows = "\n".join(
        f'<li><a href="/mp/{slug}/">{name}</a></li>'
        for name, slug in results
    )
    index = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Members of Parliament — epac</title>
  <meta name="description" content="Track all 338 sitting Members of Parliament in Canada. View recent votes, speeches, and expenditures.">
  <link rel="stylesheet" href="../default.css">
  <meta name="apple-itunes-app" content="app-id=1224459142, app-argument=https://epac.riddimsoftware.com/app/?path=%2Fmp%2F">
  <script defer src="/open-in-app.js"></script>
</head>
<body>
  <nav class="nav"><div class="nav-left"><a href="/" class="wordmark">epac</a></div></nav>
  <main style="max-width:800px;margin:0 auto;padding:2rem 1.5rem">
    <h1>Members of Parliament</h1>
    <p>Select an MP below to view their recent parliamentary activity, including votes and speeches.</p>
    <ul style="column-count:2;column-gap:2rem;list-style:disc;padding-left:1.5rem;line-height:2;margin-top:2rem">
{rows}
    </ul>
  </main>
</body>
</html>"""
    with open(os.path.join(MP_DIR, "index.html"), "w", encoding="utf-8") as f:
        f.write(index)
        
    print("Updating sitemap...")
    update_sitemap(results)
    
    print(f"Done. Generated {len(members)} MP pages + index.html")

if __name__ == "__main__":
    generate()
