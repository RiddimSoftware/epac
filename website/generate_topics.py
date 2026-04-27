#!/usr/bin/env python3
"""
Generate topic landing pages for epac — one per parliamentary policy area.
Usage: python3 generate_topics.py
Output: website/topics/{slug}.html + website/topics/index.html
Also updates website/sitemap.xml with new topic URLs.
Run after adding topics or changing the template.
"""

import os, re, datetime

TOPICS_DIR = os.path.join(os.path.dirname(__file__), "topics")
SITEMAP_PATH = os.path.join(os.path.dirname(__file__), "sitemap.xml")
SITE_ROOT = "https://epac.riddimsoftware.com"
APPSTORE_BASE = "https://apps.apple.com/ca/app/epac/id6739397803"

def appstore_url(topic_slug):
    return f"{APPSTORE_BASE}?utm_source=epac-web&utm_medium=topic-page&utm_content={topic_slug}&utm_campaign=organic"

TOPICS = [
    {
        "slug": "housing",
        "title": "Housing",
        "headline": "Housing in Parliament",
        "description": "Track every vote, speech, and bill related to housing affordability, rent, mortgage rates, and the federal housing strategy in Canada's House of Commons.",
        "intro": "Housing affordability is one of the most debated issues in Canada's Parliament. MPs regularly vote on legislation affecting rental markets, first-time homebuyers, foreign ownership rules, and federal housing investments. epac shows you exactly how your MP voted on each bill and what they said in the House.",
        "search_queries": ["housing parliament canada", "canadian housing bill parliament", "MP housing vote canada"],
        "keywords": "housing parliament canada, canadian housing affordability MP, parliament housing bill",
        "faq": [
            ("What housing bills has Parliament voted on?", "Parliament has voted on bills affecting foreign buyer taxes, rental protections, housing accelerator funds, and zoning reforms. epac shows every vote and which way your MP voted."),
            ("How do I track my MP's position on housing?", "Download epac, enter your postal code, and open your MP's voting record. Every housing-related vote is visible with their Yea or Nay."),
            ("Does epac show housing debate transcripts?", "Yes — every speech on housing made in the House of Commons is available in epac's Hansard chat view, searchable by topic."),
        ],
    },
    {
        "slug": "healthcare",
        "title": "Healthcare",
        "headline": "Healthcare in Parliament",
        "description": "Follow parliamentary debates and votes on Canada's healthcare system, pharmacare, dental care, mental health funding, and provincial health transfers.",
        "intro": "Federal healthcare policy in Canada encompasses pharmacare, dental care, mental health funding, the Canada Health Transfer, and pandemic preparedness. The House of Commons regularly debates the balance between federal standards and provincial jurisdiction. Track every related vote and speech in epac.",
        "search_queries": ["healthcare parliament canada", "pharmacare bill parliament", "MP healthcare vote"],
        "keywords": "healthcare parliament canada, pharmacare bill vote, dental care parliament",
        "faq": [
            ("What healthcare bills has Parliament passed?", "Parliament has passed the Canadian Dental Care Plan legislation, pharmacare framework bills, and transfers to provinces for mental health. epac shows each vote's result and your MP's position."),
            ("Can I track pharmacare debates in epac?", "Yes — search 'pharmacare' in epac to see every speech and vote on prescription drug coverage in the House of Commons."),
            ("How does epac cover the Canada Health Transfer?", "Budget votes and supply bills that include the Canada Health Transfer are indexed in epac. You can see which MPs voted for or against each transfer amount."),
        ],
    },
    {
        "slug": "climate",
        "title": "Climate",
        "headline": "Climate Policy in Parliament",
        "description": "Track federal climate legislation, carbon pricing votes, clean energy investments, and emissions reduction commitments in Canada's House of Commons.",
        "intro": "Climate change is among the most contested files in the House of Commons. Carbon pricing, the Clean Electricity Regulations, net-zero targets, and oil-and-gas policy generate some of Parliament's most contentious votes. epac shows every vote by party and by MP.",
        "search_queries": ["climate parliament canada", "carbon tax vote parliament", "clean energy bill canada parliament"],
        "keywords": "climate parliament canada, carbon tax vote MP, clean energy legislation canada",
        "faq": [
            ("How did Parliament vote on carbon pricing?", "epac shows every carbon pricing vote, including confidence motions and budget votes that included carbon pricing measures. Search 'carbon' to find them."),
            ("Can I see my MP's position on climate bills?", "Yes — open your MP's profile in epac and tap Voting Record. Climate-related votes are listed chronologically with the bill name and outcome."),
            ("Does epac cover emissions target debates?", "Every speech referencing emissions targets, net-zero, and the Canadian Net-Zero Emissions Accountability Act is searchable in epac's Hansard view."),
        ],
    },
    {
        "slug": "immigration",
        "title": "Immigration",
        "headline": "Immigration in Parliament",
        "description": "Follow parliamentary debates and votes on immigration levels, refugee policy, temporary foreign workers, and citizenship rules in Canada.",
        "intro": "Immigration levels, refugee intake, temporary foreign worker programs, and citizenship backlogs are regularly debated and voted on in Parliament. epac indexes every immigration-related Hansard speech and vote so you can see exactly where your MP stands.",
        "search_queries": ["immigration parliament canada", "immigration bill canada parliament", "MP immigration vote"],
        "keywords": "immigration parliament canada, refugee policy vote parliament, citizenship bill canada",
        "faq": [
            ("What immigration bills has Parliament voted on?", "Parliament votes on annual immigration levels plans, refugee protection legislation, and citizenship act amendments. epac shows each vote's outcome and MP positions."),
            ("How do I track refugee policy debates?", "Search 'refugee' in epac's search tab to find all relevant Hansard speeches and standing-committee references."),
            ("Can I see how my MP votes on immigration?", "Yes — in epac, your MP's full voting record is visible by issue. Immigration votes are labelled with the bill number and title."),
        ],
    },
    {
        "slug": "indigenous",
        "title": "Indigenous Affairs",
        "headline": "Indigenous Affairs in Parliament",
        "description": "Track legislation on Indigenous rights, land claims, self-governance, residential school reconciliation, and federal treaty obligations in the House of Commons.",
        "intro": "Legislation affecting First Nations, Métis, and Inuit communities includes UNDRIP implementation, self-governance agreements, residential school settlements, and First Nations child welfare. Parliament debates these issues frequently, and the votes carry significant constitutional weight. epac makes every vote and speech accessible.",
        "search_queries": ["indigenous affairs parliament canada", "UNDRIP bill parliament", "first nations legislation canada"],
        "keywords": "indigenous affairs parliament, UNDRIP bill canada, first nations self-governance vote",
        "faq": [
            ("How did Parliament vote on UNDRIP implementation?", "Bill C-15 (UNDRIP Act) passed Parliament in 2021. epac shows the recorded vote, which MPs voted which way, and subsequent implementation debates."),
            ("Can I track reconciliation legislation in epac?", "Yes — search 'reconciliation' or 'residential schools' to find all related Hansard speeches and votes indexed in epac."),
            ("Does epac cover First Nations self-governance bills?", "Self-governance agreements that require parliamentary approval are indexed in epac's bills tracker with full voting records."),
        ],
    },
    {
        "slug": "economy",
        "title": "Economy",
        "headline": "Economic Policy in Parliament",
        "description": "Follow federal budget votes, inflation policy, Bank of Canada oversight debates, trade agreements, and economic competitiveness legislation in Parliament.",
        "intro": "Federal budget bills, trade agreements, competitiveness legislation, and debates about Canada's economic direction are central to Parliament's work. epac tracks every budget vote and economic bill so you can see how your MP voted on each measure.",
        "search_queries": ["federal budget parliament canada", "economic policy parliament vote", "trade deal parliament canada"],
        "keywords": "federal budget vote parliament, economic competitiveness bill canada, trade agreement parliament",
        "faq": [
            ("Can I see how my MP voted on the federal budget?", "Yes — every budget implementation act is in epac's bills tracker with a full recorded vote. Open your MP's profile to see their Yea or Nay."),
            ("Does epac track trade agreement debates?", "Parliamentary debates on trade agreements, including CUSMA/USMCA ratification and new trade deals, are indexed in epac's Hansard view."),
            ("How do I track inflation and interest rate debates?", "Search 'inflation' or 'Bank of Canada' in epac to find every relevant speech and committee reference in the House of Commons."),
        ],
    },
    {
        "slug": "defence",
        "title": "Defence",
        "headline": "Defence Policy in Parliament",
        "description": "Track parliamentary votes and debates on Canada's military spending, NATO commitments, defence procurement, and veterans' affairs.",
        "intro": "Canada's defence spending commitments, military procurement decisions, NATO obligations, and veterans' benefit legislation are regularly debated and voted on in the House of Commons. epac shows every defence-related bill and vote.",
        "search_queries": ["defence parliament canada", "military spending vote parliament", "NATO commitment canada parliament"],
        "keywords": "defence parliament canada, military spending vote, NATO 2% GDP parliament debate",
        "faq": [
            ("How has Parliament voted on defence spending increases?", "Defence spending commitments are embedded in budget votes. epac shows which MPs voted for or against each budget that included defence funding changes."),
            ("Can I track veterans' benefit legislation?", "Yes — search 'veterans' in epac to find all related bills, votes, and Hansard speeches on veterans' pensions, services, and benefits."),
            ("Does epac cover military procurement debates?", "Major procurement debates (ships, fighter jets, etc.) are among the most extensively debated topics in Parliament — all indexed and searchable in epac."),
        ],
    },
    {
        "slug": "agriculture",
        "title": "Agriculture",
        "headline": "Agriculture in Parliament",
        "description": "Follow parliamentary votes and debates on farm support programs, supply management, fertilizer policy, and food security legislation in Canada.",
        "intro": "Canada's agricultural sector — dairy supply management, grain marketing, fertilizer policy, and farm income support — generates significant parliamentary activity. MPs from rural ridings are particularly active on these files. epac tracks every related vote and speech.",
        "search_queries": ["agriculture parliament canada", "supply management vote parliament", "farm bill canada parliament"],
        "keywords": "agriculture parliament canada, supply management bill vote, farm income support parliament",
        "faq": [
            ("How did Parliament vote on supply management?", "Supply management is regularly debated in trade agreement ratification votes. epac shows every vote where supply management protections were at stake."),
            ("Can I track fertilizer policy debates in epac?", "Yes — search 'fertilizer' or 'carbon pricing farm' to find all relevant Hansard speeches and committee testimony indexed in epac."),
            ("Does epac cover AgriStability and farm support programs?", "Budget votes that include AgriStability, AgriInvest, and other farm income programs are tracked in epac's bills and votes view."),
        ],
    },
    {
        "slug": "infrastructure",
        "title": "Infrastructure",
        "headline": "Infrastructure in Parliament",
        "description": "Track federal infrastructure funding votes, transit investments, broadband rollout legislation, and major project approvals in Canada's Parliament.",
        "intro": "Federal infrastructure spending — transit, broadband, bridges, and green infrastructure — requires parliamentary approval through budget bills. epac tracks every infrastructure-related vote and the Hansard debates behind each funding decision.",
        "search_queries": ["infrastructure parliament canada", "transit funding vote parliament", "broadband bill canada parliament"],
        "keywords": "infrastructure parliament canada, transit funding vote, broadband investment bill canada",
        "faq": [
            ("How does Parliament vote on infrastructure spending?", "Infrastructure spending is approved through budget implementation acts and supplementary estimates. epac shows every vote and which MPs supported or opposed each measure."),
            ("Can I track broadband rollout legislation?", "Universal broadband fund announcements and CRTC oversight bills are indexed in epac. Search 'broadband' or 'internet' to find related debates."),
            ("Does epac cover transit funding debates?", "Yes — federal transit funding, including the Canada Public Transit Fund and urban transit agreements, is covered in epac's Hansard and bills views."),
        ],
    },
    {
        "slug": "seniors",
        "title": "Seniors",
        "headline": "Seniors Policy in Parliament",
        "description": "Track Old Age Security increases, CPP changes, long-term care standards, and seniors' benefits legislation in Canada's House of Commons.",
        "intro": "Legislation affecting Canada's seniors includes Old Age Security (OAS) and Canada Pension Plan (CPP) adjustments, national long-term care standards, and Guaranteed Income Supplement (GIS) changes. These are among the most impactful votes for millions of Canadians. epac makes every related vote transparent.",
        "search_queries": ["seniors parliament canada", "OAS CPP vote parliament", "long-term care bill canada"],
        "keywords": "seniors parliament canada, OAS increase vote, CPP legislation parliament canada",
        "faq": [
            ("How did Parliament vote on OAS increases?", "OAS adjustments are included in budget implementation acts. epac shows every vote and your MP's position on each measure affecting Old Age Security."),
            ("Does epac track CPP expansion legislation?", "Yes — CPP enhancement bills and related votes are indexed in epac's bills tracker with the full recorded vote breakdown."),
            ("Can I follow long-term care standards debates?", "Federal long-term care standards and the Safe Long-Term Care Act debates are searchable in epac. Search 'long-term care' or 'LTC' to find them."),
        ],
    },
]

