# epac Monthly Growth Report — Template

> Copy this file to `docs/marketing/reports/YYYY-MM.md`, fill in every cell, and commit.
> Review on the last Friday of each month (30 min; part of Sprint Review).

---

## Period: YYYY-MM (Month Year)

Prepared by: [name]  
Date: YYYY-MM-DD

---

## App Store Connect (Analytics → Overview)

| Metric | This month | Last month | 3-month avg | Target |
|--------|-----------|-----------|-------------|--------|
| Impressions | | | | — |
| Product page views | | | | — |
| **Conversion rate** (downloads ÷ views) | | | | ≥ 3% |
| Total installs | | | | MoM growth |
| D7 retention | | | | ≥ 30% |
| D28 retention | | | | ≥ 15% |
| Average rating | | | | ≥ 4.5 |
| Rating count | | | | growing |

### Installs by source (Analytics → Acquisition → Source Type)

| Source | Installs | Conversion rate | Notes |
|--------|---------|----------------|-------|
| App Store Search | | | |
| App Store Browse | | | |
| Web Referral | | | |
| App Referral | | | |
| Campaign Links — riding pages (`epac-web-riding`) | | | |
| Campaign Links — newsletter (`epac-newsletter`) | | | |
| Campaign Links — social (`epac-bluesky`, `epac-twitter`) | | | |
| Campaign Links — Product Hunt (`epac-product-hunt`) | | | |
| Campaign Links — welcome sequence (`epac-newsletter-welcome`) | | | |

### Top 5 App Store search terms (Analytics → Acquisition → App Store Search)

1. [term] — [impressions] impressions
2. [term] — [impressions] impressions
3. [term] — [impressions] impressions
4. [term] — [impressions] impressions
5. [term] — [impressions] impressions

---

## Website — Google Search Console (last 28 days)

| Metric | This month | Last month | Notes |
|--------|-----------|-----------|-------|
| Total search clicks | | | |
| Total search impressions | | | |
| Average CTR | | | |
| Average position | | | |
| Riding pages — total clicks | | | |
| Topic pages — total clicks | | | |
| Pages indexed | | | target: 338+ riding + topic + main |

---

## Product Hunt Launch

Fill this section only in a Product Hunt launch month.

| Metric | Value | Notes |
|--------|-------|-------|
| Launch URL | | |
| Launch date | | |
| End-of-day rank | | |
| Upvotes | | |
| Comments | | |
| Product Hunt referral sessions | | |
| App Store installs via `epac-product-hunt` | | |
| Product page conversion rate on launch day | | |

### Product Hunt feedback themes

1. [theme]
2. [theme]
3. [theme]

### Top 5 queries by clicks

1. [query] — [clicks] clicks, position [x]
2.
3.
4.
5.

### Top 5 pages by clicks

1. [URL] — [clicks] clicks
2.
3.
4.
5.

---

## Interpretation guide

| Signal | What it means | Action |
|--------|--------------|--------|
| Conversion rate < 2% | Screenshot problem | Update App Store screenshots |
| Impressions up, installs flat | Keyword match but listing fails | Review title/subtitle/description |
| Campaign links — riding: 0 installs | Links not deployed or wrong URL | Verify button hrefs on riding pages |
| D7 retention falling | Core flow broken | Check recent releases for regressions |
| Search impressions up, clicks flat | Meta description/title weak | Rewrite page titles for CTR |
| Average position > 20 | Low authority for those queries | Build internal links from riding pages |

---

## Actions from this report

- [ ] [Action item from this month's data]
- [ ] [Action item from this month's data]
- [ ] Review `docs/marketing/newsletter/welcome-sequence.md`; refresh stale
      parliamentary/lobbying facts and send a Mailchimp test if any email copy
      changes.
- [ ] Run `python3 scripts/marketing/check_promotional_text_staleness.py`; if promotional text is older than 30 days or includes stale factual wording, file a Linear ASO refresh task before closing the monthly cycle.

## Carried forward from last month

- [ ] [Item that wasn't completed]