def faq_schema(faqs, slug):
    pairs = ",\n      ".join(
        f'{{"@type":"Question","name":{json_str(q)},"acceptedAnswer":{{"@type":"Answer","text":{json_str(a)}}}}}'
        for q, a in faqs
    )
    return f"""{{
    "@context": "https://schema.org",
    "@type": "FAQPage",
    "mainEntity": [
      {pairs}
    ]
  }}"""

def json_str(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'

def html_for_topic(t):
    slug = t["slug"]
    title = t["title"]
    headline = t["headline"]
    desc = t["description"]
    intro = t["intro"]
    faqs = t["faq"]
    store_url = appstore_url(slug)

    faq_html = "\n".join(
        f"""    <div>
      <h3>{q}</h3>
      <p>{a}</p>
    </div>"""
        for q, a in faqs
    )

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{headline} — epac</title>
  <meta name="description" content="{desc}">
  <meta name="keywords" content="{t['keywords']}">
  <meta property="og:title" content="{headline} — epac">
  <meta property="og:description" content="{desc}">
  <meta property="og:type" content="website">
  <meta property="og:url" content="{SITE_ROOT}/topics/{slug}.html">
  <link rel="stylesheet" href="../default.css">
  <script type="application/ld+json">
  {faq_schema(faqs, slug)}
  </script>
</head>
<body>
  <nav class="nav"><div class="nav-left"><a href="/" class="wordmark">epac</a></div></nav>
  <main style="max-width:680px;margin:0 auto;padding:2rem 1.5rem">
    <p style="color:#888;font-size:.875rem;margin-bottom:.5rem">Parliamentary policy area</p>
    <h1 style="margin:0 0 1.5rem">{headline}</h1>
    <p style="font-size:1.1rem;line-height:1.7">{intro}</p>
    <a href="{store_url}" style="display:inline-block;margin:1.5rem 0;padding:.875rem 2rem;background:#0071e3;color:#fff;border-radius:12px;text-decoration:none;font-weight:600">Track {title} in epac — free</a>

    <h2 style="margin-top:3rem">Frequently asked questions</h2>
{faq_html}

    <h2 style="margin-top:3rem">About epac</h2>
    <p>epac is a free iOS app that displays Canada's House of Commons Hansard debates, voting records, and MP expenditures using only data published by the Government of Canada. No editorial bias — just the parliamentary record.</p>
    <a href="{store_url}" style="display:inline-block;margin:1rem 0;padding:.75rem 1.75rem;background:#0071e3;color:#fff;border-radius:12px;text-decoration:none;font-weight:600">Download epac</a>

    <p style="font-size:.8rem;color:#888;margin-top:3rem">Data source: Parliament of Canada (Hansard, LEGISinfo, Open Government). epac is not affiliated with or endorsed by any government body.</p>
  </main>
  <footer style="text-align:center;padding:2rem;color:#888;font-size:.8rem;opacity:.6">
    <p><a href="/">epac</a> &middot; <a href="/topics/">Topics</a> &middot; <a href="/ridings/">Ridings</a> &middot; <a href="/blog/">Blog</a> &middot; <a href="{store_url}">App Store</a></p>
  </footer>
</body>
</html>"""

def generate():
    os.makedirs(TOPICS_DIR, exist_ok=True)
    today = datetime.date.today().isoformat()
    slugs = []

    print(f"Generating {len(TOPICS)} topic pages...")
    for t in TOPICS:
        slug = t["slug"]
        path = os.path.join(TOPICS_DIR, f"{slug}.html")
        with open(path, "w", encoding="utf-8") as f:
            f.write(html_for_topic(t))
        slugs.append((t["title"], slug))
        print(f"  ✓ topics/{slug}.html")

    # Index page
    cards = "\n".join(
        f'    <li><a href="/topics/{slug}.html">{title}</a></li>'
        for title, slug in slugs
    )
    index_html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Parliamentary Topics — epac</title>
  <meta name="description" content="Track housing, healthcare, climate, immigration, and more parliamentary policy areas in Canada's House of Commons using epac.">
  <link rel="stylesheet" href="../default.css">
</head>
<body>
  <nav class="nav"><div class="nav-left"><a href="/" class="wordmark">epac</a></div></nav>
  <main style="max-width:680px;margin:0 auto;padding:2rem 1.5rem">
    <h1>Parliamentary Topics</h1>
    <p>Follow the issues that matter to you. Each topic page shows what Parliament has done — every vote, every speech — available in the epac app.</p>
    <ul style="font-size:1.1rem;line-height:2.2;list-style:disc;padding-left:1.5rem">
{cards}
    </ul>
    <p style="margin-top:2rem"><a href="https://apps.apple.com/ca/app/epac/id6739397803" style="display:inline-block;padding:.875rem 2rem;background:#0071e3;color:#fff;border-radius:12px;text-decoration:none;font-weight:600">Download epac — free</a></p>
  </main>
  <footer style="text-align:center;padding:2rem;color:#888;font-size:.8rem;opacity:.6">
    <p><a href="/">epac</a> &middot; <a href="/ridings/">Ridings</a> &middot; <a href="/blog/">Blog</a></p>
  </footer>
</body>
</html>"""
    with open(os.path.join(TOPICS_DIR, "index.html"), "w", encoding="utf-8") as f:
        f.write(index_html)
    print("  ✓ topics/index.html")

    # Patch sitemap.xml — insert topic URLs before </urlset>
    new_entries = "\n".join(
        f"""  <url>
    <loc>{SITE_ROOT}/topics/{slug}.html</loc>
    <lastmod>{today}</lastmod>
    <changefreq>monthly</changefreq>
    <priority>0.7</priority>
  </url>"""
        for _, slug in slugs
    )
    new_entries += f"""
  <url>
    <loc>{SITE_ROOT}/topics/</loc>
    <lastmod>{today}</lastmod>
    <changefreq>monthly</changefreq>
    <priority>0.8</priority>
  </url>"""

    with open(SITEMAP_PATH, "r", encoding="utf-8") as f:
        sitemap = f.read()

    # Remove any existing topic entries to avoid duplicates on re-run
    import re
    sitemap = re.sub(
        r'\s*<url>\s*<loc>[^<]*/topics/[^<]*</loc>.*?</url>',
        '', sitemap, flags=re.DOTALL
    )
    sitemap = sitemap.replace("</urlset>", new_entries + "\n</urlset>")

    with open(SITEMAP_PATH, "w", encoding="utf-8") as f:
        f.write(sitemap)
    print(f"  ✓ sitemap.xml updated ({len(slugs) + 1} topic URLs added)")

    print(f"\nDone. Generated {len(TOPICS)} topic pages + index.html")

if __name__ == "__main__":
    generate()
